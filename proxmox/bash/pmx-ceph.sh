#!/usr/bin/env bash
# =============================================================================
# pmx-ceph.sh — Ceph management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: status, deploy, pool, osd, fs, health, scrub
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Ceph management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  status          Show overall Ceph cluster status
  health          Detailed health check
  deploy          --node=NODE [OPTIONS]
  pool-create     --name=NAME [--size=N] [--min-size=N] [--pg-num=N]
  pool-delete     --name=NAME
  pool-list       List all Ceph pools
  pool-set-size   --name=NAME --size=N
  pool-set-min    --name=NAME --min-size=N
  osd-list        List all OSDs
  osd-add         --device=DEV [--node=NODE]
  osd-remove      --osd-id=ID [--node=NODE]
  osd-reweight    --osd-id=ID --weight=FLOAT
  fs-create       --name=NAME --pool=POOL [--pg-num=N]
  fs-delete       --name=NAME
  fs-status       Show CephFS status
  scrub           --pool=POOL [--deep]

DEPLOY OPTIONS:
  --node=NODE       Target node (required)
  --mon             Also deploy monitor on this node
  --mgr             Also deploy manager on this node
  --osd-devices=DEV OSD devices (comma-separated, e.g. /dev/sdb,/dev/sdc)

POOL OPTIONS:
  --name=NAME       Pool name (required)
  --size=N          Replication size (default: 3)
  --min-size=N      Minimum replication (default: 2)
  --pg-num=N        Placement groups (default: 128)

OSD OPTIONS:
  --device=DEV      Block device (e.g. /dev/sdb)
  --osd-id=ID       OSD ID number
  --weight=FLOAT    OSD weight (0.0 - 1.0)

OPTIONS:
  --dry-run         Show what would be done
  --help, -h        Show this help

EXAMPLES:
  $(basename "$0") status
  $(basename "$0") health
  $(basename "$0") deploy --node=pve1 --mon --mgr --osd-devices=/dev/sdb,/dev/sdc
  $(basename "$0") pool-create --name=vm-pool --size=3
  $(basename "$0") osd-list
  $(basename "$0") scrub --pool=vm-pool --deep
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
NODE="${PMX_NODE:-}"
POOL_NAME=""
SIZE=3
MIN_SIZE=2
PG_NUM=128
DEVICE=""
OSD_ID=""
WEIGHT=""
FS_NAME=""
MON=false
MGR=false
OSD_DEVICES=""
SCRUB_DEEP=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node=*)           NODE="${1#*=}" ;;
            --name=*)           POOL_NAME="${1#*=}" ;;
            --size=*)           SIZE="${1#*=}" ;;
            --min-size=*)       MIN_SIZE="${1#*=}" ;;
            --pg-num=*)         PG_NUM="${1#*=}" ;;
            --device=*)         DEVICE="${1#*=}" ;;
            --osd-id=*)         OSD_ID="${1#*=}" ;;
            --weight=*)         WEIGHT="${1#*=}" ;;
            --pool=*)           POOL_NAME="${1#*=}" ;;
            --osd-devices=*)    OSD_DEVICES="${1#*=}" ;;
            --mon)              MON=true; shift; continue ;;
            --mgr)              MGR=true; shift; continue ;;
            --deep)             SCRUB_DEEP=true; shift; continue ;;
            --dry-run)          DRY_RUN=true; shift; continue ;;
            --help|-h)          usage ;;
            -*)                 log_error "Unknown option: $1"; usage ;;
            *)                  ACTION="$1" ;;
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
    if [[ -z "${NODE}" ]]; then
        NODE=$(parse_json "$(api_call GET /nodes)" ".data[0].node" 2>/dev/null) || {
            log_error "Could not auto-detect node."; exit 1
        }
    fi
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_status() {
    log_info "Fetching Ceph cluster status..."
    echo ""
    dry_run bash -c "ceph -s 2>&1 || pveceph status 2>&1" || {
        log_warn "Ceph not available or not installed."
    }
}

do_health() {
    log_info "Fetching detailed Ceph health..."
    echo ""
    dry_run bash -c "ceph health detail 2>&1" || true
    echo ""
    dry_run bash -c "ceph osd tree 2>&1" || true
}

do_deploy() {
    [[ -z "${NODE}" ]] && { log_error "--node is required."; exit 1; }

    log_info "Deploying Ceph on node ${NODE}..."
    confirm "Deploy Ceph on node ${NODE}?" || exit 2

    # Initialize Ceph if needed
    log_info "Initializing Ceph on ${NODE}..."
    dry_run bash -c "pveceph init --network auto 2>&1" || true

    if [[ "${MON}" == "true" ]]; then
        log_info "Deploying monitor on ${NODE}..."
        dry_run bash -c "pveceph createmon 2>&1"
    fi

    if [[ "${MGR}" == "true" ]]; then
        log_info "Deploying manager on ${NODE}..."
        dry_run bash -c "pveceph createmgr 2>&1"
    fi

    if [[ -n "${OSD_DEVICES}" ]]; then
        IFS=',' read -ra devs <<< "${OSD_DEVICES}"
        for dev in "${devs[@]}"; do
            dev=$(echo "${dev}" | xargs)
            log_info "Creating OSD on ${dev}..."
            dry_run bash -c "pveceph osd create ${dev} 2>&1"
        done
    fi

    echo -e "${GREEN}Ceph deployment complete on ${NODE}.${NC}"
}

do_pool_create() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--name is required."; exit 1; }

    log_info "Creating Ceph pool '${POOL_NAME}'..."
    dry_run bash -c "ceph osd pool create ${POOL_NAME} ${PG_NUM} 2>&1"
    dry_run bash -c "ceph osd pool set ${POOL_NAME} size ${SIZE} 2>&1"
    dry_run bash -c "ceph osd pool set ${POOL_NAME} min_size ${MIN_SIZE} 2>&1"
    echo -e "${GREEN}Pool '${POOL_NAME}' created (size=${SIZE}, pg=${PG_NUM}).${NC}"
}

do_pool_delete() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting Ceph pool '${POOL_NAME}'..."
    confirm "Delete Ceph pool '${POOL_NAME}'? All data will be lost." || exit 2
    dry_run bash -c "ceph osd pool delete ${POOL_NAME} ${POOL_NAME} --yes-i-really-really-mean-it 2>&1"
    echo -e "${GREEN}Pool '${POOL_NAME}' deleted.${NC}"
}

do_pool_list() {
    log_info "Listing Ceph pools..."
    echo ""
    dry_run bash -c "ceph osd pool ls detail 2>&1" || dry_run bash -c "ceph osd pool ls 2>&1"
}

do_pool_set_size() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Setting pool '${POOL_NAME}' size to ${SIZE}..."
    dry_run bash -c "ceph osd pool set ${POOL_NAME} size ${SIZE} 2>&1"
    echo -e "${GREEN}Pool size updated.${NC}"
}

do_pool_set_min() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Setting pool '${POOL_NAME}' min_size to ${MIN_SIZE}..."
    dry_run bash -c "ceph osd pool set ${POOL_NAME} min_size ${MIN_SIZE} 2>&1"
    echo -e "${GREEN}Pool min_size updated.${NC}"
}

do_osd_list() {
    log_info "Listing Ceph OSDs..."
    echo ""
    dry_run bash -c "ceph osd tree 2>&1"
}

do_osd_add() {
    [[ -z "${DEVICE}" ]] && { log_error "--device is required."; exit 1; }
    log_info "Adding OSD on device ${DEVICE}..."
    confirm "Create OSD on ${DEVICE}? The device will be wiped." || exit 2
    dry_run bash -c "pveceph osd create ${DEVICE} 2>&1"
    echo -e "${GREEN}OSD created on ${DEVICE}.${NC}"
}

do_osd_remove() {
    [[ -z "${OSD_ID}" ]] && { log_error "--osd-id is required."; exit 1; }
    log_info "Removing OSD ${OSD_ID}..."
    confirm "Remove OSD ${OSD_ID}? Data will be rebalanced." || exit 2
    dry_run bash -c "ceph osd out ${OSD_ID} 2>&1"
    dry_run bash -c "ceph osd rm ${OSD_ID} 2>&1"
    echo -e "${GREEN}OSD ${OSD_ID} removed.${NC}"
}

do_osd_reweight() {
    [[ -z "${OSD_ID}" ]] && { log_error "--osd-id is required."; exit 1; }
    [[ -z "${WEIGHT}" ]] && { log_error "--weight is required."; exit 1; }
    log_info "Reweighting OSD ${OSD_ID} to ${WEIGHT}..."
    dry_run bash -c "ceph osd reweight ${OSD_ID} ${WEIGHT} 2>&1"
    echo -e "${GREEN}OSD ${OSD_ID} reweighted to ${WEIGHT}.${NC}"
}

do_fs_create() {
    [[ -z "${FS_NAME}" ]] && { log_error "--name is required."; exit 1; }
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }

    log_info "Creating CephFS '${FS_NAME}'..."
    dry_run bash -c "ceph fs ls 2>&1" | grep -q "^name: ${FS_NAME}," && {
        log_warn "CephFS '${FS_NAME}' already exists."
        return 0
    }
    dry_run bash -c "ceph fs create ${FS_NAME} ${POOL_NAME} 2>&1"
    echo -e "${GREEN}CephFS '${FS_NAME}' created.${NC}"
}

do_fs_delete() {
    [[ -z "${FS_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Deleting CephFS '${FS_NAME}'..."
    confirm "Delete CephFS '${FS_NAME}'?" || exit 2
    dry_run bash -c "ceph fs rm ${FS_NAME} --yes-i-really-mean-it 2>&1"
    echo -e "${GREEN}CephFS '${FS_NAME}' deleted.${NC}"
}

do_fs_status() {
    log_info "CephFS status..."
    echo ""
    dry_run bash -c "ceph fs status 2>&1" || dry_run bash -c "ceph fs ls 2>&1"
}

do_scrub() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }

    if [[ "${SCRUB_DEEP}" == "true" ]]; then
        log_info "Starting deep scrub on pool '${POOL_NAME}'..."
        dry_run bash -c "ceph osd pool deep-scrub ${POOL_NAME} 2>&1"
    else
        log_info "Starting scrub on pool '${POOL_NAME}'..."
        dry_run bash -c "ceph osd pool scrub ${POOL_NAME} 2>&1"
    fi
    echo -e "${GREEN}Scrub initiated.${NC}"
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
        status)        do_status ;;
        health)        do_health ;;
        deploy)        do_deploy ;;
        pool-create)   do_pool_create ;;
        pool-delete)   do_pool_delete ;;
        pool-list)     do_pool_list ;;
        pool-set-size) do_pool_set_size ;;
        pool-set-min)  do_pool_set_min ;;
        osd-list)      do_osd_list ;;
        osd-add)       do_osd_add ;;
        osd-remove)    do_osd_remove ;;
        osd-reweight)  do_osd_reweight ;;
        fs-create)     do_fs_create ;;
        fs-delete)     do_fs_delete ;;
        fs-status)     do_fs_status ;;
        scrub)         do_scrub ;;
        *)             log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
