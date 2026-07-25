#!/usr/bin/env bash
# =============================================================================
# kvm-health-check.sh - Health monitoring for KVM hosts and VMs
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: domain, host, storage, network, report
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/bash/lib/common.sh
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
CONNECT_URI="qemu:///system"
ACTION=""
DOMAIN_NAME=""
ALL_DOMAINS=""
JSON_OUTPUT=""
OUTPUT_FILE=""

# Thresholds
CPU_WARN=75
CPU_CRIT=90
MEM_WARN=80
MEM_CRIT=95
DISK_WARN=80
DISK_CRIT=95
LOAD_WARN=4.0
LOAD_CRIT=8.0

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-health-check.sh" "Health monitoring for KVM hosts and VMs"
    cat <<'HEADER'
Usage: kvm-health-check.sh [OPTIONS] <ACTION>

 ACTIONS:
   domain       Check health of specific VM or all VMs
   host         Check host system health (CPU, RAM, disk, load, IOMMU)
   storage      Check storage pool usage and provisioning
   network      Check active networks, DHCP leases, bridge status
   report       Generate comprehensive JSON health report
HEADER
    cat <<EOF

 DOMAIN:
   --name <name>                Domain name (specific VM)
   --all                        Check all domains

 HOST / STORAGE / NETWORK / REPORT:
   No domain flags required.

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --json                       Output in JSON format
   --output <path>              Write report to file
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   All checks passed (healthy)
   1   Error
   2   Invalid arguments
   3   Degraded (warnings found)
   4   Critical (critical alerts found)

EXAMPLES:
   kvm-health-check.sh domain --name web01
   kvm-health-check.sh domain --all
   kvm-health-check.sh host
   kvm-health-check.sh storage
   kvm-health-check.sh network
   kvm-health-check.sh report --json --output /var/log/health-report.json
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            domain|host|storage|network|report)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --name)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --all)
                ALL_DOMAINS="yes"
                shift
                ;;
            --json)
                JSON_OUTPUT="yes"
                shift
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# validate_args
# ---------------------------------------------------------------------------
validate_args() {
    if [[ -z "${ACTION}" ]]; then
        log_error "No action specified."
        usage
    fi

    case "${ACTION}" in
        domain)
            if [[ -z "${DOMAIN_NAME}" && -z "${ALL_DOMAINS}" ]]; then
                log_error "domain requires --name or --all"
                exit 2
            fi
            ;;
        host|storage|network|report)
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# virsh_cmd
# ---------------------------------------------------------------------------
virsh_cmd() {
    virsh -c "${CONNECT_URI}" "$@"
}

# ---------------------------------------------------------------------------
# Severity helpers
# ---------------------------------------------------------------------------
ALERTS=()
ALERT_LEVEL=0  # 0=ok, 1=info, 2=warn, 3=crit

add_alert() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    ALERTS+=("${ts} [${level}] ${msg}")

    case "${level}" in
        WARN) (( ALERT_LEVEL < 2 )) && ALERT_LEVEL=2 ;;
        CRIT) (( ALERT_LEVEL < 3 )) && ALERT_LEVEL=3 ;;
    esac
}

# ---------------------------------------------------------------------------
# check_domain_health
# ---------------------------------------------------------------------------
check_domain_health() {
    local domain="$1"

    local state
    state=$(virsh_cmd domstate "${domain}" 2>/dev/null || echo "unknown")

    echo "=== Domain: ${domain} ==="
    echo "State: ${state}"

    if [[ "${state}" != "running" ]]; then
        echo "Status: NOT RUNNING"
        add_alert "WARN" "Domain ${domain} is not running (state: ${state})"
        echo ""
        return
    fi

    # CPU stats
    echo ""
    echo "CPU:"
    local cpu_stats
    cpu_stats=$(virsh_cmd domstats "${domain}" --vcpu 2>/dev/null || echo "")
    if [[ -n "${cpu_stats}" ]]; then
        echo "${cpu_stats}" | grep -E "cpu_time|cpu_" | head -10 || echo "  (no CPU data)"
    fi

    # Memory stats
    echo ""
    echo "Memory:"
    virsh_cmd dommemstat "${domain}" 2>/dev/null | while IFS= read -r line; do
        echo "  ${line}"
    done || echo "  (no memory data)"

    local mem_used
    mem_used=$(virsh_cmd dommemstat "${domain}" 2>/dev/null | grep "actual" | awk '{print $2}' || echo "0")
    local mem_max
    mem_max=$(virsh_cmd dominfo "${domain}" 2>/dev/null | grep "Max memory" | awk '{print $3}' || echo "1")
    if [[ "${mem_max}" -gt 0 && "${mem_used}" -gt 0 ]]; then
        local mem_pct=$((mem_used * 100 / mem_max))
        echo "  Usage: ${mem_pct}%"
        if (( mem_pct >= MEM_CRIT )); then
            add_alert "CRIT" "Domain ${domain} memory at ${mem_pct}% (critical threshold: ${MEM_CRIT}%)"
        elif (( mem_pct >= MEM_WARN )); then
            add_alert "WARN" "Domain ${domain} memory at ${mem_pct}% (warning threshold: ${MEM_WARN}%)"
        fi
    fi

    # Block I/O stats
    echo ""
    echo "Disk I/O:"
    virsh_cmd domblkstat "${domain}" 2>/dev/null | while IFS= read -r line; do
        echo "  ${line}"
    done || echo "  (no disk data)"

    # Network I/O stats
    echo ""
    echo "Network I/O:"
    virsh_cmd domifstat "${domain}" 2>/dev/null | while IFS= read -r line; do
        echo "  ${line}"
    done || echo "  (no network data)"

    echo ""
}

# ---------------------------------------------------------------------------
# action_domain
# ---------------------------------------------------------------------------
action_domain() {
    if [[ -n "${ALL_DOMAINS}" ]]; then
        log_info "Checking all domains..."
        echo ""
        virsh_cmd list --all 2>/dev/null | tail -n +3 | while IFS= read -r line; do
            local dom
            dom=$(echo "${line}" | awk '{print $2}')
            [[ -z "${dom}" ]] && continue
            check_domain_health "${dom}"
        done
    else
        check_domain_health "${DOMAIN_NAME}"
    fi
}

# ---------------------------------------------------------------------------
# action_host
# ---------------------------------------------------------------------------
action_host() {
    log_info "Host Health Check"
    echo "=================="
    echo "Hostname: $(hostname)"
    echo "Date: $(date -Iseconds)"
    echo ""

    # CPU
    echo "=== CPU ==="
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo "N/A")
    echo "CPU cores: ${cpu_count}"

    local load1 load5 load15
    read -r load1 load5 load15 _ < /proc/loadavg 2>/dev/null || {
        load1="N/A"; load5="N/A"; load15="N/A"
    }
    echo "Load average: ${load1} ${load5} ${load15}"

    if [[ "${load1}" != "N/A" ]]; then
        local load_int=${load1%.*}
        if (( $(echo "${load1} >= ${LOAD_CRIT}" | bc -l 2>/dev/null || echo 0) )); then
            add_alert "CRIT" "Host load average ${load1} exceeds critical threshold ${LOAD_CRIT}"
        elif (( $(echo "${load1} >= ${LOAD_WARN}" | bc -l 2>/dev/null || echo 0) )); then
            add_alert "WARN" "Host load average ${load1} exceeds warning threshold ${LOAD_WARN}"
        fi
    fi

    echo ""

    # CPU usage
    echo "CPU Usage:"
    top -bn1 2>/dev/null | head -5 || mpstat 1 1 2>/dev/null || echo "  (unavailable)"
    echo ""

    # Memory
    echo "=== Memory ==="
    free -h 2>/dev/null || echo "  (unavailable)"
    echo ""

    # Disk
    echo "=== Disk ==="
    df -h 2>/dev/null | grep -vE "^tmpfs|^overlay|^/dev/loop" || echo "  (unavailable)"
    echo ""

    # Disk usage alerts
    while IFS= read -r line; do
        local usage_pct mount
        usage_pct=$(echo "${line}" | awk '{print $5}' | tr -d '%')
        mount=$(echo "${line}" | awk '{print $6}')
        if [[ "${usage_pct}" =~ ^[0-9]+$ ]]; then
            if (( usage_pct >= DISK_CRIT )); then
                add_alert "CRIT" "Disk ${mount} usage at ${usage_pct}%"
            elif (( usage_pct >= DISK_WARN )); then
                add_alert "WARN" "Disk ${mount} usage at ${usage_pct}%"
            fi
        fi
    done < <(df -h 2>/dev/null | tail -n +2 | grep -vE "^tmpfs|^overlay")

    echo ""

    # Temperatures
    echo "=== Temperatures ==="
    if command -v sensors &>/dev/null; then
        sensors 2>/dev/null | head -20 || echo "  (sensors unavailable)"
    else
        echo "  lm-sensors not installed"
    fi
    echo ""

    # IOMMU
    echo "=== IOMMU ==="
    if dmesg 2>/dev/null | grep -qi "IOMMU\|DMAR\|AMD-Vi"; then
        echo "IOMMU: active"
        local groups=0
        if [[ -d /sys/kernel/iommu_groups ]]; then
            groups=$(ls -d /sys/kernel/iommu_groups/*/ 2>/dev/null | wc -l || echo 0)
        fi
        echo "IOMMU groups: ${groups}"
    else
        echo "IOMMU: not detected or not enabled"
    fi
    echo ""

    # KVM
    echo "=== KVM ==="
    if [[ -r /dev/kvm ]]; then
        echo "/dev/kvm: accessible"
    else
        echo "/dev/kvm: NOT accessible"
        add_alert "WARN" "/dev/kvm is not accessible"
    fi
    echo ""

    # Uptime
    echo "=== Uptime ==="
    uptime 2>/dev/null || echo "  (unavailable)"
    echo ""
}

# ---------------------------------------------------------------------------
# action_storage
# ---------------------------------------------------------------------------
action_storage() {
    log_info "Storage Health Check"
    echo "===================="
    echo ""

    echo "=== Storage Pools ==="
    virsh_cmd pool-list --all 2>/dev/null || echo "(libvirt pools unavailable)"
    echo ""

    virsh_cmd pool-list --all 2>/dev/null | tail -n +3 | while IFS= read -r line; do
        local pool_name
        pool_name=$(echo "${line}" | awk '{print $1}')
        [[ -z "${pool_name}" ]] && continue

        echo "Pool: ${pool_name}"
        virsh_cmd pool-info "${pool_name}" 2>/dev/null || true
        echo ""

        # Volume details
        virsh_cmd vol-list "${pool_name}" 2>/dev/null | tail -n +3 | while IFS= read -r vol_line; do
            local vol_name vol_path vol_size
            vol_name=$(echo "${vol_line}" | awk '{print $1}')
            vol_path=$(echo "${vol_line}" | awk '{print $3}')
            vol_size=$(echo "${vol_line}" | awk '{print $4}')
            [[ -z "${vol_name}" ]] && continue
            echo "  Volume: ${vol_name} (${vol_size})"
            if [[ -n "${vol_path}" && -f "${vol_path}" ]]; then
                local actual_size
                actual_size=$(du -sh "${vol_path}" 2>/dev/null | awk '{print $1}' || echo "N/A")
                echo "    Allocated: ${actual_size} | Virtual: ${vol_size}"
            fi
        done
        echo ""
    done

    echo "=== Filesystem Usage ==="
    df -hT 2>/dev/null | grep -vE "^tmpfs|^overlay|^/dev/loop" || echo "  (unavailable)"
    echo ""

    echo "=== Thin Provisioning ==="
    virsh_cmd pool-list --details 2>/dev/null | grep -i "net\|iscsi\|logical" || echo "  (check pool details above)"
    echo ""
}

# ---------------------------------------------------------------------------
# action_network
# ---------------------------------------------------------------------------
action_network() {
    log_info "Network Health Check"
    echo "===================="
    echo ""

    echo "=== Libvirt Networks ==="
    virsh_cmd net-list --all 2>/dev/null || echo "  (unavailable)"
    echo ""

    echo "=== Active Networks Detail ==="
    virsh_cmd net-list --active 2>/dev/null | tail -n +3 | while IFS= read -r line; do
        local net_name
        net_name=$(echo "${line}" | awk '{print $1}')
        [[ -z "${net_name}" ]] && continue

        echo "Network: ${net_name}"
        virsh_cmd net-info "${net_name}" 2>/dev/null || true
        echo ""

        # DHCP leases
        echo "  DHCP Leases:"
        virsh_cmd net-dhcp-leases "${net_name}" 2>/dev/null | head -20 || echo "    (none)"
        echo ""
    done

    echo "=== Host Bridges ==="
    if command -v brctl &>/dev/null; then
        brctl show 2>/dev/null || echo "  (unavailable)"
    elif [[ -d /sys/class/net ]]; then
        for iface in /sys/class/net/*/; do
            local ifname
            ifname=$(basename "${iface}")
            if [[ -d "/sys/class/net/${ifname}/bridge" ]]; then
                echo "Bridge: ${ifname}"
                cat "/sys/class/net/${ifname}/bridge/bridge_id" 2>/dev/null && echo ""
                echo "  Interfaces:"
                ls "/sys/class/net/${ifname}/brif/" 2>/dev/null | while IFS= read -r port; do
                    echo "    ${port}"
                done
            fi
        done
    fi
    echo ""

    echo "=== Network Interfaces ==="
    ip -brief addr show 2>/dev/null || ifconfig 2>/dev/null || echo "  (unavailable)"
    echo ""
}

# ---------------------------------------------------------------------------
# generate_json_report
# ---------------------------------------------------------------------------
generate_json_report() {
    local report
    report="{"
    report+="\"timestamp\":\"$(date -Iseconds)\","
    report+="\"hostname\":\"$(hostname)\","

    # Host info
    local load1 load5 load15
    read -r load1 load5 load15 _ < /proc/loadavg 2>/dev/null || {
        load1="0"; load5="0"; load15="0"
    }

    local mem_total mem_used
    mem_total=$(free -b 2>/dev/null | awk '/Mem:/{print $2}' || echo "0")
    mem_used=$(free -b 2>/dev/null | awk '/Mem:/{print $3}' || echo "0")

    report+="\"host\":{"
    report+="\"load_avg\":[${load1},${load5},${load15}],"
    report+="\"memory\":{"
    report+="\"total\":${mem_total},"
    report+="\"used\":${mem_used}"
    report+="},"
    report+="\"uptime\":$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")"
    report+="},"

    # Domain info
    report+="\"domains\":["
    local first=true
    virsh_cmd list --all 2>/dev/null | tail -n +3 | while IFS= read -r line; do
        local dom state
        dom=$(echo "${line}" | awk '{print $2}')
        state=$(echo "${line}" | awk '{print $3}')
        [[ -z "${dom}" ]] && continue

        if [[ "${first}" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "  {\"name\":\"${dom}\",\"state\":\"${state}\""
        if [[ "${state}" == "running" ]]; then
            local mem
            mem=$(virsh_cmd dommemstat "${dom}" 2>/dev/null | grep "actual" | awk '{print $2}' || echo "0")
            echo -n ",\"memory\":${mem}"
        fi
        echo -n "}"
    done
    echo ""
    report+="],"

    # Storage pools
    report+="\"storage_pools\":["
    virsh_cmd pool-list --name 2>/dev/null | tail -n +3 | head -5 | while IFS= read -r pool; do
        echo -n "  \"${pool}\""
    done
    report+="]"

    report+="}"

    echo "${report}"
}

# ---------------------------------------------------------------------------
# action_report
# ---------------------------------------------------------------------------
action_report() {
    log_info "Generating comprehensive health report..."

    local report=""
    report=$(generate_json_report)

    if [[ -n "${OUTPUT_FILE}" ]]; then
        echo "${report}" > "${OUTPUT_FILE}"
        log_info "Report written to: ${OUTPUT_FILE}"
    fi

    if [[ "${JSON_OUTPUT}" == "yes" ]]; then
        echo "${report}"
    else
        # Pretty-print key info
        echo ""
        echo "Health Report: $(date -Iseconds)"
        echo "================================"
        echo ""

        # Run all checks silently and collect output
        echo "--- Host ---"
        local load1 load5 load15
        read -r load1 load5 load15 _ < /proc/loadavg 2>/dev/null || true
        echo "Load: ${load1:-N/A} ${load5:-N/A} ${load15:-N/A}"
        free -h 2>/dev/null | head -2 || true
        echo ""

        echo "--- Domains ---"
        virsh_cmd list --all 2>/dev/null || true
        echo ""

        echo "--- Storage ---"
        df -h 2>/dev/null | grep -vE "^tmpfs|^overlay|^/dev/loop" || true
        echo ""

        echo "--- Networks ---"
        virsh_cmd net-list --all 2>/dev/null || true
        echo ""

        echo "--- Alerts ---"
        if (( ${#ALERTS[@]} == 0 )); then
            echo "No alerts."
        else
            for alert in "${ALERTS[@]}"; do
                echo "  ${alert}"
            done
        fi
    fi

    log_info "Health report complete."

    # Return appropriate exit code
    if (( ALERT_LEVEL >= 3 )); then
        return 4
    elif (( ALERT_LEVEL >= 2 )); then
        return 3
    fi
    return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs virsh

    case "${ACTION}" in
        domain)   action_domain ;;
        host)     action_host ;;
        storage)  action_storage ;;
        network)  action_network ;;
        report)   action_report ;;
    esac
}

main "$@"
