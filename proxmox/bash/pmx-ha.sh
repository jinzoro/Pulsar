#!/usr/bin/env bash
# =============================================================================
# pmx-ha.sh — HA (High Availability) management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: groups, resources, status, failover-test
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "HA (High Availability) management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  status              Show HA manager status for all resources
  groups              List HA groups
  group-create        --group=NAME [--nodes=NODE1:N2,...] [OPTIONS]
  group-delete        --group=NAME
  group-modify        --group=NAME [OPTIONS]
  resources           List HA resources
  resource-add        --vmid=ID [--group=NAME] [OPTIONS]
  resource-remove     --vmid=ID
  resource-state      --vmid=ID --state=STATE
  failover-test       --vmid=ID [--node=NODE]

GROUP OPTIONS:
  --group=NAME        Group name
  --nodes=LIST        Comma-separated node list with optional priority (e.g. pve1:2,pve2:1)
  --max-restart=N     Max restart attempts (default: 3)
  --max-relocate=N    Max relocate attempts (default: 1)

RESOURCE OPTIONS:
  --vmid=ID           VM/CT ID
  --group=NAME        HA group name
  --state=STATE       Resource state: started, stopped, disabled, ignored
  --max-restart=N     Max restart (default: 3)
  --max-relocate=N    Max relocate (default: 1)
  --priority=N        Resource priority (default: 0)

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") status
  $(basename "$0") groups
  $(basename "$0") group-create --group=prod --nodes=pve1:2,pve2:1 --max-restart=3
  $(basename "$0") resources
  $(basename "$0") resource-add --vmid=100 --group=prod --state=started
  $(basename "$0") resource-state --vmid=100 --state=stopped
  $(basename "$0") failover-test --vmid=100 --node=pve1
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
GROUP=""
NODES=""
MAX_RESTART=3
MAX_RELOCATE=1
VMID=""
STATE=""
PRIORITY=0
NODE="${PMX_NODE:-}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --group=*)          GROUP="${1#*=}" ;;
            --nodes=*)          NODES="${1#*=}" ;;
            --max-restart=*)    MAX_RESTART="${1#*=}" ;;
            --max-relocate=*)   MAX_RELOCATE="${1#*=}" ;;
            --vmid=*)           VMID="${1#*=}" ;;
            --state=*)          STATE="${1#*=}" ;;
            --priority=*)       PRIORITY="${1#*=}" ;;
            --node=*)           NODE="${1#*=}" ;;
            --dry-run)          DRY_RUN=true; shift; continue ;;
            --help|-h)          usage ;;
            -*)                 log_error "Unknown option: $1"; usage ;;
            *)                  ACTION="$1" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
validate() {
    check_prereqs curl jq
    require_api_token
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_status() {
    log_info "Fetching HA manager status..."
    local resp
    resp=$(api_call GET "/cluster/ha/status" 2>/dev/null) || {
        resp=$(api_call GET "/cluster/ha/resources" 2>/dev/null) || {
            log_warn "Could not fetch HA status. Is HA configured?"
            return 0
        }
    }

    echo ""
    printf "${BOLD}%-8s %-16s %-12s %-10s %-20s${NC}\n" \
        "VMID" "TYPE" "STATUS" "GROUP" "NODE"
    printf "%-8s %-16s %-12s %-10s %-20s\n" \
        "----" "----" "------" "-----" "----"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local sid stype sstatus sgroup snode
        sid=$(echo "${item}" | jq -r '.sid // .vmid // "unknown"')
        stype=$(echo "${item}" | jq -r '.type // "qemu"')
        sstatus=$(echo "${item}" | jq -r '.status // "unknown"')
        sgroup=$(echo "${item}" | jq -r '.group // "-"')
        snode=$(echo "${item}" | jq -r '.node // "-"')

        local status_color="${GREEN}"
        [[ "${sstatus}" != "started" && "${sstatus}" != "active" ]] && status_color="${YELLOW}"

        printf "%-8s %-16s ${status_color}%-12s${NC} %-10s %-20s\n" \
            "${sid}" "${stype}" "${sstatus}" "${sgroup}" "${snode}"
    done
}

do_groups() {
    log_info "Listing HA groups..."
    local resp
    resp=$(api_call GET "/cluster/ha/groups" 2>/dev/null) || {
        log_warn "No HA groups found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-40s %-12s %-12s${NC}\n" "GROUP" "NODES" "MAX-RESTART" "MAX-RELOCATE"
    printf "%-20s %-40s %-12s %-12s\n" "-----" "-----" "-----------" "------------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local gname gnodes grestart grelocate
        gname=$(echo "${item}" | jq -r '.group // "unknown"')
        gnodes=$(echo "${item}" | jq -r '.nodes // ""')
        grestart=$(echo "${item}" | jq -r '.max_restart // 3')
        grelocate=$(echo "${item}" | jq -r '.max_relocate // 1')

        if [[ "${gnodes}" == "{"* ]]; then
            gnodes=$(echo "${item}" | jq -r '.nodes | to_entries | map("\(.key):\(.value)") | join(", ")')
        fi

        printf "%-20s %-40s %-12s %-12s\n" "${gname}" "${gnodes}" "${grestart}" "${glocate}"
    done
}

do_group_create() {
    [[ -z "${GROUP}" ]] && { log_error "--group is required."; exit 1; }
    [[ -z "${NODES}" ]] && { log_error "--nodes is required."; exit 1; }

    local nodes_json="{}"
    IFS=',' read -ra parts <<< "${NODES}"
    for part in "${parts[@]}"; do
        local nname="${part%%:*}"
        local nprio="${part#*:}"
        [[ "${nprio}" == "${nname}" ]] && nprio=1
        nodes_json=$(echo "${nodes_json}" | jq -c --arg n "${nname}" --argjson p "${nprio}" '. + {($n): $p}')
    done

    local payload
    payload=$(jq -n \
        --arg group "${GROUP}" \
        --argjson nodes "${nodes_json}" \
        --argjson restart "${MAX_RESTART}" \
        --argjson relocate "${MAX_RELOCATE}" \
        '{"group": $group, "nodes": $nodes, "max_restart": $restart, "max_relocate": $relocate}')

    log_info "Creating HA group '${GROUP}'..."
    dry_run api_call POST "/cluster/ha/groups" -d "${payload}"
    echo -e "${GREEN}HA group '${GROUP}' created.${NC}"
}

do_group_delete() {
    [[ -z "${GROUP}" ]] && { log_error "--group is required."; exit 1; }
    log_info "Deleting HA group '${GROUP}'..."
    confirm "Delete HA group '${GROUP}'?" || exit 2
    dry_run api_call DELETE "/cluster/ha/groups/${GROUP}"
    echo -e "${GREEN}HA group '${GROUP}' deleted.${NC}"
}

do_group_modify() {
    [[ -z "${GROUP}" ]] && { log_error "--group is required."; exit 1; }

    local payload="{}"
    if [[ -n "${NODES}" ]]; then
        local nodes_json="{}"
        IFS=',' read -ra parts <<< "${NODES}"
        for part in "${parts[@]}"; do
            local nname="${part%%:*}"
            local nprio="${part#*:}"
            [[ "${nprio}" == "${nname}" ]] && nprio=1
            nodes_json=$(echo "${nodes_json}" | jq -c --arg n "${nname}" --argjson p "${nprio}" '. + {($n): $p}')
        done
        payload=$(echo "${payload}" | jq -c --argjson nodes "${nodes_json}" '. + {"nodes": $nodes}')
    fi
    payload=$(echo "${payload}" | jq -c --argjson r "${MAX_RESTART}" '. + {"max_restart": $r}')
    payload=$(echo "${payload}" | jq -c --argjson rl "${MAX_RELOCATE}" '. + {"max_relocate": $rl}')

    log_info "Modifying HA group '${GROUP}'..."
    dry_run api_call PUT "/cluster/ha/groups/${GROUP}" -d "${payload}"
    echo -e "${GREEN}HA group '${GROUP}' modified.${NC}"
}

do_resources() {
    log_info "Listing HA resources..."
    local resp
    resp=$(api_call GET "/cluster/ha/resources" 2>/dev/null) || {
        log_warn "No HA resources found."
        return 0
    }

    echo ""
    printf "${BOLD}%-8s %-12s %-12s %-10s %-8s %-8s${NC}\n" \
        "VMID" "TYPE" "STATUS" "GROUP" "RESTART" "RELOCATE"
    printf "%-8s %-12s %-12s %-10s %-8s %-8s\n" \
        "----" "----" "------" "-----" "-------" "--------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local sid stype sstatus sgroup srestart srelocate
        sid=$(echo "${item}" | jq -r '.sid // "unknown"')
        stype=$(echo "${item}" | jq -r '.type // "qemu"')
        sstatus=$(echo "${item}" | jq -r '.state // "unknown"')
        sgroup=$(echo "${item}" | jq -r '.group // "-"')
        srestart=$(echo "${item}" | jq -r '.max_restart // 3')
        srelocate=$(echo "${item}" | jq -r '.max_relocate // 1')

        local status_color="${GREEN}"
        [[ "${sstatus}" != "started" && "${sstatus}" != "active" ]] && status_color="${YELLOW}"

        printf "%-8s %-12s ${status_color}%-12s${NC} %-10s %-8s %-8s\n" \
            "${sid}" "${stype}" "${sstatus}" "${sgroup}" "${srestart}" "${srelocate}"
    done
}

do_resource_add() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg vmid "${VMID}" \
        --arg group "${GROUP}" \
        --argjson restart "${MAX_RESTART}" \
        --argjson relocate "${MAX_RELOCATE}" \
        --argjson priority "${PRIORITY}" \
        --arg state "${STATE:-started}" \
        '{"sid": $vmid, "type": "qemu", "state": $state, "max_restart": $restart, "max_relocate": $relocate, "priority": $priority}')
    if [[ -n "${GROUP}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg g "${GROUP}" '. + {"group": $g}')
    fi

    log_info "Adding VM ${VMID} to HA resources..."
    dry_run api_call POST "/cluster/ha/resources" -d "${payload}"
    echo -e "${GREEN}VM ${VMID} added to HA.${NC}"
}

do_resource_remove() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    log_info "Removing VM ${VMID} from HA..."
    confirm "Remove VM ${VMID} from HA?" || exit 2
    dry_run api_call DELETE "/cluster/ha/resources/${VMID}"
    echo -e "${GREEN}VM ${VMID} removed from HA.${NC}"
}

do_resource_state() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${STATE}" ]] && { log_error "--state is required (started/stopped/disabled/ignored)."; exit 1; }

    log_info "Setting VM ${VMID} HA state to '${STATE}'..."
    dry_run api_call PUT "/cluster/ha/resources/${VMID}/config" \
        -d "{\"state\":\"${STATE}\"}"
    echo -e "${GREEN}VM ${VMID} state set to '${STATE}'.${NC}"
}

do_failover_test() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    local test_node="${NODE:-}"
    [[ -z "${test_node}" ]] && { log_error "--node is required for failover test."; exit 1; }

    log_info "Failover test: stopping HA resource for VM ${VMID} on ${test_node}..."
    confirm "Simulate failover for VM ${VMID} by stopping on ${test_node}?" || exit 2

    dry_run api_call POST "/nodes/${test_node}/qemu/${VMID}/status/stop" 2>/dev/null || true
    log_info "VM ${VMID} stopped. HA manager should relocate it to another node."
    log_info "Monitor with: $(basename "$0") status"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    setup_logging
    validate

    [[ -z "${ACTION}" ]] && { log_error "No operation specified."; usage; }

    case "${ACTION}" in
        status)          do_status ;;
        groups)          do_groups ;;
        group-create)    do_group_create ;;
        group-delete)    do_group_delete ;;
        group-modify)    do_group_modify ;;
        resources)       do_resources ;;
        resource-add)    do_resource_add ;;
        resource-remove) do_resource_remove ;;
        resource-state)  do_resource_state ;;
        failover-test)   do_failover_test ;;
        *)               log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
