# Runbook: Cluster Split-Brain

**Severity**: Critical  
**Response Time**: Immediate  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify Split-Brain

**Symptoms**:
- Multiple nodes claim to be the cluster master
- Quorum is lost (majority of votes unavailable)
- `corosync-cfgtool -s` shows different views on different nodes
- VMs are running on multiple nodes with the same VMID
- API returns different cluster states from different nodes
- Fence devices are not working, nodes are not being fenced

**Detection commands**:

```bash
# Check quorum on each node
ssh pve1 "corosync-cfgtool -s"
ssh pve2 "corosync-cfgtool -s"
ssh pve3 "corosync-cfgtool -s"

# Check cluster status from each node
ssh pve1 "corosync-cmapctl | grep -E 'nodelist\.node\..*\.online'"
ssh pve2 "corosync-cmapctl | grep -E 'nodelist\.node\..*\.online'"

# Check who thinks they are master
ssh pve1 "ha-manager status" 2>/dev/null
ssh pve2 "ha-manager status" 2>/dev/null

# Check fencing status
ssh pve1 "ha-manager fencing" 2>/dev/null

# Quick cluster health
pmx-cluster.sh status
pmx-cluster.sh quorum
```

**Critical indicator**: If `corosync-cfgtool -s` shows different `Ring ID` or different member lists on different nodes, split-brain has occurred.

---

## Immediate Actions

### Step 1: Stop All Fencing Operations

If fencing is in progress but not completing:

```bash
# Stop HA manager to prevent further fencing attempts
ssh pve1 "systemctl stop pve-ha-lcrm"
ssh pve2 "systemctl stop pve-ha-lcrm"

# Wait for any in-progress fencing to complete or timeout
sleep 30
```

### Step 2: Identify Which Partition Has Quorum

```bash
# Check which nodes have quorum
for node in pve1 pve2 pve3; do
  echo "=== $node ==="
  ssh $node "corosync-cfgtool -s" 2>/dev/null || echo "UNREACHABLE"
  ssh $node "corosync-quorumtool -s" 2>/dev/null || echo "NO QUORUM TOOL"
done
```

**Understanding quorum**:
- 3-node cluster: needs 2 votes for quorum
- 5-node cluster: needs 3 votes for quorum
- If a partition has majority, it retains quorum
- The minority partition loses quorum and should fence itself

### Step 3: Determine Network Partition Cause

```bash
# Check network connectivity between all nodes
for src in pve1 pve2 pve3; do
  for dst in pve1 pve2 pve3; do
    [ "$src" = "$dst" ] && continue
    echo -n "$src -> $dst: "
    ssh $src "ping -c 2 -W 2 $dst" 2>/dev/null | tail -1
  done
done

# Check cluster network specifically (corosync ring)
ssh pve1 "corosync-cfgtool -s | grep ring"
ssh pve2 "corosync-cfgtool -s | grep ring"

# Check for network interface issues
ssh pve1 "ip -s link show" | grep -E "errors|dropped"
ssh pve2 "ip -s link show" | grep -E "errors|dropped"

# Check firewall rules that might block corosync traffic
ssh pve1 "iptables -L -n | grep -E '5405|5404'"  # Corosync ports
```

### Step 4: Isolate Affected Nodes

If you cannot determine the correct partition, isolate all nodes to prevent data corruption:

```bash
# Disable corosync on all nodes
ssh pve1 "systemctl stop corosync"
ssh pve2 "systemctl stop corosync"
ssh pve3 "systemctl stop corosync"

# Stop all VMs to prevent split-brain data corruption
ssh pve1 "qm stop $(qm list | awk 'NR>1{print $1}')"
ssh pve2 "qm stop $(qm list | awk 'NR>1{print $1}')"

# Stop HA manager
ssh pve1 "systemctl stop pve-ha-lcrm"
ssh pve2 "systemctl stop pve-ha-lcrm"
ssh pve3 "systemctl stop pve-ha-lcrm"
```

**WARNING**: Only do this if you are certain split-brain has occurred and you cannot determine which partition is correct. This stops all VMs.

---

## Recovery

### Step 1: Identify Correct Partition

The correct partition is the one that:
1. Has quorum (majority of nodes)
2. Has the most up-to-date data
3. Can reach the majority of cluster resources

```bash
# Check which nodes see the most recent cluster config
ssh pve1 "cat /etc/pve/corosync.conf" | head -20
ssh pve2 "cat /etc/pve/corosync.conf" | head -20

# Check which nodes have the latest VM configurations
ssh pve1 "ls -lt /etc/pve/qemu-server/" | head -5
ssh pve2 "ls -lt /etc/pve/qemu-server/" | head -5

# The partition with the latest configs and quorum is correct
```

### Step 2: Fence Nodes in Minority Partition

Nodes in the minority partition must be fenced (powered off) to prevent data corruption.

```bash
# Fence via IPMI/BMC
ipmitool -I lanplus -H 10.0.0.103 -U admin -P password power off  # pve3

# Or via Proxmox fencing
ssh pve1 "ha-manager fence node pve3" 2>/dev/null

# Verify the node is off
ipmitool -I lanplus -H 10.0.0.103 -U admin -P password power status
```

### Step 3: Rebuild Cluster if Needed

If the cluster configuration is corrupted:

```bash
# On the healthy node(s), rebuild corosync.conf
ssh pve1 "cat /etc/pve/corosync.conf"

# Remove the failed node from corosync.conf
ssh pve1 "vim /etc/pve/corosync.conf"  # Remove the node entry

# Copy updated config to all remaining nodes
ssh pve1 "cp /etc/pve/corosync.conf /etc/corosync/corosync.conf"
ssh pve2 "cp /etc/pve/corosync.conf /etc/corosync/corosync.conf"

# Restart corosync on remaining nodes
ssh pve1 "systemctl restart corosync"
ssh pve2 "systemctl restart corosync"

# Verify cluster is healthy
ssh pve1 "corosync-cfgtool -s"
ssh pve1 "corosync-quorumtool -s"
pmx-cluster.sh status
```

### Step 4: Re-add Fenced Nodes

Once the minority node(s) are back and the network issue is resolved:

```bash
# On the recovered node, rejoin the cluster
pmx-cluster.sh join \
  --node=pve3-recovered \
  --existing-host=pve1.example.com \
  --existing-token="automation@pam!mytoken=xxxx"

# Verify it joined successfully
pmx-cluster.sh nodes
pmx-cluster.sh quorum
```

### Step 5: Verify Data Consistency

```bash
# Check that all VM configurations are consistent
for vmid in $(ssh pve1 "qm list | awk 'NR>1{print $1}'"); do
  echo "=== VM $vmid ==="
  ssh pve1 "qm config $vmid" > /tmp/vm-config-pve1.txt
  ssh pve2 "qm config $vmid" > /tmp/vm-config-pve2.txt 2>/dev/null
  diff /tmp/vm-config-pve1.txt /tmp/vm-config-pve2.txt && echo "CONFIGS MATCH" || echo "CONFIGS DIFFER"
done

# Check storage consistency
ssh pve1 "pvesm status"
ssh pve2 "pvesm status"

# Check Ceph health (if using Ceph)
pmx-ceph.sh status --node=pve1

# Run health check
pmx-health-check.sh --nodes=pve1,pve2,pve3
```

---

## Prevention

### 1. Redundant Corosync Rings

Configure two corosync rings on separate networks:

```bash
# /etc/pve/corosync.conf
nodelist {
  node {
    ring0_addr: 10.0.0.1    # Primary cluster network
    ring1_addr: 10.0.1.1    # Secondary cluster network
    name: pve1
    nodeid: 1
  }
  node {
    ring0_addr: 10.0.0.2
    ring1_addr: 10.0.1.2
    name: pve2
    nodeid: 2
  }
  node {
    ring0_addr: 10.0.0.3
    ring1_addr: 10.0.1.3
    name: pve3
    nodeid: 3
  }
}
```

This ensures that a single network failure cannot cause split-brain.

### 2. Proper Fencing Configuration

Enable and test fencing:

```bash
# Check fencing configuration
ssh pve1 "ha-manager config" 2>/dev/null

# Configure IPMI fencing
ssh pve1 "cat >> /etc/pve/data.cfg" <<EOF
fencing: watchdog
watchdog: iTCO_watcher
EOF

# Test fencing
ssh pve1 "ha-manager fence node pve3"
```

### 3. Monitor Network Partitions

```bash
# Set up network monitoring
# Alert on packet loss > 0.1%
# Alert on latency > 5ms between cluster nodes
# Alert if corosync ring status changes

# Check corosync ring status
ssh pve1 "corosync-cfgtool -s"
ssh pve1 "corosync-cfgtool -r"  # Reset ring status

# Monitor with the health checker
pmx-health-check.sh --nodes=pve1,pve2,pve3
```

### 4. Keep Cluster Small

Split-brain risk increases with cluster size:
- 3 nodes: Can lose 1 node (quorum = 2)
- 5 nodes: Can lose 2 nodes (quorum = 3)
- 7+ nodes: Consider separate failure domains

### 5. Avoid Network Dependencies

- Don't put corosync on the same network as VM traffic
- Use dedicated VLANs for cluster communication
- Ensure switch redundancy (avoid single switch for cluster network)
- Consider using bonded NICs for corosync

### 6. Regular Cluster Health Checks

```bash
# Schedule regular health checks
pmx-health-check.sh --nodes=pve1,pve2,pve3

# Check corosync configuration
ssh pve1 "corosync-cfgtool -s"
ssh pve1 "corosync-quorumtool -s"

# Check HA manager status
ssh pve1 "ha-manager status"
```

### 7. Document Cluster Topology

Maintain a clear record of:
- Node names, IPs, and BMC addresses
- Corosync ring addresses (ring0 and ring1)
- Network topology (which switch, which VLAN)
- Fencing device configuration
- Quorum vote assignments

### 8. Test Failure Scenarios

Periodically test in a maintenance window:
1. Simulate network partition (iptables rules)
2. Fence a node and verify HA failover
3. Kill corosync on a node and verify recovery
4. Test that VMs continue running on surviving nodes
