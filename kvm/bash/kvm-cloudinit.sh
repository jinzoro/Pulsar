#!/usr/bin/env bash
# =============================================================================
# kvm-cloudinit.sh - Cloud-Init management for KVM VMs
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create-iso, attach, configure, dump
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
CI_USER=""
CI_PASSWORD=""
SSH_KEYS_FILE=""
CI_HOSTNAME=""
CI_IP=""
CI_GATEWAY=""
CI_DNS=""
CI_NAMESERVER=""
OUTPUT_PATH=""
ISO_PATH=""
USER_DATA_FILE=""
META_DATA_FILE=""
NETWORK_CONFIG_FILE=""

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "kvm-cloudinit.sh" "Cloud-Init management for KVM VMs"
    cat <<'HEADER'
Usage: kvm-cloudinit.sh [OPTIONS] <ACTION>

 ACTIONS:
   create-iso     Create a Cloud-Init ISO (NoCloud datasource)
   attach         Attach a Cloud-Init ISO to a domain
   configure      Attach custom cloud-init config files to a domain
   dump           Show current cloud-init config from a domain
HEADER
    cat <<EOF

 CREATE-ISO:
   --domain <name>              Domain name (required)
   --user <name>                Default username (default: root)
   --password <pass>            Default user password
   --ssh-keys-file <path>       SSH authorized_keys file
   --hostname <name>            VM hostname
   --ip <addr>                  Static IP (CIDR) or "dhcp"
   --gateway <addr>             Default gateway (required for static IP)
   --dns <addr>                 DNS server
   --nameserver <addr>          Additional nameserver
   --output-path <path>         Output ISO path (default: auto-generated)

 ATTACH:
   --domain <name>              Domain name (required)
   --iso-path <path>            Path to cloud-init ISO (required)

 CONFIGURE:
   --domain <name>              Domain name (required)
   --user-data-file <path>      Custom user-data file
   --meta-data-file <path>      Custom meta-data file
   --network-config-file <path> Custom network-config file

 DUMP:
   --domain <name>              Domain name (required)

 GENERAL:
   --connect <uri>              Libvirt URI (default: qemu:///system)
   --dry-run                    Show what would be done without executing
   -h, --help                   Show this help message

 EXIT CODES:
   0   Success
   1   Error
   2   Invalid arguments

EXAMPLES:
   kvm-cloudinit.sh create-iso --domain web01 --hostname web01.local --user deploy --ssh-keys-file ~/.ssh/id_rsa.pub --ip dhcp
   kvm-cloudinit.sh create-iso --domain db01 --hostname db01.local --ip 192.168.1.100/24 --gateway 192.168.1.1 --dns 8.8.8.8
   kvm-cloudinit.sh attach --domain web01 --iso-path /var/lib/libvirt/images/web01-cloudinit.iso
   kvm-cloudinit.sh configure --domain web01 --user-data-file ./user-data --meta-data-file ./meta-data
   kvm-cloudinit.sh dump --domain web01
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
            create-iso|attach|configure|dump)
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
            --user)
                CI_USER="$2"
                shift 2
                ;;
            --password)
                CI_PASSWORD="$2"
                shift 2
                ;;
            --ssh-keys-file)
                SSH_KEYS_FILE="$2"
                shift 2
                ;;
            --hostname)
                CI_HOSTNAME="$2"
                shift 2
                ;;
            --ip)
                CI_IP="$2"
                shift 2
                ;;
            --gateway)
                CI_GATEWAY="$2"
                shift 2
                ;;
            --dns)
                CI_DNS="$2"
                shift 2
                ;;
            --nameserver)
                CI_NAMESERVER="$2"
                shift 2
                ;;
            --output-path)
                OUTPUT_PATH="$2"
                shift 2
                ;;
            --iso-path)
                ISO_PATH="$2"
                shift 2
                ;;
            --user-data-file)
                USER_DATA_FILE="$2"
                shift 2
                ;;
            --meta-data-file)
                META_DATA_FILE="$2"
                shift 2
                ;;
            --network-config-file)
                NETWORK_CONFIG_FILE="$2"
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
        create-iso)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "create-iso requires --domain"
                exit 2
            fi
            ;;
        attach)
            if [[ -z "${DOMAIN}" || -z "${ISO_PATH}" ]]; then
                log_error "attach requires --domain and --iso-path"
                exit 2
            fi
            ;;
        configure)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "configure requires --domain"
                exit 2
            fi
            ;;
        dump)
            if [[ -z "${DOMAIN}" ]]; then
                log_error "dump requires --domain"
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
# generate_meta_data
# ---------------------------------------------------------------------------
generate_meta_data() {
    local hostname="${1:-}"
    local output="${2:-}"

    cat > "${output}" <<EOF
#cloud-config
EOF

    if [[ -n "${hostname}" ]]; then
        cat >> "${output}" <<EOF
hostname: ${hostname}
fqdn: ${hostname}
EOF
    fi
}

# ---------------------------------------------------------------------------
# generate_network_config
# ---------------------------------------------------------------------------
generate_network_config() {
    local ip_val="${1:-dhcp}"
    local gateway="${2:-}"
    local dns_val="${3:-}"
    local output="${4:-}"

    if [[ "${ip_val}" == "dhcp" || -z "${ip_val}" ]]; then
        cat > "${output}" <<'NETEOF'
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp6: false
NETEOF
    else
        cat > "${output}" <<NETEOF
version: 2
ethernets:
  eth0:
    dhcp4: false
    dhcp6: false
    addresses:
      - ${ip_val}
NETEOF
        if [[ -n "${gateway}" ]]; then
            cat >> "${output}" <<NETEOF
    routes:
      - to: default
        via: ${gateway}
NETEOF
        fi
        if [[ -n "${dns_val}" ]]; then
            cat >> "${output}" <<NETEOF
    nameservers:
      addresses:
        - ${dns_val}
NETEOF
        fi
    fi
}

# ---------------------------------------------------------------------------
# generate_user_data
# ---------------------------------------------------------------------------
generate_user_data() {
    local user="${1:-root}"
    local password="${2:-}"
    local ssh_keys="${3:-}"
    local output="${4:-}"

    cat > "${output}" <<'UDEOF'
#cloud-config
# Users configuration
users:
UDEOF

    cat >> "${output}" <<UDEOF
  - name: ${user}
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, docker, libvirt
UDEOF

    if [[ -n "${password}" ]]; then
        cat >> "${output}" <<UDEOF
    passwd: $(openssl passwd -6 "${password}" 2>/dev/null || echo "CHANGEME")
UDEOF
    fi

    if [[ -n "${ssh_keys}" && -f "${ssh_keys}" ]]; then
        echo "    ssh_authorized_keys:" >> "${output}"
        while IFS= read -r key; do
            key="$(echo "${key}" | xargs)"
            [[ -z "${key}" || "${key}" == \#* ]] && continue
            echo "      - ${key}" >> "${output}"
        done < "${ssh_keys}"
    fi

    cat >> "${output}" <<'UDEOF'

# Package updates
package_update: true
package_upgrade: false

# Packages to install
# packages:
#   - curl
#   - wget

# Run commands
# runcmd:
#   - echo "Cloud-init complete!" > /root/cloud-init.done

# Disable root login via SSH
ssh_pwauth: false
UDEOF
}

# ---------------------------------------------------------------------------
# action_create_iso
# ---------------------------------------------------------------------------
action_create_iso() {
    log_info "Creating Cloud-Init ISO for domain '${DOMAIN}'..."

    local user="${CI_USER:-root}"
    local iso_path="${OUTPUT_PATH:-}"

    if [[ -z "${iso_path}" ]]; then
        iso_path="/var/lib/libvirt/images/${DOMAIN}-cloudinit.iso"
    fi

    local ci_dir
    ci_dir=$(create_temp_file)
    mkdir -p "${ci_dir}"

    # Generate meta-data
    local meta_file="${ci_dir}/meta-data"
    generate_meta_data "${CI_HOSTNAME}" "${meta_file}"
    log_info "  Generated meta-data"

    # Generate user-data
    local user_file="${ci_dir}/user-data"
    generate_user_data "${user}" "${CI_PASSWORD}" "${SSH_KEYS_FILE}" "${user_file}"
    log_info "  Generated user-data"

    # Generate network-config
    local net_file="${ci_dir}/network-config"
    generate_network_config "${CI_IP}" "${CI_GATEWAY}" "${CI_DNS}" "${net_file}"
    log_info "  Generated network-config"

    # Create ISO
    log_info "  Creating ISO: ${iso_path}"

    local -a cmd=()
    if command -v cloud-localds &>/dev/null; then
        cmd=(cloud-localds --version 1 --meta-data "${meta_file}" --user-data "${user_file}" --network-config "${net_file}" "${iso_path}")
    elif command -v genisoimage &>/dev/null; then
        cmd=(genisoimage -output "${iso_path}" -volid "cidata" -joliet -rock "${user_file}" "${meta_file}" "${net_file}")
    elif command -v mkisofs &>/dev/null; then
        cmd=(mkisofs -output "${iso_path}" -volid "cidata" -joliet -rock "${user_file}" "${meta_file}" "${net_file}")
    else
        log_error "No ISO creation tool found. Install cloud-utils, genisoimage, or mkisofs."
        return 1
    fi

    log_info "Command: ${cmd[*]}"
    dry_run "${cmd[@]}"

    log_info "Cloud-Init ISO created: ${iso_path}"
}

# ---------------------------------------------------------------------------
# action_attach
# ---------------------------------------------------------------------------
action_attach() {
    log_info "Attaching Cloud-Init ISO '${ISO_PATH}' to domain '${DOMAIN}'..."

    local tmpxml
    tmpxml=$(create_temp_file)

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would attach ${ISO_PATH} as cdrom to ${DOMAIN}"
        return 0
    fi

    virsh_cmd dumpxml "${DOMAIN}" > "${tmpxml}" 2>/dev/null || {
        log_error "Failed to dump domain XML."
        return 1
    }

    # Check if cloud-init device already exists
    if grep -q "cloudinit" "${tmpxml}"; then
        log_info "  Cloud-init device already exists; updating source..."
        sed -i "s|<source file='[^']*'/>|<source file='${ISO_PATH}'/>|" "${tmpxml}"
    else
        # Add cloud-init disk before </domain>
        sed -i "/<\/disk>/,/<\/devices>/{/<\/devices>/i\\
    <disk type='file' device='cdrom'>\\
      <driver name='qemu' type='raw'/>\\
      <source file='${ISO_PATH}'/>\\
      <target dev='sda' bus='sata'/>\\
      <readonly/>\\
    </disk>
}" "${tmpxml}"
    fi

    virsh_cmd define "${tmpxml}" || {
        log_error "Failed to define updated domain."
        return 1
    }

    log_info "Cloud-Init ISO attached to domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_configure
# ---------------------------------------------------------------------------
action_configure() {
    log_info "Configuring Cloud-Init for domain '${DOMAIN}'..."

    local tmpxml
    tmpxml=$(create_temp_file)
    virsh_cmd dumpxml "${DOMAIN}" > "${tmpxml}" 2>/dev/null || {
        log_error "Failed to dump domain XML."
        return 1
    }

    # Create the ISO from custom files
    local ci_dir
    ci_dir=$(create_temp_file)
    mkdir -p "${ci_dir}"

    if [[ -n "${USER_DATA_FILE}" ]]; then
        cp "${USER_DATA_FILE}" "${ci_dir}/user-data"
    else
        generate_user_data "root" "" "" "${ci_dir}/user-data"
    fi

    if [[ -n "${META_DATA_FILE}" ]]; then
        cp "${META_DATA_FILE}" "${ci_dir}/meta-data"
    else
        generate_meta_data "" "${ci_dir}/meta-data"
    fi

    if [[ -n "${NETWORK_CONFIG_FILE}" ]]; then
        cp "${NETWORK_CONFIG_FILE}" "${ci_dir}/network-config"
    else
        generate_network_config "dhcp" "" "" "${ci_dir}/network-config"
    fi

    local iso_path="/var/lib/libvirt/images/${DOMAIN}-cloudinit.iso"

    local -a cmd=()
    if command -v genisoimage &>/dev/null; then
        cmd=(genisoimage -output "${iso_path}" -volid "cidata" -joliet -rock \
            "${ci_dir}/user-data" "${ci_dir}/meta-data" "${ci_dir}/network-config")
    else
        log_error "genisoimage not found."
        return 1
    fi

    log_info "  Creating ISO: ${iso_path}"
    dry_run "${cmd[@]}"

    log_info "  Attaching to domain..."
    ISO_PATH="${iso_path}"
    action_attach

    log_info "Cloud-Init configured for domain '${DOMAIN}'."
}

# ---------------------------------------------------------------------------
# action_dump
# ---------------------------------------------------------------------------
action_dump() {
    log_info "Cloud-Init configuration for domain '${DOMAIN}':"
    echo ""

    echo "=== Domain XML (disk section) ==="
    virsh_cmd dumpxml "${DOMAIN}" 2>/dev/null | grep -A 10 "disk.*cdrom" || echo "  (no cdrom found)"
    echo ""

    # Try to extract and display cloud-init config
    local ci_iso=""
    ci_iso=$(virsh_cmd dumpxml "${DOMAIN}" 2>/dev/null | grep -oP "source file='[^']*cloudinit[^']*'" | head -1 | cut -d"'" -f2 || echo "")

    if [[ -n "${ci_iso}" && -f "${ci_iso}" ]]; then
        echo "=== Cloud-Init ISO: ${ci_iso} ==="
        echo ""

        local tmpdir
        tmpdir=$(create_temp_file)
        mkdir -p "${tmpdir}"

        if command -v 7z &>/dev/null; then
            7z x -o"${tmpdir}" "${ci_iso}" >/dev/null 2>&1 || true
        elif command -v isoinfo &>/dev/null; then
            isoinfo -i "${ci_iso}" -x /user-data > "${tmpdir}/user-data" 2>/dev/null || true
            isoinfo -i "${ci_iso}" -x /meta-data > "${tmpdir}/meta-data" 2>/dev/null || true
            isoinfo -i "${ci_iso}" -x /network-config > "${tmpdir}/network-config" 2>/dev/null || true
        else
            log_warn "No tool to extract ISO (install p7zip-full or genisoimage)."
            return 0
        fi

        if [[ -f "${tmpdir}/user-data" ]]; then
            echo "=== user-data ==="
            cat "${tmpdir}/user-data"
            echo ""
        fi

        if [[ -f "${tmpdir}/meta-data" ]]; then
            echo "=== meta-data ==="
            cat "${tmpdir}/meta-data"
            echo ""
        fi

        if [[ -f "${tmpdir}/network-config" ]]; then
            echo "=== network-config ==="
            cat "${tmpdir}/network-config"
            echo ""
        fi
    else
        log_warn "Cloud-Init ISO not found or not accessible."
    fi
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
        create-iso) action_create_iso ;;
        attach)     action_attach ;;
        configure)  action_configure ;;
        dump)       action_dump ;;
    esac
}

main "$@"
