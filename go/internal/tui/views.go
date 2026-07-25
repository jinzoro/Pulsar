// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

func (m *Model) renderMenu() string {
	if m.width == 0 {
		m.width = 80
	}

	var b strings.Builder

	title := TitleStyle.Render("  Pulsar  ")
	b.WriteString(title)
	b.WriteString("\n\n")

	visibleItems := m.height - 8
	if visibleItems < 3 {
		visibleItems = 15
	}

	start := m.selected - visibleItems/2
	if start < 0 {
		start = 0
	}
	end := start + visibleItems
	if end > len(m.menuItems) {
		end = len(m.menuItems)
		start = end - visibleItems
		if start < 0 {
			start = 0
		}
	}

	for i := start; i < end; i++ {
		item := &m.menuItems[i]
		icon := lipgloss.NewStyle().Foreground(lipgloss.Color(colorPurple)).Render(item.Icon + " ")

		name := ""
		desc := lipgloss.NewStyle().Foreground(lipgloss.Color(colorFgDim)).Render(item.Description)

		if i == m.selected {
			name = activeItemStyle.Render("▸ " + item.Name)
			b.WriteString(fmt.Sprintf("  %s %s  %s\n", icon, name, desc))
		} else {
			name = inactiveItemStyle.Render("  " + item.Name)
			b.WriteString(fmt.Sprintf("  %s %s  %s\n", icon, name, desc))
		}
	}

	return b.String()
}

func (m *Model) renderVMView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Virtual Machines"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured.\n  Go to Settings to configure your connection."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderCTView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  LXC Containers"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderStorageView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Storage Pools"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderNetworkView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Network Interfaces"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderSnapshotView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Snapshots"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured.\n  Select a VM to view snapshots."))
		return b.String()
	}

	if m.tableHeaders == nil {
		m.tableHeaders = []string{"VMID", "Name", "Description", "Created"}
		m.tableData = [][]string{
			{"-", "No VM selected", "Use VM view to select a VM first", "-"},
		}
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderBackupView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Backups"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderClusterView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Cluster Status"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderHAClusterView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  High Availability"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderFirewallView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Firewall Rules"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderUserView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Users & ACLs"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderMonitoringView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Monitoring & Metrics"))
	b.WriteString("\n\n")

	var sparklines []string

	cpuSpark := NewSparklineModel("CPU Usage", 30, lipgloss.Color(colorGreen))
	memSpark := NewSparklineModel("Memory", 30, lipgloss.Color(colorCyan))
	diskSpark := NewSparklineModel("Disk I/O", 30, lipgloss.Color(colorYellow))
	netInSpark := NewSparklineModel("Net In", 30, lipgloss.Color(colorPurple))
	netOutSpark := NewSparklineModel("Net Out", 30, lipgloss.Color(colorPink))

	sparklines = append(sparklines, cpuSpark.Render())
	sparklines = append(sparklines, memSpark.Render())
	sparklines = append(sparklines, diskSpark.Render())
	sparklines = append(sparklines, netInSpark.Render())
	sparklines = append(sparklines, netOutSpark.Render())

	b.WriteString(strings.Join(sparklines, "\n"))
	b.WriteString("\n\n")

	if m.pveClient != nil {
		b.WriteString(sectionHeaderStyle.Render("  Active Alerts"))
		b.WriteString("\n")
		b.WriteString(statusStyle.Render("  No active alerts\n"))
		b.WriteString(sectionHeaderStyle.Render("  Recent Events"))
		b.WriteString("\n")
		b.WriteString(statusStyle.Render("  Monitoring initialized. Metrics will appear on refresh.\n"))
	} else {
		b.WriteString(emptyStateStyle.Render("  Connect to Proxmox to view live metrics."))
	}

	return b.String()
}

func (m *Model) renderPassthroughView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  PCI / GPU Passthrough"))
	b.WriteString("\n\n")

	b.WriteString(sectionHeaderStyle.Render("  IOMMU Status"))
	b.WriteString("\n")
	b.WriteString(statusStyle.Render("  Run 'iommu_setup' from Host Setup to configure IOMMU.\n\n"))

	b.WriteString(sectionHeaderStyle.Render("  Available PCI Devices"))
	b.WriteString("\n")

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderCloudInitView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Templates & Cloud-Init"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(sectionHeaderStyle.Render("  Cloud-Init Configuration"))
	b.WriteString("\n")
	b.WriteString("  " + statusStyle.Render("Select a VM template to configure cloud-init.\n\n"))

	b.WriteString(sectionHeaderStyle.Render("  Available Templates"))
	b.WriteString("\n")

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderMaintenanceView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Node Maintenance"))
	b.WriteString("\n\n")

	if m.pveClient == nil {
		b.WriteString(emptyStateStyle.Render("  No Proxmox connection configured."))
		return b.String()
	}

	b.WriteString(sectionHeaderStyle.Render("  Node Status"))
	b.WriteString("\n")

	b.WriteString(m.renderTable(m.tableHeaders, m.tableData))
	return b.String()
}

func (m *Model) renderPerformanceView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Performance Tuning"))
	b.WriteString("\n\n")

	b.WriteString(sectionHeaderStyle.Render("  Kernel & CPU"))
	b.WriteString("\n")
	b.WriteString("  " + statusStyle.Render("Hugepages, CPU Pinning, NUMA, IO Tuning, Kernel Parameters\n\n"))

	b.WriteString(sectionHeaderStyle.Render("  Current Settings"))
	b.WriteString("\n")

	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Hugepages:", statusStyle.Render("Not configured")))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "CPU Governor:", statusStyle.Render("Not checked")))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "NUMA:", statusStyle.Render("Not checked")))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "IO Scheduler:", statusStyle.Render("Not checked")))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Swappiness:", statusStyle.Render("Not checked")))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Transparent Hugepages:", statusStyle.Render("Not checked")))

	b.WriteString("\n")
	b.WriteString("  " + warningStyle.Render("Run 'health_check' to scan current settings, or use menu to apply tuning."))

	return b.String()
}

func (m *Model) renderHostSetupView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  KVM Host Setup"))
	b.WriteString("\n\n")

	b.WriteString(sectionHeaderStyle.Render("  System Information"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Architecture:", "Check with uname -m"))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "KVM Support:", "Check with lsmod | grep kvm"))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "IOMMU:", "Check with dmesg | grep iommu"))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Nested Virt:", "Check /sys/module/kvm_intel/parameters/nested"))

	b.WriteString("\n")
	b.WriteString(sectionHeaderStyle.Render("  Setup Actions"))
	b.WriteString("\n")

	setupItems := []struct {
		action string
		desc   string
	}{
		{"install_kvm", "Install KVM/QEMU packages and dependencies"},
		{"nested_virt", "Enable nested virtualization for Intel/AMD"},
		{"iommu_setup", "Configure IOMMU for PCI passthrough"},
		{"guest_agent", "Install and configure QEMU Guest Agent"},
	}

	for i, item := range setupItems {
		cursor := "  "
		if i == m.selected {
			cursor = activeItemStyle.Render("▸ ")
		}
		b.WriteString(fmt.Sprintf("  %s%-25s %s\n", cursor, item.action, statusStyle.Render(item.desc)))
	}

	return b.String()
}

func (m *Model) renderSettingsView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Settings"))
	b.WriteString("\n\n")

	b.WriteString(sectionHeaderStyle.Render("  Proxmox Connection"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "API URL:", m.config.Proxmox.APIURL))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "User:", m.config.Proxmox.User))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Node:", m.config.Proxmox.Node))
	b.WriteString(fmt.Sprintf("  %-25s %v\n", "Insecure TLS:", m.config.Proxmox.Insecure))

	b.WriteString("\n")
	b.WriteString(sectionHeaderStyle.Render("  KVM Connection"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Libvirt URI:", m.config.KVM.LibvirtURI))

	b.WriteString("\n")
	b.WriteString(sectionHeaderStyle.Render("  SSH"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "User:", m.config.SSH.User))
	b.WriteString(fmt.Sprintf("  %-25s %d\n", "Port:", m.config.SSH.Port))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Key File:", m.config.SSH.KeyFile))

	b.WriteString("\n")
	b.WriteString(sectionHeaderStyle.Render("  Defaults"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %d\n", "CPU:", m.config.Defaults.CPU))
	b.WriteString(fmt.Sprintf("  %-25s %d MB\n", "Memory:", m.config.Defaults.Memory))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Disk:", m.config.Defaults.DiskSize))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Network:", m.config.Defaults.Network))
	b.WriteString(fmt.Sprintf("  %-25s %s\n", "Storage:", m.config.Defaults.Storage))

	b.WriteString("\n")
	b.WriteString(sectionHeaderStyle.Render("  Alerts"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %-25s %.0f%%\n", "CPU Threshold:", m.config.Alerts.CPUThreshold))
	b.WriteString(fmt.Sprintf("  %-25s %.0f%%\n", "Memory Threshold:", m.config.Alerts.MemoryThreshold))
	b.WriteString(fmt.Sprintf("  %-25s %.0f%%\n", "Disk Threshold:", m.config.Alerts.DiskThreshold))

	return b.String()
}

func (m *Model) renderUtilitiesView() string {
	var b strings.Builder
	b.WriteString(sectionHeaderStyle.Render("  Utilities"))
	b.WriteString("\n\n")

	b.WriteString(sectionHeaderStyle.Render("  Available Tools"))
	b.WriteString("\n\n")

	tools := []struct {
		icon string
		name string
		desc string
	}{
		{"⊞", "SSH Executor", "Execute commands on remote hosts via SSH"},
		{"↓", "Config Backup", "Backup swissknife and Proxmox configuration"},
		{"✓", "Health Check", "Comprehensive system health and readiness check"},
		{"⚙", "Settings", "View and edit connection settings and credentials"},
	}

	for i, tool := range tools {
		cursor := "  "
		if i == m.selected {
			cursor = activeItemStyle.Render("▸ ")
		}
		icon := lipgloss.NewStyle().Foreground(lipgloss.Color(colorPurple)).Width(4).Render(tool.icon)
		name := ""
		if i == m.selected {
			name = activeItemStyle.Render(tool.name)
		} else {
			name = inactiveItemStyle.Render(tool.name)
		}
		desc := statusStyle.Render(tool.desc)
		b.WriteString(fmt.Sprintf("  %s %s %s\n", icon, name, desc))
	}

	return b.String()
}

func scanPCI() [][]string {
	return [][]string{
		{"00:00.0", "Intel Corporation", "Host Bridge", "Active", "hostbridge", "Xeon E3-1200 Host Bridge"},
		{"00:01.0", "Intel Corporation", "PCI Bridge", "Active", "pcieport", "PCI Express Root Port"},
		{"00:02.0", "Intel Corporation", "VGA", "Available", "i915", "HD Graphics"},
		{"01:00.0", "NVIDIA Corporation", "GPU", "Available", "nvidia", "GeForce RTX"},
	}
}
