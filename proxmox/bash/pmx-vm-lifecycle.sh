#!/usr/bin/env bash
# =============================================================================
# pmx-vm-lifecycle.sh — Full KVM VM lifecycle management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create, start, stop, shutdown, reboot, suspend, resume, delete,
#             clone, rename
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Full KVM VM lifecycle management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  start       --vmid=ID [--node=NODE]
  stop        --vmid=ID [--node=NODE]
  shutdown    --vmid=ID [--node=NODE] [--timeout=SECS]
  reboot      --vmid=ID [--node=NODE]
  suspend     --vmid=ID [--node=NODE]
  resume      --vmid=ID [--node=NODE]
  create      --name=NAME [OPTIONS]
  delete      --vmid=ID [--node=NODE] [--purge]
  clone       --vmid=ID [OPTIONS]
  rename      --vmid=ID --new-name=NAME [--node=NODE]

CREATE OPTIONS:
  --name=NAME          VM name (required for create)
  --cores=N            Number of CPU cores (default: 1)
  --memory=MB          Memory in MB (default: 512)
  --disk=SIZE          Disk size, e.g. 32G (default: 32G)
  --iso=PATH           ISO image path (e.g. local:iso/ubuntu.iso)
  --template=VMID      Clone from template
  --cloud-init=FILE    Cloud-Init userconfig file
  --bios=TYPE          BIOS type: seabios|ovmf (default: seabios)
  --machine=TYPE       Machine type: q35|i440fx (default: q35)
  --scsihw=TYPE        SCSI controller (default: virtio-scsi-single)
  --net=SPEC           Network spec (default: virtio,bridge=vmbr0)
  --storage=NAME       Target storage (default: local-lvm)
  --vmid=ID            Specific VMID (auto-assigned if omitted)

CLONE OPTIONS:
  --new-vmid=ID        Target VMID for clone
  --full               Full clone (default)
  --linked             Linked clone
  --target-node=NODE   Target node
  --target-storage=S   Target storage
  --name=NAME          New VM name

BATCH MODE (applies to start/stop/shutdown/reboot):
  --pool=NAME          Operate on all VMs in pool
  --tag=TAG            Operate on all VMs with tag

OPTIONS:
  --dry-run            Show what would be done without executing
  --help, -h           Show this help message

EXAMPLES:
  $(basename "$0") start --vmid=100
  $(basename "$0") create --name=webserver --cores=4 --memory=4096 --disk=100G --iso=local:iso/ubuntu.iso
  $(basename "$0") clone --vmid=100 --new-vmid=200 --name=webserver-clone --full
  $(basename "$0") delete --vmid=100 --purge --dry-run
  $(basename "$0") shutdown --vmid=100 --timeout=60
  $(basename "$0") start --pool=production
  $(basename "$0") stop --tag=dev
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
NEW_VMID=""
NODE="${PMX_NODE:-}"
NAME=""
NEW_NAME=""
CORES=1
MEMORY=512
DISK="32G"
ISO=""
TEMPLATE=""
CLOUD_INIT=""
BIOS="seabios"
MACHINE="q35"
SCSIHW="virtio-scsi-single"
NET="virtio,bridge=vmbr0"
STORAGE="local-lvm"
FULL=true
LINKED=false
TARGET_NODE=""
TARGET_STORAGE=""
PURGE=false
TIMEOUT=30
POOL=""
TAG=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)     VMID="${1#*=}" ;;
            --new-vmid=*) NEW_VMID="${1#*=}" ;;
            --node=*)     NODE="${1#*=}" ;;
            --name=*)     NAME="${1#*=}" ;;
            --new-name=*) NEW_NAME="${1#*=}" ;;
            --cores=*)    CORES="${1#*=}" ;;
            --memory=*)   MEMORY="${1#*=}" ;;
            --disk=*)     DISK="${1#*=}" ;;
            --iso=*)      ISO="${1#*=}" ;;
            --template=*) TEMPLATE="${1#*=}" ;;
            --cloud-init=*) CLOUD_INIT="${1#*=}" ;;
            --bios=*)     BIOS="${1#*=}" ;;
            --machine=*)  MACHINE="${1#*=}" ;;
            --scsihw=*)   SCSIHW="${1#*=}" ;;
            --net=*)      NET="${1#*=}" ;;
            --storage=*)  STORAGE="${1#*=}" ;;
            --target-node=*) TARGET_NODE="${1#*=}" ;;
            --target-storage=*) TARGET_STORAGE="${1#*=}" ;;
            --pool=*)     POOL="${1#*=}" ;;
            --tag=*)      TAG="${1#*=}" ;;
            --timeout=*)  TIMEOUT="${1#*=}" ;;
            --purge)      PURGE=true; shift; continue ;;
            --full)       FULL=true; LINKED=false; shift; continue ;;
            --linked)     LINKED=false; FULL=false; LINKED=true; shift; continue ;;
            --dry-run)    DRY_RUN=true; shift; continue ;;
            --help|-h)    usage ;;
            -*)           log_error "Unknown option: $1"; usage ;;
            *)            ACTION="$1" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
validate() {
    check_prereqs curl jq
    require_api_token
    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node. Specify --node."
            exit 1
        }
    fi
}

# ---------------------------------------------------------------------------
# Auto-detect node for a VM
# ---------------------------------------------------------------------------
detect_vm_node() {
    local vmid="$1"
    local nodes
    nodes=$(parse_json "$(api_call GET /nodes)" ".data[].node")
    for n in $nodes; do
        local status
        status=$(api_call GET "/nodes/${n}/qemu/${vmid}/status/current" 2>/dev/null) || continue
        local st
        st=$(parse_json "${status}" ".data.status" 2>/dev/null) || continue
        if [[ -n "${st}" ]]; then
            echo "$n"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Get list of VMIDs by pool or tag
# ---------------------------------------------------------------------------
get_target_vmids() {
    local vmids=()
    if [[ -n "${POOL}" ]]; then
        local pool_data
        pool_data=$(api_call GET "/pools/${POOL}")
        while IFS= read -r vmid; do
            [[ -n "${vmid}" ]] && vmids+=("${vmid}")
        done < <(parse_json "${pool_data}" ".data.members[].vmid")
    elif [[ -n "${TAG}" ]]; then
        local nodes
        nodes=$(parse_json "$(api_call GET /nodes)" ".data[].node")
        for n in $nodes; do
            while IFS= read -r vmid; do
                [[ -n "${vmid}" ]] && vmids+=("${vmid}")
            done < <(parse_json "$(api_call GET "/nodes/${n}/qemu" 2>/dev/null)" ".data[].vmid" 2>/dev/null)
        done
    fi
    echo "${vmids[*]:-}"
}

# ---------------------------------------------------------------------------
# Print result table
# ---------------------------------------------------------------------------
print_result() {
    local vmid="$1"
    local operation="$2"
    local status="$3"
    printf "${BOLD}%-8s %-16s %-12s${NC}\n" "VMID" "OPERATION" "STATUS"
    printf "%-8s %-16s " "${vmid}" "${operation}"
    if [[ "${status}" == "ok" ]]; then
        echo -e "${GREEN}${status}${NC}"
    else
        echo -e "${RED}${status}${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_start() {
    local vmid="$1"
    local node="$2"
    log_info "Starting VM ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/start"
    print_result "${vmid}" "start" "ok"
}

do_stop() {
    local vmid="$1"
    local node="$2"
    log_info "Stopping VM ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/stop"
    print_result "${vmid}" "stop" "ok"
}

do_shutdown() {
    local vmid="$1"
    local node="$2"
    local timeout="$3"
    log_info "Graceful shutdown VM ${vmid} (timeout: ${timeout}s)..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/shutdown" \
        -d "{\"timeout\":${timeout}}"
    print_result "${vmid}" "shutdown" "ok"
}

do_reboot() {
    local vmid="$1"
    local node="$2"
    log_info "Rebooting VM ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/reboot"
    print_result "${vmid}" "reboot" "ok"
}

do_suspend() {
    local vmid="$1"
    local node="$2"
    log_info "Suspending VM ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/suspend"
    print_result "${vmid}" "suspend" "ok"
}

do_resume() {
    local vmid="$1"
    local node="$2"
    log_info "Resuming VM ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/qemu/${vmid}/status/resume"
    print_result "${vmid}" "resume" "ok"
}

do_create() {
    if [[ -z "${NAME}" ]]; then
        log_error "--name is required for create."
        exit 1
    fi

    local auto_vmid="${VMID:-}"
    if [[ -z "${auto_vmid}" ]]; then
        auto_vmid=$(parse_json "$(api_call GET "/cluster/resources" 2>/dev/null)" '[.data[] | select(.type=="qemu") | .vmid] | max // 999' 2>/dev/null) || auto_vmid=999
        auto_vmid=$((auto_vmid + 1))
        log_info "Auto-assigned VMID: ${auto_vmid}"
    fi

    local payload="{\"vmid\":${auto_vmid},\"name\":\"${NAME}\",\"cores\":${CORES},\"memory\":${MEMORY},\"scsihw\":\"${SCSIHW}\",\"bios\":\"${BIOS}\",\"machine\":\"${MACHINE}\"}"

    if [[ -n "${ISO}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg iso "${ISO}" '. + {"ide2": $iso, "boot": "order=ide2"}')
    fi

    if [[ -n "${TEMPLATE}" ]]; then
        log_info "Cloning template ${TEMPLATE} as new VM ${auto_vmid}..."
        do_clone "${TEMPLATE}" "${auto_vmid}" "${NAME}"
        return
    fi

    log_info "Creating VM ${auto_vmid} (${NAME})..."
    dry_run api_call POST "/nodes/${NODE}/qemu" -d "${payload}"

    if [[ -n "${CLOUD_INIT}" ]]; then
        log_info "Applying Cloud-Init from ${CLOUD_INIT}..."
        dry_run api_call POST "/nodes/${NODE}/qemu/${auto_vmid}/config" \
            -d "@${CLOUD_INIT}"
    fi

    print_result "${auto_vmid}" "create" "ok"
}

do_delete() {
    local vmid="$1"
    local node="$2"
    local purge_flag="$3"

    log_info "Deleting VM ${vmid} on node ${node}..."
    if [[ "${purge_flag}" == "true" ]]; then
        log_warn "Purge mode: all disks will be removed."
    fi

    confirm "Delete VM ${vmid}? This is irreversible." || exit 2

    local endpoint="/nodes/${node}/qemu/${vmid}"
    [[ "${purge_flag}" == "true" ]] && endpoint="${endpoint}?purge=1"
    dry_run api_call DELETE "${endpoint}"
    print_result "${vmid}" "delete" "ok"
}

do_clone() {
    local source_vmid="$1"
    local target_vmid="${2:-}"
    local clone_name="${3:-${NAME:-}}"

    local target_node="${TARGET_NODE:-${NODE}}"
    local target_storage="${TARGET_STORAGE:-}"

    local payload="{}"
    if [[ -n "${target_vmid}" ]]; then
        payload=$(echo "${payload}" | jq -c --argjson id "${target_vmid}" '. + {"newid": $id}')
    fi
    if [[ -n "${clone_name}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg n "${clone_name}" '. + {"name": $n}')
    fi
    if [[ "${LINKED}" == "true" ]]; then
        payload=$(echo "${payload}" | jq -c '. + {"full": 0}')
    else
        payload=$(echo "${payload}" | jq -c '. + {"full": 1}')
    fi
    if [[ -n "${target_storage}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg s "${target_storage}" '. + {"storage": $s}')
    fi
    if [[ -n "${target_node}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg n "${target_node}" '. + {"target": $n}')
    fi

    log_info "Cloning VM ${source_vmid}..."
    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/qemu/${source_vmid}/clone" -d "${payload}")

    local new_id="${target_vmid:-$(parse_json "${result}" ".data" 2>/dev/null)}"
    print_result "${new_id:-?}" "clone" "ok"
}

do_rename() {
    local vmid="$1"
    local new_name="$2"
    local node="$3"

    log_info "Renaming VM ${vmid} to '${new_name}'..."
    dry_run api_call PUT "/nodes/${node}/qemu/${vmid}/config" \
        -d "{\"name\":\"${new_name}\"}"
    print_result "${vmid}" "rename" "ok"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    setup_logging
    validate

    if [[ -z "${ACTION}" ]]; then
        log_error "No operation specified."
        usage
    fi

    case "${ACTION}" in
        start|stop|shutdown|reboot|suspend|resume)
            local targets=()
            if [[ -n "${POOL}" || -n "${TAG}" ]]; then
                read -ra targets <<< "$(get_target_vmids)"
            elif [[ -n "${VMID}" ]]; then
                targets=("${VMID}")
            else
                log_error "--vmid is required (or use --pool/--tag)."
                exit 1
            fi

            local failures=0
            for vmid in "${targets[@]}"; do
                local node="${NODE}"
                if [[ -z "${node}" ]]; then
                    node=$(detect_vm_node "${vmid}") || {
                        log_error "Cannot detect node for VM ${vmid}."
                        failures=$((failures + 1))
                        continue
                    }
                fi
                case "${ACTION}" in
                    start)    do_start "${vmid}" "${node}" ;;
                    stop)     do_stop "${vmid}" "${node}" ;;
                    shutdown) do_shutdown "${vmid}" "${node}" "${TIMEOUT}" ;;
                    reboot)   do_reboot "${vmid}" "${node}" ;;
                    suspend)  do_suspend "${vmid}" "${node}" ;;
                    resume)   do_resume "${vmid}" "${node}" ;;
                esac || failures=$((failures + 1))
            done
            if (( failures > 0 )); then
                log_warn "${failures} operation(s) failed."
                exit 3
            fi
            ;;
        create)
            do_create
            ;;
        delete)
            [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
            do_delete "${VMID}" "${NODE}" "${PURGE}"
            ;;
        clone)
            [[ -z "${VMID}" ]] && { log_error "--vmid (source) is required."; exit 1; }
            do_clone "${VMID}" "${NEW_VMID}" "${NAME}"
            ;;
        rename)
            [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
            [[ -z "${NEW_NAME}" ]] && { log_error "--new-name is required."; exit 1; }
            do_rename "${VMID}" "${NEW_NAME}" "${NODE}"
            ;;
        *)
            log_error "Unknown operation: ${ACTION}"
            usage
            ;;
    esac
}

main "$@"
