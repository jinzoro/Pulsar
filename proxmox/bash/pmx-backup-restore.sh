#!/usr/bin/env bash
# =============================================================================
# pmx-backup-restore.sh — Backup and restore operations
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: backup, restore, list, verify, prune, schedule
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Backup and restore operations"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  backup    --vmid=ID --storage=S [--node=NODE] [OPTIONS]
  restore   --vmid=ID --storage=S --backup-id=ID [--node=NODE] [OPTIONS]
  list      [--vmid=ID] --storage=S [--node=NODE]
  verify    --vmid=ID --backup-id=ID [--node=NODE]
  prune     --vmid=ID --storage=S [--node=NODE] [OPTIONS]
  schedule  --vmid=ID --cron=EXPR --storage=S [--node=NODE] [OPTIONS]

BACKUP OPTIONS:
  --vmid=ID             VM/CT ID (required)
  --storage=S           Backup storage (required)
  --node=NODE           Target node
  --mode=MODE           Backup mode: snapshot, suspend, stop (default: snapshot)
  --compress=ALG        Compression: zstd, gz, lzo (default: zstd)
  --retention=N         Retention count

RESTORE OPTIONS:
  --vmid=ID             Target VM/CT ID
  --storage=S           Storage containing backup
  --backup-id=ID        Backup identifier (required)
  --target-node=NODE    Restore to different node
  --target-storage=S    Restore to different storage
  --target-vmid=ID      Restore as different VMID

LIST OPTIONS:
  --vmid=ID             Show backups for specific VM/CT (all if omitted)
  --storage=S           Storage to list backups from (required)

VERIFY OPTIONS:
  --vmid=ID             VM/CT ID
  --backup-id=ID        Backup identifier to verify

PRUNE OPTIONS:
  --vmid=ID             VM/CT ID
  --storage=S           Storage containing backups
  --keep-daily=N        Keep daily backups (default: 7)
  --keep-weekly=N       Keep weekly backups (default: 4)
  --keep-monthly=N      Keep monthly backups (default: 6)

SCHEDULE OPTIONS:
  --vmid=ID             VM/CT ID
  --cron=EXPR           Cron expression (e.g. "0 2 * * *")
  --storage=S           Backup storage
  --mode=MODE           Backup mode (default: snapshot)
  --compress=ALG        Compression (default: zstd)

OPTIONS:
  --dry-run             Show what would be done
  --help, -h            Show this help

EXAMPLES:
  $(basename "$0") backup --vmid=100 --storage=backup-nas --mode=snapshot
  $(basename "$0") list --storage=backup-nas
  $(basename "$0") restore --vmid=100 --storage=backup-nas --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst
  $(basename "$0") prune --vmid=100 --storage=backup-nas --keep-daily=7 --keep-weekly=4
  $(basename "$0") schedule --vmid=100 --cron="0 2 * * *" --storage=backup-nas
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
STORAGE=""
NODE="${PMX_NODE:-}"
MODE="snapshot"
COMPRESS="zstd"
BACKUP_ID=""
TARGET_NODE=""
TARGET_STORAGE=""
TARGET_VMID=""
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
CRON=""
RETENTION=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)           VMID="${1#*=}" ;;
            --storage=*)        STORAGE="${1#*=}" ;;
            --node=*)           NODE="${1#*=}" ;;
            --mode=*)           MODE="${1#*=}" ;;
            --compress=*)       COMPRESS="${1#*=}" ;;
            --backup-id=*)      BACKUP_ID="${1#*=}" ;;
            --target-node=*)    TARGET_NODE="${1#*=}" ;;
            --target-storage=*) TARGET_STORAGE="${1#*=}" ;;
            --target-vmid=*)    TARGET_VMID="${1#*=}" ;;
            --keep-daily=*)     KEEP_DAILY="${1#*=}" ;;
            --keep-weekly=*)    KEEP_WEEKLY="${1#*=}" ;;
            --keep-monthly=*)   KEEP_MONTHLY="${1#*=}" ;;
            --cron=*)           CRON="${1#*=}" ;;
            --retention=*)      RETENTION="${1#*=}" ;;
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
    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_backup() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }

    local payload="{\"storage\":\"${STORAGE}\",\"mode\":\"${MODE}\",\"compress\":\"${COMPRESS}\"}"
    [[ -n "${RETENTION}" ]] && payload=$(echo "${payload}" | jq -c --argjson r "${RETENTION}" '. + {"retain": $r}')

    log_info "Starting backup of VM ${VMID} to ${STORAGE} (mode: ${MODE})..."
    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/backup" -d "${payload}")

    local upid
    upid=$(parse_json "${result}" ".data" 2>/dev/null)
    if [[ -n "${upid}" ]]; then
        log_info "Backup started. UPID: ${upid}"
        log_info "Monitor with: pvesm list ${STORAGE}"
    fi
    echo -e "${GREEN}Backup initiated for VM ${VMID}${NC}"
}

do_restore() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }
    [[ -z "${BACKUP_ID}" ]] && { log_error "--backup-id is required."; exit 1; }

    local restore_node="${TARGET_NODE:-${NODE}}"
    local restore_storage="${TARGET_STORAGE:-${STORAGE}}"
    local restore_vmid="${TARGET_VMID:-${VMID}}"

    local payload="{\"storage\":\"${restore_storage}\",\"vmid\":${restore_vmid},\"archive\":\"${BACKUP_ID}\"}"

    log_info "Restoring backup ${BACKUP_ID} as VM ${restore_vmid} on ${restore_node}..."
    dry_run api_call POST "/nodes/${restore_node}/qemu" -d "${payload}"
    echo -e "${GREEN}Restore complete for VM ${restore_vmid}${NC}"
}

do_list() {
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }

    log_info "Listing backups on ${STORAGE}..."
    local content
    content=$(api_call GET "/nodes/${NODE}/storage/${STORAGE}/content" 2>/dev/null) || {
        log_error "Failed to list storage content."
        exit 1
    }

    echo ""
    printf "${BOLD}%-40s %-10s %-14s %-8s${NC}\n" "BACKUP ID" "VMID" "SIZE" "DATE"
    printf "%-40s %-10s %-14s %-8s\n" \
        "----------------------------------------" "----------" "--------------" "--------"

    parse_json "${content}" ".data[]" | while IFS= read -r item; do
        local vtype volid size ctime vmid_
        vtype=$(echo "${item}" | jq -r '.content // ""')
        volid=$(echo "${item}" | jq -r '.volid // ""')
        size=$(echo "${item}" | jq -r '.size // 0')
        ctime=$(echo "${item}" | jq -r '.ctime // ""')
        vmid_=$(echo "${item}" | jq -r '.vmid // ""')

        [[ "${vtype}" != "backup" ]] && continue
        if [[ -n "${VMID}" && "${vmid_}" != "${VMID}" ]]; then
            continue
        fi

        local size_h
        size_h=$(numfmt --to=iec --suffix=B "${size}" 2>/dev/null || echo "${size}")
        local date_h
        date_h=$(date -d "@${ctime}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "${ctime}")

        printf "%-40s %-10s %-14s %-8s\n" "${volid}" "${vmid_}" "${size_h}" "${date_h}"
    done
}

do_verify() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${BACKUP_ID}" ]] && { log_error "--backup-id is required."; exit 1; }

    log_info "Verifying backup ${BACKUP_ID}..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/backup" \
        -d "{\"verify\":1,\"archive\":\"${BACKUP_ID}\"}"
    echo -e "${GREEN}Verification complete for ${BACKUP_ID}${NC}"
}

do_prune() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }

    log_info "Pruning backups for VM ${VMID} on ${STORAGE}..."
    log_info "Retention: daily=${KEEP_DAILY}, weekly=${KEEP_WEEKLY}, monthly=${KEEP_MONTHLY}"

    local prune_str="keep-daily=${KEEP_DAILY},keep-weekly=${KEEP_WEEKLY},keep-monthly=${KEEP_MONTHLY}"

    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/backup" \
        -d "{\"storage\":\"${STORAGE}\",\"prune\":1,\"prune-schedule\":\"${prune_str}\"}"
    echo -e "${GREEN}Prune scheduled for VM ${VMID}${NC}"
}

do_schedule() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }
    [[ -z "${CRON}" ]] && { log_error "--cron is required."; exit 1; }

    log_info "Setting backup schedule for VM ${VMID}..."
    local payload
    payload=$(jq -n \
        --arg storage "${STORAGE}" \
        --arg mode "${MODE}" \
        --arg compress "${COMPRESS}" \
        --arg schedule "${CRON}" \
        '{"storage": $storage, "mode": $mode, "compress": $compress, "schedule": $schedule}')

    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"
    echo -e "${GREEN}Backup schedule set: ${CRON}${NC}"
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
        backup)   do_backup ;;
        restore)  do_restore ;;
        list)     do_list ;;
        verify)   do_verify ;;
        prune)    do_prune ;;
        schedule) do_schedule ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
