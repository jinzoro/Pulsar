#!/usr/bin/env bash
# =============================================================================
# kvm-vm-lifecycle.sh — VM lifecycle management via libvirt
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: create, start, stop, destroy, suspend, resume, save, restore,
#             list, autostart, define, undefine
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
NAME=""
RAM=""
VCPUS=""
DISK_PATH=""
DISK_SIZE=""
DISK_FORMAT="qcow2"
OS_VARIANT=""
NETWORK=""
GRAPHICS=""
CDROM=""
IMPORTDisk=""
CPU=""
MACHINE=""
TPM=""
UEFI=""
CLOUD_INIT=""
GRACEFUL_TIMEOUT=30
SNAPSHOT_FILE=""
LIST_FILTER="--all"
LIST_COLUMNS=""
ENABLE_AUTOSTART=""
REMOVE_STORAGE=""
NVRAM=""
XML_FILE=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-vm-lifecycle.sh" "VM lifecycle management via libvirt"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <ACTION>

 ACTIONS:
   create       Create a new VM (virt-install wrapper)
   start        Start a VM
   stop         Stop (shutdown) a VM
   destroy      Force stop a VM (power off)
   suspend      Suspend a VM (pause)
   resume       Resume a suspended VM
   save         Save VM state to file
   restore      Restore VM state from file
   list         List VMs
   autostart    Enable/disable autostart for a VM
   define       Define a VM from XML file
   undefine     Undefine a VM

 CREATE OPTIONS:
   --name <name>              VM name (required for create)
   --ram <MB>                 Memory in MB (required for create)
   --vcpus <N>                Number of vCPUs (required for create)
   --disk <path>              Disk image path
   --disk-size <size>         Disk size (e.g. 20G)
   --disk-format <fmt>        Disk format: qcow2 (default), raw, vmdk
   --os-variant <variant>     OS variant (e.g. linux2022, win11)
   --network <spec>           Network spec: bridge=BRIDGE or nat
   --graphics <spec>          Graphics: vnc, spice, none
   --cdrom <path>             CD-ROM ISO path
   --import-disk <path>       Import existing disk
   --cpu <model>              CPU model (e.g. host-passthrough)
   --machine <type>           Machine type (q35, pc)
   --tpm <spec>               TPM spec (e.g. version=2.0,model=tpm-crb)
   --uefi                     Use UEFI boot (OVMF)
   --cloud-init               Enable cloud-init

 START/STOP/DESTROY OPTIONS:
   --domain <name>            Domain name or UUID (required)
   --graceful <sec>           Graceful shutdown timeout in seconds (default: 30)

 SAVE/RESTORE OPTIONS:
   --domain <name>            Domain name or UUID (required)
   --file <path>              Save/restore file path (required)

 LIST OPTIONS:
   --list-all                 List all VMs (default)
   --list-running             List running VMs
   --list-paused              List paused VMs
   --list-stopped             List stopped VMs
   --columns <cols>           Comma-separated column list

 AUTOSTART OPTIONS:
   --domain <name>            Domain name or UUID (required)
   --enable                   Enable autostart
   --disable                  Disable autostart

 DEFINE/UNDEFINE OPTIONS:
   --xml <file>               XML definition file (for define)
   --domain <name>            Domain name or UUID (required for undefine)
   --remove-storage           Remove storage on undefine
   --nvram <path>             NVRAM file to remove on undefine

 GENERAL OPTIONS:
   --connect <uri>            Libvirt URI (default: qemu:///system)
   --dry-run                  Show what would be done without executing
   -h, --help                 Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments / misuse
   3   Partial failure

EXAMPLES:
   $(basename "$0") create --name web01 --ram 2048 --vcpus 2 --disk /var/lib/libvirt/images/web01.qcow2 --disk-size 20G --os-variant linux2022 --network nat --graphics vnc --cpu host-passthrough --machine q35
   $(basename "$0") start --domain web01
   $(basename "$0") stop --domain web01 --graceful 60
   $(basename "$0") list --list-running --columns name,state,memory
   $(basename "$0") undefine --domain web01 --remove-storage
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
            create|start|stop|destroy|suspend|resume|save|restore|list|autostart|define|undefine)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --name)
                NAME="$2"
                shift 2
                ;;
            --ram)
                RAM="$2"
                shift 2
                ;;
            --vcpus)
                VCPUS="$2"
                shift 2
                ;;
            --disk)
                DISK_PATH="$2"
                shift 2
                ;;
            --disk-size)
                DISK_SIZE="$2"
                shift 2
                ;;
            --disk-format)
                DISK_FORMAT="$2"
                shift 2
                ;;
            --os-variant)
                OS_VARIANT="$2"
                shift 2
                ;;
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --graphics)
                GRAPHICS="$2"
                shift 2
                ;;
            --cdrom)
                CDROM="$2"
                shift 2
                ;;
            --import-disk)
                IMPORTDisk="$2"
                shift 2
                ;;
            --cpu)
                CPU="$2"
                shift 2
                ;;
            --machine)
                MACHINE="$2"
                shift 2
                ;;
            --tpm)
                TPM="$2"
                shift 2
                ;;
            --uefi)
                UEFI="yes"
                shift
                ;;
            --cloud-init)
                CLOUD_INIT="yes"
                shift
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --graceful)
                GRACEFUL_TIMEOUT="$2"
                shift 2
                ;;
            --file)
                SNAPSHOT_FILE="$2"
                shift 2
                ;;
            --list-all)
                LIST_FILTER="--all"
                shift
                ;;
            --list-running)
                LIST_FILTER="--state-running"
                shift
                ;;
            --list-paused)
                LIST_FILTER="--state-paused"
                shift
                ;;
            --list-stopped)
                LIST_FILTER="--state-shut off"
                shift
                ;;
            --columns)
                LIST_COLUMNS="$2"
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
            --xml)
                XML_FILE="$2"
                shift 2
                ;;
            --remove-storage)
                REMOVE_STORAGE="--storage"
                shift
                ;;
            --nvram)
                NVRAM="$2"
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
        create)
            if [[ -z "${NAME}" || -z "${RAM}" || -z "${VCPUS}" ]]; then
                log_error "create requires --name, --ram, --vcpus"
                exit 2
            fi
            ;;
        start|stop|destroy|suspend|resume|autostart|undefine|verify)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "${ACTION} requires --domain"
                exit 2
            fi
            ;;
        save|restore)
            if [[ -z "${DOMAIN}" || -z "${SNAPSHOT_FILE}" ]]; then
                log_error "${ACTION} requires --domain and --file"
                exit 2
            fi
            ;;
        define)
            if [[ -z "${XML_FILE}" ]]; then
                log_error "define requires --xml"
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
# action_create
# ---------------------------------------------------------------------------
action_create() {
    log_info "Creating VM '${NAME}'..."

    local -a cmd=(virt-install)
    cmd+=(--name "${NAME}")
    cmd+=(--memory "${RAM}")
    cmd+=(--vcpus "${VCPUS}")

    if [[ -n "${DISK_PATH}" ]]; then
        local disk_opt="path=${DISK_PATH},format=${DISK_FORMAT}"
        if [[ -n "${DISK_SIZE}" ]]; then
            disk_opt+=",size=${DISK_SIZE}"
        fi
        cmd+=(--disk "${disk_opt}")
    elif [[ -n "${DISK_SIZE}" ]]; then
        cmd+=(--disk "size=${DISK_SIZE},format=${DISK_FORMAT}")
    fi

    if [[ -n "${OS_VARIANT}" ]]; then
        cmd+=(--os-variant "${OS_VARIANT}")
    fi

    if [[ -n "${NETWORK}" ]]; then
        cmd+=(--network "${NETWORK}")
    else
        cmd+=(--network "network=default")
    fi

    if [[ -n "${GRAPHICS}" ]]; then
        cmd+=(--graphics "${GRAPHICS}")
    else
        cmd+=(--graphics "vnc,listen=0.0.0.0")
    fi

    if [[ -n "${CDROM}" ]]; then
        cmd+=(--cdrom "${CDROM}")
    fi

    if [[ -n "${IMPORTDisk}" ]]; then
        cmd+=(--import)
        cmd+=(--disk "path=${IMPORTDisk}")
        cmd+=(--noautoconsole)
    fi

    if [[ -n "${CPU}" ]]; then
        cmd+=(--cpu "${CPU}")
    fi

    if [[ -n "${MACHINE}" ]]; then
        cmd+=(--machine "${MACHINE}")
    fi

    if [[ -n "${TPM}" ]]; then
        cmd+=(--tpm "${TPM}")
    fi

    if [[ "${UEFI:-}" == "yes" ]]; then
        cmd+=(--boot "uefi")
    fi

    if [[ "${CLOUD_INIT:-}" == "yes" ]]; then
        cmd+=(--cloud-init "network-config=none")
    fi

    cmd+=(--noautoconsole)
    cmd+=(--autostart)

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"
    log_info "VM '${NAME}' created successfully."
}

# ---------------------------------------------------------------------------
# action_start
# ---------------------------------------------------------------------------
action_start() {
    log_info "Starting domain '${DOMAIN}'..."
    dry_run virsh_cmd start "${DOMAIN}"
    log_info "Domain '${DOMAIN}' started."
}

# ---------------------------------------------------------------------------
# action_stop
# ---------------------------------------------------------------------------
action_stop() {
    log_info "Stopping domain '${DOMAIN}' (timeout: ${GRACEFUL_TIMEOUT}s)..."

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] virsh -c ${CONNECT_URI} shutdown ${DOMAIN} --mode acpi --timeout ${GRACEFUL_TIMEOUT}"
        return 0
    fi

    virsh_cmd shutdown "${DOMAIN}" --mode acpi || {
        log_warn "ACPI shutdown failed; attempting forced destroy."
        virsh_cmd destroy "${DOMAIN}"
        return 0
    }

    local elapsed=0
    while (( elapsed < GRACEFUL_TIMEOUT )); do
        local state
        state=$(virsh_cmd domstate "${DOMAIN}" 2>/dev/null || echo "unknown")
        if [[ "${state}" == "shut off" || "${state}" == "shut down" ]]; then
            log_info "Domain '${DOMAIN}' stopped gracefully."
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_warn "Graceful shutdown timed out; force destroying domain '${DOMAIN}'."
    virsh_cmd destroy "${DOMAIN}"
    log_info "Domain '${DOMAIN}' destroyed."
}

# ---------------------------------------------------------------------------
# action_destroy
# ---------------------------------------------------------------------------
action_destroy() {
    log_info "Force destroying domain '${DOMAIN}'..."
    dry_run virsh_cmd destroy "${DOMAIN}"
    log_info "Domain '${DOMAIN}' destroyed."
}

# ---------------------------------------------------------------------------
# action_suspend
# ---------------------------------------------------------------------------
action_suspend() {
    log_info "Suspending domain '${DOMAIN}'..."
    dry_run virsh_cmd suspend "${DOMAIN}"
    log_info "Domain '${DOMAIN}' suspended."
}

# ---------------------------------------------------------------------------
# action_resume
# ---------------------------------------------------------------------------
action_resume() {
    log_info "Resuming domain '${DOMAIN}'..."
    dry_run virsh_cmd resume "${DOMAIN}"
    log_info "Domain '${DOMAIN}' resumed."
}

# ---------------------------------------------------------------------------
# action_save
# ---------------------------------------------------------------------------
action_save() {
    log_info "Saving domain '${DOMAIN}' to ${SNAPSHOT_FILE}..."
    dry_run virsh_cmd save "${DOMAIN}" "${SNAPSHOT_FILE}"
    log_info "Domain '${DOMAIN}' saved."
}

# ---------------------------------------------------------------------------
# action_restore
# ---------------------------------------------------------------------------
action_restore() {
    log_info "Restoring domain from ${SNAPSHOT_FILE}..."
    dry_run virsh_cmd restore "${SNAPSHOT_FILE}"
    log_info "Domain restored."
}

# ---------------------------------------------------------------------------
# action_list
# ---------------------------------------------------------------------------
action_list() {
    log_info "Listing VMs..."
    local -a cmd=(virsh_cmd list ${LIST_FILTER})
    if [[ -n "${LIST_COLUMNS}" ]]; then
        cmd+=(--name)
    fi
    "${cmd[@]}"
}

# ---------------------------------------------------------------------------
# action_autostart
# ---------------------------------------------------------------------------
action_autostart() {
    if [[ -z "${ENABLE_AUTOSTART}" ]]; then
        log_error "autostart requires --enable or --disable"
        exit 2
    fi

    if [[ "${ENABLE_AUTOSTART}" == "yes" ]]; then
        log_info "Enabling autostart for domain '${DOMAIN}'..."
        dry_run virsh_cmd autostart "${DOMAIN}" --enable
        log_info "Autostart enabled."
    else
        log_info "Disabling autostart for domain '${DOMAIN}'..."
        dry_run virsh_cmd autostart "${DOMAIN}" --disable
        log_info "Autostart disabled."
    fi
}

# ---------------------------------------------------------------------------
# action_define
# ---------------------------------------------------------------------------
action_define() {
    if [[ ! -f "${XML_FILE}" ]]; then
        log_error "XML file not found: ${XML_FILE}"
        exit 1
    fi
    log_info "Defining VM from ${XML_FILE}..."
    dry_run virsh_cmd define "${XML_FILE}"
    log_info "VM defined from ${XML_FILE}."
}

# ---------------------------------------------------------------------------
# action_undefine
# ---------------------------------------------------------------------------
action_undefine() {
    log_info "Undefining domain '${DOMAIN}'..."
    local -a cmd=(virsh_cmd undefine "${DOMAIN}")

    if [[ -n "${REMOVE_STORAGE}" ]]; then
        cmd+=("${REMOVE_STORAGE}")
    fi

    if [[ -n "${NVRAM}" ]]; then
        cmd+=(--nvram "${NVRAM}")
    fi

    dry_run "${cmd[@]}"
    log_info "Domain '${DOMAIN}' undefined."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs virsh qemu-img virt-install
    require_libvirt "${CONNECT_URI}"

    case "${ACTION}" in
        create)     action_create ;;
        start)      action_start ;;
        stop)       action_stop ;;
        destroy)    action_destroy ;;
        suspend)    action_suspend ;;
        resume)     action_resume ;;
        save)       action_save ;;
        restore)    action_restore ;;
        list)       action_list ;;
        autostart)  action_autostart ;;
        define)     action_define ;;
        undefine)   action_undefine ;;
    esac
}

main "$@"
