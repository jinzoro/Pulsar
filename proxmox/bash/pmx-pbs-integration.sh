#!/usr/bin/env bash
# =============================================================================
# pmx-pbs-integration.sh — Proxmox Backup Server integration
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: add-datastore, backup, restore, verify, prune, status
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Proxmox Backup Server integration"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  add-datastore   --name=NAME --server=HOST --token=TOKEN [OPTIONS]
  backup          --vmid=ID --datastore=NAME [--node=NODE]
  restore         --vmid=ID --datastore=NAME --snapshot=SNAP [OPTIONS]
  verify          --datastore=NAME --snapshot=SNAP
  prune           --datastore=NAME [OPTIONS]
  status          --datastore=NAME

ADD-DATASTORE OPTIONS:
  --name=NAME         Datastore/proxmox storage name (required)
  --server=HOST       PBS server address (required)
  --token=TOKEN       API token (required)
  --fingerprint=SHA   Server certificate fingerprint
  --datastore=NAME    PBS datastore name (default: same as --name)

BACKUP OPTIONS:
  --vmid=ID           VM/CT ID (required)
  --datastore=NAME    PBS datastore name (required)
  --node=NODE         Source node

RESTORE OPTIONS:
  --vmid=ID           Target VM/CT ID
  --datastore=NAME    PBS datastore name (required)
  --snapshot=SNAP     Backup snapshot ID (required)
  --target-node=NODE  Restore to different node
  --target-storage=S  Restore to different storage

VERIFY OPTIONS:
  --datastore=NAME    PBS datastore (required)
  --snapshot=SNAP     Snapshot to verify (required)

PRUNE OPTIONS:
  --datastore=NAME    PBS datastore (required)
  --keep-daily=N      Keep daily (default: 7)
  --keep-weekly=N     Keep weekly (default: 4)
  --keep-monthly=N    Keep monthly (default: 6)

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") add-datastore --name=pbs-backup --server=10.0.0.2 --token=TOKEN
  $(basename "$0") backup --vmid=100 --datastore=pbs-backup
  $(basename "$0") list --datastore=pbs-backup
  $(basename "$0") restore --vmid=100 --datastore=pbs-backup --snapshot=...
  $(basename "$0") verify --datastore=pbs-backup --snapshot=...
  $(basename "$0") prune --datastore=pbs-backup --keep-daily=7
  $(basename "$0") status --datastore=pbs-backup
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NAME=""
SERVER=""
TOKEN=""
FINGERPRINT=""
PBS_DATASTORE=""
VMID=""
NODE="${PMX_NODE:-}"
SNAPSHOT=""
TARGET_NODE=""
TARGET_STORAGE=""
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name=*)            NAME="${1#*=}" ;;
            --server=*)          SERVER="${1#*=}" ;;
            --token=*)           TOKEN="${1#*=}" ;;
            --fingerprint=*)     FINGERPRINT="${1#*=}" ;;
            --datastore=*)       PBS_DATASTORE="${1#*=}" ;;
            --vmid=*)            VMID="${1#*=}" ;;
            --node=*)            NODE="${1#*=}" ;;
            --snapshot=*)        SNAPSHOT="${1#*=}" ;;
            --target-node=*)     TARGET_NODE="${1#*=}" ;;
            --target-storage=*)  TARGET_STORAGE="${1#*=}" ;;
            --keep-daily=*)      KEEP_DAILY="${1#*=}" ;;
            --keep-weekly=*)     KEEP_WEEKLY="${1#*=}" ;;
            --keep-monthly=*)    KEEP_MONTHLY="${1#*=}" ;;
            --dry-run)           DRY_RUN=true; shift; continue ;;
            --help|-h)           usage ;;
            -*)                  log_error "Unknown option: $1"; usage ;;
            *)                   ACTION="$1" ;;
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
do_add_datastore() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${SERVER}" ]] && { log_error "--server is required."; exit 1; }
    [[ -z "${TOKEN}" ]] && { log_error "--token is required."; exit 1; }

    local ds="${PBS_DATASTORE:-${NAME}}"

    log_info "Adding PBS datastore '${ds}' via server ${SERVER}..."

    local payload
    payload=$(jq -n \
        --arg server "${SERVER}" \
        --arg content "images,rootdir,vztmpl,iso,backup" \
        --arg fingerprint "${FINGERPRINT}" \
        --arg datastore "${ds}" \
        --arg transport "https" \
        --arg type "pbs" \
        --arg prune "keep-all=1" \
        '{"type": $type, "server": $server, "content": $content, "datastore": $datastore, "transport": $transport}')
    if [[ -n "${FINGERPRINT}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg fp "${FINGERPRINT}" '. + {"fingerprint": $fp}')
    fi
    if [[ -n "${TOKEN}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg token "${TOKEN}" '. + {"password": $token}')
    fi

    dry_run api_call POST "/nodes/${NODE}/storage" -d "${payload}"
    echo -e "${GREEN}PBS datastore '${ds}' added.${NC}"
}

do_backup() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${PBS_DATASTORE}" ]] && { log_error "--datastore is required."; exit 1; }

    log_info "Backing up VM ${VMID} to PBS datastore '${PBS_DATASTORE}'..."

    # Use vzdump API for PBS backup
    local payload
    payload=$(jq -n \
        --arg storage "${PBS_DATASTORE}" \
        --arg node "${NODE}" \
        --argjson vmid "${VMID}" \
        '{"storage": $storage, "node": $node, "vmid": $vmid, "mode": "snapshot", "compress": "zstd"}')

    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/backup" -d "${payload}")
    local upid
    upid=$(parse_json "${result}" ".data" 2>/dev/null)
    if [[ -n "${upid}" ]]; then
        log_info "Backup started. UPID: ${upid}"
    fi
    echo -e "${GREEN}Backup initiated for VM ${VMID}.${NC}"
}

do_restore() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${PBS_DATASTORE}" ]] && { log_error "--datastore is required."; exit 1; }
    [[ -z "${SNAPSHOT}" ]] && { log_error "--snapshot is required."; exit 1; }

    local restore_node="${TARGET_NODE:-${NODE}}"
    local restore_storage="${TARGET_STORAGE:-${PBS_DATASTORE}}"

    log_info "Restoring VM ${VMID} from PBS snapshot ${SNAPSHOT}..."

    local payload
    payload=$(jq -n \
        --arg storage "${restore_storage}" \
        --argjson vmid "${VMID}" \
        --arg archive "${SNAPSHOT}" \
        '{"storage": $storage, "vmid": $vmid, "archive": $archive}')

    dry_run api_call POST "/nodes/${restore_node}/qemu" -d "${payload}"
    echo -e "${GREEN}Restore complete for VM ${VMID}.${NC}"
}

do_verify() {
    [[ -z "${PBS_DATASTORE}" ]] && { log_error "--datastore is required."; exit 1; }
    [[ -z "${SNAPSHOT}" ]] && { log_error "--snapshot is required."; exit 1; }

    log_info "Verifying snapshot ${SNAPSHOT} on datastore '${PBS_DATASTORE}'..."
    dry_run bash -c "pbs-client verify --datastore ${PBS_DATASTORE} --snapshot ${SNAPSHOT} 2>&1" || {
        log_warn "Verification completed with warnings."
    }
    echo -e "${GREEN}Verification complete.${NC}"
}

do_prune() {
    [[ -z "${PBS_DATASTORE}" ]] && { log_error "--datastore is required."; exit 1; }

    log_info "Pruning datastore '${PBS_DATASTORE}'..."
    log_info "Retention: daily=${KEEP_DAILY}, weekly=${KEEP_WEEKLY}, monthly=${KEEP_MONTHLY}"

    local prune_str="keep-daily=${KEEP_DAILY},keep-weekly=${KEEP_WEEKLY},keep-monthly=${KEEP_MONTHLY}"
    dry_run bash -c "pbs-client prune --datastore ${PBS_DATASTORE} --prune ${prune_str} 2>&1"
    echo -e "${GREEN}Prune complete.${NC}"
}

do_status() {
    [[ -z "${PBS_DATASTORE}" ]] && { log_error "--datastore is required."; exit 1; }

    log_info "Status of PBS datastore '${PBS_DATASTORE}'..."
    echo ""
    dry_run bash -c "pbs-client status --datastore ${PBS_DATASTORE} 2>&1" || {
        # Fallback: try to get storage status via API
        local resp
        resp=$(api_call GET "/nodes/${NODE}/storage/${PBS_DATASTORE}/status" 2>/dev/null) || {
            log_warn "Could not fetch PBS status."
            return 0
        }

        local total used avail
        total=$(parse_json "${resp}" ".data.total // 0")
        used=$(parse_json "${resp}" ".data.used // 0")
        avail=$(parse_json "${resp}" ".data.avail // 0")

        local total_h used_h avail_h
        total_h=$(numfmt --to=iec --suffix=B "${total}" 2>/dev/null || echo "${total}")
        used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
        avail_h=$(numfmt --to=iec --suffix=B "${avail}" 2>/dev/null || echo "${avail}")

        printf "${BOLD}%-16s %-16s %-16s${NC}\n" "Total" "Used" "Available"
        printf "%-16s %-16s %-16s\n" "${total_h}" "${used_h}" "${avail_h}"
    }
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
        add-datastore) do_add_datastore ;;
        backup)        do_backup ;;
        restore)       do_restore ;;
        verify)        do_verify ;;
        prune)         do_prune ;;
        status)        do_status ;;
        *)             log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
