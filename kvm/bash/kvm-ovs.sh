#!/usr/bin/env bash
# =============================================================================
# kvm-ovs.sh - Open vSwitch integration for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: create-bridge, delete-bridge, add-port, delete-port, list,
#             vxlan, bond
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
OVS_BRIDGE=""
PORT_NAME=""
VLAN_TAG=""
TRUNK_TAGS=""
LOCAL_IP=""
REMOTE_IP=""
VNI=""
BOND_NAME=""
SLAVES=""
BOND_MODE="lacp"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-ovs.sh" "Open vSwitch integration for KVM"
    cat <<'HEADER'
Usage: kvm-ovs.sh [OPTIONS] <ACTION>

 ACTIONS:
   create-bridge    Create an OVS bridge
   delete-bridge    Delete an OVS bridge
   add-port         Add a port to an OVS bridge
   delete-port      Delete a port from an OVS bridge
   list             List all OVS bridges and ports
   vxlan            Create a VXLAN tunnel
   bond             Create an LACP bond on a bridge
HEADER
    cat <<EOF

 CREATE-BRIDGE / DELETE-BRIDGE:
   --bridge <name>              Bridge name (required)

 ADD-PORT / DELETE-PORT:
   --bridge <name>              OVS bridge (required)
   --port <name>                Port name (required)
   --tag <id>                   VLAN tag for access port
   --trunk <ids>                Trunk VLAN tags (comma-separated)

 VXLAN:
   --local-ip <ip>              Local tunnel endpoint IP (required)
   --remote-ip <ip>             Remote tunnel endpoint IP (required)
   --vni <id>                   VXLAN Network Identifier (required)

 BOND:
   --bridge <name>              OVS bridge (required)
   --name <name>                Bond name (required)
   --slaves <list>              Comma-separated slave interfaces (required)
   --mode <mode>                Bond mode: active-backup, balance-slb, lacp (default: lacp)

 GENERAL:
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-ovs.sh create-bridge --bridge br-ovs0
   kvm-ovs.sh add-port --bridge br-ovs0 --port eth0 --tag 100
   kvm-ovs.sh vxlan --local-ip 10.0.0.1 --remote-ip 10.0.0.2 --vni 42
   kvm-ovs.sh bond --bridge br-ovs0 --name bond0 --slaves eth0,eth1 --mode lacp
   kvm-ovs.sh list
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
            create-bridge|delete-bridge|add-port|delete-port|list|vxlan|bond)
                ACTION="$1"
                shift
                ;;
            --bridge)
                OVS_BRIDGE="$2"
                shift 2
                ;;
            --port)
                PORT_NAME="$2"
                shift 2
                ;;
            --tag)
                VLAN_TAG="$2"
                shift 2
                ;;
            --trunk)
                TRUNK_TAGS="$2"
                shift 2
                ;;
            --local-ip)
                LOCAL_IP="$2"
                shift 2
                ;;
            --remote-ip)
                REMOTE_IP="$2"
                shift 2
                ;;
            --vni)
                VNI="$2"
                shift 2
                ;;
            --name)
                BOND_NAME="$2"
                shift 2
                ;;
            --slaves)
                SLAVES="$2"
                shift 2
                ;;
            --mode)
                BOND_MODE="$2"
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
        create-bridge|delete-bridge)
            if [[ -z "${OVS_BRIDGE}" ]]; then
                log_error "${ACTION} requires --bridge"
                exit 2
            fi
            ;;
        add-port|delete-port)
            if [[ -z "${OVS_BRIDGE}" || -z "${PORT_NAME}" ]]; then
                log_error "${ACTION} requires --bridge and --port"
                exit 2
            fi
            ;;
        vxlan)
            if [[ -z "${LOCAL_IP}" || -z "${REMOTE_IP}" || -z "${VNI}" ]]; then
                log_error "vxlan requires --local-ip, --remote-ip, and --vni"
                exit 2
            fi
            ;;
        bond)
            if [[ -z "${OVS_BRIDGE}" || -z "${BOND_NAME}" || -z "${SLAVES}" ]]; then
                log_error "bond requires --bridge, --name, and --slaves"
                exit 2
            fi
            ;;
        list)
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# action_create_bridge
# ---------------------------------------------------------------------------
action_create_bridge() {
    log_info "Creating OVS bridge '${OVS_BRIDGE}'..."
    dry_run ovs-vsctl add-br "${OVS_BRIDGE}"
    dry_run ovs-vsctl set bridge "${OVS_BRIDGE}" protocols=OpenFlow13
    log_info "OVS bridge '${OVS_BRIDGE}' created."
}

# ---------------------------------------------------------------------------
# action_delete_bridge
# ---------------------------------------------------------------------------
action_delete_bridge() {
    log_info "Deleting OVS bridge '${OVS_BRIDGE}'..."
    dry_run ovs-vsctl del-br "${OVS_BRIDGE}"
    log_info "OVS bridge '${OVS_BRIDGE}' deleted."
}

# ---------------------------------------------------------------------------
# action_add_port
# ---------------------------------------------------------------------------
action_add_port() {
    log_info "Adding port '${PORT_NAME}' to bridge '${OVS_BRIDGE}'..."
    dry_run ovs-vsctl add-port "${OVS_BRIDGE}" "${PORT_NAME}"

    if [[ -n "${VLAN_TAG}" ]]; then
        log_info "Setting access VLAN tag ${VLAN_TAG}..."
        dry_run ovs-vsctl set port "${PORT_NAME}" tag="${VLAN_TAG}"
    fi

    if [[ -n "${TRUNK_TAGS}" ]]; then
        log_info "Setting trunk VLAN tags ${TRUNK_TAGS}..."
        local tag_json
        tag_json=$(echo "${TRUNK_TAGS}" | tr ',' '\n' | sort -n | paste -sd ',' -)
        dry_run ovs-vsctl set port "${PORT_NAME}" trunks="[${tag_json}]"
    fi

    log_info "Port '${PORT_NAME}' added to bridge '${OVS_BRIDGE}'."
}

# ---------------------------------------------------------------------------
# action_delete_port
# ---------------------------------------------------------------------------
action_delete_port() {
    log_info "Deleting port '${PORT_NAME}' from bridge '${OVS_BRIDGE}'..."
    dry_run ovs-vsctl del-port "${OVS_BRIDGE}" "${PORT_NAME}"
    log_info "Port '${PORT_NAME}' deleted."
}

# ---------------------------------------------------------------------------
# action_list
# ---------------------------------------------------------------------------
action_list() {
    log_info "=== OVS Bridges ==="
    ovs-vsctl list-br 2>/dev/null | while IFS= read -r br; do
        echo ""
        echo "Bridge: ${br}"
        echo "  Ports:"
        ovs-vsctl list-ports "${br}" 2>/dev/null | while IFS= read -r port; do
            local tag
            tag=$(ovs-vsctl get port "${port}" tag 2>/dev/null || echo "[]")
            local trunks
            trunks=$(ovs-vsctl get port "${port}" trunks 2>/dev/null || echo "[]")
            echo "    - ${port} (tag: ${tag}, trunks: ${trunks})"
        done
        local dp_type
        dp_type=$(ovs-vsctl get bridge "${br}" datapath_type 2>/dev/null || echo "")
        echo "  Datapath type: ${dp_type:-netdev}"
    done
    echo ""

    log_info "=== OVS Interfaces ==="
    ovs-vsctl --columns=name,type,ofport list interface 2>/dev/null || true
    echo ""

    log_info "=== OVS Ports ==="
    ovs-vsctl --columns=name,tag,trunks,listing list port 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# action_vxlan
# ---------------------------------------------------------------------------
action_vxlan() {
    local tun_name="vxlan-${VNI}"
    log_info "Creating VXLAN tunnel '${tun_name}' (${LOCAL_IP} -> ${REMOTE_IP}, VNI: ${VNI})..."

    if [[ -z "${OVS_BRIDGE}" ]]; then
        OVS_BRIDGE="br-vxlan"
        if ! ovs-vsctl br-exists "${OVS_BRIDGE}" 2>/dev/null; then
            log_info "Auto-creating bridge '${OVS_BRIDGE}'..."
            dry_run ovs-vsctl add-br "${OVS_BRIDGE}"
        fi
    fi

    dry_run ovs-vsctl add-port "${OVS_BRIDGE}" "${tun_name}" -- \
        set interface "${tun_name}" \
        type=vxlan \
        options:local_ip="${LOCAL_IP}" \
        options:remote_ip="${REMOTE_IP}" \
        options:key="${VNI}"

    log_info "VXLAN tunnel '${tun_name}' created on bridge '${OVS_BRIDGE}'."
}

# ---------------------------------------------------------------------------
# action_bond
# ---------------------------------------------------------------------------
action_bond() {
    log_info "Creating bond '${BOND_NAME}' on bridge '${OVS_BRIDGE}'..."

    IFS=',' read -ra slave_array <<< "${SLAVES}"
    for slave in "${slave_array[@]}"; do
        slave="$(echo "${slave}" | xargs)"
        log_info "  Adding slave: ${slave}"
        dry_run ovs-vsctl add-port "${OVS_BRIDGE}" "${slave}" \
            set interface "${slave}" type=ethernet
    done

    local slave_list
    slave_list=$(echo "${SLAVES}" | tr ',' ' ' | xargs)

    dry_run ovs-vsctl add-bond "${OVS_BRIDGE}" "${BOND_NAME}" ${slave_list} \
        -- set port "${BOND_NAME}" bond_mode="${BOND_MODE}"

    if [[ "${BOND_MODE}" == "lacp" ]]; then
        dry_run ovs-vsctl set port "${BOND_NAME}" lacp=active
        log_info "  LACP mode enabled (active)."
    fi

    log_info "Bond '${BOND_NAME}' created on bridge '${OVS_BRIDGE}' with slaves: ${slave_list}."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs ovs-vsctl

    case "${ACTION}" in
        create-bridge) action_create_bridge ;;
        delete-bridge) action_delete_bridge ;;
        add-port)      action_add_port ;;
        delete-port)   action_delete_port ;;
        list)          action_list ;;
        vxlan)         action_vxlan ;;
        bond)          action_bond ;;
    esac
}

main "$@"
