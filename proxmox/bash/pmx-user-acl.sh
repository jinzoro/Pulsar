#!/usr/bin/env bash
# =============================================================================
# pmx-user-acl.sh — User and ACL management
# =============================================================================
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 proxmox-kvm-swissknife contributors
# =============================================================================
# Operations: users, groups, roles, acl, tokens, tfa
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shared/bash/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_help_header "$(basename "$0")" "User and ACL management"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] OPERATION [ARGS...]

OPERATIONS:
  users-list          List all users
  user-create         --userid=ID --realm=REALM [OPTIONS]
  user-delete         --userid=ID --realm=REALM
  user-set-password   --userid=ID --realm=REALM --password=PASS
  groups-list         List all groups
  group-create        --group=NAME [--members=USER1,USER2]
  group-delete        --group=NAME
  roles-list          List all roles
  role-create         --role=NAME [--privileges=PRIV1,PRIV2]
  role-delete         --role=NAME
  acl-set             --path=PATH --user/usergroup=ID --role=ROLE
  acl-remove          --path=PATH --user/usergroup=ID --role=ROLE
  tokens-list         --userid=ID --realm=REALM
  token-create        --userid=ID --realm=REALM --token-id=TID [OPTIONS]
  token-delete        --userid=ID --realm=REALM --token-id=TID
  token-modify        --userid=ID --realm=REALM --token-id=TID [OPTIONS]
  tfa-list            --userid=ID --realm=REALM
  tfa-enable          --userid=ID --realm=REALM
  tfa-disable         --userid=ID --realm=REALM

USER OPTIONS:
  --userid=USER       Username (required)
  --realm=REALM       Authentication realm: pam, pve, ldap (required)
  --email=EMAIL       Email address
  --groups=LIST       Comma-separated group list
  --enable            Enable user (default)
  --disable           Disable user
  --password=PASS     Password

TOKEN OPTIONS:
  --token-id=TID      Token identifier
  --priv-sep          Enable privilege separation
  --expire=DATE       Expiration date (ISO format)

ACL OPTIONS:
  --path=PATH         ACL path (e.g. /vms/100, /storage/backup)
  --user=USER         User ID (userid@realm)
  --usergroup=GROUP   User group
  --role=ROLE         Role name

ROLE PRIVILEGES:
  VM.Allocate, VM.Allocate.Space, VM.Clone, VM.Config.*, VM.Migrate,
  VM.Monitor, VM.Power.*, VM.Snapshot.*, VM.Audit, Datastore.AllocateSpace,
  Datastore.Allocate, Datastore.Audit, Sys.Audit, Sys.Modify, ...

OPTIONS:
  --dry-run           Show what would be done
  --help, -h          Show this help

EXAMPLES:
  $(basename "$0") users-list
  $(basename "$0") user-create --userid=john --realm=pve --email=john@example.com --groups=admin
  $(basename "$0") acl-set --path=/vms --user=john@pve --role=PVEAuditor
  $(basename "$0") token-create --userid=john --realm=pve --token-id=api-token
  $(basename "$0") roles-list
  $(basename "$0") group-create --group=devops --members=john,jane
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ACTION=""
USERID=""
REALM=""
EMAIL=""
GROUPS=""
GROUP=""
PASSWORD=""
ENABLE_FLAG=true
TOKEN_ID=""
PRIV_SEP=false
EXPIRE=""
PATH_ACL=""
USER_TARGET=""
USERGROUP=""
ROLE=""
TOKEN_NAME=""
ROLE_PRIVS=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --userid=*)        USERID="${1#*=}" ;;
            --realm=*)         REALM="${1#*=}" ;;
            --email=*)         EMAIL="${1#*=}" ;;
            --groups=*)        GROUPS="${1#*=}" ;;
            --group=*)         GROUP="${1#*=}" ;;
            --password=*)      PASSWORD="${1#*=}" ;;
            --token-id=*)      TOKEN_ID="${1#*=}" ;;
            --expire=*)        EXPIRE="${1#*=}" ;;
            --path=*)          PATH_ACL="${1#*=}" ;;
            --user=*)          USER_TARGET="${1#*=}" ;;
            --usergroup=*)     USERGROUP="${1#*=}" ;;
            --role=*)          ROLE="${1#*=}" ;;
            --privileges=*)    ROLE_PRIVS="${1#*=}" ;;
            --members=*)       GROUPS="${1#*=}" ;;
            --enable)          ENABLE_FLAG=true; shift; continue ;;
            --disable)         ENABLE_FLAG=false; shift; continue ;;
            --priv-sep)        PRIV_SEP=true; shift; continue ;;
            --dry-run)         DRY_RUN=true; shift; continue ;;
            --help|-h)         usage ;;
            -*)                log_error "Unknown option: $1"; usage ;;
            *)                 ACTION="$1" ;;
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
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------
do_users_list() {
    log_info "Listing users..."
    local resp
    resp=$(api_call GET "/access/users" 2>/dev/null) || {
        log_warn "No users found."
        return 0
    }

    echo ""
    printf "${BOLD}%-25s %-20s %-10s %-40s${NC}\n" "USERID" "GROUPS" "ENABLED" "EMAIL"
    printf "%-25s %-20s %-10s %-40s\n" "------" "------" "-------" "-----"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local uid ugroups uenabled uemail
        uid=$(echo "${item}" | jq -r '.userid // "unknown"')
        ugroups=$(echo "${item}" | jq -r '.groups // ""')
        uenabled=$(echo "${item}" | jq -r '.enable // 1')
        uemail=$(echo "${item}" | jq -r '.email // ""')

        local ena_str="yes"
        [[ "${uenabled}" == "0" ]] && ena_str="no"

        printf "%-25s %-20s ${GREEN}%-10s${NC} %-40s\n" "${uid}" "${ugroups}" "${ena_str}" "${uemail}"
    done
}

do_user_create() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    local payload
    payload=$(jq -n \
        --arg userid "${full_id}" \
        --arg email "${EMAIL}" \
        --arg groups "${GROUPS}" \
        --argjson enable "$([ "${ENABLE_FLAG}" = true ] && echo 1 || echo 0)" \
        '{"userid": $userid}')
    [[ -n "${EMAIL}" ]] && payload=$(echo "${payload}" | jq -c --arg e "${EMAIL}" '. + {"email": $e}')
    [[ -n "${GROUPS}" ]] && payload=$(echo "${payload}" | jq -c --arg g "${GROUPS}" '. + {"groups": $g}')

    log_info "Creating user ${full_id}..."
    dry_run api_call POST "/access/users" -d "${payload}"
    echo -e "${GREEN}User ${full_id} created.${NC}"
}

do_user_delete() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Deleting user ${full_id}..."
    confirm "Delete user ${full_id}?" || exit 2
    dry_run api_call DELETE "/access/users/${full_id}"
    echo -e "${GREEN}User ${full_id} deleted.${NC}"
}

do_user_set_password() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }
    [[ -z "${PASSWORD}" ]] && { log_error "--password is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Setting password for ${full_id}..."
    dry_run api_call PUT "/access/users/${full_id}/password" \
        -d "{\"password\":\"${PASSWORD}\"}"
    echo -e "${GREEN}Password updated for ${full_id}.${NC}"
}

do_groups_list() {
    log_info "Listing groups..."
    local resp
    resp=$(api_call GET "/access/groups" 2>/dev/null) || {
        log_warn "No groups found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-40s${NC}\n" "GROUP" "COMMENT"
    printf "%-20s %-40s\n" "-----" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local gname gcmt
        gname=$(echo "${item}" | jq -r '.groupid // "unknown"')
        gcmt=$(echo "${item}" | jq -r '.comment // ""')
        printf "%-20s %-40s\n" "${gname}" "${gcmt}"
    done
}

do_group_create() {
    [[ -z "${GROUP}" ]] && { log_error "--group is required."; exit 1; }

    log_info "Creating group '${GROUP}'..."
    local payload="{\"groupid\":\"${GROUP}\"}"
    [[ -n "${GROUPS}" ]] && payload=$(echo "${payload}" | jq -c --arg m "${GROUPS}" '. + {"members": $m}')

    dry_run api_call POST "/access/groups" -d "${payload}"
    echo -e "${GREEN}Group '${GROUP}' created.${NC}"
}

do_group_delete() {
    [[ -z "${GROUP}" ]] && { log_error "--group is required."; exit 1; }
    log_info "Deleting group '${GROUP}'..."
    confirm "Delete group '${GROUP}'?" || exit 2
    dry_run api_call DELETE "/access/groups/${GROUP}"
    echo -e "${GREEN}Group '${GROUP}' deleted.${NC}"
}

do_roles_list() {
    log_info "Listing roles..."
    local resp
    resp=$(api_call GET "/access/roles" 2>/dev/null) || {
        log_warn "No roles found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-60s${NC}\n" "ROLE" "PRIVILEGES"
    printf "%-20s %-60s\n" "----" "----------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local rname rprivs
        rname=$(echo "${item}" | jq -r '.roleid // "unknown"')
        rprivs=$(echo "${item}" | jq -r '.privs // ""' | tr '\n' ' ')
        printf "%-20s %-60s\n" "${rname}" "${rprivs}"
    done
}

do_role_create() {
    [[ -z "${ROLE}" ]] && { log_error "--role is required."; exit 1; }
    [[ -z "${ROLE_PRIVS}" ]] && { log_error "--privileges is required."; exit 1; }

    log_info "Creating role '${ROLE}'..."
    local privs_json
    privs_json=$(echo "${ROLE_PRIVS}" | jq -Rc 'split(",")')

    dry_run api_call POST "/access/roles" \
        -d "{\"roleid\":\"${ROLE}\",\"privs\":${privs_json}}"
    echo -e "${GREEN}Role '${ROLE}' created.${NC}"
}

do_role_delete() {
    [[ -z "${ROLE}" ]] && { log_error "--role is required."; exit 1; }
    log_info "Deleting role '${ROLE}'..."
    confirm "Delete role '${ROLE}'?" || exit 2
    dry_run api_call DELETE "/access/roles/${ROLE}"
    echo -e "${GREEN}Role '${ROLE}' deleted.${NC}"
}

do_acl_set() {
    [[ -z "${PATH_ACL}" ]] && { log_error "--path is required."; exit 1; }
    [[ -z "${ROLE}" ]] && { log_error "--role is required."; exit 1; }

    local payload="{\"path\":\"${PATH_ACL}\",\"role\":\"${ROLE}\"}"
    if [[ -n "${USER_TARGET}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg u "${USER_TARGET}" '. + {"ugid": $u, "type": "user"}')
    elif [[ -n "${USERGROUP}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg g "${USERGROUP}" '. + {"ugid": $g, "type": "group"}')
    else
        log_error "Either --user or --usergroup is required."
        exit 1
    fi

    log_info "Setting ACL..."
    dry_run api_call POST "/access/acl" -d "${payload}"
    echo -e "${GREEN}ACL set.${NC}"
}

do_acl_remove() {
    [[ -z "${PATH_ACL}" ]] && { log_error "--path is required."; exit 1; }
    [[ -z "${ROLE}" ]] && { log_error "--role is required."; exit 1; }

    local payload="{\"path\":\"${PATH_ACL}\",\"role\":\"${ROLE}\"}"
    if [[ -n "${USER_TARGET}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg u "${USER_TARGET}" '. + {"ugid": $u, "type": "user"}')
    elif [[ -n "${USERGROUP}" ]]; then
        payload=$(echo "${payload}" | jq -c --arg g "${USERGROUP}" '. + {"ugid": $g, "type": "group"}')
    else
        log_error "Either --user or --usergroup is required."
        exit 1
    fi

    log_info "Removing ACL..."
    confirm "Remove ACL?" || exit 2
    dry_run api_call DELETE "/access/acl" -d "${payload}"
    echo -e "${GREEN}ACL removed.${NC}"
}

do_tokens_list() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Listing tokens for ${full_id}..."
    local resp
    resp=$(api_call GET "/access/users/${full_id}/token" 2>/dev/null) || {
        log_warn "No tokens found."
        return 0
    }

    echo ""
    printf "${BOLD}%-20s %-10s %-20s %-20s${NC}\n" "TOKEN" "ENABLED" "EXPIRE" "COMMENT"
    printf "%-20s %-10s %-20s %-20s\n" "-----" "-------" "------" "-------"

    parse_json "${resp}" ".data[]" 2>/dev/null | while IFS= read -r item; do
        local tname tenabled texpire tcmt
        tname=$(echo "${item}" | jq -r '.tokenid // "unknown"')
        tenabled=$(echo "${item}" | jq -r '.enable // 1')
        texpire=$(echo "${item}" | jq -r '.expire // "never"')
        tcmt=$(echo "${item}" | jq -r '.comment // ""')

        local ena_str="yes"
        [[ "${tenabled}" == "0" ]] && ena_str="no"

        printf "%-20s ${GREEN}%-10s${NC} %-20s %-20s\n" "${tname}" "${ena_str}" "${texpire}" "${tcmt}"
    done
}

do_token_create() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }
    [[ -z "${TOKEN_ID}" ]] && { log_error "--token-id is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    local payload="{\"tokenid\":\"${TOKEN_ID}\"}"
    [[ "${PRIV_SEP}" == "true" ]] && payload=$(echo "${payload}" | jq -c '. + {"privsep": 1}')
    [[ -n "${EXPIRE}" ]] && payload=$(echo "${payload}" | jq -c --arg e "${EXPIRE}" '. + {"expire": $e}')

    log_info "Creating token '${TOKEN_ID}' for ${full_id}..."
    local result
    result=$(dry_run api_call POST "/access/users/${full_id}/token" -d "${payload}")

    local secret
    secret=$(parse_json "${result}" ".data.value" 2>/dev/null)
    if [[ -n "${secret}" ]]; then
        echo -e "${GREEN}Token created.${NC}"
        echo -e "${BOLD}Secret:${NC} ${secret}"
        echo -e "${YELLOW}Save this secret now - it will not be shown again.${NC}"
    fi
}

do_token_delete() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }
    [[ -z "${TOKEN_ID}" ]] && { log_error "--token-id is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Deleting token '${TOKEN_ID}' for ${full_id}..."
    confirm "Delete token '${TOKEN_ID}'?" || exit 2
    dry_run api_call DELETE "/access/users/${full_id}/token/${TOKEN_ID}"
    echo -e "${GREEN}Token deleted.${NC}"
}

do_token_modify() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }
    [[ -z "${TOKEN_ID}" ]] && { log_error "--token-id is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    local payload="{}"
    payload=$(echo "${payload}" | jq -c --argjson e "$([ "${ENABLE_FLAG}" = true ] && echo 1 || echo 0)" '. + {"enable": $e}')
    [[ -n "${EXPIRE}" ]] && payload=$(echo "${payload}" | jq -c --arg exp "${EXPIRE}" '. + {"expire": $exp}')
    [[ "${PRIV_SEP}" == "true" ]] && payload=$(echo "${payload}" | jq -c '. + {"privsep": 1}')

    log_info "Modifying token '${TOKEN_ID}'..."
    dry_run api_call PUT "/access/users/${full_id}/token/${TOKEN_ID}" -d "${payload}"
    echo -e "${GREEN}Token modified.${NC}"
}

do_tfa_list() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Listing TFA for ${full_id}..."
    api_call GET "/access/users/${full_id}/tfa" 2>/dev/null || {
        log_info "No TFA configured."
    }
}

do_tfa_enable() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Enabling TFA for ${full_id}..."
    dry_run api_call POST "/access/users/${full_id}/tfa" -d '{"type":"totp"}'
    echo -e "${GREEN}TFA enrollment initiated for ${full_id}.${NC}"
}

do_tfa_disable() {
    [[ -z "${USERID}" ]] && { log_error "--userid is required."; exit 1; }
    [[ -z "${REALM}" ]] && { log_error "--realm is required."; exit 1; }

    local full_id="${USERID}@${REALM}"
    log_info "Disabling TFA for ${full_id}..."
    confirm "Disable TFA for ${full_id}?" || exit 2
    dry_run api_call DELETE "/access/users/${full_id}/tfa"
    echo -e "${GREEN}TFA disabled for ${full_id}.${NC}"
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
        users-list)        do_users_list ;;
        user-create)       do_user_create ;;
        user-delete)       do_user_delete ;;
        user-set-password) do_user_set_password ;;
        groups-list)       do_groups_list ;;
        group-create)      do_group_create ;;
        group-delete)      do_group_delete ;;
        roles-list)        do_roles_list ;;
        role-create)       do_role_create ;;
        role-delete)       do_role_delete ;;
        acl-set)           do_acl_set ;;
        acl-remove)        do_acl_remove ;;
        tokens-list)       do_tokens_list ;;
        token-create)      do_token_create ;;
        token-delete)      do_token_delete ;;
        token-modify)      do_token_modify ;;
        tfa-list)          do_tfa_list ;;
        tfa-enable)        do_tfa_enable ;;
        tfa-disable)       do_tfa_disable ;;
        *)                 log_error "Unknown operation: ${ACTION}"; usage ;;
    esac
}

main "$@"
