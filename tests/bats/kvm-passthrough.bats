#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR
    cat > "$MOCK_DIR/lspci" <<'SCRIPT'
#!/bin/bash
case "$*" in
    *-nn*) echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA102 [GeForce RTX 3090] [10de:2204] (rev a1)" ;;
    *) echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA102 [GeForce RTX 3090] (rev a1)" ;;
esac
SCRIPT
    cat > "$MOCK_DIR/setpci" <<'SCRIPT'
#!/bin/bash
echo "00:01.0"
SCRIPT
    cat > "$MOCK_DIR/dpkg" <<'SCRIPT'
#!/bin/bash
case "$*" in
    *--status*) echo "uninst not installed" ;;
    *) echo "dpkg mock" ;;
esac
SCRIPT
    chmod +x "$MOCK_DIR/lspci" "$MOCK_DIR/setpci" "$MOCK_DIR/dpkg"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "kvm-passthrough: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "kvm-passthrough: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh"
    [ "$status" -ne 0 ]
}

# ── Detect PCI Devices ────────────────────────────────────────────────────────

@test "kvm-passthrough: detect PCI devices" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" detect
    [ "$status" -eq 0 ]
}

@test "kvm-passthrough: detect shows device info" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" detect
    [ "$status" -eq 0 ]
    [[ "$output" == *"01:00"* ]] || [[ "$output" == *"NVIDIA"* ]] || [[ "$output" == *"VGA"* ]]
}

@test "kvm-passthrough: detect with filter" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" detect --filter "VGA"
    [ "$status" -eq 0 ]
}

@test "kvm-passthrough: detect GPU devices" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" detect --class 0300
    [ "$status" -eq 0 ]
}

# ── IOMMU Groups ──────────────────────────────────────────────────────────────

@test "kvm-passthrough: list IOMMU groups" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" iommu
    [ "$status" -eq 0 ]
}

@test "kvm-passthrough: IOMMU groups for device" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" iommu --device 01:00.0
    [ "$status" -eq 0 ]
}

@test "kvm-passthrough: IOMMU groups shows group IDs" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" iommu
    [ "$status" -eq 0 ]
    [[ "$output" == *"group"* ]] || [[ "$output" == *"IOMMU"* ]] || [[ "$output" == *"01:00"* ]]
}

# ── Bind / Unbind ─────────────────────────────────────────────────────────────

@test "kvm-passthrough: bind device to vfio-pci" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" bind --device 01:00.0
    [ "$status" -eq 0 ] || [[ "$output" == *"bind"* ]] || [[ "$output" == *"vfio"* ]]
}

@test "kvm-passthrough: bind requires device" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" bind
    [ "$status" -ne 0 ]
}

@test "kvm-passthrough: unbind device from vfio-pci" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" unbind --device 01:00.0
    [ "$status" -eq 0 ] || [[ "$output" == *"unbind"* ]] || [[ "$output" == *"reset"* ]]
}

@test "kvm-passthrough: unbind requires device" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" unbind
    [ "$status" -ne 0 ]
}

@test "kvm-passthrough: bind with --dry-run" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-passthrough.sh" bind --device 01:00.0 --dry-run
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}
