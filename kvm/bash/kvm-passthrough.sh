#!/usr/bin/env bash
# =============================================================================
# kvm-passthrough.sh - Device passthrough (GPU, PCI, USB) for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: detect, iommu-groups, bind, unbind, assign, verify, usb,
#             enable-iommu
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
PCI_DEVICE=""
DOMAIN=""
VENDOR_ID=""
PRODUCT_ID=""
VENDOR=""
GRUB_CONFIG="/etc/default/grub"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-passthrough.sh" "Device passthrough (GPU, PCI, USB) for KVM"
    cat <<'HEADER'
Usage: kvm-passthrough.sh [OPTIONS] <ACTION>

 ACTIONS:
   detect          List PCI devices with driver and IOMMU group
   iommu-groups    Show all IOMMU groups and their devices
   bind            Bind a PCI device to vfio-pci
   unbind          Unbind a PCI device from vfio-pci
   assign          Assign a PCI device to a VM
   verify          Verify passthrough is working for a domain
   usb             List USB devices / assign USB to a VM
   enable-iommu    Enable IOMMU in GRUB and update initramfs
HEADER
    cat <<EOF

 DETECT / IOMMU-GROUPS:
   No additional flags required.

 BIND / UNBIND:
   --device <BDF>               PCI bus:device.function address (e.g. 01:00.0)

 ASSIGN:
   --domain <name>              VM domain name (required)
   --device <BDF>               PCI bus:device.function address (required)

 VERIFY:
   --domain <name>              VM domain name (required)

 USB:
   --domain <name>              VM domain name (required)
   --vendor-id <id>             USB vendor ID (e.g. 1234) for assign
   --product-id <id>            USB product ID (e.g. 5678) for assign
   Without --vendor-id/--product-id, lists USB devices.

 ENABLE-IOMMU:
   --vendor <intel|amd>         CPU vendor (required)

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-passthrough.sh detect
   kvm-passthrough.sh iommu-groups
   kvm-passthrough.sh bind --device 01:00.0
   kvm-passthrough.sh assign --domain gaming-vm --device 01:00.0
   kvm-passthrough.sh usb
   kvm-passthrough.sh usb --domain printer-vm --vendor-id 04b8 --product-id 0005
   kvm-passthrough.sh enable-iommu --vendor intel
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
            detect|iommu-groups|bind|unbind|assign|verify|usb|enable-iommu)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --device)
                PCI_DEVICE="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --vendor-id)
                VENDOR_ID="$2"
                shift 2
                ;;
            --product-id)
                PRODUCT_ID="$2"
                shift 2
                ;;
            --vendor)
                VENDOR="$2"
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
        bind|unbind)
            if [[ -z "${PCI_DEVICE}" ]]; then
                log_error "${ACTION} requires --device"
                exit 2
            fi
            ;;
        assign)
            if [[ -z "${DOMAIN}" || -z "${PCI_DEVICE}" ]]; then
                log_error "assign requires --domain and --device"
                exit 2
            fi
            ;;
        verify)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "verify requires --domain"
                exit 2
            fi
            ;;
        usb)
            if [[ -n "${VENDOR_ID}" && -z "${DOMAIN}" ]]; then
                log_error "usb assign requires --domain"
                exit 2
            fi
            ;;
        enable-iommu)
            if [[ -z "${VENDOR}" ]]; then
                log_error "enable-iommu requires --vendor (intel or amd)"
                exit 2
            fi
            ;;
        detect|iommu-groups)
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# get_iommu_group
# ---------------------------------------------------------------------------
get_iommu_group() {
    local bdf="$1"
    local sysfs_path="/sys/bus/pci/devices/0000:${bdf}/iommu_group"
    if [[ -d "${sysfs_path}" ]]; then
        readlink "${sysfs_path}" 2>/dev/null | grep -oP '\d+$' || echo "unknown"
    else
        echo "none"
    fi
}

# ---------------------------------------------------------------------------
# get_driver
# ---------------------------------------------------------------------------
get_driver() {
    local bdf="$1"
    local driver_path="/sys/bus/pci/devices/0000:${bdf}/driver"
    if [[ -L "${driver_path}" ]]; then
        readlink "${driver_path}" 2>/dev/null | xargs basename || echo "none"
    else
        echo "none"
    fi
}

# ---------------------------------------------------------------------------
# get_pci_device_info
# ---------------------------------------------------------------------------
get_pci_device_info() {
    local bdf="$1"
    local class_code
    class_code=$(lspci -n -s "${bdf}" 2>/dev/null | awk '{print $3}' || echo "0000")
    local desc
    desc=$(lspci -s "${bdf}" 2>/dev/null | cut -d' ' -f3- || echo "unknown")
    local driver
    driver=$(get_driver "${bdf}")
    local iommu
    iommu=$(get_iommu_group "${bdf}")
    echo "${bdf} | ${class_code} | ${driver} | IOMMU:${iommu} | ${desc}"
}

# ---------------------------------------------------------------------------
# action_detect
# ---------------------------------------------------------------------------
action_detect() {
    log_info "Detecting PCI devices..."
    echo ""
    printf "%-12s %-10s %-14s %-12s %s\n" "BDF" "CLASS" "DRIVER" "IOMMU" "DESCRIPTION"
    printf "%-12s %-10s %-14s %-12s %s\n" "------------" "----------" "--------------" "------------" "--------------------"

    lspci -Dn 2>/dev/null | grep -E "^[0-9a-f]" | while IFS= read -r line; do
        local bdf class_code vendor_prod
        bdf=$(echo "${line}" | awk '{print $1}')
        class_code=$(echo "${line}" | awk '{print $3}')
        vendor_prod=$(echo "${line}" | awk '{print $2}')

        local driver
        driver=$(get_driver "${bdf}")
        local iommu
        iommu=$(get_iommu_group "${bdf}")
        local desc
        desc=$(lspci -s "${bdf}" 2>/dev/null | cut -d' ' -f3- || echo "")

        printf "%-12s %-10s %-14s %-12s %s\n" "${bdf}" "${class_code}" "${driver}" "group:${iommu}" "${desc}"
    done
}

# ---------------------------------------------------------------------------
# action_iommu_groups
# ---------------------------------------------------------------------------
action_iommu_groups() {
    log_info "IOMMU groups and their devices:"
    echo ""

    local -A groups
    local max_group=0

    while IFS= read -r bdf; do
        local group
        group=$(get_iommu_group "${bdf}")
        if [[ "${group}" != "none" && "${group}" != "unknown" ]]; then
            if (( group > max_group )); then
                max_group=${group}
            fi
            groups["${group}"]+="${bdf} "
        fi
    done < <(lspci -Dn 2>/dev/null | awk '{print $1}')

    local i
    for (( i=0; i<=max_group; i++ )); do
        if [[ -n "${groups[${i}]:-}" ]]; then
            echo -e "${BOLD}IOMMU Group ${i}:${NC}"
            for bdf in ${groups[${i}]}; do
                local desc
                desc=$(lspci -s "${bdf}" 2>/dev/null | cut -d' ' -f3-)
                local driver
                driver=$(get_driver "${bdf}")
                echo "  ${bdf} [${driver}] ${desc}"
            done
            echo ""
        fi
    done
}

# ---------------------------------------------------------------------------
# action_bind
# ---------------------------------------------------------------------------
action_bind() {
    log_info "Binding PCI device ${PCI_DEVICE} to vfio-pci..."

    local current_driver
    current_driver=$(get_driver "${PCI_DEVICE}")

    if [[ "${current_driver}" == "vfio-pci" ]]; then
        log_warn "Device ${PCI_DEVICE} is already bound to vfio-pci."
        return 0
    fi

    if [[ "${current_driver}" != "none" ]]; then
        log_info "  Current driver: ${current_driver}"
        log_info "  Unbinding from ${current_driver}..."
        dry_run bash -c "echo '0000:${PCI_DEVICE}' > /sys/bus/pci/devices/0000:${PCI_DEVICE}/driver/unbind"
    fi

    local pci_ids
    pci_ids=$(lspci -n -s "${PCI_DEVICE}" 2>/dev/null | awk '{print $2}' | tr ':' ' ')
    local vendor product
    vendor=$(echo "${pci_ids}" | awk '{print $1}')
    product=$(echo "${pci_ids}" | awk '{print $2}')

    log_info "  Loading vfio-pci..."
    dry_run modprobe vfio-pci

    log_info "  Binding to vfio-pci (vendor=${vendor} device=${product})..."
    dry_run bash -c "echo '${vendor} ${product}' > /sys/bus/pci/drivers/vfio-pci/new_id"
    dry_run bash -c "echo '0000:${PCI_DEVICE}' > /sys/bus/pci/drivers/vfio-pci/bind" 2>/dev/null || true

    log_info "Device ${PCI_DEVICE} bound to vfio-pci."

    if [[ "${current_driver}" != "none" ]]; then
        log_info "  To make this persistent, blacklist '${current_driver}' in /etc/modprobe.d/"
    fi
}

# ---------------------------------------------------------------------------
# action_unbind
# ---------------------------------------------------------------------------
action_unbind() {
    log_info "Unbinding PCI device ${PCI_DEVICE} from vfio-pci..."

    local current_driver
    current_driver=$(get_driver "${PCI_DEVICE}")

    if [[ "${current_driver}" != "vfio-pci" ]]; then
        log_warn "Device ${PCI_DEVICE} is not bound to vfio-pci (current: ${current_driver})."
        return 0
    fi

    dry_run bash -c "echo '0000:${PCI_DEVICE}' > /sys/bus/pci/drivers/vfio-pci/unbind"

    local pci_ids
    pci_ids=$(lspci -n -s "${PCI_DEVICE}" 2>/dev/null | awk '{print $2}')
    local vendor product
    vendor=$(echo "${pci_ids}" | cut -d: -f1)
    product=$(echo "${pci_ids}" | cut -d: -f2)

    dry_run bash -c "echo '${vendor} ${product}' > /sys/bus/pci/drivers/vfio-pci/remove_id" 2>/dev/null || true

    dry_run bash -c "echo '0000:${PCI_DEVICE}' > /sys/bus/pci/rescan"

    log_info "Device ${PCI_DEVICE} unbound. Kernel should re-bind original driver."
}

# ---------------------------------------------------------------------------
# action_assign
# ---------------------------------------------------------------------------
action_assign() {
    log_info "Assigning PCI device ${PCI_DEVICE} to domain '${DOMAIN}'..."

    local pci_ids
    pci_ids=$(lspci -n -s "${PCI_DEVICE}" 2>/dev/null | awk '{print $2}')
    local vendor product
    vendor=$(echo "${pci_ids}" | cut -d: -f1)
    product=$(echo "${pci_ids}" | cut -d: -f2)

    local hostdev_xml
    hostdev_xml="<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x$(echo "${PCI_DEVICE}" | cut -d: -f1)' slot='0x$(echo "${PCI_DEVICE}" | cut -d. -f1 | cut -d: -f2)' function='0x$(echo "${PCI_DEVICE}" | cut -d. -f2)'/>
  </source>
</hostdev>"

    log_debug "Hostdev XML: ${hostdev_xml}"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] virsh -c ${CONNECT_URI} attach-device ${DOMAIN} --file <hostdev.xml> --persistent"
        return 0
    fi

    local tmpxml
    tmpxml=$(create_temp_file)
    echo "${hostdev_xml}" > "${tmpxml}"

    virsh -c "${CONNECT_URI}" attach-device "${DOMAIN}" --file "${tmpxml}" --persistent || {
        log_error "Failed to attach device ${PCI_DEVICE} to ${DOMAIN}."
        return 1
    }

    log_info "Device ${PCI_DEVICE} assigned to domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_verify
# ---------------------------------------------------------------------------
action_verify() {
    log_info "Verifying passthrough for domain '${DOMAIN}'..."

    echo ""
    echo "Domain: ${DOMAIN}"
    echo "--------"

    local state
    state=$(virsh -c "${CONNECT_URI}" domstate "${DOMAIN}" 2>/dev/null || echo "unknown")
    echo "State: ${state}"

    echo ""
    echo "PCI Host Devices:"
    virsh -c "${CONNECT_URI}" nodedev-list --cap pci 2>/dev/null | head -20 || echo "  (none)"

    echo ""
    echo "Domain XML (hostdev section):"
    virsh -c "${CONNECT_URI}" dumpxml "${DOMAIN}" 2>/dev/null | grep -A 10 "hostdev" || echo "  (no hostdev devices)"

    echo ""
    log_info "Verify complete."
}

# ---------------------------------------------------------------------------
# action_usb
# ---------------------------------------------------------------------------
action_usb() {
    if [[ -z "${VENDOR_ID}" ]]; then
        log_info "Listing USB devices:"
        echo ""
        printf "%-10s %-10s %-50s\n" "VENDOR" "PRODUCT" "DESCRIPTION"
        printf "%-10s %-10s %-50s\n" "------" "-------" "--------------------"
        lsusb 2>/dev/null | while IFS= read -r line; do
            local vid pid desc
            vid=$(echo "${line}" | awk '{print $2}')
            pid=$(echo "${line}" | awk '{print $4}' | tr -d ':')
            desc=$(echo "${line}" | cut -d' ' -f6-)
            printf "%-10s %-10s %-50s\n" "${vid}" "${pid}" "${desc}"
        done
        return 0
    fi

    log_info "Assigning USB ${VENDOR_ID}:${PRODUCT_ID} to domain '${DOMAIN}'..."

    local usb_xml
    usb_xml="<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x${VENDOR_ID}'/>
    <product id='0x${PRODUCT_ID}'/>
  </source>
</hostdev>"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] virsh -c ${CONNECT_URI} attach-device ${DOMAIN} --file <usb.xml> --persistent"
        return 0
    fi

    local tmpxml
    tmpxml=$(create_temp_file)
    echo "${usb_xml}" > "${tmpxml}"

    virsh -c "${CONNECT_URI}" attach-device "${DOMAIN}" --file "${tmpxml}" --persistent || {
        log_error "Failed to attach USB device to ${DOMAIN}."
        return 1
    }

    log_info "USB device ${VENDOR_ID}:${PRODUCT_ID} assigned to domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_enable_iommu
# ---------------------------------------------------------------------------
action_enable_iommu() {
    log_info "Enabling IOMMU for ${VENDOR} CPU..."

    check_root

    local grub_param
    if [[ "${VENDOR,,}" == "intel" ]]; then
        grub_param="intel_iommu=on iommu=pt"
    elif [[ "${VENDOR,,}" == "amd" ]]; then
        grub_param="amd_iommu=on iommu=pt"
    else
        log_error "Invalid vendor: ${VENDOR}. Must be 'intel' or 'amd'."
        exit 2
    fi

    local grub_file="/etc/default/grub"
    if [[ ! -f "${grub_file}" ]]; then
        log_warn "GRUB config not found at ${grub_file}."
        log_info "Ensure boot parameters include: ${grub_param}"
        return 0
    fi

    log_info "Current GRUB_CMDLINE_LINUX:"
    grep "^GRUB_CMDLINE_LINUX" "${grub_file}" || true

    if grep -q "iommu=on\|intel_iommu=on\|amd_iommu=on" "${grub_file}" 2>/dev/null; then
        log_warn "IOMMU parameter already present in GRUB config."
    else
        if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
            log_info "[DRY RUN] Would append '${grub_param}' to GRUB_CMDLINE_LINUX"
        else
            sed -i "s/\(GRUB_CMDLINE_LINUX=\"\)\(.*\)/\1\2 ${grub_param}\"/" "${grub_file}"
            log_info "Added '${grub_param}' to GRUB_CMDLINE_LINUX."
        fi
    fi

    log_info "Updating initramfs..."
    if command -v update-initramfs &>/dev/null; then
        dry_run update-initramfs -u
    elif command -v dracut &>/dev/null; then
        dry_run dracut --force
    else
        log_warn "No known initramfs tool found. Update initramfs manually."
    fi

    log_info "Updating GRUB..."
    if command -v grub2-mkconfig &>/dev/null; then
        dry_run grub2-mkconfig -o /boot/grub2/grub.cfg
    elif command -v update-grub &>/dev/null; then
        dry_run update-grub
    fi

    log_info "IOMMU enabled. Reboot required for changes to take effect."
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
        detect)        action_detect ;;
        iommu-groups)  action_iommu_groups ;;
        bind)          action_bind ;;
        unbind)        action_unbind ;;
        assign)        action_assign ;;
        verify)        action_verify ;;
        usb)           action_usb ;;
        enable-iommu)  action_enable_iommu ;;
    esac
}

main "$@"
