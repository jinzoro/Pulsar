#!/usr/bin/env bash
# =============================================================================
# pmx-network.sh — Network configuration
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: bridge, bond, vlan, status, apply
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Network configuration"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  bridge-create     --name=NAME [OPTIONS]
  bridge-delete     --name=NAME
  bridge-list       List all bridges
  bond-create       --name=NAME --slaves=DEV1,DEV2 [OPTIONS]
  bond-delete       --name=NAME
  bond-list         List all bonds
  vlan-create       --name=NAME --parent=DEV --vlan-id=ID
  vlan-delete       --name=NAME
  vlan-list         List all VLANs
  status            Show all network interfaces
  apply             Apply pending network changes

BRIDGE OPTIONS:
  --name=NAME       Bridge name (required)
  --ports=DEVS      Bridge port devices (comma-separated)
  --vlan-aware      Enable VLAN filtering
  --mtu=SIZE        MTU size
  --cidr=IP/CIDR    IP address
  --gateway=IP      Gateway IP
  --comments=TEXT   Comment

BOND OPTIONS:
  --name=NAME       Bond name (required)
  --slaves=DEVS     Slave devices (comma-separated, required)
  --mode=MODE       Bond mode: 802.3ad (lacp), active-backup,
                    balance-rr, balance-xor, broadcast (default: active-backup)
  --mtu=SIZE        MTU size
  --cidr=IP/CIDR    IP address
  --gateway=IP      Gateway IP

VLAN OPTIONS:
  --name=NAME       VLAN interface name (required)
  --parent=DEV      Parent interface (required)
  --vlan-id=ID      VLAN ID (required)
  --cidr=IP/CIDR    IP address

OPTIONS:
  --dry-run         Show what would be done
  --help, -h        Show this help

EXAMPLES:
  $(basename "$0") bridge-create --name=vmbr0 --cidr=10.0.0.1/24
  $(basename "$0") bridge-create --name=vmbr1 --ports=ens192 --vlan-aware
  $(basename "$0") bond-create --name=bond0 --slaves=ens192,ens224 --mode=802.3ad
  $(basename "$0") vlan-create --name=ens192.100 --parent=ens192 --vlan-id=100 --cidr=10.0.100.1/24
  $(basename "$0") status
  $(basename "$0") apply
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NAME=""
PORTS=""
SLAVES=""
VLAN_AWARE=false
MTU=""
MODE="active-backup"
PARENT=""
VLAN_ID=""
CIDR=""
GATEWAY=""
COMMENTS=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name=*)       NAME="${1#*=}" ;;
            --ports=*)      PORTS="${1#*=}" ;;
            --slaves=*)     SLAVES="${1#*=}" ;;
            --mode=*)       MODE="${1#*=}" ;;
            --parent=*)     PARENT="${1#*=}" ;;
            --vlan-id=*)    VLAN_ID="${1#*=}" ;;
            --cidr=*)       CIDR="${1#*=}" ;;
            --gateway=*)    GATEWAY="${1#*=}" ;;
            --mtu=*)        MTU="${1#*=}" ;;
            --comments=*)   COMMENTS="${1#*=}" ;;
            --vlan-aware)   VLAN_AWARE=true; shift; continue ;;
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
    check_prereqs curl jq ip
}

# ---------------------------------------------------------------------------
# Write network config to /etc/network/interfaces.d/
# ---------------------------------------------------------------------------
write_ifupdown_config() {
    local name="$1"
    local config="$2"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would write config to /etc/network/interfaces.d/${name}"
        echo "${config}"
        return 0
    fi

    echo "${config}" > "/etc/network/interfaces.d/${name}"
    log_info "Config written to /etc/network/interfaces.d/${name}"
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_bridge_create() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }

    local config="auto ${NAME}\niface ${NAME} inet static\n"
    [[ -n "${CIDR}" ]] && config+="    address ${CIDR}\n"
    [[ -n "${GATEWAY}" ]] && config+="    gateway ${GATEWAY}\n"
    [[ -n "${MTU}" ]] && config+="    mtu ${MTU}\n"

    config+="    bridge-ports ${PORTS:-none}\n"
    [[ "${VLAN_AWARE}" == "true" ]] && config+="    bridge-vlan-aware yes\n    bridge-vids 2-4094\n"
    [[ -n "${COMMENTS}" ]] && config+="    # ${COMMENTS}\n"

    log_info "Creating bridge '${NAME}'..."
    write_ifupdown_config "${NAME}" "$(echo -e "${config}")"
    echo -e "${GREEN}Bridge '${NAME}' created (pending apply).${NC}"
}

do_bridge_delete() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting bridge '${NAME}'..."
    confirm "Delete bridge '${NAME}'?" || exit 2

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        rm -f "/etc/network/interfaces.d/${NAME}"
        dry_run ip link set "${NAME}" down 2>/dev/null || true
        dry_run ip link delete "${NAME}" 2>/dev/null || true
    fi
    echo -e "${GREEN}Bridge '${NAME}' deleted.${NC}"
}

do_bridge_list() {
    log_info "Listing bridges..."
    echo ""
    printf "${BOLD}%-16s %-20s %-8s %-40s${NC}\n" "NAME" "CIDR" "MTU" "PORTS"
    printf "%-16s %-20s %-8s %-40s\n" "----" "----" "---" "-----"

    while IFS= read -r line; do
        local bname bcidr bmtu bports
        bname=$(echo "${line}" | awk '{print $1}')
        bcidr=$(ip -4 addr show "${bname}" 2>/dev/null | grep -oP 'inet \K[\d./]+' | head -1)
        bmtu=$(ip link show "${bname}" 2>/dev/null | grep -oP 'mtu \K\d+')
        bports=$(cat "/sys/class/net/${bname}/bridge/ports" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

        printf "%-16s %-20s %-8s %-40s\n" "${bname}" "${bcidr:-N/A}" "${bmtu:-N/A}" "${bports:-N/A}"
    done < <(brctl show 2>/dev/null | awk 'NR>1 {print $1}' | sort -u)
}

do_bond_create() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${SLAVES}" ]] && { log_error "--slaves is required."; exit 1; }

    local config="auto ${NAME}\niface ${NAME} inet static\n"
    [[ -n "${CIDR}" ]] && config+="    address ${CIDR}\n"
    [[ -n "${GATEWAY}" ]] && config+="    gateway ${GATEWAY}\n"
    [[ -n "${MTU}" ]] && config+="    mtu ${MTU}\n"
    config+="    bond-slaves ${SLAVES}\n"
    config+="    bond-mode ${MODE}\n"

    case "${MODE}" in
        802.3ad)
            config+="    bond-lacp-rate fast\n    bond-xmit-hash-policy layer3+4\n"
            ;;
        balance-xor)
            config+="    bond-xmit-hash-policy layer3+4\n"
            ;;
    esac

    log_info "Creating bond '${NAME}' (mode: ${MODE})..."
    write_ifupdown_config "${NAME}" "$(echo -e "${config}")"
    echo -e "${GREEN}Bond '${NAME}' created (pending apply).${NC}"
}

do_bond_delete() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting bond '${NAME}'..."
    confirm "Delete bond '${NAME}'?" || exit 2

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        rm -f "/etc/network/interfaces.d/${NAME}"
        dry_run ip link set "${NAME}" down 2>/dev/null || true
        dry_run ip link delete "${NAME}" 2>/dev/null || true
    fi
    echo -e "${GREEN}Bond '${NAME}' deleted.${NC}"
}

do_bond_list() {
    log_info "Listing bonds..."
    echo ""
    printf "${BOLD}%-16s %-16s %-20s${NC}\n" "NAME" "MODE" "SLAVES"
    printf "%-16s %-16s %-20s\n" "----" "----" "------"

    for bond_dir in /proc/net/bonding/bond*; do
        [[ -f "${bond_dir}" ]] || continue
        local bname
        bname=$(basename "${bond_dir}")
        local bmode
        bmode=$(grep -oP 'Bonding Mode:\s*\K.*' "${bond_dir}" 2>/dev/null || echo "unknown")
        local bslaves
        bslaves=$(grep -oP 'Slave Interface:\s*\K.*' "${bond_dir}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

        printf "%-16s %-16s %-20s\n" "${bname}" "${bmode}" "${bslaves}"
    done
}

do_vlan_create() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${PARENT}" ]] && { log_error "--parent is required."; exit 1; }
    [[ -z "${VLAN_ID}" ]] && { log_error "--vlan-id is required."; exit 1; }

    local config="auto ${NAME}\niface ${NAME} inet static\n"
    [[ -n "${CIDR}" ]] && config+="    address ${CIDR}\n"
    config+="    vlan-raw-device ${PARENT}\n"

    log_info "Creating VLAN '${NAME}' (parent: ${PARENT}, id: ${VLAN_ID})..."
    write_ifupdown_config "${NAME}" "$(echo -e "${config}")"
    echo -e "${GREEN}VLAN '${NAME}' created (pending apply).${NC}"
}

do_vlan_delete() {
    [[ -z "${NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting VLAN '${NAME}'..."
    confirm "Delete VLAN '${NAME}'?" || exit 2

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        rm -f "/etc/network/interfaces.d/${NAME}"
        dry_run ip link set "${NAME}" down 2>/dev/null || true
        dry_run ip link delete "${NAME}" 2>/dev/null || true
    fi
    echo -e "${GREEN}VLAN '${NAME}' deleted.${NC}"
}

do_vlan_list() {
    log_info "Listing VLANs..."
    echo ""
    printf "${BOLD}%-16s %-12s %-12s %-20s${NC}\n" "NAME" "PARENT" "VLAN-ID" "CIDR"
    printf "%-16s %-12s %-12s %-20s\n" "----" "------" "-------" "----"

    for vlan_dev in /proc/net/vlan/config; do
        [[ -f "${vlan_dev}" ]] || continue
        tail -n +2 "${vlan_dev}" | while IFS='|' read -r vname vparent vid _; do
            vname=$(echo "${vname}" | xargs)
            vparent=$(echo "${vparent}" | xargs)
            vid=$(echo "${vid}" | xargs)
            local vcidr
            vcidr=$(ip -4 addr show "${vname}" 2>/dev/null | grep -oP 'inet \K[\d./]+' | head -1)

            printf "%-16s %-12s %-12s %-20s\n" "${vname}" "${vparent}" "${vid}" "${vcidr:-N/A}"
        done
    done
}

do_status() {
    log_info "Network interface status..."
    echo ""
    ip -brief addr show
    echo ""
    ip -brief link show
    echo ""

    if command -v brctl &>/dev/null; then
        log_info "Bridges:"
        brctl show 2>/dev/null || true
    fi
}

do_apply() {
    log_info "Applying network changes..."
    confirm "Apply network changes? This may cause brief connectivity loss." || exit 2

    if command -v ifreload &>/dev/null; then
        dry_run ifreload -a
    elif command -v systemctl &>/dev/null; then
        dry_run systemctl restart networking
    else
        dry_run /etc/init.d/networking restart
    fi
    echo -e "${GREEN}Network changes applied.${NC}"
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
        bridge-create) do_bridge_create ;;
        bridge-delete) do_bridge_delete ;;
        bridge-list)   do_bridge_list ;;
        bond-create)   do_bond_create ;;
        bond-delete)   do_bond_delete ;;
        bond-list)     do_bond_list ;;
        vlan-create)   do_vlan_create ;;
        vlan-delete)   do_vlan_delete ;;
        vlan-list)     do_vlan_list ;;
        status)        do_status ;;
        apply)         do_apply ;;
        *)             log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
