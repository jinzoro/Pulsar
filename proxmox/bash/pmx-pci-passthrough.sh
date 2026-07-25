#!/usr/bin/env bash
# =============================================================================
# pmx-pci-passthrough.sh — PCI device passthrough
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: list, groups, bind, assign, verify, unbind, override
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "PCI device passthrough"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  list            List all PCI devices with driver info
  groups          Show IOMMU groups and devices
  bind            --device=PCI --driver=DRIVER
  unbind          --device=PCI
  assign          --vmid=ID --pci-address=PCI [OPTIONS]
  verify          --vmid=ID
  override        Enable ACS override for all functions

LIST OPTIONS:
  --filter=EXPR    Filter devices by expression (e.g. "net", "nvme")

BIND OPTIONS:
  --device=PCI     PCI address (e.g. 01:00.0) (required)
  --driver=DRIVER  Driver to bind (default: vfio-pci)

ASSIGN OPTIONS:
  --vmid=ID        Target VM (required)
  --pci-address=PCI  PCI address (required)
  --pcie           Use PCIe (pcie=1)

VERIFY OPTIONS:
  --vmid=ID        VM to check (required)

OPTIONS:
  --dry-run        Show what would be done
  --help, -h       Show this help

EXAMPLES:
  $(basename "$0") list
  $(basename "$0") list --filter=net
  $(basename "$0") groups
  $(basename "$0") bind --device=01:00.0 --driver=vfio-pci
  $(basename "$0") assign --vmid=100 --pci-address=01:00.0 --pcie
  $(basename "$0") verify --vmid=100
  $(basename "$0") unbind --device=01:00.0
  $(basename "$0") override
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
PCI_ADDRESS=""
DRIVER="vfio-pci"
FILTER=""
PCIE=false
NODE="${PMX_NODE:-}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)         VMID="${1#*=}" ;;
            --pci-address=*)  PCI_ADDRESS="${1#*=}" ;;
            --device=*)       PCI_ADDRESS="${1#*=}" ;;
            --driver=*)       DRIVER="${1#*=}" ;;
            --filter=*)       FILTER="${1#*=}" ;;
            --node=*)         NODE="${1#*=}" ;;
            --pcie)           PCIE=true; shift; continue ;;
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
do_list() {
    log_info "Listing PCI devices..."
    echo ""

    printf "${BOLD}%-12s %-40s %-20s %-16s${NC}\n" "PCI ADDR" "DEVICE" "DRIVER" "IOMMU GROUP"
    printf "%-12s %-40s %-20s %-16s\n" "---------" "------" "------" "-----------"

    while IFS= read -r line; do
        local pci_addr device_name
        pci_addr=$(echo "${line}" | awk '{print $1}')
        device_name=$(echo "${line}" | cut -d' ' -f2-)

        # Apply filter
        if [[ -n "${FILTER}" ]]; then
            echo "${device_name}" | grep -qi "${FILTER}" || continue
        fi

        # Find driver
        local current_driver="none"
        if [[ -d "/sys/bus/pci/devices/0000:${pci_addr}/driver" ]]; then
            current_driver=$(readlink "/sys/bus/pci/devices/0000:${pci_addr}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
        fi

        # Find IOMMU group
        local iommu_group="N/A"
        for group_dir in /sys/kernel/iommu_groups/*/devices/*; do
            if [[ "$(basename "${group_dir}")" == "${pci_addr}" ]]; then
                iommu_group=$(echo "${group_dir}" | cut -d'/' -f5)
                break
            fi
        done

        local driver_color="${NC}"
        [[ "${current_driver}" == "vfio-pci" ]] && driver_color="${GREEN}"

        printf "%-12s ${CYAN}%-40s${NC} ${driver_color}%-20s${NC} %-16s\n" \
            "${pci_addr}" "${device_name}" "${current_driver}" "${iommu_group}"
    done < <(lspci -D | grep -iE "^[0-9]")
}

do_groups() {
    log_info "Listing IOMMU groups..."
    echo ""

    local groups_dir="/sys/kernel/iommu_groups"
    if [[ ! -d "${groups_dir}" ]]; then
        log_error "IOMMU groups not found. Is IOMMU enabled?"
        return 1
    fi

    for group_dir in "${groups_dir}"/*/; do
        [[ -d "${group_dir}/devices" ]] || continue
        local group_num
        group_num=$(basename "${group_dir}")
        local devices
        devices=$(ls "${group_dir}/devices" 2>/dev/null)
        [[ -z "${devices}" ]] && continue

        echo -e "${BOLD}IOMMU Group ${group_num}:${NC}"
        while IFS= read -r dev; do
            local pci_addr
            pci_addr=$(basename "${dev}")
            local device_name
            device_name=$(lspci -s "${pci_addr}" 2>/dev/null | cut -d' ' -f2-)
            local current_driver="none"
            if [[ -d "${dev}/driver" ]]; then
                current_driver=$(readlink "${dev}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
            fi
            printf "  %-12s %-40s [%s]\n" "${pci_addr}" "${device_name}" "${current_driver}"
        done <<< "${devices}"
        echo ""
    done
}

do_bind() {
    [[ -z "${PCI_ADDRESS}" ]] && { log_error "--device is required."; exit 1; }

    log_info "Binding PCI device ${PCI_ADDRESS} to ${DRIVER}..."

    # Check if device exists
    if [[ ! -d "/sys/bus/pci/devices/0000:${PCI_ADDRESS}" ]]; then
        log_error "PCI device ${PCI_ADDRESS} not found."
        exit 1
    fi

    local current_driver
    current_driver=$(readlink "/sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")

    if [[ "${current_driver}" == "${DRIVER}" ]]; then
        log_info "Device already bound to ${DRIVER}."
        return 0
    fi

    # Unbind from current driver
    if [[ "${current_driver}" != "none" ]]; then
        log_info "Unbinding from ${current_driver}..."
        dry_run bash -c "echo '0000:${PCI_ADDRESS}' > /sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver/unbind" 2>/dev/null || true
    fi

    # Bind to target driver
    if [[ "${DRIVER}" == "vfio-pci" ]]; then
        # Ensure vfio-pci is loaded
        dry_run modprobe vfio-pci 2>/dev/null || true
    fi

    dry_run bash -c "echo '${DRIVER}' > /sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver_override"
    dry_run bash -c "echo '0000:${PCI_ADDRESS}' > /sys/bus/pci/drivers/${DRIVER}/bind"

    echo -e "${GREEN}Device ${PCI_ADDRESS} bound to ${DRIVER}.${NC}"
}

do_unbind() {
    [[ -z "${PCI_ADDRESS}" ]] && { log_error "--device is required."; exit 1; }

    log_info "Unbinding PCI device ${PCI_ADDRESS}..."

    local current_driver
    current_driver=$(readlink "/sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")

    if [[ "${current_driver}" == "none" ]]; then
        log_info "Device is not bound to any driver."
        return 0
    fi

    dry_run bash -c "echo '0000:${PCI_ADDRESS}' > /sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver/unbind"
    dry_run bash -c "echo '' > /sys/bus/pci/devices/0000:${PCI_ADDRESS}/driver_override"

    echo -e "${GREEN}Device ${PCI_ADDRESS} unbound.${NC}"
}

do_assign() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${PCI_ADDRESS}" ]] && { log_error "--pci-address is required."; exit 1; }

    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi

    local hostpci_str="${PCI_ADDRESS}"
    [[ "${PCIE}" == "true" ]] && hostpci_str+=",pcie=1"

    local payload="{\"hostpci\":\"${hostpci_str}\"}"

    log_info "Assigning PCI device ${PCI_ADDRESS} to VM ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"
    echo -e "${GREEN}PCI device ${PCI_ADDRESS} assigned to VM ${VMID}.${NC}"
}

do_verify() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi

    log_info "Verifying PCI passthrough for VM ${VMID}..."
    echo ""

    local config
    config=$(api_call GET "/nodes/${NODE}/qemu/${VMID}/config" 2>/dev/null) || {
        log_error "Could not fetch VM config."; return 1
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
    local driver="none"
    if [[ -d "/sys/bus/pci/devices/0000:${pci_addr}/driver" ]]; then
        driver=$(readlink "/sys/bus/pci/devices/0000:${pci_addr}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
    fi
    printf "%-20s %-30s\n" "Driver" "${driver}"

    if [[ "${driver}" == "vfio-pci" ]]; then
        echo -e "\n${GREEN}PCI passthrough properly configured.${NC}"
    else
        echo -e "\n${YELLOW}Driver is '${driver}', expected 'vfio-pci'.${NC}"
    fi
}

do_override() {
    log_info "Enabling ACS override..."
    confirm "Enable ACS override? This modifies kernel parameters." || exit 2

    local grub_file="/etc/default/grub"
    local grub_cfg="/etc/modprobe.d/pve-acs-override.conf"

    if [[ -f "${grub_cfg}" ]] && grep -q "pcie_acs_override" "${grub_cfg}" 2>/dev/null; then
        log_info "ACS override already configured."
        return 0
    fi

    # Add GRUB parameter
    if [[ -f "${grub_file}" ]]; then
        dry_run sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 pcie_acs_override=downstream,multifunction"/' "${grub_file}"
    fi

    # Add modprobe option
    dry_run bash -c "echo 'options vfio-pci enable_unsafe_no_iommu_mode=1' > ${grub_cfg}"

    dry_run update-grub
    echo -e "${GREEN}ACS override enabled. Reboot required.${NC}"
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
        list)     do_list ;;
        groups)   do_groups ;;
        bind)     do_bind ;;
        unbind)   do_unbind ;;
        assign)   do_assign ;;
        verify)   do_verify ;;
        override) do_override ;;
        *)        log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
