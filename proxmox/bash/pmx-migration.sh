#!/usr/bin/env bash
# =============================================================================
# pmx-migration.sh — Migration operations
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: migrate, status, batch-migrate, evacuate
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Migration operations"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  migrate        --vmid=ID --target-node=NODE [OPTIONS]
  status         --vmid=ID
  batch-migrate  --source-node=NODE --target-node=NODE [OPTIONS]
  evacuate       --node=NODE

MIGRATE OPTIONS:
  --vmid=ID             VM ID (required)
  --target-node=NODE    Target node (required)
  --online              Online migration (default if VM is running)
  --offline             Offline migration
  --with-local-disks    Also migrate local disks
  --bandwidth-limit=Mbps  Bandwidth limit in Mbps
  --max-downtime=MS     Maximum downtime in ms for online migration

BATCH-MIGRATE OPTIONS:
  --source-node=NODE    Source node (required)
  --target-node=NODE    Target node (required)
  --vmids=LIST          Comma-separated VM IDs
  --all                 Migrate all VMs from source node

EVACUATE OPTIONS:
  --node=NODE           Node to evacuate (required)

OPTIONS:
  --dry-run             Show what would be done
  --help, -h            Show this help

EXAMPLES:
  $(basename "$0") migrate --vmid=100 --target-node=pve2 --online
  $(basename "$0") status --vmid=100
  $(basename "$0") batch-migrate --source-node=pve1 --target-node=pve2 --vmids=100,101,102
  $(basename "$0") batch-migrate --source-node=pve1 --target-node=pve2 --all
  $(basename "$0") evacuate --node=pve1
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
TARGET_NODE=""
SOURCE_NODE=""
ONLINE=true
OFFLINE=false
WITH_LOCAL_DISKS=false
BANDWIDTH_LIMIT=""
MAX_DOWNTIME=""
VMIDS=""
MIGRATE_ALL=false
NODE="${PMX_NODE:-}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)              VMID="${1#*=}" ;;
            --target-node=*)       TARGET_NODE="${1#*=}" ;;
            --source-node=*)       SOURCE_NODE="${1#*=}" ;;
            --bandwidth-limit=*)   BANDWIDTH_LIMIT="${1#*=}" ;;
            --max-downtime=*)      MAX_DOWNTIME="${1#*=}" ;;
            --vmids=*)             VMIDS="${1#*=}" ;;
            --node=*)              NODE="${1#*=}" ;;
            --online)              ONLINE=true; OFFLINE=false; shift; continue ;;
            --offline)             OFFLINE=true; ONLINE=false; shift; continue ;;
            --with-local-disks)    WITH_LOCAL_DISKS=true; shift; continue ;;
            --all)                 MIGRATE_ALL=true; shift; continue ;;
            --dry-run)             DRY_RUN=true; shift; continue ;;
            --help|-h)             usage ;;
            -*)                    log_error "Unknown option: $1"; usage ;;
            *)                     ACTION="$1" ;;
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
# Pre-checks
# ---------------------------------------------------------------------------
pre_check_migration() {
    local vmid="$1"
    local src="$2"
    local dst="$3"

    log_info "Running pre-migration checks for VM ${vmid}..."

    # Check VM exists on source
    local vm_resp
    vm_resp=$(api_call GET "/nodes/${src}/qemu/${vmid}/status/current" 2>/dev/null) || {
        log_error "VM ${vmid} not found on node ${src}."
        return 1
    }

    # Check target node exists
    local nodes_resp
    nodes_resp=$(api_call GET "/nodes" 2>/dev/null) || return 1
    local node_found
    node_found=$(parse_json "${nodes_resp}" "[.data[] | select(.node==\"${dst}\")] | length")
    if [[ "${node_found}" == "0" ]]; then
        log_error "Target node ${dst} not found."
        return 1
    fi

    # Check target node status
    local dst_status
    dst_status=$(api_call GET "/nodes/${dst}/status" 2>/dev/null) || return 1
    local dst_online
    dst_online=$(parse_json "${dst_status}" ".data.status")
    if [[ "${dst_online}" != "online" ]]; then
        log_error "Target node ${dst} is not online."
        return 1
    fi

    log_info "Pre-checks passed."
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_migrate() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${TARGET_NODE}" ]] && { log_error "--target-node is required."; exit 1; }

    pre_check_migration "${VMID}" "${NODE}" "${TARGET_NODE}"

    local payload
    payload=$(jq -n \
        --arg target "${TARGET_NODE}" \
        --argjson online "$([ "${ONLINE}" = true ] && echo 1 || echo 0)" \
        '{"target": $target, "online": $online}')
    [[ "${WITH_LOCAL_DISKS}" == "true" ]] && payload=$(echo "${payload}" | jq -c '. + {"local": 1}')
    [[ -n "${BANDWIDTH_LIMIT}" ]] && payload=$(echo "${payload}" | jq -c --argjson bw "${BANDWIDTH_LIMIT}" '. + {"bwlimit": $bw}')
    [[ -n "${MAX_DOWNTIME}" ]] && payload=$(echo "${payload}" | jq -c --argjson dt "${MAX_DOWNTIME}" '. + {"max downtime": $dt}')

    log_info "Migrating VM ${VMID} from ${NODE} to ${TARGET_NODE}..."
    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/migrate" -d "${payload}")

    local upid
    upid=$(parse_json "${result}" ".data" 2>/dev/null)
    if [[ -n "${upid}" ]]; then
        log_info "Migration started. UPID: ${upid}"
    fi
    echo -e "${GREEN}Migration initiated for VM ${VMID}.${NC}"
}

do_status() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    log_info "Checking migration status for VM ${VMID}..."
    local resp
    resp=$(api_call GET "/nodes/${NODE}/qemu/${VMID}/status/current" 2>/dev/null) || {
        log_error "Could not get VM status."
        return 1
    }

    local status
    status=$(parse_json "${resp}" ".data.status")

    echo ""
    printf "${BOLD}VM ${VMID} Status:${NC} %s\n" "${status}"

    if [[ "${status}" == "migrating" ]]; then
        log_info "VM is currently being migrated."
    fi
}

do_batch_migrate() {
    [[ -z "${SOURCE_NODE}" ]] && { log_error "--source-node is required."; exit 1; }
    [[ -z "${TARGET_NODE}" ]] && { log_error "--target-node is required."; exit 1; }

    local vmid_list=()
    if [[ "${MIGRATE_ALL}" == "true" ]]; then
        log_info "Fetching all VMs from node ${SOURCE_NODE}..."
        local resp
        resp=$(api_call GET "/nodes/${SOURCE_NODE}/qemu" 2>/dev/null) || exit 1
        while IFS= read -r vid; do
            [[ -n "${vid}" ]] && vmid_list+=("${vid}")
        done < <(parse_json "${resp}" ".data[].vmid")
    elif [[ -n "${VMIDS}" ]]; then
        IFS=',' read -ra vmid_list <<< "${VMIDS}"
    else
        log_error "Specify --vmids or --all."
        exit 1
    fi

    if (( ${#vmid_list[@]} == 0 )); then
        log_info "No VMs to migrate."
        return 0
    fi

    log_info "Batch migrating ${#vmid_list[@]} VM(s) from ${SOURCE_NODE} to ${TARGET_NODE}..."

    local failures=0
    local successes=0
    for vid in "${vmid_list[@]}"; do
        log_info "Migrating VM ${vid}..."
        local payload
        payload=$(jq -n --arg target "${TARGET_NODE}" --argjson online 1 '{"target": $target, "online": $online}')
        if dry_run api_call POST "/nodes/${SOURCE_NODE}/qemu/${vid}/migrate" -d "${payload}"; then
            successes=$((successes + 1))
            echo -e "${GREEN}VM ${vid}: migration initiated${NC}"
        else
            failures=$((failures + 1))
            echo -e "${RED}VM ${vid}: migration failed${NC}"
        fi
    done

    echo ""
    log_info "Batch migration complete: ${successes} succeeded, ${failures} failed."
    if (( failures > 0 )); then
        exit 3
    fi
}

do_evacuate() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }

    log_info "Evacuating all VMs from node ${NODE}..."
    confirm "Evacuate all VMs from node ${NODE}? This will migrate every VM off the node." || exit 2

    # Find a target node
    local target
    target=$(parse_json "$(api_call GET /nodes)" ".data[] | select(.node!=\"${NODE}\" and .status==\"online\") | .node | head -1" 2>/dev/null)
    if [[ -z "${target}" ]]; then
        log_error "No other online node found for evacuation target."
        exit 1
    fi

    log_info "Using ${target} as evacuation target."

    local resp
    resp=$(api_call GET "/nodes/${NODE}/qemu" 2>/dev/null) || exit 1

    local failures=0
    local successes=0
    while IFS= read -r item; do
        local vid vstatus
        vid=$(echo "${item}" | jq -r '.vmid // ""')
        vstatus=$(echo "${item}" | jq -r '.status // "unknown"')
        [[ -z "${vid}" ]] && continue

        log_info "Evacuating VM ${vid} (status: ${vstatus})..."
        local payload
        payload=$(jq -n --arg t "${target}" --argjson online 1 '{"target": $t, "online": $online}')
        if dry_run api_call POST "/nodes/${NODE}/qemu/${vid}/migrate" -d "${payload}"; then
            successes=$((successes + 1))
        else
            failures=$((failures + 1))
            log_warn "Failed to evacuate VM ${vid}."
        fi
    done < <(parse_json "${resp}" ".data[]")

    echo ""
    log_info "Evacuation complete: ${successes} migrated, ${failures} failed."
    if (( failures > 0 )); then
        exit 3
    fi
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
        migrate)        do_migrate ;;
        status)         do_status ;;
        batch-migrate)  do_batch_migrate ;;
        evacuate)       do_evacuate ;;
        *)              log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
