#!/usr/bin/env bash
# =============================================================================
# kvm-nested-virt.sh - Nested virtualization management for KVM
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: enable, disable, status, test
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
VENDOR=""
TEST_DOMAIN="nested-test-$$"
TEST_RAM="512"
TEST_VCPUS="1"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-nested-virt.sh" "Nested virtualization management"
    cat <<'HEADER'
Usage: kvm-nested-virt.sh [OPTIONS] <ACTION>

 ACTIONS:
   enable      Enable nested virtualization
   disable     Disable nested virtualization
   status      Check nested virtualization status
   test        Create a small nested VM and verify it works
HEADER
    cat <<EOF

 ENABLE / DISABLE:
   --vendor <intel|amd>         CPU vendor (required)

 STATUS:
   No additional flags required.

 TEST:
   --connect <uri>              Libvirt URI (default: qemu:///system)

 GENERAL:
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-nested-virt.sh enable --vendor intel
   kvm-nested-virt.sh enable --vendor amd
   kvm-nested-virt.sh disable --vendor intel
   kvm-nested-virt.sh status
   kvm-nested-virt.sh test
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
            enable|disable|status|test)
                ACTION="$1"
                shift
                ;;
            --connect)
                CONNECT_URI="$2"
                shift 2
                ;;
            --vendor)
                VENDOR="$2"
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
        enable|disable)
            if [[ -z "${VENDOR}" ]]; then
                log_error "${ACTION} requires --vendor (intel or amd)"
                exit 2
            fi
            local v="${VENDOR,,}"
            if [[ "${v}" != "intel" && "${v}" != "amd" ]]; then
                log_error "Invalid vendor: ${VENDOR}. Must be 'intel' or 'amd'."
                exit 2
            fi
            ;;
        status|test)
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# detect_vendor
# ---------------------------------------------------------------------------
detect_vendor() {
    if [[ -n "${VENDOR}" ]]; then
        echo "${VENDOR,,}"
        return
    fi

    if grep -qi "intel" /proc/cpuinfo 2>/dev/null; then
        echo "intel"
    elif grep -qi "amd" /proc/cpuinfo 2>/dev/null; then
        echo "amd"
    else
        log_error "Cannot detect CPU vendor."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# action_enable
# ---------------------------------------------------------------------------
action_enable() {
    local vendor
    vendor=$(detect_vendor)

    log_info "Enabling nested virtualization for ${vendor} CPU..."

    check_root

    local module="kvm-${vendor}"
    local param_path="/sys/module/${module}/parameters/nested"

    if [[ ! -d "/sys/module/${module}" ]]; then
        log_info "  Loading ${module} module..."
        dry_run modprobe "${module}"
    fi

    if [[ -f "${param_path}" ]]; then
        local current
        current=$(cat "${param_path}")
        if [[ "${current}" == "Y" || "${current}" == "1" ]]; then
            log_info "  Nested virtualization is already enabled (value: ${current})."
        else
            log_info "  Current value: ${current}. Enabling..."
            if [[ -w "${param_path}" ]]; then
                dry_run bash -c "echo 1 > ${param_path}"
            fi
        fi
    else
        log_warn "  Parameter path not found: ${param_path}"
        log_info "  Trying modprobe options..."
    fi

    # Make persistent via modprobe.d
    local conf_file="/etc/modprobe.d/kvm-nested.conf"
    log_info "  Making persistent via ${conf_file}..."

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        mkdir -p /etc/modprobe.d
        echo "options ${module} nested=1" > "${conf_file}"
        log_info "  Wrote ${conf_file}"
    else
        log_info "[DRY RUN] Would write: options ${module} nested=1 > ${conf_file}"
    fi

    # Unload and reload module to apply
    log_info "  Reloading ${module} module..."
    dry_run modprobe -r "${module}" 2>/dev/null || {
        log_warn "  Cannot unload ${module} (VMs may be running). Setting takes effect on next reboot."
    }
    dry_run modprobe "${module}"

    log_info "Nested virtualization enabled for ${vendor}."
}

# ---------------------------------------------------------------------------
# action_disable
# ---------------------------------------------------------------------------
action_disable() {
    local vendor
    vendor=$(detect_vendor)

    log_info "Disabling nested virtualization for ${vendor} CPU..."
    check_root

    local module="kvm-${vendor}"
    local conf_file="/etc/modprobe.d/kvm-nested.conf"

    if [[ -f "${conf_file}" ]]; then
        if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
            echo "options ${module} nested=0" > "${conf_file}"
        fi
        log_info "  Updated ${conf_file}"
    fi

    local param_path="/sys/module/${module}/parameters/nested"
    if [[ -f "${param_path}" && -w "${param_path}" ]]; then
        dry_run bash -c "echo 0 > ${param_path}"
    fi

    log_info "Nested virtualization disabled for ${vendor}."
    log_info "Reload module or reboot for full effect."
}

# ---------------------------------------------------------------------------
# action_status
# ---------------------------------------------------------------------------
action_status() {
    log_info "Nested virtualization status:"
    echo ""

    for mod in kvm-intel kvm-amd; do
        local param_path="/sys/module/${mod}/parameters/nested"
        if [[ -f "${param_path}" ]]; then
            local val
            val=$(cat "${param_path}")
            local label="disabled"
            if [[ "${val}" == "Y" || "${val}" == "1" ]]; then
                label="enabled"
            fi
            echo "  ${mod}: nested=${val} (${label})"
        else
            echo "  ${mod}: module not loaded"
        fi
    done

    echo ""

    if [[ -d /sys/module/kvm ]]; then
        echo "  KVM module: loaded"
    else
        echo "  KVM module: NOT loaded"
    fi

    echo ""

    log_info "CPU flags check:"
    if grep -q "vmx" /proc/cpuinfo 2>/dev/null; then
        echo "  Intel VMX: present"
    elif grep -q "svm" /proc/cpuinfo 2>/dev/null; then
        echo "  AMD SVM: present"
    else
        echo "  No virtualization extensions found!"
    fi

    echo ""

    log_info "Modprobe config:"
    local conf_file="/etc/modprobe.d/kvm-nested.conf"
    if [[ -f "${conf_file}" ]]; then
        cat "${conf_file}"
    else
        echo "  ${conf_file}: not found (using defaults)"
    fi
}

# ---------------------------------------------------------------------------
# action_test
# ---------------------------------------------------------------------------
action_test() {
    log_info "Testing nested virtualization..."

    check_prereqs virsh qemu-img virt-install

    local vendor
    vendor=$(detect_vendor)

    local param_path="/sys/module/kvm-${vendor}/parameters/nested"
    if [[ -f "${param_path}" ]]; then
        local val
        val=$(cat "${param_path}")
        if [[ "${val}" != "Y" && "${val}" != "1" ]]; then
            log_warn "Nested virtualization is not enabled. Test may fail."
        fi
    fi

    log_info "  Creating small test VM..."

    local test_img
    test_img=$(create_temp_file)

    qemu-img create -f qcow2 "${test_img}" 1G 2>/dev/null || {
        log_error "Failed to create test disk."
        return 1
    }

    local -a cmd=(virt-install
        --name "${TEST_DOMAIN}"
        --memory "${TEST_RAM}"
        --vcpus "${TEST_VCPUS}"
        --disk "path=${test_img},format=qcow2"
        --import
        --noautoconsole
        --connect "${CONNECT_URI}"
    )

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would create test VM: ${cmd[*]}"
        return 0
    fi

    if ! "${cmd[@]}" 2>/dev/null; then
        log_error "Failed to create test VM."
        return 1
    fi

    sleep 5

    local state
    state=$(virsh -c "${CONNECT_URI}" domstate "${TEST_DOMAIN}" 2>/dev/null || echo "unknown")

    if [[ "${state}" == "running" ]]; then
        log_info "  Test VM is running. Nested virtualization is functional."
        virsh -c "${CONNECT_URI}" destroy "${TEST_DOMAIN}" 2>/dev/null || true
    else
        log_error "  Test VM is not running (state: ${state}). Nested virtualization may not be working."
        virsh -c "${CONNECT_URI}" undefine "${TEST_DOMAIN}" 2>/dev/null || true
    fi

    rm -f "${test_img}"
    log_info "Test complete."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_args
    setup_logging
    check_prereqs modprobe

    case "${ACTION}" in
        enable)   action_enable ;;
        disable)  action_disable ;;
        status)   action_status ;;
        test)     action_test ;;
    esac
}

main "$@"
