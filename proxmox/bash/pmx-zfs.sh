#!/usr/bin/env bash
# =============================================================================
# pmx-zfs.sh — ZFS management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: pool, dataset, zvol, scrub, snapshot, properties, ARC
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "ZFS management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  pool-list           List all ZFS pools
  pool-status         --pool=POOL
  pool-create         --pool=POOL --devices=DEV1,DEV2 [OPTIONS]
  pool-destroy        --pool=POOL
  pool-import         --pool=POOL
  pool-export         --pool=POOL
  dataset-list        [--pool=POOL]
  dataset-create      --dataset=NAME [OPTIONS]
  dataset-destroy     --dataset=NAME
  dataset-rename      --dataset=OLD --new-name=NEW
  zvol-list           [--pool=POOL]
  zvol-create         --zvol=NAME --size=SIZE [OPTIONS]
  zvol-destroy        --zvol=NAME
  zvol-resize         --zvol=NAME --size=SIZE
  property-get        --dataset=NAME [--property=PROP]
  property-set        --dataset=NAME --property=PROP --value=VAL
  scrub-start         --pool=POOL [--deep]
  scrub-status        --pool=POOL
  snapshot-create     --dataset=NAME --name=SNAP [OPTIONS]
  snapshot-list       --dataset=NAME
  snapshot-destroy    --dataset=NAME --name=SNAP
  arc-usage           Show ARC usage
  arc-set-limit       --size=SIZE

PROPERTY OPTIONS:
  --property=PROP     ZFS property (e.g. compression, dedup, recordsize, sync, atime)
  --value=VAL         Property value

DATASET OPTIONS:
  --dataset=NAME      Dataset name (pool/dataset)
  --compression=ALG   Compression algorithm (default: lz4)
  --recordsize=SIZE   Record size (default: 128K)
  --quota=SIZE        Quota limit
  --mountpoint=PATH   Mount point

ZVOL OPTIONS:
  --zvol=NAME         Zvol name
  --size=SIZE         Size (e.g. 10G)
  --sparse            Create sparse zvol

SNAPSHOT OPTIONS:
  --dataset=NAME      Parent dataset
  --name=SNAP         Snapshot name
  --recursive         Recursive snapshot

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") pool-list
  $(basename "$0") pool-status --pool=rpool
  $(basename "$0") dataset-create --dataset=rpool/data --compression=lz4 --quota=500G
  $(basename "$0") property-set --dataset=rpool/data --property=compression --value=zstd
  $(basename "$0") snapshot-create --dataset=rpool/data --name=snap-20260101
  $(basename "$0") scrub-start --pool=rpool --deep
  $(basename "$0") arc-usage
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
POOL_NAME=""
DATASET=""
NEW_NAME=""
ZVOL=""
SIZE=""
DEVICE=""
DEVICES=""
PROPERTY=""
PROP_VALUE=""
SNAP_NAME=""
COMPRESSION="lz4"
RECORDSIZE="128K"
QUOTA=""
MOUNTPOINT=""
SPARSE=false
RECURSIVE=false
SCRUB_DEEP=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pool=*)         POOL_NAME="${1#*=}" ;;
            --dataset=*)      DATASET="${1#*=}" ;;
            --new-name=*)     NEW_NAME="${1#*=}" ;;
            --zvol=*)         ZVOL="${1#*=}" ;;
            --size=*)         SIZE="${1#*=}" ;;
            --device=*)       DEVICE="${1#*=}" ;;
            --devices=*)      DEVICES="${1#*=}" ;;
            --property=*)     PROPERTY="${1#*=}" ;;
            --value=*)        PROP_VALUE="${1#*=}" ;;
            --name=*)         SNAP_NAME="${1#*=}" ;;
            --compression=*)  COMPRESSION="${1#*=}" ;;
            --recordsize=*)   RECORDSIZE="${1#*=}" ;;
            --quota=*)        QUOTA="${1#*=}" ;;
            --mountpoint=*)   MOUNTPOINT="${1#*=}" ;;
            --sparse)         SPARSE=true; shift; continue ;;
            --recursive)      RECURSIVE=true; shift; continue ;;
            --deep)           SCRUB_DEEP=true; shift; continue ;;
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
    check_prereqs zfs jq
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_pool_list() {
    log_info "Listing ZFS pools..."
    echo ""
    dry_run zpool list -H -o name,size,used,avail,cap,health,frag 2>/dev/null || {
        log_warn "No ZFS pools found."
    }
}

do_pool_status() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    log_info "Status of pool '${POOL_NAME}'..."
    echo ""
    dry_run zpool status "${POOL_NAME}"
}

do_pool_create() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    [[ -z "${DEVICES}" ]] && { log_error "--devices is required."; exit 1; }

    log_info "Creating ZFS pool '${POOL_NAME}'..."
    confirm "Create ZFS pool '${POOL_NAME}'?" || exit 2

    local dev_args=""
    IFS=',' read -ra devs <<< "${DEVICES}"
    for d in "${devs[@]}"; do
        dev_args+=" $(echo "${d}" | xargs)"
    done

    dry_run bash -c "zpool create ${POOL_NAME}${dev_args}"
    echo -e "${GREEN}Pool '${POOL_NAME}' created.${NC}"
}

do_pool_destroy() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    log_info "Destroying ZFS pool '${POOL_NAME}'..."
    confirm "DESTROY pool '${POOL_NAME}'? ALL DATA WILL BE LOST." || exit 2
    dry_run zpool destroy "${POOL_NAME}"
    echo -e "${GREEN}Pool '${POOL_NAME}' destroyed.${NC}"
}

do_pool_import() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    log_info "Importing ZFS pool '${POOL_NAME}'..."
    dry_run zpool import "${POOL_NAME}"
    echo -e "${GREEN}Pool '${POOL_NAME}' imported.${NC}"
}

do_pool_export() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    log_info "Exporting ZFS pool '${POOL_NAME}'..."
    confirm "Export pool '${POOL_NAME}'?" || exit 2
    dry_run zpool export "${POOL_NAME}"
    echo -e "${GREEN}Pool '${POOL_NAME}' exported.${NC}"
}

do_dataset_list() {
    log_info "Listing ZFS datasets..."
    echo ""
    local cmd="zfs list -H -o name,used,avail,refer,mountpoint"
    [[ -n "${POOL_NAME}" ]] && cmd+=" -t filesystem -r ${POOL_NAME}"
    dry_run bash -c "${cmd}" 2>/dev/null || log_warn "No datasets found."
}

do_dataset_create() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }

    log_info "Creating dataset '${DATASET}'..."
    local cmd="zfs create"
    [[ -n "${COMPRESSION}" ]] && cmd+=" -o compression=${COMPRESSION}"
    [[ -n "${RECORDSIZE}" ]] && cmd+=" -o recordsize=${RECORDSIZE}"
    [[ -n "${QUOTA}" ]] && cmd+=" -o quota=${QUOTA}"
    [[ -n "${MOUNTPOINT}" ]] && cmd+=" -o mountpoint=${MOUNTPOINT}"
    cmd+=" ${DATASET}"

    dry_run bash -c "${cmd}"
    echo -e "${GREEN}Dataset '${DATASET}' created.${NC}"
}

do_dataset_destroy() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    log_info "Destroying dataset '${DATASET}'..."
    confirm "Destroy dataset '${DATASET}'?" || exit 2
    local cmd="zfs destroy -r ${DATASET}"
    [[ "${RECURSIVE}" == "true" ]] && cmd="zfs destroy -r ${DATASET}"
    dry_run bash -c "${cmd}"
    echo -e "${GREEN}Dataset '${DATASET}' destroyed.${NC}"
}

do_dataset_rename() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    [[ -z "${NEW_NAME}" ]] && { log_error "--new-name is required."; exit 1; }
    log_info "Renaming dataset '${DATASET}' to '${NEW_NAME}'..."
    dry_run zfs rename "${DATASET}" "${NEW_NAME}"
    echo -e "${GREEN}Dataset renamed.${NC}"
}

do_zvol_list() {
    log_info "Listing ZFS zvols..."
    echo ""
    local cmd="zfs list -H -o name,used,avail,refer -t volume"
    [[ -n "${POOL_NAME}" ]] && cmd+=" -r ${POOL_NAME}"
    dry_run bash -c "${cmd}" 2>/dev/null || log_warn "No zvols found."
}

do_zvol_create() {
    [[ -z "${ZVOL}" ]] && { log_error "--zvol is required."; exit 1; }
    [[ -z "${SIZE}" ]] && { log_error "--size is required."; exit 1; }

    log_info "Creating zvol '${ZVOL}' (${SIZE})..."
    local cmd="zfs create -V ${SIZE}"
    [[ "${SPARSE}" == "true" ]] && cmd+=" -s"
    [[ -n "${COMPRESSION}" ]] && cmd+=" -o compression=${COMPRESSION}"
    cmd+=" ${ZVOL}"

    dry_run bash -c "${cmd}"
    echo -e "${GREEN}Zvol '${ZVOL}' created.${NC}"
}

do_zvol_destroy() {
    [[ -z "${ZVOL}" ]] && { log_error "--zvol is required."; exit 1; }
    log_info "Destroying zvol '${ZVOL}'..."
    confirm "Destroy zvol '${ZVOL}'?" || exit 2
    dry_run zfs destroy "${ZVOL}"
    echo -e "${GREEN}Zvol '${ZVOL}' destroyed.${NC}"
}

do_zvol_resize() {
    [[ -z "${ZVOL}" ]] && { log_error "--zvol is required."; exit 1; }
    [[ -z "${SIZE}" ]] && { log_error "--size is required."; exit 1; }
    log_info "Resizing zvol '${ZVOL}' to ${SIZE}..."
    dry_run zfs set volsize="${SIZE}" "${ZVOL}"
    echo -e "${GREEN}Zvol resized.${NC}"
}

do_property_get() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    if [[ -n "${PROPERTY}" ]]; then
        log_info "Getting property '${PROPERTY}' on '${DATASET}'..."
        dry_run zfs get -H -o value "${PROPERTY}" "${DATASET}"
    else
        log_info "All properties for '${DATASET}'..."
        echo ""
        dry_run zfs list -o all "${DATASET}"
    fi
}

do_property_set() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    [[ -z "${PROPERTY}" ]] && { log_error "--property is required."; exit 1; }
    [[ -z "${PROP_VALUE}" ]] && { log_error "--value is required."; exit 1; }
    log_info "Setting ${PROPERTY}=${PROP_VALUE} on '${DATASET}'..."
    dry_run zfs set "${PROPERTY}=${PROP_VALUE}" "${DATASET}"
    echo -e "${GREEN}Property set.${NC}"
}

do_scrub_start() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    local scrub_type="scrub"
    [[ "${SCRUB_DEEP}" == "true" ]] && scrub_type="deep-scrub"
    log_info "Starting ${scrub_type} on pool '${POOL_NAME}'..."
    dry_run zpool "${scrub_type}" "${POOL_NAME}"
    echo -e "${GREEN}Scrub started.${NC}"
}

do_scrub_status() {
    [[ -z "${POOL_NAME}" ]] && { log_error "--pool is required."; exit 1; }
    log_info "Scrub status for pool '${POOL_NAME}'..."
    echo ""
    dry_run zpool scrub -s "${POOL_NAME}" 2>/dev/null || true
    dry_run zpool status "${POOL_NAME}"
}

do_snapshot_create() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    [[ -z "${SNAP_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Creating snapshot '${DATASET}@${SNAP_NAME}'..."
    local cmd="zfs snapshot"
    [[ "${RECURSIVE}" == "true" ]] && cmd+=" -r"
    cmd+=" ${DATASET}@${SNAP_NAME}"
    dry_run bash -c "${cmd}"
    echo -e "${GREEN}Snapshot created.${NC}"
}

do_snapshot_list() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    log_info "Listing snapshots for '${DATASET}'..."
    echo ""
    dry_run zfs list -t snapshot -r "${DATASET}" 2>/dev/null || log_warn "No snapshots."
}

do_snapshot_destroy() {
    [[ -z "${DATASET}" ]] && { log_error "--dataset is required."; exit 1; }
    [[ -z "${SNAP_NAME}" ]] && { log_error "--name is required."; exit 1; }
    log_info "Destroying snapshot '${DATASET}@${SNAP_NAME}'..."
    confirm "Destroy snapshot '${DATASET}@${SNAP_NAME}'?" || exit 2
    dry_run zfs destroy "${DATASET}@${SNAP_NAME}"
    echo -e "${GREEN}Snapshot destroyed.${NC}"
}

do_arc_usage() {
    log_info "ARC usage statistics..."
    echo ""
    if [[ -f /proc/spl/kstat/zfs/arcstats ]]; then
        local size hits misses hit_rate
        size=$(awk '/^size/ {printf "%.2f GB", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo "N/A")
        hits=$(awk '/^hits/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo "0")
        misses=$(awk '/^misses/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo "0")

        local total=$((hits + misses))
        if (( total > 0 )); then
            hit_rate=$(awk "BEGIN {printf \"%.2f%%\", (${hits}/${total})*100}")
        else
            hit_rate="N/A"
        fi

        printf "${BOLD}%-20s %-20s${NC}\n" "Metric" "Value"
        printf "%-20s %-20s\n" "------" "-----"
        printf "%-20s %-20s\n" "ARC Size" "${size}"
        printf "%-20s %-20s\n" "Hits" "${hits}"
        printf "%-20s %-20s\n" "Misses" "${misses}"
        printf "%-20s %-20s\n" "Hit Rate" "${hit_rate}"
    else
        dry_run zfs stats arc 2>/dev/null || log_warn "ARC stats not available."
    fi
}

do_arc_set_limit() {
    [[ -z "${SIZE}" ]] && { log_error "--size is required."; exit 1; }
    log_info "Setting ARC max size to ${SIZE}..."
    dry_run bash -c "echo ${SIZE} > /sys/module/zfs/parameters/zfs_arc_max"
    echo -e "${GREEN}ARC limit set to ${SIZE}.${NC}"
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
        pool-list)        do_pool_list ;;
        pool-status)      do_pool_status ;;
        pool-create)      do_pool_create ;;
        pool-destroy)     do_pool_destroy ;;
        pool-import)      do_pool_import ;;
        pool-export)      do_pool_export ;;
        dataset-list)     do_dataset_list ;;
        dataset-create)   do_dataset_create ;;
        dataset-destroy)  do_dataset_destroy ;;
        dataset-rename)   do_dataset_rename ;;
        zvol-list)        do_zvol_list ;;
        zvol-create)      do_zvol_create ;;
        zvol-destroy)     do_zvol_destroy ;;
        zvol-resize)      do_zvol_resize ;;
        property-get)     do_property_get ;;
        property-set)     do_property_set ;;
        scrub-start)      do_scrub_start ;;
        scrub-status)     do_scrub_status ;;
        snapshot-create)  do_snapshot_create ;;
        snapshot-list)    do_snapshot_list ;;
        snapshot-destroy) do_snapshot_destroy ;;
        arc-usage)        do_arc_usage ;;
        arc-set-limit)    do_arc_set_limit ;;
        *)                log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
