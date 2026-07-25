#!/usr/bin/env bash
# =============================================================================
# kvm-backup.sh - Backup operations for KVM VMs
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: full, incremental, live, offline, list
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
DOMAIN=""
OUTPUT_DIR=""
BACKUP_FORMAT="qcow2"
COMPRESS=""
BASE_SNAPSHOT=""
LIST_BACKUPS=""
FREEZE_TIMEOUT=30

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-backup.sh" "Backup operations for KVM VMs"
    cat <<'HEADER'
Usage: kvm-backup.sh [OPTIONS] <ACTION>

 ACTIONS:
   full           Full offline backup of a VM
   incremental    Incremental backup using dirty bitmaps
   live           Live backup with filesystem freeze (fsfreeze)
   offline        Shutdown VM, backup, then restart
   list           List available backups/snapshots
HEADER
    cat <<EOF

 FULL:
   --domain <name>              VM domain name (required)
   --output-dir <path>          Output directory for backups (required)
   --format <fmt>               Output format: qcow2 (default), raw
   --compress                   Compress the backup image

 INCREMENTAL:
   --domain <name>              VM domain name (required)
   --output-dir <path>          Output directory (required)
   --base-snapshot <name>       Base snapshot for incremental (required)

 LIVE:
   --domain <name>              VM domain name (required)
   --output-dir <path>          Output directory (required)

 OFFLINE:
   --domain <name>              VM domain name (required)
   --output-dir <path>          Output directory (required)

 LIST:
   --domain <name>              VM domain name (required)

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments
   3   Partial failure

EXAMPLES:
   kvm-backup.sh full --domain web01 --output-dir /backups/web01 --compress
   kvm-backup.sh incremental --domain web01 --output-dir /backups/web01 --base-snapshot base-2026-01-01
   kvm-backup.sh live --domain web01 --output-dir /backups/web01
   kvm-backup.sh offline --domain web01 --output-dir /backups/web01
   kvm-backup.sh list --domain web01
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
            full|incremental|live|offline|list)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --format)
                BACKUP_FORMAT="$2"
                shift 2
                ;;
            --compress)
                COMPRESS="-c"
                shift
                ;;
            --base-snapshot)
                BASE_SNAPSHOT="$2"
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
        full|incremental|live|offline)
            if [[ -z "${DOMAIN}" || -z "${OUTPUT_DIR}" ]]; then
                log_error "${ACTION} requires --domain and --output-dir"
                exit 2
            fi
            ;;
        list)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "list requires --domain"
                exit 2
            fi
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
# get_disk_path
# ---------------------------------------------------------------------------
get_disk_path() {
    local domain="$1"
    virsh_cmd domblklist "${domain}" 2>/dev/null | grep -E '^\s*[a-z]' | head -1 | awk '{print $2}' || true
}

# ---------------------------------------------------------------------------
# get_disk_devices
# ---------------------------------------------------------------------------
get_disk_devices() {
    local domain="$1"
    virsh_cmd domblklist "${domain}" 2>/dev/null | tail -n +3
}

# ---------------------------------------------------------------------------
# prepare_output_dir
# ---------------------------------------------------------------------------
prepare_output_dir() {
    local dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    mkdir -p "${dir}/${DOMAIN}/${timestamp}" || {
        log_error "Failed to create output directory: ${dir}/${DOMAIN}/${timestamp}"
        return 1
    }

    echo "${dir}/${DOMAIN}/${timestamp}"
}

# ---------------------------------------------------------------------------
# action_full
# ---------------------------------------------------------------------------
action_full() {
    log_info "Starting full backup of domain '${DOMAIN}'..."

    local backup_dir
    backup_dir=$(prepare_output_dir "${OUTPUT_DIR}")

    log_info "Backup directory: ${backup_dir}"

    local -a disks
    mapfile -t disks < <(get_disk_devices "${DOMAIN}")

    local rc=0

    for disk_line in "${disks[@]}"; do
        local dev
        dev=$(echo "${disk_line}" | awk '{print $1}')
        local src_path
        src_path=$(echo "${disk_line}" | awk '{print $2}')

        if [[ -z "${src_path}" || "${src_path}" == "-" ]]; then
            continue
        fi

        local ext="qcow2"
        if [[ "${BACKUP_FORMAT}" == "raw" ]]; then
            ext="raw"
        fi

        local dest="${backup_dir}/${dev}.${ext}"
        log_info "  Backing up ${dev} (${src_path}) -> ${dest}"

        local -a cmd=(qemu-img convert -f "${BACKUP_FORMAT}" -O "${BACKUP_FORMAT}")

        if [[ -n "${COMPRESS}" ]]; then
            cmd+=(-c)
        fi

        cmd+=("${src_path}" "${dest}")

        if ! dry_run "${cmd[@]}"; then
            log_error "Failed to backup ${dev}"
            rc=3
        fi
    done

    echo "${DOMAIN} $(date -Iseconds) FULL" > "${backup_dir}/manifest.txt"

    if (( rc == 0 )); then
        log_info "Full backup complete: ${backup_dir}"
    else
        log_warn "Full backup completed with errors (partial failure)."
    fi

    return ${rc}
}

# ---------------------------------------------------------------------------
# action_incremental
# ---------------------------------------------------------------------------
action_incremental() {
    log_info "Starting incremental backup of domain '${DOMAIN}'..."
    log_info "Base snapshot: ${BASE_SNAPSHOT}"

    local backup_dir
    backup_dir=$(prepare_output_dir "${OUTPUT_DIR}")

    log_info "Backup directory: ${backup_dir}"

    local -a disks
    mapfile -t disks < <(get_disk_devices "${DOMAIN}")

    local rc=0
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    for disk_line in "${disks[@]}"; do
        local dev
        dev=$(echo "${disk_line}" | awk '{print $1}')
        local src_path
        src_path=$(echo "${disk_line}" | awk '{print $2}')

        if [[ -z "${src_path}" || "${src_path}" == "-" ]]; then
            continue
        fi

        local bitmap_name="bitmap-${dev}-${timestamp}"
        local dest="${backup_dir}/${dev}-incr.qcow2"

        log_info "  Creating bitmap '${bitmap_name}' on ${src_path}..."
        if ! dry_run qemu-img bitmap --add "${src_path}" "${bitmap_name}"; then
            log_warn "  Failed to add bitmap for ${dev}; skipping."
            rc=3
            continue
        fi

        log_info "  Incremental backup ${dev} with bitmap -> ${dest}"
        local -a cmd=(qemu-img convert -f qcow2 -O qcow2)

        if [[ -n "${COMPRESS}" ]]; then
            cmd+=(-c)
        fi

        cmd+=(-l "${bitmap_name}" "${src_path}" "${dest}")

        if ! dry_run "${cmd[@]}"; then
            log_error "Failed incremental backup for ${dev}"
            rc=3
        fi
    done

    echo "${DOMAIN} $(date -Iseconds) INCREMENTAL base=${BASE_SNAPSHOT}" > "${backup_dir}/manifest.txt"

    if (( rc == 0 )); then
        log_info "Incremental backup complete: ${backup_dir}"
    else
        log_warn "Incremental backup completed with partial failures."
    fi

    return ${rc}
}

# ---------------------------------------------------------------------------
# action_live
# ---------------------------------------------------------------------------
action_live() {
    log_info "Starting live backup of domain '${DOMAIN}'..."

    local backup_dir
    backup_dir=$(prepare_output_dir "${OUTPUT_DIR}")

    log_info "Backup directory: ${backup_dir}"

    log_info "Freezing filesystems in domain '${DOMAIN}'..."
    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        virsh_cmd fsfreeze freeze "${DOMAIN}" || {
            log_warn "fsfreeze not available or failed; proceeding without freeze."
        }

        sleep 2
    fi

    local -a disks
    mapfile -t disks < <(get_disk_devices "${DOMAIN}")

    local rc=0

    for disk_line in "${disks[@]}"; do
        local dev
        dev=$(echo "${disk_line}" | awk '{print $1}')
        local src_path
        src_path=$(echo "${disk_line}" | awk '{print $2}')

        if [[ -z "${src_path}" || "${src_path}" == "-" ]]; then
            continue
        fi

        local dest="${backup_dir}/${dev}.qcow2"
        log_info "  Live backup ${dev} -> ${dest}"

        if ! dry_run qemu-img convert -f qcow2 -O qcow2 "${src_path}" "${dest}"; then
            log_error "Failed live backup for ${dev}"
            rc=3
        fi
    done

    log_info "Thawing filesystems..."
    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        virsh_cmd fsfreeze thaw "${DOMAIN}" 2>/dev/null || true
    fi

    echo "${DOMAIN} $(date -Iseconds) LIVE" > "${backup_dir}/manifest.txt"

    if (( rc == 0 )); then
        log_info "Live backup complete: ${backup_dir}"
    else
        log_warn "Live backup completed with partial failures."
    fi

    return ${rc}
}

# ---------------------------------------------------------------------------
# action_offline
# ---------------------------------------------------------------------------
action_offline() {
    log_info "Starting offline backup of domain '${DOMAIN}'..."

    local was_running=false
    local state
    state=$(virsh_cmd domstate "${DOMAIN}" 2>/dev/null || echo "unknown")

    if [[ "${state}" == "running" ]]; then
        was_running=true
        log_info "  VM is running; shutting down gracefully..."

        virsh_cmd shutdown "${DOMAIN}" --mode acpi || true

        local elapsed=0
        while (( elapsed < FREEZE_TIMEOUT )); do
            local current_state
            current_state=$(virsh_cmd domstate "${DOMAIN}" 2>/dev/null || echo "unknown")
            if [[ "${current_state}" == "shut off" || "${current_state}" == "shut down" ]]; then
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done

        if [[ "${current_state}" != "shut off" && "${current_state}" != "shut down" ]]; then
            log_warn "Graceful shutdown timed out; force destroying."
            virsh_cmd destroy "${DOMAIN}" 2>/dev/null || true
            sleep 2
        fi
    fi

    log_info "  VM is stopped. Proceeding with backup..."
    action_full

    if [[ "${was_running}" == "true" ]]; then
        log_info "  Restarting VM..."
        dry_run virsh_cmd start "${DOMAIN}"
    fi

    log_info "Offline backup complete."
}

# ---------------------------------------------------------------------------
# action_list
# ---------------------------------------------------------------------------
action_list() {
    log_info "Snapshots for domain '${DOMAIN}':"
    virsh_cmd snapshot-list "${DOMAIN}" 2>/dev/null || echo "  (no snapshots)"
    echo ""

    log_info "Domain block devices:"
    virsh_cmd domblklist "${DOMAIN}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs virsh qemu-img
    require_libvirt "${CONNECT_URI}"

    case "${ACTION}" in
        full)         action_full ;;
        incremental)  action_incremental ;;
        live)         action_live ;;
        offline)      action_offline ;;
        list)         action_list ;;
    esac
}

main "$@"
