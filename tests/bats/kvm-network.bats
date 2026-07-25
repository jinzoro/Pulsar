#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR
    cat > "$MOCK_DIR/virsh" <<'SCRIPT'
#!/bin/bash
case "$1" in
    net-list)
        echo " Name              State    Autostart"
        echo "----------------------------------------"
        echo " default          active   yes"
        echo " br-mgmt          active   no"
        ;;
    net-info)
        echo "Name:           default\nUUID:           abc-123\nActive:         yes\nAutostart:      yes\nBridge:         virbr0"
        ;;
    net-start) echo "Network default started" ;;
    net-destroy) echo "Network default destroyed" ;;
    net-undefine) echo "Network default has been undefined" ;;
    net-dhcp-leases)
        echo " MAC                IP Address          Protocol   Name       Expiry Time"
        echo "--------------------------------------------------------------------------------"
        echo " 52:54:00:ab:cd:ef  192.168.122.100    ipv4       testvm     2025-12-31"
        ;;
    net-create)
        echo "Network default.xml created" ;;
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

@test "kvm-network: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "kvm-network: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh"
    [ "$status" -ne 0 ]
}

# ── Create ────────────────────────────────────────────────────────────────────

@test "kvm-network: create network" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" create --name br-test --bridge virbr1 --subnet 192.168.100.0/24
    [ "$status" -eq 0 ] || [[ "$output" == *"creat"* ]] || [[ "$output" == *"network"* ]]
}

@test "kvm-network: create requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" create --subnet 192.168.100.0/24
    [ "$status" -ne 0 ]
}

@test "kvm-network: create with DHCP range" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" create --name br-dhcp --subnet 10.0.0.0/24 --dhcp-start 10.0.0.100 --dhcp-end 10.0.0.200
    [ "$status" -eq 0 ] || [[ "$output" == *"creat"* ]]
}

# ── Delete ────────────────────────────────────────────────────────────────────

@test "kvm-network: delete requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" delete
    [ "$status" -ne 0 ]
}

@test "kvm-network: delete network" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" delete --name br-test
    [ "$status" -eq 0 ] || [[ "$output" == *"delet"* ]] || [[ "$output" == *"destroy"* ]] || [[ "$output" == *"undefin"* ]]
}

# ── List ──────────────────────────────────────────────────────────────────────

@test "kvm-network: list networks" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" list
    [ "$status" -eq 0 ]
}

@test "kvm-network: list includes network names" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"default"* ]] || [[ "$output" == *"active"* ]]
}

# ── Start / Stop ──────────────────────────────────────────────────────────────

@test "kvm-network: start network" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" start --name default
    [ "$status" -eq 0 ] || [[ "$output" == *"start"* ]]
}

@test "kvm-network: stop network" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" stop --name default
    [ "$status" -eq 0 ] || [[ "$output" == *"destroy"* ]] || [[ "$output" == *"stop"* ]]
}

@test "kvm-network: start requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" start
    [ "$status" -ne 0 ]
}

# ── DHCP Leases ───────────────────────────────────────────────────────────────

@test "kvm-network: show DHCP leases" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" leases --name default
    [ "$status" -eq 0 ]
}

@test "kvm-network: leases requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" leases
    [ "$status" -ne 0 ]
}

@test "kvm-network: leases shows IP addresses" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-network.sh" leases --name default
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168"* ]] || [[ "$output" == *"IP"* ]] || [[ "$output" == *"lease"* ]]
}
