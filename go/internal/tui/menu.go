// SPDX-License-Identifier: MIT

package tui

type menuItemView viewName

const (
	menuVirtualMachines menuItemView = "vm_view"
	menuContainers      menuItemView = "ct_view"
	menuStorage         menuItemView = "storage_view"
	menuNetworking      menuItemView = "network_view"
	menuSnapshots       menuItemView = "snapshot_view"
	menuCluster         menuItemView = "cluster_view"
	menuTemplates       menuItemView = "cloudinit_view"
	menuSecurity        menuItemView = "user_view"
	menuMonitoring      menuItemView = "monitoring_view"
	menuPerformance     menuItemView = "performance_view"
	menuHostSetup       menuItemView = "hostsetup_view"
	menuUtilities       menuItemView = "utilities_view"
)

type MenuItem struct {
	Name        string
	Description string
	Action      string
	Icon        string
	Children    []MenuItem
	viewID      viewName
}

func BuildMenuTree() []MenuItem {
	return []MenuItem{
		{
			Name:        "Virtual Machines",
			Description: "Manage KVM/Proxmox VMs",
			Icon:        "⬢",
			viewID:      menuVirtualMachines,
			Children: []MenuItem{
				{Name: "List VMs", Description: "List all virtual machines", Action: "list_vms", Icon: "≡"},
				{Name: "Create Proxmox VM", Description: "Create a new Proxmox VM", Action: "create_pmx_vm", Icon: "+"},
				{Name: "Create KVM VM", Description: "Create a local KVM VM", Action: "create_kvm_vm", Icon: "+"},
				{Name: "Start VM", Description: "Start a virtual machine", Action: "start_vm", Icon: "▶"},
				{Name: "Stop VM", Description: "Stop a virtual machine", Action: "stop_vm", Icon: "■"},
				{Name: "Shutdown VM", Description: "Graceful shutdown", Action: "shutdown_vm", Icon: "⏻"},
				{Name: "Clone VM", Description: "Clone an existing VM", Action: "clone_vm", Icon: "⧉"},
				{Name: "Migrate VM", Description: "Migrate VM to another node", Action: "migrate_vm", Icon: "⇄"},
				{Name: "Resize VM Disk", Description: "Resize VM disk", Action: "resize_vm", Icon: "↕"},
				{Name: "Delete VM", Description: "Delete a virtual machine", Action: "delete_vm", Icon: "✕"},
				{Name: "VM Console", Description: "Open VM console", Action: "vm_console", Icon: "⊞"},
				{Name: "Config Audit", Description: "Audit VM configuration", Action: "vm_config_audit", Icon: "⊡"},
			},
		},
		{
			Name:        "Containers",
			Description: "Manage LXC containers",
			Icon:        "▣",
			viewID:      menuContainers,
			Children: []MenuItem{
				{Name: "List Containers", Description: "List all LXC containers", Action: "list_ct", Icon: "≡"},
				{Name: "Create Container", Description: "Create a new LXC container", Action: "create_ct", Icon: "+"},
				{Name: "Start Container", Description: "Start an LXC container", Action: "start_ct", Icon: "▶"},
				{Name: "Stop Container", Description: "Stop an LXC container", Action: "stop_ct", Icon: "■"},
				{Name: "Resize Container", Description: "Resize container disk", Action: "resize_ct", Icon: "↕"},
				{Name: "Delete Container", Description: "Delete an LXC container", Action: "delete_ct", Icon: "✕"},
				{Name: "Templates", Description: "Manage container templates", Action: "ct_templates", Icon: "◫"},
			},
		},
		{
			Name:        "Storage",
			Description: "Manage storage pools and disks",
			Icon:        "◧",
			viewID:      menuStorage,
			Children: []MenuItem{
				{Name: "List Storage", Description: "List all storage pools", Action: "list_storage", Icon: "≡"},
				{Name: "Add Storage", Description: "Add a new storage backend", Action: "add_storage", Icon: "+"},
				{Name: "Remove Storage", Description: "Remove a storage pool", Action: "remove_storage", Icon: "✕"},
				{Name: "Ceph Management", Description: "Manage Ceph cluster", Action: "ceph_mgmt", Icon: "◆"},
				{Name: "ZFS Management", Description: "Manage ZFS pools", Action: "zfs_mgmt", Icon: "◆"},
				{Name: "LVM Management", Description: "Manage LVM volumes", Action: "lvm_mgmt", Icon: "◆"},
				{Name: "Migrate Disks", Description: "Move disks between storage", Action: "migrate_disks", Icon: "⇄"},
				{Name: "Benchmark", Description: "Run storage benchmark", Action: "storage_benchmark", Icon: "◈"},
			},
		},
		{
			Name:        "Networking",
			Description: "Network configuration and diagnostics",
			Icon:        "⬡",
			viewID:      menuNetworking,
			Children: []MenuItem{
				{Name: "Bridges/Bonds/VLANs", Description: "Manage network interfaces", Action: "net_bridges", Icon: "≡"},
				{Name: "SDN Zones", Description: "Software Defined Networking", Action: "sdn_zones", Icon: "◈"},
				{Name: "SDN Vnets", Description: "Virtual networks", Action: "sdn_vnets", Icon: "◈"},
				{Name: "Firewall Rules", Description: "Host/VM firewall", Action: "net_firewall", Icon: "◆"},
				{Name: "SR-IOV / GPU Passthrough", Description: "PCI passthrough config", Action: "net_sriov", Icon: "◆"},
				{Name: "OVS Management", Description: "Open vSwitch", Action: "ovs_mgmt", Icon: "◈"},
				{Name: "Network Diagnostics", Description: "Test connectivity", Action: "net_diagnostics", Icon: "◇"},
			},
		},
		{
			Name:        "Snapshots & Backups",
			Description: "Snapshot and backup management",
			Icon:        "◉",
			viewID:      menuSnapshots,
			Children: []MenuItem{
				{Name: "List Snapshots", Description: "View VM snapshots", Action: "list_snapshots", Icon: "≡"},
				{Name: "Create Snapshot", Description: "Take a new snapshot", Action: "create_snapshot", Icon: "+"},
				{Name: "Rollback Snapshot", Description: "Restore to snapshot", Action: "rollback_snapshot", Icon: "↺"},
				{Name: "Delete Snapshot", Description: "Remove a snapshot", Action: "delete_snapshot", Icon: "✕"},
				{Name: "Backup VM", Description: "Create a backup", Action: "backup_vm", Icon: "↓"},
				{Name: "Restore Backup", Description: "Restore from backup", Action: "restore_backup", Icon: "↑"},
				{Name: "Backup Schedule", Description: "Configure backup jobs", Action: "backup_schedule", Icon: "◷"},
				{Name: "Verify Backups", Description: "Verify backup integrity", Action: "verify_backups", Icon: "✓"},
			},
		},
		{
			Name:        "Cluster & HA",
			Description: "Cluster management and high availability",
			Icon:        "⬢",
			viewID:      menuCluster,
			Children: []MenuItem{
				{Name: "Cluster Status", Description: "View cluster health", Action: "cluster_status", Icon: "◉"},
				{Name: "Node Status", Description: "Per-node resource usage", Action: "node_status", Icon: "◉"},
				{Name: "Join Cluster", Description: "Join a node to cluster", Action: "join_cluster", Icon: "+"},
				{Name: "Remove Node", Description: "Remove node from cluster", Action: "remove_node", Icon: "✕"},
				{Name: "HA Groups", Description: "Manage HA groups", Action: "ha_groups", Icon: "◆"},
				{Name: "HA Resources", Description: "Manage HA resources", Action: "ha_resources", Icon: "◆"},
				{Name: "Failover Policy", Description: "Configure failover", Action: "failover_policy", Icon: "⟳"},
				{Name: "Rolling Upgrade", Description: "Cluster rolling upgrade", Action: "rolling_upgrade", Icon: "⟳"},
			},
		},
		{
			Name:        "Templates & Cloud-Init",
			Description: "VM templates and cloud-init",
			Icon:        "◫",
			viewID:      menuTemplates,
			Children: []MenuItem{
				{Name: "List Templates", Description: "View VM templates", Action: "list_templates", Icon: "≡"},
				{Name: "Create Template", Description: "Convert VM to template", Action: "create_template", Icon: "+"},
				{Name: "Cloud-Init Config", Description: "Configure cloud-init", Action: "cloudinit_config", Icon: "⊡"},
				{Name: "Packer Templates", Description: "HashiCorp Packer integration", Action: "packer_templates", Icon: "◆"},
				{Name: "Terraform Provider", Description: "Terraform provider setup", Action: "terraform_provider", Icon: "◆"},
			},
		},
		{
			Name:        "Security & Users",
			Description: "User management and security hardening",
			Icon:        "◆",
			viewID:      menuSecurity,
			Children: []MenuItem{
				{Name: "List Users", Description: "View all users", Action: "list_users", Icon: "≡"},
				{Name: "Create User", Description: "Create a new user", Action: "create_user", Icon: "+"},
				{Name: "ACL Management", Description: "Access control lists", Action: "acl_mgmt", Icon: "◆"},
				{Name: "API Tokens", Description: "Manage API tokens", Action: "api_tokens", Icon: "◈"},
				{Name: "Certificates", Description: "SSL/TLS certificates", Action: "certificates", Icon: "◆"},
				{Name: "Security Hardening", Description: "Harden Proxmox security", Action: "security_hardening", Icon: "◆"},
			},
		},
		{
			Name:        "Monitoring & Reports",
			Description: "Metrics, alerts, and reporting",
			Icon:        "◎",
			viewID:      menuMonitoring,
			Children: []MenuItem{
				{Name: "Live Metrics", Description: "Real-time performance metrics", Action: "live_metrics", Icon: "◎"},
				{Name: "Alert Configuration", Description: "Configure alerting thresholds", Action: "alert_config", Icon: "⚠"},
				{Name: "Capacity Planning", Description: "Resource capacity overview", Action: "capacity_planning", Icon: "◈"},
				{Name: "System Logs", Description: "View system logs", Action: "system_logs", Icon: "≡"},
				{Name: "Prometheus Export", Description: "Export metrics for Prometheus", Action: "prometheus_export", Icon: "◈"},
			},
		},
		{
			Name:        "Performance Tuning",
			Description: "VM and host performance optimization",
			Icon:        "⚡",
			viewID:      menuPerformance,
			Children: []MenuItem{
				{Name: "Hugepages", Description: "Configure hugepages", Action: "hugepages", Icon: "◆"},
				{Name: "CPU Pinning", Description: "CPU pinning for VMs", Action: "cpu_pinning", Icon: "◆"},
				{Name: "NUMA Topology", Description: "NUMA-aware configuration", Action: "numa_topology", Icon: "◆"},
				{Name: "IO Tuning", Description: "Disk IO optimization", Action: "io_tuning", Icon: "◆"},
				{Name: "Kernel Parameters", Description: "Sysctl tuning", Action: "kernel_params", Icon: "◆"},
			},
		},
		{
			Name:        "Host Setup",
			Description: "KVM host configuration and setup",
			Icon:        "⊡",
			viewID:      menuHostSetup,
			Children: []MenuItem{
				{Name: "Install KVM", Description: "Install KVM packages", Action: "install_kvm", Icon: "+"},
				{Name: "Nested Virtualization", Description: "Enable nested virt", Action: "nested_virt", Icon: "◆"},
				{Name: "IOMMU / Passthrough", Description: "Configure IOMMU", Action: "iommu_setup", Icon: "◆"},
				{Name: "Guest Agent", Description: "QEMU guest agent setup", Action: "guest_agent", Icon: "◆"},
			},
		},
		{
			Name:        "Utilities",
			Description: "SSH, health checks, and tools",
			Icon:        "⚙",
			viewID:      menuUtilities,
			Children: []MenuItem{
				{Name: "SSH Executor", Description: "Execute remote commands", Action: "ssh_executor", Icon: "⊞"},
				{Name: "Config Backup", Description: "Backup configuration", Action: "config_backup", Icon: "↓"},
				{Name: "Health Check", Description: "System health overview", Action: "health_check", Icon: "✓"},
				{Name: "Settings", Description: "Connection settings", Action: "settings", Icon: "⚙"},
			},
		},
	}
}
