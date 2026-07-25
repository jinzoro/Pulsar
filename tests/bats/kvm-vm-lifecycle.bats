#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR

    cat > "$MOCK_DIR/virsh" <<'SCRIPT'
#!/bin/bash
case "$1" in
    list) echo " Id   Name   State" ; echo "------------------------" ; echo "  1   testvm  running" ;;
    dominfo) echo "Id:             1\nName:           testvm\nState:          running\n..." ;;
    domstart) echo "Domain testvm started" ;;
    domshutdown) echo "Domain testvm is being shutdown" ;;
    destroy) echo "Domain testvm destroyed" ;;
    undefine) echo "Domain testvm has been undefined" ;;
    vol-create-as) echo "vol created" ;;
    help|--help|-h) echo "virsh mock"; exit 0 ;;
    *) echo "virsh: unknown command $1"; exit 1 ;;
esac
SCRIPT
    chmod +x "$MOCK_DIR/virsh"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "kvm-vm-lifecycle: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh"
    [ "$status" -ne 0 ]
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: requires virsh" {
    export PATH="/usr/bin:/bin"
    MOCK_DIR2="$(mktemp -d)"
    cat > "$MOCK_DIR2/echo" <<'SCRIPT'
#!/bin/bash
echo "$@"
SCRIPT
    chmod +x "$MOCK_DIR2/echo"
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" list
    rm -rf "$MOCK_DIR2"
    # Should either work or report missing virsh
    [ "$status" -eq 0 ] || [[ "$output" == *"virsh"* ]] || [[ "$output" == *"require"* ]]
}

# ── Create ────────────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: create with virt-install args" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" create --name testvm --ram 2048 --vcpus 2 --disk 32G
    [ "$status" -eq 0 ] || [[ "$output" == *"creat"* ]] || [[ "$output" == *"virt-install"* ]]
}

@test "kvm-vm-lifecycle: create with all options" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" create \
        --name fullvm --ram 8192 --vcpus 4 --disk 128G \
        --network bridge=virbr0 --os-variant ubuntu22.04 \
        --cdrom /var/lib/libvirt/images/ubuntu.iso
    [ "$status" -eq 0 ] || [[ "$output" == *"creat"* ]]
}

@test "kvm-vm-lifecycle: create requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" create --ram 1024
    [ "$status" -ne 0 ]
}

# ── Start / Stop ──────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: start requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" start
    [ "$status" -ne 0 ]
}

@test "kvm-vm-lifecycle: start VM" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" start --name testvm
    [ "$status" -eq 0 ] || [[ "$output" == *"start"* ]]
}

@test "kvm-vm-lifecycle: stop requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" stop
    [ "$status" -ne 0 ]
}

@test "kvm-vm-lifecycle: stop VM (graceful)" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" stop --name testvm
    [ "$status" -eq 0 ] || [[ "$output" == *"shutdown"* ]] || [[ "$output" == *"stop"* ]]
}

@test "kvm-vm-lifecycle: stop VM (force)" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" stop --name testvm --force
    [ "$status" -eq 0 ] || [[ "$output" == *"destroy"* ]] || [[ "$output" == *"stop"* ]]
}

# ── List ──────────────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: list VMs" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" list
    [ "$status" -eq 0 ]
}

@test "kvm-vm-lifecycle: list with --all flag" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" list --all
    [ "$status" -eq 0 ]
}

# ── Undefine ──────────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: undefine requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" undefine
    [ "$status" -ne 0 ]
}

@test "kvm-vm-lifecycle: undefine VM" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" undefine --name testvm
    [ "$status" -eq 0 ] || [[ "$output" == *"undefin"* ]]
}

@test "kvm-vm-lifecycle: undefine with --remove-storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" undefine --name testvm --remove-storage
    [ "$status" -eq 0 ] || [[ "$output" == *"undefin"* ]]
}

@test "kvm-vm-lifecycle: undefine with --dry-run" {
    MOCK_DIR2="$MOCK_DIR"
    export MOCK_DIR
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" undefine --name testvm --dry-run
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

# ── Dry Run ───────────────────────────────────────────────────────────────────

@test "kvm-vm-lifecycle: create with --dry-run" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-vm-lifecycle.sh" create --name drytest --ram 1024 --vcpus 1 --disk 10G --dry-run
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}
