#!/usr/bin/env bash
# =============================================================================
# kvm-qemu-direct.sh - Direct QEMU control (bypassing libvirt)
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: launch, monitor, migrate, info, kill
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
VM_NAME=""
VM_RAM=""
VM_VCPUS=""
VM_DISK=""
VM_CDROM=""
VM_NET=""
VM_DISPLAY=""
DAEMONIZE=""
VM_BIOS=""
QMP_SOCKET=""
DEST_URI=""
MIGRATE_ONLINE=""
QMP_COMMAND=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-qemu-direct.sh" "Direct QEMU control (no libvirt)"
    cat <<'HEADER'
Usage: kvm-qemu-direct.sh [OPTIONS] <ACTION>

 ACTIONS:
   launch     Launch a QEMU VM directly
   monitor    Send QMP command to a running VM
   migrate    Migrate a VM to another host
   info       Query VM status via QMP
   kill       Stop and quit a VM via QMP
HEADER
    cat <<EOF

 LAUNCH:
   --name <name>                VM name (required)
   --ram <MB>                   Memory in MB (required)
   --vcpus <N>                  Number of vCPUs (required)
   --disk <path>                Disk image path (required)
   --cdrom <path>               CD-ROM ISO path
   --net <spec>                 Network spec: user, tap=TAP, bridge=BR
   --display <spec>             Display: vnc=:0, spice, none
   --daemonize                  Run as background daemon
   --bios <type>                BIOS: OVMF (UEFI), SeaBIOS (default)

 MONITOR:
   --name <name>                VM name (required, used for socket path)
   --command <cmd>              QMP command to send (required)
   --socket <path>              QMP socket path (default: /tmp/qmp-<name>.sock)

 MIGRATE:
   --name <name>                VM name (required)
   --dest-uri <uri>             QEMU monitor destination URI (required)
   --online                     Online (live) migration

 INFO:
   --name <name>                VM name (required)
   --socket <path>              QMP socket path

 KILL:
   --name <name>                VM name (required)
   --socket <path>              QMP socket path

 GENERAL:
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-qemu-direct.sh launch --name test01 --ram 2048 --vcpus 2 --disk /images/test01.qcow2 --display vnc=:0 --daemonize
   kvm-qemu-direct.sh launch --name uefi01 --ram 4096 --vcpus 4 --disk /images/uefi01.qcow2 --bios OVMF --net bridge=br0 --daemonize
   kvm-qemu-direct.sh monitor --name test01 --command "info status"
   kvm-qemu-direct.sh info --name test01
   kvm-qemu-direct.sh migrate --name test01 --dest-uri tcp:10.0.0.2:4444 --online
   kvm-qemu-direct.sh kill --name test01
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
            launch|monitor|migrate|info|kill)
                ACTION="$1"
                shift
                ;;
            --name)
                VM_NAME="$2"
                shift 2
                ;;
            --ram)
                VM_RAM="$2"
                shift 2
                ;;
            --vcpus)
                VM_VCPUS="$2"
                shift 2
                ;;
            --disk)
                VM_DISK="$2"
                shift 2
                ;;
            --cdrom)
                VM_CDROM="$2"
                shift 2
                ;;
            --net)
                VM_NET="$2"
                shift 2
                ;;
            --display)
                VM_DISPLAY="$2"
                shift 2
                ;;
            --daemonize)
                DAEMONIZE="-daemonize"
                shift
                ;;
            --bios)
                VM_BIOS="$2"
                shift 2
                ;;
            --socket)
                QMP_SOCKET="$2"
                shift 2
                ;;
            --command)
                QMP_COMMAND="$2"
                shift 2
                ;;
            --dest-uri)
                DEST_URI="$2"
                shift 2
                ;;
            --online)
                MIGRATE_ONLINE="-d migrate:blk"
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
        launch)
            if [[ -z "${VM_NAME}" || -z "${VM_RAM}" || -z "${VM_VCPUS}" || -z "${VM_DISK}" ]]; then
                log_error "launch requires --name, --ram, --vcpus, and --disk"
                exit 2
            fi
            ;;
        monitor)
            if [[ -z "${VM_NAME}" || -z "${QMP_COMMAND}" ]]; then
                log_error "monitor requires --name and --command"
                exit 2
            fi
            ;;
        migrate)
            if [[ -z "${VM_NAME}" || -z "${DEST_URI}" ]]; then
                log_error "migrate requires --name and --dest-uri"
                exit 2
            fi
            ;;
        info|kill)
            if [[ -z "${VM_NAME}" ]]; then
                log_error "${ACTION} requires --name"
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
# get_socket_path
# ---------------------------------------------------------------------------
get_socket_path() {
    local name="${1:-${VM_NAME}}"
    if [[ -n "${QMP_SOCKET}" ]]; then
        echo "${QMP_SOCKET}"
    else
        echo "/tmp/qmp-${name}.sock"
    fi
}

# ---------------------------------------------------------------------------
# send_qmp_command
# ---------------------------------------------------------------------------
send_qmp_command() {
    local socket_path="$1"
    local command="$2"

    if [[ ! -S "${socket_path}" ]]; then
        log_error "QMP socket not found: ${socket_path}"
        return 1
    fi

    # Try socat first, then nc
    local qmp_init='{"execute":"qmp_capabilities"}'
    local qmp_cmd="${command}"

    if command -v socat &>/dev/null; then
        echo -e "${qmp_init}\n${qmp_cmd}" | socat - UNIX-CONNECT:"${socket_path}" 2>/dev/null
    elif command -v ncat &>/dev/null; then
        echo -e "${qmp_init}\n${qmp_cmd}" | ncat -U "${socket_path}" 2>/dev/null
    elif command -v nc &>/dev/null; then
        echo -e "${qmp_init}\n${qmp_cmd}" | nc -U "${socket_path}" 2>/dev/null
    else
        log_error "No socket client found (install socat, ncat, or nc-openbsd)."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# action_launch
# ---------------------------------------------------------------------------
action_launch() {
    log_info "Launching QEMU VM '${VM_NAME}'..."

    local -a cmd=(qemu-system-x86_64)
    cmd+=(-name "${VM_NAME}")
    cmd+=(-m "${VM_RAM}")
    cmd+=(-smp "${VM_VCPUS}")
    cmd+=(-enable-kvm)

    # Disk
    cmd+=(-drive "file=${VM_DISK},format=qcow2,if=none,id=drive-virtio-disk0")
    cmd+=(-device "virtio-blk-pci,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1")

    # CD-ROM
    if [[ -n "${VM_CDROM}" ]]; then
        cmd+=(-drive "file=${VM_CDROM},media=cdrom,if=none,id=drive-ide0-1-0")
        cmd+=(-device "ide-cd,bus=ide.1,drive=drive-ide0-1-0,id=ide0-1-0")
    fi

    # Network
    if [[ -n "${VM_NET}" ]]; then
        case "${VM_NET}" in
            user*)
                cmd+=(-netdev "user,id=net0")
                cmd+=(-device "virtio-net-pci,netdev=net0")
                ;;
            tap=*)
                local tap_dev="${VM_NET#tap=}"
                cmd+=(-netdev "tap,id=net0,ifname=${tap_dev},script=no,downscript=no")
                cmd+=(-device "virtio-net-pci,netdev=net0")
                ;;
            bridge=*)
                local br_dev="${VM_NET#bridge=}"
                cmd+=(-netdev "bridge,id=net0,br=${br_dev}")
                cmd+=(-device "virtio-net-pci,netdev=net0")
                ;;
            *)
                cmd+=(-netdev "${VM_NET},id=net0")
                cmd+=(-device "virtio-net-pci,netdev=net0")
                ;;
        esac
    else
        cmd+=(-netdev "user,id=net0")
        cmd+=(-device "virtio-net-pci,netdev=net0")
    fi

    # Display
    if [[ -n "${VM_DISPLAY}" ]]; then
        case "${VM_DISPLAY}" in
            vnc=*)
                cmd+=(-vnc "${VM_DISPLAY#vnc=}" -no-acpi)
                ;;
            spice)
                cmd+=(-spice "port=5930,disable-ticketing=on")
                cmd+=(-device virtio-serial-pci)
                cmd+=(-device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0)
                cmd+=(-chardev "spicechannel,id=spicechannel0,name=none")
                ;;
            none)
                cmd+=(-display none)
                ;;
            *)
                cmd+=(-display "${VM_DISPLAY}")
                ;;
        esac
    else
        cmd+=(-vnc :0 -no-acpi)
    fi

    # BIOS
    if [[ "${VM_BIOS}" == "OVMF" || "${VM_BIOS}" == "uefi" ]]; then
        cmd+=(-bios /usr/share/OVMF/OVMF_CODE.fd)
    else
        cmd+=(-bios /usr/share/seabios/bios-256k.bin) 2>/dev/null || true
    fi

    # QMP socket
    local socket_path
    socket_path=$(get_socket_path)
    cmd+=(-qmp "unix:${socket_path},server,nowait")

    # Serial console
    cmd+=(-serial mon:stdio)
    cmd+=(-monitor none)

    # Daemonize
    if [[ -n "${DAEMONIZE}" ]]; then
        cmd+=("${DAEMONIZE}")
    fi

    # Machine type
    cmd+=(-machine q35,accel=kvm)

    # CPU
    cmd+=(-cpu host)

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"

    log_info "QEMU VM '${VM_NAME}' launched."
    log_info "QMP socket: ${socket_path}"
}

# ---------------------------------------------------------------------------
# action_monitor
# ---------------------------------------------------------------------------
action_monitor() {
    local socket_path
    socket_path=$(get_socket_path)
    log_info "Sending QMP command to '${VM_NAME}' via ${socket_path}..."

    local result
    result=$(send_qmp_command "${socket_path}" "${QMP_COMMAND}") || {
        log_error "Failed to send QMP command."
        return 1
    }

    echo "${result}"
}

# ---------------------------------------------------------------------------
# action_migrate
# ---------------------------------------------------------------------------
action_migrate() {
    log_info "Migrating VM '${VM_NAME}' to ${DEST_URI}..."

    local socket_path
    socket_path=$(get_socket_path)

    local migrate_cmd="{\"execute\":\"migrate\",\"arguments\":{\"uri\":\"${DEST_URI}\",\"detach\":true}"
    if [[ -n "${MIGRATE_ONLINE}" ]]; then
        migrate_cmd+=",\"blk\":true,\"inc\":true"
    fi
    migrate_cmd+="}"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would migrate ${VM_NAME} to ${DEST_URI}"
        return 0
    fi

    send_qmp_command "${socket_path}" "${migrate_cmd}" || {
        log_error "Migration command failed."
        return 1
    }

    log_info "Migration initiated for '${VM_NAME}'."
    log_info "Monitor with: $(basename "$0") monitor --name ${VM_NAME} --command '{\"execute\":\"query-migrate\"}'"
}

# ---------------------------------------------------------------------------
# action_info
# ---------------------------------------------------------------------------
action_info() {
    local socket_path
    socket_path=$(get_socket_path)

    log_info "Querying status of VM '${VM_NAME}'..."

    if [[ ! -S "${socket_path}" ]]; then
        log_warn "QMP socket not found: ${socket_path}"
        log_info "VM '${VM_NAME}' may not be running (or not managed by this script)."
        return 1
    fi

    echo "=== Status ==="
    send_qmp_command "${socket_path}" '{"execute":"query-status"}' 2>/dev/null || echo "  (failed to query)"
    echo ""

    echo "=== Name ==="
    send_qmp_command "${socket_path}" '{"execute":"query-name"}' 2>/dev/null || echo "  (failed to query)"
    echo ""

    echo "=== Version ==="
    send_qmp_command "${socket_path}" '{"execute":"query-version"}' 2>/dev/null || echo "  (failed to query)"
    echo ""
}

# ---------------------------------------------------------------------------
# action_kill
# ---------------------------------------------------------------------------
action_kill() {
    local socket_path
    socket_path=$(get_socket_path)

    log_info "Killing VM '${VM_NAME}'..."

    if [[ ! -S "${socket_path}" ]]; then
        log_warn "QMP socket not found: ${socket_path}"
        return 1
    fi

    log_info "  Sending stop..."
    send_qmp_command "${socket_path}" '{"execute":"stop"}' 2>/dev/null || true

    sleep 1

    log_info "  Sending quit..."
    send_qmp_command "${socket_path}" '{"execute":"quit"}' 2>/dev/null || true

    log_info "VM '${VM_NAME}' killed."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs qemu-system-x86_64

    case "${ACTION}" in
        launch)  action_launch ;;
        monitor) action_monitor ;;
        migrate) action_migrate ;;
        info)    action_info ;;
        kill)    action_kill ;;
    esac
}

main "$@"
