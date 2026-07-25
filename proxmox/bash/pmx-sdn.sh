#!/usr/bin/env bash
# =============================================================================
# pmx-sdn.sh — Proxmox SDN management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: zones, vnets, subnets, status, apply
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Proxmox SDN management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  zones           List all SDN zones
  zone-create     --id=ID --type=TYPE [OPTIONS]
  zone-delete     --id=ID
  vnets           List all VNets
  vnet-create     --id=ID --zone=ZONE [OPTIONS]
  vnet-delete     --id=ID
  subnets         [--vnet=VNET]
  subnet-create   --vnet=VNET --cidr=CIDR [OPTIONS]
  subnet-delete   --vnet=VNET --id=ID
  status          Show SDN status
  apply           Apply SDN configuration

ZONE OPTIONS:
  --id=ID           Zone identifier (required)
  --type=TYPE       Zone type: vlan, vxlan, evpn, qinq (required)
  --ipam=IPAM       IPAM plugin (pveam, phpipam, etc.)
  --dns=DNS         DNS plugin

VNET OPTIONS:
  --id=ID           VNet identifier (required)
  --zone=ZONE       Parent zone (required)
  --alias=ALIAS     VNet alias name

SUBNET OPTIONS:
  --vnet=VNET       Parent VNet (required)
  --id=ID           Subnet identifier (auto from CIDR)
  --cidr=CIDR       Subnet CIDR (required)
  --gateway=IP      Gateway IP
  --dhcp-start=IP   DHCP range start
  --dhcp-end=IP     DHCP range end

OPTIONS:
  --dry-run         Show what would be done
  --help, -h        Show this help

EXAMPLES:
  $(basename "$0") zones
  $(basename "$0") zone-create --id=myzone --type=vlan
  $(basename "$0") vnets
  $(basename "$0") vnet-create --id=myvnet --zone=myzone --alias="Production"
  $(basename "$0") subnet-create --vnet=myvnet --cidr=10.0.100.0/24 --gateway=10.0.100.1 --dhcp-start=10.0.100.10 --dhcp-end=10.0.100.200
  $(basename "$0") status
  $(basename "$0") apply
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
ZONE_ID=""
ZONE_TYPE=""
VNET_ID=""
VNET_ZONE=""
ALIAS=""
SUBNET_CIDR=""
GATEWAY=""
DHCP_START=""
DHCP_END=""
IPAM=""
DNS=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id=*)         ZONE_ID="${1#*=}" ;;
            --type=*)       ZONE_TYPE="${1#*=}" ;;
            --vnet=*)       VNET_ID="${1#*=}" ;;
            --zone=*)       VNET_ZONE="${1#*=}" ;;
            --alias=*)      ALIAS="${1#*=}" ;;
            --cidr=*)       SUBNET_CIDR="${1#*=}" ;;
            --gateway=*)    GATEWAY="${1#*=}" ;;
            --dhcp-start=*) DHCP_START="${1#*=}" ;;
            --dhcp-end=*)   DHCP_END="${1#*=}" ;;
            --ipam=*)       IPAM="${1#*=}" ;;
            --dns=*)        DNS="${1#*=}" ;;
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
    check_prereqs curl jq
    require_api_token
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_zones() {
    log_info "Listing SDN zones..."
    local resp
    resp=$(api_call GET "/cluster/sdn/zones" 2>/dev/null) || {
        log_warn "No SDN zones found."
        return 0
    }

    echo ""
    printf "${BOLD}%-16s %-10s %-12s %-12s${NC}\n" "ZONE" "TYPE" "IPAM" "DNS"
    printf "%-16s %-10s %-12s %-12s\n" "----" "----" "----" "---"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local zid ztype zipam zdns
        zid=$(echo "${item}" | jq -r '.zone // "unknown"')
        ztype=$(echo "${item}" | jq -r '.type // "unknown"')
        zipam=$(echo "${item}" | jq -r '.ipam // "-"')
        zdns=$(echo "${item}" | jq -r '.dns // "-"')

        printf "%-16s %-10s %-12s %-12s\n" "${zid}" "${ztype}" "${zipam}" "${zdns}"
    done
}

do_zone_create() {
    [[ -z "${ZONE_ID}" ]] && { log_error "--id is required."; exit 1; }
    [[ -z "${ZONE_TYPE}" ]] && { log_error "--type is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg zone "${ZONE_ID}" \
        --arg type "${ZONE_TYPE}" \
        --arg ipam "${IPAM}" \
        --arg dns "${DNS}" \
        '{"zone": $zone, "type": $type}')
    [[ -n "${IPAM}" ]] && payload=$(echo "${payload}" | jq -c --arg i "${IPAM}" '. + {"ipam": $i}')
    [[ -n "${DNS}" ]] && payload=$(echo "${payload}" | jq -c --arg d "${DNS}" '. + {"dns": $d}')

    log_info "Creating SDN zone '${ZONE_ID}' (type: ${ZONE_TYPE})..."
    dry_run api_call POST "/cluster/sdn/zones" -d "${payload}"
    echo -e "${GREEN}Zone '${ZONE_ID}' created.${NC}"
}

do_zone_delete() {
    [[ -z "${ZONE_ID}" ]] && { log_error "--id is required."; exit 1; }
    log_info "Deleting SDN zone '${ZONE_ID}'..."
    confirm "Delete zone '${ZONE_ID}'? All VNets in this zone will be removed." || exit 2
    dry_run api_call DELETE "/cluster/sdn/zones/${ZONE_ID}"
    echo -e "${GREEN}Zone '${ZONE_ID}' deleted.${NC}"
}

do_vnets() {
    log_info "Listing VNets..."
    local resp
    resp=$(api_call GET "/cluster/sdn/vnets" 2>/dev/null) || {
        log_warn "No VNets found."
        return 0
    }

    echo ""
    printf "${BOLD}%-16s %-16s %-30s${NC}\n" "VNET" "ZONE" "ALIAS"
    printf "%-16s %-16s %-30s\n" "----" "----" "-----"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local vid vzid valias
        vid=$(echo "${item}" | jq -r '.vnet // "unknown"')
        vzid=$(echo "${item}" | jq -r '.zone // "unknown"')
        valias=$(echo "${item}" | jq -r '.alias // ""')

        printf "%-16s %-16s %-30s\n" "${vid}" "${vzid}" "${valias}"
    done
}

do_vnet_create() {
    [[ -z "${VNET_ID}" ]] && { log_error "--id is required."; exit 1; }
    [[ -z "${VNET_ZONE}" ]] && { log_error "--zone is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg vnet "${VNET_ID}" \
        --arg zone "${VNET_ZONE}" \
        --arg alias "${ALIAS}" \
        '{"vnet": $vnet, "zone": $zone}')
    [[ -n "${ALIAS}" ]] && payload=$(echo "${payload}" | jq -c --arg a "${ALIAS}" '. + {"alias": $a}')

    log_info "Creating VNet '${VNET_ID}' in zone '${VNET_ZONE}'..."
    dry_run api_call POST "/cluster/sdn/vnets" -d "${payload}"
    echo -e "${GREEN}VNet '${VNET_ID}' created.${NC}"
}

do_vnet_delete() {
    [[ -z "${VNET_ID}" ]] && { log_error "--id is required."; exit 1; }
    log_info "Deleting VNet '${VNET_ID}'..."
    confirm "Delete VNet '${VNET_ID}'?" || exit 2
    dry_run api_call DELETE "/cluster/sdn/vnets/${VNET_ID}"
    echo -e "${GREEN}VNet '${VNET_ID}' deleted.${NC}"
}

do_subnets() {
    log_info "Listing subnets..."
    local resp
    if [[ -n "${VNET_ID}" ]]; then
        resp=$(api_call GET "/cluster/sdn/vnets/${VNET_ID}/subnets" 2>/dev/null) || {
            log_warn "No subnets found."
            return 0
        }
    else
        resp=$(api_call GET "/cluster/sdn/subnets" 2>/dev/null) || {
            log_warn "No subnets found."
            return 0
        }
    fi

    echo ""
    printf "${BOLD}%-8s %-20s %-18s %-20s${NC}\n" "VNET" "CIDR" "GATEWAY" "DHCP-RANGE"
    printf "%-8s %-20s %-18s %-20s\n" "----" "----" "-------" "----------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local svnet scidr sgateway sdhcp
        svnet=$(echo "${item}" | jq -r '.vnet // "unknown"')
        scidr=$(echo "${item}" | jq -r '.cidr // ""')
        sgateway=$(echo "${item}" | jq -r '.gateway // "-"')
        sdhcp=$(echo "${item}" | jq -r '"\(.dhcp_start // "-")-\(.dhcp_end // "-")"')

        printf "%-8s %-20s %-18s %-20s\n" "${svnet}" "${scidr}" "${sgateway}" "${sdhcp}"
    done
}

do_subnet_create() {
    [[ -z "${VNET_ID}" ]] && { log_error "--vnet is required."; exit 1; }
    [[ -z "${SUBNET_CIDR}" ]] && { log_error "--cidr is required."; exit 1; }

    local payload
    payload=$(jq -n \
        --arg cidr "${SUBNET_CIDR}" \
        --arg gateway "${GATEWAY}" \
        --arg dhcp_start "${DHCP_START}" \
        --arg dhcp_end "${DHCP_END}" \
        '{"cidr": $cidr}')
    [[ -n "${GATEWAY}" ]] && payload=$(echo "${payload}" | jq -c --arg g "${GATEWAY}" '. + {"gateway": $g}')
    if [[ -n "${DHCP_START}" && -n "${DHCP_END}" ]]; then
        payload=$(echo "${payload}" | jq -c \
            --arg ds "${DHCP_START}" --arg de "${DHCP_END}" \
            '. + {"dhcp_start": $ds, "dhcp_end": $de}')
    fi

    log_info "Creating subnet ${SUBNET_CIDR} on VNet '${VNET_ID}'..."
    dry_run api_call POST "/cluster/sdn/vnets/${VNET_ID}/subnets" -d "${payload}"
    echo -e "${GREEN}Subnet created.${NC}"
}

do_subnet_delete() {
    [[ -z "${VNET_ID}" ]] && { log_error "--vnet is required."; exit 1; }
    [[ -z "${SUBNET_CIDR}" ]] && { log_error "--cidr is required."; exit 1; }
    log_info "Deleting subnet ${SUBNET_CIDR} from VNet '${VNET_ID}'..."
    confirm "Delete subnet ${SUBNET_CIDR}?" || exit 2
    dry_run api_call DELETE "/cluster/sdn/vnets/${VNET_ID}/subnets/${SUBNET_CIDR}"
    echo -e "${GREEN}Subnet deleted.${NC}"
}

do_status() {
    log_info "SDN status..."
    echo ""
    dry_run bash -c "ip -brief link show | grep -E 'vm|veth|vlan|vxlan|bridge' 2>/dev/null" || true

    echo ""
    log_info "SDN Zones:"
    do_zones 2>/dev/null || true

    echo ""
    log_info "VNets:"
    do_vnets 2>/dev/null || true

    echo ""
    log_info "Subnets:"
    do_subnets 2>/dev/null || true
}

do_apply() {
    log_info "Applying SDN configuration..."
    confirm "Apply SDN configuration?" || exit 2

    dry_run api_call PUT "/cluster/sdn" -d '{"version":1}'
    echo -e "${GREEN}SDN configuration applied.${NC}"
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
        zones)          do_zones ;;
        zone-create)    do_zone_create ;;
        zone-delete)    do_zone_delete ;;
        vnets)          do_vnets ;;
        vnet-create)    do_vnet_create ;;
        vnet-delete)    do_vnet_delete ;;
        subnets)        do_subnets ;;
        subnet-create)  do_subnet_create ;;
        subnet-delete)  do_subnet_delete ;;
        status)         do_status ;;
        apply)          do_apply ;;
        *)              log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
