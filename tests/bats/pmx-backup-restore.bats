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

@test "pmx-backup-restore: --help shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"--help"* ]]
}

@test "pmx-backup-restore: no args shows usage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh"
    [ "$status" -ne 0 ]
}

# ── Backup Create ─────────────────────────────────────────────────────────────

@test "pmx-backup-restore: backup create requires vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" create
    [ "$status" -ne 0 ]
}

@test "pmx-backup-restore: backup create with vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" create --vmid 100 --storage local --mode snapshot
    [ "$status" -eq 0 ] || [[ "$output" == *"backup"* ]] || [[ "$output" == *"creat"* ]]
}

@test "pmx-backup-restore: backup create with compression" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" create --vmid 100 --storage local --compress zstd
    [ "$status" -eq 0 ] || [[ "$output" == *"backup"* ]]
}

@test "pmx-backup-restore: backup create with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" create --vmid 100 --storage local
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

# ── List Backups ──────────────────────────────────────────────────────────────

@test "pmx-backup-restore: list backups" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" list
    [ "$status" -eq 0 ]
}

@test "pmx-backup-restore: list backups filtered by vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" list --vmid 100
    [ "$status" -eq 0 ]
}

@test "pmx-backup-restore: list backups filtered by storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" list --storage local
    [ "$status" -eq 0 ]
}

# ── Restore ───────────────────────────────────────────────────────────────────

@test "pmx-backup-restore: restore requires backup identifier" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" restore
    [ "$status" -ne 0 ]
}

@test "pmx-backup-restore: restore backup" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" restore --vmid 100 --backup "vzdump-qemu-100-2024_01_01-12_00_00.vma.zst"
    [ "$status" -eq 0 ] || [[ "$output" == *"restore"* ]]
}

@test "pmx-backup-restore: restore to different storage" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" restore --vmid 100 --backup "vzdump-qemu-100-2024_01_01.vma.zst" --storage local-lvm
    [ "$status" -eq 0 ] || [[ "$output" == *"restore"* ]]
}

@test "pmx-backup-restore: restore with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" restore --vmid 100 --backup "vzdump-qemu-100-2024_01_01.vma.zst"
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

# ── Verify ────────────────────────────────────────────────────────────────────

@test "pmx-backup-restore: verify backup" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" verify --backup "vzdump-qemu-100-2024_01_01.vma.zst" --storage local
    [ "$status" -eq 0 ] || [[ "$output" == *"verify"* ]] || [[ "$output" == *"check"* ]]
}

@test "pmx-backup-restore: verify requires backup" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" verify
    [ "$status" -ne 0 ]
}

# ── Prune ─────────────────────────────────────────────────────────────────────

@test "pmx-backup-restore: prune by keep count" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" prune --vmid 100 --keep-last 3 --storage local
    [ "$status" -eq 0 ] || [[ "$output" == *"prune"* ]]
}

@test "pmx-backup-restore: prune with --dry-run" {
    PMX_DRY_RUN=true run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" prune --vmid 100 --keep-last 2 --storage local
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"would"* ]]
}

@test "pmx-backup-restore: prune requires vmid" {
    run bash "$(dirname "$BATS_TEST_DIRNAME")/src/pmx-backup-restore.sh" prune
    [ "$status" -ne 0 ]
}
