# Runbook: Storage Full

**Severity**: High  
**Response Time**: Within 30 minutes  
**Last Updated**: 2026-07-25

---

## Detection

### How to Identify Storage Full

**Symptoms**:
- VM operations fail with "no space left on device"
- Backup jobs fail
- New VM creation fails
- Ceph reports `HEALTH_WARN` with "full" flag
- ZFS shows 100% usage

**Detection commands**:
```bash
# Check storage usage via Proxmox
pmx-storage.sh status --node=pve1

# Check via CLI
ssh pve1 "pvesm status"

# Check disk usage directly
ssh pve1 "df -h /var/lib/vz /dev/pve"
ssh pve1 "df -h"

# Check Ceph usage
pmx-ceph.sh status --node=pve1

# Check ZFS usage
pmx-zfs.sh list --node=pve1
ssh pve1 "zpool list"

# Health check includes storage
pmx-health-check.sh --nodes=pve1,pve2,pve3
```

**Thresholds** (from `settings.yaml`):
- Warning: 80% usage
- Critical: 95% usage

---

## Assessment

### Step 1: Identify What's Using Space

```bash
# Proxmox storage content breakdown
ssh pve1 "pvesm list local-lvm"
ssh pve1 "pvesm list local"

# List backup files with sizes
ssh pve1 "ls -lhS /var/lib/vz/dump/"

# List ISO files with sizes
ssh pve1 "ls -lhS /var/lib/vz/template/iso/"

# List VM disk images
ssh pve1 "ls -lhS /dev/pve/"

# Check thin provisioning usage (for lvmthin)
ssh pve1 "lvs -o+data_percent,metadata_percent /dev/pve/vm-*"
ssh pve1 "lvs -a -o+data_percent,metadata_percent"
```

### Step 2: Determine Provisioning Type

```bash
# Check if storage is thin or thick provisioned
ssh pve1 "pvesm status | grep -E 'local|ceph|zfspool'"

# Thin provisioned (lvmthin, zfs, ceph): can overcommit, monitor actual usage
# Thick provisioned (lvm, dir, nfs): usage = allocated, must free space
```

### Step 3: Assess Impact

```bash
# How many backups exist?
pmx-backup-restore.sh list --storage=backup-nas | wc -l

# How old are the oldest backups?
pmx-backup-restore.sh list --storage=backup-nas | sort -k4 | head -5

# Are there unused templates/ISOs?
ssh pve1 "ls -lhS /var/lib/vz/template/iso/"

# How many snapshots exist per VM?
for vmid in $(ssh pve1 "qm list | awk 'NR>1{print $1}'"); do
  count=$(ssh pve1 "qm listsnapshot $vmid 2>/dev/null | wc -l")
  echo "VM $vmid: $count snapshots"
done
```

---

## Immediate Cleanup

### Priority 1: Remove Old Backups

```bash
# Prune backups using retention policy
pmx-backup-restore.sh prune --vmid=100 --storage=backup-nas \
  --keep-daily=7 --keep-weekly=4 --keep-monthly=6

# Or manually remove old backups (BEYOND retention policy)
ssh pve1 "cd /var/lib/vz/dump && ls -t vzdump-qemu-*.vma.zst | tail -n +30 | xargs -r rm -f"
# This keeps only the 30 most recent backup files

# If using PBS
pmx-pbs-integration.sh prune --datastore=backup --keep-daily=7 --keep-weekly=4 --keep-monthly=6
```

### Priority 2: Remove Old Snapshots

```bash
# List all snapshots and their ages
for vmid in $(ssh pve1 "qm list | awk 'NR>1{print $1}'"); do
  echo "=== VM $vmid ==="
  ssh pve1 "qm listsnapshot $vmid 2>/dev/null"
done

# Delete snapshots older than 30 days (adjust threshold as needed)
# Example: delete a specific old snapshot
pmx-snapshot.sh delete --vmid=100 --name=old-snapshot

# Automate: find and remove snapshots older than N days
# (Requires scripting against the API for each VM)
```

### Priority 3: Remove Unused ISOs and Templates

```bash
# List ISOs by size (largest first)
ssh pve1 "ls -lhS /var/lib/vz/template/iso/"

# Remove specific ISOs
ssh pve1 "rm /var/lib/vz/template/iso/ubuntu-22.04-desktop-amd64.iso"

# Remove all ISOs older than 90 days
ssh pve1 "find /var/lib/vz/template/iso/ -name '*.iso' -mtime +90 -delete"

# List and remove unused templates
ssh pve1 "ls -lhS /var/lib/vz/template/cache/"
ssh pve1 "rm /var/lib/vz/template/cache/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
```

### Priority 4: Clean apt Cache on Nodes

```bash
# Clean apt package cache
ssh pve1 "apt-get clean"
ssh pve1 "apt-get autoremove -y"

# Clean PVE enterprise repo cache (if not using enterprise)
ssh pve1 "rm -f /var/lib/apt/lists/*pve-enterprise*"
ssh pve1 "apt-get update"

# Clean kernel images (if multiple kernels are installed)
ssh pve1 "dpkg -l 'pve-kernel-*' | grep ^ii"
ssh pve1 "apt-get remove --purge pve-kernel-6.5.* -y"  # Keep current kernel
```

### Priority 5: Clean Container Templates

```bash
# List container templates
ssh pve1 "ls -lhS /var/lib/vz/template/cache/"

# Remove old templates
ssh pve1 "find /var/lib/vz/template/cache/ -name '*.tar.zst' -mtime +60 -delete"
```

---

## Disk Expansion

### Add New Disks (Hardware)

If the physical disk is full:

1. Add a new disk to the server
2. Initialize it:

```bash
# For LVM
ssh pve1 "pvcreate /dev/sdb"
ssh pve1 "vgextend pve /dev/sdb"

# For ZFS
ssh pve1 "zpool add fast-ssd /dev/sdb"

# For Ceph OSD
pmx-ceph.sh osd-add --device=/dev/sdb --node=pve1
```

### Expand LVM

```bash
# Check current LVM layout
ssh pve1 "pvs"
ssh pve1 "vgs"

# Extend the data logical volume
ssh pve1 "lvextend -l +100%FREE /dev/pve/data"

# For thin pool, extend the pool
ssh pve1 "lvextend -l +100%FREE /dev/pve/data"

# Resize the filesystem (ext4 or xfs)
ssh pve1 "resize2fs /dev/mapper/pve-data"  # ext4
# or
ssh pve1 "xfs_growfs /dev/mapper/pve-data"  # xfs
```

### Expand ZFS Pool

```bash
# Add a mirror vdev
ssh pve1 "zpool add fast-ssd mirror /dev/sdc /dev/sdd"

# Add a single disk (striped)
ssh pve1 "zpool add fast-ssd /dev/sdc"

# Check resulting pool
ssh pve1 "zpool status fast-ssd"
ssh pve1 "zpool list fast-ssd"
```

### Expand Ceph

```bash
# Add new OSD
pmx-ceph.sh osd-add --device=/dev/sdc --node=pve1

# Check Ceph now has more capacity
pmx-ceph.sh status --node=pve1
```

---

## Migration to Larger Storage

### Move VMs to Another Storage

```bash
# Move a VM's disk to a different storage
ssh pve1 "qm disk move 100 scsi0 --storage ceph-ssd"

# Move all disks of a VM
for disk in scsi0 scsi1 ide2; do
  ssh pve1 "qm disk move 100 $disk --storage ceph-ssd" 2>/dev/null && \
    echo "Moved $disk" || echo "Disk $disk not found, skipping"
done
```

### Add New Storage Pool

```bash
# Add NFS storage
pmx-storage.sh add --node=pve1 --name=backup-nfs --type=nfs \
  --server=10.0.0.50 --export=/volume1/backups \
  --content=images,backup,vztmpl

# Add ZFS storage
pmx-storage.sh add --node=pve1 --name=fast-ssd --type=zfspool \
  --pool=fast-ssd --content=images,rootdir
```

---

## Prevention

### 1. Monitoring and Alerts

Configure alerting thresholds in `settings.yaml`:
```yaml
alerts:
  disk_warn: 80
  disk_crit: 95
```

Enable notifications:
```yaml
notifications:
  slack:
    enabled: true
    webhook_url: "https://hooks.slack.com/services/..."
```

### 2. Retention Policies

Set consistent retention policies:
```bash
# Backup retention (in settings.yaml)
backup:
  retention:
    daily: 7
    weekly: 4
    monthly: 6
```

### 3. Regular Cleanup Scripts

Create a cron job for regular cleanup:
```bash
# /etc/cron.weekly/swissknife-cleanup
#!/bin/bash
source /opt/pulsar/shared/bash/lib/common.sh
load_env /opt/pulsar/.env

# Prune backups for all VMs
for vmid in $(ssh pve1 "qm list | awk 'NR>1{print $1}'"); do
  pmx-backup-restore.sh prune --vmid=$vmid --storage=backup-nas \
    --keep-daily=7 --keep-weekly=4 --keep-monthly=6
done

# Clean apt cache
ssh pve1 "apt-get clean"
```

### 4. Capacity Planning

Run capacity reports regularly:
```bash
# Generate capacity report
python3 proxmox/python/pmx_capacity_report.py

# Check storage trends
pmx-health-check.sh --nodes=pve1,pve2,pve3
```

### 5. Thin Provisioning Alerts

Monitor thin provisioning ratios:
```bash
# Check actual vs allocated for lvmthin
ssh pve1 "lvs -o lv_name,data_percent,metadata_percent /dev/pve/data"

# Check ZFS compression ratio
ssh pve1 "zpool get ratio fast-ssd"

# Alert if thin provisioning ratio > 3:1
```
