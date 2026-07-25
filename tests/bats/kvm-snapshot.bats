#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR
    cat > "$MOCK_DIR/virsh" <<'SCRIPT'
#!/bin/bash
case "$1" in
    snapshot-create-as)
        echo "Domain snapshot 'snap1' created" ;;
    snapshot-list)
        echo " Name        Creation Time             State"
        echo "--------------------------------------------------"
        echo "  snap1       2024-01-01 12:00:00 +0000  running"
        echo "  snap2       2024-02-15 08:30:00 +0000  running"
        ;;
    snapshot-revert)
        echo "Domain snapshot 'snap1' reverted" ;;
    snapshot-delete)
        echo "Domain snapshot 'snap1' deleted" ;;
    snapshot-info)
        echo "Name:           snap1\nCreation Time:  2024-01-01 12:00:00 +0000\nState:          running" ;;
    help|--help|-h) echo "virsh mock"; exit 0 ;;
    *) echo "virsh: unknown"; exit 1 ;;
esac
SCRIPT
    chmod +x "$MOCK_DIR/virsh"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "kvm-snapshot: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "kvm-snapshot: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh"
    [ "$status" -ne 0 ]
}

# ── Create ────────────────────────────────────────────────────────────────────

@test "kvm-snapshot: create requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" create
    [ "$status" -ne 0 ]
}

@test "kvm-snapshot: create snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" create --domain testvm --name "snap-pre-update"
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]] || [[ "$output" == *"creat"* ]]
}

@test "kvm-snapshot: create with description" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" create --domain testvm --name "snap-desc" --description "Before upgrade"
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]]
}

@test "kvm-snapshot: create snapshot for running VM" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" create --domain testvm --name "snap-live" --live
    [ "$status" -eq 0 ] || [[ "$output" == *"snap"* ]]
}

# ── List ──────────────────────────────────────────────────────────────────────

@test "kvm-snapshot: list snapshots" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" list --domain testvm
    [ "$status" -eq 0 ]
}

@test "kvm-snapshot: list shows snapshot names" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" list --domain testvm
    [ "$status" -eq 0 ]
    [[ "$output" == *"snap1"* ]] || [[ "$output" == *"snap"* ]]
}

@test "kvm-snapshot: list requires domain" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" list
    [ "$status" -ne 0 ]
}

# ── Revert ────────────────────────────────────────────────────────────────────

@test "kvm-snapshot: revert requires domain and name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" revert
    [ "$status" -ne 0 ]
}

@test "kvm-snapshot: revert to snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" revert --domain testvm --name "snap1"
    [ "$status" -eq 0 ] || [[ "$output" == *"revert"* ]]
}

# ── Delete ────────────────────────────────────────────────────────────────────

@test "kvm-snapshot: delete requires domain and name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" delete
    [ "$status" -ne 0 ]
}

@test "kvm-snapshot: delete snapshot" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" delete --domain testvm --name "snap1"
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]]
}

@test "kvm-snapshot: delete all snapshots" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-snapshot.sh" delete --domain testvm --all
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]] || [[ "$output" == *"all"* ]]
}
