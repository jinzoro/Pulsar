# Runbook: Ceph Recovery

**Severity**: Critical  
**Response Time**: Immediate  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify Ceph Issues

**Symptoms**:
- `ceph status` shows `HEALTH_WARN` or `HEALTH_ERR`
- VM disk I/O errors or pauses
- Slow performance on Ceph-backed storage
- OSDs down or degraded
- PGs in `degraded` or `undersized` state

**Detection commands**:
```bash
# Overall Ceph status
pmx-ceph.sh status --node=pve1
pmx-ceph.sh health --node=pve1

# Direct Ceph CLI (run on any monitor node)
ssh pve1 "ceph -s"
ssh pve1 "ceph health detail"
ssh pve1 "ceph osd tree"
ssh pve1 "ceph pg stat"
```

---

## Health Check

### Step 1: Overall Status

```bash
# Full Ceph status
ssh pve1 "ceph -s"

# Health details
ssh pve1 "ceph health detail"

# Check for specific issues
ssh pve1 "ceph health detail --format json" | jq .
```

**Status meanings**:
- `HEALTH_OK` — All good, no action needed
- `HEALTH_WARN` — Warning, investigate but not immediately dangerous
- `HEALTH_ERR` — Critical, immediate action required

### Step 2: OSD Status

```bash
# List all OSDs and their state
pmx-ceph.sh osd-list --node=pve1

# Direct Ceph CLI
ssh pve1 "ceph osd tree"
ssh pve1 "ceph osd stat"
ssh pve1 "ceph osd dump | grep -E 'osd\.[0-9]'"

# Check OSD utilization
ssh pve1 "ceph osd df"
```

### Step 3: PG Status

```bash
# Check PG states
ssh pve1 "ceph pg stat"
ssh pve1 "ceph pg dump --format json" | jq '.pg_stats | length'

# Find PGs in problematic states
ssh pve1 "ceph pg dump | grep -E 'degraded|undersized|peering|inconsistent'"
```

### Step 4: Pool Status

```bash
# List pools and their status
ssh pve1 "ceph osd pool ls detail"

# Check pool statistics
ssh pve1 "ceph osd pool stats"
```

---

## OSD Down

### Step 1: Identify the Failed OSD

```bash
# Find which OSDs are down
ssh pve1 "ceph osd tree" | grep -E "down|out"

# Get details about the specific OSD
ssh pve1 "ceph osd find 0"  # Replace 0 with OSD ID

# Check OSD logs
ssh pve1 "journalctl -u ceph-osd@0 --since '1 hour ago'"
```

### Step 2: Check the Disk

```bash
# Check disk health
ssh pve1 "smartctl -a /dev/sdb"  # Replace with the OSD's physical disk

# Check SMART status
ssh pve1 "smartctl -H /dev/sdb"

# Check disk I/O errors
ssh pve1 "dmesg | grep -i 'error\|fault\|bad' | grep -i 'sd\|nvme'"

# Check if the disk is readable
ssh pve1 "dd if=/dev/sdb bs=512 count=1 of=/dev/null" 2>&1
```

### Step 3: Attempt OSD Restart

```bash
# Restart the OSD service
ssh pve1 "systemctl restart ceph-osd@0"

# Wait and check if it comes back
sleep 10
ssh pve1 "ceph osd tree" | grep "osd.0"
```

### Step 4: Reweight OSD

If the OSD is back but causing performance issues:

```bash
# Reduce weight to distribute load
pmx-ceph.sh osd-reweight --osd-id=0 --weight=0.8

# Or directly
ssh pve1 "ceph osd reweight 0 0.8"

# Monitor recovery
ssh pve1 "ceph -w"
```

### Step 5: Replace Failed OSD

If the disk is dead:

```bash
# Mark OSD as out
ssh pve1 "ceph osd out 0"

# Wait for data to rebalance
ssh pve1 "ceph -w"  # Wait for recovery to complete

# Destroy the OSD
ssh pve1 "ceph osd destroy 0 --yes-i-really-mean-it"

# Remove the disk (if hot-swappable, replace physically)

# Create new OSD on replacement disk
pmx-ceph.sh osd-add --device=/dev/sdc --node=pve1

# Verify new OSD is in
ssh pve1 "ceph osd tree"
ssh pve1 "ceph -s"
```

---

## PG Degradation

### Step 1: Identify Degraded PGs

```bash
# Find PGs that are degraded or undersized
ssh pve1 "ceph pg dump_stuck degraded --format json" | jq .
ssh pve1 "ceph pg dump_stuck undersized --format json" | jq .

# Get detailed PG information
ssh pve1 "ceph pg dump | grep -E 'degraded|undersized'"
```

### Step 2: Understand the Cause

PGs are typically degraded because:
1. An OSD is down (most common)
2. A disk is slow causing OSD to be marked down
3. Network issue between OSDs

```bash
# Check OSD status
ssh pve1 "ceph osd tree" | grep -E "down|out"

# Check for slow requests
ssh pve1 "ceph daemon osd.0 dump_historic_ops" | head -20

# Check network between OSDs
ssh pve1 "ceph daemon osd.0 config show | grep ms_bind"
```

### Step 3: Repair Degraded PGs

```bash
# If the issue is OSD down, fix that first (see OSD Down section)

# Once OSDs are back, PGs will self-heal. Monitor recovery:
ssh pve1 "ceph -w"

# Force recovery if needed (use cautiously)
ssh pve1 "ceph osd pool set <pool-name> recovery_op_priority 1"

# Check recovery progress
ssh pve1 "ceph pg stat"
```

### Step 4: Repair Inconsistent PGs

```bash
# Find inconsistent PGs
ssh pve1 "ceph pg dump | grep inconsistent"

# Repair specific PG
ssh pve1 "ceph pg repair <pgid>"

# Monitor repair progress
ssh pve1 "ceph -w"
```

---

## Monitor Failure

### Step 1: Identify Failed Monitor

```bash
# Check monitor status
ssh pve1 "ceph mon stat"
ssh pve1 "ceph quorum_status --format json" | jq '.election_epoch, .quorum'

# Find which monitor is down
ssh pve1 "ceph mon dump"
```

### Step 2: Assess Impact

```bash
# Check if quorum is maintained
# Ceph needs majority of monitors for quorum
# 1 monitor = single point of failure
# 2 monitors = can lose 0
# 3 monitors = can lose 1
# 5 monitors = can lose 2

ssh pve1 "ceph quorum_status --format json" | jq '.quorum | length'
```

### Step 3: Replace Failed Monitor

If the monitor host is permanently lost:

```bash
# Remove the failed monitor from the monmap
ssh pve1 "ceph mon remove <failed-mon-name>"

# If the host is gone, remove from monmap directly
ssh pve1 "ceph mon getmap -o /tmp/monmap"
ssh pve1 "monmaptool /tmp/monmap --rm <failed-mon-name>"
ssh pve1 "ceph-mon -i <new-mon-name> --monmap /tmp/monmap --mkfs"

# Deploy new monitor on a healthy node
pmx-ceph.sh deploy --node=pve2 --mon

# Verify new monitor is in quorum
ssh pve1 "ceph mon stat"
ssh pve1 "ceph quorum_status --format json" | jq '.quorum'
```

### Step 4: Update Mon Map

```bash
# If you need to manually update the monmap
ssh pve1 "ceph mon getmap -o /tmp/monmap"

# Edit monmap
ssh pve1 "monmaptool /tmp/monmap --add <name> <ip>"
ssh pve1 "monmaptool /tmp/monmap --rm <name>"

# Apply to all monitors
for mon in $(ssh pve1 "ceph mon dump" | awk '/mon\./{print $2}'); do
  ssh $mon "ceph-mon -i $mon --inject-monmap /tmp/monmap"
  ssh $mon "systemctl restart ceph-mon@$(echo $mon | grep -o '[0-9]*')"
done
```

---

## Pool Issues

### Check Pool Configuration

```bash
# List pool settings
ssh pve1 "ceph osd pool get <pool-name> size"
ssh pve1 "ceph osd pool get <pool-name> min_size"

# Check pool stats
ssh pve1 "ceph osd pool stats <pool-name>"
```

### Repair Pool Size/Min Size

```bash
# If min_size is too high (causing I/O errors when an OSD is down)
ssh pve1 "ceph osd pool set <pool-name> min_size 1"

# Set proper replication size
ssh pve1 "ceph osd pool set <pool-name> size 3"

# Verify changes
ssh pve1 "ceph osd pool get <pool-name> size"
ssh pve1 "ceph osd pool get <pool-name> min_size"
```

### Pool Repair

```bash
# Scrub the pool to find inconsistencies
ssh pve1 "ceph osd pool scrub <pool-name> deep"

# Repair scrubbed data
ssh pve1 "ceph pg repair <pgid>"
```

---

## Full Cluster Recovery Procedure

### Phase 1: Assessment

```bash
# Run comprehensive health check
ssh pve1 "ceph -s"
ssh pve1 "ceph health detail"
ssh pve1 "ceph osd tree"
ssh pve1 "ceph pg stat"
ssh pve1 "ceph mon stat"
```

### Phase 2: Stabilize

```bash
# 1. Ensure all monitors are up and quorum is healthy
ssh pve1 "ceph mon stat"

# 2. Fix any down OSDs
ssh pve1 "ceph osd tree" | grep down
# Restart or replace as needed

# 3. Set min_size to 1 temporarily to allow I/O during recovery
ssh pve1 "ceph osd pool set <pool-name> min_size 1"
```

### Phase 3: Recovery

```bash
# 1. Wait for OSDs to come back (if restartable)
sleep 60
ssh pve1 "ceph -s"

# 2. Monitor PG recovery progress
ssh pve1 "ceph -w"  # Watch real-time events
ssh pve1 "ceph pg stat"  # Check PG states

# 3. If recovery is slow, increase recovery threads
ssh pve1 "ceph tell 'osd.*' injectargs --osd-max-backfills=4 --osd-recovery-max-active=8"
```

### Phase 4: Restore Normal Settings

```bash
# Once recovery is complete (ceph -s shows HEALTH_OK):
ssh pve1 "ceph osd pool set <pool-name> min_size 2"
ssh pve1 "ceph osd pool set <pool-name> size 3"

# Reset recovery throttle
ssh pve1 "ceph tell 'osd.*' injectargs --osd-max-backfills=1 --osd-recovery-max-active=3"

# Final verification
ssh pve1 "ceph -s"
ssh pve1 "ceph osd df"
ssh pve1 "ceph pg stat"
```

---

## Prevention

### 1. Hardware Monitoring

Monitor disk health with SMART:
```bash
# Check SMART status regularly
ssh pve1 "smartctl -H /dev/sd[a-z]"

# Set up smartd for automatic monitoring
ssh pve1 "systemctl enable smartd"
```

### 2. Proactive Scrubbing

Schedule regular deep scrubs:
```bash
# Weekly scrub
ssh pve1 "ceph osd pool scrub <pool-name>"
ssh pve1 "ceph osd pool scrub <pool-name> deep"

# Or configure in ceph.conf
ssh pve1 "cat >> /etc/ceph/ceph.conf" <<EOF
[osd]
osd scrub begin hour = 2
osd scrub end hour = 6
osd deep scrub interval = 604800
EOF
```

### 3. Sufficient Replication

Use at least 3 replicas for production data:
```bash
ssh pve1 "ceph osd pool set <pool-name> size 3"
ssh pve1 "ceph osd pool set <pool-name> min_size 2"
```

### 4. Monitor Capacity

```bash
# Check OSD utilization
ssh pve1 "ceph osd df"

# Alert if any OSD > 80% full
# Alert if overall cluster > 75% full
```

### 5. Test Recovery

Periodically test failure scenarios:
- Stop an OSD and verify self-healing
- Remove a monitor and verify quorum
- Simulate network partition (in lab only)

### 6. Keep Ceph Updated

```bash
# Check Ceph version
ssh pve1 "ceph --version"

# Update through Proxmox UI or
ssh pve1 "apt-get update && apt-get install ceph-common ceph-osd ceph-mon"
```
