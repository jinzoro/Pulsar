#!/usr/bin/env bash
# =============================================================================
# pmx-snapshot.sh — Snapshot management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: create, list, rollback, delete, schedule
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Snapshot management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  create      --vmid=ID --name=NAME [--description=TEXT] [--ram] [--node=NODE]
  list        --vmid=ID [--node=NODE]
  rollback    --vmid=ID --snap-name=NAME [--node=NODE]
  delete      --vmid=ID --snap-name=NAME [--node=NODE]
  schedule    --vmid=ID --cron=EXPR [--retention=N] [--node=NODE]

CREATE OPTIONS:
  --vmid=ID             VM ID (required)
  --name=NAME           Snapshot name (required)
  --description=TEXT    Description
  --ram                 Include memory state
  --node=NODE           Target node

ROLLBACK OPTIONS:
  --vmid=ID             VM ID (required)
  --snap-name=NAME      Snapshot name (required)

DELETE OPTIONS:
  --vmid=ID             VM ID (required)
  --snap-name=NAME      Snapshot name (required)

SCHEDULE OPTIONS:
  --vmid=ID             VM ID (required)
  --cron=EXPR           Cron expression (e.g. "0 */6 * * *")
  --retention=N         Keep last N snapshots (default: 5)

OPTIONS:
  --dry-run             Show what would be done
  --help, -h            Show this help

EXAMPLES:
  $(basename "$0") create --vmid=100 --name=before-update --description="Pre-update snapshot" --ram
  $(basename "$0") list --vmid=100
  $(basename "$0") rollback --vmid=100 --snap-name=before-update
  $(basename "$0") delete --vmid=100 --snap-name=old-snapshot
  $(basename "$0") schedule --vmid=100 --cron="0 2 * * *" --retention=7
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
SNAP_NAME=""
DESCRIPTION=""
INCLUDE_RAM=false
NODE="${PMX_NODE:-}"
CRON=""
RETENTION=5

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)         VMID="${1#*=}" ;;
            --name=*)         SNAP_NAME="${1#*=}" ;;
            --snap-name=*)    SNAP_NAME="${1#*=}" ;;
            --description=*)  DESCRIPTION="${1#*=}" ;;
            --node=*)         NODE="${1#*=}" ;;
            --cron=*)         CRON="${1#*=}" ;;
            --retention=*)    RETENTION="${1#*=}" ;;
            --ram)            INCLUDE_RAM=true; shift; continue ;;
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
# Operations
# ---------------------------------------------------------------------------
do_create() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${SNAP_NAME}" ]] && { log_error "--name is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg name "${SNAP_NAME}" \
        --arg desc "${DESCRIPTION}" \
        --argjson ram "$([ "${INCLUDE_RAM}" = true ] && echo 1 || echo 0)" \
        '{"snapname": $name, "ram": $ram}')
    [[ -n "${DESCRIPTION}" ]] && payload=$(echo "${payload}" | jq -c --arg d "${DESCRIPTION}" '. + {"description": $d}')

    log_info "Creating snapshot '${SNAP_NAME}' for VM ${VMID}..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/snapshot" -d "${payload}"
    echo -e "${GREEN}Snapshot '${SNAP_NAME}' created.${NC}"
}

do_list() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    log_info "Listing snapshots for VM ${VMID}..."
    local resp
    resp=$(api_call GET "/nodes/${NODE}/qemu/${VMID}/snapshot" 2>/dev/null) || {
        log_warn "No snapshots found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-30s %-20s %-10s${NC}\n" "NAME" "DESCRIPTION" "CREATED" "CURRENT"
    printf "%-20s %-30s %-20s %-10s\n" "----" "-----------" "-------" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local sname sdesc screat scurrent
        sname=$(echo "${item}" | jq -r '.name // "unknown"')
        sdesc=$(echo "${item}" | jq -r '.description // ""')
        screat=$(echo "${item}" | jq -r '.snaptime // ""')
        scurrent=$(echo "${item}" | jq -r '.current // 0')

        local date_h=""
        if [[ -n "${screat}" && "${screat}" != "null" ]]; then
            date_h=$(date -d "@${screat}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "${screat}")
        fi

        local current_str="no"
        [[ "${scurrent}" == "1" || "${scurrent}" == "true" ]] && current_str="${GREEN}yes${NC}"

        printf "%-20s %-30s %-20s %-10s\n" "${sname}" "${sdesc}" "${date_h}" "${current_str}"
    done
}

do_rollback() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${SNAP_NAME}" ]] && { log_error "--snap-name is required."; exit 1; }

    log_info "Rolling back VM ${VMID} to snapshot '${SNAP_NAME}'..."
    confirm "Rollback VM ${VMID} to snapshot '${SNAP_NAME}'? The VM will be restarted." || exit 2
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/snapshot/${SNAP_NAME}/rollback"
    echo -e "${GREEN}Rollback complete. VM ${VMID} is now at snapshot '${SNAP_NAME}'.${NC}"
}

do_delete() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${SNAP_NAME}" ]] && { log_error "--snap-name is required."; exit 1; }

    log_info "Deleting snapshot '${SNAP_NAME}' for VM ${VMID}..."
    confirm "Delete snapshot '${SNAP_NAME}'? This cannot be undone." || exit 2
    dry_run api_call DELETE "/nodes/${NODE}/qemu/${VMID}/snapshot/${SNAP_NAME}"
    echo -e "${GREEN}Snapshot '${SNAP_NAME}' deleted.${NC}"
}

do_schedule() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${CRON}" ]] && { log_error "--cron is required."; exit 1; }

    log_info "Setting snapshot schedule for VM ${VMID}..."

    local snap_tag="snapshot-schedule"
    local description="Auto-snapshot: cron=${CRON}, retention=${RETENTION}"

    local payload
    payload=$(jq -n \
        --arg cron "${CRON}" \
        --arg desc "${description}" \
        --argjson retention "${RETENTION}" \
        '{"snapshotschedule": $cron, "snapshot_retention": $retention}')

    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"
    echo -e "${GREEN}Snapshot schedule set: ${CRON} (keep last ${RETENTION})${NC}"
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
        create)   do_create ;;
        list)     do_list ;;
        rollback) do_rollback ;;
        delete)   do_delete ;;
        schedule) do_schedule ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
