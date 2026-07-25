#!/usr/bin/env bash
# =============================================================================
# pmx-sriov.sh — SR-IOV NIC management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: detect, enable, create-vfs, assign, status, persistent
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "SR-IOV NIC management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  detect          List SR-IOV capable NICs
  enable          --nic=NAME --num-vfs=N
  create-vfs      --nic=NAME --num-vfs=N
  assign          --vmid=ID --vf-address=PCI [--mac=MAC] [--vlan=ID]
  status          Show all VFs and their assignments
  persistent      --nic=NAME --num-vfs=N  (write udev rules)

DETECT OPTIONS:
  (no additional options)

ENABLE OPTIONS:
  --nic=NAME       Network interface name (required)
  --num-vfs=N      Number of VFs to create (required)

CREATE-VFS OPTIONS:
  --nic=NAME       Network interface name (required)
  --num-vfs=N      Number of VFs to create (required)

ASSIGN OPTIONS:
  --vmid=ID        Target VM (required)
  --vf-address=PCI VF PCI address (required)
  --mac=MAC        MAC address for VF
  --vlan=ID        VLAN tag for VF

STATUS OPTIONS:
  (no additional options)

PERSISTENT OPTIONS:
  --nic=NAME       Network interface (required)
  --num-vfs=N      Number of VFs (required)

OPTIONS:
  --dry-run        Show what would be done
  --help, -h       Show this help

EXAMPLES:
  $(basename "$0") detect
  $(basename "$0") enable --nic=ens192 --num-vfs=8
  $(basename "$0") assign --vmid=100 --vf-address=03:00.2
  $(basename "$0") status
  $(basename "$0") persistent --nic=ens192 --num-vfs=8
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NIC=""
NUM_VFS=""
VMID=""
VF_ADDRESS=""
MAC=""
VLAN=""
NODE="${PMX_NODE:-}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --nic=*)        NIC="${1#*=}" ;;
            --num-vfs=*)    NUM_VFS="${1#*=}" ;;
            --vmid=*)       VMID="${1#*=}" ;;
            --vf-address=*) VF_ADDRESS="${1#*=}" ;;
            --mac=*)        MAC="${1#*=}" ;;
            --vlan=*)       VLAN="${1#*=}" ;;
            --node=*)       NODE="${1#*=}" ;;
            --dry-run)      DRY_RUN=true; shift; continue ;;
            --help|-h)      usage ;;
            -*)             log_error "Unknown option: $1"; usage ;;
            *)              ACTION="$1" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
validate() {
    check_prereqs lspci ip jq
}

# ---------------------------------------------------------------------------
# Get SR-IOV capable NICs
# ---------------------------------------------------------------------------
get_sriov_nics() {
    local -a nics=()
    for dev_path in /sys/class/net/*/device/sriov_totalvfs; do
        if [[ -f "${dev_path}" ]]; then
            local nic_name
            nic_name=$(echo "${dev_path}" | cut -d'/' -f5)
            nics+=("${nic_name}")
        fi
    done
    echo "${nics[@]:-}"
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_detect() {
    log_info "Detecting SR-IOV capable NICs..."
    echo ""

    local found=false
    printf "${BOLD}%-16s %-12s %-12s %-12s %-20s${NC}\n" "NIC" "MAX-VFS" "CUR-VFS" "DRIVER" "PCI"
    printf "%-16s %-12s %-12s %-12s %-20s\n" "---" "-------" "-------" "------" "---"

    for dev_path in /sys/class/net/*/device; do
        [[ -f "${dev_path}/sriov_totalvfs" ]] || continue
        local nic_name
        nic_name=$(basename "$(dirname "${dev_path}")")

        local max_vfs cur_vfs
        max_vfs=$(cat "${dev_path}/sriov_totalvfs" 2>/dev/null || echo "0")
        cur_vfs=$(cat "${dev_path}/sriov_numvfs" 2>/dev/null || echo "0")

        # Only show if SR-IOV capable (max > 0)
        (( max_vfs > 0 )) || continue
        found=true

        local pci_addr
        pci_addr=$(basename "$(readlink -f "${dev_path}")" 2>/dev/null || echo "unknown")
        local driver="none"
        if [[ -d "${dev_path}/driver" ]]; then
            driver=$(readlink "${dev_path}/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
        fi

        printf "%-16s %-12s %-12s %-12s %-20s\n" "${nic_name}" "${max_vfs}" "${cur_vfs}" "${driver}" "${pci_addr}"
    done

    if [[ "${found}" == "false" ]]; then
        log_warn "No SR-IOV capable NICs found."
    fi
}

do_enable() {
    [[ -z "${NIC}" ]] && { log_error "--nic is required."; exit 1; }
    [[ -z "${NUM_VFS}" ]] && { log_error "--num-vfs is required."; exit 1; }

    local dev_path="/sys/class/net/${NIC}/device"
    if [[ ! -f "${dev_path}/sriov_totalvfs" ]]; then
        log_error "NIC '${NIC}' does not support SR-IOV."
        exit 1
    fi

    local max_vfs
    max_vfs=$(cat "${dev_path}/sriov_totalvfs")
    if (( NUM_VFS > max_vfs )); then
        log_error "Requested ${NUM_VFS} VFs, but max is ${max_vfs}."
        exit 1
    fi

    log_info "Enabling SR-IOV on ${NIC} with ${NUM_VFS} VFs..."
    confirm "Enable ${NUM_VFS} VFs on ${NIC}?" || exit 2

    dry_run bash -c "echo ${NUM_VFS} > ${dev_path}/sriov_numvfs"

    # Wait for VFs to appear
    sleep 2

    echo -e "${GREEN}SR-IOV enabled: ${NUM_VFS} VFs created on ${NIC}.${NC}"
}

do_create_vfs() {
    [[ -z "${NIC}" ]] && { log_error "--nic is required."; exit 1; }
    [[ -z "${NUM_VFS}" ]] && { log_error "--num-vfs is required."; exit 1; }

    local dev_path="/sys/class/net/${NIC}/device"
    if [[ ! -f "${dev_path}/sriov_totalvfs" ]]; then
        log_error "NIC '${NIC}' does not support SR-IOV."
        exit 1
    fi

    local max_vfs
    max_vfs=$(cat "${dev_path}/sriov_totalvfs")
    if (( NUM_VFS > max_vfs )); then
        log_error "Requested ${NUM_VFS} VFs, but max is ${max_vfs}."
        exit 1
    fi

    log_info "Creating ${NUM_VFS} VFs on ${NIC}..."
    dry_run bash -c "echo ${NUM_VFS} > ${dev_path}/sriov_numvfs"
    sleep 1
    echo -e "${GREEN}VFs created.${NC}"
}

do_assign() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    [[ -z "${VF_ADDRESS}" ]] && { log_error "--vf-address is required."; exit 1; }

    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi

    # Build hostpci string
    local hostpci_str="${VF_ADDRESS}"
    [[ -n "${VLAN}" ]] && hostpci_str+=",vlan=${VLAN}"

    local payload="{\"hostpci\":\"${hostpci_str}\"}"

    log_info "Assigning VF ${VF_ADDRESS} to VM ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"

    # Set MAC if provided
    if [[ -n "${MAC}" ]]; then
        log_info "Setting MAC ${MAC} for VF..."
        local vf_pci="0000:${VF_ADDRESS}"
        # Find the VF netdev
        for vf_dir in /sys/class/net/*/device/virtfn*; do
            local link
            link=$(readlink "${vf_dir}" 2>/dev/null) || continue
            if echo "${link}" | grep -q "${VF_ADDRESS}"; then
                local netdev
                netdev=$(basename "$(dirname "${vf_dir}")")
                dry_run ip link set "${netdev}" down 2>/dev/null || true
                dry_run ip link set "${netdev}" address "${MAC}" 2>/dev/null || true
                dry_run ip link set "${netdev}" up 2>/dev/null || true
                break
            fi
        done
    fi

    echo -e "${GREEN}VF ${VF_ADDRESS} assigned to VM ${VMID}.${NC}"
}

do_status() {
    log_info "SR-IOV VF status..."
    echo ""

    printf "${BOLD}%-16s %-12s %-14s %-12s${NC}\n" "NIC" "VF-PATH" "PCI" "DRIVER"
    printf "%-16s %-12s %-14s %-12s\n" "---" "--------" "---" "------"

    for nic_path in /sys/class/net/*/device/virtfn*; do
        [[ -d "${nic_path}" ]] || continue
        local nic_name
        nic_name=$(echo "${nic_path}" | cut -d'/' -f5)
        local vf_name
        vf_name=$(basename "${nic_path}")

        local vf_link
        vf_link=$(readlink "${nic_path}" 2>/dev/null) || continue
        local vf_pci
        vf_pci=$(basename "${vf_link}")

        local driver="none"
        local vf_driver_path="/sys/bus/pci/devices/0000:${vf_pci}/driver"
        if [[ -L "${vf_driver_path}" ]]; then
            driver=$(readlink "${vf_driver_path}" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
        fi

        local driver_color="${NC}"
        [[ "${driver}" == "vfio-pci" ]] && driver_color="${GREEN}"

        printf "%-16s %-12s %-14s ${driver_color}%-12s${NC}\n" \
            "${nic_name}" "${vf_name}" "${vf_pci}" "${driver}"
    done
}

do_persistent() {
    [[ -z "${NIC}" ]] && { log_error "--nic is required."; exit 1; }
    [[ -z "${NUM_VFS}" ]] && { log_error "--num-vfs is required."; exit 1; }

    log_info "Creating persistent udev rules for ${NIC} VFs..."
    confirm "Create persistent VF rules for ${NIC}?" || exit 2

    local udev_file="/etc/udev/rules.d/99-sriov-${NIC}.rules"
    local pci_addr
    pci_addr=$(readlink -f "/sys/class/net/${NIC}/device" 2>/dev/null | xargs basename 2>/dev/null)
    if [[ -z "${pci_addr}" ]]; then
        log_error "Could not determine PCI address for ${NIC}."
        exit 1
    fi

    local rule="ACTION==\"add\", SUBSYSTEM==\"net\", KERNEL==\"${NIC}*\", ATTR{device/sriov_numvfs}\"==\"*\", RUN+=\"/bin/bash -c 'echo ${NUM_VFS} > /sys/class/net/${NIC}/device/sriov_numvfs'\""

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        echo "${rule}" > "${udev_file}"
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger --subsystem-match=net 2>/dev/null || true
    fi

    echo -e "${GREEN}Persistent VF rules created at ${udev_file}.${NC}"
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
        detect)     do_detect ;;
        enable)     do_enable ;;
        create-vfs) do_create_vfs ;;
        assign)     do_assign ;;
        status)     do_status ;;
        persistent) do_persistent ;;
        *)          log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
