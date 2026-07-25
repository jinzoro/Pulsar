# KVM/libvirt Operations Reference

Complete reference for all KVM/libvirt operations available through the proxmox-kvm-swissknife toolset. These operations manage local KVM hypervisors via libvirt.

---

## VM Lifecycle

### Create VM

**Purpose**: Create a new KVM virtual machine via libvirt.

**Python**:
```python
from kvm_vm_manager import VMManager

manager = VMManager()
name = manager.create(
    name="web01",
    ram_mb=4096,
    vcpus=4,
    disk_path="/var/lib/libvirt/images/web01.qcow2",
    disk_format="qcow2",
    network="default",
    os_variant="ubuntu24.04",
    cpu_model="host-passthrough",
    machine="q35",
    uefi=True
)
```

**CLI (kvmctl)**:
```bash
kvmctl create --name dev-vm --cpus 4 --ram 8G --disk 50G --iso /var/lib/libvirt/images/ubuntu-22.04.iso
```

**Bash**: `kvm-vm-lifecycle.sh create --name=dev-vm --cpus=4 --ram=8G --disk=50G`

**Parameters**:
- `name` — VM name (unique)
- `ram_mb` / `--ram` — RAM in MB or human-readable (8G)
- `vcpus` / `--cpus` — Number of virtual CPUs
- `disk_path` / `--disk` — Disk image path or size
- `disk_format` — `qcow2` (default), `raw`, `vmdk`
- `network` — Network name or bridge (default: `default` for NAT)
- `graphics` — Graphics type: `vnc` (default), `spice`
- `os_variant` — OS type for optimal defaults
- `cpu_model` — CPU model: `host-passthrough`, `host-model`, `qemu64`
- `machine` — Machine type: `q35` (recommended), `pc`
- `uefi` — Enable UEFI boot (OVMF)
- `tpm` — Enable TPM 2.0 emulation
- `cloud_init_iso` — Attach Cloud-Init ISO

**Domain XML generation**: The `VMManager._build_domain_xml()` method generates minimal domain XML with proper device definitions.

---

### Start VM

**Python**:
```python
manager.start("web01")
```

**CLI**: `kvmctl start --name dev-vm`

**Bash**: `kvm-vm-lifecycle.sh start --name=dev-vm`

**libvirt call**: `virsh start <domain>`

---

### Stop VM

**Python**:
```python
manager.stop("web01")
```

**CLI**: `kvmctl stop --name dev-vm`

**Bash**: `kvm-vm-lifecycle.sh stop --name=dev-vm`

**libvirt call**: `virsh destroy <domain>` (force stop, equivalent to pulling power cord)

---

### Destroy VM

**Python**:
```python
manager.destroy("web01")
```

**CLI**: `kvmctl destroy --name dev-vm`

**Bash**: `kvm-vm-lifecycle.sh destroy --name=dev-vm`

**libvirt call**: `virsh undefine <domain> --remove-all-storage`

**Prerequisites**: VM must be stopped.

---

### Suspend VM

**Python**:
```python
manager.suspend("web01")
```

**Bash**: `kvm-vm-lifecycle.sh suspend --name=dev-vm`

**libvirt call**: `virsh suspend <domain>`

**Note**: Suspend to RAM — state is kept in memory. Requires the VM to remain powered on (but paused).

---

### Resume VM

**Python**:
```python
manager.resume("web01")
```

**Bash**: `kvm-vm-lifecycle.sh resume --name=dev-vm`

**libvirt call**: `virsh resume <domain>`

---

### Save VM State

**Purpose**: Save complete VM state to a file and shut down.

**Python**:
```python
manager.save("web01", "/var/lib/libvirt/saves/web01.save")
```

**Bash**: `kvm-vm-lifecycle.sh save --name=dev-vm --file=/var/lib/libvirt/saves/dev-vm.save`

**libvirt call**: `virsh save <domain> <file>`

**Prerequisites**: VM must be running. VM is stopped after save.

---

### Restore VM State

**Purpose**: Restore a previously saved VM state.

**Python**:
```python
manager.restore("/var/lib/libvirt/saves/web01.save")
```

**Bash**: `kvm-vm-lifecycle.sh restore --file=/var/lib/libvirt/saves/dev-vm.save`

**libvirt call**: `virsh restore <file>`

---

### Undefine VM

**Purpose**: Remove VM definition without deleting disk images.

**Bash**: `kvm-vm-lifecycle.sh undefine --name=dev-vm`

**libvirt call**: `virsh undefine <domain>`

---

### Clone VM

**Purpose**: Create a linked or full clone of an existing VM.

**Python**:
```python
manager.clone("web01", "web01-clone", full=True)
```

**CLI**: `kvmctl clone --source dev-vm --name dev-vm-clone`

**Bash**: `kvm-vm-lifecycle.sh clone --source=dev-vm --name=dev-vm-clone --full`

**Parameters**:
- `source` — Source VM name
- `name` — Clone name
- `full` — Full clone (independent) vs linked clone (shares backing file)

---

## Disk Management

### Create Disk Image

**Python**:
```python
from kvm_disk_manager import DiskManager

dm = DiskManager()
dm.create("/var/lib/libvirt/images/data.qcow2", size_gb=100, format="qcow2")
```

**Bash**: `kvm-disk-image.sh create --path=/var/lib/libvirt/images/data.qcow2 --size=100G --format=qcow2`

**Tool**: `qemu-img create -f qcow2 /path/to/disk.qcow2 100G`

---

### Convert Disk Format

**Bash**: `kvm-disk-image.sh convert --source=/path/source.vmdk --target=/path/target.qcow2 --format=qcow2`

**Tool**: `qemu-img convert -f vmdk -O qcow2 source.vmdk target.qcow2`

---

### Resize Disk

**Bash**: `kvm-disk-image.sh resize --path=/var/lib/libvirt/images/data.qcow2 --size=+50G`

**Tool**: `qemu-img resize /path/to/disk.qcow2 +50G`

---

### Disk Info

**Python**:
```python
info = dm.info("/var/lib/libvirt/images/data.qcow2")
print(info)  # {virtual_size, actual_size, format, backing_file, ...}
```

**Bash**: `kvm-disk-image.sh info --path=/var/lib/libvirt/images/data.qcow2`

**Tool**: `qemu-img info /path/to/disk.qcow2`

---

### Disk Check

**Bash**: `kvm-disk-image.sh check --path=/var/lib/libvirt/images/data.qcow2`

**Tool**: `qemu-img check /path/to/disk.qcow2`

---

### Disk Benchmark

**Bash**: `kvm-disk-image.sh benchmark --path=/var/lib/libvirt/images/data.qcow2 --size=1G`

Runs sequential and random read/write benchmarks using dd/fio.

---

### Sparsify Disk

**Purpose**: Reclaim unused space in a QCOW2 image.

**Bash**: `kvm-disk-image.sh sparsify --source=/path/source.qcow2 --target=/path/compact.qcow2`

**Tool**: `virt-sparsify --format qcow2 source.qcow2 target.qcow2`

---

### Customize Disk

**Purpose**: Apply custom settings to a disk image.

**Bash**: `kvm-disk-image.sh customize --path=/path/disk.qcow2 --preallocation=metadata --compat=1.1`

---

### Backing Chain Management

**Python**:
```python
from kvm_backing_chain import BackingChainManager

bcm = BackingChainManager()
chain = bcm.get_chain("/var/lib/libvirt/images/overlay.qcow2")
# Returns: [base.qcow2, overlay.qcow2]

rebase_info = bcm.analyze_rebase("base.qcow2", "new_base.qcow2", "overlay.qcow2")
```

Manages QCOW2 backing file chains for snapshots and overlays.

---

### Disk Encryption

**Python**:
```python
from kvm_disk_encryption import DiskEncryption

de = DiskEncryption()
de.encrypt("/var/lib/libvirt/images/secret.qcow2", passphrase="my-secure-passphrase")
de.decrypt("/var/lib/libvirt/images/secret.qcow2", passphrase="my-secure-passphrase")
```

Supports LUKS encryption for disk images.

---

## Networking

### NAT Networking

**Default libvirt network (NAT)**:
```bash
# Start default network
virsh net-start default
virsh net-autostart default

# Create custom NAT network
kvm-network-bridge.sh create-nat --name=app-net --cidr=192.168.122.0/24 --gateway=192.168.122.1
```

DHCP is handled by libvirt's built-in dnsmasq.

---

### Routed Networking

**Bash**: `kvm-network-bridge.sh create-routed --name=routed-net --cidr=10.0.0.0/24 --gateway=10.0.0.1`

---

### Isolated Networking

**Bash**: `kvm-network-bridge.sh create-isolated --name=isolated-net --cidr=172.16.0.0/24`

No external connectivity. VMs on this network can only talk to each other.

---

### Bridge Networking

**Bash**: `kvm-network-bridge.sh create-bridge --name=br0 --interface=eth0 --cidr=192.168.1.100/24`

Connects VMs directly to the physical network.

---

### Open vSwitch

**Bash**: `kvm-ovs.sh create-switch --name=ovs-br0 --ports=eth0,eth1`

**Bash**: `kvm-ovs.sh add-port --bridge=ovs-br0 --port=vlan100 --tag=100`

**Bash**: `kvm-ovs.sh create-trunk --bridge=ovs-br0 --port=trunk0 --vlans=100,200,300`

---

### DHCP Configuration

**Bash**: `kvm-network-bridge.sh configure-dhcp --network=app-net --range=192.168.122.100-192.168.122.200`

---

### Network Filtering (nwfilter)

**Bash**: `kvm-network-bridge.sh nwfilter-create --name=allow-ssh --rule="tcp:22=ACCEPT"`

---

## Snapshots

### Internal Snapshots (QCOW2)

**Python**:
```python
from kvm_snapshot_manager import SnapshotManager

sm = SnapshotManager()
sm.create("web01", label="pre-upgrade")
sm.list("web01")
sm.revert("web01", label="pre-upgrade")
sm.delete("web01", label="old-snapshot")
```

**Bash**: `kvm-snapshot.sh create --name=dev-vm --label=pre-upgrade`

**Tool**: `virsh snapshot-create-as <domain> <name> "<description>"`

---

### External Snapshots

**Bash**: `kvm-snapshot.sh create-external --name=dev-vm --label=backup --memory-file=/var/lib/libvirt/saves/dev-vm-mem.save`

---

### Revert Snapshot

**Bash**: `kvm-snapshot.sh revert --name=dev-vm --label=pre-upgrade`

**Tool**: `virsh snapshot-revert <domain> <snapshot-name>`

---

### Delete Snapshot

**Bash**: `kvm-snapshot.sh delete --name=dev-vm --label=old-snapshot`

**Tool**: `virsh snapshot-delete <domain> <snapshot-name>`

---

### Commit Overlay

**Purpose**: Merge a snapshot overlay back into its backing file.

**Bash**: `kvm-snapshot.sh commit --name=dev-vm --label=daily`

**Tool**: `virsh blockcommit <domain> <disk> --active --wait`

---

## Backups

### Full Backup (Offline)

**Bash**: `kvm-backup.sh backup --name=dev-vm --output=/backup/dev-vm-full.qcow2`

**Method**: Shuts down VM, copies disk, starts VM.

---

### Incremental Backup

**Bash**: `kvm-backup.sh backup --name=dev-vm --output=/backup/dev-vm-incr.qcow2 --incremental --base=/backup/dev-vm-full.qcow2`

Uses QCOW2 bitmap-based incremental backups.

---

### Live Backup

**Bash**: `kvm-backup.sh backup --name=dev-vm --output=/backup/dev-vm-live.qcow2 --live`

**Method**: Creates external snapshot, backs up the active layer, merges back. VM stays running.

---

### Offline Backup

**Bash**: `kvm-backup.sh backup --name=dev-vm --output=/backup/dev-vm.qcow2 --offline`

**Method**: Stops VM, backs up, starts VM.

---

### Backup Restore

**Bash**: `kvm-backup-restore.sh restore --backup=/backup/dev-vm.qcow2 --name=dev-vm-restored`

---

## Performance Tuning

### Hugepages

**Python**:
```python
from kvm_performance import PerformanceManager

pm = PerformanceManager()
pm.enable_hugepages(vm_name="web01", size_mb=4096)
```

**Bash**: `kvm-performance-tune.sh hugepages --name=dev-vm --size=2048`

**Kernel parameter**: Add `transparent_hugepage=always` or configure static hugepages.

---

### CPU Pinning

**Python**:
```python
from kvm_cpu_pinning import CPUPinning

cp = CPUPinning()
cp.pin(vm_name="web01", vcpus={0: "0", 1: "1", 2: "2", 3: "3"})
cp.pin(vm_name="web01", vcpus="auto")  # Auto-distribute across physical CPUs
```

**Bash**: `kvm-performance-tune.sh cpu-pin --name=dev-vm --cpus=0-3`

---

### NUMA Topology

**Python**:
```python
from kvm_numa_topology import NUMATopology

numa = NUMATopology()
topology = numa.analyze()
numa.configure_vm("web01", topology)
```

**Bash**: `kvm-performance-tune.sh numa --name=dev-vm --nodes=0,1`

---

### I/O Tuning

**Bash**: `kvm-performance-tune.sh io-tune --name=dev-vm --cache=writeback --io=native --discard=unmap`

**Parameters**:
- `cache` — Cache mode: `none`, `writethrough`, `writeback`
- `io` — I/O mode: `native` (AIO), `threads`
- `discard` — Discard support: `unmap`, `ignore`

---

### Memory Ballooning

**Bash**: `kvm-performance-tune.sh balloon --name=dev-vm --min=1024 --max=8192`

Enables dynamic memory allocation via the virtio-balloon driver.

---

### Kernel Tuning

**Bash**: `kvm-performance-tune.sh kernel-tune --sysctl`

Applies sysctl settings for VM performance:
- `vm.swappiness=10`
- `vm.dirty_ratio=15`
- `vm.dirty_background_ratio=5`
- `net.core.somaxconn=65535`

---

## Passthrough

### GPU Passthrough

**Python**:
```python
from kvm_gpu_passthrough import GPUPassthrough

gpu = GPUPassthrough()
gpu.setup(pci_addr="01:00.0", vm_name="web01")
gpu.bind_vfio(pci_addr="01:00.0")
```

**Bash**: `kvm-passthrough.sh gpu --pci-addr=01:00.0 --vm-name=dev-vm`

**Steps**:
1. Enable IOMMU in kernel
2. Bind GPU to vfio-pci driver
3. Add hostdev element to domain XML
4. Start VM with GPU assigned

---

### PCI Passthrough

**Bash**: `kvm-passthrough.sh pci --pci-addr=03:00.0 --vm-name=dev-vm`

---

### USB Passthrough

**Bash**: `kvm-passthrough.sh usb --vendor=046d --product=c52b --vm-name=dev-vm`

---

### SR-IOV

**Python**:
```python
from kvm_sriov_passthrough import SRIOVManager

sriov = SRIOVManager()
sriov.create_vfs(pci_addr="01:00.0", count=4)
sriov.assign_vf(vm_name="web01", vf_pci="01:00.2")
```

**Bash**: `kvm-passthrough.sh sriov --pci-addr=01:00.0 --vfs=4 --vm-name=dev-vm`

---

## Cloud-Init

### Generate Cloud-Init ISO

**Python**:
```python
from kvm_cloudinit import CloudInitGenerator

ci = CloudInitGenerator()
ci.generate(
    vm_name="web01",
    hostname="web01.local",
    user="ubuntu",
    ssh_keys=["ssh-rsa AAAA..."],
    ip_config="192.168.1.100/24",
    gateway="192.168.1.1",
    dns="8.8.8.8",
    output="/var/lib/libvirt/images/web01-cidata.iso"
)
```

**Bash**: `kvm-cloudinit.sh create-iso --name=dev-vm --user=ubuntu --hostname=dev-vm.local --ip=192.168.1.100/24 --gateway=192.168.1.1`

---

### Attach Cloud-Init ISO

**Bash**: `kvm-cloudinit.sh attach --name=dev-vm --iso=/var/lib/libvirt/images/dev-vm-cidata.iso`

---

### Configure Cloud-Init

**Bash**: `kvm-cloudinit.sh configure --name=dev-vm --user=admin --ssh-key=~/.ssh/id_rsa.pub --password=changeme`

---

## QMP Direct Control

### Query VM Status

**Python**:
```python
from kvm_qmp_client import QMPClient

qmp = QMPClient("/var/run/libvirt/qemu/web01-monitor.sock")
status = qmp.query_status()
# Returns: {"status": "running", "running": true}
```

**Bash**: `kvm-qemu-direct.sh query --name=dev-vm --command="query-status"`

---

### Stop VM via QMP

**Bash**: `kvm-qemu-direct.sh stop --name=dev-vm`

---

### Migrate via QMP

**Bash**: `kvm-qemu-direct.sh migrate --name=dev-vm --dest=pve2 --uri=qemu+ssh://pve2/system`

---

### Snapshot via QMP

**Bash**: `kvm-qemu-direct.sh snapshot --name=dev-vm --label=qmp-snapshot`

---

### Query Block Devices

**Bash**: `kvm-qemu-direct.sh query --name=dev-vm --command="query-block"`

---

### Query CPUs

**Bash**: `kvm-qemu-direct.sh query --name=dev-vm --command="query-cpus-fast"`

---

## Nested Virtualization

### Enable Nested Virtualization

**Bash**: `kvm-nested-virt.sh enable`

**Actions**:
1. Loads `kvm_intel` or `kvm_amd` module with `nested=Y`
2. Verifies via `/sys/module/kvm_intel/parameters/nested`

---

### Verify Nested Virtualization

**Bash**: `kvm-nested-virt.sh verify`

**Check**: `cat /sys/module/kvm_intel/parameters/nested` → should return `Y` or `1`

---

## IOMMU Setup

### Enable IOMMU

**Bash**: `kvm-iommu-setup.sh enable --mode=intel` (or `amd`)

**Actions**:
1. Adds `intel_iommu=on` or `amd_iommu=on` to kernel boot parameters
2. Updates `/etc/default/grub`
3. Triggers `update-grub`
4. Warns about reboot requirement

---

### Verify IOMMU Groups

**Bash**: `kvm-iommu-setup.sh verify`

Lists all IOMMU groups and devices:
```
IOMMU Group 0: 00:00.0 Host bridge
IOMMU Group 1: 00:01.0 PCI bridge
...
```

---

### Blacklist Drivers

**Bash**: `kvm-iommu-setup.sh blacklist --drivers=nouveau,nvidia`

Prevents host from claiming devices intended for passthrough.

---

## Monitoring

### Domain Statistics

**Python**:
```python
from kvm_monitoring import DomainMonitor

monitor = DomainMonitor()
stats = monitor.get_stats("web01")
# Returns: {cpu_time, vcpu_stats, net_rx, net_tx, block_read, block_write, memory}
```

---

### Prometheus Export

**Python**:
```python
from kvm_monitoring import PrometheusExporter

exporter = PrometheusExporter(port=9100)
exporter.start()
# Exposes /metrics endpoint for all running domains
```

**Metrics exposed**:
- `kvm_vcpu_seconds_total` — CPU time per vCPU
- `kvm_memory_bytes` — Memory usage
- `kvm_network_receive_bytes_total` — Network bytes received
- `kvm_network_transmit_bytes_total` — Network bytes transmitted
- `kvm_block_read_bytes_total` — Disk read bytes
- `kvm_block_write_bytes_total` — Disk write bytes

---

### Health Check

**Bash**: `kvm-health-check.sh`

Checks:
- libvirtd service status
- Running domain count and status
- Storage pool availability
- Network status
- Disk usage
- Host load and memory
