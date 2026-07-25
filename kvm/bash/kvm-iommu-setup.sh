#!/usr/bin/env bash
# =============================================================================
# kvm-iommu-setup.sh - IOMMU setup and configuration for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: enable, status, groups, blacklist-gpu
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/bash/lib/common.sh
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VENDOR=""
BLACKLIST_DRIVERS=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-iommu-setup.sh" "IOMMU setup and configuration"
    cat <<'HEADER'
Usage: kvm-iommu-setup.sh [OPTIONS] <ACTION>

 ACTIONS:
   enable          Enable IOMMU in GRUB and verify
   status          Check IOMMU status and group count
   groups          List all IOMMU groups with devices
   blacklist-gpu   Blacklist GPU drivers for passthrough
HEADER
    cat <<EOF

 ENABLE:
   --vendor <intel|amd>         CPU vendor (required)

 STATUS / GROUPS:
   No additional flags required.

 BLACKLIST-GPU:
   --drivers <list>             Comma-separated drivers to blacklist
                                (default: nouveau,nvidiafb,amdgpu,radeon)

 GENERAL:
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-iommu-setup.sh enable --vendor intel
   kvm-iommu-setup.sh enable --vendor amd
   kvm-iommu-setup.sh status
   kvm-iommu-setup.sh groups
   kvm-iommu-setup.sh blacklist-gpu
   kvm-iommu-setup.sh blacklist-gpu --drivers nouveau,radeon
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
            enable|status|groups|blacklist-gpu)
                ACTION="$1"
                shift
                ;;
            --vendor)
                VENDOR="$2"
                shift 2
                ;;
            --drivers)
                BLACKLIST_DRIVERS="$2"
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
        enable)
            if [[ -z "${VENDOR}" ]]; then
                log_error "enable requires --vendor (intel or amd)"
                exit 2
            fi
            local v="${VENDOR,,}"
            if [[ "${v}" != "intel" && "${v}" != "amd" ]]; then
                log_error "Invalid vendor: ${VENDOR}. Must be 'intel' or 'amd'."
                exit 2
            fi
            ;;
        status|groups|blacklist-gpu)
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# action_enable
# ---------------------------------------------------------------------------
action_enable() {
    local vendor="${VENDOR,,}"
    log_info "Enabling IOMMU for ${vendor} CPU..."

    check_root

    local grub_params
    if [[ "${vendor}" == "intel" ]]; then
        grub_params="intel_iommu=on iommu=pt"
    else
        grub_params="amd_iommu=on iommu=pt"
    fi

    # Detect GRUB config location
    local grub_file=""
    local grub_update_cmd=""
    local grub_output=""

    if [[ -f /etc/default/grub ]]; then
        grub_file="/etc/default/grub"
        grub_output="/boot/grub2/grub.cfg"
        if command -v grub2-mkconfig &>/dev/null; then
            grub_update_cmd="grub2-mkconfig -o ${grub_output}"
        elif command -v update-grub &>/dev/null; then
            grub_update_cmd="update-grub"
            grub_output="/boot/grub/grub.cfg"
        fi
    elif [[ -f /etc/grub/default ]]; then
        grub_file="/etc/grub/default"
        grub_update_cmd="update-grub"
    fi

    if [[ -z "${grub_file}" ]]; then
        log_warn "GRUB config not found."
        log_info "Please add the following to your kernel boot parameters:"
        log_info "  ${grub_params}"
        return 0
    fi

    log_info "  GRUB config: ${grub_file}"

    # Check current state
    if grep -q "iommu=on\|intel_iommu=on\|amd_iommu=on" "${grub_file}" 2>/dev/null; then
        log_warn "  IOMMU parameters already present in GRUB config."
    else
        if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
            log_info "[DRY RUN] Would append '${grub_params}' to GRUB_CMDLINE_LINUX in ${grub_file}"
        else
            sed -i "s/\(GRUB_CMDLINE_LINUX=\"\)\(.*\)/\1\2 ${grub_params}\"/" "${grub_file}"
            log_info "  Added '${grub_params}' to GRUB_CMDLINE_LINUX."
        fi
    fi

    # Enable kernel modules
    log_info "  Loading vfio-pci module..."
    dry_run modprobe vfio-pci

    log_info "  Making vfio modules persistent..."
    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        local modules_conf="/etc/modules-load.d/vfio.conf"
        mkdir -p /etc/modules-load.d
        cat > "${modules_conf}" <<'MODULES'
vfio
vfio_iommu_type1
vfio_pci
MODULES
        log_info "  Wrote ${modules_conf}"
    fi

    # Update initramfs
    log_info "  Updating initramfs..."
    if command -v update-initramfs &>/dev/null; then
        dry_run update-initramfs -u
    elif command -v dracut &>/dev/null; then
        dry_run dracut --force
    else
        log_warn "  No known initramfs tool found."
    fi

    # Update GRUB
    if [[ -n "${grub_update_cmd}" ]]; then
        log_info "  Updating GRUB..."
        dry_run bash -c "${grub_update_cmd}"
    fi

    # Verify current IOMMU state
    log_info "  Current IOMMU status:"
    if dmesg 2>/dev/null | grep -qi "IOMMU enabled\|DMAR.*IOMMU enabled\|AMD-Vi.*IOMMU enabled"; then
        log_info "  IOMMU is active in the running kernel."
    else
        log_warn "  IOMMU may not be active. Reboot required."
    fi

    log_info "IOMMU setup complete. Reboot for changes to take effect."
}

# ---------------------------------------------------------------------------
# action_status
# ---------------------------------------------------------------------------
action_status() {
    log_info "IOMMU Status:"
    echo ""

    # Check dmesg
    echo "=== IOMMU Detection ==="
    if dmesg 2>/dev/null | grep -qi "IOMMU\|DMAR\|AMD-Vi"; then
        dmesg 2>/dev/null | grep -i "IOMMU\|DMAR\|AMD-Vi" | head -20
    else
        echo "  No IOMMU entries found in dmesg."
    fi
    echo ""

    echo "=== IOMMU Groups ==="
    local group_count=0
    if [[ -d /sys/kernel/iommu_groups ]]; then
        group_count=$(ls -d /sys/kernel/iommu_groups/*/ 2>/dev/null | wc -l)
        echo "  Total IOMMU groups: ${group_count}"
    else
        echo "  /sys/kernel/iommu_groups not found."
        echo "  IOMMU may not be enabled."
    fi
    echo ""

    echo "=== Kernel Parameters ==="
    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
    if echo "${cmdline}" | grep -qi "iommu"; then
        echo "  IOMMU boot parameters: $(echo "${cmdline}" | grep -oi '[a-z_]*iommu[a-z_=]*')"
    else
        echo "  No IOMMU parameters in kernel command line."
    fi
    echo ""

    echo "=== Loaded Modules ==="
    for mod in vfio vfio_iommu_type1 vfio_pci kvm kvm_intel kvm_amd; do
        if lsmod 2>/dev/null | grep -q "^${mod} "; then
            echo "  ${mod}: loaded"
        fi
    done
}

# ---------------------------------------------------------------------------
# action_groups
# ---------------------------------------------------------------------------
action_groups() {
    log_info "IOMMU Groups and Devices:"
    echo ""

    if [[ ! -d /sys/kernel/iommu_groups ]]; then
        log_error "/sys/kernel/iommu_groups not found. IOMMU may not be enabled."
        return 1
    fi

    local group_count=0
    for group_dir in /sys/kernel/iommu_groups/*/; do
        local group_num
        group_num=$(basename "${group_dir}")
        local devices_dir="${group_dir}devices/"

        if [[ ! -d "${devices_dir}" ]]; then
            continue
        fi

        local has_devices=false
        for dev_dir in "${devices_dir}"*/; do
            if [[ -d "${dev_dir}" ]]; then
                has_devices=true
                break
            fi
        done

        if [[ "${has_devices}" == "true" ]]; then
            group_count=$((group_count + 1))
            echo "IOMMU Group ${group_num}:"
            for dev_dir in "${devices_dir}"*/; do
                local bdf
                bdf=$(basename "${dev_dir}")
                local driver="none"
                local driver_path="${dev_dir}/driver"
                if [[ -L "${driver_path}" ]]; then
                    driver=$(readlink "${driver_path}" | xargs basename)
                fi
                local desc
                desc=$(lspci -s "${bdf}" 2>/dev/null | cut -d' ' -f3- || echo "")
                echo "  ${bdf} [${driver}] ${desc}"
            done
            echo ""
        fi
    done

    echo "Total IOMMU groups with devices: ${group_count}"
}

# ---------------------------------------------------------------------------
# action_blacklist_gpu
# ---------------------------------------------------------------------------
action_blacklist_gpu() {
    log_info "Blacklisting GPU drivers for passthrough..."
    check_root

    local drivers="${BLACKLIST_DRIVERS:-nouveau,nvidiafb,amdgpu,radeon}"
    local conf_file="/etc/modprobe.d/blacklist-gpu.conf"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would write blacklist to ${conf_file}:"
        IFS=',' read -ra drv_list <<< "${drivers}"
        for drv in "${drv_list[@]}"; do
            log_info "  blacklist $(echo "${drv}" | xargs)"
        done
        return 0
    fi

    mkdir -p /etc/modprobe.d

    {
        echo "# GPU passthrough blacklist - generated by kvm-iommu-setup.sh"
        echo "# Date: $(date -Iseconds)"
        IFS=',' read -ra drv_list <<< "${drivers}"
        for drv in "${drv_list[@]}"; do
            drv="$(echo "${drv}" | xargs)"
            echo "blacklist ${drv}"
            echo "blacklist ${drv}fb"
        done
    } > "${conf_file}"

    log_info "  Wrote ${conf_file}"

    # Try to unbind GPUs from their current drivers
    log_info "  Looking for GPUs to unbind..."
    lspci -nn 2>/dev/null | grep -iE "VGA|3D|Display" | while IFS= read -r line; do
        local bdf
        bdf=$(echo "${line}" | awk '{print $1}')
        local driver_path="/sys/bus/pci/devices/0000:${bdf}/driver"
        if [[ -L "${driver_path}" ]]; then
            local driver
            driver=$(readlink "${driver_path}" | xargs basename)
            log_info "    ${bdf}: current driver = ${driver}"
            IFS=',' read -ra drv_list <<< "${drivers}"
            for drv in "${drv_list[@]}"; do
                drv="$(echo "${drv}" | xargs)"
                if [[ "${driver}" == "${drv}" ]]; then
                    log_info "    Unbinding ${bdf} from ${driver}..."
                    bash -c "echo '0000:${bdf}' > /sys/bus/pci/devices/0000:${bdf}/driver/unbind" 2>/dev/null || true
                fi
            done
        fi
    done

    # Bind to vfio-pci
    log_info "  Binding GPU devices to vfio-pci..."
    modprobe vfio-pci 2>/dev/null || true

    lspci -nn 2>/dev/null | grep -iE "VGA|3D|Display" | while IFS= read -r line; do
        local bdf
        bdf=$(echo "${line}" | awk '{print $1}')
        local pci_ids
        pci_ids=$(lspci -n -s "${bdf}" 2>/dev/null | awk '{print $2}')
        local vendor product
        vendor=$(echo "${pci_ids}" | cut -d: -f1)
        product=$(echo "${pci_ids}" | cut -d: -f2)

        local driver_path="/sys/bus/pci/devices/0000:${bdf}/driver"
        if [[ ! -L "${driver_path}" ]]; then
            log_info "    Binding ${bdf} (${vendor}:${product}) to vfio-pci..."
            bash -c "echo '${vendor} ${product}' > /sys/bus/pci/drivers/vfio-pci/new_id" 2>/dev/null || true
            bash -c "echo '0000:${bdf}' > /sys/bus/pci/drivers/vfio-pci/bind" 2>/dev/null || true
        fi
    done

    log_info "GPU blacklist applied. Reboot for full effect."
    log_info "  Update initramfs: update-initramfs -u"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs lspci

    case "${ACTION}" in
        enable)         action_enable ;;
        status)         action_status ;;
        groups)         action_groups ;;
        blacklist-gpu)  action_blacklist_gpu ;;
    esac
}

main "$@"
