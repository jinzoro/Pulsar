# Runbook: Backup Recovery

**Severity**: High  
**Response Time**: Within 1 hour  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify Backup Issues

**Symptoms**:
- Backup job fails or reports errors
- VM is corrupted or deleted and needs restoration
- Data loss detected in a VM
- Storage containing backups is damaged
- Need to recover a VM to a different node or storage

**Detection commands**:
```bash
# Check backup job status
pmx-backup-restore.sh list --storage=backup-nas

# Check PBS backup status (if using PBS)
pmx-pbs-integration.sh list-backups --datastore=backup

# Check for failed backup tasks
ssh pve1 "cat /var/log/pve/tasks/active" | grep backup

# Check backup storage availability
ssh pve1 "pvesm status" | grep backup
```

---

## Verify Backup Integrity

### Check Backup Files

```bash
# List backups with metadata
pmx-backup-restore.sh list --storage=backup-nas

# Check file sizes (unexpected size = possible corruption)
ssh pve1 "ls -lh /var/lib/vz/dump/vzdump-qemu-*.vma.zst"

# Verify checksums (if stored)
ssh pve1 "md5sum -c /var/lib/vz/dump/vzdump-qemu-100-*.md5"
```

### Test Backup Mount

```bash
# Extract and test backup integrity without restoring
ssh pve1 "vzdump --verify /var/lib/vz/dump/vzdump-qemu-100-2026_01_01-02_00_00.vma.zst"

# For PBS backups
pmx-pbs-integration.sh verify --datastore=backup --snapshot=2026-01-01T02:00:00Z
```

---

## Restore from Local vzdump

### Restore to Same Node, Same Storage

```bash
# Restore VM 100 from its most recent backup
pmx-backup-restore.sh restore \
  --vmid=100 \
  --storage=local-lvm \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst

# Verify the restored VM
pmxctl vm status 100
ssh pve1 "qm config 100"
```

### Restore to Different VMID

```bash
# Restore as a new VM (VMID 200)
pmx-backup-restore.sh restore \
  --vmid=100 \
  --storage=local-lvm \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst \
  --target-vmid=200

# Verify the new VM
pmxctl vm status 200
ssh pve1 "qm config 200"
```

---

## Restore from PBS

### List Available PBS Backups

```bash
# List all backups in PBS datastore
pmx-pbs-integration.sh list-backups --datastore=backup

# List backups for specific VM
pmx-pbs-integration.sh list-backups --datastore=backup --vmid=100

# Get snapshot timestamp
pmx-pbs-integration.sh list-backups --datastore=backup --vmid=100 | tail -1
```

### Restore from PBS

```bash
# Restore from PBS snapshot
pmx-pbs-integration.sh restore \
  --vmid=100 \
  --datastore=backup \
  --snapshot=2026-01-01T02:00:00Z \
  --target-node=pve2 \
  --target-storage=local-lvm

# Verify restored VM
pmxctl vm status 100
```

### Restore Specific Disk from PBS

```bash
# Restore only specific disks from PBS backup
pmx-pbs-integration.sh restore \
  --vmid=100 \
  --datastore=backup \
  --snapshot=2026-01-01T02:00:00Z \
  --disk=scsi0 \
  --target-storage=ceph-ssd
```

---

## Restore to Different Node/Storage

### Restore to Different Node

```bash
# Restore VM 100 from backup on pve1 to pve2
pmx-backup-restore.sh restore \
  --vmid=100 \
  --storage=backup-nas \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst \
  --target-node=pve2

# Verify on target node
pmxctl vm list --node=pve2
```

### Restore to Different Storage

```bash
# Restore from backup-nas to ceph-ssd storage
pmx-backup-restore.sh restore \
  --vmid=100 \
  --storage=backup-nas \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst \
  --target-storage=ceph-ssd
```

### Restore Both Different Node and Storage

```bash
pmx-backup-restore.sh restore \
  --vmid=100 \
  --storage=backup-nas \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst \
  --target-node=pve2 \
  --target-storage=ceph-ssd \
  --target-vmid=100
```

---

## Bare-Metal Recovery

### When All VMs Are Lost

If the entire Proxmox installation is lost but backups exist on external storage:

#### 1. Install Proxmox VE

Install Proxmox VE on new hardware from the official ISO.

#### 2. Join Cluster (if applicable)

```bash
# On the new node, join the existing cluster
pmx-cluster.sh join \
  --node=pve-new \
  --existing-host=pve2.example.com \
  --existing-token="automation@pam!mytoken=xxxx"
```

#### 3. Import Backup Storage

```bash
# Add the backup storage to the new node
pmx-storage.sh add --node=pve-new --name=backup-nas --type=nfs \
  --server=10.0.0.50 --export=/volume1/backups --content=backup
```

#### 4. Restore VMs

```bash
# List available backups
pmx-backup-restore.sh list --storage=backup-nas

# Restore each VM
pmx-backup-restore.sh restore --vmid=100 --storage=backup-nas \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst

pmx-backup-restore.sh restore --vmid=101 --storage=backup-nas \
  --backup-id=vzdump-qemu-101-2026_01_01-02_00_00.vma.zst

# Continue for all VMs...
```

#### 5. Verify All Restored VMs

```bash
# Check all VMs are restored and startable
pmxctl vm list

# Start each VM
for vmid in 100 101 102; do
  pmxctl vm start $vmid
  sleep 5
  pmxctl vm status $vmid
done

# Verify network connectivity
for vmid in 100 101 102; do
  ip=$(ssh pve-new "qm guest cmd $vmid get-network-ifaces" 2>/dev/null | jq -r '.result[0].ip-addresses[0].ip-address')
  echo "VM $vmid IP: $ip"
done
```

#### 6. Reconfigure HA and Backup

```bash
# Re-add VMs to HA groups
pmx-ha.sh resource-add --sid=vm:100 --group=hagroup1 --type=vm --state=started

# Re-establish backup schedules
pmx-backup-restore.sh schedule --vmid=100 --cron="0 2 * * *" --storage=backup-nas
```

---

## Verify Restored VM

### Post-Restore Verification Checklist

```bash
# 1. VM starts successfully
pmxctl vm start 100
sleep 10
pmxctl vm status 100
# Should show: status=running

# 2. Guest OS boots
ssh pve1 "qm guest cmd 100 ping-get-ip"  # If QEMU guest agent is installed

# 3. Network connectivity
ssh pve1 "qm guest cmd 100 get-network-ifaces" | jq .

# 4. Disk mounts correctly
ssh pve1 "qm guest fsinfo 100" | jq '.result[] | select(.type=="ext4" or .type=="xfs")'

# 5. Services running (if guest agent installed)
ssh pve1 "qm guest cmd 100 fsfreeze-status"

# 6. Application accessible
curl -sk https://<vm-ip>  # Or appropriate port

# 7. Data integrity
# Compare critical files, databases, etc. with known good state
```

### If VM Doesn't Boot

```bash
# Check console output
ssh pve1 "qm terminal 100 --stdio"

# Check if VM is in rescue mode
# Mount filesystem manually if needed
ssh pve1 "qm set 100 --ide2 local:iso/ubuntu-rescue.iso,media=cdrom"
ssh pve1 "qm start 100"

# Boot from rescue ISO and check filesystem
ssh pve1 "qm guest cmd 100 fsfreeze-status"
```

---

## Prevention

### 1. Regular Backup Verification

```bash
# Set up automated backup verification
pmx-backup-restore.sh verify --vmid=100 \
  --backup-id=vzdump-qemu-100-$(date +%Y_%m_%d)-02_00_00.vma.zst
```

### 2. Offsite Backup Copies

Maintain backups in at least two locations:

```bash
# Primary: local NAS
pmx-backup-restore.sh backup --vmid=100 --storage=backup-nas

# Secondary: PBS on separate server
pmx-pbs-integration.sh backup --vmid=100 --datastore=offsite-backup

# Tertiary: remote PBS (geographically separate)
pmx-pbs-integration.sh backup --vmid=100 --datastore=remote-pbs
```

### 3. Documented Recovery Procedure

Keep a documented list of all VMs and their restoration priority:

| Priority | VMID | Name | Description | Backup Location |
|----------|------|------|-------------|-----------------|
| P1 | 100 | dc01 | Domain controller | backup-nas, pbs |
| P1 | 101 | db01 | Primary database | backup-nas, pbs |
| P2 | 102 | web01 | Web server | backup-nas |
| P3 | 103 | dev01 | Development VM | backup-nas |

### 4. Test Recovery

Periodically perform test recoveries:

```bash
# Restore to a test VMID
pmx-backup-restore.sh restore --vmid=100 --storage=backup-nas \
  --backup-id=<latest-backup> --target-vmid=999

# Verify it works
pmxctl vm start 999
# Run verification checks

# Clean up test VM
pmx-vm-lifecycle.sh delete --vmid=999 --purge
```

### 5. Monitor Backup Health

```bash
# Check that backups are being created
pmx-backup-restore.sh list --storage=backup-nas | wc -l

# Alert if no backups in last 24 hours
find /var/lib/vz/dump/ -name "vzdump-qemu-100-*" -mtime -1 | wc -l

# Run health check which includes backup status
pmx-health-check.sh --nodes=pve1
```
