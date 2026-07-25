#!/usr/bin/env bash
# =============================================================================
# kvm-snapshot.sh - Snapshot management for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: create, list, revert, delete, external, commit
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
SNAPSHOT_NAME=""
SNAPSHOT_DESC=""
LIVE_SNAPSHOT=""
QUIESCE=""
NO_METADATA=""
ATOMIC=""
SNAPSHOT_FILE=""
TOPLOGY=""
COMMIT_FILE=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-snapshot.sh" "Snapshot management for KVM"
    cat <<'HEADER'
Usage: kvm-snapshot.sh [OPTIONS] <ACTION>

 ACTIONS:
   create       Create a snapshot
   list         List snapshots for a domain
   revert       Revert to a snapshot
   delete       Delete a snapshot
   external     Create an external snapshot (separate disk/state)
   commit       Commit an external snapshot back to base
HEADER
    cat <<EOF

 CREATE:
   --domain <name>              Domain name (required)
   --name <name>                Snapshot name (required)
   --description <text>         Snapshot description
   --live                       Snapshot while VM is running
   --quiesce                    Quiesce filesystem before snapshot
   --no-metadata                Skip metadata (only disk snapshot)
   --atomic                     Atomic snapshot (all-or-nothing)

 LIST:
   --domain <name>              Domain name (required)
   --topology                   Show snapshot tree topology

 REVERT / DELETE:
   --domain <name>              Domain name (required)
   --name <name>                Snapshot name (required)

 EXTERNAL:
   --domain <name>              Domain name (required)
   --name <name>                Snapshot name (required)
   --file <path>                External disk snapshot file path

 COMMIT:
   --domain <name>              Domain name (required)
   --file <path>                External snapshot file to commit

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-snapshot.sh create --domain web01 --name pre-upgrade --description "Before kernel upgrade"
   kvm-snapshot.sh create --domain web01 --name live-snap --live --quiesce
   kvm-snapshot.sh list --domain web01
   kvm-snapshot.sh list --domain web01 --topology
   kvm-snapshot.sh revert --domain web01 --name pre-upgrade
   kvm-snapshot.sh delete --domain web01 --name old-snap
   kvm-snapshot.sh external --domain web01 --name ext-snap-01 --file /var/lib/libvirt/snapshots/web01-snap01.qcow2
   kvm-snapshot.sh commit --domain web01 --file /var/lib/libvirt/snapshots/web01-snap01.qcow2
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
            create|list|revert|delete|external|commit)
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
            --name)
                SNAP_NAME_ARG="$2"
                shift 2
                ;;
            --description)
                SNAPSHOT_DESC="$2"
                shift 2
                ;;
            --live)
                LIVE_SNAPSHOT="--live"
                shift
                ;;
            --quiesce)
                QUIESCE="--quiesce"
                shift
                ;;
            --no-metadata)
                NO_METADATA="--no-metadata"
                shift
                ;;
            --atomic)
                ATOMIC="--atomic"
                shift
                ;;
            --file)
                SNAPSHOT_FILE="$2"
                shift 2
                ;;
            --topology)
                TOPOLOGY="--tree"
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

# Globals (set by parse_args)
SNAP_NAME_ARG=""

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
            if [[ -z "${DOMAIN}" || -z "${SNAP_NAME_ARG}" ]]; then
                log_error "create requires --domain and --name"
                exit 2
            fi
            ;;
        list)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "list requires --domain"
                exit 2
            fi
            ;;
        revert|delete)
            if [[ -z "${DOMAIN}" || -z "${SNAP_NAME_ARG}" ]]; then
                log_error "${ACTION} requires --domain and --name"
                exit 2
            fi
            ;;
        external)
            if [[ -z "${DOMAIN}" || -z "${SNAP_NAME_ARG}" || -z "${SNAPSHOT_FILE}" ]]; then
                log_error "external requires --domain, --name, and --file"
                exit 2
            fi
            ;;
        commit)
            if [[ -z "${DOMAIN}" || -z "${SNAPSHOT_FILE}" ]]; then
                log_error "commit requires --domain and --file"
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
# action_create
# ---------------------------------------------------------------------------
action_create() {
    log_info "Creating snapshot '${SNAP_NAME_ARG}' for domain '${DOMAIN}'..."

    local -a cmd=(virsh_cmd snapshot-create-as "${DOMAIN}" "${SNAP_NAME_ARG}")

    if [[ -n "${SNAPSHOT_DESC}" ]]; then
        cmd+=(--description "${SNAPSHOT_DESC}")
    fi

    if [[ -n "${LIVE_SNAPSHOT}" ]]; then
        cmd+=("${LIVE_SNAPSHOT}")
    fi

    if [[ -n "${QUIESCE}" ]]; then
        cmd+=("${QUIESCE}")
    fi

    if [[ -n "${NO_METADATA}" ]]; then
        cmd+=("${NO_METADATA}")
    fi

    if [[ -n "${ATOMIC}" ]]; then
        cmd+=("${ATOMIC}")
    fi

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "Snapshot '${SNAP_NAME_ARG}' created."
}

# ---------------------------------------------------------------------------
# action_list
# ---------------------------------------------------------------------------
action_list() {
    log_info "Snapshots for domain '${DOMAIN}':"
    echo ""

    if [[ -n "${TOPOLOGY}" ]]; then
        virsh_cmd snapshot-list "${DOMAIN}" --tree
    else
        virsh_cmd snapshot-list "${DOMAIN}"
    fi
}

# ---------------------------------------------------------------------------
# action_revert
# ---------------------------------------------------------------------------
action_revert() {
    log_info "Reverting domain '${DOMAIN}' to snapshot '${SNAP_NAME_ARG}'..."
    dry_run virsh_cmd snapshot-revert "${DOMAIN}" "${SNAP_NAME_ARG}"
    log_info "Domain '${DOMAIN}' reverted to snapshot '${SNAP_NAME_ARG}'."
}

# ---------------------------------------------------------------------------
# action_delete
# ---------------------------------------------------------------------------
action_delete() {
    log_info "Deleting snapshot '${SNAP_NAME_ARG}' from domain '${DOMAIN}'..."
    dry_run virsh_cmd snapshot-delete "${DOMAIN}" "${SNAP_NAME_ARG}"
    log_info "Snapshot '${SNAP_NAME_ARG}' deleted."
}

# ---------------------------------------------------------------------------
# action_external
# ---------------------------------------------------------------------------
action_external() {
    log_info "Creating external snapshot '${SNAP_NAME_ARG}' for domain '${DOMAIN}'..."

    local snap_file="${SNAPSHOT_FILE}"
    local state_file="${snap_file%.qcow2}.state"

    local -a cmd=(virsh_cmd snapshot-create-as "${DOMAIN}" "${SNAP_NAME_ARG}")

    if [[ -n "${SNAPSHOT_DESC}" ]]; then
        cmd+=(--description "${SNAPSHOT_DESC}")
    fi

    cmd+=(--disk-only --no-metadata)

    if [[ -n "${LIVE_SNAPSHOT}" ]]; then
        cmd+=("${LIVE_SNAPSHOT}")
    fi

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"

    log_info "External snapshot created. Disk state saved to: ${snap_file}"
    log_info "Use 'commit' action to merge back into the base image."
}

# ---------------------------------------------------------------------------
# action_commit
# ---------------------------------------------------------------------------
action_commit() {
    log_info "Committing external snapshot ${SNAPSHOT_FILE} to base..."

    dry_run qemu-img commit "${SNAPSHOT_FILE}"
    log_info "External snapshot committed."
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
        create)   action_create ;;
        list)     action_list ;;
        revert)   action_revert ;;
        delete)   action_delete ;;
        external) action_external ;;
        commit)   action_commit ;;
    esac
}

main "$@"
