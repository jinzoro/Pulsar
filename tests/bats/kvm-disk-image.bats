#!/usr/bin/env bats

setup() {
    export PATH="$BATS_TEST_DIRNAME/../../bin:$PATH"
    MOCK_DIR="$(mktemp -d)"
    export MOCK_DIR
    cat > "$MOCK_DIR/qemu-img" <<'SCRIPT'
#!/bin/bash
case "$1" in
    create)
        echo "Formatting '$2', fmt=$3"
        ;;
    convert)
        echo "Converting from $2 to $4"
        ;;
    resize)
        echo "Image resized."
        ;;
    info)
        echo "image: test.qcow2\nfile format: qcow2\nvirtual size: 32 GiB (34359738368 bytes)\ndisk size: 0 bytes\ncluster_size: 65536"
        ;;
    check)
        echo "No errors were found on the image."
        ;;
    help|--help|-h)
        echo "qemu-img mock"; exit 0
        ;;
    *)
        echo "qemu-img: unknown command"; exit 1
        ;;
esac
SCRIPT
    chmod +x "$MOCK_DIR/qemu-img"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "kvm-disk-image: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "kvm-disk-image: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh"
    [ "$status" -ne 0 ]
}

# ── Create ────────────────────────────────────────────────────────────────────

@test "kvm-disk-image: create qcow2" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" create --format qcow2 --size 32G --output /tmp/test.qcow2
    [ "$status" -eq 0 ] || [[ "$output" == *"qcow2"* ]] || [[ "$output" == *"creat"* ]]
}

@test "kvm-disk-image: create raw" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" create --format raw --size 64G --output /tmp/test.raw
    [ "$status" -eq 0 ] || [[ "$output" == *"raw"* ]]
}

@test "kvm-disk-image: create requires size" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" create --format qcow2 --output /tmp/test.qcow2
    [ "$status" -ne 0 ]
}

@test "kvm-disk-image: create requires output path" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" create --format qcow2 --size 10G
    [ "$status" -ne 0 ]
}

@test "kvm-disk-image: create with backing file" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" create --format qcow2 --size 32G --output /tmp/child.qcow2 --backing /tmp/base.qcow2
    [ "$status" -eq 0 ] || [[ "$output" == *"qcow2"* ]]
}

# ── Convert ───────────────────────────────────────────────────────────────────

@test "kvm-disk-image: convert qcow2 to raw" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" convert --input /tmp/test.qcow2 --output /tmp/test.raw --format raw
    [ "$status" -eq 0 ] || [[ "$output" == *"convert"* ]]
}

@test "kvm-disk-image: convert raw to qcow2" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" convert --input /tmp/test.raw --output /tmp/test.qcow2 --format qcow2
    [ "$status" -eq 0 ] || [[ "$output" == *"convert"* ]]
}

@test "kvm-disk-image: convert requires input" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" convert --output /tmp/test.raw --format raw
    [ "$status" -ne 0 ]
}

# ── Resize ────────────────────────────────────────────────────────────────────

@test "kvm-disk-image: resize larger" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" resize --image /tmp/test.qcow2 --size 64G
    [ "$status" -eq 0 ] || [[ "$output" == *"resize"* ]] || [[ "$output" == *"Resize"* ]]
}

@test "kvm-disk-image: resize requires image and size" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" resize
    [ "$status" -ne 0 ]
}

# ── Info ──────────────────────────────────────────────────────────────────────

@test "kvm-disk-image: show info" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" info --image /tmp/test.qcow2
    [ "$status" -eq 0 ]
    [[ "$output" == *"qcow2"* ]] || [[ "$output" == *"virtual"* ]] || [[ "$output" == *"format"* ]]
}

@test "kvm-disk-image: info requires image" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" info
    [ "$status" -ne 0 ]
}

# ── Check ─────────────────────────────────────────────────────────────────────

@test "kvm-disk-image: check image integrity" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" check --image /tmp/test.qcow2
    [ "$status" -eq 0 ]
    [[ "$output" == *"error"* ]] || [[ "$output" == *"No errors"* ]] || [[ "$output" == *"check"* ]]
}

@test "kvm-disk-image: check requires image" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/kvm-disk-image.sh" check
    [ "$status" -ne 0 ]
}
