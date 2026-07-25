# MASTER PROMPT — Proxmox VE & KVM Full Automation Suite + TUI Swiss-Knife

You are a senior infrastructure automation engineer. Generate a **production-grade, fully commented, modular** automation suite that covers **every realistic administrative and operational task** for:

1. **Proxmox VE 8.x+** (Debian-based, API v2, `pve-cluster`, `pvedaemon`, `pveproxy`)
2. **Generic KVM / libvirt / QEMU** (any distro: RHEL, Ubuntu, Arch, Fedora, Alpine)

The project must be fully modular, well-documented, and culminate in a single TUI application that orchestrates everything.

---

## 0. GLOBAL RULES

| # | Rule |
|---|------|
| R1 | Every script must be **idempotent** where possible. |
| R2 | Every script must include a `--help` / `-h` flag with full usage block. |
| R3 | Every script must validate prerequisites (installed packages, root/sudo, API token, etc.) before running. |
| R4 | Every script must log to both stdout AND to `/var/log/pulsar/<module>.log` (rotating). |
| R5 | Every script must support `--dry-run` where destructive actions are involved. |
| R6 | Secrets (API tokens, passwords) must **never** be hardcoded — use env vars, `.env` files, or a vault reference. |
| R7 | All Python code must target **Python 3.12+**, use `type hints`, and include a `requirements.txt` per module. |
| R8 | All Go code must target **Go 1.22+**, use modules, and include a `Makefile`. |
| R9 | All Ansible playbooks must be **Ansible 2.16+** compatible, use FQCNs, and include an `ansible.cfg` + `inventory.example`. |
| R10 | All Bash scripts must pass `shellcheck` with zero warnings (`set -euo pipefail`). |
| R11 | Every file must start with an SPDX license header (MIT). |
| R12 | Provide a top-level `README.md` with directory tree, quickstart, and per-module docs. |
| R13 | Return proper exit codes (0=ok, 1=error, 2=misuse, 3=partial-failure). |
| R14 | Include a header comment block: PURPOSE, AUTHOR, DEPS, PROXMOX\|KVM\|SHARED tag. |

---

## 1. ARCHITECTURAL RULES

### 1.1 Separation of Concerns

| Directory | Purpose |
|-----------|---------|
| `/proxmox/` | Scripts using Proxmox API (`/api2/json`), CLIs (`qm`, `pct`, `pvesm`, `pveceph`, `pveum`, `ha-manager`, `pvecm`), or config (`/etc/pve/`). |
| `/kvm/` | Scripts working on ANY KVM/QEMU host (libvirt, `virsh`, `virt-install`, `qemu-img`, `qemu-system-x86_64`, libguestfs, OVMF/UEFI, vhost-net, SR-IOV via sysfs). **NO Proxmox dependencies.** |
| `/shared/` | Utilities usable by **both** Proxmox and raw KVM: SSH executors, network helpers, disk benchmarks, generic log parsers, notification senders, inventory parsers. |
| `/packer/` | Golden-image / template baking (QEMU builder for KVM, Proxmox builder for PVE). |
| `/terraform/` | Infrastructure-as-Code for Proxmox VMs/CTs, network definitions, DNS records. |
| `/tui/` | The Go TUI application. |
| `/tests/` | BATS (bash), pytest (Python), Go tests. |
| `/docs/` | Architecture, operation guides, runbooks. |

### 1.2 Proxmox vs KVM Distinction

| Aspect | Proxmox-Specific | Generic KVM |
|--------|-----------------|-------------|
| API | REST API v2 (`/api2/json`) | libvirt XML + virsh |
| VM mgmt | `qm` | `virsh`, `virt-install` |
| CT mgmt | `pct` (LXC) | N/A (KVM has no native CT) |
| Storage | `pvesm`, Ceph/ZFS integrated | `virsh pool-*`, `qemu-img` |
| Cluster | `pvecm`, corosync | N/A (libvirt has no cluster) |
| HA | `ha-manager` | N/A (use external: Pacemaker) |
| Firewall | `pve-firewall` | `nwfilter`, iptables/nftables |
| Backup | `vzdump`, PBS | `virsh snapshot`, external tools |
| Users | `pveum`, realms | N/A (OS-level) |
| Network | `/etc/network/interfaces`, SDN | `virsh net-*`, OVS, bridge-utils |
| Passthrough | Proxmox GUI + `hostpci` | `hostdev` in domain XML |
| Cloud-Init | `qm cloudinit` | `cloud-localds` + attach |
| QMP | Indirect via API | Direct QMP socket control |

---

## 2. DIRECTORY STRUCTURE (create exactly this)

```
pulsar/
├── README.md
├── LICENSE
├── .env.example
├── .gitignore
├── Makefile                            # build, test, lint, install, clean, tui, packer-build, ansible-check
├── config/
│   ├── settings.yaml                   # global config (API endpoints, defaults, thresholds, themes)
│   ├── inventory/                      # Ansible inventories (YAML)
│   └── templates/                      # Jinja2, cloud-init, kickstart, Packer HCL
│
├── shared/                             # ── SHARED UTILITIES ──
│   ├── bash/
│   │   └── lib/
│   │       └── common.sh              # logging, colors, prereqs, .env loading, dry-run, jq, curl wrapper
│   ├── python/
│   │   ├── ssh_executor.py            # remote command execution (paramiko / subprocess ssh)
│   │   ├── inventory_parser.py        # parse YAML host/VM inventory
│   │   ├── notification.py            # email, Slack, Telegram, ntfy.sh, webhook, PagerDuty
│   │   ├── report_generator.py        # Markdown / HTML / PDF reports
│   │   └── health_check.py            # ping, SSH, port, disk, memory, load → JSON
│   └── go/
│       └── sshexec/
│           └── executor.go
│
├── proxmox/                            # ── PROXMOX-SPECIFIC ──
│   ├── bash/
│   │   ├── pmx-vm-lifecycle.sh
│   │   ├── pmx-ct-lifecycle.sh
│   │   ├── pmx-storage.sh
│   │   ├── pmx-backup-restore.sh
│   │   ├── pmx-cluster.sh
│   │   ├── pmx-ha.sh
│   │   ├── pmx-firewall.sh
│   │   ├── pmx-user-acl.sh
│   │   ├── pmx-snapshot.sh
│   │   ├── pmx-template.sh
│   │   ├── pmx-migration.sh
│   │   ├── pmx-ceph.sh
│   │   ├── pmx-zfs.sh
│   │   ├── pmx-pbs-integration.sh
│   │   ├── pmx-node-maintenance.sh
│   │   ├── pmx-network.sh
│   │   ├── pmx-sdn.sh
│   │   ├── pmx-gpu-passthrough.sh
│   │   ├── pmx-pci-passthrough.sh
│   │   ├── pmx-sriov.sh
│   │   ├── pmx-cloudinit.sh
│   │   ├── pmx-network-diagnostics.sh
│   │   └── pmx-health-check.sh
│   ├── python/
│   │   ├── requirements.txt
│   │   ├── pve_api_client.py          # full Proxmox REST API wrapper (auth, retry, rate-limit, connection pool)
│   │   ├── pmx_vm_manager.py
│   │   ├── pmx_ct_manager.py
│   │   ├── pmx_storage_manager.py
│   │   ├── pmx_backup_manager.py
│   │   ├── pmx_cluster_manager.py
│   │   ├── pmx_ha_manager.py
│   │   ├── pmx_firewall_manager.py
│   │   ├── pmx_user_acl_manager.py
│   │   ├── pmx_snapshot_manager.py
│   │   ├── pmx_migration_manager.py
│   │   ├── pmx_ceph_manager.py
│   │   ├── pmx_zfs_manager.py
│   │   ├── pmx_pbs_manager.py
│   │   ├── pmx_network_manager.py
│   │   ├── pmx_sdn_manager.py
│   │   ├── pmx_passthrough_manager.py
│   │   ├── pmx_cloudinit_manager.py
│   │   ├── pmx_template_manager.py
│   │   ├── pmx_vm_config_audit.py
│   │   ├── pmx_vm_console.py
│   │   ├── pmx_monitoring.py          # Prometheus metrics export
│   │   ├── pmx_capacity_report.py
│   │   ├── pmx_alerting.py
│   │   ├── pmx_certificate_manager.py
│   │   └── pmx_bulk_operations.py
│   ├── ansible/
│   │   ├── ansible.cfg
│   │   ├── inventory.example
│   │   ├── group_vars/all.yml
│   │   ├── roles/
│   │   │   ├── proxmox_install/
│   │   │   ├── proxmox_cluster/
│   │   │   ├── proxmox_storage/
│   │   │   ├── proxmox_vm_deploy/
│   │   │   ├── proxmox_ct_deploy/
│   │   │   ├── proxmox_backup/
│   │   │   ├── proxmox_ha/
│   │   │   ├── proxmox_firewall/
│   │   │   ├── proxmox_users/
│   │   │   ├── proxmox_ceph/
│   │   │   ├── proxmox_zfs/
│   │   │   ├── proxmox_pbs/
│   │   │   ├── proxmox_network/
│   │   │   ├── proxmox_sdn/
│   │   │   ├── proxmox_passthrough/
│   │   │   ├── proxmox_cloudinit/
│   │   │   ├── proxmox_hardening/
│   │   │   └── proxmox_patching/
│   │   └── playbooks/
│   │       ├── site.yml
│   │       ├── deploy_vms.yml
│   │       ├── deploy_cts.yml
│   │       ├── backup_all.yml
│   │       ├── backup_setup.yml
│   │       ├── cluster_setup.yml
│   │       ├── ceph_setup.yml
│   │       ├── network_setup.yml
│   │       ├── sdn_setup.yml
│   │       ├── hardening.yml
│   │       ├── patching.yml
│   │       ├── rolling_upgrade.yml
│   │       └── monitoring_stack.yml
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── versions.tf
│       └── modules/
│           ├── vm/
│           ├── ct/
│           ├── network/
│           └── pool/
│
├── kvm/                                # ── KVM-GENERIC (no Proxmox deps) ──
│   ├── bash/
│   │   ├── kvm-vm-lifecycle.sh
│   │   ├── kvm-disk-image.sh
│   │   ├── kvm-network-bridge.sh
│   │   ├── kvm-ovs.sh
│   │   ├── kvm-passthrough.sh
│   │   ├── kvm-snapshot.sh
│   │   ├── kvm-backup.sh
│   │   ├── kvm-backup-restore.sh
│   │   ├── kvm-performance-tune.sh
│   │   ├── kvm-nested-virt.sh
│   │   ├── kvm-iommu-setup.sh
│   │   ├── kvm-cloudinit.sh
│   │   ├── kvm-qemu-direct.sh
│   │   └── kvm-health-check.sh
│   ├── python/
│   │   ├── requirements.txt
│   │   ├── kvm_libvirt_client.py      # reusable libvirt wrapper
│   │   ├── kvm_vm_manager.py
│   │   ├── kvm_vm_modify.py
│   │   ├── kvm_disk_manager.py
│   │   ├── kvm_disk_encryption.py
│   │   ├── kvm_backing_chain.py
│   │   ├── kvm_network_manager.py
│   │   ├── kvm_sriov_passthrough.py
│   │   ├── kvm_gpu_passthrough.py
│   │   ├── kvm_snapshot_manager.py
│   │   ├── kvm_backup.py
│   │   ├── kvm_performance.py
│   │   ├── kvm_cpu_pinning.py
│   │   ├── kvm_numa_topology.py
│   │   ├── kvm_passthrough.py
│   │   ├── kvm_cloudinit.py
│   │   ├── kvm_vm_fleet_deploy.py
│   │   ├── kvm_qmp_client.py
│   │   └── kvm_monitoring.py
│   └── ansible/
│       ├── inventory.example
│       └── playbooks/
│           ├── kvm_host_setup.yml
│           └── kvm_vm_deploy.yml
│
├── packer/                             # ── GOLDEN IMAGE BAKING ──
│   ├── proxmox-ubuntu-2404.pkr.hcl
│   ├── proxmox-debian-12.pkr.hcl
│   ├── proxmox-rocky-9.pkr.hcl
│   ├── proxmox-windows-2022.pkr.hcl
│   ├── qemu-ubuntu-2404.pkr.hcl
│   └── qemu-debian-12.pkr.hcl
│
├── go/                                 # ── GO (TUI + CLI + API clients) ──
│   ├── go.mod
│   ├── go.sum
│   ├── Makefile
│   ├── cmd/
│   │   ├── swissknife/                 # TUI application entry
│   │   │   └── main.go
│   │   ├── pmxctl/                     # Proxmox CLI tool
│   │   │   └── main.go
│   │   └── kvmctl/                     # KVM CLI tool
│   │       └── main.go
│   └── internal/
│       ├── ui/
│       │   ├── app.go
│       │   ├── menu.go
│       │   ├── vm_view.go
│       │   ├── ct_view.go
│       │   ├── storage_view.go
│       │   ├── backup_view.go
│       │   ├── snapshot_view.go
│       │   ├── network_view.go
│       │   ├── firewall_view.go
│       │   ├── cluster_view.go
│       │   ├── user_view.go
│       │   ├── monitoring_view.go
│       │   ├── passthrough_view.go
│       │   ├── cloudinit_view.go
│       │   ├── maintenance_view.go
│       │   ├── performance_view.go
│       │   ├── settings_view.go
│       │   ├── form.go
│       │   ├── confirm.go
│       │   ├── progress.go
│       │   ├── log_viewer.go
│       │   └── sparkline.go
│       ├── executor/
│       │   ├── bash_runner.go
│       │   ├── python_runner.go
│       │   ├── ansible_runner.go
│       │   ├── terraform_runner.go
│       │   └── api_runner.go
│       ├── config/
│       │   └── config.go
│       ├── proxmox/
│       │   ├── client.go
│       │   ├── vm.go
│       │   ├── container.go
│       │   ├── storage.go
│       │   ├── backup.go
│       │   ├── cluster.go
│       │   ├── ha.go
│       │   ├── firewall.go
│       │   ├── user.go
│       │   ├── snapshot.go
│       │   ├── migration.go
│       │   ├── network.go
│       │   ├── sdn.go
│       │   └── monitor.go
│       ├── kvm/
│       │   ├── libvirt.go
│       │   ├── vm.go
│       │   ├── disk.go
│       │   ├── network.go
│       │   ├── snapshot.go
│       │   ├── qmp.go
│       │   └── monitor.go
│       └── sshexec/
│           └── executor.go
│
├── tests/
│   ├── bats/                           # Bash integration tests (mock pvesh, virsh)
│   ├── pytest/                         # Python unit + integration (mock API with responses, mock libvirt)
│   └── go/                             # Go tests (bubbletea teatest, httptest mock)
│
└── docs/
    ├── ARCHITECTURE.md                 # ASCII diagram, module map, language rationale
    ├── PROXMOX_OPERATIONS.md           # Every Proxmox operation with examples
    ├── KVM_OPERATIONS.md               # Every raw-KVM operation with examples
    ├── TUI.md                          # TUI usage, keyboard shortcuts, config
    └── RUNBOOKS/
        ├── node-failure.md
        ├── storage-full.md
        ├── failed-migration.md
        ├── ceph-recovery.md
        ├── backup-recovery.md
        └── split-brain.md
```

---

## 3. LANGUAGE ASSIGNMENT MATRIX

| Task Category | Bash | Python | Ansible | Go | Terraform | Packer |
|---|---|---|---|---|---|---|
| VM/CT Lifecycle | quick ops | API bulk | declarative deploy | high-perf CLI | IaC | |
| Storage | local cmds | API | multi-node | | | |
| Backup/Restore | cron jobs | PBS API | scheduled | | | |
| Cluster | pvecm wrap | API | full setup | | | |
| HA | | API | declarative | | | |
| Firewall | | API | rules-as-code | | | |
| User/ACL | | API + LDAP | bulk | | | |
| Snapshots | | API | scheduled | | | |
| Templates | | API | | | | golden images |
| Migration | | API | rolling | | | |
| Ceph | | ceph API | full deploy | | | |
| ZFS | zfs cmds | | | | | |
| PBS | | PBS API | | | | |
| Network | ip/bridge | API | multi-node | | | |
| Passthrough | grub/modprobe | XML edit | idempotent | | | |
| Cloud-Init | | | templated | | | |
| Monitoring | | Prometheus | exporter deploy | sparklines | | |
| Disk/Image | qemu-img | | | | | |
| Perf Tuning | sysctl | libvirt XML | baseline | | | |
| Nested Virt | modprobe | | | | | |
| QMP Control | | QMP client | | | | |
| Disk Encryption | | LUKS + libvirt | | | | |
| Diagnostics | tcpdump/wrap | | | | | |
| Host Setup | | | KVM stack install | | | |
| Notifications | | sender | | | | |
| Reports | | generator | | | | |

---

## 4. MODULE CATALOGUE — SHARED (`/shared/`)

Tag each file **[SHARED]**. Usable by both Proxmox and raw KVM.

### S1. `shared/bash/lib/common.sh`
- Logging (rotate, levels: DEBUG/INFO/WARN/ERROR), color output
- Prerequisite checks, `.env` loading, dry-run wrapper, confirmation prompts
- JSON parsing (`jq`), API call helper (`curl` wrapper)
- Sourced by every Bash script

### S2. `shared/python/ssh_executor.py`
- Run commands on remote hosts via SSH (paramiko / subprocess)
- Parallel execution, timeout, retry

### S3. `shared/python/inventory_parser.py`
- Parse YAML inventory of hosts/VMs. Used by all modules.

### S4. `shared/python/notification.py`
- Send alerts: email (smtplib), Slack webhook, Telegram, ntfy.sh, PagerDuty, generic webhook

### S5. `shared/python/report_generator.py`
- Generate Markdown / HTML / PDF reports from structured data

### S6. `shared/python/health_check.py`
- Ping, SSH reachability, port check, disk space, memory, load → JSON status

### S7. `shared/go/sshexec/executor.go`
- Go SSH executor for TUI and CLI tools

---

## 5. MODULE CATALOGUE — PROXMOX (`/proxmox/`)

Generate ALL of the following. Tag each file **[PROXMOX]**.

### A. VM & Container Lifecycle (qm / pct / API)

**A1. `pmx-vm-lifecycle.sh` / `pmx_vm_manager.py`**
- Create QEMU VM: CPU model, cores, sockets, RAM, balloon, BIOS (SeaBIOS/OVMF), machine type (q35/i440fx), SCSI controller (virtio-scsi-single), disk bus, NIC model (virtio), cloud-init drive, ISO mount, TPM 2.0, secure boot
- Create LXC CT: template, storage, unprivileged, nesting, features, rootfs size
- Start, stop, shutdown (graceful with timeout + force fallback), reboot, suspend, resume, reset, poweroff
- Clone (full/linked), rename, set boot order, CPU/mem/NUMA hotplug, set display (VNC/SPICE/virtio), watchdog, tablet, agent (qemu-guest-agent), start-on-boot, protection flag, startup/shutdown order and delay
- Accept a YAML/JSON spec file OR CLI flags
- Batch operations: all VMs in a pool, all VMs matching a tag

**A2. `pmx-ct-lifecycle.sh` / `pmx_ct_manager.py`**
- Create (from template, unprivileged/privileged), start, stop, shutdown, delete, clone
- Resize rootfs, set CPU/mem/swap limits, set features (nesting, keyctl, fuse, mount)
- Set DNS, hostname, console mode, unprivileged mapping, apparmor profile, cgroup version

**A3. `pmx_vm_config_audit.py`**
- Dump full running config vs on-disk config, diff report, drift detection

**A4. `pmx_vm_console.py`**
- Open VNC/SPICE console via API ticket, generate noVNC URL

### B. Snapshot & Backup

**B1. `pmx-snapshot.sh` / `pmx_snapshot_manager.py`**
- Create snapshot (with/without RAM), rollback, delete, list
- Scheduled snapshot rotation policy (daily/weekly/monthly, retention counts)
- Pre-snapshot hook: run guest-agent fs-freeze via qga

**B2. `pmx-backup-restore.sh` / `pmx_backup_manager.py`**
- Trigger vzdump via API: mode (snapshot/suspend/stop), compression (zstd/gz/lzo), target storage
- PBS integration: backup to PBS, restore from PBS, verify backup integrity
- PBS-specific: prune, verify, garbage-collect via pbs-client
- Parallel backup of multiple VMs with concurrency limiter
- Post-backup verification: mount backup, checksum, report
- Restore from local vzdump or PBS, restore to different node/storage/vmid
- Prune old backups per retention policy, export backup to remote (rsync/rclone)
- Backup notification (email/Slack/webhook)
- Bare-metal restore workflow

### C. Storage

**C1. `pmx-storage.sh` / `pmx_storage_manager.py`**
- Add/remove storage backends via API: dir, LVM, LVM-thin, ZFS, ZFS-over-iSCSI, NFS, CIFS/SMB, Ceph RBD, CephFS, GlusterFS, iSCSI, PBS
- Validate connectivity before adding
- List storage status, resize disk, move disk between storages, import disk image
- Set storage content types, maxfiles, shared flag, prune-backups

**C2. `pmx-ceph.sh` / `pmx_ceph_manager.py`**
- Deploy Ceph cluster (mons, mgrs, OSDs) via pveceph
- Create/manage pools, CRUSH rules, erasure coding
- OSD add/replace/reweight/rebalance, CephFS create + export
- Health monitoring: parse `ceph status`, alert on WARN/ERR
- Scrub/deep-scrub, set pool size/min_size, manage Ceph dashboard

**C3. `pmx-zfs.sh` / `pmx_zfs_manager.py`**
- Create/destroy/import ZFS pools, datasets, zvols
- Set properties: compression, dedup, checksum, recordsize, sync, ARC/L2ARC tuning
- Scrub scheduling, snapshot management, replication (zfs send/recv)
- Add/remove vdev, replace disk

**C4. `pmx_pbs_manager.py`**
- Add PBS datastore, configure PBS target in Proxmox, trigger PBS backup
- Verify PBS backup, prune PBS datastore, manage PBS encryption keys
- Set PBS sync jobs, check PBS status

### D. Networking

**D1. `pmx-network.sh` / `pmx_network_manager.py`**
- Create/edit/delete Linux bridge, OVS bridge, VLAN-aware bridge
- Bond (LACP/active-backup), VLAN interface, alias IP, set MTU, set rate limit

**D2. `pmx-sdn.sh` / `pmx_sdn_manager.py`**
- Proxmox SDN API: create zones (VLAN, VXLAN, EVPN, Q-in-Q), vnets, subnets, IPAM, DNS zones, BGP/EVPN peering
- Apply pending network changes

**D3. `pmx-firewall.sh` / `pmx_firewall_manager.py`**
- Enable/disable firewall at DC/VM/CT level
- Add/remove/edit rules (in/out), manage IP sets, aliases, security groups
- Set default policies, log level, rate limiting, MAC filters

**D4. `pmx-network-diagnostics.sh`**
- tcpdump wrappers, bridge port status, bond status, OVS flow dumps
- MTU path discovery, VLAN tagging verification

### E. Cluster & HA

**E1. `pmx-cluster.sh` / `pmx_cluster_manager.py`**
- Create cluster (pvecm create), join node, remove node, list nodes
- Check quorum, set expected votes, manage corosync links
- Corosync config tuning (ring redundancy, transport udpu/knet)
- Handle split-brain recovery, manage fence devices

**E2. `pmx-ha.sh` / `pmx_ha_manager.py`**
- Create/modify HA groups, HA resources (vm/ct)
- Set HA policy: max_relocate, max_restart, state (started/stopped/disabled/ignored)
- Simulate node failure, verify failover
- Configure fencing, test HA failover

### F. Templates & Cloud-Init

**F1. `pmx-template.sh` / `pmx_template_manager.py`**
- Download cloud image (Ubuntu, Debian, Rocky, Alma, Fedora, Windows)
- Attach cloud-init drive, set default user/keys, convert to template
- Update template (patch and re-template), delete template

**F2. `pmx-cloudinit.sh` / `pmx_cloudinit_manager.py`**
- Generate cloud-init YAML: user, ssh-keys, packages, runcmd, write_files, network-config (static/DHCP), growpart, timezone, locale
- Set custom user-data, meta-data, network-config, regenerate cloud-init image

### G. User, ACL & Security

**G1. `pmx-user-acl.sh` / `pmx_user_acl_manager.py`**
- Create/delete users (PAM, PVE, LDAP, AD, OpenID), set passwords
- Create/delete groups, create/delete roles, set ACL paths
- Enable/disable TFA (TOTP/WebAuthn/YubiKey)
- Manage API tokens, set token expiry, manage realms
- LDAP/AD integration setup

**G2. `pmx_certificate_manager.py`**
- Let's Encrypt / ACME via Proxmox API, or upload custom certs
- Auto-renewal cron

### H. Monitoring, Alerting & Reporting

**H1. `pmx_monitoring.py`**
- Pull metrics from Proxmox RRD (rrdtool), API `/nodes/{node}/rrd`, `/cluster/resources`
- CPU, RAM, disk, net per VM/node
- Export to Prometheus format (textfile collector) or push to InfluxDB

**H2. `pmx_alerting.py`**
- Threshold-based alerts: CPU > 90%, disk > 85%, VM down, backup failed
- Channels: email, Slack, Telegram, PagerDuty, ntfy.sh

**H3. `pmx_capacity_report.py`**
- Generate PDF/HTML report: cluster capacity, per-node utilization
- Storage forecast (linear regression on usage trend), VM inventory

### I. Migration & Maintenance

**I1. `pmx-migration.sh` / `pmx_migration_manager.py`**
- Online migration (qm migrate --online), with or without local disks
- Pre-check: compatible CPU, shared storage, network, HA constraints
- Batch migrate: evacuate a node (all VMs/CTs off)
- Set migration network, type (secure/insecure), bandwidth limit

**I2. `pmx-node-maintenance.sh`**
- Drain node (migrate all), set maintenance mode, run updates, reboot
- Wait healthy, re-enable HA
- Kernel update + reboot orchestration

### J. PCI/GPU Passthrough & SR-IOV

**J1. `pmx-gpu-passthrough.sh` / `pmx-pci-passthrough.sh` / `pmx_passthrough_manager.py`**
- Detect GPU, enable IOMMU, blacklist nouveau/nvidiafb
- Configure vfio-pci, set GPU ROM BAR, add GPU to VM (hostpci0)
- Verify passthrough, handle multi-GPU, handle vGPU (NVIDIA GRID/SR-IOV)
- List PCI devices, identify IOMMU groups, handle ACS override

**J2. `pmx-sriov.sh`**
- Enable SR-IOV on NIC, create VFs, assign VF to VM
- Manage VF MAC/VLAN, persistent SR-IOV config

### K. Health Check

**K1. `pmx-health-check.sh`**
- Check node health (CPU, RAM, disk, SMART, temps, load)
- Check VM/CT health, storage health, Ceph health, cluster health
- Generate JSON report, alert on thresholds

---

## 6. MODULE CATALOGUE — KVM-GENERIC (`/kvm/`)

Generate ALL of the following. Tag each file **[KVM]**. These must work on ANY KVM host with libvirt/QEMU installed. **NO Proxmox dependencies.**

### A. VM Lifecycle via libvirt/virsh

**A1. `kvm-vm-lifecycle.sh` / `kvm_vm_manager.py`**
- `virt-install` wrapper: CPU topology, RAM, disks (qcow2/raw), NIC, graphics (VNC/SPICE/none), UEFI (OVMF), TPM (swtpm), cloud-init ISO
- Or define XML directly via `virsh define`
- `virsh start/shutdown/destroy/suspend/resume/save/restore/autostart`
- Batch via `--all` or `--tag` (libvirt metadata tags)

**A2. `kvm_vm_modify.py`**
- Hotplug/unplug CPU, RAM (virtio-balloon), disk, NIC
- Modify XML: change boot order, add serial console, add PCI passthrough
- Set vCPUs (hotplug), CPU model/pinning, NUMA topology, max memory

**A3. `kvm-disk-image.sh` / `kvm_disk_manager.py`**
- `qemu-img`: create (qcow2/raw/vmdk/vhdx), convert between formats, resize, rebase, commit, check, info, amend (encryption, cluster size)
- `libguestfs`: virt-resize, virt-sparsify, virt-sysprep, virt-customize (inject files, set hostname, add keys, run scripts inside image offline)
- sparsify, bench, merge backing chain

**A4. `kvm_disk_encryption.py`**
- LUKS-encrypted qcow2, secret management via libvirt secret objects

**A5. `kvm_backing_chain.py`**
- Create/manage qcow2 backing chains (base → delta → delta)
- Commit, rebase, flatten

### B. Networking

**B1. `kvm-network-bridge.sh` / `kvm_network_manager.py`**
- Create/destroy libvirt networks: NAT, routed, isolated, bridge, SR-IOV, Open vSwitch
- Manage dnsmasq DHCP/static leases, DNS entries
- Set bandwidth limits (`tc`/`virsh domiftune`), manage macvtap/macvlan
- Manage network filters (nwfilter): anti-spoofing, rate limiting, port isolation

**B2. `kvm-ovs.sh`**
- Open vSwitch: create bridges, ports, VLANs, VXLAN tunnels, bond LACP
- Attach libvirt VMs to OVS

**B3. `kvm-sriov.sh` / `kvm_sriov_passthrough.py`**
- Enumerate IOMMU groups, bind VF to vfio-pci, attach to VM
- Validate ACS, kernel params (intel_iommu=on, iommu=pt)

**B4. `kvm-gpu-passthrough.sh` / `kvm_gpu_passthrough.py`**
- PCI passthrough for GPU (NVIDIA/AMD): IOMMU group isolation, vfio-pci bind, romfile, hugepages, kvm.ignore_msrs
- vGPU (NVIDIA vGPU / Intel GVT-g / AMD MxGPU) setup

### C. Snapshots & Backups

**C1. `kvm-snapshot.sh` / `kvm_snapshot_manager.py`**
- `virsh snapshot-create-as` (internal for qcow2), external snapshots with `qemu-img` + blockcommit
- Create live snapshot with quiesce (fsfreeze), rollback, delete, list
- Snapshot chain management, block-commit, block-pull, block-rebase

**C2. `kvm-backup.sh` / `kvm_backup.py`**
- Live backup: `virsh domfsfreeze` → `qemu-img convert` / `blockdev-backup` (QMP) → `domfsthaw`
- Incremental backup via QEMU dirty-bitmap (`block-dirty-bitmap-add`, `drive-backup` with `sync=incremental`)
- Offline backup: shutdown → copy → start

**C3. `kvm-backup-restore.sh`**
- Restore from full/incremental chain, rebuild qcow2 chain

### D. Performance Tuning

**D1. `kvm-performance-tune.sh` / `kvm_performance.py`**
- Enable hugepages (1G/2M), mount hugetlbfs, configure per-NUMA node
- Set in libvirt XML (`<memoryBacking>`)

**D2. `kvm_cpu_pinning.py`**
- Pin vCPUs to pCPUs, set NUMA topology, emulator pin, IOThread pin
- Generate `<cputune>` and `<numatune>` XML

**D3. `kvm_numa_topology.py`**
- Detect host NUMA, map VM NUMA nodes to host nodes
- Set memory mode (strict/preferred/interleave)

**D4. `kvm-kernel-tuning.sh`**
- sysctl: vm.dirty_ratio, net.core.somaxconn, KSM (ksmtuned)
- Transparent hugepages (disable for VMs), swappiness
- I/O scheduler selection (mq-deadline, none, bfq), ionice
- virtio-blk vs virtio-scsi, iothreads, cache mode (none/writethrough/writeback)

### E. Cloud-Init & Automation

**E1. `kvm-cloudinit.sh` / `kvm_cloudinit.py`**
- Generate cloud-init NoCloud ISO (meta-data + user-data + network-config)
- Attach to VM as cdrom, configure network, configure user-data

**E2. `kvm_vm_fleet_deploy.py`**
- Deploy N VMs from a base qcow2 template + cloud-init
- Parallel creation, IP assignment, wait-for-SSH, run post-provision script

### F. QMP Direct Control

**F1. `kvm_qmp_client.py`**
- Connect to QEMU QMP socket, send arbitrary commands
- Query block jobs, migrate, snapshot, change CD, send keys

**F2. `kvm-qemu-direct.sh`**
- Launch `qemu-system-x86_64` directly (no libvirt) with full arg control
- Useful for debugging, custom devices, nested virt

### G. Host-Level Setup

**G1. `kvm_host_setup.yml` (Ansible)**
- Install qemu-kvm, libvirt, virt-install, bridge-utils, OVMF, swtpm, libguestfs-tools, cockpit-machines
- Enable libvirtd, add user to libvirt group, configure default network, storage pool

**G2. `kvm-nested-virt.sh`**
- Enable nested virtualization (`kvm-intel nested=1` / `kvm-amd nested=1`)
- Verify with `/sys/module/kvm_*/parameters/nested`

**G3. `kvm-iommu-setup.sh`**
- Enable IOMMU in GRUB, verify groups, blacklist GPU drivers for passthrough

### H. Monitoring

**H1. `kvm_monitoring.py`**
- Get domain stats (`virsh domstats`, `dommemstat`, `domblkstat`, `domifstat`)
- Export to Prometheus (`libvirt_exporter` config)
- Check libvirtd/storage pool/network health

---

## 7. PROXMOX API CLIENT LIBRARY

### Python (primary) — `proxmox/python/pve_api_client.py`
- Full wrapper around `/api2/json`. Auth: PAM, PVE, API token.
- Methods for every endpoint used above. Retry logic, rate limiting, connection pooling (`httpx` async).
- Use `proxmoxer` library as base.

### Go (for TUI) — `go/internal/proxmox/client.go`
- Go HTTP client for Proxmox API. Used by the TUI.
- Concurrent requests, context-aware cancellation.
- Use `github.com/Telmate/proxmox-api-go` or `github.com/luthermonson/go-proxmox`.

---

## 8. DETAILED IMPLEMENTATION REQUIREMENTS PER LANGUAGE

### 8.1 BASH
- Use `set -euo pipefail` in every script.
- Source `shared/bash/lib/common.sh` for: logging, colors, prereqs, `.env` loading, dry-run, confirmation, `jq`, API call helper.
- Each script: positional args AND long options (`getopt`).
- Proxmox scripts: authenticate via API token (`PMX_API_TOKEN` env var), support `--node`, `--vmid`, `--api-host` flags.
- KVM scripts: detect `virsh` connection URI (`--connect` flag, default `qemu:///system`).
- Include `trap` for cleanup on errors.

### 8.2 PYTHON
- Use `proxmoxer` library for Proxmox API.
- Use `libvirt-python` for KVM/libvirt.
- Use `click` or `typer` for CLI interfaces.
- Use `rich` for colored output and tables.
- Use `pydantic` for config/data validation.
- Use `httpx` (async) where batch API calls are needed.
- Use `prometheus_client` for metrics export.
- Structure each module as a class with methods per operation.
- Include `pytest` tests with `pytest-mock` for API calls.
- Include `mypy` type checking config.

### 8.3 ANSIBLE
- Every role: `tasks/main.yml`, `handlers/main.yml`, `defaults/main.yml`, `vars/main.yml`, `templates/`, `meta/main.yml`.
- Use `community.general.proxmox_*` modules where available.
- Use `community.libvirt.virt_*` modules for KVM.
- Include `molecule/` test scaffolding per role.
- Tag every task for selective runs. Support `check_mode`.

### 8.4 GO
- Use `github.com/Telmate/proxmox-api-go` or `github.com/luthermonson/go-proxmox` for Proxmox.
- Use `libvirt.org/go/libvirt` for KVM.
- Use `cobra` for CLI structure.
- Use `viper` for config.
- Use `zerolog` for structured logging.
- Use `prometheus/client_golang` for metrics.
- Include `_test.go` files with table-driven tests.
- Include `golangci-lint` config.

### 8.5 TERRAFORM
- Use `bpg/proxmox` provider (latest).
- Include `terraform.tfvars.example`.
- Use modules for reusability.
- Include `terraform validate` and `tflint` config.

---

## 9. PACKER TEMPLATES (`/packer/`)

All templates: provision with cloud-init + Ansible (install qemu-guest-agent, harden, update, clean). Output as template.

| Template | Builder | OS |
|----------|---------|-----|
| `proxmox-ubuntu-2404.pkr.hcl` | `proxmox-iso` | Ubuntu 24.04 |
| `proxmox-debian-12.pkr.hcl` | `proxmox-iso` | Debian 12 |
| `proxmox-rocky-9.pkr.hcl` | `proxmox-iso` | Rocky 9 |
| `proxmox-windows-2022.pkr.hcl` | `proxmox-iso` | Windows Server 2022 (with autounattend.xml) |
| `qemu-ubuntu-2404.pkr.hcl` | `qemu` | Ubuntu 24.04 |
| `qemu-debian-12.pkr.hcl` | `qemu` | Debian 12 |

---

## 10. THE TUI APPLICATION (`/tui/`) — "SwissKnife"

### 10.1 Technology
- **Language**: Go 1.22+
- **Framework**: `charmbracelet/bubbletea` (Elm architecture) + `charmbracelet/lipgloss` (styling) + `charmbracelet/bubbles` (components: list, table, textinput, spinner, progress, viewport, textarea, checkbox)
- **Goal**: Single binary `swissknife` — statically compiled, zero runtime dependencies

### 10.2 Architecture

```
┌─────────────────────────────────────────────────┐
│                  TUI Main Loop                  │
│  ┌───────────┐  ┌───────────┐  ┌─────────────┐  │
│  │ Menu Nav  │  │ Form/Input│  │ Output/Log  │  │
│  │ (Bubbles) │  │ (Bubbles) │  │ (Viewport)  │  │
│  └─────┬─────┘  └─────┬─────┘  └──────┬──────┘  │
│        └───────────────┼───────────────┘         │
│                   Dispatcher                     │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌───────┐ │
│  │Bash Exec │ │Python Ex │ │Ansible │ │API Dir│ │
│  │(os/exec) │ │(os/exec) │ │(os/exec│ │(HTTP) │ │
│  └──────────┘ └──────────┘ └────────┘ └───────┘ │
└─────────────────────────────────────────────────┘
```

### 10.3 Menu Structure

```
╔══════════════════════════════════════════════════════╗
║            SWISSKNIFE  v1.0                          ║
╠══════════════════════════════════════════════════════╣
║  [1] 🖥  Virtual Machines                            ║
║      ├─ Create VM (Proxmox) / Create VM (KVM/libvirt)║
║      ├─ Start / Stop / Reboot / Shutdown             ║
║      ├─ Clone / Migrate (live) / Resize              ║
║      ├─ Delete / Console (VNC/SPICE)                 ║
║      ├─ Config Audit                                 ║
║      └─ List / Filter / Search                       ║
║  [2] 📦 Containers (LXC)                             ║
║      ├─ Create / Clone                               ║
║      ├─ Start / Stop                                 ║
║      ├─ Resize / Delete                              ║
║      └─ Template management                          ║
║  [3] 💾 Storage                                      ║
║      ├─ Add / Remove Storage Backend                 ║
║      ├─ Ceph Management                              ║
║      ├─ ZFS Management                               ║
║      ├─ LVM Management                               ║
║      ├─ Move Disk / Resize Disk                      ║
║      ├─ Storage Status                               ║
║      └─ Benchmark (fio)                              ║
║  [4] 🌐 Networking                                   ║
║      ├─ Bridges / Bonds / VLANs                      ║
║      ├─ Proxmox SDN                                  ║
║      ├─ Firewall Rules                               ║
║      ├─ SR-IOV / GPU Passthrough                     ║
║      ├─ OVS Management                               ║
║      └─ Diagnostics                                  ║
║  [5] 📸 Snapshots & Backups                          ║
║      ├─ Create / List / Rollback Snapshot            ║
║      ├─ Backup (vzdump / PBS / libvirt)              ║
║      ├─ Restore                                      ║
║      ├─ Schedule Management                          ║
║      └─ Backup Verification                          ║
║  [6] 🏗  Cluster & HA                                ║
║      ├─ Cluster Status / Join / Remove               ║
║      ├─ HA Groups / Resources                        ║
║      ├─ Failover Test                                ║
║      └─ Rolling Upgrade                              ║
║  [7] 📋 Templates & Cloud-Init                       ║
║      ├─ Create Template                              ║
║      ├─ Cloud-Init Generator                         ║
║      ├─ Packer Build (trigger)                       ║
║      └─ Terraform Apply (trigger)                    ║
║  [8] 🔒 Security & Users                             ║
║      ├─ User / ACL Management                        ║
║      ├─ API Tokens                                   ║
║      ├─ Certificates (ACME)                          ║
║      └─ Hardening Audit                              ║
║  [9] 📊 Monitoring & Reports                         ║
║      ├─ Live Metrics Dashboard (sparklines)          ║
║      ├─ Alerts Config                                ║
║      ├─ Capacity Report                              ║
║      └─ Log Viewer (tail -f style in viewport)       ║
║ [10] ⚡ Performance Tuning                            ║
║      ├─ Hugepages / CPU Pinning / NUMA               ║
║      ├─ IO Tuning                                    ║
║      └─ Kernel Params                                ║
║ [11] 🔧 Host Setup                                   ║
║      ├─ Install KVM stack                            ║
║      ├─ Enable Nested Virt                           ║
║      ├─ IOMMU Setup                                  ║
║      └─ Guest Agent Install                          ║
║ [12] 🛠  Utilities                                   ║
║      ├─ SSH Executor (run cmd on N hosts)            ║
║      ├─ Config Git Backup                            ║
║      ├─ Health Check (all nodes)                     ║
║      └─ Settings / API Credentials                   ║
║                                                      ║
║  [q] Quit   [?] Help   [/] Search   [Esc] Back      ║
║  [Tab] Switch panel   [Enter] Select                 ║
╚══════════════════════════════════════════════════════╝
```

### 10.4 UX Requirements

- **Fuzzy search**: type to filter the menu list (type `/` to activate).
- **Breadcrumb navigation**: Esc = go back to parent menu.
- **Form → Confirm → Progress flow**: each action shows a FORM (text inputs, select dropdowns, checkboxes) to collect parameters, then a CONFIRMATION screen, then a PROGRESS/LOG view that streams stdout/stderr of the underlying script.
- **Color-coded status**: green=ok, yellow=warning, red=error.
- **Sortable table views**: VM lists, storage, cluster nodes (sortable columns).
- **Live metrics**: sparklines in TUI, poll every 2s.
- **Keyboard shortcuts**: q=quit, ?=help, /=search, tab=switch panel, Enter=select, Esc=back.
- **Persistent config**: `~/.config/swissknife/config.yaml` (API URL, user, token, default node, SSH keys, theme).
- **Multi-cluster support**: config supports multiple Proxmox clusters / KVM hosts, switchable.
- **Executor abstraction**: each menu action maps to a command:
  - Bash scripts → `exec.Command("bash", scriptPath, args...)`
  - Python scripts → `exec.Command("python3", scriptPath, args...)`
  - Ansible → `exec.Command("ansible-playbook", playbookPath, args...)`
  - Terraform → `exec.Command("terraform", "apply", ...)`
  - Go-native → call Go functions directly (pveclient, libvirt-go)
- **Live output**: long-running operations stream stdout/stderr to a viewport panel in real time.
- **Timeout + cancel**: Ctrl-C / Esc during execution cancels the operation.
- **Confirmation dialogs**: all destructive actions show a modal confirmation.
- **Dry-run toggle**: global toggle in the status bar.
- **Multi-node selector**: when connected to a cluster, allow selecting target node.
- **Error handling**: API errors, SSH errors, and script failures caught and displayed in a toast/notification.
- **Responsive**: must work in terminals from 80x24 up to 4K.
- **Embed scripts**: `go:embed` all `.sh`, `.py`, `.yml` bundled in the binary.

### 10.5 Build

```bash
go build -ldflags "-s -w" -o swissknife ./cmd/swissknife
```

Makefile target: `make tui`

---

## 11. CROSS-CUTTING CONCERNS

### 11.1 Security Hardening (Ansible hardening role + Bash/Python scripts)
- Disable root SSH login
- Configure fail2ban for Proxmox web UI
- Enable TFA for all admin users
- Restrict API token permissions
- Enable audit logging (auditd)
- Configure automatic security updates
- Harden Ceph (msgr2 encryption)
- Restrict VNC/SPICE to TLS
- Disable unused services
- Kernel hardening (sysctl)
- TLS cert management (ACME via Proxmox or certbot)

### 11.2 Error Handling & Logging
- All scripts: structured JSON logs + human-readable logs.
- Log rotation: `logrotate` config included.
- Error codes: 0=success, 1=error, 2=misuse, 3=partial-failure

### 11.3 Config File — `config/settings.yaml`
```yaml
# Global configuration for Pulsar
# Uncomment and modify as needed

# Proxmox connection
# proxmox:
#   hosts:
#     - name: "pve-prod"
#       api_url: "https://pve1.example.com:8006"
#       user: "root@pam"
#       token_id: ""
#       token_secret: ""
#       node: "pve1"
#     - name: "pve-dev"
#       api_url: "https://pve2.example.com:8006"
#       user: "admin@pam"
#       token_id: ""
#       token_secret: ""
#       node: "pve2"

# KVM/libvirt connection
# kvm:
#   uris:
#     - name: "local"
#       uri: "qemu:///system"
#     - name: "remote"
#       uri: "qemu+ssh://root@kvm-host/system"

# Defaults
# defaults:
#   node: "pve1"
#   storage: "local-lvm"
#   backup_retention: 7
#   snapshot_retention: 10
#   log_level: "INFO"
#   log_dir: "/var/log/pulsar"
#   dry_run: false
#   executor: "bash"  # bash | python | ansible | api

# Notification channels
# notifications:
#   email:
#     enabled: false
#     smtp_host: ""
#     smtp_port: 587
#     from: ""
#     to: []
#   slack:
#     enabled: false
#     webhook_url: ""
#   telegram:
#     enabled: false
#     bot_token: ""
#     chat_id: ""

# Alerting thresholds
# alerts:
#   cpu_warn: 80
#   cpu_crit: 95
#   disk_warn: 75
#   disk_crit: 90
#   mem_warn: 80
#   mem_crit: 95

# TUI settings
# tui:
#   theme: "dark"  # dark | light
#   refresh_interval: 2
#   default_view: "list"

# SSH settings
# ssh:
#   default_user: "root"
#   key_path: "~/.ssh/id_rsa"
#   timeout: 30
#   retry: 3
```

---

## 12. TESTING

### 12.1 BATS (`tests/bats/`)
- BATS tests for every `.sh` script (mock `pvesh`, `virsh`, `qemu-img`, etc.)
- Integration tests that verify idempotency and error handling

### 12.2 pytest (`tests/pytest/`)
- Unit + integration tests for Python modules
- Mock API responses with `responses` library
- Mock libvirt with `libvirt-python` test driver
- Coverage reporting

### 12.3 Go (`tests/go/`)
- Go tests for TUI components (`bubbletea teatest`)
- `pveclient` tests with `httptest` mock server
- Table-driven tests

### 12.4 Makefile Targets
```makefile
test:          # runs all (bats, pytest, go)
lint:          # shellcheck, pylint/ruff, golangci-lint, ansible-lint, tflint
```

---

## 13. DOCUMENTATION

| File | Content |
|------|---------|
| `README.md` | Quick start, install, configure, first run, screenshots |
| `docs/ARCHITECTURE.md` | ASCII diagram, module map, language rationale |
| `docs/PROXMOX_OPERATIONS.md` | Every Proxmox operation with examples |
| `docs/KVM_OPERATIONS.md` | Every raw-KVM operation with examples |
| `docs/TUI.md` | TUI usage, keyboard shortcuts, config reference |
| `docs/RUNBOOKS/*.md` | Step-by-step for: node failure, storage full, failed migration, Ceph recovery, backup recovery, split-brain |

---

## 14. DELIVERABLES CHECKLIST

- [ ] All shared utilities (`/shared/`)
- [ ] All Bash scripts (Proxmox + KVM) with `shared/bash/lib/common.sh`
- [ ] All Python modules with `requirements.txt`, tests, type hints
- [ ] All Ansible roles and playbooks with inventory and vars
- [ ] All Go packages with `go.mod`, tests, Makefile
- [ ] Packer templates (Proxmox + QEMU builders)
- [ ] Terraform modules and examples
- [ ] TUI application (Go + Bubble Tea) with full menu tree
- [ ] Top-level `README.md` with quickstart, architecture diagram, per-module docs
- [ ] `config/settings.yaml` with all commented-out parameters
- [ ] `.env.example` with all required environment variables
- [ ] `Makefile` at root with targets: `build`, `test`, `lint`, `install`, `clean`, `tui`, `packer-build`, `ansible-check`
- [ ] `tests/` — BATS, pytest, Go tests
- [ ] `docs/` — ARCHITECTURE, OPERATIONS, RUNBOOKS
- [ ] `CHANGELOG.md`

---

## 15. EXECUTION ORDER

Generate files in this order so dependencies are satisfied:

1. `README.md`, `LICENSE`, `.env.example`, `.gitignore`, root `Makefile`
2. `config/settings.yaml`
3. `shared/bash/lib/common.sh` (shared Bash library)
4. `shared/python/` (ssh_executor, inventory_parser, notification, report_generator, health_check)
5. `shared/go/sshexec/`
6. All Bash scripts (Proxmox first, then KVM)
7. `proxmox/python/requirements.txt`, `pve_api_client.py`, then all Proxmox Python modules
8. `kvm/python/requirements.txt`, `kvm_libvirt_client.py`, then all KVM Python modules
9. Ansible: `ansible.cfg`, inventory, group_vars, then roles, then playbooks (Proxmox, then KVM)
10. `go/go.mod`, internal packages, then `cmd/`
11. `packer/` templates
12. `terraform/` modules and examples
13. `tui/` — the full Bubble Tea application
14. `tests/` — BATS, pytest, Go
15. `docs/` — architecture, operations, runbooks
16. `CHANGELOG.md`

---

**Generate ALL files now. Do not summarize. Do not skip any file. Produce complete, working code for every single file listed in the directory tree above.**

BEGIN GENERATION NOW.
