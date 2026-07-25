#!/usr/bin/env bash
# =============================================================================
# pmx-cloudinit.sh — Cloud-Init management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create, configure, regenerate, dump, download-image
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Cloud-Init management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  create            --vmid=ID [--template-vmid=ID] [--node=NODE]
  configure         --vmid=ID [OPTIONS] [--node=NODE]
  regenerate        --vmid=ID [--node=NODE]
  dump              --vmid=ID [--node=NODE]
  download-image    --os=OS [--version=VER] [--storage=S]

CREATE OPTIONS:
  --vmid=ID               Target VM ID (required)
  --template-vmid=ID      Source template VMID
  --node=NODE             Target node

CONFIGURE OPTIONS:
  --vmid=ID               Target VM ID (required)
  --user=USERNAME         Cloud-init user
  --password=PASS         User password
  --ssh-keys=KEYS         SSH public keys (comma-separated or file path)
  --ip=IP                 Static IP (CIDR) or "dhcp"
  --gateway=IP            Default gateway
  --dns=IP                DNS server(s) (comma-separated)
  --nameserver=IP         Nameserver
  --searchdomain=DOMAIN   Search domain
  --ciuser=USERNAME       ciuser override
  --cipassword=PASS       cipassword override
  --node=NODE             Target node

DOWNLOAD-IMAGE OPTIONS:
  --os=OS                 OS: ubuntu, debian, rocky, almalinux, fedora (required)
  --version=VER           Version (e.g. 22.04, 12, 9)
  --storage=S             Target storage (default: local)

OPTIONS:
  --dry-run               Show what would be done
  --help, -h              Show this help

EXAMPLES:
  $(basename "$0") create --vmid=200 --template-vmid=9000
  $(basename "$0") configure --vmid=200 --user=admin --ip=dhcp --ssh-keys=/root/.ssh/id_rsa.pub
  $(basename "$0") configure --vmid=200 --user=admin --ip=10.0.0.100/24 --gateway=10.0.0.1
  $(basename "$0") regenerate --vmid=200
  $(basename "$0") dump --vmid=200
  $(basename "$0") download-image --os=ubuntu --version=22.04 --storage=local
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
TEMPLATE_VMID=""
NODE="${PMX_NODE:-}"
CIUSER=""
CIPASSWORD=""
USER=""
PASSWORD=""
SSH_KEYS=""
IP_CONFIG=""
GATEWAY=""
DNS=""
NAMESERVER=""
SEARCHDOMAIN=""
OS_NAME=""
VERSION=""
STORAGE="local"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)           VMID="${1#*=}" ;;
            --template-vmid=*)  TEMPLATE_VMID="${1#*=}" ;;
            --node=*)           NODE="${1#*=}" ;;
            --user=*)           USER="${1#*=}" ;;
            --password=*)       PASSWORD="${1#*=}" ;;
            --ssh-keys=*)       SSH_KEYS="${1#*=}" ;;
            --ip=*)             IP_CONFIG="${1#*=}" ;;
            --gateway=*)        GATEWAY="${1#*=}" ;;
            --dns=*)            DNS="${1#*=}" ;;
            --nameserver=*)     NAMESERVER="${1#*=}" ;;
            --searchdomain=*)   SEARCHDOMAIN="${1#*=}" ;;
            --ciuser=*)         CIUSER="${1#*=}" ;;
            --cipassword=*)     CIPASSWORD="${1#*=}" ;;
            --os=*)             OS_NAME="${1#*=}" ;;
            --version=*)        VERSION="${1#*=}" ;;
            --storage=*)        STORAGE="${1#*=}" ;;
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
do_create() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    if [[ -n "${TEMPLATE_VMID}" ]]; then
        log_info "Creating VM ${VMID} from template ${TEMPLATE_VMID} with Cloud-Init..."

        # Clone template
        local clone_payload
        clone_payload=$(jq -n --argjson id "${VMID}" --argjson full 1 '{"newid": $id, "full": $full}')
        dry_run api_call POST "/nodes/${NODE}/qemu/${TEMPLATE_VMID}/clone" -d "${clone_payload}"

        # Enable cloud-init on the new VM
        log_info "Enabling Cloud-Init on VM ${VMID}..."
        local ci_payload
        ci_payload=$(jq -n --arg storage "${STORAGE}" '{"ide2": ($storage + ":cloudinit")}')
        dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${ci_payload}"

        echo -e "${GREEN}VM ${VMID} created from template with Cloud-Init.${NC}"
    else
        log_info "Enabling Cloud-Init on existing VM ${VMID}..."
        local ci_payload
        ci_payload=$(jq -n --arg storage "${STORAGE}" '{"ide2": ($storage + ":cloudinit")}')
        dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${ci_payload}"
        echo -e "${GREEN}Cloud-Init enabled on VM ${VMID}.${NC}"
    fi
}

do_configure() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    local payload="{}"

    # Process SSH keys
    local ssh_keys_json="[]"
    if [[ -n "${SSH_KEYS}" ]]; then
        if [[ -f "${SSH_KEYS}" ]]; then
            # Read from file
            ssh_keys_json=$(jq -Rsc 'split("\n") | map(select(length > 0))' "${SSH_KEYS}")
        else
            # Comma-separated keys
            ssh_keys_json=$(echo "${SSH_KEYS}" | jq -Rsc 'split(",")')
        fi
    fi

    [[ -n "${USER}" ]] && payload=$(echo "${payload}" | jq -c --arg u "${USER}" '. + {"ciuser": $u}')
    [[ -n "${CIUSER}" ]] && payload=$(echo "${payload}" | jq -c --arg u "${CIUSER}" '. + {"ciuser": $u}')
    [[ -n "${PASSWORD}" ]] && payload=$(echo "${payload}" | jq -c --arg p "${PASSWORD}" '. + {"cipassword": $p}')
    [[ -n "${CIPASSWORD}" ]] && payload=$(echo "${payload}" | jq -c --arg p "${CIPASSWORD}" '. + {"cipassword": $p}')

    if [[ -n "${SSH_KEYS}" ]]; then
        payload=$(echo "${payload}" | jq -c --argjson keys "${ssh_keys_json}" '. + {"sshkeys": ($keys | join("\n"))}')
    fi

    # Network configuration
    if [[ -n "${IP_CONFIG}" ]]; then
        if [[ "${IP_CONFIG}" == "dhcp" ]]; then
            payload=$(echo "${payload}" | jq -c '. + {"ipconfig0": "ip=dhcp"}')
        else
            local ipconfig="ip=${IP_CONFIG}"
            [[ -n "${GATEWAY}" ]] && ipconfig+=",gw=${GATEWAY}"
            payload=$(echo "${payload}" | jq -c --arg ip "${ipconfig}" '. + {"ipconfig0": $ip}')
        fi
    fi

    [[ -n "${NAMESERVER}" ]] && payload=$(echo "${payload}" | jq -c --arg ns "${NAMESERVER}" '. + {"nameserver": $ns}')
    [[ -n "${DNS}" ]] && payload=$(echo "${payload}" | jq -c --arg ns "${DNS}" '. + {"nameserver": $ns}')
    [[ -n "${SEARCHDOMAIN}" ]] && payload=$(echo "${payload}" | jq -c --arg sd "${SEARCHDOMAIN}" '. + {"searchdomain": $sd}')

    if [[ "${payload}" == "{}" ]]; then
        log_error "Specify at least one Cloud-Init parameter."
        exit 1
    fi

    log_info "Configuring Cloud-Init for VM ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"

    # Regenerate cloud-init drive
    log_info "Regenerating Cloud-Init drive..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/cloudinit"

    echo -e "${GREEN}Cloud-Init configured for VM ${VMID}.${NC}"
}

do_regenerate() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    log_info "Regenerating Cloud-Init drive for VM ${VMID}..."
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/cloudinit"
    echo -e "${GREEN}Cloud-Init drive regenerated.${NC}"
}

do_dump() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    log_info "Dumping Cloud-Init config for VM ${VMID}..."
    echo ""

    local resp
    resp=$(api_call GET "/nodes/${NODE}/qemu/${VMID}/config" 2>/dev/null) || {
        log_error "Could not fetch VM config."; return 1
    }

    printf "${BOLD}%-20s %-50s${NC}\n" "PROPERTY" "VALUE"
    printf "%-20s %-50s\n" "--------" "-----"

    local ciuser cipassword ipconfig sshkeys nameserver searchdomain ide2
    ciuser=$(parse_json "${resp}" ".data.ciuser // \"\"")
    cipassword=$(parse_json "${resp}" ".data.cipassword // \"\"")
    ipconfig=$(parse_json "${resp}" ".data.ipconfig0 // \"\"")
    sshkeys=$(parse_json "${resp}" ".data.sshkeys // \"\"")
    nameserver=$(parse_json "${resp}" ".data.nameserver // \"\"")
    searchdomain=$(parse_json "${resp}" ".data.searchdomain // \"\"")
    ide2=$(parse_json "${resp}" ".data.ide2 // \"\"")

    printf "%-20s %-50s\n" "Cloud-Init Device" "${ide2}"
    printf "%-20s %-50s\n" "User" "${ciuser}"
    [[ -n "${cipassword}" ]] && printf "%-20s %-50s\n" "Password" "(set)"
    printf "%-20s %-50s\n" "IP Config" "${ipconfig}"
    printf "%-20s %-50s\n" "Nameserver" "${nameserver}"
    printf "%-20s %-50s\n" "Search Domain" "${searchdomain}"
    if [[ -n "${sshkeys}" ]]; then
        printf "%-20s %-50s\n" "SSH Keys" "(set, $(echo "${sshkeys}" | wc -l) key(s))"
    fi
}

do_download_image() {
    [[ -z "${OS_NAME}" ]] && { log_error "--os is required."; exit 1; }

    local os_lower="${OS_NAME,,}"

    # Determine URL and filename based on OS
    local url="" filename=""
    case "${os_lower}" in
        ubuntu)
            VERSION="${VERSION:-22.04}"
            filename="ubuntu-${VERSION}-server-cloudimg-amd64.img"
            url="https://cloud-images.ubuntu.com/${VERSION}/current/${filename}"
            ;;
        debian)
            VERSION="${VERSION:-12}"
            filename="debian-${VERSION}-generic-amd64.img"
            url="https://cloud.debian.org/cloud/${VERSION}/latest/debian-${VERSION}-generic-amd64.img"
            ;;
        rocky)
            VERSION="${VERSION:-9}"
            filename="Rocky-${VERSION}-GenericCloud-Base.latest.x86_64.qcow2"
            url="https://dl.rockylinux.org/rocky/${VERSION}/images/x86_64/Rocky-9-latest.x86_64.qcow2"
            ;;
        almalinux)
            VERSION="${VERSION:-9}"
            filename="AlmaLinux-${VERSION}-GenericCloud-latest.x86_64.qcow2"
            url="https://repo.almalinux.org/almalinux/${VERSION}/cloud/x86_64/images/${filename}"
            ;;
        fedora)
            VERSION="${VERSION:-40}"
            filename="Fedora-Cloud-Base-Generic.${VERSION}.x86_64.qcow2"
            url="https://download.fedoraproject.org/pub/fedora/linux/releases/${VERSION}/Cloud/x86_64/images/${filename}"
            ;;
        *)
            log_error "Unsupported OS: ${OS_NAME}. Supported: ubuntu, debian, rocky, almalinux, fedora"
            exit 1
            ;;
    esac

    log_info "Downloading ${OS_NAME} ${VERSION} cloud image..."

    local dest="/var/lib/vz/template/cache/${filename}"

    if [[ "${DRY_RUN,,}" != "true" && "${DRY_RUN}" != "1" ]]; then
        if [[ -f "${dest}" ]]; then
            log_info "Image already exists at ${dest}"
        else
            curl -L -o "${dest}" "${url}" || {
                log_error "Download failed."
                exit 1
            }
            log_info "Downloaded to ${dest}"
        fi
    else
        log_info "[DRY RUN] Would download: ${url}"
        log_info "[DRY RUN] Destination: ${dest}"
    fi

    echo -e "${GREEN}Cloud image downloaded: ${filename}${NC}"
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
        create)         do_create ;;
        configure)      do_configure ;;
        regenerate)     do_regenerate ;;
        dump)           do_dump ;;
        download-image) do_download_image ;;
        *)              log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
