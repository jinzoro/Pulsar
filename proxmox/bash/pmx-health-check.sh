#!/usr/bin/env bash
# =============================================================================
# pmx-health-check.sh — Health monitoring
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: node, vm, storage, ceph, cluster, report, alert
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Health monitoring"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  node        [--node=NODE]           Node health (CPU, RAM, disk, temps, load, uptime)
  vm          [--vmid=ID]             VM health (status, CPU, RAM, disk, agent)
  storage     [--node=NODE] [--storage=S]  Storage health
  ceph                                Ceph cluster health
  cluster                             Cluster quorum, nodes, HA status
  report                              Comprehensive JSON health report
  alert                               Check against thresholds

NODE OPTIONS:
  --node=NODE         Node to check (default: all nodes)

VM OPTIONS:
  --vmid=ID           Specific VM (all if omitted)

STORAGE OPTIONS:
  --node=NODE         Node filter
  --storage=S         Storage filter

OPTIONS:
  --json              Output as JSON
  --threshold-cpu=N   CPU alert threshold % (default: 80)
  --threshold-mem=N   Memory alert threshold % (default: 85)
  --threshold-disk=N  Disk alert threshold % (default: 90)
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") node
  $(basename "$0") node --node=pve1
  $(basename "$0") vm --vmid=100
  $(basename "$0") vm
  $(basename "$0") storage --node=pve1
  $(basename "$0") ceph
  $(basename "$0") cluster
  $(basename "$0") report --json
  $(basename "$0") alert --threshold-cpu=90 --threshold-mem=90
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NODE_FILTER=""
VM_FILTER=""
STORAGE_FILTER=""
JSON_OUTPUT=false
THRESHOLD_CPU=80
THRESHOLD_MEM=85
THRESHOLD_DISK=90

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node=*)           NODE_FILTER="${1#*=}" ;;
            --vmid=*)           VM_FILTER="${1#*=}" ;;
            --storage=*)        STORAGE_FILTER="${1#*=}" ;;
            --threshold-cpu=*)  THRESHOLD_CPU="${1#*=}" ;;
            --threshold-mem=*)  THRESHOLD_MEM="${1#*=}" ;;
            --threshold-disk=*) THRESHOLD_DISK="${1#*=}" ;;
            --json)             JSON_OUTPUT=true; shift; continue ;;
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
# Helpers
# ---------------------------------------------------------------------------
get_nodes() {
    if [[ -n "${NODE_FILTER}" ]]; then
        echo "${NODE_FILTER}"
    else
        parse_json "$(api_call GET /nodes)" ".data[].node" 2>/dev/null
    fi
}

json_escape() {
    echo "$1" | jq -Rs '.'
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_node() {
    log_info "Checking node health..."
    local json_out="[]"

    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue

        local resp
        resp=$(api_call GET "/nodes/${node}/status" 2>/dev/null) || continue

        local cpu mem_total mem_used uptime_ load1 load5 load15
        cpu=$(parse_json "${resp}" ".data.cpu // 0")
        mem_total=$(parse_json "${resp}" ".data.maxmem // 0")
        mem_used=$(parse_json "${resp}" ".data.mem // 0")
        uptime_=$(parse_json "${resp}" ".data.uptime // 0")
        load1=$(parse_json "${resp}" ".data.loadavg[0] // 0")
        load5=$(parse_json "${resp}" ".data.loadavg[1] // 0")
        load15=$(parse_json "${resp}" ".data.loadavg[2] // 0")

        local cpu_pct
        cpu_pct=$(echo "${cpu}" | awk '{printf "%.1f", $1*100}')
        local mem_pct=0
        if (( mem_total > 0 )); then
            mem_pct=$(( (mem_used * 100) / mem_total ))
        fi
        local mem_total_h mem_used_h
        mem_total_h=$(numfmt --to=iec --suffix=B "${mem_total}" 2>/dev/null || echo "${mem_total}")
        mem_used_h=$(numfmt --to=iec --suffix=B "${mem_used}" 2>/dev/null || echo "${mem_used}")
        local uptime_h
        uptime_h=$(printf '%dd %dh %dm' $(( uptime_/86400 )) $(( (uptime_%86400)/3600 )) $(( (uptime_%3600)/60 )))

        if [[ "${JSON_OUTPUT}" == "true" ]]; then
            local node_json
            node_json=$(jq -n \
                --arg node "${node}" \
                --argjson cpu "${cpu_pct}" \
                --argjson mem_pct "${mem_pct}" \
                --arg mem_used "${mem_used_h}" \
                --arg mem_total "${mem_total_h}" \
                --arg uptime "${uptime_h}" \
                --arg load1 "${load1}" --arg load5 "${load5}" --arg load15 "${load15}" \
                '{"node": $node, "cpu_pct": $cpu, "mem_pct": $mem_pct, "mem_used": $mem_used, "mem_total": $mem_total, "uptime": $uptime, "load_1m": $load1, "load_5m": $load5, "load_15m": $load15}')
            json_out=$(echo "${json_out}" | jq -c --argjson nj "${node_json}" '. + [$nj]')
        else
            echo ""
            local cpu_color="${GREEN}" mem_color="${GREEN}"
            (( $(echo "${cpu_pct} > ${THRESHOLD_CPU}" | bc -l 2>/dev/null || echo 0) )) && cpu_color="${RED}"
            (( mem_pct > THRESHOLD_MEM )) && mem_color="${RED}"

            printf "${BOLD}Node: ${CYAN}%s${NC}\n" "${node}"
            printf "  CPU:        ${cpu_color}%s%%${NC}  Load: %s / %s / %s\n" "${cpu_pct}" "${load1}" "${load5}" "${load15}"
            printf "  Memory:     ${mem_color}%s%%${NC}  (%s / %s)\n" "${mem_pct}" "${mem_used_h}" "${mem_total_h}"
            printf "  Uptime:     %s\n" "${uptime_h}"
        fi

        # Disk health
        local disks_resp
        disks_resp=$(api_call GET "/nodes/${node}/disks/list" 2>/dev/null) || true
        parse_json "${disks_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local dev size used pct
            dev=$(echo "${item}" | jq -r '.dev // ""')
            size=$(echo "${item}" | jq -r '.size // 0')
            used=$(echo "${item}" | jq -r '.used // 0')
            pct=$(echo "${item}" | jq -r '.percent // 0')

            if [[ "${JSON_OUTPUT}" != "true" ]]; then
                local disk_color="${GREEN}"
                (( pct > THRESHOLD_DISK )) && disk_color="${RED}"
                local size_h used_h
                size_h=$(numfmt --to=iec --suffix=B "${size}" 2>/dev/null || echo "${size}")
                used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
                printf "  Disk %-10s ${disk_color}%3d%%${NC}  (%s / %s)\n" "${dev}" "${pct}" "${used_h}" "${size_h}"
            fi
        done

        # Temperature
        local temp_resp
        temp_resp=$(api_call GET "/nodes/${node}/hardware/temperature" 2>/dev/null) || true
        parse_json "${temp_resp}" ".data[] | select(.current != null)" 2>/dev/null | while IFS= read -r item; do
            local tname tcurrent twarn
            tname=$(echo "${item}" | jq -r '.name // ""')
            tcurrent=$(echo "${item}" | jq -r '.current // 0')
            twarn=$(echo "${item}" | jq -r '.warning // 0')

            if [[ "${JSON_OUTPUT}" != "true" ]]; then
                local temp_color="${GREEN}"
                (( tcurrent >= twarn )) && temp_color="${RED}"
                printf "  Temp %-16s ${temp_color}%d°C${NC}\n" "${tname}" "${tcurrent}"
            fi
        done
    done < <(get_nodes)

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        echo "${json_out}" | jq .
    fi
}

do_vm() {
    log_info "Checking VM health..."
    local json_out="[]"

    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue

        local vm_resp
        if [[ -n "${VM_FILTER}" ]]; then
            vm_resp=$(api_call GET "/nodes/${node}/qemu/${VM_FILTER}/status/current" 2>/dev/null) || continue
            # Wrap in array for consistency
            vm_resp="{\"data\":[$(parse_json "${vm_resp}" ".data")]}"
        else
            vm_resp=$(api_call GET "/nodes/${node}/qemu" 2>/dev/null) || continue
        fi

        parse_json "${vm_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local vmid name status cpu mem_max mem_pct
            vmid=$(echo "${item}" | jq -r '.vmid // ""')
            name=$(echo "${item}" | jq -r '.name // "unnamed"')
            status=$(echo "${item}" | jq -r '.status // "unknown"')
            cpu=$(echo "${item}" | jq -r '.cpu // 0')
            mem_max=$(echo "${item}" | jq -r '.maxmem // 0')
            mem_pct=$(echo "${item}" | jq -r '.mem // 0')

            local mem_pct_val=0
            if (( mem_max > 0 )); then
                mem_pct_val=$(( (mem_pct * 100) / mem_max ))
            fi
            local mem_h
            mem_h=$(numfmt --to=iec --suffix=B "${mem_max}" 2>/dev/null || echo "${mem_max}")

            if [[ "${JSON_OUTPUT}" == "true" ]]; then
                local vm_json
                vm_json=$(jq -n \
                    --arg vmid "${vmid}" --arg name "${name}" --arg status "${status}" \
                    --argjson cpu "$(echo "${cpu}" | awk '{printf "%.1f", $1*100}')" \
                    --argjson mem_pct "${mem_pct_val}" --arg mem "${mem_h}" \
                    --arg node "${node}" \
                    '{"vmid": $vmid, "name": $name, "status": $status, "cpu_pct": $cpu, "mem_pct": $mem_pct, "mem": $mem, "node": $node}')
                json_out=$(echo "${json_out}" | jq -c --argjson v "${vm_json}" '. + [$v]')
            else
                local status_color="${GREEN}"
                [[ "${status}" != "running" ]] && status_color="${YELLOW}"

                printf "%-6s ${status_color}%-12s${NC} %-20s CPU:%-6s MEM:%-4s%%\n" \
                    "${vmid}" "${status}" "${name}" \
                    "$(echo "${cpu}" | awk '{printf "%.1f%%", $1*100}')" \
                    "${mem_pct_val}"
            fi
        done
    done < <(get_nodes)

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        echo "${json_out}" | jq .
    fi
}

do_storage() {
    log_info "Checking storage health..."
    local json_out="[]"

    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue

        local stor_resp
        stor_resp=$(api_call GET "/nodes/${node}/storage" 2>/dev/null) || continue

        parse_json "${stor_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local sname stype
            sname=$(echo "${item}" | jq -r '.storage // "unknown"')
            stype=$(echo "${item}" | jq -r '.type // "unknown"')

            [[ -n "${STORAGE_FILTER}" && "${sname}" != "${STORAGE_FILTER}" ]] && continue

            local status_resp
            status_resp=$(api_call GET "/nodes/${node}/storage/${sname}/status" 2>/dev/null) || continue

            local total used avail status
            total=$(parse_json "${status_resp}" ".data.total // 0")
            used=$(parse_json "${status_resp}" ".data.used // 0")
            avail=$(parse_json "${status_resp}" ".data.avail // 0")
            status=$(parse_json "${status_resp}" ".data.status // unknown")

            local pct=0
            (( total > 0 )) && pct=$(( (used * 100) / total ))

            if [[ "${JSON_OUTPUT}" == "true" ]]; then
                local s_json
                s_json=$(jq -n \
                    --arg name "${sname}" --arg type "${stype}" --arg status "${status}" \
                    --argjson total "${total}" --argjson used "${used}" --argjson avail "${avail}" \
                    --argjson pct "${pct}" --arg node "${node}" \
                    '{"storage": $name, "type": $type, "status": $status, "total": $total, "used": $used, "avail": $avail, "pct": $pct, "node": $node}')
                json_out=$(echo "${json_out}" | jq -c --argjson s "${s_json}" '. + [$s]')
            else
                local pct_color="${GREEN}"
                (( pct > THRESHOLD_DISK )) && pct_color="${RED}"

                local total_h used_h avail_h
                total_h=$(numfmt --to=iec --suffix=B "${total}" 2>/dev/null || echo "${total}")
                used_h=$(numfmt --to=iec --suffix=B "${used}" 2>/dev/null || echo "${used}")
                avail_h=$(numfmt --to=iec --suffix=B "${avail}" 2>/dev/null || echo "${avail}")

                printf "${BOLD}%-16s${NC} %-12s ${GREEN}%-8s${NC} ${pct_color}%3d%%${NC}  %s / %s\n" \
                    "${sname}" "${stype}" "${status}" "${pct}" "${used_h}" "${total_h}"
            fi
        done
    done < <(get_nodes)

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        echo "${json_out}" | jq .
    fi
}

do_ceph() {
    log_info "Checking Ceph health..."

    if ! command -v ceph &>/dev/null; then
        log_warn "Ceph not installed."
        return 0
    fi

    local ceph_status
    ceph_status=$(ceph health 2>/dev/null) || {
        log_warn "Ceph not running."
        return 0
    }

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        ceph health -f json 2>/dev/null || echo "{}"
    else
        echo ""
        echo -e "${BOLD}Ceph Health:${NC} ${ceph_status}"
        echo ""
        ceph -s 2>/dev/null || true
    fi
}

do_cluster() {
    log_info "Checking cluster health..."

    # Quorum
    echo ""
    echo -e "${BOLD}Quorum:${NC}"
    dry_run bash -c "pvecm status 2>&1" || log_warn "Not in a cluster."

    # Nodes
    echo ""
    echo -e "${BOLD}Nodes:${NC}"
    do_node

    # HA
    echo ""
    echo -e "${BOLD}HA Resources:${NC}"
    local ha_resp
    ha_resp=$(api_call GET "/cluster/ha/resources" 2>/dev/null) || {
        log_info "No HA configured."
        return 0
    }

    printf "%-8s %-12s %-10s\n" "VMID" "STATUS" "GROUP"
    parse_json "${ha_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local sid sstatus sgroup
        sid=$(echo "${item}" | jq -r '.sid // ""')
        sstatus=$(echo "${item}" | jq -r '.state // "unknown"')
        sgroup=$(echo "${item}" | jq -r '.group // "-"')

        local color="${GREEN}"
        [[ "${sstatus}" != "started" && "${sstatus}" != "active" ]] && color="${RED}"
        printf "%-8s ${color}%-12s${NC} %-10s\n" "${sid}" "${sstatus}" "${sgroup}"
    done
}

do_report() {
    log_info "Generating comprehensive health report..."
    echo ""

    local report
    report=$(jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg host "$(hostname)" \
        '{"timestamp": $ts, "host": $host}')

    # Node health
    local nodes_json="[]"
    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue
        local resp
        resp=$(api_call GET "/nodes/${node}/status" 2>/dev/null) || continue

        local cpu mem_total mem_used uptime_
        cpu=$(parse_json "${resp}" ".data.cpu // 0")
        mem_total=$(parse_json "${resp}" ".data.maxmem // 0")
        mem_used=$(parse_json "${resp}" ".data.mem // 0")
        uptime_=$(parse_json "${resp}" ".data.uptime // 0")

        local cpu_pct
        cpu_pct=$(echo "${cpu}" | awk '{printf "%.1f", $1*100}')
        local mem_pct=0
        (( mem_total > 0 )) && mem_pct=$(( (mem_used * 100) / mem_total ))

        local n_json
        n_json=$(jq -n \
            --arg name "${node}" \
            --argjson cpu "${cpu_pct}" \
            --argjson mem_pct "${mem_pct}" \
            --argjson uptime "${uptime_}" \
            '{"name": $name, "cpu_pct": $cpu, "mem_pct": $mem_pct, "uptime_s": $uptime}')
        nodes_json=$(echo "${nodes_json}" | jq -c --argjson n "${n_json}". '. + [$n]')
    done < <(get_nodes)

    report=$(echo "${report}" | jq -c --argjson nodes "${nodes_json}" '. + {"nodes": $nodes}')

    # VM health
    local vms_json="[]"
    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue
        local vm_resp
        vm_resp=$(api_call GET "/nodes/${node}/qemu" 2>/dev/null) || continue

        parse_json "${vm_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local vmid status cpu mem_max mem_used
            vmid=$(echo "${item}" | jq -r '.vmid // ""')
            status=$(echo "${item}" | jq -r '.status // "unknown"')
            cpu=$(echo "${item}" | jq -r '.cpu // 0')
            mem_max=$(echo "${item}" | jq -r '.maxmem // 0')
            mem_used=$(echo "${item}" | jq -r '.mem // 0')

            local mem_pct=0
            (( mem_max > 0 )) && mem_pct=$(( (mem_used * 100) / mem_max ))

            printf '{"vmid":"%s","status":"%s","cpu_pct":%.1f,"mem_pct":%d,"node":"%s"}\n' \
                "${vmid}" "${status}" "$(echo "${cpu}" | awk '{printf "%.1f", $1*100}')" "${mem_pct}" "${node}"
        done
    done < <(get_nodes) | jq -s '.' > /tmp/vms.json 2>/dev/null

    vms_json=$(cat /tmp/vms.json 2>/dev/null || echo "[]")
    rm -f /tmp/vms.json

    report=$(echo "${report}" | jq -c --argjson vms "${vms_json}" '. + {"vms": $vms}')

    # Ceph
    local ceph_health="not_installed"
    if command -v ceph &>/dev/null; then
        ceph_health=$(ceph health 2>/dev/null || echo "not_running")
    fi
    report=$(echo "${report}" | jq -c --arg ceph "${ceph_health}" '. + {"ceph": $ceph}')

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        echo "${report}" | jq .
    else
        echo "${report}" | jq -r '
            "=== Health Report ===",
            "Timestamp: \(.timestamp)",
            "Host: \(.host)",
            "",
            "Nodes:",
            (.nodes[] | "  \(.name): CPU=\(.cpu_pct)% MEM=\(.mem_pct)% Uptime=\(.uptime_s)s"),
            "",
            "VMs: \(.vms | length) total",
            (.vms[] | "  \(.vmid): \(.status) CPU=\(.cpu_pct)% MEM=\(.mem_pct)% [\(.node)]"),
            "",
            "Ceph: \(.ceph)"
        '
    fi
}

do_alert() {
    log_info "Checking alerts against thresholds..."
    local alerts=0

    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue

        local resp
        resp=$(api_call GET "/nodes/${node}/status" 2>/dev/null) || continue

        local cpu mem_total mem_used
        cpu=$(parse_json "${resp}" ".data.cpu // 0")
        mem_total=$(parse_json "${resp}" ".data.maxmem // 0")
        mem_used=$(parse_json "${resp}" ".data.mem // 0")

        local cpu_pct
        cpu_pct=$(echo "${cpu}" | awk '{printf "%.0f", $1*100}')
        local mem_pct=0
        (( mem_total > 0 )) && mem_pct=$(( (mem_used * 100) / mem_total ))

        if (( cpu_pct > THRESHOLD_CPU )); then
            echo -e "${RED}[ALERT] ${node}: CPU at ${cpu_pct}% (threshold: ${THRESHOLD_CPU}%)${NC}"
            alerts=$((alerts + 1))
        fi
        if (( mem_pct > THRESHOLD_MEM )); then
            echo -e "${RED}[ALERT] ${node}: Memory at ${mem_pct}% (threshold: ${THRESHOLD_MEM}%)${NC}"
            alerts=$((alerts + 1))
        fi

        # Disk check
        local disks_resp
        disks_resp=$(api_call GET "/nodes/${node}/disks/list" 2>/dev/null) || true
        parse_json "${disks_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local dev pct
            dev=$(echo "${item}" | jq -r '.dev // ""')
            pct=$(echo "${item}" | jq -r '.percent // 0')
            if (( pct > THRESHOLD_DISK )); then
                echo -e "${RED}[ALERT] ${node} / ${dev}: Disk at ${pct}% (threshold: ${THRESHOLD_DISK}%)${NC}"
            fi
        done
    done < <(get_nodes)

    # Storage check
    while IFS= read -r node; do
        [[ -z "${node}" ]] && continue
        local stor_resp
        stor_resp=$(api_call GET "/nodes/${node}/storage" 2>/dev/null) || continue

        parse_json "${stor_resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
            local sname
            sname=$(echo "${item}" | jq -r '.storage // ""')
            local status_resp
            status_resp=$(api_call GET "/nodes/${node}/storage/${sname}/status" 2>/dev/null) || continue

            local total used
            total=$(parse_json "${status_resp}" ".data.total // 0")
            used=$(parse_json "${status_resp}" ".data.used // 0")
            local pct=0
            (( total > 0 )) && pct=$(( (used * 100) / total ))

            if (( pct > THRESHOLD_DISK )); then
                echo -e "${RED}[ALERT] Storage ${sname} on ${node}: ${pct}% used (threshold: ${THRESHOLD_DISK}%)${NC}"
            fi
        done
    done < <(get_nodes)

    if (( alerts == 0 )); then
        echo -e "${GREEN}No alerts. All systems within thresholds.${NC}"
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
        node)     do_node ;;
        vm)       do_vm ;;
        storage)  do_storage ;;
        ceph)     do_ceph ;;
        cluster)  do_cluster ;;
        report)   do_report ;;
        alert)    do_alert ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
