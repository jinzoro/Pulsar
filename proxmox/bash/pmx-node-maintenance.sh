#!/usr/bin/env bash
# =============================================================================
# pmx-node-maintenance.sh — Node maintenance operations
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: enter, exit, update, reboot, shutdown, health
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Node maintenance operations"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  enter       --node=NODE           Enter maintenance mode
  exit        --node=NODE           Exit maintenance mode
  update      [--node=NODE] [OPTIONS]
  reboot      --node=NODE [--timeout=SECS] [--force]
  shutdown    --node=NODE [--timeout=SECS]
  health      [--node=NODE]

ENTER OPTIONS:
  --node=NODE         Node to enter maintenance mode (required)

EXIT OPTIONS:
  --node=NODE         Node to exit maintenance mode (required)

UPDATE OPTIONS:
  --node=NODE         Node to update (default: local)
  --reboot            Reboot after update
  --security-only     Only apply security updates

REBOOT OPTIONS:
  --node=NODE         Node to reboot (required)
  --timeout=SECS      Wait timeout (default: 120)
  --force             Force reboot without graceful shutdown

SHUTDOWN OPTIONS:
  --node=NODE         Node to shutdown (required)
  --timeout=SECS      Graceful timeout (default: 180)

HEALTH OPTIONS:
  --node=NODE         Node to check (default: local)

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") enter --node=pve1
  $(basename "$0") exit --node=pve1
  $(basename "$0") update --node=pve1 --reboot
  $(basename "$0") reboot --node=pve1 --timeout=120
  $(basename "$0") health --node=pve1
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NODE="${PMX_NODE:-}"
TIMEOUT=120
FORCE=false
REBOOT_AFTER=false
SECURITY_ONLY=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node=*)         NODE="${1#*=}" ;;
            --timeout=*)      TIMEOUT="${1#*=}" ;;
            --security-only)  SECURITY_ONLY=true; shift; continue ;;
            --reboot)         REBOOT_AFTER=true; shift; continue ;;
            --force)          FORCE=true; shift; continue ;;
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
do_enter() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }

    log_info "Entering maintenance mode on node ${NODE}..."
    confirm "Enter maintenance mode on ${NODE}? VMs will be migrated." || exit 2

    # Migrate running VMs
    log_info "Checking for running VMs..."
    local vm_resp
    vm_resp=$(api_call GET "/nodes/${NODE}/qemu" 2>/dev/null) || true

    local vm_count
    vm_count=$(parse_json "${vm_resp}" ".data | length" 2>/dev/null) || vm_count=0

    if (( vm_count > 0 )); then
        log_info "Found ${vm_count} VM(s). Migrating..."
        local target
        target=$(parse_json "$(api_call GET /nodes)" ".data[] | select(.node!=\"${NODE}\" and .status==\"online\") | .node | head -1" 2>/dev/null)

        if [[ -n "${target}" ]]; then
            while IFS= read -r item; do
                local vid vstatus
                vid=$(echo "${item}" | jq -r '.vmid // ""')
                vstatus=$(echo "${item}" | jq -r '.status // "stopped"')
                [[ -z "${vid}" ]] && continue
                if [[ "${vstatus}" == "running" ]]; then
                    log_info "Migrating VM ${vid} to ${target}..."
                    dry_run api_call POST "/nodes/${NODE}/qemu/${vid}/migrate" \
                        -d "{\"target\":\"${target}\",\"online\":1}" 2>/dev/null || {
                        log_warn "Failed to migrate VM ${vid}."
                    }
                fi
            done < <(parse_json "${vm_resp}" ".data[]")
        else
            log_warn "No target node available for migration."
        fi
    fi

    # Also check containers
    local ct_resp
    ct_resp=$(api_call GET "/nodes/${NODE}/lxc" 2>/dev/null) || true
    while IFS= read -r item; do
        local vid vstatus
        vid=$(echo "${item}" | jq -r '.vmid // ""')
        vstatus=$(echo "${item}" | jq -r '.status // "stopped"')
        [[ -z "${vid}" ]] && continue
        if [[ "${vstatus}" == "running" ]]; then
            log_info "Stopping container ${vid}..."
            dry_run api_call POST "/nodes/${NODE}/lxc/${vid}/status/stop" 2>/dev/null || true
        fi
    done < <(parse_json "${ct_resp}" ".data[]" 2>/dev/null)

    log_info "Node ${NODE} is now in maintenance mode."
    echo -e "${GREEN}Maintenance mode enabled.${NC}"
}

do_exit() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    log_info "Exiting maintenance mode on node ${NODE}..."

    # Re-enable HA resources
    log_info "Restoring HA resources..."
    local ha_resp
    ha_resp=$(api_call GET "/cluster/ha/resources" 2>/dev/null) || true
    while IFS= read -r item; do
        local sid
        sid=$(echo "${item}" | jq -r '.sid // ""')
        [[ -z "${sid}" ]] && continue
        log_info "Enabling HA resource ${sid}..."
        dry_run api_call PUT "/cluster/ha/resources/${sid}/config" \
            -d '{"state":"started"}' 2>/dev/null || true
    done < <(parse_json "${ha_resp}" ".data[]" 2>/dev/null)

    echo -e "${GREEN}Maintenance mode exited. HA restored.${NC}"
}

do_update() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }

    log_info "Updating packages on node ${NODE}..."

    local apt_cmd="apt update && apt dist-upgrade -y"
    [[ "${SECURITY_ONLY}" == "true" ]] && apt_cmd="apt update && apt upgrade -y -o Dir::Etc::SourceList=/etc/apt/sources.list.d/security.list"

    dry_run bash -c "ssh ${NODE} '${apt_cmd}'" 2>/dev/null || dry_run bash -c "${apt_cmd}"

    if [[ "${REBOOT_AFTER}" == "true" ]]; then
        log_info "Rebooting after update..."
        do_reboot_internal "${NODE}" "${TIMEOUT}"
    fi

    echo -e "${GREEN}Update complete.${NC}"
}

do_reboot_internal() {
    local node="$1"
    local timeout="$2"

    log_info "Rebooting node ${node} (timeout: ${timeout}s)..."

    if [[ "${FORCE}" == "true" ]]; then
        dry_run api_call POST "/nodes/${node}/status" -d '{"command":"reboot"}'
    else
        # Graceful: try to stop VMs first
        log_info "Attempting graceful shutdown first..."
        dry_run api_call POST "/nodes/${node}/status" -d "{\"command\":\"reboot\",\"timeout\":${timeout}}"
    fi
}

do_reboot() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    confirm "Reboot node ${NODE}?" || exit 2
    do_reboot_internal "${NODE}" "${TIMEOUT}"
    echo -e "${GREEN}Reboot initiated for node ${NODE}.${NC}"
}

do_shutdown() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    confirm "Shutdown node ${NODE}?" || exit 2
    log_info "Shutting down node ${NODE} (timeout: ${TIMEOUT}s)..."
    dry_run api_call POST "/nodes/${NODE}/status" -d "{\"command\":\"shutdown\",\"timeout\":${TIMEOUT}}"
    echo -e "${GREEN}Shutdown initiated for node ${NODE}.${NC}"
}

do_health() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }
    log_info "Health check for node ${NODE}..."

    local resp
    resp=$(api_call GET "/nodes/${NODE}/status")
    echo ""

    # Basic stats
    local cpu mem_total mem_used mem_pct uptime_
    cpu=$(parse_json "${resp}" ".data.cpu // 0")
    mem_total=$(parse_json "${resp}" ".data.maxmem // 0")
    mem_used=$(parse_json "${resp}" ".data.mem // 0")
    uptime_=$(parse_json "${resp}" ".data.uptime // 0")

    local cpu_pct
    cpu_pct=$(echo "${cpu}" | awk '{printf "%.1f%%", $1*100}')
    local mem_pct_val=0
    if (( mem_total > 0 )); then
        mem_pct_val=$(( (mem_used * 100) / mem_total ))
    fi
    local mem_total_h mem_used_h
    mem_total_h=$(numfmt --to=iec --suffix=B "${mem_total}" 2>/dev/null || echo "${mem_total}")
    mem_used_h=$(numfmt --to=iec --suffix=B "${mem_used}" 2>/dev/null || echo "${mem_used}")

    local uptime_h
    uptime_h=$(printf '%dd %dh %dm' $(( uptime_/86400 )) $(( (uptime_%86400)/3600 )) $(( (uptime_%3600)/60 )))

    printf "${BOLD}Node:${NC}         %s\n" "${NODE}"
    printf "${BOLD}CPU Usage:${NC}    %s\n" "${cpu_pct}"
    printf "${BOLD}Memory:${NC}       %s / %s (%d%%)\n" "${mem_used_h}" "${mem_total_h}" "${mem_pct_val}"
    printf "${BOLD}Uptime:${NC}       %s\n" "${uptime_h}"

    # Disk usage
    echo ""
    printf "${BOLD}%-20s %-10s %-10s %-10s %-8s${NC}\n" "DEVICE" "SIZE" "USED" "AVAIL" "USE%"
    printf "%-20s %-10s %-10s %-10s %-8s\n" "------" "----" "----" "-----" "----"
    local disks_resp
    disks_resp=$(api_call GET "/nodes/${NODE}/disks/list" 2>/dev/null) || true
    parse_json "${disks_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local dev size used avail use_pct
        dev=$(echo "${item}" | jq -r '.dev // ""')
        size=$(echo "${item}" | jq -r '.size // 0')
        used=$(echo "${item}" | jq -r '.used // 0')
        avail=$(echo "${item}" | jq -r '.avail // 0')
        use_pct=$(echo "${item}" | jq -r '.percent // 0')

        local size_h used_h avail_h
        size_h=$(numfmt --to=iec --suffix=B "${size}" 2>/dev/null || echo "${size}")
        used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
        avail_h=$(numfmt --to=iec --suffix=B "${avail}" 2>/dev/null || echo "${avail}")

        local pct_color="${GREEN}"
        (( use_pct > 80 )) && pct_color="${YELLOW}"
        (( use_pct > 90 )) && pct_color="${RED}"

        printf "%-20s %-10s %-10s %-10s ${pct_color}%-8s${NC}\n" \
            "${dev}" "${size_h}" "${used_h}" "${avail_h}" "${use_pct}%"
    done

    # Temperature
    echo ""
    log_info "Checking temperatures..."
    local temp_resp
    temp_resp=$(api_call GET "/nodes/${NODE}/hardware/temperature" 2>/dev/null) || true
    parse_json "${temp_resp}" ".data[] | select(.name != null)" 2>/dev/null | while IFS= read -r item; do
        local tname tcurrent twarn tcrit
        tname=$(echo "${item}" | jq -r '.name // "unknown"')
        tcurrent=$(echo "${item}" | jq -r '.current // 0')
        twarn=$(echo "${item}" | jq -r '.warning // 0')
        tcrit=$(echo "${item}" | jq -r '.critical // 0')

        local temp_color="${GREEN}"
        (( tcurrent >= twarn )) && temp_color="${YELLOW}"
        (( tcurrent >= tcrit )) && temp_color="${RED}"

        printf "${BOLD}%-20s${NC} ${temp_color}%-6s${NC} (warn: %s, crit: %s)\n" \
            "${tname}" "${tcurrent}°C" "${twarn}°C" "${tcrit}°C"
    done
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
        enter)    do_enter ;;
        exit)     do_exit ;;
        update)   do_update ;;
        reboot)   do_reboot ;;
        shutdown) do_shutdown ;;
        health)   do_health ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
