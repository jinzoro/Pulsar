#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared Bash library for Pulsar
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Pulsar contributors
# =============================================================================
# Provides logging, environment loading, prerequisite checks, API helpers,
# input prompts, and utility functions for all Bash scripts in this project.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Color / Formatting Variables
# ---------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color / Reset

# ---------------------------------------------------------------------------
# Exported Defaults
# ---------------------------------------------------------------------------
export LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_DIR="${LOG_DIR:-/var/log/Pulsar}"
export LOG_FILE=""
export DRY_RUN="${DRY_RUN:-false}"
export PMX_API_TOKEN="${PMX_API_TOKEN:-}"
export PMX_API_URL="${PMX_API_URL:-}"
export PMX_NODE="${PMX_NODE:-}"
export PMX_USER="${PMX_USER:-root@pam}"

# ---------------------------------------------------------------------------
# setup_logging
# ---------------------------------------------------------------------------
# Create the log directory (if it doesn't exist) and set the LOG_FILE path
# to a timestamped file.  Rotates old logs if the directory exceeds 10 MB.
# ---------------------------------------------------------------------------
setup_logging() {
    local log_dir="${1:-$LOG_DIR}"

    mkdir -p "${log_dir}" 2>/dev/null || {
        echo -e "${YELLOW}[WARN] Could not create log dir ${log_dir}; logging to stderr only.${NC}" >&2
        return 0
    }

    LOG_DIR="${log_dir}"
    LOG_FILE="${LOG_DIR}/Pulsar-$(date +%Y%m%d-%H%M%S).log"
    touch "${LOG_FILE}" 2>/dev/null || {
        LOG_FILE=""
        return 0
    }

    _rotate_logs "${log_dir}"
}

# ---------------------------------------------------------------------------
# _rotate_logs (internal)
# ---------------------------------------------------------------------------
# Compress logs older than the current one; remove compressed logs once the
# total directory size exceeds 10 MB.
# ---------------------------------------------------------------------------
_rotate_logs() {
    local log_dir="$1"
    local max_size_bytes=$((10 * 1024 * 1024)) # 10 MB

    # Compress uncompressed log files that are not the current active log
    while IFS= read -r -d '' old_log; do
        if [[ "${old_log}" != "${LOG_FILE}" && "${old_log}" != *.gz ]]; then
            gzip -f "${old_log}" 2>/dev/null || true
        fi
    done < <(find "${log_dir}" -maxdepth 1 -name '*.log' -print0 2>/dev/null)

    # Calculate total directory size
    local total_size
    total_size=$(du -sb "${log_dir}" 2>/dev/null | awk '{print $1}') || return 0
    total_size="${total_size:-0}"

    if (( total_size > max_size_bytes )); then
        # Remove oldest compressed files until we are under the limit
        while IFS= read -r -d '' old_gz; do
            local current_size
            current_size=$(du -sb "${log_dir}" 2>/dev/null | awk '{print $1}') || break
            current_size="${current_size:-0}"
            if (( current_size <= max_size_bytes )); then
                break
            fi
            rm -f "${old_gz}" 2>/dev/null || true
        done < <(find "${log_dir}" -maxdepth 1 -name '*.log.gz' -print0 2>/dev/null | sort -z)
    fi
}

# ---------------------------------------------------------------------------
# Logging Functions
# ---------------------------------------------------------------------------
# Each function writes to both stdout/stderr and the active log file (if set).
# Messages are filtered by the current LOG_LEVEL threshold.
# ---------------------------------------------------------------------------

# Determine numeric severity for comparison
_log_level_num() {
    case "${1,,}" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_log_write() {
    local level="$1"
    local color="$2"
    local msg="$3"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local entry="${ts} [${level}] ${msg}"

    # Filter by log level
    local current_num threshold_num
    threshold_num=$(_log_level_num "${LOG_LEVEL}")
    current_num=$(_log_level_num "${level}")
    if (( current_num < threshold_num )); then
        return 0
    fi

    # Write to stdout/stderr
    if [[ "${level}" == "ERROR" ]]; then
        echo -e "${color}${entry}${NC}" >&2
    else
        echo -e "${color}${entry}${NC}"
    fi

    # Append to log file if available
    if [[ -n "${LOG_FILE}" && -w "${LOG_FILE}" ]]; then
        echo "${entry}" >> "${LOG_FILE}"
    fi
}

log_debug() {
    _log_write "DEBUG" "${CYAN}" "$*"
}

log_info() {
    _log_write "INFO" "${GREEN}" "$*"
}

log_warn() {
    _log_write "WARN" "${YELLOW}" "$*"
}

log_error() {
    _log_write "ERROR" "${RED}" "$*"
}

# ---------------------------------------------------------------------------
# load_env
# ---------------------------------------------------------------------------
# Load key=value pairs from a .env file into the environment.
# Lines starting with # and blank lines are ignored.
# ---------------------------------------------------------------------------
load_env() {
    local env_file="${1:-.env}"

    if [[ ! -f "${env_file}" ]]; then
        log_warn "Env file not found: ${env_file} — skipping."
        return 0
    fi

    log_debug "Loading environment from ${env_file}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip comments and blank lines
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        # Strip inline comments
        line="${line%%#*}"
        # Split on first =
        local key="${line%%=*}"
        local value="${line#*=}"
        # Trim whitespace
        key="$(echo "${key}" | xargs)"
        value="$(echo "${value}" | xargs)"
        # Strip surrounding quotes from value
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        # Export if not already set
        if [[ -z "${!key:-}" ]]; then
            export "${key}=${value}"
        fi
    done < "${env_file}"
}

# ---------------------------------------------------------------------------
# check_prereqs
# ---------------------------------------------------------------------------
# Verify that all required commands are available on the system.
# Usage: check_prereqs curl jq ssh
# ---------------------------------------------------------------------------
check_prereqs() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Required command not found: ${cmd}"
            missing=1
        fi
    done
    if (( missing )); then
        log_error "Install missing dependencies and try again."
        return 1
    fi
    log_debug "All prerequisites satisfied: $*"
}

# ---------------------------------------------------------------------------
# check_root
# ---------------------------------------------------------------------------
# Verify the script is running as root or under sudo.
# ---------------------------------------------------------------------------
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo."
        return 1
    fi
    log_debug "Running as root."
}

# ---------------------------------------------------------------------------
# require_api_token
# ---------------------------------------------------------------------------
# Verify that the Proxmox API token environment variable is set.
# ---------------------------------------------------------------------------
require_api_token() {
    if [[ -z "${PMX_API_TOKEN}" ]]; then
        log_error "PMX_API_TOKEN environment variable is not set."
        log_error "Export it or add it to your .env file."
        return 1
    fi
    if [[ -z "${PMX_API_URL}" ]]; then
        log_error "PMX_API_URL environment variable is not set."
        return 1
    fi
    log_debug "Proxmox API token and URL are configured."
}

# ---------------------------------------------------------------------------
# require_libvirt
# ---------------------------------------------------------------------------
# Verify that virsh is installed and can connect to the configured URI.
# ---------------------------------------------------------------------------
require_libvirt() {
    if ! command -v virsh &>/dev/null; then
        log_error "virsh (libvirt) is not installed."
        return 1
    fi

    local uri="${1:-qemu:///system}"
    if ! virsh -c "${uri}" list &>/dev/null; then
        log_error "Cannot connect to libvirt at URI: ${uri}"
        return 1
    fi
    log_debug "libvirt connection verified: ${uri}"
}

# ---------------------------------------------------------------------------
# dry_run
# ---------------------------------------------------------------------------
# If DRY_RUN is true, print the command and return 0 without executing.
# Otherwise, execute the command normally.
# ---------------------------------------------------------------------------
dry_run() {
    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] $*"
        return 0
    fi
    log_debug "Executing: $*"
    "$@"
}

# ---------------------------------------------------------------------------
# confirm
# ---------------------------------------------------------------------------
# Prompt the user for y/n confirmation.  Returns 0 on yes, 1 on no.
# Usage: confirm "Are you sure you want to delete VM 100?" || exit 1
# ---------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    if [[ "${DRY_RUN,,}" == "true" || "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY RUN] Would ask: ${prompt}"
        return 0
    fi

    local yn_hint="[y/N]"
    if [[ "${default}" == "y" || "${default}" == "Y" ]]; then
        yn_hint="[Y/n]"
    fi

    while true; do
        read -r -p "${BOLD}${prompt} ${yn_hint} ${NC}" answer
        answer="${answer:-${default}}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer y or n." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# api_call
# ---------------------------------------------------------------------------
# Wrapper around curl for Proxmox VE REST API calls.
# Handles authentication headers, JSON parsing, and error detection.
#
# Usage:
#   api_call GET /nodes/pve1/status
#   api_call POST /nodes/pve1/qemu/100/status/start
#   api_call DELETE /nodes/pve1/qemu/100/snapshots/mysnap
# ---------------------------------------------------------------------------
api_call() {
    local method="${1}"
    local endpoint="${2}"
    shift 2
    local -a extra_args=("$@")

    require_api_token

    local url="${PMX_API_URL}/api2/json${endpoint}"
    local auth_header="Authorization: PMXAPIToken=${PMX_API_TOKEN}"

    log_debug "API ${method} ${url}"

    local http_code body tmp_file
    tmp_file=$(mktemp)

    local curl_args=(
        -s
        -w '%{http_code}'
        -o "${tmp_file}"
        -X "${method}"
        -H "${auth_header}"
        -H "Content-Type: application/json"
        --connect-timeout 10
        --max-time 30
    )

    if (( ${#extra_args[@]} )); then
        curl_args+=("${extra_args[@]}")
    fi

    http_code=$(curl "${curl_args[@]}" "${url}" 2>/dev/null) || {
        rm -f "${tmp_file}"
        log_error "curl request failed for ${method} ${endpoint}"
        return 1
    }

    body=$(cat "${tmp_file}")
    rm -f "${tmp_file}"

    # Check for API errors
    if (( http_code >= 400 )); then
        local err_msg
        err_msg=$(parse_json "${body}" ".errors // .data // empty" 2>/dev/null || echo "${body}")
        log_error "API error ${http_code} on ${method} ${endpoint}: ${err_msg}"
        return 1
    fi

    log_debug "API response (${http_code}): ${body}"
    echo "${body}"
}

# ---------------------------------------------------------------------------
# parse_json
# ---------------------------------------------------------------------------
# Wrapper around jq with error handling.
# Usage: parse_json '{"a":1}' '.a'
# ---------------------------------------------------------------------------
parse_json() {
    local input="$1"
    local filter="${2:-.}"

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for JSON parsing but is not installed."
        return 1
    fi

    local result
    result=$(echo "${input}" | jq -r "${filter}" 2>/dev/null) || {
        log_error "Failed to parse JSON with filter: ${filter}"
        return 1
    }

    echo "${result}"
}

# ---------------------------------------------------------------------------
# get_vm_status
# ---------------------------------------------------------------------------
# Get the status of a specific VM via the Proxmox API.
# Usage: get_vm_status <vmid> [host_name]
# ---------------------------------------------------------------------------
get_vm_status() {
    local vmid="$1"
    local host="${2:-$(hostname)}"
    local node="${PMX_NODE:-$(hostname)}"

    local response
    response=$(api_call GET "/nodes/${node}/qemu/${vmid}/status/current") || return 1
    parse_json "${response}" ".data.status"
}

# ---------------------------------------------------------------------------
# get_node_status
# ---------------------------------------------------------------------------
# Get node information via the Proxmox API.
# Usage: get_node_status [node_name]
# ---------------------------------------------------------------------------
get_node_status() {
    local node="${1:-${PMX_NODE:-$(hostname)}}"

    local response
    response=$(api_call GET "/nodes/${node}/status") || return 1
    echo "${response}"
}

# ---------------------------------------------------------------------------
# spinner
# ---------------------------------------------------------------------------
# Display a terminal spinner while a command runs in the background.
# Usage:
#   spinner $! "Performing backup..."
# ---------------------------------------------------------------------------
spinner() {
    local pid="$1"
    local message="${2:-Working...}"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    echo -ne "${CYAN}${message} ${NC}" >&2

    while kill -0 "${pid}" 2>/dev/null; do
        local char="${spin_chars:i++%${#spin_chars}:1}"
        echo -ne "\r${CYAN}${message} ${char}${NC}" >&2
        sleep 0.1
    done

    echo -ne "\r\033[K" >&2
}

# ---------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------
# Trap handler for cleanup on EXIT, ERR, INT, TERM.
# Override by defining your own _custom_cleanup before sourcing this file.
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    log_debug "Cleanup triggered (exit code: ${exit_code})"

    # Call custom cleanup if defined
    if declare -f _custom_cleanup &>/dev/null; then
        _custom_cleanup
    fi

    # Remove temporary files created during this session
    if [[ -n "${_TMP_FILES:-}" ]]; then
        for tmp in "${_TMP_FILES[@]}"; do
            rm -f "${tmp}" 2>/dev/null || true
        done
    fi
}

trap cleanup EXIT
trap 'log_error "Interrupted (signal)."; exit 130' INT
trap 'log_error "Terminated (signal)."; exit 143' TERM
trap 'log_error "Error on line ${LINENO}."; exit 1' ERR

# Track temporary files for automatic cleanup
_TMP_FILES=()

# Usage: create_temp_file  — adds to _TMP_FILES and echoes the path
create_temp_file() {
    local tmp
    tmp=$(mktemp)
    _TMP_FILES+=("${tmp}")
    echo "${tmp}"
}

# ---------------------------------------------------------------------------
# print_help_header
# ---------------------------------------------------------------------------
# Print a standard help header for scripts.
# Usage: print_help_header "script-name" "Short description of what it does."
# ---------------------------------------------------------------------------
print_help_header() {
    local name="${1:-$(basename "$0")}"
    local description="${2:-Proxmox KVM Swiss Knife utility}"

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  ${name}${NC}"
    echo -e "${BOLD}${GREEN}║  ${description}${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Export functions for use in subshells / child scripts
# ---------------------------------------------------------------------------
export -f log_debug log_info log_warn log_error
export -f load_env check_prereqs check_root require_api_token require_libvirt
export -f dry_run confirm api_call parse_json
export -f get_vm_status get_node_status spinner cleanup print_help_header
export -f create_temp_file setup_logging
