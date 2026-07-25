#!/usr/bin/env bash
# =============================================================================
# kvm-network-bridge.sh — Network management for KVM via libvirt
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create, delete, list, start, stop, autostart, dhcp, leases
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
NET_NAME=""
NET_MODE=""
BRIDGE=""
SUBNET=""
DHCP_RANGE=""
DNS=""
DOMAIN=""
FORWARD_DEV=""
MAC_ADDR=""
IP_ADDR=""
HOSTNAME_VAL=""
ENABLE_AUTOSTART=""
LIST_DETAILS=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-network-bridge.sh" "Network management for KVM"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <ACTION>

 ACTIONS:
   create       Create a new virtual network
   delete       Delete a virtual network
   list         List virtual networks
   start        Start a virtual network
   stop         Stop a virtual network
   autostart    Enable/disable network autostart
   dhcp         Add static DHCP lease
   leases       Show DHCP leases for a network

 CREATE OPTIONS:
   --name <name>              Network name (required)
   --mode <mode>              Network mode: nat (default), routed, isolated, bridge
   --bridge <name>            Bridge device for bridge mode (e.g. br0)
   --subnet <CIDR>            Subnet in CIDR notation (e.g. 192.168.122.0/24)
   --dhcp-range <range>       DHCP range (e.g. 192.168.122.100,192.168.122.254)
   --dns <ip>                 DNS server IP
   --domain <name>            DNS domain name
   --forward-dev <dev>        Forward device for routed mode (e.g. eth0)

 DELETE/LIST/START/STOP OPTIONS:
   --name <name>              Network name (required)

 AUTOSTART OPTIONS:
   --name <name>              Network name (required)
   --enable                   Enable autostart
   --disable                  Disable autostart

 DHCP OPTIONS:
   --name <name>              Network name (required)
   --mac <addr>               MAC address
   --ip <addr>                IP address
   --hostname <name>          Hostname for the lease

 LEASES OPTIONS:
   --name <name>              Network name (required)

 GENERAL OPTIONS:
   --connect <uri>            Libvirt URI (default: qemu:///system)
   --list-details             Show detailed network info
   --dry-run                  Show what would be done without executing
   -h, --help                 Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   $(basename "$0") create --name mgmt --mode nat --subnet 192.168.100.0/24 --dhcp-range 192.168.100.50,192.168.100.200
   $(basename "$0") create --name production --mode bridge --bridge br0
   $(basename "$0") list --list-details
   $(basename "$0") dhcp --name mgmt --mac 52:54:00:12:34:56 --ip 192.168.100.10 --hostname server01
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
            create|delete|list|start|stop|autostart|dhcp|leases)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --name)
                NET_NAME="$2"
                shift 2
                ;;
            --mode)
                NET_MODE="$2"
                shift 2
                ;;
            --bridge)
                BRIDGE="$2"
                shift 2
                ;;
            --subnet)
                SUBNET="$2"
                shift 2
                ;;
            --dhcp-range)
                DHCP_RANGE="$2"
                shift 2
                ;;
            --dns)
                DNS="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --forward-dev)
                FORWARD_DEV="$2"
                shift 2
                ;;
            --mac)
                MAC_ADDR="$2"
                shift 2
                ;;
            --ip)
                IP_ADDR="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME_VAL="$2"
                shift 2
                ;;
            --enable)
                ENABLE_AUTOSTART="yes"
                shift
                ;;
            --disable)
                ENABLE_AUTOSTART="no"
                shift
                ;;
            --list-details)
                LIST_DETAILS="--name --uuid --bridge --domain-name --forward-mode --ip-address --dhcp-range"
                shift
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
        create|delete|start|stop|leases)
            if [[ -z "${NET_NAME}" ]]; then
                log_error "${ACTION} requires --name"
                exit 2
            fi
            ;;
        autostart)
            if [[ -z "${NET_NAME}" ]]; then
                log_error "autostart requires --name"
                exit 2
            fi
            if [[ -z "${ENABLE_AUTOSTART}" ]]; then
                log_error "autostart requires --enable or --disable"
                exit 2
            fi
            ;;
        dhcp)
            if [[ -z "${NET_NAME}" || -z "${MAC_ADDR}" || -z "${IP_ADDR}" ]]; then
                log_error "dhcp requires --name, --mac, and --ip"
                exit 2
            fi
            ;;
        list)
            # No required args
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
# build_network_xml
# ---------------------------------------------------------------------------
build_network_xml() {
    local name="$1"
    local mode="${2:-nat}"
    local subnet="${3:-}"
    local dhcp_range="${4:-}"
    local dns_val="${5:-}"
    local domain_val="${6:-}"
    local bridge_val="${7:-}"
    local forward_dev_val="${8:-}"

    # Parse subnet
    local network_addr prefix
    if [[ -n "${subnet}" ]]; then
        network_addr="${subnet%/*}"
        prefix="${subnet#*/}"
    else
        network_addr="192.168.122.0"
        prefix="24"
    fi

    # Calculate netmask
    local netmask
    netmask=$(python3 -c "
import ipaddress
net = ipaddress.IPv4Network('${network_addr}/${prefix}', strict=False)
print(str(net.netmask))
" 2>/dev/null || echo "255.255.255.0")

    local xml="<network>"

    xml+="<name>${name}</name>"

    if [[ -n "${domain_val}" ]]; then
        xml+="<domain name='${domain_val}'/>"
    fi

    case "${mode}" in
        nat)
            xml+="<forward mode='nat'/>"
            if [[ -n "${forward_dev_val}" ]]; then
                xml="<network>"
                xml+="<name>${name}</name>"
                xml+="<forward mode='nat'>"
                xml+="<interface dev='${forward_dev_val}'/>"
                xml+="</forward>"
            fi
            ;;
        routed)
            xml+="<forward mode='route'/>"
            if [[ -n "${forward_dev_val}" ]]; then
                xml+="<forward mode='route'>"
                xml+="<interface dev='${forward_dev_val}'/>"
                xml+="</forward>"
            fi
            ;;
        isolated)
            # No forward element for isolated
            ;;
        bridge)
            xml+="<forward mode='bridge'/>"
            xml+="<bridge name='${bridge_val}'/>"
            ;;
    esac

    if [[ "${mode}" != "bridge" ]]; then
        xml+="<ip address='${network_addr}' netmask='${netmask}'>"

        if [[ -n "${dhcp_range}" ]]; then
            local dhcp_start dhcp_end
            dhcp_start="${dhcp_range%%,*}"
            dhcp_end="${dhcp_range##*,}"
            xml+="<dhcp>"
            xml+="<range start='${dhcp_start}' end='${dhcp_end}'/>"
            xml+="</dhcp>"
        fi

        xml+="</ip>"
    fi

    if [[ -n "${dns_val}" ]]; xml+="<dns><forwarder addr='${dns_val}'/></dns>"; fi

    xml+="</network>"

    echo "${xml}"
}

# ---------------------------------------------------------------------------
# action_create
# ---------------------------------------------------------------------------
action_create() {
    log_info "Creating network '${NET_NAME}' (mode: ${NET_MODE:-nat})..."

    local mode="${NET_MODE:-nat}"

    if [[ "${mode}" == "bridge" && -z "${BRIDGE}" ]]; then
        log_error "bridge mode requires --bridge"
        exit 2
    fi

    local xml
    xml=$(build_network_xml "${NET_NAME}" "${mode}" "${SUBNET}" \
        "${DHCP_RANGE}" "${DNS}" "${DOMAIN}" "${BRIDGE}" "${FORWARD_DEV}")

    log_debug "Network XML:"
    log_debug "${xml}"

    local tmpxml
    tmpxml=$(create_temp_file)
    echo "${xml}" > "${tmpxml}"

    dry_run virsh_cmd net-define "${tmpxml}"
    dry_run virsh_cmd net-start "${NET_NAME}"
    dry_run virsh_cmd net-autostart "${NET_NAME}" --enable

    log_info "Network '${NET_NAME}' created and started."
}

# ---------------------------------------------------------------------------
# action_delete
# ---------------------------------------------------------------------------
action_delete() {
    log_info "Deleting network '${NET_NAME}'..."

    # Stop if running
    virsh_cmd net-info "${NET_NAME}" 2>/dev/null | grep -q "Active.*yes" && {
        dry_run virsh_cmd net-destroy "${NET_NAME}"
    }

    dry_run virsh_cmd net-undefine "${NET_NAME}"
    log_info "Network '${NET_NAME}' deleted."
}

# ---------------------------------------------------------------------------
# action_list
# ---------------------------------------------------------------------------
action_list() {
    log_info "Listing networks..."
    virsh_cmd net-list --all
}

# ---------------------------------------------------------------------------
# action_start
# ---------------------------------------------------------------------------
action_start() {
    log_info "Starting network '${NET_NAME}'..."
    dry_run virsh_cmd net-start "${NET_NAME}"
    log_info "Network '${NET_NAME}' started."
}

# ---------------------------------------------------------------------------
# action_stop
# ---------------------------------------------------------------------------
action_stop() {
    log_info "Stopping network '${NET_NAME}'..."
    dry_run virsh_cmd net-destroy "${NET_NAME}"
    log_info "Network '${NET_NAME}' stopped."
}

# ---------------------------------------------------------------------------
# action_autostart
# ---------------------------------------------------------------------------
action_autostart() {
    if [[ "${ENABLE_AUTOSTART}" == "yes" ]]; then
        log_info "Enabling autostart for network '${NET_NAME}'..."
        dry_run virsh_cmd net-autostart "${NET_NAME}" --enable
    else
        log_info "Disabling autostart for network '${NET_NAME}'..."
        dry_run virsh_cmd net-autostart "${NET_NAME}" --disable
    fi
}

# ---------------------------------------------------------------------------
# action_dhcp
# ---------------------------------------------------------------------------
action_dhcp() {
    log_info "Adding static DHCP lease for ${MAC_ADDR} -> ${IP_ADDR} on network '${NET_NAME}'..."

    local hostname_arg=""
    if [[ -n "${HOSTNAME_VAL}" ]]; then
        hostname_arg="${HOSTNAME_VAL}"
    fi

    local -a cmd=(virsh_cmd net-update "${NET_NAME}" add-last ip-dhcp-host)
    local host_xml="<host mac='${MAC_ADDR}' ip='${IP_ADDR}'"
    if [[ -n "${HOSTNAME_VAL}" ]]; then
        host_xml+=" name='${HOSTNAME_VAL}'"
    fi
    host_xml+="/>"

    local tmpxml
    tmpxml=$(create_temp_file)
    echo "${host_xml}" > "${tmpxml}"

    cmd+=(--file "${tmpxml}")

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "DHCP lease added."
}

# ---------------------------------------------------------------------------
# action_leases
# ---------------------------------------------------------------------------
action_leases() {
    log_info "DHCP leases for network '${NET_NAME}':"
    virsh_cmd net-dhcp-leases "${NET_NAME}"
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
        create)     action_create ;;
        delete)     action_delete ;;
        list)       action_list ;;
        start)      action_start ;;
        stop)       action_stop ;;
        autostart)  action_autostart ;;
        dhcp)       action_dhcp ;;
        leases)     action_leases ;;
    esac
}

main "$@"
