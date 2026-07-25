#!/usr/bin/env bash
# =============================================================================
# pmx-gpu-passthrough.sh — GPU passthrough setup and management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: detect, enable, configure, assign, verify, blacklist
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "GPU passthrough setup and management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  detect          List available GPUs with IOMMU groups
  enable          Enable IOMMU in GRUB (intel or amd)
  configure       Blacklist drivers, load vfio-pci, set GPU ROM BAR
  assign          --vmid=ID --pci-address=PCI [--rombar] [--x-vga]
  verify          --vmid=ID
  blacklist       List or modify blacklisted drivers
  blacklist-add   --driver=NAME
  blacklist-del   --driver=NAME

ENABLE OPTIONS:
  --intel          Enable Intel IOMMU (intel_iommu=on)
  --amd            Enable AMD IOMMU (amd_iommu=on)

CONFIGURE OPTIONS:
  --pci-address=PCI   GPU PCI address (e.g. 01:00.0)
  --rombar            Enable ROM BAR for GPU
  --vfio-pci          Load vfio-pci module for device

ASSIGN OPTIONS:
  --vmid=ID           Target VM (required)
  --pci-address=PCI   GPU PCI address (required)
  --rombar            Enable ROM BAR
  --x-vga             Enable primary display (x-vga=1)

VERIFY OPTIONS:
  --vmid=ID           VM to check (required)

BLACKLIST OPTIONS:
  --driver=NAME       Driver name (e.g. nouveau, nvidiafb, nvidia)

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") detect
  $(basename "$0") enable --intel
  $(basename "$0") configure --pci-address=01:00.0 --vfio-pci
  $(basename "$0") assign --vmid=100 --pci-address=01:00.0 --x-vga --rombar
  $(basename "$0") verify --vmid=100
  $(basename "$0") blacklist-add --driver=nouveau
  $(basename "$0") blacklist
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
PCI_ADDRESS=""
ROMBAR=false
X_VGA=false
INTEL_IOMMU=false
AMD_IOMMU=false
DRIVER=""
NODE="${PMX_NODE:-}"

# Blacklist defaults
DEFAULT_BLACKLIST_DRIVERS=("nouveau" "nvidiafb" "radeon" "amdgpu")

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)         VMID="${1#*=}" ;;
            --pci-address=*)  PCI_ADDRESS="${1#*=}" ;;
            --driver=*)       DRIVER="${1#*=}" ;;
            --node=*)         NODE="${1#*=}" ;;
            --rombar)         ROMBAR=true; shift; continue ;;
            --x-vga)          X_VGA=true; shift; continue ;;
            --intel)          INTEL_IOMMU=true; shift; continue ;;
            --amd)            AMD_IOMMU=true; shift; continue ;;
            --vfio-pci)       ;;  # Flag only
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
    check_prereqs lspci jq
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_detect() {
    log_info "Detecting GPUs and IOMMU groups..."
    echo ""

    printf "${BOLD}%-12s %-30s %-16s${NC}\n" "IOMMU" "DEVICE" "DRIVER"
    printf "%-12s %-30s %-16s\n" "------" "------" "------"

    # Check IOMMU status
    local iommu_active=false
    if dmesg 2>/dev/null | grep -q "IOMMU enabled\|AMD-Vi\|Intel-IOMMU\|DMAR"; then
        iommu_active=true
    fi
    if [[ -f /sys/kernel/iommu_groups/ ]]; then
        iommu_active=true
    fi

    if [[ "${iommu_active}" == "false" ]]; then
        echo -e "${RED}WARNING: IOMMU does not appear to be enabled.${NC}"
        echo "Run: $(basename "$0") enable --intel or --amd first."
        echo ""
    fi

    # List GPUs (VGA, 3D controllers)
    while IFS= read -r line; do
        local pci_addr device_name
        pci_addr=$(echo "${line}" | awk '{print $1}')
        device_name=$(echo "${line}" | awk -F': ' '{print $2}')

        # Find IOMMU group
        local iommu_group="N/A"
        for group_dir in /sys/kernel/iommu_groups/*/devices/*; do
            if [[ "$(basename "${group_dir}")" == "${pci_addr}" ]]; then
                iommu_group=$(echo "${group_dir}" | cut -d'/' -f5)
                break
            fi
        done

        # Find current driver
        local current_driver="none"
        if [[ -d "/sys/bus/pci/devices/0000:${pci_addr}/driver" ]]; then
            current_driver=$(readlink "/sys/bus/pci/devices/0000:${pci_addr}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
        fi

        printf "%-12s ${CYAN}%-30s${NC} %-16s\n" "${iommu_group}" "${device_name}" "${current_driver}"
    done < <(lspci | grep -iE "vga|3d|display")
}

do_enable() {
    if [[ "${INTEL_IOMMU}" == "false" && "${AMD_IOMMU}" == "false" ]]; then
        log_error "Specify --intel or --amd."
        exit 1
    fi

    log_info "Enabling IOMMU..."
    confirm "Enable IOMMU? This requires modifying GRUB and rebooting." || exit 2

    local grub_file="/etc/default/grub"
    if [[ ! -f "${grub_file}" ]]; then
        log_error "GRUB config not found at ${grub_file}"
        exit 1
    fi

    local iommu_param=""
    if [[ "${INTEL_IOMMU}" == "true" ]]; then
        iommu_param="intel_iommu=on"
    elif [[ "${AMD_IOMMU}" == "true" ]]; then
        iommu_param="amd_iommu=on"
    fi

    local current_grub
    current_grub=$(cat "${grub_file}")

    # Update GRUB_CMDLINE_LINUX_DEFAULT
    if echo "${current_grub}" | grep -q "iommu=on"; then
        log_info "IOMMU already configured in GRUB."
    else
        dry_run sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${iommu_param} iommu=pt\"/" "${grub_file}"
        log_info "GRUB updated with ${iommu_param}."
    fi

    # Enable IOMMU kernel modules
    local modules_file="/etc/modules"
    for mod in vfio vfio_iommu_type1 vfio_pci; do
        if ! grep -q "^${mod}$" "${modules_file}" 2>/dev/null; then
            dry_run bash -c "echo '${mod}' >> ${modules_file}"
            log_info "Added module: ${mod}"
        fi
    done

    # Update GRUB
    dry_run update-grub

    log_warn "IOMMU enabled. REBOOT REQUIRED for changes to take effect."
    echo -e "${GREEN}IOMMU configured. Reboot to activate.${NC}"
}

do_configure() {
    [[ -z "${PCI_ADDRESS}" ]] && { log_error "--pci-address is required."; exit 1; }

    log_info "Configuring GPU passthrough for ${PCI_ADDRESS}..."

    # Blacklist default GPU drivers
    local blacklist_file="/etc/modprobe.d/pve-gpu-blacklist.conf"
    log_info "Blacklisting GPU drivers..."
    for drv in "${DEFAULT_BLACKLIST_DRIVERS[@]}"; do
        if ! grep -q "blacklist ${drv}" "${blacklist_file}" 2>/dev/null; then
            dry_run bash -c "echo 'blacklist ${drv}' >> ${blacklist_file}"
            log_info "Blacklisted: ${drv}"
        fi
    done

    # Load vfio-pci
    local vfio_conf="/etc/modprobe.d/pve-vfio.conf"
    log_info "Configuring vfio-pci for ${PCI_ADDRESS}..."
    local vfio_line="options vfio-pci ids=${PCI_ADDRESS}"
    if ! grep -q "${PCI_ADDRESS}" "${vfio_conf}" 2>/dev/null; then
        dry_run bash -c "echo '${vfio_line}' > ${vfio_conf}"
    fi

    # Ensure vfio modules load early
    local initramfs_modules="/etc/initramfs-tools/modules"
    for mod in vfio vfio_iommu_type1 vfio_pci; do
        if ! grep -q "^${mod}$" "${initramfs_modules}" 2>/dev/null; then
            dry_run bash -c "echo '${mod}' >> ${initramfs_modules}"
        fi
    done

    # Update initramfs
    dry_run update-initramfs -u

    echo -e "${GREEN}GPU passthrough configured for ${PCI_ADDRESS}. Reboot required.${NC}"
}

do_assign() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${PCI_ADDRESS}" ]] && { log_error "--pci-address is required."; exit 1; }

    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi

    local full_pci="0000:${PCI_ADDRESS}"
    local hostpci="${PCI_ADDRESS}"

    local payload
    payload=$(jq -n --arg pci "${hostpci}" '{"hostpci": $pci}')
    [[ "${ROMBAR}" == "true" ]] && payload=$(echo "${payload}" | jq -c '.hostpci = (.hostpci + ",rombar=1")')
    [[ "${X_VGA}" == "true" ]] && payload=$(echo "${payload}" | jq -c '.hostpci = (.hostpci + ",x-vga=1")')

    # Build hostpci string properly
    local hostpci_str="${hostpci}"
    [[ "${ROMBAR}" == "true" ]] && hostpci_str+=",rombar=1"
    [[ "${X_VGA}" == "true" ]] && hostpci_str+=",x-vga=1"

    payload="{\"hostpci\":\"${hostpci_str}\"}"

    log_info "Assigning PCI device ${PCI_ADDRESS} to VM ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"
    echo -e "${GREEN}GPU ${PCI_ADDRESS} assigned to VM ${VMID}.${NC}"
}

do_verify() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi

    log_info "Verifying GPU passthrough for VM ${VMID}..."
    echo ""

    local config
    config=$(api_call GET "/nodes/${NODE}/qemu/${VMID}/config" 2>/dev/null) || {
        log_error "Could not fetch VM config."
        return 1
    }

    local hostpci
    hostpci=$(parse_json "${config}" ".data.hostpci // empty")
    if [[ -z "${hostpci}" ]]; then
        log_warn "No PCI device assigned to VM ${VMID}."
        return 1
    fi

    printf "${BOLD}%-20s %-30s${NC}\n" "Property" "Value"
    printf "%-20s %-30s\n" "--------" "-----"
    printf "%-20s %-30s\n" "Host PCI" "${hostpci}"

    local pci_addr="${hostpci%%,*}"
    local iommu_group="N/A"
    for group_dir in /sys/kernel/iommu_groups/*/devices/*; do
        if [[ "$(basename "${group_dir}")" == "${pci_addr}" ]]; then
            iommu_group=$(echo "${group_dir}" | cut -d'/' -f5)
            break
        fi
    done
    printf "%-20s %-30s\n" "IOMMU Group" "${iommu_group}"

    local driver="none"
    if [[ -d "/sys/bus/pci/devices/0000:${pci_addr}/driver" ]]; then
        driver=$(readlink "/sys/bus/pci/devices/0000:${pci_addr}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
    fi
    printf "%-20s %-30s\n" "Driver" "${driver}"

    if [[ "${driver}" == "vfio-pci" ]]; then
        echo -e "\n${GREEN}GPU passthrough appears properly configured.${NC}"
    else
        echo -e "\n${YELLOW}Driver is '${driver}', expected 'vfio-pci'. GPU may not be properly bound.${NC}"
    fi
}

do_blacklist() {
    log_info "Current GPU driver blacklist:"
    echo ""
    local blacklist_file="/etc/modprobe.d/pve-gpu-blacklist.conf"
    if [[ -f "${blacklist_file}" ]]; then
        cat "${blacklist_file}"
    else
        log_info "No blacklist file found."
    fi
}

do_blacklist_add() {
    [[ -z "${DRIVER}" ]] && { log_error "--driver is required."; exit 1; }
    local blacklist_file="/etc/modprobe.d/pve-gpu-blacklist.conf"

    if grep -q "blacklist ${DRIVER}" "${blacklist_file}" 2>/dev/null; then
        log_info "Driver '${DRIVER}' is already blacklisted."
        return 0
    fi

    log_info "Blacklisting driver '${DRIVER}'..."
    dry_run bash -c "echo 'blacklist ${DRIVER}' >> ${blacklist_file}"
    echo -e "${GREEN}Driver '${DRIVER}' blacklisted.${NC}"
}

do_blacklist_del() {
    [[ -z "${DRIVER}" ]] && { log_error "--driver is required."; exit 1; }
    local blacklist_file="/etc/modprobe.d/pve-gpu-blacklist.conf"

    if [[ ! -f "${blacklist_file}" ]]; then
        log_warn "No blacklist file found."
        return 0
    fi

    log_info "Removing '${DRIVER}' from blacklist..."
    dry_run sed -i "/blacklist ${DRIVER}/d" "${blacklist_file}"
    echo -e "${GREEN}Driver '${DRIVER}' removed from blacklist.${NC}"
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
        detect)         do_detect ;;
        enable)         do_enable ;;
        configure)      do_configure ;;
        assign)         do_assign ;;
        verify)         do_verify ;;
        blacklist)      do_blacklist ;;
        blacklist-add)  do_blacklist_add ;;
        blacklist-del)  do_blacklist_del ;;
        *)              log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
