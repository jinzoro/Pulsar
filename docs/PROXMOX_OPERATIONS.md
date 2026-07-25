# Proxmox Operations Reference

Complete reference for all Proxmox VE operations available through the Pulsar toolset.

---

## VM Lifecycle

### Create VM

**Purpose**: Create a new KVM virtual machine on a Proxmox node.

**CLI (pmxctl)**:
```bash
pmxctl vm create --name web-01 --node pve1 --cores 4 --memory 8192 --disk 100G --iso local:iso/ubuntu.iso
```

**Bash**:
```bash
proxmox/bash/pmx-vm-lifecycle.sh create \
  --name=web-01 --cores=4 --memory=8192 --disk=100G \
  --iso=local:iso/ubuntu.iso --storage=local-lvm --node=pve1
```

**Python**:
```python
client.create_vm(node="pve1", vmid=200, name="web-01", cores=4, memory=8192, disk="100G")
```

**API Endpoint**: `POST /nodes/{node}/qemu`

**Example payload**:
```json
{
  "vmid": 200,
  "name": "web-01",
  "cores": 4,
  "memory": 8192,
  "scsihw": "virtio-scsi-single",
  "bios": "seabios",
  "machine": "q35",
  "ide2": "local:iso/ubuntu.iso",
  "boot": "order=ide2"
}
```

**Prerequisites**: Node online, storage available, VMID not in use (or auto-assign).

**Error codes**:
- `400` — Invalid parameters (missing required fields)
- `409` — VMID already in use
- `500` — Node offline or internal error

---

### Start VM

**Purpose**: Start a stopped VM.

**CLI**: `pmxctl vm start [vmid]`

**Bash**: `pmx-vm-lifecycle.sh start --vmid=100 --node=pve1`

**Batch mode**: `pmx-vm-lifecycle.sh start --pool=production` or `start --tag=dev`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/start`

**Prerequisites**: VM exists and is stopped.

**Error codes**:
- `400` — VM already running
- `404` — VMID not found
- `500` — Node offline

---

### Stop VM

**Purpose**: Force-stop a VM (equivalent to pulling the power cord).

**CLI**: `pmxctl vm stop [vmid]`

**Bash**: `pmx-vm-lifecycle.sh stop --vmid=100`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/stop`

**Prerequisites**: VM exists.

---

### Shutdown VM

**Purpose**: Gracefully shut down a VM using ACPI. Waits for the guest OS to power off.

**CLI**: `pmxctl vm shutdown [vmid]`

**Bash**: `pmx-vm-lifecycle.sh shutdown --vmid=100 --timeout=60`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/shutdown` with body `{"timeout": 60}`

**Parameters**:
- `timeout` — Seconds to wait before force-stop (default: 30)

**Prerequisites**: VM exists and is running. Guest must have ACPI support.

---

### Reboot VM

**Purpose**: Reboot a running VM (ACPI reset signal).

**CLI**: Not directly available via pmxctl CLI; use stop + start.

**Bash**: `pmx-vm-lifecycle.sh reboot --vmid=100`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/reboot`

---

### Suspend VM

**Purpose**: Suspend a running VM to disk (pause with state saved to RAM/disk).

**Bash**: `pmx-vm-lifecycle.sh suspend --vmid=100`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/suspend`

**Prerequisites**: VM must be running.

---

### Resume VM

**Purpose**: Resume a suspended VM.

**Bash**: `pmx-vm-lifecycle.sh resume --vmid=100`

**API**: `POST /nodes/{node}/qemu/{vmid}/status/resume`

**Prerequisites**: VM must be in suspended state.

---

### Delete VM

**Purpose**: Delete a VM and optionally all its disks.

**CLI**: `pmxctl vm delete [vmid]`

**Bash**: `pmx-vm-lifecycle.sh delete --vmid=100 --purge`

**API**: `DELETE /nodes/{node}/qemu/{vmid}` (add `?purge=1` for full removal)

**Prerequisites**: VM should be stopped. Confirmation prompt required.

**Parameters**:
- `purge` — Also remove all disks and configuration (default: false)

**Safety**: The `confirm()` function in `common.sh` requires explicit `y` before deletion.

---

### Clone VM

**Purpose**: Clone an existing VM (full or linked clone).

**CLI**: `pmxctl vm clone [vmid] --newid 200 --name web-02 --full`

**Bash**: `pmx-vm-lifecycle.sh clone --vmid=100 --new-vmid=200 --name=web-02 --full`

**API**: `POST /nodes/{node}/qemu/{vmid}/clone`

**Parameters**:
- `newid` — Target VMID for the clone
- `name` — Name for the cloned VM
- `full` — Full clone (independent, default) vs linked clone (shares base disk)
- `target` — Target node for cross-node cloning
- `storage` — Target storage for the clone

**Prerequisites**: Source VM must exist and be stopped (or be a template).

---

### Rename VM

**Purpose**: Change the name of an existing VM.

**Bash**: `pmx-vm-lifecycle.sh rename --vmid=100 --new-name=web-server-01`

**API**: `PUT /nodes/{node}/qemu/{vmid}/config` with body `{"name": "web-server-01"}`

---

### Resize VM Disk

**Purpose**: Increase a VM's disk size.

**API**: `PUT /nodes/{node}/qemu/{vmid}/resize` with body `{"disk": "scsi0", "size": "+20G"}`

**Prerequisites**: VM should be stopped for resize, or use online resize if supported by the guest OS and disk type.

---

## Container (CT) Lifecycle

### Create Container

**Purpose**: Create an LXC container.

**Bash**: `pmx-ct-lifecycle.sh create --vmid=300 --hostname=web-ct --cores=2 --memory=1024 --disk=10G --storage=local-lvm --template=vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`

**API**: `POST /nodes/{node}/lxc`

**Parameters**:
- `vmid` — Container ID
- `hostname` — Container hostname
- `cores` — Number of CPU cores
- `memory` — Memory in MB
- `disk` — Root disk size
- `storage` — Target storage
- `template` — Template for the root filesystem
- `net0` — Network configuration (e.g., `name=eth0,bridge=vmbr0,ip=dhcp`)

---

### Start Container

**Bash**: `pmx-ct-lifecycle.sh start --vmid=300`

**API**: `POST /nodes/{node}/lxc/{vmid}/status/start`

---

### Stop Container

**Bash**: `pmx-ct-lifecycle.sh stop --vmid=300`

**API**: `POST /nodes/{node}/lxc/{vmid}/status/stop`

---

### Shutdown Container

**Bash**: `pmx-ct-lifecycle.sh shutdown --vmid=300 --timeout=60`

**API**: `POST /nodes/{node}/lxc/{vmid}/status/shutdown`

---

### Delete Container

**Bash**: `pmx-ct-lifecycle.sh delete --vmid=300 --purge`

**API**: `DELETE /nodes/{node}/lxc/{vmid}?purge=1`

---

### Clone Container

**Bash**: `pmx-ct-lifecycle.sh clone --vmid=300 --new-vmid=400 --name=web-ct-clone`

**API**: `POST /nodes/{node}/lxc/{vmid}/clone`

---

### Resize Container

**API**: `PUT /nodes/{node}/lxc/{vmid}/resize` with body `{"disk": "rootfs", "size": "+10G"}`

---

## Storage

### List Storage

**CLI**: `pmxctl storage list`

**Bash**: `pmx-storage.sh list --node=pve1`

**API**: `GET /nodes/{node}/storage`

---

### Add Storage

**Bash**: `pmx-storage.sh add --node=pve1 --name=backup-nas --type=nfs --server=10.0.0.50 --export=/volume1/backups --content=vztmpl,backup`

**API**: `POST /nodes/{node}/storage`

**Parameters**:
- `type` — Storage type: `dir`, `lvm`, `lvmthin`, `nfs`, `cifs`, `zfspool`, `cephfs`, `rbd`
- `server` — NFS/CIFS server address
- `export` — NFS export path
- `content` — Comma-separated content types: `images`, `iso`, `vztmpl`, `backup`, `rootdir`

---

### Remove Storage

**Bash**: `pmx-storage.sh remove --node=pve1 --name=backup-nas`

**API**: `DELETE /nodes/{node}/storage/{storage}`

---

### Storage Status

**Bash**: `pmx-storage.sh status --node=pve1 --name=local-lvm`

**API**: `GET /nodes/{node}/storage/{storage}/status`

---

### Resize Storage Volume

**API**: `PUT /nodes/{node}/qemu/{vmid}/resize` with body `{"disk": "scsi0", "size": "+50G"}`

---

### Move Disk

**Purpose**: Move a VM disk between storage locations.

**API**: `POST /nodes/{node}/qemu/{vmid}/migratedisk` with body `{"disk": "scsi0", "storage": "ceph-ssd"}`

---

### Import Disk

**Purpose**: Import an external disk image into a VM.

**API**: `POST /nodes/{node}/storage/{storage}/content` (upload) then `POST /nodes/{node}/qemu/{vmid}/config` to attach.

---

## Backup

### Backup VM

**CLI**: `pmxctl backup list [storage]`

**Bash**: `pmx-backup-restore.sh backup --vmid=100 --storage=backup-nas --mode=snapshot --compress=zstd`

**API**: `POST /nodes/{node}/qemu/{vmid}/backup`

**Parameters**:
- `storage` — Target backup storage
- `mode` — Backup mode: `snapshot` (live, default), `suspend` (brief pause), `stop` (VM stopped during backup)
- `compress` — Compression: `zstd` (best ratio), `gz`, `lzo`
- `retain` — Retention count

---

### Restore VM

**Bash**: `pmx-backup-restore.sh restore --vmid=100 --storage=backup-nas --backup-id=vzdump-qemu-100-2026_01_01-02_00_00.vma.zst`

**API**: `POST /nodes/{node}/qemu` with body containing the archive reference

**Parameters**:
- `vmid` — Target VMID for restore
- `storage` — Storage containing the backup
- `archive` — Backup file identifier
- `target-node` — Restore to a different node
- `target-storage` — Restore to different storage
- `target-vmid` — Restore as a different VMID

---

### List Backups

**Bash**: `pmx-backup-restore.sh list --storage=backup-nas` or `list --vmid=100 --storage=backup-nas`

**API**: `GET /nodes/{node}/storage/{storage}/content`

---

### Verify Backup

**Bash**: `pmx-backup-restore.sh verify --vmid=100 --backup-id=vzdump-qemu-100-....vma.zst`

---

### Prune Backups

**Bash**: `pmx-backup-restore.sh prune --vmid=100 --storage=backup-nas --keep-daily=7 --keep-weekly=4 --keep-monthly=6`

**Retention parameters**:
- `keep-daily` — Number of daily backups to keep (default: 7)
- `keep-weekly` — Number of weekly backups to keep (default: 4)
- `keep-monthly` — Number of monthly backups to keep (default: 6)

---

### Schedule Backup

**Bash**: `pmx-backup-restore.sh schedule --vmid=100 --cron="0 2 * * *" --storage=backup-nas --mode=snapshot`

**API**: `PUT /nodes/{node}/qemu/{vmid}/config` with backup schedule parameters.

---

## PBS Integration

### PBS Datastore Operations

**Bash**: `pmx-pbs-integration.sh list-backups --datastore=backup`

**API**: PBS REST API at `PBS_API_URL` with `PBS_TOKEN` authentication.

---

### PBS Backup

**Bash**: `pmx-pbs-integration.sh backup --vmid=100 --datastore=backup --prune-config="keep-daily=7,keep-weekly=4"`

---

### PBS Restore

**Bash**: `pmx-pbs-integration.sh restore --vmid=100 --datastore=backup --snapshot=2026-01-01T02:00:00Z`

---

### PBS Verify

**Bash**: `pmx-pbs-integration.sh verify --datastore=backup --snapshot=2026-01-01T02:00:00Z`

---

### PBS Prune

**Bash**: `pmx-pbs-integration.sh prune --datastore=backup --keep-daily=7 --keep-weekly=4 --keep-monthly=6`

---

## Cluster

### Cluster Status

**CLI**: `pmxctl cluster status`

**Bash**: `pmx-cluster.sh status`

**API**: `GET /cluster/status`

**Returns**: Cluster name, type, and per-node status (name, status, ID).

---

### Create Cluster

**Bash**: `pmx-cluster.sh create --cluster-name=mycluster --node=pve1`

**Prerequisites**: Single-node Proxmox installation, no existing cluster.

---

### Join Cluster

**Bash**: `pmx-cluster.sh join --node=pve2 --existing-host=pve1.example.com --existing-token="automation@pam!mytoken=xxxx" --ring0=10.0.0.1 --ring1=10.0.1.1`

**API**: `POST /cluster/join`

**Prerequisites**: Target node must be a standalone Proxmox node. API token from the existing cluster.

---

### Remove Node from Cluster

**Bash**: `pmx-cluster.sh remove --node=pve3`

**Prerequisites**: Node should be in maintenance mode with all VMs migrated.

---

### List Cluster Nodes

**CLI**: `pmxctl cluster nodes`

**Bash**: `pmx-cluster.sh nodes`

**API**: `GET /cluster/config/nodes`

---

### Quorum Status

**Bash**: `pmx-cluster.sh quorum`

**API**: `GET /cluster/config/quorum`

---

## High Availability (HA)

### List HA Groups

**CLI**: `pmxctl ha groups`

**Bash**: `pmx-ha.sh groups`

**API**: `GET /cluster/ha/groups`

---

### Create HA Group

**Bash**: `pmx-ha.sh group-create --name=hagroup1 --nodes="pve1:2,pve2:1" --type=failover`

---

### List HA Resources

**CLI**: `pmxctl ha resources`

**Bash**: `pmx-ha.sh resources`

**API**: `GET /cluster/ha/resources`

---

### Add HA Resource

**Bash**: `pmx-ha.sh resource-add --sid=vm:100 --group=hagroup1 --type=vm --state=started`

---

### HA Resource State

**Bash**: `pmx-ha.sh state --sid=vm:100`

---

### Failover

Automatic when a node fails. HA manager on another node starts the VM. Manual failover:

**Bash**: `pmx-ha.sh migrate --sid=vm:100 --target=pve2`

---

## Firewall

### List Firewall Rules

**CLI**: `pmxctl firewall rules`

**Bash**: `pmx-firewall.sh rules --node=pve1`

**API**: `GET /nodes/{node}/firewall/rules` or `GET /cluster/firewall/rules`

---

### Add Firewall Rule

**Bash**: `pmx-firewall.sh rule-add --node=pve1 --action=ACCEPT --proto=tcp --dport=80 --source=10.0.0.0/8`

---

### IP Sets

**Bash**: `pmx-firewall.sh ipset-create --node=pve1 --name=trusted-servers --cidr=10.0.0.0/24`

---

### Aliases

**Bash**: `pmx-firewall.sh alias-create --node=pve1 --name=web-servers --cidr=10.0.0.10/32`

---

### Security Groups

**Bash**: `pmx-firewall.sh group-create --node=pve1 --name=web-allowed --rules=rule1,rule2`

---

## Users and ACLs

### List Users

**CLI**: `pmxctl user list`

**Bash**: `pmx-user-acl.sh list-users`

**API**: `GET /access/users`

---

### Create User

**Bash**: `pmx-user-acl.sh user-create --userid=operator@pve --password=changeme --email=ops@example.com`

---

### List Groups

**Bash**: `pmx-user-acl.sh list-groups`

**API**: `GET /access/groups`

---

### Create Group

**Bash**: `pmx-user-acl.sh group-create --groupid=operators --comment="Operations team"`

---

### List Roles

**Bash**: `pmx-user-acl.sh list-roles`

**API**: `GET /access/roles`

---

### Create Role

**Bash**: `pmx-user-acl.sh role-create --roleid=vm-operator --privs="VM.Allocate,VM.PowerMgmt,VM.Console"`

---

### Set ACL

**Bash**: `pmx-user-acl.sh acl-set --path="/storage/backup-nas" --auth-id=operator@pve --role=PVEVMAdmin`

**API**: `POST /access/acl`

---

### API Tokens

**Bash**: `pmx-user-acl.sh token-create --auth-id="automation@pam!mytoken" --comment="CI/CD token" --privsep=0`

---

### Two-Factor Authentication

**Bash**: `pmx-user-acl.sh tfa-setup --user=admin@pam --type=totp --digits=6 --period=30`

---

## Snapshots

### List Snapshots

**CLI**: `pmxctl snapshot list [vmid]`

**Bash**: `pmx-snapshot.sh list --vmid=100`

**API**: `GET /nodes/{node}/qemu/{vmid}/snapshot`

---

### Create Snapshot

**CLI**: `pmxctl snapshot create [vmid] [name] --description "Before upgrade"`

**Bash**: `pmx-snapshot.sh create --vmid=100 --name=pre-upgrade --description="Before kernel upgrade"`

**API**: `POST /nodes/{node}/qemu/{vmid}/snapshot`

**Parameters**:
- `snapname` — Snapshot name
- `description` — Human-readable description
- `vmstate` — Include VM memory state (for live snapshots; default: false)

---

### Rollback to Snapshot

**CLI**: `pmxctl snapshot rollback [vmid] [snapname]`

**Bash**: `pmx-snapshot.sh rollback --vmid=100 --name=pre-upgrade`

**API**: `POST /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/rollback`

**Prerequisites**: VM must be stopped before rollback.

---

### Delete Snapshot

**CLI**: `pmxctl snapshot delete [vmid] [snapname]`

**Bash**: `pmx-snapshot.sh delete --vmid=100 --name=old-snapshot`

**API**: `DELETE /nodes/{node}/qemu/{vmid}/snapshot/{snapname}`

---

## Templates

### Create Template

**Bash**: `pmx-template.sh create --vmid=100 --node=pve1`

Converts an existing VM into a template (VM must be stopped).

**API**: `POST /nodes/{node}/qemu/{vmid}/template`

---

### List Templates

**Bash**: `pmx-template.sh list --node=pve1`

---

### Clone from Template

**Bash**: `pmx-template.sh clone --vmid=100 --new-vmid=200 --name=new-vm --full`

---

### Delete Template

**Bash**: `pmx-template.sh delete --vmid=100 --purge`

---

## Migration

### Live Migration

**CLI**: `pmxctl migrate vm [vmid] [target] --online`

**Bash**: `pmx-migration.sh migrate --vmid=100 --target=pve2 --online`

**API**: `POST /nodes/{source}/qemu/{vmid}/migrate` with body `{"target": "pve2", "online": true}`

**Prerequisites**:
- Shared storage between source and target (for online migration without disk copy)
- Both nodes online and in the same cluster
- Sufficient resources on target node

---

### Offline Migration

**Bash**: `pmx-migration.sh migrate --vmid=100 --target=pve2`

VM is stopped, disk is copied, then started on the target.

---

### Batch Migration

**Bash**: `pmx-migration.sh migrate --tag=dev --target=pve2 --online`

Migrates all VMs with a specific tag.

---

### Evacuate

**Bash**: `pmx-migration.sh evacuate --node=pve1 --target=pve2`

Migrates all VMs off a node (for maintenance).

---

### Cancel Migration

**Bash**: `pmx-migration.sh cancel --vmid=100`

**API**: `DELETE /nodes/{node}/qemu/{vmid}/migrate`

---

## Ceph

### Deploy Ceph

**Bash**: `pmx-ceph.sh deploy --node=pve1 --mon --mgr --osd-devices=/dev/sdb,/dev/sdc`

---

### Ceph Status

**CLI**: `pmxctl ceph status [node]`

**Bash**: `pmx-ceph.sh status --node=pve1`

**API**: `GET /nodes/{node}/ceph/status`

---

### Ceph Health Detail

**Bash**: `pmx-ceph.sh health --node=pve1`

---

### Pool Operations

**Create**: `pmx-ceph.sh pool-create --name=ssd-pool --size=3 --min-size=2 --pg-num=128`

**Delete**: `pmx-ceph.sh pool-delete --name=ssd-pool`

**List**: `pmx-ceph.sh pool-list --node=pve1`

**Set size**: `pmx-ceph.sh pool-set-size --name=ssd-pool --size=3`

---

### OSD Operations

**List**: `pmx-ceph.sh osd-list --node=pve1`

**Add**: `pmx-ceph.sh osd-add --device=/dev/sdd --node=pve1`

**Remove**: `pmx-ceph.sh osd-remove --osd-id=0 --node=pve1`

**Reweight**: `pmx-ceph.sh osd-reweight --osd-id=0 --weight=0.8`

---

### Scrub

**Bash**: `pmx-ceph.sh scrub --pool=ssd-pool --deep`

---

## ZFS

### List ZFS Pools

**CLI**: `pmxctl zfs list [node]`

**Bash**: `pmx-zfs.sh list --node=pve1`

**API**: `GET /nodes/{node}/disks/zfs`

---

### Create ZFS Pool

**Bash**: `pmx-zfs.sh pool-create --name=fast-ssd --devices=/dev/nvme0n1,/dev/nvme1n1 --type=mirror`

---

### Create ZFS Dataset

**Bash**: `pmx-zfs.sh dataset-create --pool=fast-ssd --name=vms --quota=500G`

---

### ZFS Properties

**Bash**: `pmx-zfs.sh set --pool=fast-ssd --property=compression=lz4 --dataset=vms`

---

### ZFS Scrub

**Bash**: `pmx-zfs.sh scrub --pool=fast-ssd`

---

### ZFS Snapshots

**Create**: `pmx-zfs.sh snapshot-create --pool=fast-ssd --dataset=vms --name=pre-update`

**List**: `pmx-zfs.sh snapshot-list --pool=fast-ssd`

**Delete**: `pmx-zfs.sh snapshot-delete --pool=fast-ssd --name=pre-update`

---

## Network

### List Network Interfaces

**CLI**: `pmxctl network list [node]`

**Bash**: `pmx-network.sh list --node=pve1`

**API**: `GET /nodes/{node}/network`

---

### Create Bridge

**Bash**: `pmx-network.sh bridge-create --node=pve1 --name=vmbr1 --cidr=10.0.1.1/24`

---

### Create Bond

**Bash**: `pmx-network.sh bond-create --node=pve1 --name=bond0 --interfaces=eth0,eth1 --mode=802.3ad`

---

### VLAN Configuration

**Bash**: `pmx-network.sh vlan-create --node=pve1 --name=vmbr0.100 --vlan-id=100 --parent=vmbr0 --cidr=10.0.100.1/24`

---

### SDN (Software-Defined Networking)

**Bash**: `pmx-sdn.sh zone-create --node=pve1 --type=vlan --id=vlan-zone`

**Bash**: `pmx-sdn.sh vnet-create --node=pve1 --zone=vlan-zone --id=tenant-a --alias="Tenant A network"`

---

## Passthrough

### GPU Passthrough

**Bash**: `pmx-gpu-passthrough.sh setup --node=pve1 --pci-addr=01:00.0 --vmid=100`

**Enables**:
- IOMMU isolation
- VFIO driver binding
- GPU assignment to VM

---

### PCI Passthrough

**Bash**: `pmx-pci-passthrough.sh setup --node=pve1 --pci-addr=03:00.0 --vmid=100`

**API**: `PUT /nodes/{node}/qemu/{vmid}/config` with hostpci parameter.

---

### SR-IOV

**Bash**: `pmx-sriov.sh setup --node=pve1 --pci-addr=01:00.0 --vfs=4 --vmid=100`

---

## Cloud-Init

### Configure Cloud-Init

**Bash**: `pmx-cloudinit.sh configure --vmid=100 --node=pve1 --ip=10.0.0.10/24 --gateway=10.0.0.1 --dns=8.8.8.8 --user=ubuntu --ssh-key-file=~/.ssh/id_rsa.pub`

**API**: `PUT /nodes/{node}/qemu/{vmid}/config` with cloud-init parameters:
- `ipconfig0` — IP configuration
- `ciuser` — Default user
- `cipassword` — Default user password
- `sshkeys` — SSH public keys
- `nameserver` — DNS servers

---

### Regenerate Cloud-Init

**Bash**: `pmx-cloudinit.sh regenerate --vmid=100`

**API**: `POST /nodes/{node}/qemu/{vmid}/cloudinit`

---

### Download Cloud-Init Drive

**Bash**: `pmx-cloudinit.sh download --vmid=100 --output=/tmp/cloud-init.iso`

---

## Monitoring

### Health Check

**CLI**: `pmxctl health`

**Bash**: `pmx-health-check.sh --nodes=pve1,pve2,pve3`

Checks: node status, VM status, storage availability, Ceph health, load averages, disk usage.

---

### Capacity Report

**Python**: `pmx_capacity_report.py`

Generates capacity planning reports across all nodes.

---

### Alerting

**Python**: `pmx_alerting.py`

Evaluates alert rules against cluster state and dispatches notifications via configured channels.

**Configurable thresholds** (from `settings.yaml`):
- CPU warning: 75%, critical: 90%
- Memory warning: 80%, critical: 95%
- Disk warning: 80%, critical: 95%
- Backup failure alerts: enabled/disabled

---

## Maintenance

### Enter Maintenance Mode

**Bash**: `pmx-node-maintenance.sh enter --node=pve1`

**Actions**:
1. Migrates or shuts down all VMs (based on `--mode=migrate|shutdown|wait`)
2. Marks node as maintenance in Proxmox UI
3. Optionally drains Ceph OSDs

---

### Exit Maintenance Mode

**Bash**: `pmx-node-maintenance.sh exit --node=pve1`

**Actions**:
1. Marks node as active
2. Returns Ceph OSDs to service
3. Optionally starts previously shut down VMs

---

### Update Node

**Bash**: `pmx-node-maintenance.sh update --node=pve1`

**API**: `POST /nodes/{node}/apt/update`

---

### Reboot Node

**Bash**: `pmx-node-maintenance.sh reboot --node=pve1`

**API**: `POST /nodes/{node}/status/reboot`
