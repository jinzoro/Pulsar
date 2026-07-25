#!/usr/bin/env bash
# =============================================================================
# kvm-backup-restore.sh - Backup restore operations for KVM VMs
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: restore-full, restore-incremental, verify, rebuild-chain
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
BACKUP_FILE=""
DOMAIN=""
OUTPUT_DISK=""
RESTORE_FORMAT="qcow2"
CHECKSUM=""
INCREMENTAL_FILES=""
BASE_BACKUP=""
SNAPSHOT_CHAIN=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-backup-restore.sh" "Backup restore operations for KVM"
    cat <<'HEADER'
Usage: kvm-backup-restore.sh [OPTIONS] <ACTION>

 ACTIONS:
   restore-full          Restore from a full backup
   restore-incremental   Restore from base + incremental chain
   verify                Verify backup file integrity
   rebuild-chain         Rebuild qcow2 backing chain from snapshots
HEADER
    cat <<EOF

 RESTORE-FULL:
   --backup-file <path>        Backup file to restore (required)
   --domain <name>             Target domain name (required)
   --output-disk <path>        Output disk path (required)
   --format <fmt>              Output format: qcow2 (default), raw

 RESTORE-INCREMENTAL:
   --base-backup <path>        Base backup file (required)
   --incremental-files <list>  Comma-separated incremental files (required)
   --domain <name>             Target domain name (required)
   --output-disk <path>        Output disk path (required)

 VERIFY:
   --backup-file <path>        Backup file to verify (required)
   --checksum <sha256>         Expected SHA256 checksum (optional)

 REBUILD-CHAIN:
   --snapshots <list>          Comma-separated snapshot files, base first (required)
   --domain <name>             Target domain name (for verification)

 GENERAL:
   --connect <uri>             Libvirt URI (default: qemu:///system)
   --dry-run                   Show what would be done without executing
   -h, --help                  Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments
   3   Partial failure

EXAMPLES:
   kvm-backup-restore.sh restore-full --backup-file /backups/web01/2026-01-01/sda.qcow2 --domain web01 --output-disk /var/lib/libvirt/images/web01.qcow2
   kvm-backup-restore.sh restore-incremental --base-backup /backups/base.qcow2 --incremental-files /backups/incr1.qcow2,/backups/incr2.qcow2 --domain web01 --output-disk /var/lib/libvirt/images/web01.qcow2
   kvm-backup-restore.sh verify --backup-file /backups/web01/2026-01-01/sda.qcow2
   kvm-backup-restore.sh rebuild-chain --snapshots base.qcow2,incr1.qcow2,incr2.qcow2 --domain web01
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
            restore-full|restore-incremental|verify|rebuild-chain)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --backup-file)
                BACKUP_FILE="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --output-disk)
                OUTPUT_DISK="$2"
                shift 2
                ;;
            --format)
                RESTORE_FORMAT="$2"
                shift 2
                ;;
            --checksum)
                CHECKSUM="$2"
                shift 2
                ;;
            --base-backup)
                BASE_BACKUP="$2"
                shift 2
                ;;
            --incremental-files)
                INCREMENTAL_FILES="$2"
                shift 2
                ;;
            --snapshots)
                SNAPSHOT_CHAIN="$2"
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
        restore-full)
            if [[ -z "${BACKUP_FILE}" || -z "${DOMAIN}" || -z "${OUTPUT_DISK}" ]]; then
                log_error "restore-full requires --backup-file, --domain, and --output-disk"
                exit 2
            fi
            ;;
        restore-incremental)
            if [[ -z "${BASE_BACKUP}" || -z "${INCREMENTAL_FILES}" || -z "${DOMAIN}" || -z "${OUTPUT_DISK}" ]]; then
                log_error "restore-incremental requires --base-backup, --incremental-files, --domain, and --output-disk"
                exit 2
            fi
            ;;
        verify)
            if [[ -z "${BACKUP_FILE}" ]]; then
                log_error "verify requires --backup-file"
                exit 2
            fi
            ;;
        rebuild-chain)
            if [[ -z "${SNAPSHOT_CHAIN}" ]]; then
                log_error "rebuild-chain requires --snapshots"
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
# verify_image
# ---------------------------------------------------------------------------
verify_image() {
    local file="$1"
    local expected="${2:-}"

    log_info "Verifying image: ${file}..."

    if [[ ! -f "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi

    log_info "  Running qemu-img check..."
    if ! qemu-img check "${file}" 2>&1; then
        log_error "Image check failed: ${file}"
        return 1
    fi

    if [[ -n "${expected}" ]]; then
        log_info "  Checking SHA256 checksum..."
        local actual
        actual=$(sha256sum "${file}" | awk '{print $1}')
        if [[ "${actual}" != "${expected}" ]]; then
            log_error "Checksum mismatch!"
            log_error "  Expected: ${expected}"
            log_error "  Actual:   ${actual}"
            return 1
        fi
        log_info "  Checksum verified."
    fi

    log_info "  Image info:"
    qemu-img info "${file}" 2>/dev/null || true
    log_info "Verification passed: ${file}"
}

# ---------------------------------------------------------------------------
# action_restore_full
# ---------------------------------------------------------------------------
action_restore_full() {
    log_info "Restoring full backup: ${BACKUP_FILE} -> ${OUTPUT_DISK}..."

    if [[ ! -f "${BACKUP_FILE}" ]]; then
        log_error "Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi

    log_info "  Source info:"
    qemu-img info "${BACKUP_FILE}" 2>/dev/null || true

    log_info "  Restoring to ${OUTPUT_DISK}..."

    local -a cmd=(qemu-img convert -f "${RESTORE_FORMAT}" -O "${RESTORE_FORMAT}")
    cmd+=("${BACKUP_FILE}" "${OUTPUT_DISK}")

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}" || {
        log_error "Restore failed."
        return 1
    }

    log_info "  Verifying restored image..."
    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        qemu-img check "${OUTPUT_DISK}" || {
            log_error "Restored image verification failed."
            return 1
        }
    fi

    log_info "Full restore complete: ${OUTPUT_DISK}"
}

# ---------------------------------------------------------------------------
# action_restore_incremental
# ---------------------------------------------------------------------------
action_restore_incremental() {
    log_info "Restoring incremental backup chain..."

    if [[ ! -f "${BASE_BACKUP}" ]]; then
        log_error "Base backup not found: ${BASE_BACKUP}"
        exit 1
    fi

    log_info "  Step 1: Rebase base backup -> ${OUTPUT_DISK}..."
    dry_run qemu-img convert -f qcow2 -O qcow2 "${BASE_BACKUP}" "${OUTPUT_DISK}"

    log_info "  Step 2: Applying incremental layers..."
    IFS=',' read -ra incr_files <<< "${INCREMENTAL_FILES}"

    local step=3
    for incr in "${incr_files[@]}"; do
        incr="$(echo "${incr}" | xargs)"
        if [[ ! -f "${incr}" ]]; then
            log_warn "  Incremental file not found: ${incr}; skipping."
            continue
        fi

        log_info "  Step ${step}: Applying ${incr}..."

        local tmp_img
        tmp_img=$(create_temp_file)

        dry_run qemu-img rebase -u -b "${incr}" "${OUTPUT_DISK}" || {
            log_warn "  rebase failed for ${incr}; trying overlay approach."
            dry_run qemu-img create -f qcow2 -b "${OUTPUT_DISK}" -F qcow2 "${tmp_img}"
            dry_run mv "${tmp_img}" "${OUTPUT_DISK}"
        }

        step=$((step + 1))
    done

    log_info "  Verifying final image..."
    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        qemu-img check "${OUTPUT_DISK}" || {
            log_error "Restored image verification failed."
            return 1
        }
    fi

    log_info "Incremental restore complete: ${OUTPUT_DISK}"
}

# ---------------------------------------------------------------------------
# action_verify
# ---------------------------------------------------------------------------
action_verify() {
    verify_image "${BACKUP_FILE}" "${CHECKSUM}"
}

# ---------------------------------------------------------------------------
# action_rebuild_chain
# ---------------------------------------------------------------------------
action_rebuild_chain() {
    log_info "Rebuilding qcow2 backing chain..."

    IFS=',' read -ra chain_files <<< "${SNAPSHOT_CHAIN}"

    local files=()
    for f in "${chain_files[@]}"; do
        f="$(echo "${f}" | xargs)"
        if [[ ! -f "${f}" ]]; then
            log_warn "File not found: ${f}; skipping."
            continue
        fi
        files+=("${f}")
    done

    if (( ${#files[@]} < 2 )); then
        log_error "Need at least 2 files for chain rebuild."
        exit 2
    fi

    log_info "  Chain: ${files[0]}"
    local prev="${files[0]}"

    for (( i=1; i<${#files[@]}; i++ )); do
        local current="${files[$i]}"
        local base_name
        base_name=$(basename "${current}")

        log_info "  Rebasing ${base_name} -> backing: $(basename "${prev}")"

        dry_run qemu-img rebase -u -b "${prev}" "${current}" || {
            log_warn "  Failed to rebase ${base_name}"
        }

        prev="${current}"
    done

    log_info "Backing chain rebuilt."

    if [[ -n "${DOMAIN}" ]]; then
        log_info "  Verifying with qemu-img info on last file..."
        qemu-img info "${prev}" --backing-chain 2>/dev/null || true
    fi
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
        restore-full)        action_restore_full ;;
        restore-incremental) action_restore_incremental ;;
        verify)              action_verify ;;
        rebuild-chain)       action_rebuild_chain ;;
    esac
}

main "$@"
