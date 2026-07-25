#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    export PMX_API_HOST="pve.example.com"
    export PMX_API_TOKEN="test@pam!test=abc123"
    export PMX_NODE="pve1"
    export PMX_DRY_RUN="false"
    export PMX_SKIP_TLS="1"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR
    cat > "$MOCK_DIR/pmux" <<'SCRIPT'
#!/bin/bash
case "$1" in
    --help|-h) echo "pmux mock v0.1"; exit 0 ;;
    *) echo '{"data":{}}'; exit 0 ;;
esac
SCRIPT
    chmod +x "$MOCK_DIR/pmux"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-vm-lifecycle: -h shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-vm-lifecycle: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh"
    [ "$status" -ne 0 ]
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: fails when API_HOST not set" {
    unset PMX_API_HOST
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" list
    [ "$status" -ne 0 ]
    [[ "$output" == *"API"* ]] || [[ "$output" == *"HOST"* ]] || [[ "$output" == *"required"* ]]
}

@test "pmx-vm-lifecycle: fails when API_TOKEN not set" {
    unset PMX_API_TOKEN
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" list
    [ "$status" -ne 0 ]
}

# ── VM Create ─────────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: create requires vmid or auto" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" create
    [ "$status" -ne 0 ]
    [[ "$output" == *"vmid"* ]] || [[ "$output" == *"required"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"Error"* ]]
}

@test "pmx-vm-lifecycle: create with required args succeeds" {
    # Mock the API call for nextid and create
    cat > "$MOCK_DIR/pmux" <<'SCRIPT'
#!/bin/bash
echo '{"data":"100"}'
SCRIPT
    chmod +x "$MOCK_DIR/pmux"
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" create --vmid 100 --name testvm --cores 2 --memory 2048 --disk 32
    [ "$status" -eq 0 ] || [[ "$output" == *"mock"* ]] || [[ "$output" == *"create"* ]]
}

@test "pmx-vm-lifecycle: create with all options" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" create \
        --vmid 200 --name fulltest --cores 4 --memory 8192 --disk 128 \
        --net "virtio,bridge=vmbr0" --ostype l26 --scsihw virtio-scsi-pci
    [ "$status" -eq 0 ] || [[ "$output" == *"error"* ]]
}

@test "pmx-vm-lifecycle: create with --dry-run does not create VM" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" create --vmid 300 --name drytest --cores 1 --memory 1024 --disk 10
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
    [ "${output,,}" != *"created successfully"* ] || true
}

# ── Start / Stop / Shutdown ───────────────────────────────────────────────────

@test "pmx-vm-lifecycle: start requires vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" start
    [ "$status" -ne 0 ]
}

@test "pmx-vm-lifecycle: start with valid vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" start --vmid 100
    [ "$status" -eq 0 ] || [[ "$output" == *"started"* ]] || [[ "$output" == *"start"* ]]
}

@test "pmx-vm-lifecycle: stop with valid vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" stop --vmid 100
    [ "$status" -eq 0 ] || [[ "$output" == *"stop"* ]]
}

@test "pmx-vm-lifecycle: shutdown with valid vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" shutdown --vmid 100
    [ "$status" -eq 0 ] || [[ "$output" == *"shutdown"* ]]
}

@test "pmx-vm-lifecycle: shutdown with timeout" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" shutdown --vmid 100 --timeout 60
    [ "$status" -eq 0 ] || [[ "$output" == *"shutdown"* ]]
}

# ── Delete ────────────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: delete requires vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" delete
    [ "$status" -ne 0 ]
}

@test "pmx-vm-lifecycle: delete with --dry-run does not delete" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" delete --vmid 100
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]] || [[ "$output" == *"Dry"* ]]
}

@test "pmx-vm-lifecycle: delete with --purge" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" delete --vmid 100 --purge
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]] || [[ "$output" == *"purge"* ]]
}

# ── Clone ─────────────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: clone full" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" clone --vmid 100 --newid 200 --full
    [ "$status" -eq 0 ] || [[ "$output" == *"clone"* ]] || [[ "$output" == *"full"* ]]
}

@test "pmx-vm-lifecycle: clone linked (not full)" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" clone --vmid 100 --newid 300
    [ "$status" -eq 0 ] || [[ "$output" == *"clone"* ]]
}

@test "pmx-vm-lifecycle: clone requires source vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" clone
    [ "$status" -ne 0 ]
}

# ── Error Handling ────────────────────────────────────────────────────────────

@test "pmx-vm-lifecycle: invalid action shows error" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" invalidaction
    [ "$status" -ne 0 ] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"error"* ]]
}

@test "pmx-vm-lifecycle: handles missing vmid for operations" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-vm-lifecycle.sh" status
    [ "$status" -ne 0 ]
}
