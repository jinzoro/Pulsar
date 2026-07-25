# Runbook: Failed Migration

**Severity**: Medium  
**Response Time**: Within 1 hour  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify a Failed Migration

**Symptoms**:
- Migration stuck in "running" state for an extended period
- VM appears on both source and target nodes (dangerous state)
- VM is paused on either source or target node
- Migration task shows error in Proxmox task log
- `qm migrate` returns error

**Detection commands**:
```bash
# Check VM status on both nodes
pmxctl vm list --node=pve1
pmxctl vm list --node=pve2

# Check for stuck migration tasks
ssh pve1 "qm status 100"

# Check Proxmox task log
ssh pve1 "cat /var/log/pve/tasks/active" | grep migrate

# Check if VM is running on both nodes (split-brain state)
ssh pve1 "qm status 100"
ssh pve2 "qm status 100"
```

**Warning**: If a VM appears running on both nodes, IMMEDIATELY stop it on one node. This is a dangerous state that can cause data corruption.

---

## Assessment

### Step 1: Determine Migration Type

```bash
# Was this an online or offline migration?
# Check VM status — if running, it was online migration
ssh pve1 "qm status 100"

# Check if disk copy was involved
ssh pve1 "qm config 100" | grep scsi  # Check disk locations
```

### Step 2: Identify Failure Reason

Common failure reasons and how to identify them:

**Timeout**:
```bash
# Check migration task log for timeout messages
ssh pve1 "cat /var/log/pve/tasks/active" 2>/dev/null
ssh pve1 "journalctl -u pve-migration --since '1 hour ago'"

# Check network throughput during migration
ssh pve1 "iftop -i bond0 -t -s 10"  # or nload, vnstat
```

**CPU Incompatibility**:
```bash
# Check CPU types on source and target
ssh pve1 "cat /proc/cpuinfo | grep 'model name' | head -1"
ssh pve2 "cat /proc/cpuinfo | grep 'model name' | head -1"

# Check VM CPU type setting
ssh pve1 "qm config 100" | grep cpu
```

**Storage Not Shared**:
```bash
# Check where VM disks are located
ssh pve1 "qm config 100" | grep -E '^(scsi|ide|virtio|sata)'

# Check if storage is available on target
ssh pve2 "pvesm status" | grep local-lvm

# Check if storage is shared (NFS, Ceph, etc.)
ssh pve2 "pvesm list local-lvm" 2>/dev/null
```

**Network Issues**:
```bash
# Check migration network configuration
ssh pve1 "cat /etc/pve/data.cfg" 2>/dev/null | grep -i migration

# Test connectivity between nodes on migration network
ssh pve1 "ping -c 5 pve2"
ssh pve1 "iperf3 -c pve2 -t 10"

# Check for packet loss
ssh pve1 "mtr --report pve2"
```

**Insufficient Resources on Target**:
```bash
# Check target node resources
pmxctl node status pve2

# Check available memory/CPU on target
ssh pve2 "free -h"
ssh pve2 "nproc"
ssh pve2 "qm list"
```

### Step 3: Check Migration State

```bash
# On source node
ssh pve1 "qm status 100"
ssh pve1 "ps aux | grep qemu" | grep 100

# On target node
ssh pve2 "qm status 100"
ssh pve2 "ps aux | grep qemu" | grep 100

# Check for zombie processes
ssh pve1 "ps aux | grep defunct" | grep qemu
ssh pve2 "ps aux | grep defunct" | grep qemu
```

---

## Recovery

### Cancel Stuck Migration

```bash
# Cancel via API
ssh pve1 "curl -sk -X DELETE 'https://localhost:8006/api2/json/nodes/pve1/qemu/100/migrate' \
  -H 'Authorization: PMXAPIToken=automation@pam!mytoken=xxxx'"

# Or via CLI
pmx-migration.sh cancel --vmid=100

# Wait for cancellation to complete (may take a few minutes)
sleep 30
ssh pve1 "qm status 100"
```

### Verify VM State After Cancellation

```bash
# Check source node
ssh pve1 "qm status 100"
# Expected: "running" or "stopped" — not "pausing" or "migrating"

# Check target node
ssh pve2 "qm status 100"
# Expected: should not exist, or "stopped"

# If VM is paused on either node
ssh pve1 "qm resume 100"  # Resume if paused
# or
ssh pve1 "qm stop 100"    # Force stop if needed
```

### Restart VM on Source if Needed

```bash
# If VM was stopped during failed migration
ssh pve1 "qm start 100"

# Verify it's running
pmxctl vm status 100
```

### Verify Disk Integrity

```bash
# Check disk images for corruption
ssh pve1 "qm disk check 100" 2>/dev/null

# Verify disk is not locked
ssh pve1 "qm unlock 100" 2>/dev/null

# Check storage for VM 100
ssh pve1 "pvesm list local-lvm" | grep 100
```

### Fix Root Cause and Retry

Based on the identified root cause, apply the appropriate fix before retrying.

---

## Common Issues and Fixes

### CPU Incompatibility

**Problem**: Source and target have different CPU models. VM uses `host-passthrough` which is CPU-specific.

**Fix**: Set a compatible CPU type in VM configuration:
```bash
# Change to a generic CPU type
ssh pve1 "qm set 100 --cpu host"

# Or set specific model that both hosts support
ssh pve1 "qm set 100 --cpu kvm64"

# For online migration with different CPUs, use "host-model"
ssh pve1 "qm set 100 --cpu host-model"
```

**Prevention**: Always use `host-model` instead of `host-passthrough` in multi-node clusters, or ensure all nodes have identical CPUs.

### Storage Not Shared

**Problem**: VM disk is on local storage that doesn't exist on the target node.

**Fix 1 — Move to shared storage first**:
```bash
# Move disk to shared storage (Ceph, NFS, etc.)
ssh pve1 "qm disk move 100 scsi0 --storage ceph-ssd"

# Then retry migration
pmx-migration.sh migrate --vmid=100 --target=pve2 --online
```

**Fix 2 — Offline migration with disk copy**:
```bash
# This stops the VM, copies disk, then starts on target
pmx-migration.sh migrate --vmid=100 --target=pve2
# Without --online, it does offline migration with disk copy
```

**Prevention**: Use shared storage (Ceph, NFS, ZFS replication) for VMs that may be migrated.

### Network Issues

**Problem**: Migration network is slow, congested, or has packet loss.

**Fix 1 — Use dedicated migration network**:
```bash
# Configure dedicated migration network in Proxmox
ssh pve1 "cat >> /etc/pve/data.cfg" <<EOF
migration: secure,type=1
migration_network: 10.0.1.0/24
EOF

# Restart clustering service
ssh pve1 "systemctl restart corosync"
ssh pve2 "systemctl restart corosync"
```

**Fix 2 — Increase migration timeout**:
```bash
# Set longer timeout in Proxmox config
ssh pve1 "cat >> /etc/pve/data.cfg" <<EOF
migration_timeout: 300
EOF
```

**Fix 3 — Throttle migration to avoid saturating network**:
```bash
# Limit bandwidth during migration (in MB/s)
ssh pve1 "qm set 100 --migration_limit 100"
```

### Timeout

**Problem**: Migration takes too long and times out (default: 180 seconds for downtime).

**Fix — Increase max downtime tolerance**:
```bash
# Set longer timeout (in seconds)
ssh pve1 "qm set 100 --migration_downtime 300"

# Or increase overall migration timeout
ssh pve1 "qm migrate 100 pve2 --online --timeout 3600"
```

### Disk Lock Issues

**Problem**: Migration left disk locks in place, preventing further operations.

**Fix**:
```bash
# Check for locks
ssh pve1 "qm unlock 100"

# If that doesn't work, check for orphaned lock files
ssh pve1 "ls -la /var/lock/qemu-server/"
ssh pve1 "rm /var/lock/qemu-server/100.lock"  # Only if VM is confirmed stopped

# Restart QEMU processes if needed
ssh pve1 "qm stop 100"  # Force stop to clear locks
ssh pve1 "qm start 100"
```

---

## Prevention

### 1. Use Shared Storage

Always use shared storage (Ceph, NFS, ZFS replication) for VMs that may be migrated. This enables fast online migration without disk copy.

### 2. Consistent CPU Configuration

Set `cpu: host-model` instead of `cpu: host-passthrough` for VMs in clusters with mixed hardware. This allows the hypervisor to adapt the CPU model to each host.

### 3. Dedicated Migration Network

Configure a dedicated migration network to avoid contention with production traffic:
```yaml
# In Proxmox datacenter configuration
migration: secure, network=10.0.1.0/24
```

### 4. Pre-Migration Checks

Before any migration, verify:
- [ ] Source and target nodes are online
- [ ] Sufficient resources on target (CPU, RAM, disk)
- [ ] Network connectivity between nodes
- [ ] Storage accessibility from both nodes
- [ ] VM is in a consistent state (no disk I/O in progress)

### 5. Monitor Migration Progress

For large VMs, monitor migration progress:
```bash
# Watch migration task
ssh pve1 "qm status 100 --verbose"

# Monitor network usage during migration
ssh pve1 "iftop -i bond0"
```

### 6. Test Migrations

Periodically test migrations to ensure they work:
```bash
# Test with a non-critical VM
pmx-migration.sh migrate --vmid=100 --target=pve2 --online
```
