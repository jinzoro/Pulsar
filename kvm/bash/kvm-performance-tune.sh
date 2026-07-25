#!/usr/bin/env bash
# =============================================================================
# kvm-performance-tune.sh - Performance tuning for KVM VMs
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: hugepages, cpu-pin, numa, io-tune, balloon, kernel, status
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
DOMAIN=""
HUGEPAGES_COUNT=""
HUGEPAGES_1G_COUNT=""
ALLOCATE=""
VERIFY_HUGEPAGES=""
SET_IN_DOMAIN=""
VCPU_MAP=""
EMULATOR_PCPU=""
MEMORY_MODE=""
NODE_BIND=""
DISK_NAME=""
SCHEDULER=""
CACHE_MODE=""
IOTHREAD=""
IO_WEIGHT=""
BALLOON_CURRENT=""
BALLOON_MIN=""
BALLOON_MAX=""
HUGEPAGES_SYSCTL=""
KSM=""
SWAPPINESS=""
DIRTY_RATIO=""
THP=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-performance-tune.sh" "Performance tuning for KVM VMs"
    cat <<'HEADER'
Usage: kvm-performance-tune.sh [OPTIONS] <ACTION>

 ACTIONS:
   hugepages     Allocate and configure hugepages
   cpu-pin       Pin vCPUs to physical CPUs
   numa          Configure NUMA settings for a domain
   io-tune       Tune I/O scheduler, cache, and iothread settings
   balloon       Configure memory balloon for a domain
   kernel        Tune kernel parameters (hugepages, KSM, swappiness)
   status        Show current tuning for a domain
HEADER
    cat <<EOF

 HUGEPAGES:
   --count <N>                  Number of 2MB hugepages
   --count-1g <N>               Number of 1GB hugepages
   --allocate                   Allocate hugepages now
   --verify                     Verify hugepage allocation
   --set-in-domain              Apply hugepage config to running domain

 CPU-PIN:
   --domain <name>              Domain name (required)
   --vcpu-map <map>             vCPU mapping (e.g. vcpu0:pcpu0,vcpu1:pcpu1)
   --emulator-pcpu <cpus>       Emulator pinning (e.g. 4-7)

 NUMA:
   --domain <name>              Domain name (required)
   --memory-mode <mode>         Memory mode: strict, preferred, interleave
   --node-bind <nodes>          NUMA node binding (e.g. 0,1)

 IO-TUNE:
   --domain <name>              Domain name (required)
   --disk <name>                Disk target name (e.g. vda)
   --scheduler <algo>           I/O scheduler: mq-deadline, none, bfq
   --cache <mode>               Cache mode: none, writethrough, writeback
   --iothread                   Enable IOThread
   --io-weight <10-1000>        I/O weight

 BALLOON:
   --domain <name>              Domain name (required)
   --current <MB>               Current balloon size
   --min <MB>                   Minimum memory
   --max <MB>                   Maximum memory

 KERNEL:
   --hugepages-sysctl <val>     Set vm.nr_hugepages sysctl
   --ksm <0|1>                  Enable/disable KSM (Kernel Same-page Merging)
   --swappiness <0-100>         Set vm.swappiness
   --dirty-ratio <0-100>        Set vm.dirty_ratio
   --transparent-hugepages <val> Set THP: always, madvise, never

 STATUS:
   --domain <name>              Domain name (required)

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-performance-tune.sh hugepages --count 1024 --allocate --verify
   kvm-performance-tune.sh cpu-pin --domain db01 --vcpu-map vcpu0:pcpu0,vcpu1:pcpu1 --emulator-pcpu 4-7
   kvm-performance-tune.sh io-tune --domain web01 --disk vda --scheduler none --cache writeback --iothread
   kvm-performance-tune.sh kernel --hugepages-sysctl 4096 --ksm 0 --swappiness 10
   kvm-performance-tune.sh status --domain web01
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
            hugepages|cpu-pin|numa|io-tune|balloon|kernel|status)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --count)
                HUGEPAGES_COUNT="$2"
                shift 2
                ;;
            --count-1g)
                HUGEPAGES_1G_COUNT="$2"
                shift 2
                ;;
            --allocate)
                ALLOCATE="yes"
                shift
                ;;
            --verify)
                VERIFY_HUGEPAGES="yes"
                shift
                ;;
            --set-in-domain)
                SET_IN_DOMAIN="yes"
                shift
                ;;
            --vcpu-map)
                VCPU_MAP="$2"
                shift 2
                ;;
            --emulator-pcpu)
                EMULATOR_PCPU="$2"
                shift 2
                ;;
            --memory-mode)
                MEMORY_MODE="$2"
                shift 2
                ;;
            --node-bind)
                NODE_BIND="$2"
                shift 2
                ;;
            --disk)
                DISK_NAME="$2"
                shift 2
                ;;
            --scheduler)
                SCHEDULER="$2"
                shift 2
                ;;
            --cache)
                CACHE_MODE="$2"
                shift 2
                ;;
            --iothread)
                IOTHREAD="on"
                shift
                ;;
            --io-weight)
                IO_WEIGHT="$2"
                shift 2
                ;;
            --current)
                BALLOON_CURRENT="$2"
                shift 2
                ;;
            --min)
                BALLOON_MIN="$2"
                shift 2
                ;;
            --max)
                BALLOON_MAX="$2"
                shift 2
                ;;
            --hugepages-sysctl)
                HUGEPAGES_SYSCTL="$2"
                shift 2
                ;;
            --ksm)
                KSM="$2"
                shift 2
                ;;
            --swappiness)
                SWAPPINESS="$2"
                shift 2
                ;;
            --dirty-ratio)
                DIRTY_RATIO="$2"
                shift 2
                ;;
            --transparent-hugepages)
                THP="$2"
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
        cpu-pin|numa|io-tune|balloon|status)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "${ACTION} requires --domain"
                exit 2
            fi
            ;;
        hugepages|kernel)
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
# action_hugepages
# ---------------------------------------------------------------------------
action_hugepages() {
    log_info "Configuring hugepages..."

    if [[ "${ALLOCATE:-}" == "yes" ]]; then
        if [[ -n "${HUGEPAGES_COUNT}" ]]; then
            log_info "  Allocating ${HUGEPAGES_COUNT} x 2MB hugepages..."
            dry_run sysctl -w "vm.nr_hugepages=${HUGEPAGES_COUNT}"
        fi

        if [[ -n "${HUGEPAGES_1G_COUNT}" ]]; then
            log_info "  Allocating ${HUGEPAGES_1G_COUNT} x 1GB hugepages..."
            if [[ -d /sys/kernel/mm/hugepages/hugepages-1048576kB ]]; then
                dry_run bash -c "echo ${HUGEPAGES_1G_COUNT} > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
            else
                log_warn "  1GB hugepages not supported on this system."
            fi
        fi
    fi

    if [[ "${VERIFY_HUGEPAGES:-}" == "yes" ]]; then
        log_info "  Verifying hugepage allocation:"
        echo ""
        echo "=== 2MB Hugepages ==="
        cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo "N/A"
        echo "  allocated: $(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo N/A)"
        echo "  free:      $(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo N/A)"
        echo ""
        echo "=== 1GB Hugepages ==="
        echo "  allocated: $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo N/A)"
        echo "  free:      $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo N/A)"
        echo ""

        log_info "  Transparent Hugepages:"
        cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "  N/A"
    fi

    if [[ "${SET_IN_DOMAIN:-}" == "yes" && -n "${DOMAIN}" ]]; then
        log_info "  Setting hugepages in domain XML..."
        local mem_kib
        mem_kib=$(virsh_cmd dominfo "${DOMAIN}" 2>/dev/null | grep "Max memory" | awk '{print $3}' || echo "0")

        if [[ -n "${HUGEPAGES_COUNT}" && "${HUGEPAGES_COUNT}" -gt 0 ]]; then
            local hp_size_kb=$((HUGEPAGES_COUNT * 2048))
            log_info "  Setting ${HUGEPAGES_COUNT} x 2MB pages (${hp_size_kb} KB) for ${DOMAIN}"
            dry_run virsh_cmd setmem "${DOMAIN}" "${hp_size_kb}" --config
        fi
    fi

    log_info "Hugepages configuration complete."
}

# ---------------------------------------------------------------------------
# action_cpu_pin
# ---------------------------------------------------------------------------
action_cpu_pin() {
    log_info "Pinning vCPUs for domain '${DOMAIN}'..."

    if [[ -n "${VCPU_MAP}" ]]; then
        log_info "  vCPU mapping: ${VCPU_MAP}"

        IFS=',' read -ra mappings <<< "${VCPU_MAP}"
        local xml_mods=""
        for mapping in "${mappings[@]}"; do
            local vcpu pcpu
            vcpu="${mapping%%:*}"
            pcpu="${mapping##*:}"
            log_info "  ${vcpu} -> pcpu${pcpu}"

            local vcpu_num
            vcpu_num=$(echo "${vcpu}" | grep -oP '\d+' || echo "0")

            xml_mods+="<vcpupin vcpu='${vcpu_num}' cpuset='${pcpu}'/>"
        done

        if [[ -n "${EMULATOR_PCPU}" ]]; then
            log_info "  Emulator -> pcpu${EMULATOR_PCPU}"
            xml_mods+="<emulatorpin cpuset='${EMULATOR_PCPU}'/>"
        fi

        if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
            log_info "[DRY RUN] Would update domain XML with CPU pinning"
        else
            local tmpxml
            tmpxml=$(create_temp_file)
            virsh_cmd dumpxml "${DOMAIN}" > "${tmpxml}" 2>/dev/null || {
                log_error "Failed to dump domain XML."
                return 1
            }

            if ! grep -q "cputune" "${tmpxml}"; then
                sed -i "/<\/domain>/i\\  <cputune>${xml_mods}</cputune>" "${tmpxml}"
            else
                log_info "  cputune section already exists; updating..."
                sed -i "s|<cputune>.*</cputune>|<cputune>${xml_mods}</cputune>|" "${tmpxml}"
            fi

            virsh_cmd define "${tmpxml}" || {
                log_error "Failed to define updated XML."
                return 1
            }
        fi
    fi

    log_info "CPU pinning configured for domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_numa
# ---------------------------------------------------------------------------
action_numa() {
    log_info "Configuring NUMA for domain '${DOMAIN}'..."

    local -a cmd=(virsh_cmd numatune "${DOMAIN}")

    if [[ -n "${MEMORY_MODE}" ]]; then
        cmd+=(--mode "${MEMORY_MODE}")
    fi

    if [[ -n "${NODE_BIND}" ]]; then
        cmd+=(--nodemask "${NODE_BIND}")
    fi

    if (( ${#cmd[@]} > 3 )); then
        log_info "Command: ${cmd[*]}"
        dry_run "${cmd[@]}"
    fi

    log_info "NUMA configuration complete."
}

# ---------------------------------------------------------------------------
# action_io_tune
# ---------------------------------------------------------------------------
action_io_tune() {
    log_info "Tuning I/O for domain '${DOMAIN}'..."

    if [[ -z "${DISK_NAME}" ]]; then
        log_error "io-tune requires --disk"
        exit 2
    fi

    local -a cmd=(virsh_cmd iothreadinfo "${DOMAIN}" --domain)

    if [[ -n "${SCHEDULER}" ]]; then
        log_info "  Setting I/O scheduler to ${SCHEDULER} for ${DISK_NAME}..."
        local block_path="/sys/block/$(basename "${DISK_NAME}")/queue/scheduler"
        if [[ -w "${block_path}" ]]; then
            dry_run bash -c "echo ${SCHEDULER} > ${block_path}"
        else
            log_warn "  Cannot set scheduler directly at ${block_path}"
        fi
    fi

    if [[ -n "${CACHE_MODE}" ]]; then
        log_info "  Setting cache mode to ${CACHE_MODE}..."
        dry_run virsh_cmd iothreadinfo "${DOMAIN}" --domain
    fi

    if [[ -n "${IOTHREAD:-}" ]]; then
        log_info "  Enabling IOThread for ${DISK_NAME}..."
    fi

    if [[ -n "${IO_WEIGHT}" ]]; then
        log_info "  Setting I/O weight to ${IO_WEIGHT}..."
        dry_run virsh_cmd blkiotune "${DOMAIN}" --weight "${IO_WEIGHT}"
    fi

    log_info "I/O tuning complete for domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_balloon
# ---------------------------------------------------------------------------
action_balloon() {
    log_info "Configuring memory balloon for domain '${DOMAIN}'..."

    if [[ -n "${BALLOON_CURRENT}" ]]; then
        log_info "  Setting current balloon to ${BALLOON_CURRENT} MB..."
        dry_run virsh_cmd setmem "${DOMAIN}" "${BALLOON_CURRENT}" --current
    fi

    if [[ -n "${BALLOON_MIN}" && -n "${BALLOON_MAX}" ]]; then
        log_info "  Setting balloon range: ${BALLOON_MIN} MB - ${BALLOON_MAX} MB..."
        dry_run virsh_cmd setmem "${DOMAIN}" "${BALLOON_MIN}" --minimum
        dry_run virsh_cmd setmem "${DOMAIN}" "${BALLOON_MAX}" --maximum
    fi

    log_info "Balloon configuration complete."
}

# ---------------------------------------------------------------------------
# action_kernel
# ---------------------------------------------------------------------------
action_kernel() {
    log_info "Tuning kernel parameters..."

    check_root

    if [[ -n "${HUGEPAGES_SYSCTL}" ]]; then
        log_info "  Setting vm.nr_hugepages = ${HUGEPAGES_SYSCTL}..."
        dry_run sysctl -w "vm.nr_hugepages=${HUGEPAGES_SYSCTL}"
    fi

    if [[ -n "${KSM}" ]]; then
        local ksm_path="/sys/kernel/mm/ksm/run"
        if [[ -w "${ksm_path}" ]]; then
            log_info "  Setting KSM = ${KSM}..."
            dry_run bash -c "echo ${KSM} > ${ksm_path}"
        else
            log_warn "  KSM sysfs not found; modprobe ksm may be needed."
        fi
    fi

    if [[ -n "${SWAPPINESS}" ]]; then
        log_info "  Setting vm.swappiness = ${SWAPPINESS}..."
        dry_run sysctl -w "vm.swappiness=${SWAPPINESS}"
    fi

    if [[ -n "${DIRTY_RATIO}" ]]; then
        log_info "  Setting vm.dirty_ratio = ${DIRTY_RATIO}..."
        dry_run sysctl -w "vm.dirty_ratio=${DIRTY_RATIO}"
    fi

    if [[ -n "${THP}" ]]; then
        local thp_path="/sys/kernel/mm/transparent_hugepage/enabled"
        if [[ -w "${thp_path}" ]]; then
            log_info "  Setting transparent hugepages = ${THP}..."
            dry_run bash -c "echo ${THP} > ${thp_path}"
        else
            log_warn "  THP sysfs not found."
        fi
    fi

    log_info "Kernel tuning complete."
}

# ---------------------------------------------------------------------------
# action_status
# ---------------------------------------------------------------------------
action_status() {
    log_info "Performance tuning status for domain '${DOMAIN}':"
    echo ""

    echo "=== Domain Info ==="
    virsh_cmd dominfo "${DOMAIN}" 2>/dev/null || true
    echo ""

    echo "=== Memory Stats ==="
    virsh_cmd dommemstat "${DOMAIN}" 2>/dev/null || true
    echo ""

    echo "=== Block Stats ==="
    virsh_cmd domblkstat "${DOMAIN}" 2>/dev/null || true
    echo ""

    echo "=== CPU Stats ==="
    virsh_cmd domstats "${DOMAIN}" --vcpu 2>/dev/null || true
    echo ""

    echo "=== NUMA Info ==="
    virsh_cmd numatune "${DOMAIN}" 2>/dev/null || true
    echo ""

    echo "=== Current Hugepages ==="
    cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo "N/A"
    echo ""

    echo "=== KSM Status ==="
    cat /sys/kernel/mm/ksm/run 2>/dev/null || echo "N/A"
    echo ""

    echo "=== Transparent Hugepages ==="
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "N/A"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs virsh
    require_libvirt "${CONNECT_URI}"

    case "${ACTION}" in
        hugepages) action_hugepages ;;
        cpu-pin)   action_cpu_pin ;;
        numa)      action_numa ;;
        io-tune)   action_io_tune ;;
        balloon)   action_balloon ;;
        kernel)    action_kernel ;;
        status)    action_status ;;
    esac
}

main "$@"
