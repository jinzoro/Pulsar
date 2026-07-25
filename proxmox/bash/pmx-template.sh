#!/usr/bin/env bash
# =============================================================================
# pmx-template.sh — Template management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Operations: create, list, clone-from-template, delete, update
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "Template management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  create              --vmid=ID [--node=NODE]
  list                [--node=NODE]
  clone-from-template --template-vmid=ID [OPTIONS]
  delete              --vmid=ID [--node=NODE]
  update              --vmid=ID [--description=TEXT] [--node=NODE]

CREATE OPTIONS:
  --vmid=ID           Existing VM to convert to template (required)
  --node=NODE         Target node

CLONE-FROM-TEMPLATE OPTIONS:
  --template-vmid=ID  Source template VMID (required)
  --new-vmid=ID       Target VMID for clone
  --name=NAME         New VM name
  --full              Full clone (default)
  --linked            Linked clone
  --target-node=NODE  Target node
  --target-storage=S  Target storage

UPDATE OPTIONS:
  --vmid=ID           Template VMID (required)
  --description=TEXT  New description
  --node=NODE         Target node

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") create --vmid=100
  $(basename "$0") list
  $(basename "$0") clone-from-template --template-vmid=9000 --new-vmid=100 --name=webserver --full
  $(basename "$0") update --vmid=9000 --description="Ubuntu 22.04 base template"
  $(basename "$0") delete --vmid=9000
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
VMID=""
NODE="${PMX_NODE:-}"
TEMPLATE_VMID=""
NEW_VMID=""
NAME=""
FULL=true
LINKED=false
TARGET_NODE=""
TARGET_STORAGE=""
DESCRIPTION=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid=*)             VMID="${1#*=}" ;;
            --template-vmid=*)    TEMPLATE_VMID="${1#*=}" ;;
            --new-vmid=*)         NEW_VMID="${1#*=}" ;;
            --name=*)             NAME="${1#*=}" ;;
            --target-node=*)      TARGET_NODE="${1#*=}" ;;
            --target-storage=*)   TARGET_STORAGE="${1#*=}" ;;
            --description=*)      DESCRIPTION="${1#*=}" ;;
            --node=*)             NODE="${1#*=}" ;;
            --full)               FULL=true; LINKED=false; shift; continue ;;
            --linked)             LINKED=true; FULL=false; shift; continue ;;
            --dry-run)            DRY_RUN=true; shift; continue ;;
            --help|-h)            usage ;;
            -*)                   log_error "Unknown option: $1"; usage ;;
            *)                    ACTION="$1" ;;
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

    log_info "Converting VM ${VMID} to template on node ${NODE}..."
    confirm "Convert VM ${VMID} to template? The VM will be stopped and this is irreversible." || exit 2
    dry_run api_call POST "/nodes/${NODE}/qemu/${VMID}/template"
    echo -e "${GREEN}VM ${VMID} converted to template.${NC}"
}

do_list() {
    log_info "Listing templates on node ${NODE}..."
    local resp
    resp=$(api_call GET "/nodes/${NODE}/qemu" 2>/dev/null) || {
        log_warn "Could not list VMs."
        return 0
    }

    echo ""
    printf "${BOLD}%-8s %-25s %-10s %-12s %-12s${NC}\n" \
        "VMID" "NAME" "STATUS" "CPU" "MEMORY"
    printf "%-8s %-25s %-10s %-12s %-12s\n" \
        "----" "----" "------" "---" "------"

    parse_json "${resp}" ".data[] | select(.template == 1)" 2>/dev/null | while IFS= read -r item; do
        local tvmid tname tstatus tcpu tmem
        tvmid=$(echo "${item}" | jq -r '.vmid // "unknown"')
        tname=$(echo "${item}" | jq -r '.name // "unnamed"')
        tstatus=$(echo "${item}" | jq -r '.status // "unknown"')
        tcpu=$(echo "${item}" | jq -r '.cpus // 0')
        tmem=$(echo "${item}" | jq -r '.maxmem // 0')

        local mem_h
        mem_h=$(numfmt --to=iec --suffix=B "${tmem}" 2>/dev/null || echo "${tmem}")

        printf "${CYAN}%-8s${NC} %-25s %-10s %-12s %-12s\n" \
            "${tvmid}" "${tname}" "${tstatus}" "${tcpu}" "${mem_h}"
    done
}

do_clone_from_template() {
    [[ -z "${TEMPLATE_VMID}" ]] && { log_error "--template-vmid is required."; exit 1; }

    local payload="{}"
    [[ -n "${NEW_VMID}" ]] && payload=$(echo "${payload}" | jq -c --argjson id "${NEW_VMID}" '. + {"newid": $id}')
    [[ -n "${NAME}" ]] && payload=$(echo "${payload}" | jq -c --arg n "${NAME}" '. + {"name": $n}')
    if [[ "${LINKED}" == "true" ]]; then
        payload=$(echo "${payload}" | jq -c '. + {"full": 0}')
    else
        payload=$(echo "${payload}" | jq -c '. + {"full": 1}')
    fi
    [[ -n "${TARGET_STORAGE}" ]] && payload=$(echo "${payload}" | jq -c --arg s "${TARGET_STORAGE}" '. + {"storage": $s}')
    [[ -n "${TARGET_NODE}" ]] && payload=$(echo "${payload}" | jq -c --arg n "${TARGET_NODE}" '. + {"target": $n}')

    log_info "Cloning from template ${TEMPLATE_VMID}..."
    local result
    result=$(dry_run api_call POST "/nodes/${NODE}/qemu/${TEMPLATE_VMID}/clone" -d "${payload}")

    local new_id="${NEW_VMID:-$(parse_json "${result}" ".data" 2>/dev/null)}"
    echo -e "${GREEN}Cloned template ${TEMPLATE_VMID} as VM ${new_id:-?}.${NC}"
}

do_delete() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }
    log_info "Deleting template ${VMID} on node ${NODE}..."
    confirm "Delete template ${VMID}? This is irreversible." || exit 2
    dry_run api_call DELETE "/nodes/${NODE}/qemu/${VMID}?purge=1"
    echo -e "${GREEN}Template ${VMID} deleted.${NC}"
}

do_update() {
    [[ -z "${VMID}" ]] && { log_error "--vmid is required."; exit 1; }

    local payload="{}"
    [[ -n "${DESCRIPTION}" ]] && payload=$(echo "${payload}" | jq -c --arg d "${DESCRIPTION}" '. + {"description": $d}')

    if [[ "${payload}" == "{}" ]]; then
        log_error "Specify at least --description."
        exit 1
    fi

    log_info "Updating template ${VMID}..."
    dry_run api_call PUT "/nodes/${NODE}/qemu/${VMID}/config" -d "${payload}"
    echo -e "${GREEN}Template ${VMID} updated.${NC}"
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
        create)              do_create ;;
        list)                do_list ;;
        clone-from-template) do_clone_from_template ;;
        delete)              do_delete ;;
        update)              do_update ;;
        *)                   log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
