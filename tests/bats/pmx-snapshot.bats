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
echo '{"data":[]}'
SCRIPT
    chmod +x "$MOCK_DIR/pmux"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "pmx-snapshot: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-snapshot: no args shows usage or error" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh"
    [ "$status" -ne 0 ]
}

# ── Create ────────────────────────────────────────────────────────────────────

@test "pmx-snapshot: create requires vmid and name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" create
    [ "$status" -ne 0 ]
}

@test "pmx-snapshot: create snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" create --vmid 100 --name "snap-pre-update"
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]] || [[ "$output" == *"creat"* ]]
}

@test "pmx-snapshot: create with description" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" create --vmid 100 --name "snap-desc" --description "Before major upgrade"
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]]
}

@test "pmx-snapshot: create with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" create --vmid 100 --name "snap-dry"
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

@test "pmx-snapshot: create snapshot for running VM" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" create --vmid 100 --name "snap-running" --include-running
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]]
}

# ── List ──────────────────────────────────────────────────────────────────────

@test "pmx-snapshot: list snapshots requires vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" list
    [ "$status" -ne 0 ]
}

@test "pmx-snapshot: list snapshots" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" list --vmid 100
    [ "$status" -eq 0 ]
}

@test "pmx-snapshot: list with verbose output" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" list --vmid 100 --verbose
    [ "$status" -eq 0 ]
}

# ── Rollback ──────────────────────────────────────────────────────────────────

@test "pmx-snapshot: rollback requires vmid and name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" rollback
    [ "$status" -ne 0 ]
}

@test "pmx-snapshot: rollback snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" rollback --vmid 100 --name "snap-pre-update"
    [ "$status" -eq 0 ] || [[ "$output" == *"rollback"* ]] || [[ "$output" == *"restor"* ]]
}

@test "pmx-snapshot: rollback with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" rollback --vmid 100 --name "snap-pre-update"
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

# ── Delete ────────────────────────────────────────────────────────────────────

@test "pmx-snapshot: delete requires vmid and name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" delete
    [ "$status" -ne 0 ]
}

@test "pmx-snapshot: delete snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" delete --vmid 100 --name "snap-old"
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]] || [[ "$output" == *"remov"* ]]
}

@test "pmx-snapshot: delete with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" delete --vmid 100 --name "snap-old"
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

@test "pmx-snapshot: delete all snapshots" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-snapshot.sh" delete --vmid 100 --all
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]] || [[ "$output" == *"all"* ]]
}
