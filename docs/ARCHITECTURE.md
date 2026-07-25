# Architecture — Pulsar

## Project Overview

**Pulsar** is a comprehensive, opinionated automation suite for managing Proxmox VE clusters and local KVM/libvirt hypervisors. It provides a unified CLI with a rich terminal UI, wrapping Proxmox REST API operations, libvirt management, Packer image builds, Terraform provisioning, and Ansible orchestration into a single coherent toolset.

### Goals

- **Unified interface**: A single `swissknife` binary and TUI that orchestrates all operations across Proxmox clusters and local KVM hosts. A REST API gateway (`apigateway`) enables web-based UIs and third-party integrations.
- **Multi-layered tooling**: Go CLIs for performance-critical paths, Python modules for complex logic and API integration, Bash scripts for direct node-level operations, and Terraform/Ansible/Packer for infrastructure-as-code workflows.
- **Resilience by default**: Retry logic, graceful degradation (paramiko fallback), dry-run mode, and comprehensive error handling at every layer.
- **Observability**: Structured logging (zerolog for Go, Python logging for scripts), Prometheus metrics, and multi-channel alerting (Slack, Telegram, email, ntfy, PagerDuty).
- **Testability**: Every module has a test path — Bats for Bash, pytest for Python, Go test for Go — with CI-ready configurations.

## ASCII Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        USER INTERFACE LAYER                             │
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────────┐  │
│  │  swissknife   │  │  pmxctl      │  │  kvmctl                      │  │
│  │  (TUI + CLI)  │  │  (Proxmox)   │  │  (KVM/libvirt)               │  │
│  │  Go/Bubbletea │  │  Go/Cobra    │  │  Go/Cobra                    │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬────────────────────┘  │
│         │                  │                      │                       │
│  ┌──────▼──────────────────▼──────────────────────▼──────────────────┐  │
│  │                    apigateway (REST API)                           │  │
│  │                    Go / net/http                                   │  │
│  │                    :8443 — JSON over HTTP                          │  │
│  └──────────┬─────────────────────────────────────────────────────────┘  │
│             │                                                            │
│  ┌──────────▼─────────────────────────────────────────────────────────┐  │
│  │  Web UI (SvelteKit SPA)                                            │  │
│  │  npm run dev → :5173 (proxies /api → :8443)                       │  │
│  │  npm run build → web/build/ (static files for production)          │  │
│  │  Pages: Dashboard, VMs, Nodes, Containers, Storage, Settings       │  │
│  └────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────┼──────────────────────────────────────────────┤
│                     EXECUTOR LAYER                                        │
│                            │                                              │
│  ┌─────────────────────────┼──────────────────────────────────────────┐  │
│  │              ┌──────────┴──────────┐                              │  │
│  │              │    config.Load()    │                              │  │
│  │              │  (viper + env +     │                              │  │
│  │              │   settings.yaml)    │                              │  │
│  │              └──────────┬──────────┘                              │  │
│  │                         │                                          │  │
│  │  ┌──────────────────────┼──────────────────────────────────┐      │  │
│  │  │                      │                                  │      │  │
│  │  ▼                      ▼                                  ▼      │  │
│  │  ┌──────────┐  ┌───────────────┐  ┌─────────────────────────┐   │  │
│  │  │ sshexec  │  │ proxmox.Client│  │ kvm.LibvirtClient       │   │  │
│  │  │ (Go)     │  │ (Go/HTTPS)    │  │ (Go/libvirt bindings)   │   │  │
│  │  │──────────│  │───────────────│  │─────────────────────────│   │  │
│  │  │ sshexec  │  │               │  │ kvm_vm_manager.py       │   │  │
│  │  │ (Python) │  │               │  │ kvm_disk_manager.py     │   │  │
│  │  │──────────│  │               │  │ kvm_snapshot_manager.py │   │  │
│  │  │ common.sh│  │               │  │ kvm_network_manager.py  │   │  │
│  │  │ (Bash)   │  │               │  │ kvm_backup.py           │   │  │
│  │  └────┬─────┘  └──────┬────────┘  │ kvm_performance.py      │   │  │
│  │       │               │            │ kvm_cpu_pinning.py      │   │  │
│  │       │               │            │ kvm_gpu_passthrough.py  │   │  │
│  │       │               │            │ kvm_sriov_passthrough.py│   │  │
│  │       │               │            │ kvm_cloudinit.py        │   │  │
│  │       │               │            │ kvm_qmp_client.py       │   │  │
│  │       │               │            │ kvm_monitoring.py       │   │  │
│  │       │               │            │ kvm_disk_encryption.py  │   │  │
│  │       │               │            │ kvm_backing_chain.py    │   │  │
│  │       │               │            │ kvm_numa_topology.py    │   │  │
│  │       │               │            │ kvm_vm_modify.py        │   │  │
│  │       │               │            │ kvm_vm_fleet_deploy.py  │   │  │
│  │       │               │            └────────────┬────────────┘   │  │
│  │       │               │                         │                │  │
│  └───────┼───────────────┼─────────────────────────┼────────────────┘  │
│          │               │                         │                    │
├──────────┼───────────────┼─────────────────────────┼────────────────────┤
│          │       SCRIPT/API LAYER                  │                    │
│          │               │                         │                    │
│  ┌───────┼───────────────┼─────────────────────────┼────────────────┐  │
│  │       │               │                         │                │  │
│  │  ┌────▼──────────┐  ┌─▼────────────────┐  ┌────▼────────────┐  │  │
│  │  │ proxmox/      │  │ proxmox/         │  │ kvm/            │  │  │
│  │  │ bash/         │  │ python/          │  │ bash/           │  │  │
│  │  │               │  │                  │  │                 │  │  │
│  │  │ pmx-vm-       │  │ pmx_backup_      │  │ kvm-vm-         │  │  │
│  │  │  lifecycle.sh │  │  manager.py      │  │  lifecycle.sh   │  │  │
│  │  │ pmx-ct-       │  │ pmx_ceph_        │  │ kvm-backup.sh   │  │  │
│  │  │  lifecycle.sh │  │  manager.py      │  │ kvm-snapshot.sh │  │  │
│  │  │ pmx-storage   │  │ pmx_cluster_     │  │ kvm-network-    │  │  │
│  │  │  .sh          │  │  manager.py      │  │  bridge.sh      │  │  │
│  │  │ pmx-backup-   │  │ pmx_cloudinit_   │  │ kvm-ovs.sh      │  │  │
│  │  │  restore.sh   │  │  manager.py      │  │ kvm-passthrough │  │  │
│  │  │ pmx-cluster   │  │ pmx_passthrough_ │  │  .sh            │  │  │
│  │  │  .sh          │  │  manager.py      │  │ kvm-performance │  │  │
│  │  │ pmx-ceph.sh   │  │ pmx_certificate_ │  │  -tune.sh       │  │  │
│  │  │ pmx-zfs.sh    │  │  manager.py      │  │ kvm-disk-image  │  │  │
│  │  │ pmx-ha.sh     │  │ pmx_bulk_        │  │  .sh            │  │  │
│  │  │ pmx-firewall  │  │  operations.py   │  │ kvm-cloudinit   │  │  │
│  │  │  .sh          │  │ pmx_capacity_    │  │  .sh            │  │  │
│  │  │ pmx-user-     │  │  report.py       │  │ kvm-qemu-direct │  │  │
│  │  │  acl.sh       │  │ pmx_alerting.py  │  │  .sh            │  │  │
│  │  │ pmx-snapshot  │  │ pmx_node_maint_  │  │ kvm-nested-     │  │  │
│  │  │  .sh          │  │  enance.py       │  │  virt.sh        │  │  │
│  │  │ pmx-template  │  │                  │  │ kvm-iommu-      │  │  │
│  │  │  .sh          │  │                  │  │  setup.sh       │  │  │
│  │  │ pmx-migration │  │                  │  │ kvm-health-     │  │  │
│  │  │  .sh          │  │                  │  │  check.sh       │  │  │
│  │  │ pmx-network   │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  │ pmx-sdn.sh    │  │                  │  │                 │  │  │
│  │  │ pmx-pbs-      │  │                  │  │                 │  │  │
│  │  │  integration  │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  │ pmx-pci-      │  │                  │  │                 │  │  │
│  │  │  passthrough  │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  │ pmx-gpu-      │  │                  │  │                 │  │  │
│  │  │  passthrough  │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  │ pmx-sriov.sh  │  │                  │  │                 │  │  │
│  │  │ pmx-cloudinit │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  │ pmx-health-   │  │                  │  │                 │  │  │
│  │  │  check.sh     │  │                  │  │                 │  │  │
│  │  │ pmx-node-     │  │                  │  │                 │  │  │
│  │  │  maintenance  │  │                  │  │                 │  │  │
│  │  │  .sh          │  │                  │  │                 │  │  │
│  │  └───────┬───────┘  └────────┬─────────┘  └────────┬────────┘  │  │
│  │          │                   │                      │            │  │
│  │  ┌───────▼───────────────────▼──────────────────────▼────────┐  │  │
│  │  │              SHARED UTILITIES                              │  │  │
│  │  │                                                           │  │  │
│  │  │  shared/bash/lib/common.sh    shared/go/sshexec/          │  │  │
│  │  │  (logging, env loading,       executor.go                 │  │  │
│  │  │   API call helper,            (SSH execution,             │  │  │
│  │  │   prerequisite checks,         parallel execution)        │  │  │
│  │  │   dry-run, confirm)                                        │  │  │
│  │  │                                                           │  │  │
│  │  │  shared/python/                                             │  │  │
│  │  │  ssh_executor.py (SSH with paramiko fallback)              │  │  │
│  │  │  notification.py  (Slack, Telegram, email, ntfy, PD)       │  │  │
│  │  │  health_check.py  (ping, SSH, disk, memory, load)          │  │  │
│  │  │  inventory_parser.py (YAML inventory with pydantic)        │  │  │
│  │  │  report_generator.py (Markdown, HTML, JSON reports)        │  │  │
│  │  └───────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
├───────────────────────────────────────────────────────────────────────┤
│                     INFRASTRUCTURE LAYER                              │
│                                                                       │
│  ┌───────────────────┐  ┌──────────────┐  ┌─────────────────────┐    │
│  │ packer/            │  │ proxmox/     │  │ tests/              │    │
│  │                    │  │ terraform/   │  │                     │    │
│  │ *.pkr.hcl          │  │ *.tf         │  │ bats/               │    │
│  │                    │  │              │  │ pytest/             │    │
│  │ Build golden       │  │ Provision    │  │ go test ./...       │    │
│  │ VM images          │  │ infra as     │  │                     │    │
│  │ (Ubuntu, Debian,   │  │ code         │  │ Automated test      │    │
│  │  Rocky, Windows)   │  │              │  │ suite               │    │
│  └───────────────────┘  └──────────────┘  └─────────────────────┘    │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                    TARGET INFRASTRUCTURE                        │  │
│  │                                                                 │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │  │
│  │  │ Proxmox  │  │  Local   │  │   PBS    │  │  Ceph / ZFS  │   │  │
│  │  │ VE 8+    │  │  KVM     │  │  Backup  │  │  Storage     │   │  │
│  │  │ Cluster  │  │  Hosts   │  │  Server  │  │              │   │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

## Module Map

### Go Binaries (`go/cmd/`)

| Binary | Source | Purpose |
|--------|--------|---------|
| `swissknife` | `go/cmd/swissknife/main.go` | Unified CLI + Bubble Tea TUI dashboard |
| `pmxctl` | `go/cmd/pmxctl/main.go` | Proxmox VE CLI — all cluster/node/VM operations |
| `kvmctl` | `go/cmd/kvmctl/main.go` | KVM/libvirt CLI — local hypervisor management |
| `apigateway` | `go/cmd/apigateway/main.go` | REST API gateway — HTTP/HTTPS JSON API wrapping the Proxmox client |

### Go Internal Packages (`go/internal/`)

| Package | Purpose |
|---------|---------|
| `apiserver` | REST API gateway — HTTP server, middleware (auth/CORS/logging/metrics), routing, and 40+ endpoint handlers |
| `config` | Configuration loading via viper (env, .env, settings.yaml, CLI flags) |
| `proxmox` | Proxmox REST API client (nodes, VMs, CTs, storage, cluster, HA, firewall, snapshots, migration, Ceph, ZFS) |
| `kvm` | libvirt domain management, QMP client, disk operations |
| `tui` | Bubble Tea components — dashboards, lists, forms, charts |
| `notify` | Go notification dispatcher (wraps shared/python/notification.py or native) |
| `logging` | Structured zerolog configuration |

### Go Shared Packages (`shared/go/`)

| Package | File | Purpose |
|---------|------|---------|
| `sshexec` | `executor.go` | SSH command execution with retry, parallel execution, script piping |

### Python Modules (`proxmox/python/`)

| Module | Purpose |
|--------|---------|
| `pmx_backup_manager.py` | Backup scheduling, retention, PBS integration |
| `pmx_ceph_manager.py` | Ceph cluster deployment and management |
| `pmx_cluster_manager.py` | Cluster join/leave, quorum operations |
| `pmx_cloudinit_manager.py` | Cloud-Init template management |
| `pmx_passthrough_manager.py` | GPU and PCI passthrough configuration |
| `pmx_certificate_manager.py` | TLS certificate lifecycle |
| `pmx_bulk_operations.py` | Batch operations across VMs |
| `pmx_capacity_report.py` | Capacity planning reports |
| `pmx_alerting.py` | Alert rule evaluation and dispatch |

### Python Modules (`kvm/python/`)

| Module | Purpose |
|--------|---------|
| `kvm_libvirt_client.py` | Low-level libvirt connection wrapper |
| `kvm_vm_manager.py` | VM lifecycle (create, start, stop, clone, modify, fleet deploy) |
| `kvm_vm_modify.py` | Runtime VM modification (CPU, RAM, disks) |
| `kvm_vm_fleet_deploy.py` | Bulk VM deployment from templates |
| `kvm_disk_manager.py` | Disk creation, conversion, resize, info |
| `kvm_disk_encryption.py` | LUKS disk encryption |
| `kvm_backing_chain.py` | QCOW2 backing chain management |
| `kvm_snapshot_manager.py` | Snapshot create/revert/delete/commit |
| `kvm_network_manager.py` | Virtual network management (NAT, bridge, OVS) |
| `kvm_performance.py` | Hugepages, CPU pinning, NUMA, I/O tuning |
| `kvm_cpu_pinning.py` | CPU affinity configuration |
| `kvm_numa_topology.py` | NUMA topology analysis and configuration |
| `kvm_gpu_passthrough.py` | GPU passthrough setup |
| `kvm_sriov_passthrough.py` | SR-IOV virtual function management |
| `kvm_backup.py` | VM backup and restore |
| `kvm_cloudinit.py` | Cloud-Init ISO generation |
| `kvm_qmp_client.py` | QMP socket direct control |
| `kvm_monitoring.py` | Domain statistics and Prometheus export |

### Shared Python Utilities (`shared/python/`)

| Module | Purpose |
|--------|---------|
| `ssh_executor.py` | SSH execution with native OpenSSH + paramiko fallback |
| `notification.py` | Multi-channel notifications (email, Slack, Telegram, ntfy, PagerDuty) |
| `health_check.py` | Host health checks (ping, SSH, disk, memory, load) |
| `inventory_parser.py` | YAML inventory parser with pydantic validation |
| `report_generator.py` | Markdown, HTML, and JSON report generation |

### Bash Scripts (`proxmox/bash/`)

| Script | Purpose |
|--------|---------|
| `pmx-vm-lifecycle.sh` | VM create, start, stop, shutdown, reboot, suspend, resume, delete, clone, rename |
| `pmx-ct-lifecycle.sh` | Container lifecycle operations |
| `pmx-storage.sh` | Storage pool management |
| `pmx-backup-restore.sh` | Backup, restore, list, verify, prune, schedule |
| `pmx-cluster.sh` | Cluster create, join, remove, status, quorum |
| `pmx-ha.sh` | High availability groups, resources, failover |
| `pmx-firewall.sh` | Firewall rules, ipsets, aliases, security groups |
| `pmx-user-acl.sh` | Users, groups, roles, ACLs, API tokens, TFA |
| `pmx-snapshot.sh` | VM snapshot create, list, rollback, delete |
| `pmx-template.sh` | Template management |
| `pmx-migration.sh` | Live/offline VM migration |
| `pmx-network.sh` | Bridge, bond, VLAN management |
| `pmx-sdn.sh` | Software-Defined Networking (VNet, zone, subnet) |
| `pmx-ceph.sh` | Ceph deploy, pools, OSDs, health, scrub |
| `pmx-zfs.sh` | ZFS pool, dataset, property, scrub, snapshots |
| `pmx-pbs-integration.sh` | Proxmox Backup Server operations |
| `pmx-pci-passthrough.sh` | PCI device passthrough |
| `pmx-gpu-passthrough.sh` | GPU passthrough |
| `pmx-sriov.sh` | SR-IOV configuration |
| `pmx-cloudinit.sh` | Cloud-Init operations |
| `pmx-health-check.sh` | Comprehensive cluster health check |
| `pmx-node-maintenance.sh` | Node enter/exit maintenance mode |

### Bash Scripts (`kvm/bash/`)

| Script | Purpose |
|--------|---------|
| `kvm-vm-lifecycle.sh` | Local KVM VM lifecycle |
| `kvm-backup.sh` | KVM VM backup |
| `kvm-backup-restore.sh` | KVM VM restore |
| `kvm-snapshot.sh` | KVM VM snapshots |
| `kvm-network-bridge.sh` | Network bridge management |
| `kvm-ovs.sh` | Open vSwitch management |
| `kvm-disk-image.sh` | Disk image creation and manipulation |
| `kvm-cloudinit.sh` | Cloud-Init ISO creation |
| `kvm-passthrough.sh` | PCI/GPU passthrough |
| `kvm-performance-tune.sh` | Performance tuning (hugepages, CPU, I/O) |
| `kvm-qemu-direct.sh` | Direct QEMU/QMP control |
| `kvm-nested-virt.sh` | Nested virtualization enable/verify |
| `kvm-iommu-setup.sh` | IOMMU configuration and verification |
| `kvm-health-check.sh` | KVM host health check |

### Packer Templates (`packer/`)

| Template | Target |
|----------|--------|
| `proxmox-ubuntu-2404.pkr.hcl` | Ubuntu 24.04 on Proxmox |
| `proxmox-debian-12.pkr.hcl` | Debian 12 on Proxmox |
| `proxmox-rocky-9.pkr.hcl` | Rocky Linux 9 on Proxmox |
| `proxmox-windows-2022.pkr.hcl` | Windows Server 2022 on Proxmox |
| `qemu-ubuntu-2404.pkr.hcl` | Ubuntu 24.04 via QEMU |
| `qemu-debian-12.pkr.hcl` | Debian 12 via QEMU |

### Terraform (`proxmox/terraform/`)

| File | Purpose |
|------|---------|
| `providers.tf` | Provider configuration |
| `variables.tf` | Input variables |
| `terraform.tfvars.example` | Example variable values |
| `versions.tf` | Version constraints |
| `outputs.tf` | Output values |

## Language Rationale

### Go — CLI and TUI Layer

**Why Go**: The CLIs (`swissknife`, `pmxctl`, `kvmctl`) are the primary user-facing interfaces. Go was chosen for:

1. **Single binary distribution**: No runtime dependencies; `make build` produces three self-contained executables.
2. **Performance**: SSH execution, API calls, and TUI rendering are latency-sensitive. Go's goroutines enable non-blocking TUI updates while background operations run.
3. **TUI ecosystem**: Bubble Tea and Lip Gloss provide a production-quality terminal UI framework with composability.
4. **CLI framework**: Cobra + Viper is the de facto standard for Go CLIs, providing flag parsing, subcommand routing, and config file integration.
5. **Concurrency**: Parallel SSH execution (`sshexec.ExecuteParallel`) uses goroutines with mutex-protected result maps.
6. **Type safety**: Strong typing catches configuration and API contract errors at compile time.

### Python — Complex Logic and API Integration

**Why Python**: The Python modules handle complex business logic that benefits from rapid iteration and rich library ecosystems:

1. **libvirt bindings**: The `libvirt` Python API is the most mature and well-documented interface for KVM management.
2. **Data validation**: Pydantic models (`inventory_parser.py`) provide typed validation for configuration schemas.
3. **HTTP/SMTP**: Python's `smtplib`, `urllib`, and optional `requests` make notification delivery straightforward.
4. **Rapid prototyping**: Complex operations like backing chain traversal (`kvm_backing_chain.py`), disk encryption, and NUMA topology analysis are easier to implement and iterate on in Python.
5. **Fallback resilience**: The SSH executor transparently falls back from native OpenSSH to `paramiko` when the `ssh` binary is unavailable.

### Bash — Direct Node Operations

**Why Bash**: The Bash scripts execute directly on Proxmox nodes and KVM hosts:

1. **Zero-dependency execution**: Proxmox nodes ship with bash, curl, and jq. No Python or Go installation required on target nodes.
2. **SSH script piping**: Scripts are read locally and executed remotely via `bash -s` through SSH, enabling zero-install remote execution.
3. **Dry-run support**: The `common.sh` library wraps every destructive operation with `--dry-run` support for safe testing.
4. **Proxmox CLI integration**: Many operations are simpler as thin wrappers around `pvesm`, `qm`, `pct`, `ceph`, `zfs`, and `corosync` CLI tools.
5. **Idempotent design**: Scripts check state before acting and report changes clearly.

### Terraform — Infrastructure Provisioning

**Why Terraform**: For repeatable infrastructure provisioning from CI/CD pipelines:

1. **State management**: Terraform tracks resource state, enabling drift detection and planned changes.
2. **CI/CD integration**: `terraform plan` and `terraform apply` fit naturally into pipeline stages.
3. **Proxmox provider maturity**: The `bpg/proxmox` provider is well-maintained and supports the full Proxmox API.

### Packer — Image Building

**Why Packer**: For building golden VM images:

1. **Reproducible builds**: HCL2 templates produce identical images every time.
2. **Multi-platform**: Templates exist for both Proxmox-native and QEMU-based image builds.
3. **Pre-installed software**: Golden images include all required packages, reducing boot-time provisioning.

### Ansible — Configuration Management

**Why Ansible**: For post-deployment configuration and hardening:

1. **Idempotent roles**: Roles can be re-run safely to enforce desired state.
2. **No agent required**: SSH-based execution means no agent installation on targets.
3. **Variable-driven**: Host-specific configuration is driven by inventory variables.

## Data Flow Diagrams

### VM Create Flow

```
User CLI Input
      │
      ▼
┌─────────────┐
│  swissknife  │  or  pmxctl vm create  or  pmx-vm-lifecycle.sh create
│  (TUI form)  │
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│  Load Configuration  │  config.Load() reads env → .env → settings.yaml → defaults
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│  Validate Parameters │  Check required fields, node exists, storage exists
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐     ┌────────────────────────────────┐
│  Acquire next VMID   │────▶│ GET /cluster/resources          │
│  (auto-assign)       │◀────│ → find max(qemu.vmid) + 1      │
└──────┬───────────────┘     └────────────────────────────────┘
       │
       ▼
┌──────────────────────┐     ┌────────────────────────────────┐
│  Create VM           │────▶│ POST /nodes/{node}/qemu         │
│                      │◀────│   {vmid, name, cores, memory,  │
│                      │     │    scsihw, bios, machine,       │
│                      │     │    ide2 (ISO), boot order}      │
└──────┬───────────────┘     └────────────────────────────────┘
       │
       ├── If Cloud-Init specified:
       │   ┌──────────────────────┐
       │   │ POST /nodes/{node}/  │
       │   │   qemu/{vmid}/config │  Apply cloud-init user-data
       │   └──────────────────────┘
       │
       ├── If --template specified:
       │   ┌──────────────────────┐
       │   │ POST /nodes/{node}/  │
       │   │   qemu/{vmid}/clone  │  Clone from template instead
       │   └──────────────────────┘
       │
       ▼
┌──────────────────────┐
│  Notify (optional)   │  Slack / Telegram / email on success/failure
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│  Log + Print Result  │  Structured log entry, TUI status update
└──────────────────────┘
```

### Backup Flow

```
Backup Trigger (CLI / Cron / TUI action)
      │
      ▼
┌──────────────────────────┐
│  pmx-backup-restore.sh   │  or  pmx_backup_manager.py  or  pmxctl backup
│  backup --vmid=X         │
│  --storage=Y --mode=Z    │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│  Validate inputs         │  VM exists? Storage accessible? Mode valid?
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐     ┌─────────────────────────────────────┐
│  Initiate backup job     │────▶│ POST /nodes/{node}/qemu/{vmid}/backup│
│                          │◀────│   {storage, mode, compress}          │
│                          │     │ Returns UPID for tracking            │
└──────────┬───────────────┘     └─────────────────────────────────────┘
           │
           ▼
┌──────────────────────────┐
│  Monitor backup UPID     │  Poll job status until complete
│  (optional async)        │
└──────────┬───────────────┘
           │
           ├── If PBS integration:
           │   ┌────────────────────────────┐
           │   │ PBS API: datastore prune   │  Apply retention policy
           │   │ according to keep-daily,   │  on PBS side
           │   │ keep-weekly, keep-monthly  │
           │   └────────────────────────────┘
           │
           ▼
┌──────────────────────────┐
│  Notification on         │  Success → info alert
│  completion              │  Failure → critical alert (PagerDuty/Slack)
└──────────────────────────┘
```

### API Gateway Data Flow

```
HTTP Request (REST client — curl, web UI, monitoring system)
       │
       ▼
┌──────────────────────┐
│  X-API-Key / Bearer  │  Auth middleware (optional)
│  token validation    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│  Logging + Request   │  zerolog structured log + X-Request-ID header
│  ID middleware        │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│  Route dispatch      │  Go 1.22+ ServeMux pattern matching
│  GET /api/v1/...     │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐     ┌────────────────────────────────┐
│  Handler (wrapped)   │────▶│ proxmox.Client.Get/Post/Put/   │
│                      │◀────│ Delete → Proxmox VE API        │
│  Return (data, err)  │     │                                │
│  or writeError()      │     │ - Zero retry logic (delegated) │
│                      │     │ - Context timeout from request  │
└──────┬───────────────┘     └────────────────────────────────┘
       │
       ▼
┌──────────────────────┐
│  JSON APIResponse    │  {success: true, data: ..., error: ...}
│  + Prometheus metric │  request_count, duration, active_requests
└──────────────────────┘
```

**Available endpoint groups:**

| Group | Prefix | Examples |
|-------|--------|---------|
| Health | `GET /api/v1/health` | Liveness check |
| Cluster | `GET /api/v1/cluster/...` | status, resources, log, options |
| Nodes | `GET /api/v1/nodes/...` | list, status, services, network |
| VMs | `GET/POST/DELETE /api/v1/vms/...` | CRUD, start, stop, shutdown, clone, resize, migrate, config, monitor |
| Snapshots | `GET/POST/DELETE /api/v1/vms/{vmid}/snapshots/...` | list, create, delete, rollback |
| Containers | `GET/POST/DELETE /api/v1/containers/...` | CRUD, start, stop, shutdown |
| Storage | `GET/POST/DELETE /api/v1/storage/...` | list, content, add, remove |
| Pools | `GET/POST/DELETE /api/v1/pools/...` | list, create, delete |
| Backups | `GET/POST /api/v1/backups/...` | list, backup now |
| Firewall | `GET/POST /api/v1/nodes/{node}/firewall/rules` | list, add rule |
| HA | `GET/POST /api/v1/ha/...` | groups, resources |
| Metrics | `GET /api/v1/metrics/...` | node, cluster aggregation |
| Prometheus | `GET /metrics` | Scrape endpoint |

```
Migration Request (CLI / TUI)
      │
      ▼
┌──────────────────────────┐
│  pmx-migration.sh        │  or  pmxctl migration vm {vmid} {target}
│  migrate --vmid=X        │
│  --target=Y --online     │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│  Pre-flight checks       │
│  - Source node online?   │
│  - Target node online?   │
│  - Storage accessible    │
│    from both nodes?      │
│  - CPU compatibility?    │
│  - Sufficient resources  │
│    on target?            │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐     ┌──────────────────────────────────────┐
│  Check migration type    │────▶│ Online: shared storage → live migrate │
│                          │     │ Online: local storage  → live +      │
│                          │     │          disk copy (slower)          │
│                          │     │ Offline: stop → copy → start on      │
│                          │     │          target                       │
└──────────┬───────────────┘     └──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────┐     ┌──────────────────────────────────────┐
│  Execute migration       │────▶│ POST /nodes/{source}/qemu/{vmid}/    │
│                          │     │   migrate {target}                    │
│                          │◀────│   ?online=1                          │
│                          │     │ Returns UPID for tracking             │
└──────────┬───────────────┘     └──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────┐
│  Monitor migration       │  Poll UPID status
│  (may take minutes to    │
│   hours for large VMs)   │
└──────────┬───────────────┘
           │
           ├── On failure: see docs/RUNBOOKS/failed-migration.md
           │
           ▼
┌──────────────────────────┐
│  Post-migration verify   │
│  - VM running on target? │
│  - Network connectivity? │
│  - Storage mounted?      │
│  - Remove from source    │
│    (if full migration)   │
└──────────────────────────┘
```

## Security Architecture

### API Tokens

Proxmox API authentication uses token-based authentication:

1. **Token generation**: Tokens are created in the Proxmox web UI under Datacenter → Permissions → API Tokens.
2. **Token format**: `{user}@realm!{tokenid}` with a separate secret value.
3. **Storage**: Tokens and secrets are stored in environment variables (`PMX_API_TOKEN`, `PMX_TOKEN_ID`, `PMX_TOKEN_SECRET`) or `.env` files, never in version control.
4. **Principle of least privilege**: Tokens should be scoped to the minimum required permissions (e.g., `PVEAuditor` for read-only monitoring, `PVEVMAdmin` for VM operations).
5. **Rotation**: Rotate tokens periodically and after any personnel changes.

### Secrets Management

- **Environment variables**: Primary mechanism. The `.env` file is loaded by `load_env()` in `common.sh` and by viper in Go binaries.
- **`.env` exclusion**: The `.gitignore` file excludes `.env` from version control.
- **No secrets in code**: API tokens, passwords, and webhook URLs are never hardcoded.
- **PBS tokens**: PBS API tokens follow the `PBSAPIToken=TokenName:TokenValue` format and are stored in `PBS_TOKEN`.
- **SSH keys**: Referenced via `SSH_KEY_PATH`, never embedded. The SSH executor passes keys to the `ssh` binary via `-i` flag.
- **SMTP credentials**: Stored in env vars (`SMTP_FROM`, `SMTP_TO`) or settings.yaml, prefer env vars over file-based storage.

### Encryption

- **Disk encryption**: `kvm_disk_encryption.py` supports LUKS encryption for QCOW2 and raw disk images.
- **Transport**: All Proxmox API calls use HTTPS (port 8006). PBS API calls use HTTPS (port 8007). SSH uses encrypted transport by design.
- **TLS certificates**: `pmx_certificate_manager.py` manages TLS certificate lifecycle for Proxmox and PBS endpoints.

### Dry-Run Mode

Every Bash script supports `--dry-run` (or `DRY_RUN=true` env var):

- Commands are printed but not executed.
- API calls are logged but not sent.
- The `dry_run()` wrapper in `common.sh` intercepts all destructive operations.
- The TUI shows a visual indicator when dry-run is active.

### Execution Safety

- **Confirmation prompts**: Destructive operations (delete VM, purge backup) require explicit `y/N` confirmation via the `confirm()` helper.
- **Root checks**: Scripts that require root call `check_root()` and exit immediately if not running as root.
- **Prerequisite validation**: `check_prereqs` ensures required tools (curl, jq, ssh) are installed before proceeding.

## Configuration Hierarchy

Configuration is loaded with the following precedence (highest priority wins):

```
┌─────────────────────────────────────────────────────┐
│  1. CLI Flags (--api-url, --node, etc.)              │  ← Highest priority
│     Set directly on the command line                  │
├─────────────────────────────────────────────────────┤
│  2. Environment Variables                            │
│     PMX_API_URL, PMX_USER, PMX_API_TOKEN,            │
│     PMX_API_TOKEN_SECRET, PMX_NODE, SSH_USER, etc.   │
│     Loaded from shell environment and .env file       │
├─────────────────────────────────────────────────────┤
│  3. .env File                                        │
│     Loaded by load_env() (Bash) or viper (Go)        │
│     Located in project root or $HOME                  │
├─────────────────────────────────────────────────────┤
│  4. settings.yaml (config/settings.yaml)             │
│     Central configuration file with all defaults      │
│     Supports settings.local.yaml overrides            │
├─────────────────────────────────────────────────────┤
│  5. User Config File                                 │
│     Go CLIs: $HOME/.pmxctl.yaml or $HOME/.kvmctl.yaml│
│     TUI: ~/.config/swissknife/config.yaml            │
├─────────────────────────────────────────────────────┤
│  6. Hardcoded Defaults                                │  ← Lowest priority
│     Sensible defaults in source code                  │
│     (node: pve1, storage: local-lvm, bridge: vmbr0)  │
└─────────────────────────────────────────────────────┘
```

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| `.env` | Project root | API tokens, notification webhooks, SSH keys |
| `config/settings.yaml` | Project root | Global defaults for all operations |
| `config/settings.local.yaml` | Project root (gitignored) | Local overrides for settings.yaml |
| `~/.pmxctl.yaml` | User home | pmxctl-specific config overrides |
| `~/.kvmctl.yaml` | User home | kvmctl-specific config overrides |
| `~/.config/swissknife/config.yaml` | User home | TUI preferences (theme, refresh, default view) |

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `PMX_API_URL` | Proxmox API endpoint | Yes (Proxmox ops) |
| `PMX_USER` | Authentication user | Yes (Proxmox ops) |
| `PMX_TOKEN_ID` | API token identifier | Yes (Proxmox ops) |
| `PMX_TOKEN_SECRET` | API token secret | Yes (Proxmox ops) |
| `PMX_NODE` | Default Proxmox node | Yes (Proxmox ops) |
| `LIBVIRT_URI` | libvirt connection URI | For KVM ops |
| `SSH_USER` | SSH username | No |
| `SSH_KEY_PATH` | SSH private key path | No |
| `PBS_API_URL` | PBS API endpoint | For PBS ops |
| `PBS_TOKEN` | PBS API token | For PBS ops |
| `SLACK_WEBHOOK_URL` | Slack webhook | For Slack alerts |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | For Telegram alerts |
| `TELEGRAM_CHAT_ID` | Telegram chat ID | For Telegram alerts |
| `SMTP_HOST` | SMTP server | For email alerts |
| `SMTP_PORT` | SMTP port | For email alerts |
| `SMTP_FROM` | Sender email | For email alerts |
| `SMTP_TO` | Recipient email | For email alerts |
| `NTFY_URL` | ntfy topic URL | For ntfy alerts |
| `LOG_LEVEL` | Logging verbosity | No (default: info) |
| `DRY_RUN` | Dry-run mode | No (default: false) |

## Directory Structure

```
pulsar/
│
├── config/                          # Configuration files
│   ├── settings.yaml                #   Global settings with all options documented
│   └── templates/                   #   Variable templates for Packer/Terraform
│
├── docs/                            # Documentation
│   ├── ARCHITECTURE.md              #   This file
│   ├── PROXMOX_OPERATIONS.md        #   Complete Proxmox operations reference
│   ├── KVM_OPERATIONS.md            #   Complete KVM/libvirt operations reference
│   ├── TUI.md                       #   TUI user guide
│   └── RUNBOOKS/                    #   Operational runbooks
│       ├── node-failure.md          #     Node failure recovery
│       ├── storage-full.md          #     Storage full recovery
│       ├── failed-migration.md      #     Migration failure recovery
│       ├── ceph-recovery.md         #     Ceph issue recovery
│       ├── backup-recovery.md       #     Backup restore procedures
│       └── split-brain.md           #     Cluster split-brain recovery
│
├── web/                             # SvelteKit web UI
│   ├── src/                         #   Components, pages, API client library
│   │   ├── lib/
│   │   │   ├── api/client.ts        #     API client (talks to apigateway)
│   │   │   └── components/          #     Sidebar, Topbar, StatusBadge
│   │   └── routes/                  #     SvelteKit pages (Dashboard, VMs, Nodes, Containers, Storage, Settings)
│   ├── static/                      #   Static assets
│   ├── build/                       #   Production build output
│   ├── package.json
│   ├── svelte.config.js
│   └── vite.config.ts               #   Dev proxy /api → :8443
│
├── go/                              # Go source code
│   ├── cmd/                         #   CLI & server entry points
│   │   ├── swissknife/main.go       #     Unified CLI + TUI
│   │   ├── pmxctl/main.go           #     Proxmox control CLI
│   │   ├── kvmctl/main.go           #     KVM control CLI
│   │   └── apigateway/main.go       #     REST API gateway
│   ├── internal/                    #   Internal packages (not importable)
│   │   ├── apiserver/               #     API gateway server, handlers, types, middleware
│   │   ├── config/                  #     Configuration loader (viper)
│   │   ├── proxmox/                 #     Proxmox REST API client
│   │   ├── kvm/                     #     libvirt/libkvm client
│   │   ├── tui/                     #     Bubble Tea TUI components
│   │   ├── notify/                  #     Notification dispatcher
│   │   └── logging/                 #     Structured logging
│   ├── pkg/                         #   Public reusable packages
│   ├── go.mod                       #   Go module definition
│   ├── go.sum                       #   Module checksums
│   ├── Makefile                     #   Go-specific build targets
│   └── .golangci-lint.yml           #   Linter configuration
│
├── kvm/                             # KVM/libvirt helper scripts and modules
│   ├── python/                      #   Python modules for KVM management
│   │   ├── kvm_libvirt_client.py    #     libvirt connection wrapper
│   │   ├── kvm_vm_manager.py        #     VM lifecycle management
│   │   ├── kvm_disk_manager.py      #     Disk operations
│   │   ├── kvm_snapshot_manager.py  #     Snapshot management
│   │   ├── kvm_network_manager.py   #     Network management
│   │   ├── kvm_performance.py       #     Performance tuning
│   │   ├── kvm_backup.py            #     Backup operations
│   │   ├── requirements.txt         #     Python dependencies
│   │   └── ... (15+ modules)
│   └── bash/                        #   Bash scripts for KVM operations
│       ├── kvm-vm-lifecycle.sh      #     VM lifecycle
│       ├── kvm-backup.sh            #     Backup
│       ├── kvm-snapshot.sh          #     Snapshots
│       ├── kvm-passthrough.sh       #     Device passthrough
│       ├── kvm-performance-tune.sh  #     Performance tuning
│       └── ... (14 scripts)
│
├── proxmox/                         # Proxmox-specific tools
│   ├── bash/                        #   Bash scripts for Proxmox operations
│   │   ├── pmx-vm-lifecycle.sh      #     VM lifecycle
│   │   ├── pmx-ct-lifecycle.sh      #     Container lifecycle
│   │   ├── pmx-backup-restore.sh    #     Backup/restore
│   │   ├── pmx-cluster.sh           #     Cluster management
│   │   ├── pmx-ceph.sh              #     Ceph storage
│   │   ├── pmx-zfs.sh               #     ZFS storage
│   │   ├── pmx-ha.sh                #     High availability
│   │   └── ... (16 scripts)
│   ├── python/                      #   Python modules for Proxmox
│   │   ├── pmx_backup_manager.py    #     Backup management
│   │   ├── pmx_ceph_manager.py      #     Ceph management
│   │   ├── pmx_cluster_manager.py   #     Cluster management
│   │   └── ... (9 modules)
│   └── terraform/                   #   Terraform IaC
│       ├── providers.tf
│       ├── variables.tf
│       ├── versions.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
│
├── shared/                          # Shared utilities
│   ├── bash/lib/common.sh           #   Bash library (logging, API, dry-run, etc.)
│   ├── go/sshexec/executor.go       #   Go SSH execution library
│   └── python/                      #   Shared Python utilities
│       ├── ssh_executor.py          #     SSH with paramiko fallback
│       ├── notification.py          #     Multi-channel notifications
│       ├── health_check.py          #     Host health checks
│       ├── inventory_parser.py      #     YAML inventory parser
│       ├── report_generator.py      #     Report generation
│       └── requirements.txt         #     Python dependencies
│
├── packer/                          # Packer image templates
│   ├── proxmox-ubuntu-2404.pkr.hcl
│   ├── proxmox-debian-12.pkr.hcl
│   ├── proxmox-rocky-9.pkr.hcl
│   ├── proxmox-windows-2022.pkr.hcl
│   ├── qemu-ubuntu-2404.pkr.hcl
│   └── qemu-debian-12.pkr.hcl
│
├── tests/                           # Test suites
│   ├── bats/                        #   Bash integration tests
│   │   └── pmx-vm-lifecycle.bats    #     VM lifecycle test cases
│   ├── pytest/                      #   Python unit tests
│   └── go/                          #   Go test suite
│
├── .env.example                     # Environment variable template
├── .gitignore                       # Git ignore rules
├── Makefile                         # Build and task automation
├── CHANGELOG.md                     # Release changelog
├── LICENSE                          # MIT License
└── README.md                        # Project overview
```

## Dependency Graph Between Modules

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DEPENDENCY GRAPH                            │
│                                                                     │
│  swissknife ──────┬──── tui (Bubble Tea)                           │
│                   ├── config (viper)                                │
│                   ├── proxmox client (internal)                     │
│                   └── kvm client (internal)                         │
│                                                                     │
│  apigateway ───────┬──── apiserver (internal)                      │
│                    ├── proxmox client (internal)                    │
│                    ├── config (viper)                               │
│                    ├── prometheus (external)                        │
│                    └── zerolog (external)                           │
│                                                                     │
│  Web UI (SvelteKit) ─── apigateway (REST API via HTTP proxy)      │
│                                                                     │
│  pmxctl ──────────┬──── proxmox client (internal)                  │
│                   ├── config (viper)                                │
│                   └── sshexec (shared/go)                           │
│                                                                     │
│  kvmctl ──────────┬──── kvm client (internal)                       │
│                   ├── config (viper)                                │
│                   └── sshexec (shared/go)                           │
│                                                                     │
│  Proxmox bash scripts ─── common.sh (shared/bash)                   │
│  (pmx-*.sh)        ├── curl + jq (external)                        │
│                    └── Proxmox API (remote)                         │
│                                                                     │
│  KVM bash scripts ──────── common.sh (shared/bash)                  │
│  (kvm-*.sh)         ├── virsh / qemu-img (external)                │
│                    └── libvirt socket (local)                       │
│                                                                     │
│  Proxmox Python modules ── ssh_executor.py (shared/python)          │
│  (pmx_*.py)         ├── notification.py (shared/python)             │
│                    └── Proxmox API (remote)                         │
│                                                                     │
│  KVM Python modules ────── libvirt Python bindings                   │
│  (kvm_*.py)          ├── kvm_libvirt_client.py                      │
│                    └── libvirt socket (local)                       │
│                                                                     │
│  All Python modules ──────── Optional: pydantic, requests            │
│                         (graceful fallback if absent)                │
│                                                                     │
│  Packer templates ────── packer (external)                           │
│                    └── Proxmox API or QEMU (remote/local)           │
│                                                                     │
│  Terraform configs ────── terraform + bpg/proxmox provider           │
│                    └── Proxmox API (remote)                         │
│                                                                     │
│  Test suites ──────────── bats / pytest / go test                    │
│                    └── Mock binaries for offline testing             │
└─────────────────────────────────────────────────────────────────────┘
```

### Dependency Rules

1. **Shared modules are leaf dependencies**: `common.sh`, `ssh_executor.py`, `notification.py`, `health_check.py` have no inbound dependencies from other project modules.
2. **Bash scripts only depend on shared/bash**: Each `pmx-*.sh` or `kvm-*.sh` sources `common.sh` and uses only external system tools (curl, jq, virsh, etc.).
3. **Python modules may depend on shared/python**: A `kvm_*.py` module can import from `shared/python/` but not from `proxmox/python/`.
4. **Go internal packages are not importable**: The `internal/` directory prevents external packages from depending on implementation details.
5. **Terraform and Packer are standalone**: They interact with infrastructure directly via their respective providers, not through the project's own code.

## Test Infrastructure

| Framework | Location | Coverage |
|-----------|----------|----------|
| Bats | `tests/bats/` | Bash script integration tests with mock API responses |
| pytest | `tests/pytest/` | Python module unit tests |
| Go test | `tests/go/` and inline `*_test.go` | Go package unit tests with race detection |

### Test Patterns

- **Mock APIs**: Bats tests create temporary mock scripts that return JSON, injected via `$PATH` precedence.
- **Dry-run validation**: Tests verify that `--dry-run` mode never executes destructive operations.
- **Error path coverage**: Tests verify behavior when required arguments are missing, API calls fail, and prerequisites are not met.
- **Parallel execution**: Go tests use `-race` flag; Python tests can use `pytest-xdist`.

### Running Tests

```bash
make test           # Run all test suites
make test-go        # Go tests only
make test-py        # Python tests only
make test-bats      # Bats tests only
make lint           # All linters
```
