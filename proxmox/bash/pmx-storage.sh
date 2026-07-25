#!/usr/bin/env bash
# =============================================================================
# pmx-storage.sh — Storage management for Proxmox VE
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: add, remove, list, status, resize-disk, move-disk, import-disk
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Storage management for Proxmox VE"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  list         [--node=NODE] [--storage=NAME]
  status       --storage=NAME [--node=NODE]
  add          --name=NAME --type=TYPE [OPTIONS] [--node=NODE]
  remove       --name=NAME [--node=NODE]
  resize-disk  --vmid=ID --disk=DISK --size=SIZE [--node=NODE]
  move-disk    --vmid=ID --disk=DISK --target-storage=S [--node=NODE] [--online]
  import-disk  --vmid=ID --file=PATH [--format=FMT] [--storage=S] [--node=NODE]

ADD OPTIONS:
  --name=NAME           Storage name (required)
  --type=TYPE           Storage type (required):
                        dir, nfs, cifs, iscsi, lvm, lvmthin,
                        zfs, zfspool, cephfs, ceph, glusterfs, pbs
  --options=KEY=VAL     Type-specific options (comma-separated)
                        dir:    path=/mnt/data
                        nfs:    server=10.0.0.1,path=/export
                        cifs:   server=10.0.0.1,share=data,user=admin
                        lvm:    vgname=vgdata
                        lvmthin: vgname=vgdata,thinpool=data
                        zfs:    pool=rpool/data
                        zfspool: pool=rpool/data
                        ceph:   pool=cephfs_data
                        cephfs: cephfs=cephfs
                        pbs:    server=10.0.0.2 datastore=backup
  --node=NODE           Target node (default: auto-detect)

REMOVE OPTIONS:
  --name=NAME           Storage name (required)
  --node=NODE           Target node

RESIZE-DISK OPTIONS:
  --vmid=ID             VM ID
  --disk=DISK           Disk to resize (e.g. scsi0, virtio0)
  --size=SIZE           New size (e.g. +10G, 100G)
  --node=NODE           Target node

MOVE-DISK OPTIONS:
  --vmid=ID             VM ID
  --disk=DISK           Disk to move (e.g. scsi0)
  --target-storage=S    Target storage
  --online              Move disk while VM is running
  --node=NODE           Target node

IMPORT-DISK OPTIONS:
  --vmid=ID             VM ID
  --file=PATH           File path to import (e.g. /var/lib/vz/images/qcow2.img)
  --format=FMT          Format: raw, qcow2, vmdk (default: auto-detect)
  --storage=S           Target storage
  --node=NODE           Target node

OPTIONS:
  --dry-run             Show what would be done
  --help, -h            Show this help

EXAMPLES:
  $(basename "$0") list
  $(basename "$0") add --name=nas --type=nfs --options=server=10.0.0.1,path=/export
  $(basename "$0") resize-disk --vmid=100 --disk=scsi0 --size=+50G
  $(basename "$0") move-disk --vmid=100 --disk=scsi0 --target-storage=nas --online
  $(basename "$0") import-disk --vmid=100 --file=/tmp/disk.qcow2 --storage=local-lvm
  $(basename "$0") remove --name=nas
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NAME=""
STORAGE_TYPE=""
STORAGE=""
OPTIONS=""
NODE="${PMX_NODE:-}"
VMID=""
DISK=""
SIZE=""
TARGET_STORAGE=""
ONLINE=false
FILE=""
FORMAT=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name=*)            NAME="${1#*=}" ;;
            --type=*)            STORAGE_TYPE="${1#*=}" ;;
            --storage=*)         STORAGE="${1#*=}" ;;
            --options=*)         OPTIONS="${1#*=}" ;;
            --node=*)            NODE="${1#*=}" ;;
            --vmid=*)            VMID="${1#*=}" ;;
            --disk=*)            DISK="${1#*=}" ;;
            --size=*)            SIZE="${1#*=}" ;;
            --target-storage=*)  TARGET_STORAGE="${1#*=}" ;;
            --file=*)            FILE="${1#*=}" ;;
            --format=*)          FORMAT="${1#*=}" ;;
            --online)            ONLINE=true; shift; continue ;;
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
# Parse options string into JSON
# ---------------------------------------------------------------------------
options_to_json() {
    local opts="$1"
    local json="{}"
    if [[ -z "${opts}" ]]; then
        echo "{}"
        return
    fi
    IFS=',' read -ra pairs <<< "${opts}"
    for pair in "${pairs[@]}"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        json=$(echo "${json}" | jq -c --arg k "${key}" --arg v "${val}" '. + {($k): $v}')
    done
    echo "${json}"
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_list() {
    log_info "Listing storage on node ${NODE}..."
    local response
    response=$(api_call GET "/nodes/${NODE}/storage")
    echo ""
    printf "${BOLD}%-20s %-14s %-10s %-12s %-12s %-12s${NC}\n" \
        "NAME" "TYPE" "STATUS" "TOTAL" "USED" "AVAILABLE"
    printf "%-20s %-14s %-10s %-12s %-12s %-12s\n" \
        "----" "----" "------" "-----" "----" "---------"

    parse_json "${response}" ".data[]" | while IFS= read -r item; do
        local sname stype sstatus total used avail
        sname=$(echo "${item}" | jq -r '.storage // "unknown"')
        stype=$(echo "${item}" | jq -r '.type // "unknown"')

        [[ -n "${STORAGE}" && "${sname}" != "${STORAGE}" ]] && continue

        local status_resp
        status_resp=$(api_call GET "/nodes/${NODE}/storage/${sname}/status" 2>/dev/null) || continue
        sstatus=$(parse_json "${status_resp}" ".data.status // \"unknown\"" 2>/dev/null) || sstatus="unknown"
        total=$(parse_json "${status_resp}" ".data.total // 0" 2>/dev/null) || total=0
        used=$(parse_json "${status_resp}" ".data.used // 0" 2>/dev/null) || used=0
        avail=$(parse_json "${status_resp}" ".data.avail // 0" 2>/dev/null) || avail=0

        local total_h used_h avail_h
        total_h=$(numfmt --to=iec --suffix=B "${total}" 2>/dev/null || echo "${total}")
        used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
        avail_h=$(numfmt --to=iec --suffix=B "${avail}" 2>/dev/null || echo "${avail}")

        printf "%-20s %-14s ${GREEN}%-10s${NC} %-12s %-12s %-12s\n" \
            "${sname}" "${stype}" "${sstatus}" "${total_h}" "${used_h}" "${avail_h}"
    done
}

do_status() {
    [[ -z "${STORAGE}" ]] && { log_error "--storage is required."; exit 1; }
    log_info "Status of storage '${STORAGE}' on node ${NODE}..."
    local resp
    resp=$(api_call GET "/nodes/${NODE}/storage/${STORAGE}/status")
    local total used avail status
    total=$(parse_json "${resp}" ".data.total // 0")
    used=$(parse_json "${resp}" ".data.used // 0")
    avail=$(parse_json "${resp}" ".data.avail // 0")
    status=$(parse_json "${resp}" ".data.status // unknown")

    local total_h used_h avail_h
    total_h=$(numfmt --to=iec --suffix=B "${total}" 2>/dev/null || echo "${total}")
    used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
    avail_h=$(numfmt --to=iec --suffix=B "${avail}" 2>/dev/null || echo "${avail}")

    local pct=0
    if (( total > 0 )); then
        pct=$(( (used * 100) / total ))
    fi

    echo ""
    printf "${BOLD}Storage:${NC}  %s\n" "${STORAGE}"
    printf "${BOLD}Status:${NC}   %s\n" "${status}"
    printf "${BOLD}Total:${NC}    %s\n" "${total_h}"
    printf "${BOLD}Used:${NC}     %s\n" "${used_h}"
    printf "${BOLD}Avail:${NC}    %s\n" "${avail_h}"
    printf "${BOLD}Usage:${NC}    %d%%\n" "${pct}"
}

do_add() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${STORAGE_TYPE}" ]] && { log_error "--type is required."; exit 1; }

    local opts_json
    opts_json=$(options_to_json "${OPTIONS}")

    local payload
    payload=$(echo "${opts_json}" | jq -c \
        --arg type "${STORAGE_TYPE}" \
        --arg content "images,rootdir,vztmpl,iso,backup" \
        '. + {"type": $type, "content": $content}')

    log_info "Adding storage '${NAME}' (type: ${STORAGE_TYPE}) on node ${NODE}..."
    dry_run api_call POST "/nodes/${NODE}/storage" -d "${payload}"
    log_info "Storage '${NAME}' added successfully."
}

do_remove() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Removing storage '${NAME}' from node ${NODE}..."
    confirm "Remove storage '${NAME}'? Content may become inaccessible." || exit 2
    dry_run api_call DELETE "/nodes/${NODE}/storage/${NAME}"
    log_info "Storage '${NAME}' removed."
}

do_resize_disk() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${DISK}" ]] && { log_error "--disk is required."; exit 1; }
    [[ -z "${SIZE}" ]] && { log_error "--size is required."; exit 1; }

    log_info "Resizing disk ${DISK} on VM ${VMID} to ${SIZE}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/resize" \
        -d "{\"disk\":\"${DISK}\",\"size\":\"${SIZE}\"}"
    log_info "Disk ${DISK} resized."
}

do_move_disk() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${DISK}" ]] && { log_error "--disk is required."; exit 1; }
    [[ -z "${TARGET_STORAGE}" ]] && { log_error "--target-storage is required."; exit 1; }

    local payload="{\"disk\":\"${DISK}\",\"storage\":\"${TARGET_STORAGE}\"}"
    [[ "${ONLINE}" == "true" ]] && payload=$(echo "${payload}" | jq -c '. + {"online": 1}')

    log_info "Moving disk ${DISK} of VM ${VMID} to ${TARGET_STORAGE}..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/migrate_disk" -d "${payload}"
    log_info "Disk moved."
}

do_import_disk() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${FILE}" ]] && { log_error "--file is required."; exit 1; }

    local payload="{\"filename\":\"${FILE}\"}"
    [[ -n "${FORMAT}" ]] && payload=$(echo "${payload}" | jq -c --arg f "${FORMAT}" '. + {"format": $f}')
    [[ -n "${STORAGE}" ]] && payload=$(echo "${payload}" | jq -c --arg s "${STORAGE}" '. + {"storage": $s}')

    log_info "Importing disk into VM ${VMID}..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/import" -d "${payload}"
    log_info "Disk imported."
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
        list)         do_list ;;
        status)       do_status ;;
        add)          do_add ;;
        remove)       do_remove ;;
        resize-disk)  do_resize_disk ;;
        move-disk)    do_move_disk ;;
        import-disk)  do_import_disk ;;
        *)            log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
