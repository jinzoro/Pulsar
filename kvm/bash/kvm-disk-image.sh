#!/usr/bin/env bash
# =============================================================================
# kvm-disk-image.sh — Disk image management for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: create, convert, resize, snapshot, info, check, benchmark,
#             sparsify, customize, resize-fs
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
FILE=""
FORMAT="qcow2"
OUTPUT=""
OUTPUT_FORMAT=""
SIZE=""
PREALLOCATION="off"
BACKING_FILE=""
COMPRESS=""
SNAPSHOT_NAME=""
SNAPSHOT_ACTION="create"
HOSTNAME=""
SSH_KEYS_FILE=""
PASSWORD=""
INSTALL_PKG=""
RUN_SCRIPT=""
SELINUX_RELABEL=""
CUSTOMIZE_ARGS=()

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-disk-image.sh" "Disk image management for KVM"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <ACTION>

 ACTIONS:
   create       Create a new disk image
   convert      Convert disk image to another format
   resize       Resize a disk image
   snapshot     Manage internal snapshots (create/delete/revert)
   info         Display disk image information
   check        Check disk image integrity
   benchmark    Run I/O benchmark with fio
   sparsify     Sparsify a disk image (reclaim unused space)
   customize    Customize a disk image (virt-customize)
   resize-fs    Resize filesystem to fill disk (virt-resize)

 CREATE OPTIONS:
   --file <path>                Disk image file path (required)
   --format <fmt>               Format: qcow2 (default), raw, vmdk, vhdx
   --size <size>                Disk size (e.g. 20G, 512M) (required)
   --preallocation <mode>       Preallocation: off, metadata, falloc, full
   --backing-file <path>        Backing file for overlays

 CONVERT OPTIONS:
   --file <path>                Source file (required)
   --format <fmt>               Source format
   --output <path>              Output file (required)
   --output-format <fmt>        Output format
   --compress                   Enable compression

 RESIZE OPTIONS:
   --file <path>                Disk image file (required)
   --size <size>                New size (+10G for relative, 30G for absolute)

 SNAPSHOT OPTIONS:
   --file <path>                Disk image file (required)
   --snapshot-name <name>       Snapshot name
   --snapshot-create            Create internal snapshot (default)
   --snapshot-delete            Delete internal snapshot
   --snapshot-revert            Revert to internal snapshot

 INFO/CHECK OPTIONS:
   --file <path>                Disk image file (required)

 BENCHMARK OPTIONS:
   --file <path>                Disk image file (required)

 SPARSIFY OPTIONS:
   --file <path>                Source disk image (required)
   --output <path>              Output file (required)

 CUSTOMIZE OPTIONS:
   --file <path>                Disk image file (required)
   --hostname <name>            Set hostname
   --ssh-keys-file <path>       SSH authorized_keys file
   --password <pass>            Set user password
   --install-pkg <pkgs>         Comma-separated packages to install
   --run-script <path>          Script to run inside guest
   --selinux-relabel            Relabel SELinux contexts

 RESIZE-FS OPTIONS:
   --file <path>                Disk image file (required)

 GENERAL OPTIONS:
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments
   3   Partial failure

EXAMPLES:
   $(basename "$0") create --file /var/lib/libvirt/images/vm.qcow2 --size 20G --format qcow2
   $(basename "$0") convert --file vm.qcow2 --output vm.raw --output-format raw --compress
   $(basename "$0") resize --file vm.qcow2 --size +10G
   $(basename "$0") customize --file vm.qcow2 --hostname myserver --install-pkg vim,curl --ssh-keys-file ~/.ssh/id_rsa.pub
   $(basename "$0") benchmark --file vm.qcow2
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
            create|convert|resize|snapshot|info|check|benchmark|sparsify|customize|resize-fs)
                ACTION="$1"
                shift
                ;;
            --file)
                FILE="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                shift 2
                ;;
            --output)
                OUTPUT="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --size)
                SIZE="$2"
                shift 2
                ;;
            --preallocation)
                PREALLOCATION="$2"
                shift 2
                ;;
            --backing-file)
                BACKING_FILE="$2"
                shift 2
                ;;
            --compress)
                COMPRESS="-c"
                shift
                ;;
            --snapshot-name)
                SNAPSHOT_NAME="$2"
                shift 2
                ;;
            --snapshot-create)
                SNAPSHOT_ACTION="create"
                shift
                ;;
            --snapshot-delete)
                SNAPSHOT_ACTION="delete"
                shift
                ;;
            --snapshot-revert)
                SNAPSHOT_ACTION="revert"
                shift
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --ssh-keys-file)
                SSH_KEYS_FILE="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --install-pkg)
                INSTALL_PKG="$2"
                shift 2
                ;;
            --run-script)
                RUN_SCRIPT="$2"
                shift 2
                ;;
            --selinux-relabel)
                SELINUX_RELABEL="yes"
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
        create)
            if [[ -z "${FILE}" || -z "${SIZE}" ]]; then
                log_error "create requires --file and --size"
                exit 2
            fi
            ;;
        convert)
            if [[ -z "${FILE}" || -z "${OUTPUT}" ]]; then
                log_error "convert requires --file and --output"
                exit 2
            fi
            ;;
        resize)
            if [[ -z "${FILE}" || -z "${SIZE}" ]]; then
                log_error "resize requires --file and --size"
                exit 2
            fi
            ;;
        snapshot)
            if [[ -z "${FILE}" ]]; then
                log_error "snapshot requires --file"
                exit 2
            fi
            if [[ -z "${SNAPSHOT_NAME}" ]]; then
                log_error "snapshot requires --snapshot-name"
                exit 2
            fi
            ;;
        info|check|benchmark|resize-fs)
            if [[ -z "${FILE}" ]]; then
                log_error "${ACTION} requires --file"
                exit 2
            fi
            ;;
        sparsify)
            if [[ -z "${FILE}" || -z "${OUTPUT}" ]]; then
                log_error "sparsify requires --file and --output"
                exit 2
            fi
            ;;
        customize)
            if [[ -z "${FILE}" ]]; then
                log_error "customize requires --file"
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
# action_create
# ---------------------------------------------------------------------------
action_create() {
    log_info "Creating disk image: ${FILE} (${SIZE}, ${FORMAT})..."

    local -a cmd=(qemu-img create -f "${FORMAT}")

    if [[ "${PREALLOCATION}" != "off" ]]; then
        case "${FORMAT}" in
            qcow2)
                cmd+=(-o "preallocation=${PREALLOCATION}")
                ;;
            raw)
                if [[ "${PREALLOCATION}" == "full" ]]; then
                    cmd+=(-o "preallocation=full")
                fi
                ;;
        esac
    fi

    if [[ -n "${BACKING_FILE}" ]]; then
        cmd+=(-b "${BACKING_FILE}" -F "${FORMAT}")
    fi

    cmd+=("${FILE}" "${SIZE}")

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "Disk image created: ${FILE}"
}

# ---------------------------------------------------------------------------
# action_convert
# ---------------------------------------------------------------------------
action_convert() {
    log_info "Converting ${FILE} -> ${OUTPUT}..."

    local -a cmd=(qemu-img convert -f "${FORMAT}")

    if [[ -n "${OUTPUT_FORMAT}" ]]; then
        cmd+=(-O "${OUTPUT_FORMAT}")
    fi

    if [[ -n "${COMPRESS}" ]]; then
        cmd+=("${COMPRESS}")
    fi

    cmd+=("${FILE}" "${OUTPUT}")

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "Conversion complete: ${OUTPUT}"
}

# ---------------------------------------------------------------------------
# action_resize
# ---------------------------------------------------------------------------
action_resize() {
    log_info "Resizing ${FILE} to ${SIZE}..."

    dry_run qemu-img resize "${FILE}" "${SIZE}"
    log_info "Disk resized."
}

# ---------------------------------------------------------------------------
# action_snapshot
# ---------------------------------------------------------------------------
action_snapshot() {
    case "${SNAPSHOT_ACTION}" in
        create)
            log_info "Creating snapshot '${SNAPSHOT_NAME}' on ${FILE}..."
            dry_run qemu-img snapshot -c "${SNAPSHOT_NAME}" "${FILE}"
            log_info "Snapshot created."
            ;;
        delete)
            log_info "Deleting snapshot '${SNAPSHOT_NAME}' from ${FILE}..."
            dry_run qemu-img snapshot -d "${SNAPSHOT_NAME}" "${FILE}"
            log_info "Snapshot deleted."
            ;;
        revert)
            log_info "Reverting to snapshot '${SNAPSHOT_NAME}' on ${FILE}..."
            dry_run qemu-img snapshot -a "${SNAPSHOT_NAME}" "${FILE}"
            log_info "Reverted to snapshot."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# action_info
# ---------------------------------------------------------------------------
action_info() {
    log_info "Disk image info for ${FILE}:"
    echo "============================================"
    qemu-img info "${FILE}"
    echo ""
    echo "Allocated: $(qemu-img info --output=json "${FILE}" 2>/dev/null | grep '"allocated"' || echo 'N/A')"
    echo "Virtual:   $(qemu-img info --output=json "${FILE}" 2>/dev/null | grep '"virtual-size"' || echo 'N/A')"
}

# ---------------------------------------------------------------------------
# action_check
# ---------------------------------------------------------------------------
action_check() {
    log_info "Checking image integrity: ${FILE}..."

    if qemu-img check "${FILE}" 2>&1; then
        log_info "Image check passed: ${FILE}"
    else
        log_error "Image check failed: ${FILE}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# action_benchmark
# ---------------------------------------------------------------------------
action_benchmark() {
    check_prereqs fio
    log_info "Running I/O benchmark on ${FILE}..."

    local runtime=10
    local filename="${FILE}"

    log_info "=== Sequential Read ==="
    fio --name=seq-read --filename="${filename}" --ioengine=libaio \
        --direct=1 --bs=128k --size=256M --numjobs=1 \
        --rw=read --runtime="${runtime}" --time_based \
        --group_reporting --output-format=text 2>/dev/null || true

    echo ""
    log_info "=== Sequential Write ==="
    fio --name=seq-write --filename="${filename}" --ioengine=libaio \
        --direct=1 --bs=128k --size=256M --numjobs=1 \
        --rw=write --runtime="${runtime}" --time_based \
        --group_reporting --output-format=text 2>/dev/null || true

    echo ""
    log_info "=== Random Read (4K) ==="
    fio --name=rand-read --filename="${filename}" --ioengine=libaio \
        --direct=1 --bs=4k --size=256M --numjobs=4 \
        --rw=randread --runtime="${runtime}" --time_based \
        --iodepth=32 --group_reporting --output-format=text 2>/dev/null || true

    echo ""
    log_info "=== Random Write (4K) ==="
    fio --name=rand-write --filename="${filename}" --ioengine=libaio \
        --direct=1 --bs=4k --size=256M --numjobs=4 \
        --rw=randwrite --runtime="${runtime}" --time_based \
        --iodepth=32 --group_reporting --output-format=text 2>/dev/null || true

    log_info "Benchmark complete."
}

# ---------------------------------------------------------------------------
# action_sparsify
# ---------------------------------------------------------------------------
action_sparsify() {
    log_info "Sparsifying ${FILE} -> ${OUTPUT}..."

    dry_run virt-sparsify "${FILE}" "${OUTPUT}"
    log_info "Sparsification complete: ${OUTPUT}"
}

# ---------------------------------------------------------------------------
# action_customize
# ---------------------------------------------------------------------------
action_customize() {
    log_info "Customizing disk image: ${FILE}..."

    local -a cmd=(virt-customize -a "${FILE}")

    if [[ -n "${HOSTNAME}" ]]; then
        cmd+=(--hostname "${HOSTNAME}")
    fi

    if [[ -n "${SSH_KEYS_FILE}" ]]; then
        cmd+=(--sshkey "${SSH_KEYS_FILE}")
    fi

    if [[ -n "${PASSWORD}" ]]; then
        cmd+=(--password "root:${PASSWORD}")
    fi

    if [[ -n "${INSTALL_PKG}" ]]; then
        IFS=',' read -ra pkgs <<< "${INSTALL_PKG}"
        cmd+=(--install "${INSTALL_PKG}")
    fi

    if [[ -n "${RUN_SCRIPT}" ]]; then
        cmd+=(--run-command "bash ${RUN_SCRIPT}")
    fi

    if [[ "${SELINUX_RELABEL:-}" == "yes" ]]; then
        cmd+=(--selinux-relabel)
    fi

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "Disk image customized."
}

# ---------------------------------------------------------------------------
# action_resize_fs
# ---------------------------------------------------------------------------
action_resize_fs() {
    log_info "Resizing filesystem in ${FILE}..."

    local tmpfile
    tmpfile=$(create_temp_file)

    dry_run virt-resize --expand "${FILE}" "${tmpfile}" "${FILE}" || {
        log_error "virt-resize failed."
        return 1
    }

    log_info "Filesystem resized."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs qemu-img

    case "${ACTION}" in
        create)     action_create ;;
        convert)    action_convert ;;
        resize)     action_resize ;;
        snapshot)   action_snapshot ;;
        info)       action_info ;;
        check)      action_check ;;
        benchmark)  action_benchmark ;;
        sparsify)   action_sparsify ;;
        customize)  action_customize ;;
        resize-fs)  action_resize_fs ;;
    esac
}

main "$@"
