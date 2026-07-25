#!/usr/bin/env bash
# =============================================================================
# pmx-firewall.sh — Firewall management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: enable, disable, rules, ipsets, aliases, security-groups
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Firewall management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  enable              --scope=SCOPE [--vmid=ID] [--node=NODE]
  disable             --scope=SCOPE [--vmid=ID] [--node=NODE]
  rules-list          --scope=SCOPE [--vmid=ID] [--node=NODE]
  rules-add           --scope=SCOPE [OPTIONS]
  rules-delete        --scope=SCOPE --pos=POS [--vmid=ID] [--node=NODE]
  rules-move-up       --scope=SCOPE --pos=POS [--vmid=ID] [--node=NODE]
  rules-move-down     --scope=SCOPE --pos=POS [--vmid=ID] [--node=NODE]
  ipsets-list         [--scope=SCOPE] [--node=NODE]
  ipset-create        --name=NAME [--scope=SCOPE] [--node=NODE]
  ipset-delete        --name=NAME [--scope=SCOPE] [--node=NODE]
  ipset-add-cidr      --name=NAME --cidr=CIDR [--node=NODE]
  aliases-list        [--node=NODE]
  alias-create        --name=NAME --cidr=CIDR [--node=NODE]
  alias-delete        --name=NAME [--node=NODE]
  secgroups-list      [--node=NODE]
  secgroup-create     --name=NAME [--node=NODE]
  secgroup-delete     --name=NAME [--node=NODE]
  secgroup-add-rule   --group=NAME [RULE OPTIONS]
  secgroup-del-rule   --group=NAME --pos=POS [--node=NODE]

SCOPE: cluster | node | vm

RULE OPTIONS (for rules-add and secgroup-add-rule):
  --direction=DIR      in | out
  --action=ACTION      accept | drop | reject
  --proto=PROTO        tcp | udp | icmp | ip
  --source=IP          Source IP/CIDR
  --dest=IP            Destination IP/CIDR
  --dport=PORT         Destination port/range
  --sport=PORT         Source port/range
  --comment=TEXT       Rule comment
  --enable             Enable rule (default)
  --disable            Disable rule
  --pos=POS            Rule position (for delete/move)

OPTIONS:
  --dry-run            Show what would be done
  --help, -h           Show this help

EXAMPLES:
  $(basename "$0") enable --scope=cluster
  $(basename "$0") rules-list --scope=vm --vmid=100
  $(basename "$0") rules-add --scope=vm --vmid=100 --direction=in --action=accept --proto=tcp --dport=80
  $(basename "$0") ipset-create --name=trusted --scope=cluster
  $(basename "$0") ipset-add-cidr --name=trusted --cidr=10.0.0.0/8
  $(basename "$0") alias-create --name=webserver --cidr=10.0.0.10/32
  $(basename "$0") secgroup-create --name=web
  $(basename "$0") secgroup-add-rule --group=web --direction=in --action=accept --proto=tcp --dport=80
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
SCOPE=""
VMID=""
NODE="${PMX_NODE:-}"
ENABLE_FLAG=true
DIRECTION=""
ACTION_RULE=""
PROTO=""
SOURCE=""
DEST=""
DPORT=""
SPORT=""
COMMENT=""
POS=""
IPSET_NAME=""
CIDR=""
SEC_GROUP=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope=*)        SCOPE="${1#*=}" ;;
            --vmid=*)         VMID="${1#*=}" ;;
            --node=*)         NODE="${1#*=}" ;;
            --direction=*)    DIRECTION="${1#*=}" ;;
            --action=*)       ACTION_RULE="${1#*=}" ;;
            --proto=*)        PROTO="${1#*=}" ;;
            --source=*)       SOURCE="${1#*=}" ;;
            --dest=*)         DEST="${1#*=}" ;;
            --dport=*)        DPORT="${1#*=}" ;;
            --sport=*)        SPORT="${1#*=}" ;;
            --comment=*)      COMMENT="${1#*=}" ;;
            --pos=*)          POS="${1#*=}" ;;
            --name=*)         IPSET_NAME="${1#*=}" ;;
            --cidr=*)         CIDR="${1#*=}" ;;
            --group=*)        SEC_GROUP="${1#*=}" ;;
            --enable)         ENABLE_FLAG=true; shift; continue ;;
            --disable)        ENABLE_FLAG=false; shift; continue ;;
            --dry-run)        DRY_RUN=true; shift; continue ;;
            --help|-h)        usage ;;
            -*)               log_error "Unknown option: $1"; usage ;;
            *)                ACTION="$1" ;;
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
    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi
}

# ---------------------------------------------------------------------------
# Build endpoint from scope
# ---------------------------------------------------------------------------
fw_endpoint() {
    local scope="${1:-${SCOPE}}"
    case "${scope}" in
        cluster) echo "/cluster/firewall" ;;
        node)    echo "/nodes/${NODE}/firewall" ;;
        vm)      [[ -z "${VMID}" ]] && { log_error "--vmid required for vm scope."; exit 1; }
                 echo "/nodes/${NODE}/qemu/${VMID}/firewall" ;;
        *)       log_error "Invalid scope: ${scope}"; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_enable() {
    local ep
    ep=$(fw_endpoint)
    log_info "Enabling firewall (${SCOPE})..."
    dry_run api_call PUT "${ep}" -d '{"enable":1}'
    echo -e "${GREEN}Firewall enabled.${NC}"
}

do_disable() {
    local ep
    ep=$(fw_endpoint)
    log_info "Disabling firewall (${SCOPE})..."
    dry_run api_call PUT "${ep}" -d '{"enable":0}'
    echo -e "${GREEN}Firewall disabled.${NC}"
}

do_rules_list() {
    local ep
    ep=$(fw_endpoint)
    log_info "Listing firewall rules (${SCOPE})..."
    local resp
    resp=$(api_call GET "${ep}/rules" 2>/dev/null) || {
        log_warn "No rules found."
        return 0
    }

    echo ""
    printf "${BOLD}%-5s %-8s %-8s %-8s %-6s %-14s %-14s %-30s${NC}\n" \
        "POS" "ENABLED" "DIRECTION" "ACTION" "PROTO" "SOURCE" "DEST" "COMMENT"
    printf "%-5s %-8s %-8s %-8s %-6s %-14s %-14s %-30s\n" \
        "---" "-------" "---------" "------" "-----" "------" "----" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local pos ena dir act proto src dst cmt
        pos=$(echo "${item}" | jq -r '.pos // ""')
        ena=$(echo "${item}" | jq -r '.enable // 1')
        dir=$(echo "${item}" | jq -r '.direction // ""')
        act=$(echo "${item}" | jq -r '.action // ""')
        proto=$(echo "${item}" | jq -r '.proto // ""')
        src=$(echo "${item}" | jq -r '.source // ""')
        dst=$(echo "${item}" | jq -r '.dest // ""')
        cmt=$(echo "${item}" | jq -r '.comment // ""')

        local ena_str="yes"
        [[ "${ena}" == "0" ]] && ena_str="no"

        printf "%-5s ${GREEN}%-8s${NC} %-8s %-8s %-6s %-14s %-14s %-30s\n" \
            "${pos}" "${ena_str}" "${dir}" "${act}" "${proto}" "${src}" "${dst}" "${cmt}"
    done
}

do_rules_add() {
    [[ -z "${DIRECTION}" ]] && { log_error "--direction is required."; exit 1; }
    [[ -z "${ACTION_RULE}" ]] && { log_error "--action is required."; exit 1; }

    local ep
    ep=$(fw_endpoint)

    local payload
    payload=$(jq -n \
        --arg dir "${DIRECTION}" \
        --arg act "${ACTION_RULE}" \
        --arg proto "${PROTO}" \
        --arg src "${SOURCE}" \
        --arg dst "${DEST}" \
        --arg dport "${DPORT}" \
        --arg sport "${SPORT}" \
        --arg cmt "${COMMENT}" \
        --argjson enable "$([ "${ENABLE_FLAG}" = true ] && echo 1 || echo 0)" \
        '{\"direction\": $dir, \"action\": $act, \"enable\": $enable}')
    [[ -n "${PROTO}" ]] && payload=$(echo "${payload}" | jq -c --arg p "${PROTO}" '. + {"proto": $p}')
    [[ -n "${SOURCE}" ]] && payload=$(echo "${payload}" | jq -c --arg s "${SOURCE}" '. + {"source": $s}')
    [[ -n "${DEST}" ]] && payload=$(echo "${payload}" | jq -c --arg d "${DEST}" '. + {"dest": $d}')
    [[ -n "${DPORT}" ]] && payload=$(echo "${payload}" | jq -c --arg dp "${DPORT}" '. + {"dport": $dp}')
    [[ -n "${SPORT}" ]] && payload=$(echo "${payload}" | jq -c --arg sp "${SPORT}" '. + {"sport": $sp}')
    [[ -n "${COMMENT}" ]] && payload=$(echo "${payload}" | jq -c --arg c "${COMMENT}" '. + {"comment": $c}')

    log_info "Adding firewall rule (${SCOPE})..."
    dry_run api_call POST "${ep}/rules" -d "${payload}"
    echo -e "${GREEN}Rule added.${NC}"
}

do_rules_delete() {
    [[ -z "${POS}" ]] && { log_error "--pos is required."; exit 1; }
    local ep
    ep=$(fw_endpoint)
    log_info "Deleting rule at position ${POS}..."
    confirm "Delete firewall rule at position ${POS}?" || exit 2
    dry_run api_call DELETE "${ep}/rules/${POS}"
    echo -e "${GREEN}Rule deleted.${NC}"
}

do_rules_move_up() {
    [[ -z "${POS}" ]] && { log_error "--pos is required."; exit 1; }
    local ep
    ep=$(fw_endpoint)
    log_info "Moving rule ${POS} up..."
    dry_run api_call PUT "${ep}/rules/${POS}" -d '{"movewanted":1}'
    echo -e "${GREEN}Rule moved up.${NC}"
}

do_rules_move_down() {
    [[ -z "${POS}" ]] && { log_error "--pos is required."; exit 1; }
    local ep
    ep=$(fw_endpoint)
    log_info "Moving rule ${POS} down..."
    dry_run api_call PUT "${ep}/rules/${POS}" -d '{"movewanted":0}'
    echo -e "${GREEN}Rule moved down.${NC}"
}

do_ipsets_list() {
    log_info "Listing IP sets..."
    local ep="/nodes/${NODE}/firewall"
    local resp
    resp=$(api_call GET "${ep}/ipset" 2>/dev/null) || {
        log_warn "No IP sets found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-40s${NC}\n" "NAME" "COMMENT"
    printf "%-20s %-40s\n" "----" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local iname icmt
        iname=$(echo "${item}" | jq -r '.name // "unknown"')
        icmt=$(echo "${item}" | jq -r '.comment // ""')
        printf "%-20s %-40s\n" "${iname}" "${icmt}"
    done
}

do_ipset_create() {
    [[ -z "${IPSET_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Creating IP set '${IPSET_NAME}'..."
    dry_run api_call POST "/nodes/${NODE}/firewall/ipset" \
        -d "{\"name\":\"${IPSET_NAME}\"}"
    echo -e "${GREEN}IP set '${IPSET_NAME}' created.${NC}"
}

do_ipset_delete() {
    [[ -z "${IPSET_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting IP set '${IPSET_NAME}'..."
    confirm "Delete IP set '${IPSET_NAME}'?" || exit 2
    dry_run api_call DELETE "/nodes/${NODE}/firewall/ipset/${IPSET_NAME}"
    echo -e "${GREEN}IP set '${IPSET_NAME}' deleted.${NC}"
}

do_ipset_add_cidr() {
    [[ -z "${IPSET_NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${CIDR}" ]] && { log_error "--cidr is required."; exit 1; }
    log_info "Adding CIDR ${CIDR} to IP set '${IPSET_NAME}'..."
    dry_run api_call POST "/nodes/${NODE}/firewall/ipset/${IPSET_NAME}/cidr" \
        -d "{\"cidr\":\"${CIDR}\"}"
    echo -e "${GREEN}CIDR added.${NC}"
}

do_aliases_list() {
    log_info "Listing aliases..."
    local resp
    resp=$(api_call GET "/nodes/${NODE}/firewall/aliases" 2>/dev/null) || {
        log_warn "No aliases found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-20s %-40s${NC}\n" "NAME" "CIDR" "COMMENT"
    printf "%-20s %-20s %-40s\n" "----" "----" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local aname acidr acmt
        aname=$(echo "${item}" | jq -r '.name // "unknown"')
        acidr=$(echo "${item}" | jq -r '.cidr // ""')
        acmt=$(echo "${item}" | jq -r '.comment // ""')
        printf "%-20s %-20s %-40s\n" "${aname}" "${acidr}" "${acmt}"
    done
}

do_alias_create() {
    [[ -z "${IPSET_NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${CIDR}" ]] && { log_error "--cidr is required."; exit 1; }
    log_info "Creating alias '${IPSET_NAME}' = ${CIDR}..."
    dry_run api_call POST "/nodes/${NODE}/firewall/aliases" \
        -d "{\"name\":\"${IPSET_NAME}\",\"cidr\":\"${CIDR}\"}"
    echo -e "${GREEN}Alias created.${NC}"
}

do_alias_delete() {
    [[ -z "${IPSET_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting alias '${IPSET_NAME}'..."
    confirm "Delete alias '${IPSET_NAME}'?" || exit 2
    dry_run api_call DELETE "/nodes/${NODE}/firewall/aliases/${IPSET_NAME}"
    echo -e "${GREEN}Alias deleted.${NC}"
}

do_secgroups_list() {
    log_info "Listing security groups..."
    local resp
    resp=$(api_call GET "/cluster/firewall/security_groups" 2>/dev/null) || {
        log_warn "No security groups found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-40s${NC}\n" "GROUP" "COMMENT"
    printf "%-20s %-40s\n" "-----" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local gname gcmt
        gname=$(echo "${item}" | jq -r '.group // "unknown"')
        gcmt=$(echo "${item}" | jq -r '.comment // ""')
        printf "%-20s %-40s\n" "${gname}" "${gcmt}"
    done
}

do_secgroup_create() {
    [[ -z "${SEC_GROUP}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Creating security group '${SEC_GROUP}'..."
    dry_run api_call POST "/cluster/firewall/security_groups" \
        -d "{\"group\":\"${SEC_GROUP}\"}"
    echo -e "${GREEN}Security group '${SEC_GROUP}' created.${NC}"
}

do_secgroup_delete() {
    [[ -z "${SEC_GROUP}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting security group '${SEC_GROUP}'..."
    confirm "Delete security group '${SEC_GROUP}'?" || exit 2
    dry_run api_call DELETE "/cluster/firewall/security_groups/${SEC_GROUP}"
    echo -e "${GREEN}Security group deleted.${NC}"
}

do_secgroup_add_rule() {
    [[ -z "${SEC_GROUP}" ]] && { log_error "--group is required."; exit 1; }
    [[ -z "${DIRECTION}" ]] && { log_error "--direction is required."; exit 1; }
    [[ -z "${ACTION_RULE}" ]] && { log_error "--action is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg dir "${DIRECTION}" \
        --arg act "${ACTION_RULE}" \
        --arg proto "${PROTO}" \
        --arg src "${SOURCE}" \
        --arg dst "${DEST}" \
        --arg dport "${DPORT}" \
        --arg sport "${SPORT}" \
        --arg cmt "${COMMENT}" \
        --argjson enable "$([ "${ENABLE_FLAG}" = true ] && echo 1 || echo 0)" \
        '{\"direction\": $dir, \"action\": $act, \"enable\": $enable}')
    [[ -n "${PROTO}" ]] && payload=$(echo "${payload}" | jq -c --arg p "${PROTO}" '. + {"proto": $p}')
    [[ -n "${SOURCE}" ]] && payload=$(echo "${payload}" | jq -c --arg s "${SOURCE}" '. + {"source": $s}')
    [[ -n "${DEST}" ]] && payload=$(echo "${payload}" | jq -c --arg d "${DEST}" '. + {"dest": $d}')
    [[ -n "${DPORT}" ]] && payload=$(echo "${payload}" | jq -c --arg dp "${DPORT}" '. + {"dport": $dp}')
    [[ -n "${SPORT}" ]] && payload=$(echo "${payload}" | jq -c --arg sp "${SPORT}" '. + {"sport": $sp}')
    [[ -n "${COMMENT}" ]] && payload=$(echo "${payload}" | jq -c --arg c "${COMMENT}" '. + {"comment": $c}')

    log_info "Adding rule to security group '${SEC_GROUP}'..."
    dry_run api_call POST "/cluster/firewall/security_groups/${SEC_GROUP}/rules" -d "${payload}"
    echo -e "${GREEN}Rule added to security group.${NC}"
}

do_secgroup_del_rule() {
    [[ -z "${SEC_GROUP}" ]] && { log_error "--group is required."; exit 1; }
    [[ -z "${POS}" ]] && { log_error "--pos is required."; exit 1; }
    log_info "Deleting rule ${POS} from security group '${SEC_GROUP}'..."
    confirm "Delete rule from security group '${SEC_GROUP}'?" || exit 2
    dry_run api_call DELETE "/cluster/firewall/security_groups/${SEC_GROUP}/rules/${POS}"
    echo -e "${GREEN}Rule deleted.${NC}"
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
        enable)              do_enable ;;
        disable)             do_disable ;;
        rules-list)          do_rules_list ;;
        rules-add)           do_rules_add ;;
        rules-delete)        do_rules_delete ;;
        rules-move-up)       do_rules_move_up ;;
        rules-move-down)     do_rules_move_down ;;
        ipsets-list)         do_ipsets_list ;;
        ipset-create)        do_ipset_create ;;
        ipset-delete)        do_ipset_delete ;;
        ipset-add-cidr)      do_ipset_add_cidr ;;
        aliases-list)        do_aliases_list ;;
        alias-create)        do_alias_create ;;
        alias-delete)        do_alias_delete ;;
        secgroups-list)      do_secgroups_list ;;
        secgroup-create)     do_secgroup_create ;;
        secgroup-delete)     do_secgroup_delete ;;
        secgroup-add-rule)   do_secgroup_add_rule ;;
        secgroup-del-rule)   do_secgroup_del_rule ;;
        *)                   log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
