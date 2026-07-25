#!/usr/bin/env bash
# =============================================================================
# pmx-ct-lifecycle.sh — LXC container lifecycle management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create, start, stop, shutdown, delete, clone, resize, set-features
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "LXC container lifecycle management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  start        --vmid=ID [--node=NODE]
  stop         --vmid=ID [--node=NODE]
  shutdown     --vmid=ID [--node=NODE] [--timeout=SECS]
  create       --template=TEMPLATE [OPTIONS]
  delete       --vmid=ID [--node=NODE] [--purge]
  clone        --vmid=ID [OPTIONS]
  resize       --vmid=ID --rootfs-size=SIZE [--node=NODE]
  set-features --vmid=ID [OPTIONS] [--node=NODE]

CREATE OPTIONS:
  --template=TEMPLATE      Template storage path (e.g. local:vztmpl/debian-12-standard.tar.zst)
  --storage=NAME           Target storage (default: local-lvm)
  --hostname=NAME          Container hostname
  --unprivileged           Unprivileged container (default)
  --privileged             Privileged container
  --nesting                Enable nesting feature
  --rootfs-size=SIZE       Root filesystem size (default: 8G)
  --cpu=N                  Number of CPUs (default: 1)
  --memory=MB              Memory in MB (default: 512)
  --swap=MB                Swap in MB (default: 0)
  --dns=IP                 DNS server IP
  --searchdomain=DOMAIN    Search domain
  --node=NODE              Target node

CLONE OPTIONS:
  --new-vmid=ID            Target VMID
  --full                   Full clone (default)
  --linked                 Linked clone
  --target-node=NODE       Target node
  --target-storage=S       Target storage
  --name=NAME              New container name

SET-FEATURES OPTIONS:
  --nesting=on|off         Enable/disable nesting
  --keyctl=on|off          Enable/disable keyctl
  --fuse=on|off            Enable/disable FUSE
  --mount=on|off           Enable/disable mount

OPTIONS:
  --dry-run                Show what would be done
  --help, -h               Show this help

EXAMPLES:
  $(basename "$0") create --template=local:vztmpl/debian-12.tar.zst --hostname=web1 --rootfs-size=20G
  $(basename "$0") start --vmid=200
  $(basename "$0") resize --vmid=200 --rootfs-size=+10G
  $(basename "$0") set-features --vmid=200 --nesting=on
  $(basename "$0") clone --vmid=200 --new-vmid=201 --name=web2 --full
  $(basename "$0") delete --vmid=200 --purge
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
NODE="${PMX_NODE:-}"
TEMPLATE=""
STORAGE="local-lvm"
HOSTNAME=""
UNPRIVILEGED=true
PRIVILEGED=false
NESTING=false
ROOTFS_SIZE="8G"
CPU=1
MEMORY=512
SWAP=0
DNS=""
SEARCHDOMAIN=""
NEW_VMID=""
FULL=true
LINKED=false
TARGET_NODE=""
TARGET_STORAGE=""
NAME=""
PURGE=false
TIMEOUT=30
FEAT_NESTING=""
FEAT_KEYCTL=""
FEAT_FUSE=""
FEAT_MOUNT=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)           VMID="${1#*=}" ;;
            --node=*)           NODE="${1#*=}" ;;
            --template=*)       TEMPLATE="${1#*=}" ;;
            --storage=*)        STORAGE="${1#*=}" ;;
            --hostname=*)       HOSTNAME="${1#*=}" ;;
            --rootfs-size=*)    ROOTFS_SIZE="${1#*=}" ;;
            --cpu=*)            CPU="${1#*=}" ;;
            --memory=*)         MEMORY="${1#*=}" ;;
            --swap=*)           SWAP="${1#*=}" ;;
            --dns=*)            DNS="${1#*=}" ;;
            --searchdomain=*)   SEARCHDOMAIN="${1#*=}" ;;
            --new-vmid=*)       NEW_VMID="${1#*=}" ;;
            --target-node=*)    TARGET_NODE="${1#*=}" ;;
            --target-storage=*) TARGET_STORAGE="${1#*=}" ;;
            --name=*)           NAME="${1#*=}" ;;
            --timeout=*)        TIMEOUT="${1#*=}" ;;
            --nesting=*)        FEAT_NESTING="${1#*=}" ;;
            --keyctl=*)         FEAT_KEYCTL="${1#*=}" ;;
            --fuse=*)           FEAT_FUSE="${1#*=}" ;;
            --mount=*)          FEAT_MOUNT="${1#*=}" ;;
            --purge)            PURGE=true; shift; continue ;;
            --full)             FULL=true; LINKED=false; shift; continue ;;
            --linked)           LINKED=true; FULL=false; shift; continue ;;
            --unprivileged)     UNPRIVILEGED=true; PRIVILEGED=false; shift; continue ;;
            --privileged)       PRIVILEGED=false; PRIVILEGED=true; UNPRIVILEGED=false; shift; continue ;;
            --nesting)          NESTING=true; shift; continue ;;
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
            log_error "Could not auto-detect node. Specify --node."
            exit 1
        }
    fi
}

detect_ct_node() {
    local vmid="$1"
    local nodes
    nodes=$(parse_json "$(api_call GET /nodes)" ".data[].node")
    for n in $nodes; do
        local resp
        resp=$(api_call GET "/nodes/${n}/lxc/${vmid}/status/current" 2>/dev/null) || continue
        local st
        st=$(parse_json "${resp}" ".data.status" 2>/dev/null) || continue
        if [[ -n "${st}" ]]; then
            echo "$n"
            return 0
        fi
    done
    return 1
}

print_result() {
    local vmid="$1"
    local operation="$2"
    local status="$3"
    printf "${BOLD}%-8s %-16s %-12s${NC}\n" "CTID" "OPERATION" "STATUS"
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
    local vmid="$1" node="$2"
    log_info "Starting container ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/lxc/${vmid}/status/start"
    print_result "${vmid}" "start" "ok"
}

do_stop() {
    local vmid="$1" node="$2"
    log_info "Stopping container ${vmid} on node ${node}..."
    dry_run api_call POST "/nodes/${node}/lxc/${vmid}/status/stop"
    print_result "${vmid}" "stop" "ok"
}

do_shutdown() {
    local vmid="$1" node="$2" timeout="$3"
    log_info "Shutting down container ${vmid} (timeout: ${timeout}s)..."
    dry_run api_call POST "/nodes/${node}/lxc/${vmid}/status/shutdown" \
        -d "{\"timeout\":${timeout}}"
    print_result "${vmid}" "shutdown" "ok"
}

do_create() {
    [[ -z "${TEMPLATE}" ]] && { log_error "--template is required."; exit 1; }
    [[ -z "${HOSTNAME}" ]] && { log_error "--hostname is required."; exit 1; }

    local auto_vmid="${VMID:-}"
    if [[ -z "${auto_vmid}" ]]; then
        auto_vmid=$(parse_json "$(api_call GET "/cluster/resources" 2>/dev/null)" '[.data[] | select(.type=="lxc") | .vmid] | max // 99' 2>/dev/null) || auto_vmid=99
        auto_vmid=$((auto_vmid + 1))
        log_info "Auto-assigned CTID: ${auto_vmid}"
    fi

    local unpriv=1
    [[ "${PRIVILEGED}" == "true" ]] && unpriv=0

    local features=""
    if [[ "${NESTING}" == "true" ]]; then
        features=',"features":{"nesting":1}'
    fi

    local payload
    payload=$(jq -n \
        --arg template "${TEMPLATE}" \
        --arg hostname "${HOSTNAME}" \
        --arg storage "${STORAGE}" \
        --arg rootfs "${ROOTFS_SIZE}" \
        --argjson cpu "${CPU}" \
        --argjson memory "${MEMORY}" \
        --argjson swap "${SWAP}" \
        --argjson unpriv "${unpriv}" \
        --arg dns "${DNS}" \
        --arg search "${SEARCHDOMAIN}" \
        --argjson vmid "${auto_vmid}" \
        '{
            "vmid": $vmid,
            "ostemplate": $template,
            "hostname": $hostname,
            "storage": $storage,
            "rootfs": $rootfs,
            "cpus": $cpu,
            "memory": $memory,
            "swap": $swap,
            "unprivileged": $unpriv
        } + (if $dns != "" then {"nameserver": $dns} else {} end)
          + (if $search != "" then {"searchdomain": $search} else {} end)
        ')

    log_info "Creating container ${auto_vmid} (${HOSTNAME})..."
    dry_run api_call POST "/nodes/${NODE}/lxc" -d "${payload}"
    print_result "${auto_vmid}" "create" "ok"
}

do_delete() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    log_info "Deleting container ${VMID} on node ${NODE}..."
    confirm "Delete container ${VMID}? This is irreversible." || exit 2
    local endpoint="/nodes/${NODE}/lxc/${VMID}"
    [[ "${PURGE}" == "true" ]] && endpoint="${endpoint}?purge=1"
    dry_run api_call DELETE "${endpoint}"
    print_result "${VMID}" "delete" "ok"
}

do_clone() {
    [[ -z "${VMID}" ]] && { log_error "--vmid (source) is required."; exit 1; }
    local target_node="${TARGET_NODE:-${NODE}}"
    local payload="{}"
    [[ -n "${NEW_VMID}" ]] && payload=$(echo "${payload}" | jq -c --argjson id "${NEW_VMID}" '. + {"newid": $id}')
    [[ -n "${NAME}" ]] && payload=$(echo "${payload}" | jq -c --arg n "${NAME}" '. + {"name": $n}')
    [[ "${LINKED}" == "true" ]] && payload=$(echo "${payload}" | jq -c '. + {"full": 0}') || payload=$(echo "${payload}" | jq -c '. + {"full": 1}')
    [[ -n "${TARGET_STORAGE}" ]] && payload=$(echo "${payload}" | jq -c --arg s "${TARGET_STORAGE}" '. + {"storage": $s}')
    [[ -n "${target_node}" ]] && payload=$(echo "${payload}" | jq -c --arg n "${target_node}" '. + {"target": $n}')

    log_info "Cloning container ${VMID}..."
    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/lxc/${VMID}/clone" -d "${payload}")
    local new_id="${NEW_VMID:-$(parse_json "${result}" ".data" 2>/dev/null)}"
    print_result "${new_id:-?}" "clone" "ok"
}

do_resize() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${ROOTFS_SIZE}" ]] && { log_error "--rootfs-size is required."; exit 1; }
    log_info "Resizing rootfs of container ${VMID} by ${ROOTFS_SIZE}..."
    dry_run api_call PUT "/nodes/${NODE}/lxc/${VMID}/resize" \
        -d "{\"disk\":\"rootfs\",\"size\":\"${ROOTFS_SIZE}\"}"
    print_result "${VMID}" "resize" "ok"
}

do_set_features() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    local features="{"
    local first=true
    for feat_val in "nesting:${FEAT_NESTING}" "keyctl:${FEAT_KEYCTL}" "fuse:${FEAT_FUSE}" "mount:${FEAT_MOUNT}"; do
        local feat="${feat_val%%:*}"
        local val="${feat_val#*:}"
        [[ -z "${val}" ]] && continue
        if [[ "${first}" == "true" ]]; then first=false; else features+=","; fi
        if [[ "${val}" == "on" || "${val}" == "1" ]]; then
            features+="\"${feat}\":1"
        else
            features+="\"${feat}\":0"
        fi
    done
    features+="}"

    if [[ "${features}" == "{}" ]]; then
        log_error "Specify at least one feature (--nesting, --keyctl, --fuse, --mount)."
        exit 1
    fi

    log_info "Setting features for container ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/lxc/${VMID}/config" -d "{\"features\":${features}}"
    print_result "${VMID}" "set-features" "ok"
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
        start)
            [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
            local node="${NODE}"
            [[ -z "${node}" ]] && node=$(detect_ct_node "${VMID}") || true
            do_start "${VMID}" "${node}"
            ;;
        stop)
            [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
            local node="${NODE}"
            [[ -z "${node}" ]] && node=$(detect_ct_node "${VMID}") || true
            do_stop "${VMID}" "${node}"
            ;;
        shutdown)
            [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
            local node="${NODE}"
            [[ -z "${node}" ]] && node=$(detect_ct_node "${VMID}") || true
            do_shutdown "${VMID}" "${node}" "${TIMEOUT}"
            ;;
        create)   do_create ;;
        delete)   do_delete ;;
        clone)    do_clone ;;
        resize)   do_resize ;;
        set-features) do_set_features ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
