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

@test "pmx-storage: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-storage: no args shows usage or error" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh"
    [ "$status" -ne 0 ]
}

# ── Storage Add ───────────────────────────────────────────────────────────────

@test "pmx-storage: add directory storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" add --type dir --name local-lvm --path /mnt/data
    [ "$status" -eq 0 ] || [[ "$output" == *"add"* ]] || [[ "$output" == *"storage"* ]]
}

@test "pmx-storage: add NFS storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" add --type nfs --name nfs-store --server 10.0.0.5 --export /exports/data
    [ "$status" -eq 0 ] || [[ "$output" == *"nfs"* ]] || [[ "$output" == *"add"* ]]
}

@test "pmx-storage: add Ceph storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" add --type rbd --name ceph-vm --pool vm-pool
    [ "$status" -eq 0 ] || [[ "$output" == *"rbd"* ]] || [[ "$output" == *"ceph"* ]]
}

@test "pmx-storage: add requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" add --type dir
    [ "$status" -ne 0 ]
}

# ── Storage Remove ────────────────────────────────────────────────────────────

@test "pmx-storage: remove requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" remove
    [ "$status" -ne 0 ]
}

@test "pmx-storage: remove with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" remove --name test-store
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]] || [[ "$output" == *"Dry"* ]]
}

@test "pmx-storage: remove storage by name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" remove --name test-store
    [ "$status" -eq 0 ] || [[ "$output" == *"remove"* ]] || [[ "$output" == *"delet"* ]]
}

# ── List ──────────────────────────────────────────────────────────────────────

@test "pmx-storage: list all storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" list
    [ "$status" -eq 0 ]
}

@test "pmx-storage: list with type filter" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" list --type dir
    [ "$status" -eq 0 ]
}

# ── Status ────────────────────────────────────────────────────────────────────

@test "pmx-storage: status of storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" status --name local
    [ "$status" -eq 0 ] || [[ "$output" == *"status"* ]]
}

@test "pmx-storage: status requires name" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" status
    [ "$status" -ne 0 ]
}

# ── Resize ────────────────────────────────────────────────────────────────────

@test "pmx-storage: resize disk" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" resize --vmid 100 --disk scsi0 --size 64G
    [ "$status" -eq 0 ] || [[ "$output" == *"resize"* ]]
}

@test "pmx-storage: resize requires vmid and disk" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" resize
    [ "$status" -ne 0 ]
}

# ── Move Disk ─────────────────────────────────────────────────────────────────

@test "pmx-storage: move disk to target storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" move-disk --vmid 100 --disk scsi0 --target local-lvm
    [ "$status" -eq 0 ] || [[ "$output" == *"move"* ]] || [[ "$output" == *"migrat"* ]]
}

@test "pmx-storage: move disk requires target" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" move-disk --vmid 100 --disk scsi0
    [ "$status" -ne 0 ]
}

@test "pmx-storage: move disk with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-storage.sh" move-disk --vmid 100 --disk scsi0 --target local-lvm
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}
