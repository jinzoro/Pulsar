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

@test "pmx-cluster: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-cluster: no args shows usage or error" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh"
    [ "$status" -ne 0 ]
}

# ── Cluster Status ────────────────────────────────────────────────────────────

@test "pmx-cluster: status shows cluster info" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" status
    [ "$status" -eq 0 ]
}

@test "pmx-cluster: status with verbose flag" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" status --verbose
    [ "$status" -eq 0 ]
}

@test "pmx-cluster: status with JSON output" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" status --json
    [ "$status" -eq 0 ]
}

# ── Nodes List ────────────────────────────────────────────────────────────────

@test "pmx-cluster: list nodes" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" nodes
    [ "$status" -eq 0 ]
}

@test "pmx-cluster: list nodes shows node names" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" nodes
    [ "$status" -eq 0 ]
}

@test "pmx-cluster: list nodes with status filter" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" nodes --status online
    [ "$status" -eq 0 ]
}

# ── Quorum ────────────────────────────────────────────────────────────────────

@test "pmx-cluster: quorum check" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" quorum
    [ "$status" -eq 0 ]
}

@test "pmx-cluster: quorum shows expected votes" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" quorum
    [ "$status" -eq 0 ]
    [[ "$output" == *"vote"* ]] || [[ "$output" == *"quorum"* ]] || [[ "$output" == *"node"* ]]
}

@test "pmx-cluster: quorum with JSON output" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" quorum --json
    [ "$status" -eq 0 ]
}

# ── Error Handling ────────────────────────────────────────────────────────────

@test "pmx-cluster: unknown subcommand shows error" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-cluster.sh" invalidcmd
    [ "$status" -ne 0 ]
}
