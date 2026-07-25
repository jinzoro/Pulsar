# Graph Report - .  (2026-07-25)

## Corpus Check
- 320 files · ~181,238 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3080 nodes · 5077 edges · 199 communities (160 shown, 39 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 224 edges (avg confidence: 0.68)
- Token cost: 20,480 input · 4,096 output

## Community Hubs (Navigation)
- TUI Action Executor
- Configuration System
- KVM Libvirt Client
- PVE API Client
- Architecture & Design
- Proxmox Template Manager
- Architecture Concepts
- CPU Pinning & Libvirt
- Shared Bash Library
- Notification System
- Report Generator
- KVM QMP Client
- KVM Disk Manager
- Go QMP Client
- CPU Pinning
- GPU Passthrough
- Inventory Parser
- TUI Sparkline
- KVM Backup Manager
- Performance Manager
- Pytest Test Fixtures
- ZFS Management
- KVM Monitoring
- Health Check
- KVMCTL CLI
- Kvm Python
- Kvm Python
- Kvm Python
- Proxmox Bash
- Ceph & Cluster Concepts
- Kvm Python
- Proxmox Bash
- Proxmox Python
- Proxmox Python
- Tests Pytest
- Tui Model
- Kvm Python
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Tests Pytest
- Proxmox Client
- Kvm Python
- Proxmox Bash
- Proxmox Python
- Proxmox Client
- Proxmox Ansible
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Shared Python
- Tests Pytest
- Proxmox Python
- Cloud Images & Containers
- Kvm Vmoperation
- Proxmox Client
- Kvm Bash
- Kvm Python
- Proxmox Bash
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Kvm Networkoperation
- Proxmox Client
- Proxmox Client
- Proxmox Client
- Proxmox Bash
- Proxmox Client
- Tui Logviewmodel
- Kvm Bash
- Kvm Python
- Proxmox Bash
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Proxmox Python
- Backup & Ceph Concepts
- Go Internal
- Proxmox Client
- Proxmox Client
- Kvm Bash
- Proxmox Bash
- Proxmox Bash
- Sshexec Executor
- Proxmox Client
- Proxmox Client
- Kvm Bash
- Kvm Bash
- Kvm Bash
- Proxmox Ansible
- Proxmox Bash
- Proxmox Python
- Tests Pytest
- Tests Pytest
- Tests Pytest
- Kvm Snapshotoperation
- Kvm Bash
- Kvm Bash
- Kvm Python
- Proxmox Bash
- Proxmox Bash
- Tests Pytest
- Tests Pytest
- Tests Pytest
- Tests Pytest
- Kvm Domain
- Kvm Libvirtclient
- Proxmox Client
- Go Internal
- Go Internal
- Kvm Bash
- Kvm Bash
- Kvm Bash
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Bash
- Proxmox Bash
- Proxmox Bash
- Proxmox Python
- Proxmox Python
- Tests Pytest
- Tui Progressmodel
- Tests Go
- Proxmox Ansible
- Proxmox Bash
- Proxmox Bash
- Proxmox Bash
- Proxmox Python
- Proxmox Python
- Tests Pytest
- Kvm Bash
- Kvm Bash
- Proxmox Bash
- Proxmox Bash
- Proxmox Bash
- Proxmox Bash
- Tests Pytest
- Kvm Bash
- Proxmox Ansible
- Tests Pytest
- Proxmox Client
- Proxmox Hardening
- Tests Go
- Tui
- Go Config Tests
- Alerting System
- Go Internal
- Go Internal
- Proxmox Ansible
- Proxmox Network
- High Availability
- PCI Passthrough
- Shared Python
- Proxmox Ansible
- Proxmox Installation
- Python Dependencies
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Ansible
- Kvm Python
- Pkg Github
- Pkg Github
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Proxmox Ansible
- Community: rich
- Community: typer

## God Nodes (most connected - your core abstractions)
1. `PVEClient` - 113 edges
2. `_wrap_libvirt_error()` - 69 edges
3. `ActionExecutor` - 61 edges
4. `LibvirtClient` - 61 edges
5. `decodeJSON()` - 47 edges
6. `LibvirtError` - 45 edges
7. `Model` - 32 edges
8. `QMPClient` - 28 edges
9. `main()` - 28 edges
10. `VMManager` - 25 edges

## Surprising Connections (you probably didn't know these)
- `mock_pve_client()` --calls--> `PVEClient`  [INFERRED]
  tests/pytest/conftest.py → proxmox/python/pve_api_client.py
- `TestHealthCheckerAll` --uses--> `HealthChecker`  [INFERRED]
  tests/pytest/test_health_check.py → shared/python/health_check.py
- `TestHealthCheckerDisk` --uses--> `HealthChecker`  [INFERRED]
  tests/pytest/test_health_check.py → shared/python/health_check.py
- `TestHealthCheckerMemory` --uses--> `HealthChecker`  [INFERRED]
  tests/pytest/test_health_check.py → shared/python/health_check.py
- `TestHealthCheckerPing` --uses--> `HealthChecker`  [INFERRED]
  tests/pytest/test_health_check.py → shared/python/health_check.py

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Ansible Orchestration Playbooks** — proxmox_ansible_playbooks_site, proxmox_ansible_playbooks_cluster_setup, proxmox_ansible_playbooks_ceph_setup, proxmox_ansible_playbooks_network_setup, proxmox_ansible_playbooks_backup_setup, proxmox_ansible_playbooks_deploy_vms, proxmox_ansible_playbooks_deploy_cts, proxmox_ansible_playbooks_hardening, proxmox_ansible_playbooks_patching, proxmox_ansible_playbooks_sdn_setup, proxmox_ansible_playbooks_monitoring_stack [INFERRED 0.85]
- **Operational Runbooks** — docs_runbooks_backup_recovery, docs_runbooks_ceph_recovery, docs_runbooks_failed_migration, docs_runbooks_node_failure, docs_runbooks_split_brain, docs_runbooks_storage_full [INFERRED 0.85]
- **Design Goals and Language Rationale** — docs_architecture, unified_interface, multi_layered_tooling, resilience_by_default, observability, testability, go_for_cli_tui, python_for_complex_logic, bash_for_direct_ops, terraform_for_iac, packer_for_image_building, ansible_for_config_mgmt, configuration_hierarchy, dry_run_mode, secrets_management [EXTRACTED 1.00]

## Communities (199 total, 39 thin omitted)

### Community 0 - "TUI Action Executor"
Cohesion: 0.09
Nodes (10): CancelFunc, Client, Cmd, Context, LibvirtClient, Logger, Mutex, NewActionExecutor() (+2 more)

### Community 1 - "Configuration System"
Cohesion: 0.07
Nodes (43): AlertsConfig, Config, DefaultsConfig, KVMConfig, NotificationsConfig, ProxmoxConfig, SSHConfig, TUIConfig (+35 more)

### Community 2 - "KVM Libvirt Client"
Cohesion: 0.06
Nodes (31): SPDX-License-Identifier: MIT VM backup operations via virsh, qemu-img, and QMP., SPDX-License-Identifier: MIT Reusable libvirt connection wrapper for KVM/libvirt, Convert a libvirt error into the custom LibvirtError., _wrap_libvirt_error(), FleetDeployer, LibvirtClient, SPDX-License-Identifier: MIT Fleet deployment: create multiple VMs in parallel f, Stop, undefine, and remove disks for all VMs matching *name_prefix*.          Ar (+23 more)

### Community 3 - "PVE API Client"
Cohesion: 0.08
Nodes (22): PVEClient, Any, BaseException, Authenticate against the Proxmox API., Close the underlying HTTP connection., Execute an HTTP request with retry and rate-limiting., Send a DELETE request., Return all cluster nodes. (+14 more)

### Community 4 - "Architecture & Design"
Cohesion: 0.05
Nodes (47): Ansible 2.16+, API Token Authentication, Bubble Tea TUI Framework, Central Configuration (config/settings.yaml), Engineering Documentation (sketchnote-documentation.html), TUI Application Guide (docs/TUI.md), Dry-Run Mode for Destructive Actions, Go Lint Configuration (.golangci-lint.yml) (+39 more)

### Community 5 - "Proxmox Template Manager"
Cohesion: 0.06
Nodes (24): Any, Delete a template (must be a template, not a running VM).          .. warning::, Update template metadata (description)., High-level template operations.      Parameters     ----------     client:, Convert an existing VM into a template.          .. warning::             The VM, List available VM templates.          Parameters         ----------         node, Clone a VM from a template.          Parameters         ----------         templ, TemplateManager (+16 more)

### Community 6 - "Architecture Concepts"
Cohesion: 0.05
Nodes (44): Ansible for Configuration Management, Bash for Direct Node Operations, Configuration Hierarchy (flags > env > .env > settings.yaml > defaults), Corosync Quorum (majority vote), Dedicated Migration Network, Architecture Document, KVM Operations Reference, Proxmox Operations Reference (+36 more)

### Community 7 - "CPU Pinning & Libvirt"
Cohesion: 0.06
Nodes (24): Apply vCPU pinning and optional NUMA settings to a domain.          Args:, LibvirtClient, Any, BaseException, Return the underlying ``virConnect``, connecting first if needed.          Raise, Return domains according to the requested filter flags.          Args:, Look up a domain by name *or* integer id.          Args:             name_or_id:, Return libvirt networks matching *active* / *inactive* flags. (+16 more)

### Community 8 - "Shared Bash Library"
Cohesion: 0.08
Nodes (34): api_call(), BLUE, BOLD, check_prereqs(), check_root(), cleanup(), confirm(), CYAN (+26 more)

### Community 9 - "Notification System"
Cohesion: 0.08
Nodes (21): _http_post(), NotificationManager, Any, Send an email notification via SMTP.          Parameters         ----------, Send a message to Slack via incoming webhook.          Parameters         ------, Send a message via the Telegram Bot API.          Parameters         ----------, Send a notification via ntfy.sh (or self-hosted instance).          Parameters, Send an incident alert to PagerDuty Events API v2.          Parameters         - (+13 more)

### Community 10 - "Report Generator"
Cohesion: 0.09
Nodes (20): Any, Generate reports in Markdown, HTML, and JSON formats.      Parameters     ------, Generate a Markdown report.          Parameters         ----------         title, Render a list of row dicts into a Markdown table., Generate a styled HTML report.          Parameters         ----------         ti, Render rows into an HTML table., Escape HTML special characters., Convert a small subset of Markdown to HTML. (+12 more)

### Community 11 - "KVM QMP Client"
Cohesion: 0.09
Nodes (19): Any, BaseException, Exception, QMPClient, QMPError, SPDX-License-Identifier: MIT QEMU Machine Protocol (QMP) client over Unix socket, Execute a QMP command.          Args:             command: QMP command name (e.g, Return the current run status of the VM.          Returns:             Dict with (+11 more)

### Community 12 - "KVM Disk Manager"
Cohesion: 0.11
Nodes (22): DiskError, DiskManager, Any, CompletedProcess, Exception, SPDX-License-Identifier: MIT Disk image management via qemu-img.  Provides ``Dis, Convert a disk image to another format.          Args:             source: Sourc, Resize a disk image to the given total size in GiB.          Returns: (+14 more)

### Community 13 - "Go QMP Client"
Cohesion: 0.12
Nodes (10): Conn, Mutex, RawMessage, NewQMPClient(), QMPClient, QMPError, QMPResponse, QMPStatus (+2 more)

### Community 14 - "CPU Pinning"
Cohesion: 0.09
Nodes (21): CPUError, Exception, SPDX-License-Identifier: MIT CPU topology detection and vCPU-to-pCPU pinning.  P, Raised when a CPU pinning operation fails., LibvirtError, Exception, Raised when a libvirt API call fails., _ensure_client() (+13 more)

### Community 15 - "GPU Passthrough"
Cohesion: 0.11
Nodes (15): GPUError, GPUPassthrough, Any, Exception, SPDX-License-Identifier: MIT GPU detection, IOMMU, VFIO binding, and passthrough, Return IOMMU group mapping for all PCI devices.          Returns:             Di, Print instructions for enabling IOMMU via kernel parameters.          IOMMU requ, Bind a PCI device to the ``vfio-pci`` driver.          Args:             pci_add (+7 more)

### Community 16 - "Inventory Parser"
Cohesion: 0.08
Nodes (18): BaseModel, pydantic>=2.0.0, HostEntry, Inventory, InventoryParser, Any, Load and parse the YAML file., Validate the inventory using pydantic models. (+10 more)

### Community 17 - "TUI Sparkline"
Cohesion: 0.08
Nodes (6): generateSampleData(), Color, NewSparklineModel(), NewSparklineWithData(), Model, SparklineModel

### Community 18 - "KVM Backup Manager"
Cohesion: 0.13
Nodes (17): BackupError, BackupManager, Any, CompletedProcess, Exception, LibvirtClient, Return the QMP monitor socket path for a domain., Perform a full backup by converting disk images.          Args:             doma (+9 more)

### Community 19 - "Performance Manager"
Cohesion: 0.09
Nodes (17): PerformanceError, PerformanceManager, Any, CompletedProcess, Exception, LibvirtClient, SPDX-License-Identifier: MIT VM performance tuning: hugepages, CPU pinning, NUMA, Pin vCPUs to physical CPUs via libvirt XML.          Args:             domain: D (+9 more)

### Community 20 - "Pytest Test Fixtures"
Cohesion: 0.07
Nodes (25): mock_libvirt(), mock_pve_client(), MockTransport, Shared fixtures for proxmox-kvm-swissknife pytest tests., Dictionary with typical VM configuration from Proxmox API., Dictionary with typical node info from Proxmox API., List of storage entries from Proxmox API., List of backup entries from Proxmox API. (+17 more)

### Community 21 - "ZFS Management"
Cohesion: 0.14
Nodes (28): do_arc_set_limit(), do_arc_usage(), do_dataset_create(), do_dataset_destroy(), do_dataset_list(), do_dataset_rename(), do_pool_create(), do_pool_destroy() (+20 more)

### Community 22 - "KVM Monitoring"
Cohesion: 0.13
Nodes (14): MonitoringManager, Any, CompletedProcess, LibvirtClient, Return memory statistics for a domain.          Uses ``virsh dommemstat``., Return block (disk) I/O statistics for a domain.          Uses ``virsh domblksta, Return network interface statistics for a domain.          Uses ``virsh domifsta, Return stats for all running domains.          Returns:             List of per- (+6 more)

### Community 23 - "Health Check"
Cohesion: 0.12
Nodes (15): HealthChecker, Any, Ping a host and report reachability and latency.          Parameters         ---, Test SSH connectivity and capture the server banner.          Parameters, Check whether a TCP port is open.          Parameters         ----------, Check disk usage for the local or a remote host.          Parameters         ---, Check memory usage for the local or a remote host.          Parameters         -, Check CPU load average for the local or a remote host.          Parameters (+7 more)

### Community 24 - "KVMCTL CLI"
Cohesion: 0.13
Nodes (17): Command, main(), newBackupCmd(), newCloudInitCmd(), newDiskCmd(), newHealthCmd(), newNetCmd(), newPassthroughCmd() (+9 more)

### Community 25 - "Kvm Python"
Cohesion: 0.11
Nodes (15): _ensure_client(), NetworkManager, LibvirtClient, SPDX-License-Identifier: MIT Virtual network lifecycle management via libvirt., Define a new virtual network.          Args:             name: Network name., Undefine and destroy a network.          Args:             name: Network name., List networks with summary information.          Returns:             List of di, Start a defined network.          Args:             name: Network name. (+7 more)

### Community 26 - "Kvm Python"
Cohesion: 0.11
Nodes (17): Any, CompletedProcess, Exception, LibvirtClient, SPDX-License-Identifier: MIT VM snapshot management via virsh and qemu-img.  Pro, List all snapshots for a domain.          Returns:             List of dicts wit, Revert a domain to a named snapshot.          Args:             domain: Domain n, Delete a named snapshot.          Args:             domain: Domain name. (+9 more)

### Community 27 - "Kvm Python"
Cohesion: 0.12
Nodes (14): Any, Exception, SPDX-License-Identifier: MIT SR-IOV NIC detection, VF creation, and passthrough., Alias for :meth:`enable_sriov`., List virtual functions, optionally filtered by a PF.          Args:, Bind a VF to a host driver.          Args:             vf_address: PCI address o, Unbind a VF from its current driver and return it to the PF., Return a mapping of IOMMU group numbers to PCI device addresses.          Return (+6 more)

### Community 28 - "Proxmox Bash"
Cohesion: 0.15
Nodes (24): do_alias_create(), do_alias_delete(), do_aliases_list(), do_disable(), do_enable(), do_ipset_add_cidr(), do_ipset_create(), do_ipset_delete() (+16 more)

### Community 29 - "Ceph & Cluster Concepts"
Cohesion: 0.09
Nodes (25): Ceph cluster, Ceph OSD, Ceph pool, IPset, Proxmox VE cluster, Proxmox VE firewall, Corosync firewall rule, Proxmox API firewall rule (+17 more)

### Community 30 - "Kvm Python"
Cohesion: 0.12
Nodes (15): BackingChain, ChainError, Any, CompletedProcess, Exception, SPDX-License-Identifier: MIT Qcow2 backing-chain management via qemu-img.  Provi, Commit *path*'s changes into its backing file.          After committing, the ba, Rebase *path* onto a new (or no) backing file.          Args:             path: (+7 more)

### Community 31 - "Proxmox Bash"
Cohesion: 0.16
Nodes (24): do_acl_remove(), do_acl_set(), do_group_create(), do_group_delete(), do_groups_list(), do_role_create(), do_role_delete(), do_roles_list() (+16 more)

### Community 32 - "Proxmox Python"
Cohesion: 0.13
Nodes (9): Any, Create a role with the given privileges.          Parameters         ----------, Grant a role to a user or group on a path.          Parameters         ---------, High-level user, group, role, ACL and token operations.      Parameters     ----, List API tokens for a user., Create an API token.          Parameters         ----------         userid:, Create a new user.          Parameters         ----------         userid:, Set a user password (admin only). (+1 more)

### Community 33 - "Proxmox Python"
Cohesion: 0.12
Nodes (12): Any, Destroy a ZFS dataset., Get a single ZFS property value., Return ZFS scrub status for a pool., High-level ZFS operations on Proxmox nodes.      Parameters     ----------     c, List ZFS pools on a node., Create a ZFS pool.          Parameters         ----------         name:, Destroy a ZFS pool (dangerous!). (+4 more)

### Community 34 - "Tests Pytest"
Cohesion: 0.13
Nodes (12): _build_client(), _FakeTransport, _get_client_class(), Tests for the Proxmox API HTTP client (PVEClient)., Instantiate PVEClient with a mock transport, or fall back to MagicMock., Minimal httpx transport that returns canned responses., TestPVEClientContextManager, TestPVEClientErrors (+4 more)

### Community 35 - "Tui Model"
Cohesion: 0.17
Nodes (7): Client, Cmd, LibvirtClient, Msg, Model, scanPCI(), KeyMsg

### Community 36 - "Kvm Python"
Cohesion: 0.13
Nodes (14): CloudInitError, CloudInitManager, CompletedProcess, Exception, LibvirtClient, SPDX-License-Identifier: MIT Cloud-init ISO generation and domain configuration., Locate genisoimage or mkisofs., Attach a cloud-init ISO as a SATA CDROM to the domain.          Args: (+6 more)

### Community 37 - "Proxmox Python"
Cohesion: 0.13
Nodes (11): CephManager, Any, Set the replication size of a pool., Create an OSD on the given block device., Reweight an OSD.          Parameters         ----------         weight:, Trigger a scrub operation.          Parameters         ----------         pool:, High-level Ceph operations through the Proxmox API.      Parameters     --------, Return overall Ceph cluster status. (+3 more)

### Community 38 - "Proxmox Python"
Cohesion: 0.13
Nodes (12): CapacityReport, Any, Return storage capacity summary, optionally per-node., Return a list of all VMs and containers across the cluster., Forecast storage usage using simple linear regression.          Parameters, Cluster capacity and inventory reporting.      Parameters     ----------     cli, Convert a capacity report to Markdown format., Convert a capacity report to an HTML page. (+4 more)

### Community 39 - "Proxmox Python"
Cohesion: 0.16
Nodes (11): FirewallManager, Any, Delete a firewall rule by its position., Move a firewall rule up or down.          Parameters         ----------, Build the API path prefix for a firewall scope., Add a CIDR entry to an IP set.          Parameters         ----------         ip, High-level Proxmox firewall operations.      Parameters     ----------     clien, Enable the firewall at the given scope. (+3 more)

### Community 40 - "Tests Pytest"
Cohesion: 0.14
Nodes (10): _get_manager_class(), _make_manager(), Tests for VMManager operations against the Proxmox API., TestVMManagerBatch, TestVMManagerClone, TestVMManagerConfig, TestVMManagerCreate, TestVMManagerDelete (+2 more)

### Community 41 - "Proxmox Client"
Cohesion: 0.14
Nodes (6): decodeJSON(), Client, ACL, Token, User, UserCreateRequest

### Community 42 - "Kvm Python"
Cohesion: 0.13
Nodes (14): DiskEncryption, EncryptionError, CompletedProcess, Exception, LibvirtClient, SPDX-License-Identifier: MIT LUKS disk encryption and libvirt secret management., Open a LUKS volume and expose it as a device-mapper mapping.          Args:, Close (lock) a device-mapper LUKS mapping.          Args:             name: Devi (+6 more)

### Community 43 - "Proxmox Bash"
Cohesion: 0.18
Nodes (21): do_deploy(), do_fs_create(), do_fs_delete(), do_fs_status(), do_health(), do_osd_add(), do_osd_list(), do_osd_remove() (+13 more)

### Community 44 - "Proxmox Python"
Cohesion: 0.13
Nodes (10): CTManager, Any, Gracefully shut down a container., Resize the root filesystem of a container.          Parameters         ---------, Update container features.          Parameters         ----------         nestin, High-level LXC container lifecycle operations.      Parameters     ----------, Configure container DNS settings.          Parameters         ----------, Return the full configuration of a container. (+2 more)

### Community 45 - "Proxmox Client"
Cohesion: 0.13
Nodes (5): Client, FirewallCreateRequest, FirewallRule, IPSec, IPSet

### Community 46 - "Proxmox Ansible"
Cohesion: 0.10
Nodes (21): proxmox_storage role vars (empty), VM definition: app-server (commented out, VMID 102), VM definition: database-server (VMID 101), VM definition: web-server (VMID 100), Handler: reboot VM via community.general.proxmox, Task: configure cloud-init for VMs, Task: configure VM disks, Task: configure VM network interfaces (+13 more)

### Community 47 - "Proxmox Python"
Cohesion: 0.15
Nodes (11): BulkOperations, Any, Create snapshots for multiple VMs in parallel., Add a tag to multiple VMs in parallel., Execute an operation on all members of a Proxmox resource pool.          Paramet, Batch operations for managing multiple VMs efficiently.      Parameters     ----, Execute an operation on multiple VMs in parallel., Start multiple VMs in parallel. (+3 more)

### Community 48 - "Proxmox Python"
Cohesion: 0.13
Nodes (11): NetworkManager, Any, Delete a network bond., Create a VLAN interface.          Parameters         ----------         name:, Delete a VLAN interface., Apply pending network configuration changes., High-level network configuration operations on Proxmox nodes.      Parameters, List network interfaces on a node. (+3 more)

### Community 49 - "Proxmox Python"
Cohesion: 0.14
Nodes (9): Any, List subnets across all VNets., Create a subnet within a VNet.          Parameters         ----------         vn, High-level SDN zone, VNet and subnet operations.      Parameters     ----------, Apply pending SDN configuration., List SDN zones on a node., Create an SDN zone.          Parameters         ----------         zone_id:, Create a VNet.          Parameters         ----------         vnet_id: (+1 more)

### Community 50 - "Shared Python"
Cohesion: 0.12
Nodes (11): Build the SSH command vector., Run command via native OpenSSH subprocess., Run command via paramiko as a fallback transport., Execute a command with retry logic., Execute a single command on the remote host.          Parameters         -------, Execute commands on multiple hosts in parallel.          Parameters         ----, Execute a local script file on the remote host.          The script is read loca, Run a local command via subprocess.      Parameters     ----------     command : (+3 more)

### Community 51 - "Tests Pytest"
Cohesion: 0.15
Nodes (9): _get_checker_class(), _make_checker(), Tests for HealthChecker (ping, SSH, port, disk, memory)., TestHealthCheckerAll, TestHealthCheckerDisk, TestHealthCheckerMemory, TestHealthCheckerPing, TestHealthCheckerPort (+1 more)

### Community 52 - "Proxmox Python"
Cohesion: 0.17
Nodes (11): AlertManager, Any, Check disk usage across all nodes., Check for HA-managed VMs that are unexpectedly stopped., Check for failed backup tasks., Check Ceph cluster health status., Run all health checks and return aggregated alerts., Dispatch alerts via the configured notification transport.          Returns a su (+3 more)

### Community 53 - "Cloud Images & Containers"
Cohesion: 0.14
Nodes (19): Debian 12 cloud image, Rocky Linux 9 cloud image, Ubuntu 24.04 cloud image, Cloud-Init VM template, LXC container, monitor-ct container, web-ct container, proxmox_cloudinit defaults/main.yml (+11 more)

### Community 54 - "Kvm Vmoperation"
Cohesion: 0.12
Nodes (3): LibvirtClient, NewVMOperation(), VMOperation

### Community 55 - "Proxmox Client"
Cohesion: 0.18
Nodes (5): Client, CloneRequest, VM, VMCreateRequest, VMStatus

### Community 56 - "Kvm Bash"
Cohesion: 0.21
Nodes (18): action_autostart(), action_create(), action_define(), action_destroy(), action_list(), action_restore(), action_resume(), action_save() (+10 more)

### Community 57 - "Kvm Python"
Cohesion: 0.14
Nodes (11): NUMAError, NUMATopology, Any, Exception, SPDX-License-Identifier: MIT Host and VM NUMA topology detection and configurati, Map a VM's NUMA node to a specific host NUMA node.          This modifies the do, Return the NUMA configuration of a domain.          Returns:             Dict wi, Raised when a NUMA operation fails. (+3 more)

### Community 58 - "Proxmox Bash"
Cohesion: 0.26
Nodes (16): do_clone(), do_create(), do_delete(), do_reboot(), do_rename(), do_resume(), do_shutdown(), do_start() (+8 more)

### Community 59 - "Proxmox Python"
Cohesion: 0.14
Nodes (10): CertificateManager, Any, Request an ACME certificate for a domain.          Parameters         ----------, List registered ACME accounts., Register a new ACME account.          Parameters         ----------         emai, High-level certificate and ACME operations.      Parameters     ----------     c, List SSL certificates on a node., Upload a custom SSL certificate and private key.          Parameters         --- (+2 more)

### Community 60 - "Proxmox Python"
Cohesion: 0.15
Nodes (9): HAManager, Any, Remove a resource from HA management., Set the desired state of an HA resource.          Parameters         ----------, Return overall HA manager status., High-level HA group and resource operations.      Parameters     ----------, Create an HA group.          Parameters         ----------         group_id:, List all HA-managed resources. (+1 more)

### Community 61 - "Proxmox Python"
Cohesion: 0.14
Nodes (10): PBSManager, Any, Restore a VM / container from a PBS backup.          Parameters         --------, Verify the integrity of PBS backup data.          Parameters         ----------, High-level Proxmox Backup Server operations.      Parameters     ----------, Prune old backups on a PBS datastore.          Parameters         ----------, Return status of a PBS datastore., Register a PBS datastore as a Proxmox backup target.          Parameters (+2 more)

### Community 62 - "Proxmox Python"
Cohesion: 0.14
Nodes (10): Any, Move a VM disk to a different storage.          Parameters         ----------, Import a disk image into a VM.          Parameters         ----------         fi, High-level storage operations on Proxmox nodes.      Parameters     ----------, Add a storage backend.          Parameters         ----------         node:, Remove a storage backend from a node., List storage backends.          Parameters         ----------         node:, Return status of a specific storage on a node. (+2 more)

### Community 63 - "Kvm Networkoperation"
Cohesion: 0.13
Nodes (4): LibvirtClient, NewNetworkOperation(), Network, NetworkOperation

### Community 64 - "Proxmox Client"
Cohesion: 0.16
Nodes (8): Client, RawMessage, ClusterConfig, ClusterNode, ClusterStatus, NodeDisk, NodeInfo, NodeMemory

### Community 65 - "Proxmox Client"
Cohesion: 0.16
Nodes (4): Client, RawMessage, NetworkCreateRequest, NetworkInterface

### Community 66 - "Proxmox Client"
Cohesion: 0.14
Nodes (5): Client, RawMessage, SDNSubnet, SDNVnet, SDNZone

### Community 67 - "Proxmox Bash"
Cohesion: 0.24
Nodes (17): do_apply(), do_bond_create(), do_bond_delete(), do_bond_list(), do_bridge_create(), do_bridge_delete(), do_bridge_list(), do_status() (+9 more)

### Community 68 - "Proxmox Client"
Cohesion: 0.17
Nodes (4): Client, HAGroup, HAResource, HAStatus

### Community 69 - "Tui Logviewmodel"
Cohesion: 0.15
Nodes (5): formatScrollInfo(), Model, NewLogViewModel(), truncateStyled(), LogViewModel

### Community 70 - "Kvm Bash"
Cohesion: 0.21
Nodes (13): action_assign(), action_bind(), action_detect(), action_enable_iommu(), action_iommu_groups(), action_unbind(), action_usb(), action_verify() (+5 more)

### Community 71 - "Kvm Python"
Cohesion: 0.16
Nodes (9): CPUPinning, Any, Return NUMA node to CPU mapping., Expand a CPU set string like ``0-3,8`` into a list of ints., Generate ``<cputune>`` XML for the given vCPU-to-pCPU mapping.          Args:, Generate ``<numatune>`` XML.          Args:             mode: ``strict`` or ``in, Return the current CPU pinning configuration for a domain.          Returns:, CPU topology detection and vCPU pinning.      Example::          cp = CPUPinning (+1 more)

### Community 72 - "Proxmox Bash"
Cohesion: 0.26
Nodes (16): do_apply(), do_status(), do_subnet_create(), do_subnet_delete(), do_subnets(), do_vnet_create(), do_vnet_delete(), do_vnets() (+8 more)

### Community 73 - "Proxmox Python"
Cohesion: 0.15
Nodes (9): BackupManager, Any, List available backups.          Parameters         ----------         node:, Verify the integrity of a backup., High-level backup and restore operations via VZDump.      Parameters     -------, Prune old backups according to retention policy.          Parameters         ---, Create or update a scheduled backup job.          Parameters         ----------, Trigger a backup for a VM or container.          Parameters         ---------- (+1 more)

### Community 74 - "Proxmox Python"
Cohesion: 0.15
Nodes (9): ClusterManager, Any, Return cluster quorum status., High-level Proxmox cluster operations.      Parameters     ----------     client, Return the overall cluster status., Create a new cluster on *node*.          Parameters         ----------         c, Join an existing cluster.          Parameters         ----------         node:, Remove a node from the cluster.          This sends a ``delnode`` request. The n (+1 more)

### Community 75 - "Proxmox Python"
Cohesion: 0.18
Nodes (9): PXEMonitoring, Any, Generate Prometheus text-format metrics for the entire cluster., Check metrics against configurable thresholds and return alerts.          Parame, Metrics collection and monitoring for Proxmox VE.      Parameters     ----------, Fetch RRD (round-robin database) metrics for a node.          Parameters, Return cluster-wide resource summary (VMs, nodes, storage)., Collect CPU, memory, disk and network metrics for a node. (+1 more)

### Community 76 - "Proxmox Python"
Cohesion: 0.17
Nodes (9): PassthroughManager, Any, Assign a GPU to a VM via PCI passthrough.          Parameters         ----------, Assign a generic PCI device to a VM., Verify PCI passthrough configuration for a VM.          Returns a dict with IOMM, High-level PCI passthrough operations.      Parameters     ----------     client, List PCI devices on a node., Group PCI devices by their IOMMU group.          Returns a dict mapping group-id (+1 more)

### Community 77 - "Proxmox Python"
Cohesion: 0.18
Nodes (9): Any, Generate a formatted audit report.          Parameters         ----------, Audit VM configurations for drift and compliance.      Parameters     ----------, Return the live (running) configuration of a VM., Extract disk-specific configuration.          Returns a dict mapping disk name (, Parse a Proxmox disk configuration string.          Example: ``local-lvm:vm-100-, Compare two configuration dicts and return differences.          Returns a dict, Perform a full audit of a VM.          Returns a comprehensive audit report incl (+1 more)

### Community 78 - "Backup & Ceph Concepts"
Cohesion: 0.15
Nodes (16): backup retention policy, backup schedule nightly, backup schedule weekend full, ceph CRUSH rules, Ceph MDS, Ceph Monitor, Ceph OSD, ceph pool ceph-hdd (+8 more)

### Community 79 - "Go Internal"
Cohesion: 0.24
Nodes (14): GetAllDomainStats(), GetBlockStats(), GetDomainStats(), GetInterfaceStats(), GetJSONStats(), GetMemoryStats(), GetNetworkStats(), RawMessage (+6 more)

### Community 80 - "Proxmox Client"
Cohesion: 0.16
Nodes (7): Client, RawMessage, Backup, BackupPruneRequest, BackupRequest, BackupStatus, BackupVerifyRequest

### Community 81 - "Proxmox Client"
Cohesion: 0.17
Nodes (4): Client, Container, ContainerCreateRequest, ContainerStatus

### Community 82 - "Kvm Bash"
Cohesion: 0.25
Nodes (15): action_benchmark(), action_check(), action_convert(), action_create(), action_customize(), action_info(), action_resize(), action_resize_fs() (+7 more)

### Community 83 - "Proxmox Bash"
Cohesion: 0.30
Nodes (14): do_clone(), do_create(), do_delete(), do_resize(), do_set_features(), do_shutdown(), do_start(), do_stop() (+6 more)

### Community 84 - "Proxmox Bash"
Cohesion: 0.25
Nodes (15): do_failover_test(), do_group_create(), do_group_delete(), do_group_modify(), do_groups(), do_resource_add(), do_resource_remove(), do_resource_state() (+7 more)

### Community 85 - "Sshexec Executor"
Cohesion: 0.24
Nodes (4): Duration, New(), Executor, Result

### Community 86 - "Proxmox Client"
Cohesion: 0.19
Nodes (6): Client, RawMessage, Time, ClusterResource, PrometheusMetrics, RRDData

### Community 87 - "Proxmox Client"
Cohesion: 0.18
Nodes (6): Client, RawMessage, Storage, StorageContent, StorageCreateRequest, StorageStatus

### Community 88 - "Kvm Bash"
Cohesion: 0.29
Nodes (13): action_full(), action_incremental(), action_list(), action_live(), action_offline(), get_disk_devices(), get_disk_path(), main() (+5 more)

### Community 89 - "Kvm Bash"
Cohesion: 0.31
Nodes (14): action_domain(), action_host(), action_network(), action_report(), action_storage(), add_alert(), check_domain_health(), generate_json_report() (+6 more)

### Community 90 - "Kvm Bash"
Cohesion: 0.29
Nodes (14): action_autostart(), action_create(), action_delete(), action_dhcp(), action_leases(), action_list(), action_start(), action_stop() (+6 more)

### Community 91 - "Proxmox Ansible"
Cohesion: 0.13
Nodes (15): GPU Passthrough, IOMMU, PCI Passthrough, proxmox_passthrough, VFIO, Blacklist GPU drivers, Configure VFIO modules, Create VFIO configuration (+7 more)

### Community 92 - "Proxmox Bash"
Cohesion: 0.26
Nodes (12): do_alert(), do_ceph(), do_cluster(), do_node(), do_report(), do_storage(), do_vm(), main() (+4 more)

### Community 93 - "Proxmox Python"
Cohesion: 0.17
Nodes (8): CloudInitManager, Any, Regenerate the CloudInit drive.          This rebuilds the CloudInit ISO from th, Return the rendered CloudInit configuration (user-data, network-data, meta-data), Download a CloudInit-ready OS image template.          Parameters         ------, Convert a configured VM into a CloudInit template.          Parameters         -, High-level CloudInit configuration and image operations.      Parameters     ---, Configure CloudInit parameters for a VM.          Parameters         ----------

### Community 94 - "Tests Pytest"
Cohesion: 0.20
Nodes (8): _get_manager_class(), _make_manager(), Tests for BackupManager operations., TestBackupManagerBackup, TestBackupManagerList, TestBackupManagerPrune, TestBackupManagerRestore, TestBackupManagerVerify

### Community 95 - "Tests Pytest"
Cohesion: 0.21
Nodes (7): _get_manager_class(), _make_manager(), Tests for CephManager operations., TestCephManagerOSDs, TestCephManagerPool, TestCephManagerScrub, TestCephManagerStatus

### Community 96 - "Tests Pytest"
Cohesion: 0.20
Nodes (8): _get_manager_class(), _make_manager(), Tests for CTManager (LXC container operations)., TestCTManagerClone, TestCTManagerCreate, TestCTManagerFeatures, TestCTManagerResize, TestCTManagerStartStop

### Community 97 - "Kvm Snapshotoperation"
Cohesion: 0.19
Nodes (4): LibvirtClient, NewSnapshotOperation(), DomainSnapshot, SnapshotOperation

### Community 98 - "Kvm Bash"
Cohesion: 0.35
Nodes (13): action_attach(), action_configure(), action_create_iso(), action_dump(), generate_meta_data(), generate_network_config(), generate_user_data(), main() (+5 more)

### Community 99 - "Kvm Bash"
Cohesion: 0.30
Nodes (13): action_balloon(), action_cpu_pin(), action_hugepages(), action_io_tune(), action_kernel(), action_numa(), action_status(), main() (+5 more)

### Community 100 - "Kvm Python"
Cohesion: 0.15
Nodes (9): FleetError, Any, Exception, Deploy a single VM from the fleet spec., Wait for SSH to become available on a domain.          Uses ``virsh domifaddr``, Run a shell script on a VM via virsh., Raised when a fleet operation fails., List VMs, optionally filtered by name prefix.          Returns:             List (+1 more)

### Community 101 - "Proxmox Bash"
Cohesion: 0.29
Nodes (13): do_assign(), do_blacklist(), do_blacklist_add(), do_blacklist_del(), do_configure(), do_detect(), do_enable(), do_verify() (+5 more)

### Community 102 - "Proxmox Bash"
Cohesion: 0.27
Nodes (12): do_add(), do_import_disk(), do_list(), do_move_disk(), do_remove(), do_resize_disk(), do_status(), main() (+4 more)

### Community 103 - "Tests Pytest"
Cohesion: 0.22
Nodes (7): _get_manager_class(), _make_manager(), Tests for SnapshotManager operations., TestSnapshotManagerCreate, TestSnapshotManagerDelete, TestSnapshotManagerList, TestSnapshotManagerRollback

### Community 104 - "Tests Pytest"
Cohesion: 0.22
Nodes (7): _get_manager_class(), _make_manager(), Tests for StorageManager operations., TestStorageManagerAdd, TestStorageManagerList, TestStorageManagerMoveDisk, TestStorageManagerRemove

### Community 105 - "Tests Pytest"
Cohesion: 0.22
Nodes (7): _get_manager_class(), _make_manager(), Tests for UserACLManager (users, groups, tokens, ACL)., TestUserACLManagerACL, TestUserACLManagerGroups, TestUserACLManagerTokens, TestUserACLManagerUsers

### Community 106 - "Tests Pytest"
Cohesion: 0.23
Nodes (6): _get_manager_class(), _make_manager(), Tests for ZFSManager operations., TestZFSManagerDatasets, TestZFSManagerPools, TestZFSManagerScrub

### Community 107 - "Kvm Domain"
Cohesion: 0.27
Nodes (3): runDomainCmd(), writeFile(), Domain

### Community 109 - "Proxmox Client"
Cohesion: 0.19
Nodes (3): Client, MigrationStatus, Values

### Community 110 - "Go Internal"
Cohesion: 0.24
Nodes (6): Cmd, Model, Msg, Model, NewConfirmModel(), ConfirmModel

### Community 111 - "Go Internal"
Cohesion: 0.28
Nodes (7): Cmd, Model, Msg, Model, NewFormModel(), FormField, FormModel

### Community 112 - "Kvm Bash"
Cohesion: 0.31
Nodes (12): action_add_port(), action_bond(), action_create_bridge(), action_delete_bridge(), action_delete_port(), action_list(), action_vxlan(), main() (+4 more)

### Community 113 - "Kvm Bash"
Cohesion: 0.32
Nodes (11): action_info(), action_kill(), action_launch(), action_migrate(), action_monitor(), main(), parse_args(), send_qmp_command() (+3 more)

### Community 114 - "Kvm Bash"
Cohesion: 0.31
Nodes (12): action_commit(), action_create(), action_delete(), action_external(), action_list(), action_revert(), main(), parse_args() (+4 more)

### Community 115 - "Proxmox Ansible"
Cohesion: 0.15
Nodes (13): Patching defaults configuration, Patching service restart handlers, Cluster Patching, HA Resource Drain, proxmox_patching, Rolling Update, Drain HA resources, Post-patch verification (+5 more)

### Community 116 - "Proxmox Ansible"
Cohesion: 0.15
Nodes (13): SDN defaults configuration, SDN apply config handler, proxmox_sdn, Software Defined Networking, SDN Subnet, SDN VNet, SDN Zone, Apply SDN configuration (+5 more)

### Community 117 - "Proxmox Bash"
Cohesion: 0.32
Nodes (12): do_enter(), do_exit(), do_health(), do_reboot(), do_reboot_internal(), do_shutdown(), do_update(), main() (+4 more)

### Community 118 - "Proxmox Bash"
Cohesion: 0.31
Nodes (12): do_assign(), do_bind(), do_groups(), do_list(), do_override(), do_unbind(), do_verify(), main() (+4 more)

### Community 119 - "Proxmox Bash"
Cohesion: 0.29
Nodes (11): do_assign(), do_create_vfs(), do_detect(), do_enable(), do_persistent(), do_status(), main(), parse_args() (+3 more)

### Community 120 - "Proxmox Python"
Cohesion: 0.15
Nodes (4): RateLimiter, Token-bucket rate limiter for API requests., Block until enough time has elapsed since the last request., Establish the underlying HTTP client and authenticate.

### Community 121 - "Proxmox Python"
Cohesion: 0.22
Nodes (7): MigrationManager, Any, Evacuate all VMs from a node.          Parameters         ----------         nod, High-level live migration operations.      Parameters     ----------     client:, Migrate a VM or container to another node.          Parameters         ---------, Return migration status for a VM., Migrate multiple VMs sequentially.          Returns a mapping of VMID → result d

### Community 122 - "Tests Pytest"
Cohesion: 0.24
Nodes (6): _get_manager_class(), _make_manager(), Tests for PXEMonitoring (RRD data, Prometheus export, thresholds)., TestPXEMonitoringPrometheus, TestPXEMonitoringRRD, TestPXEMonitoringThresholds

### Community 123 - "Tui Progressmodel"
Cohesion: 0.20
Nodes (3): Model, NewProgressModel(), ProgressModel

### Community 124 - "Tests Go"
Cohesion: 0.33
Nodes (11): Header, Server, defaultHeaders(), HandlerFunc, T, newTestServer(), TestGetRequest(), TestNewClient() (+3 more)

### Community 125 - "Proxmox Ansible"
Cohesion: 0.17
Nodes (12): Storage defaults configuration, Storage refresh handlers, proxmox_storage, Storage Backend, Configure Ceph RBD storage, Configure directory storage, Configure LVM storage, Configure LVM-thin storage (+4 more)

### Community 126 - "Proxmox Bash"
Cohesion: 0.33
Nodes (11): do_backup(), do_list(), do_prune(), do_restore(), do_schedule(), do_verify(), main(), parse_args() (+3 more)

### Community 127 - "Proxmox Bash"
Cohesion: 0.33
Nodes (11): do_create(), do_join(), do_nodes(), do_quorum(), do_remove(), do_status(), main(), parse_args() (+3 more)

### Community 128 - "Proxmox Bash"
Cohesion: 0.33
Nodes (11): do_add_datastore(), do_backup(), do_prune(), do_restore(), do_status(), do_verify(), main(), parse_args() (+3 more)

### Community 129 - "Proxmox Python"
Cohesion: 0.21
Nodes (6): Any, High-level snapshot operations for VMs and LXC containers.      Parameters     -, Create a snapshot.          Parameters         ----------         node:, List all snapshots for a VM or container.          Returns a list of snapshot di, Roll back a VM or container to a snapshot.          The VM / container should be, SnapshotManager

### Community 130 - "Proxmox Python"
Cohesion: 0.26
Nodes (7): Any, Console access helpers for VNC, SPICE and noVNC.      Parameters     ----------, Obtain a VNC proxy ticket for a VM.          Returns the VNC connection paramete, Obtain a SPICE proxy ticket for a VM.          Returns the SPICE connection data, Generate a noVNC websocket URL for browser-based console access.          Parame, Return comprehensive console connection information.          Includes VNC, SPIC, VMConsole

### Community 131 - "Tests Pytest"
Cohesion: 0.26
Nodes (6): _get_manager_class(), _make_manager(), Tests for FirewallManager operations., TestFirewallManagerEnableDisable, TestFirewallManagerIpsets, TestFirewallManagerRules

### Community 132 - "Kvm Bash"
Cohesion: 0.36
Nodes (10): action_rebuild_chain(), action_restore_full(), action_restore_incremental(), action_verify(), main(), parse_args(), kvm-backup-restore.sh script, usage() (+2 more)

### Community 133 - "Kvm Bash"
Cohesion: 0.35
Nodes (9): action_disable(), action_enable(), action_status(), action_test(), main(), parse_args(), kvm-nested-virt.sh script, usage() (+1 more)

### Community 134 - "Proxmox Bash"
Cohesion: 0.36
Nodes (10): do_configure(), do_create(), do_download_image(), do_dump(), do_regenerate(), main(), parse_args(), pmx-cloudinit.sh script (+2 more)

### Community 135 - "Proxmox Bash"
Cohesion: 0.36
Nodes (10): do_batch_migrate(), do_evacuate(), do_migrate(), do_status(), main(), parse_args(), pre_check_migration(), pmx-migration.sh script (+2 more)

### Community 136 - "Proxmox Bash"
Cohesion: 0.36
Nodes (10): do_create(), do_delete(), do_list(), do_rollback(), do_schedule(), main(), parse_args(), pmx-snapshot.sh script (+2 more)

### Community 137 - "Proxmox Bash"
Cohesion: 0.36
Nodes (10): do_clone_from_template(), do_create(), do_delete(), do_list(), do_update(), main(), parse_args(), pmx-template.sh script (+2 more)

### Community 138 - "Tests Pytest"
Cohesion: 0.29
Nodes (5): _get_manager_class(), _make_manager(), Tests for HAManager operations., TestHAManagerGroups, TestHAManagerResources

### Community 139 - "Kvm Bash"
Cohesion: 0.40
Nodes (9): action_blacklist_gpu(), action_enable(), action_groups(), action_status(), main(), parse_args(), kvm-iommu-setup.sh script, usage() (+1 more)

### Community 140 - "Proxmox Ansible"
Cohesion: 0.20
Nodes (10): PBS integration defaults, PBS storage refresh handler, Backup Job, Proxmox Backup Server, Retention Policy, proxmox_pbs, Configure backup jobs, Install PBS client (+2 more)

### Community 141 - "Tests Pytest"
Cohesion: 0.29
Nodes (6): _get_manager_class(), _make_manager(), Tests for ClusterManager operations., TestClusterManagerNodes, TestClusterManagerQuorum, TestClusterManagerStatus

### Community 142 - "Proxmox Client"
Cohesion: 0.25
Nodes (3): Client, Snapshot, SnapshotCreateRequest

### Community 143 - "Proxmox Hardening"
Cohesion: 0.22
Nodes (9): Auditd Configuration, Fail2ban Configuration, Kernel Module Disablement, File Permission Hardening, proxmox_hardening, SSH Hardening, SUID Binary Audit, Sysctl Hardening Parameters (+1 more)

### Community 144 - "Tests Go"
Cohesion: 0.47
Nodes (8): HandlerFunc, T, mockPVEHandler(), mustJSONMap(), TestGetVM(), TestListVMs(), TestStartVM(), TestStopVM()

### Community 145 - "Tui"
Cohesion: 0.29
Nodes (6): Context, actionCompleteMsg, dataLoadedMsg, logLineMsg, sshExecutor, viewName

### Community 146 - "Go Config Tests"
Cohesion: 0.50
Nodes (7): PVEConfig, defaultConfig(), T, loadConfig(), TestDefaultConfig(), TestEnvironmentOverride(), TestLoadConfig()

### Community 147 - "Alerting System"
Cohesion: 0.29
Nodes (5): Protocol, NotificationTransport, _NullTransport, Protocol for pluggable notification transports., Silent fallback transport that logs alerts instead of sending.

### Community 148 - "Go Internal"
Cohesion: 0.33
Nodes (5): BuildMenuTree(), Logger, NewModel(), MenuItem, menuItemView

### Community 149 - "Go Internal"
Cohesion: 0.38
Nodes (5): Color, padRight(), statusColor(), statusDot(), truncate()

### Community 150 - "Proxmox Ansible"
Cohesion: 0.38
Nodes (7): API token for automation user, Proxmox users (admin, automation, viewer), Task: create users, Ceph cluster configuration (reef release, network, MON, OSD), Ceph MDS, RGW, CRUSH rule and auth config, Ceph pool definitions (ceph-ssd, ceph-hdd), proxmox_ceph role defaults

### Community 151 - "Proxmox Network"
Cohesion: 0.40
Nodes (6): Network Bond Configuration, Network Bridge Configuration, proxmox_network, Routes and DNS Configuration, systemd-networkd Interface Management, VLAN Configuration

### Community 152 - "High Availability"
Cohesion: 0.40
Nodes (5): HA API Management, HA Fencing, HA Group Configuration, HA Resource Configuration, proxmox_ha

### Community 153 - "PCI Passthrough"
Cohesion: 0.70
Nodes (5): GPU Passthrough Configuration, IOMMU Configuration, Kernel Parameter Configuration, proxmox_passthrough, VFIO-PCI Configuration

### Community 154 - "Shared Python"
Cohesion: 0.40
Nodes (3): Result of an SSH command execution., Return True if the command exited with code 0., SSHResult

### Community 155 - "Proxmox Ansible"
Cohesion: 0.50
Nodes (4): User groups definition, Handler: reload access config via pveam refresh, Task: create user groups, Task: gather existing user groups via API

### Community 156 - "Proxmox Installation"
Cohesion: 0.50
Nodes (4): Proxmox Package Installation, Proxmox Repository Configuration, proxmox_install, Proxmox Systemd Service Management

### Community 157 - "Python Dependencies"
Cohesion: 0.50
Nodes (4): proxmoxer Python library (Proxmox API client), Python dependencies for proxmox-kvm-swissknife, Shared Python libraries (pyyaml, pydantic, requests, paramiko), Python dependencies for shared modules

### Community 158 - "Proxmox Ansible"
Cohesion: 0.67
Nodes (3): proxmox_users role defaults, proxmox_users role handlers, proxmox_users role tasks

### Community 159 - "Proxmox Ansible"
Cohesion: 0.67
Nodes (3): proxmox_vm_deploy role defaults, proxmox_vm_deploy role handlers, proxmox_vm_deploy role tasks

## Knowledge Gaps
- **206 isolated node(s):** `github.com/proxmox-kvm-swissknife`, `QMPError`, `IPSec`, `SnapshotCreateRequest`, `CloneRequest` (+201 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **39 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `decodeJSON()` connect `Proxmox Client` to `Proxmox Client`, `Configuration System`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`, `Proxmox Client`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Why does `PVEClient` connect `PVE API Client` to `Proxmox Python`, `Proxmox Python`, `Proxmox Template Manager`, `Alerting System`, `Pytest Test Fixtures`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`, `Proxmox Python`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Why does `New()` connect `Configuration System` to `KVMCTL CLI`, `Go Internal`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Are the 28 inferred relationships involving `PVEClient` (e.g. with `AlertManager` and `NotificationTransport`) actually correct?**
  _`PVEClient` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `LibvirtClient` (e.g. with `BackupError` and `BackupManager`) actually correct?**
  _`LibvirtClient` has 23 INFERRED edges - model-reasoned connections that need verification._
- **What connects `github.com/proxmox-kvm-swissknife`, `QMPError`, `IPSec` to the rest of the system?**
  _206 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `TUI Action Executor` be split into smaller, more focused modules?**
  _Cohesion score 0.08960573476702509 - nodes in this community are weakly interconnected._