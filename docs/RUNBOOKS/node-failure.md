# Runbook: Node Failure

**Severity**: Critical  
**Response Time**: Immediate  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify a Failed Node

**Symptoms**:
- Node appears "offline" in Proxmox web UI (Datacenter → Summary)
- `pmxctl node status <node>` returns connection error
- `pmx-health-check.sh` reports node unreachable
- HA failover events in cluster log
- VMs on the failed node become unreachable

**Detection commands**:
```bash
# Check cluster status
pmxctl cluster status
pmx-cluster.sh status

# Check node from CLI
pmxctl node status pve1
ping -c 3 pve1

# Check via health check
pmx-health-check.sh --nodes=pve1,pve2,pve3

# Check HA status
pmxctl ha resources
```

**Automated detection** (if monitoring is configured):
- `pmx_alerting.py` evaluates thresholds and sends alerts via configured channels
- Check Slack, Telegram, email, or ntfy for cluster alerts

---

## Assessment

### Step 1: Check HA Status

```bash
# View HA resources and their current state
pmxctl ha resources
pmx-ha.sh resources --verbose

# Check if failover has occurred
# Look for resources in "error" or "fencing" state
```

**Expected behavior**: HA should automatically failover VMs to surviving nodes. If HA is configured, VMs should already be running on another node.

### Step 2: Check VM Status

```bash
# List all VMs across all nodes
pmxctl vm list

# Check specific VMs that were on the failed node
pmxctl vm status 100
pmxctl vm status 101

# Check if VMs are in "paused" or "stopped" state
```

### Step 3: Check Storage Status

```bash
# Check storage availability across nodes
pmx-storage.sh list --node=pve2
pmx-storage.sh status --node=pve2

# If using Ceph, check health
pmx-ceph.sh status --node=pve2

# If using ZFS replication, check replication status
pmx-zfs.sh list --node=pve2
```

### Step 4: Assess Network Impact

```bash
# Check if cluster network is still functional
pmx-cluster.sh quorum

# Check corosync status
ssh pve2 "corosync-cfgtool -s"
ssh pve2 "corosync-cmapctl | grep members"

# Check if remaining nodes can communicate
ssh pve2 "ping -c 3 pve3"
```

---

## Immediate Actions

### Step 1: Isolate the Failed Node

If the node is partially functional (flapping, causing split-brain risk):

```bash
# If the node is reachable but misbehaving, put it in maintenance
pmx-node-maintenance.sh enter --node=pve1

# If the node is completely unreachable, fence it
# This is handled automatically by HA if watchdog/fencing is configured
```

### Step 2: Check Physical/Remote Access

```bash
# Try IPMI/BMC access
ipmitool -I lanplus -H 10.0.0.101 -U admin -P password power status

# Check if node responds to ping
ping -c 5 10.0.0.101

# Try SSH
ssh -o ConnectTimeout=5 root@10.0.0.101 "uptime"

# Check Proxmox web UI
curl -sk https://10.0.0.101:8006 | head -5
```

### Step 3: Verify Cluster Quorum

```bash
# On a surviving node
ssh pve2 "corosync-cfgtool -s"
ssh pve2 "pcs status"  # if using pcs, otherwise corosync-cfgtool

# Check quorum votes
# Expected: at least (total_nodes / 2) + 1 votes
# With 3 nodes, need 2 votes to maintain quorum
```

---

## Recovery

### Scenario A: Node Comes Back

If the node hardware is functional and the node returns:

#### 1. Verify Node Health

```bash
# Check node status
pmxctl node status pve1

# Check system resources on the recovered node
ssh pve1 "uptime"
ssh pve1 "free -h"
ssh pve1 "df -h"
```

#### 2. Check and Re-enable HA

```bash
# Verify HA resources are healthy
pmxctl ha resources

# If resources are in error state, restart HA agent
ssh pve1 "systemctl restart pve-ha-lcrm"

# Verify VMs are running correctly
pmxctl vm list --node pve1
```

#### 3. Check Data Integrity

```bash
# Check local storage integrity
ssh pve1 "pvesm status"

# If using Ceph, check OSD status
pmx-ceph.sh osd-list --node=pve1

# If using ZFS, check pool status
pmx-zfs.sh list --node=pve1
ssh pve1 "zpool status"

# Verify no data corruption on VM disks
# (check QEMU image integrity)
ssh pve1 "for vmid in $(qm list | awk 'NR>1{print $1}'); do echo \"VM $vmid\"; qm disk check $vmid 2>/dev/null; done"
```

#### 4. Return to Service

```bash
# Exit maintenance mode if applicable
pmx-node-maintenance.sh exit --node=pve1

# Verify cluster is fully healthy
pmx-health-check.sh --nodes=pve1,pve2,pve3
```

### Scenario B: Node is Dead (Hardware Failure)

If the node cannot be recovered:

#### 1. Fence the Node

```bash
# Fence via IPMI if available
ipmitool -I lanplus -H 10.0.0.101 -U admin -P password power off

# Or remove from cluster if IPMI is unavailable
# WARNING: This is destructive — only do this if you're certain the node is dead
ssh pve2 "ha-manager crmigrate <sid>"  # manually migrate any stuck resources
```

#### 2. Remove Node from Cluster

```bash
# Remove the dead node from cluster configuration
ssh pve2 "corosync-cfgtool --remove-node pve1"

# Remove from corosync.conf
ssh pve2 "vim /etc/pve/corosync.conf"  # Remove the node entry
ssh pve2 "cp /etc/pve/corosync.conf /etc/corosync/corosync.conf"
ssh pve2 "systemctl restart corosync"

# Verify remaining cluster
pmx-cluster.sh status
pmx-cluster.sh quorum
```

#### 3. Migrate VMs from Dead Node

```bash
# List VMs that were on the dead node (from web UI or backup)
# These VMs need to be restored from backup

# Check available backups
pmx-backup-restore.sh list --storage=backup-nas

# Restore VMs to a healthy node
pmx-backup-restore.sh restore --vmid=100 --storage=backup-nas \
  --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst \
  --target-node=pve2
```

#### 4. Replace Hardware and Rejoin

1. Install Proxmox VE on new hardware
2. Configure network (same IPs as old node or update cluster config)
3. Join the cluster:

```bash
# On the new node
pmx-cluster.sh join \
  --node=pve1-new \
  --existing-host=pve2.example.com \
  --existing-token="automation@pam!mytoken=xxxx" \
  --ring0=10.0.0.101 \
  --ring1=10.0.1.101
```

4. Configure storage on the new node
5. Re-add to HA groups if needed

---

## Verification Checklist

- [ ] All nodes in cluster are online and quorate
- [ ] All VMs are running on their expected nodes
- [ ] No VMs in "error" or "paused" state
- [ ] All storage pools are accessible from all nodes
- [ ] Ceph health is `HEALTH_OK` (if applicable)
- [ ] ZFS pools are `ONLINE` (if applicable)
- [ ] Network connectivity between all nodes verified
- [ ] HA groups and resources are correctly configured
- [ ] Backup schedules are active
- [ ] Monitoring/alerting is functioning
- [ ] No replication errors in logs

---

## Prevention Measures

1. **Enable HA for critical VMs**: Ensure all production VMs are in an HA group.
2. **Configure fencing**: Set up IPMI/BMC fencing so HA can properly fence failed nodes.
3. **Redundant network**: Use multiple network rings for corosync (corosync.conf ring0 and ring1).
4. **Regular backups**: Ensure backups run daily with offsite copies.
5. **Hardware monitoring**: Use IPMI sensors, SMART monitoring, and hardware vendor tools to predict failures.
6. **UPS**: Protect against power failures that can corrupt state.
7. **Test failover**: Periodically test HA failover in a maintenance window.
8. **Document hardware**: Keep a record of hardware specs, IPs, and BMC credentials for each node.
