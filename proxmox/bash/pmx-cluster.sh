#!/usr/bin/env bash
# =============================================================================
# pmx-cluster.sh — Cluster management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: status, create, join, remove, nodes, quorum
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Cluster management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  status              Show cluster status
  create              --cluster-name=NAME --node=NODE
  join                --node=NODE --existing-host=HOST --existing-token=TOKEN
  remove              --node=NODE
  nodes               List all cluster nodes
  quorum              Show quorum information

CREATE OPTIONS:
  --cluster-name=NAME   Cluster name (required)
  --node=NODE           Local node name (required)

JOIN OPTIONS:
  --node=NODE           Local node to join from
  --existing-host=HOST  Existing cluster node address
  --existing-token=TOKEN  Api token for authentication
  --ring0=IP            Ring 0 address
  --ring1=IP            Ring 1 address

REMOVE OPTIONS:
  --node=NODE           Node to remove from cluster

OPTIONS:
  --dry-run             Show what would be done
  --help, -h            Show this help

EXAMPLES:
  $(basename "$0") status
  $(basename "$0") create --cluster-name=mycluster --node=pve1
  $(basename "$0") join --node=pve2 --existing-host=10.0.0.1 --existing-token=TOKEN
  $(basename "$0") nodes
  $(basename "$0") quorum
  $(basename "$0") remove --node=pve3
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
CLUSTER_NAME=""
NODE="${PMX_NODE:-}"
EXISTING_HOST=""
EXISTING_TOKEN=""
RING0=""
RING1=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster-name=*)   CLUSTER_NAME="${1#*=}" ;;
            --node=*)           NODE="${1#*=}" ;;
            --existing-host=*)  EXISTING_HOST="${1#*=}" ;;
            --existing-token=*) EXISTING_TOKEN="${1#*=}" ;;
            --ring0=*)          RING0="${1#*=}" ;;
            --ring1=*)          RING1="${1#*=}" ;;
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
    log_info "Fetching cluster status..."
    local resp
    resp=$(api_call GET "/cluster/status")
    echo ""
    printf "${BOLD}Cluster Information${NC}\n"
    printf "%-20s %-30s\n" "Property" "Value"
    printf "%-20s %-30s\n" "--------" "-----"

    parse_json "${resp}" ".data[] | select(.type==\"cluster\")" 2>/dev/null | while IFS= read -r item; do
        local cname cversion nodes_ quorum_
        cname=$(echo "${item}" | jq -r '.name // "unknown"')
        cversion=$(echo "${item}" | jq -r '.version // "unknown"')
        nodes_=$(echo "${item}" | jq -r '.nodes // 0')
        quorum_=$(echo "${item}" | jq -r '.quorate // "unknown"')
        printf "%-20s ${GREEN}%-30s${NC}\n" "Name" "${cname}"
        printf "%-20s %-30s\n" "Version" "${cversion}"
        printf "%-20s %-30s\n" "Nodes" "${nodes_}"
        printf "%-20s %-30s\n" "Quorate" "${quorum_}"
    done
}

do_create() {
    [[ -z "${CLUSTER_NAME}" ]] && { log_error "--cluster-name is required."; exit 1; }
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }

    log_info "Creating cluster '${CLUSTER_NAME}' on node ${NODE}..."
    confirm "Create new cluster '${CLUSTER_NAME}'?" || exit 2
    dry_run bash -c "pvecm create ${CLUSTER_NAME} 2>&1"
    echo -e "${GREEN}Cluster '${CLUSTER_NAME}' created.${NC}"
}

do_join() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    [[ -z "${EXISTING_HOST}" ]] && { log_error "--existing-host is required."; exit 1; }
    [[ -z "${EXISTING_TOKEN}" ]] && { log_error "--existing-token is required."; exit 1; }

    log_info "Joining node ${NODE} to cluster via ${EXISTING_HOST}..."
    confirm "Join cluster at ${EXISTING_HOST}?" || exit 2

    local join_cmd="pvecm add ${EXISTING_HOST} --token ${EXISTING_TOKEN}"
    [[ -n "${RING0}" ]] && join_cmd+=" --ring0_addr ${RING0}"
    [[ -n "${RING1}" ]] && join_cmd+=" --ring1_addr ${RING1}"

    dry_run bash -c "${join_cmd} 2>&1"
    echo -e "${GREEN}Node ${NODE} joined cluster.${NC}"
}

do_remove() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    log_info "Removing node ${NODE} from cluster..."
    confirm "Remove node ${NODE} from cluster? This cannot be undone." || exit 2
    dry_run bash -c "pvecm delnode ${NODE} 2>&1"
    echo -e "${GREEN}Node ${NODE} removed from cluster.${NC}"
}

do_nodes() {
    log_info "Listing cluster nodes..."
    local resp
    resp=$(api_call GET "/cluster/resources" 2>/dev/null) || {
        log_error "Not in a cluster or API error."
        exit 1
    }

    echo ""
    printf "${BOLD}%-12s %-12s %-16s %-10s %-12s %-10s${NC}\n" \
        "NODE" "STATUS" "ADDRESS" "UPTIME" "CPU" "MEMORY"
    printf "%-12s %-12s %-16s %-10s %-12s %-10s\n" \
        "----" "------" "-------" "------" "---" "------"

    local nodes_resp
    nodes_resp=$(api_call GET "/nodes" 2>/dev/null) || exit 1

    parse_json "${nodes_resp}" ".data[]" | while IFS= read -r item; do
        local nname nstatus nip nuptime ncpu nmem
        nname=$(echo "${item}" | jq -r '.node // "unknown"')
        nstatus=$(echo "${item}" | jq -r '.status // "unknown"')
        nip=$(echo "${item}" | jq -r '.level // ""')
        nuptime=$(echo "${item}" | jq -r '.uptime // 0')
        ncpu=$(echo "${item}" | jq -r '.cpu // 0')
        nmem=$(echo "${item}" | jq -r '.maxmem // 0')

        local uptime_h
        uptime_h=$(printf '%dd %dh %dm' $(( nuptime/86400 )) $(( (nuptime%86400)/3600 )) $(( (nuptime%3600)/60 )) 2>/dev/null || echo "${nuptime}s")
        local cpu_pct
        cpu_pct=$(echo "${ncpu}" | awk '{printf "%.1f%%", $1*100}')
        local mem_h
        mem_h=$(numfmt --to=iec --suffix=B "${nmem}" 2>/dev/null || echo "${nmem}")

        local status_color="${GREEN}"
        [[ "${nstatus}" != "online" ]] && status_color="${RED}"

        printf "%-12s ${status_color}%-12s${NC} %-16s %-10s %-12s %-10s\n" \
            "${nname}" "${nstatus}" "${nip}" "${uptime_h}" "${cpu_pct}" "${mem_h}"
    done
}

do_quorum() {
    log_info "Fetching quorum information..."
    echo ""
    dry_run bash -c "pvecm status 2>&1"
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
        status) do_status ;;
        create) do_create ;;
        join)   do_join ;;
        remove) do_remove ;;
        nodes)  do_nodes ;;
        quorum) do_quorum ;;
        *)      log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
