// SPDX-License-Identifier: MIT

package tui

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/rs/zerolog"

	"github.com/proxmox-kvm-swissknife/internal/config"
	"github.com/proxmox-kvm-swissknife/internal/kvm"
	"github.com/proxmox-kvm-swissknife/internal/proxmox"
)

type viewName string

const (
	viewMainMenu  viewName = "main_menu"
	viewVMView    viewName = "vm_view"
	viewCTView    viewName = "ct_view"
	viewStorage   viewName = "storage_view"
	viewNetwork   viewName = "network_view"
	viewSnapshot  viewName = "snapshot_view"
	viewBackup    viewName = "backup_view"
	viewCluster   viewName = "cluster_view"
	viewHACluster viewName = "ha_cluster_view"
	viewFirewall  viewName = "firewall_view"
	viewUser      viewName = "user_view"
	viewMonitor   viewName = "monitoring_view"
	viewPassThru  viewName = "passthrough_view"
	viewCloudInit viewName = "cloudinit_view"
	viewMaint     viewName = "maintenance_view"
	viewPerf      viewName = "performance_view"
	viewHostSetup viewName = "hostsetup_view"
	viewSettings  viewName = "settings_view"
	viewUtility   viewName = "utilities_view"
	viewForm      viewName = "form_view"
	viewConfirm   viewName = "confirm_view"
	viewProgress  viewName = "progress_view"
	viewLog       viewName = "log_view"
)

type dataLoadedMsg struct {
	view    viewName
	headers []string
	rows    [][]string
	err     error
	message string
}

type actionCompleteMsg struct {
	action string
	err    error
	output string
}

type logLineMsg struct {
	line string
}

type sshExecutor struct {
	host string
	user string
	port int
	key  string
}

func (s *sshExecutor) Execute(_ context.Context, _ string) (string, error) {
	return "", fmt.Errorf("SSH executor not configured: connect to a host first")
}

type Model struct {
	currentView   viewName
	previousViews []viewName
	menuItems     []MenuItem
	selected      int
	width         int
	height        int
	config        *config.Config
	pveClient     *proxmox.Client
	kvmClient     *kvm.LibvirtClient
	sshExec       *sshExecutor
	log           zerolog.Logger

	formFields  []FormField
	formCursor  int
	formTitle   string
	formHandler func(map[string]string) tea.Cmd

	confirmMessage string
	confirmAction  tea.Cmd
	confirmCursor  int

	progressModel *ProgressModel
	logModel      *LogViewModel

	statusMessage string
	statusIsError bool
	isLoading     bool
	spinner       spinner.Model

	searchInput  textinput.Model
	searchActive bool

	tableData    [][]string
	tableHeaders []string
	tableCursor  int

	executor *ActionExecutor

	quitting bool
}

func NewModel(cfg *config.Config, log zerolog.Logger) (*Model, error) {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color(colorPrimary))

	ti := textinput.New()
	ti.Placeholder = "Search..."
	ti.Focus()
	ti.CharLimit = 100
	ti.Width = 40

	var pveClient *proxmox.Client
	if cfg.Proxmox.APIURL != "" {
		var err error
		pveClient, err = proxmox.New(
			cfg.Proxmox.APIURL,
			cfg.Proxmox.User,
			cfg.Proxmox.APITokenID,
			cfg.Proxmox.APITokenSecret,
		)
		if err != nil {
			log.Warn().Err(err).Msg("failed to connect to Proxmox API, running in offline mode")
		}
	}

	var kvmClient *kvm.LibvirtClient
	if cfg.KVM.LibvirtURI != "" {
		var err error
		kvmClient, err = kvm.NewLibvirtClient(cfg.KVM.LibvirtURI)
		if err != nil {
			log.Warn().Err(err).Msg("failed to connect to libvirt, KVM features unavailable")
		}
	}

	m := &Model{
		currentView: viewMainMenu,
		config:      cfg,
		pveClient:   pveClient,
		kvmClient:   kvmClient,
		log:         log,
		statusMessage: "Ready",
		spinner:     s,
		searchInput: ti,
		executor: &ActionExecutor{
			pveClient: pveClient,
			kvmClient: kvmClient,
			log:       log,
		},
		logModel:      NewLogViewModel(200),
		progressModel: NewProgressModel(),
	}

	m.menuItems = BuildMenuTree()

	return m, nil
}

func (m *Model) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick)
}

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		if m.searchActive {
			return m.handleSearchKeys(msg)
		}
		return m.handleGlobalKeys(msg)

	case spinner.TickMsg:
		if m.isLoading {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			cmds = append(cmds, cmd)
		}

	case dataLoadedMsg:
		m.isLoading = false
		m.tableHeaders = msg.headers
		m.tableData = msg.rows
		if msg.err != nil {
			m.statusMessage = fmt.Sprintf("Error: %v", msg.err)
			m.statusIsError = true
		} else if msg.message != "" {
			m.statusMessage = msg.message
			m.statusIsError = false
		}

	case actionCompleteMsg:
		m.isLoading = false
		if msg.err != nil {
			m.statusMessage = fmt.Sprintf("Error: %v", msg.err)
			m.statusIsError = true
		} else {
			m.statusMessage = fmt.Sprintf("✓ %s", msg.action)
			m.statusIsError = false
			if msg.output != "" {
				m.logModel.AppendLine(msg.output)
			}
		}

	case logLineMsg:
		m.logModel.AppendLine(msg.line)
	}

	return m, tea.Batch(cmds...)
}

func (m *Model) handleSearchKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.searchActive = false
		m.searchInput.Blur()
		m.searchInput.SetValue("")
		return m, nil
	case "enter":
		m.searchActive = false
		m.searchInput.Blur()
		return m, nil
	}
	var cmd tea.Cmd
	m.searchInput, cmd = m.searchInput.Update(msg)
	return m, cmd
}

func (m *Model) handleGlobalKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c", "q":
		if m.currentView == viewMainMenu {
			m.quitting = true
			return m, tea.Quit
		}
		return m, m.goBack()

	case "esc":
		if m.currentView == viewConfirm {
			m.currentView = m.previousViews[len(m.previousViews)-1]
			m.previousViews = m.previousViews[:len(m.previousViews)-1]
			return m, nil
		}
		if m.currentView == viewForm {
			m.currentView = m.previousViews[len(m.previousViews)-1]
			m.previousViews = m.previousViews[:len(m.previousViews)-1]
			return m, nil
		}
		return m, m.goBack()

	case "/":
		m.searchActive = true
		m.searchInput.Focus()
		return m, textinput.Blink

	case "up", "k":
		m.moveUp()
		return m, nil

	case "down", "j":
		m.moveDown()
		return m, nil

	case "enter", " ":
		return m, m.executeSelection()

	case "pgup":
		m.tableCursor -= 10
		if m.tableCursor < 0 {
			m.tableCursor = 0
		}
		return m, nil

	case "pgdown":
		m.tableCursor += 10
		if m.tableCursor >= len(m.tableData) {
			m.tableCursor = len(m.tableData) - 1
		}
		return m, nil

	case "home":
		m.tableCursor = 0
		return m, nil

	case "end":
		if len(m.tableData) > 0 {
			m.tableCursor = len(m.tableData) - 1
		}
		return m, nil
	}

	return m, nil
}

func (m *Model) moveUp() {
	switch m.currentView {
	case viewConfirm:
		if m.confirmCursor > 0 {
			m.confirmCursor--
		}
	case viewForm:
		if m.formCursor > 0 {
			m.formCursor--
		}
	default:
		if m.selected > 0 {
			m.selected--
		}
		if m.tableCursor > 0 {
			m.tableCursor--
		}
	}
}

func (m *Model) moveDown() {
	switch m.currentView {
	case viewConfirm:
		if m.confirmCursor < 1 {
			m.confirmCursor++
		}
	case viewForm:
		if m.formCursor < len(m.formFields)-1 {
			m.formCursor++
		}
	default:
		items := m.getCurrentItems()
		if m.selected < len(items)-1 {
			m.selected++
		}
		visibleRows := m.height - 12
		if visibleRows < 1 {
			visibleRows = 10
		}
		if m.tableCursor < len(m.tableData)-1 && m.tableCursor < visibleRows-1 {
			m.tableCursor++
		}
	}
}

func (m *Model) getCurrentItems() []MenuItem {
	if m.currentView == viewMainMenu {
		return m.menuItems
	}
	for _, item := range m.menuItems {
		if item.viewID == m.currentView || item.viewID == m.previousView() {
			return item.Children
		}
	}
	return nil
}

func (m *Model) previousView() viewName {
	if len(m.previousViews) == 0 {
		return ""
	}
	return m.previousViews[len(m.previousViews)-1]
}

func (m *Model) executeSelection() tea.Cmd {
	if m.currentView == viewConfirm {
		if m.confirmCursor == 0 {
			m.currentView = m.previousViews[len(m.previousViews)-1]
			m.previousViews = m.previousViews[:len(m.previousViews)-1]
			return m.confirmAction
		}
		m.currentView = m.previousViews[len(m.previousViews)-1]
		m.previousViews = m.previousViews[:len(m.previousViews)-1]
		return nil
	}

	if m.currentView == viewMainMenu {
		if m.selected < len(m.menuItems) {
			item := &m.menuItems[m.selected]
			if len(item.Children) > 0 {
				m.navigateTo(item)
				return nil
			}
			if item.Action != "" {
				return m.executeAction(item.Action, item.Name)
			}
		}
		return nil
	}

	items := m.getCurrentItems()
	if m.selected >= 0 && m.selected < len(items) {
		item := &items[m.selected]
		if len(item.Children) > 0 {
			m.navigateTo(item)
			return m.loadDataForView(item.viewID)
		}
		if item.Action != "" {
			return m.executeAction(item.Action, item.Name)
		}
	}
	return nil
}

func (m *Model) navigateTo(item *MenuItem) {
	m.previousViews = append(m.previousViews, m.currentView)
	m.currentView = item.viewID
	m.selected = 0
	m.tableCursor = 0
	m.tableData = nil
	m.tableHeaders = nil
	m.statusMessage = item.Name
	m.statusIsError = false
}

func (m *Model) goBack() tea.Cmd {
	if len(m.previousViews) > 0 {
		m.currentView = m.previousViews[len(m.previousViews)-1]
		m.previousViews = m.previousViews[:len(m.previousViews)-1]
		m.selected = 0
		m.tableCursor = 0
		m.tableData = nil
		m.tableHeaders = nil
		m.statusMessage = ""
		m.statusIsError = false
		return nil
	}
	return tea.Quit
}

func (m *Model) loadDataForView(view viewName) tea.Cmd {
	if m.pveClient == nil {
		return nil
	}
	return func() tea.Msg {
		node := m.config.Proxmox.Node
		switch view {
		case viewVMView:
			vms, err := m.pveClient.ListVMs()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"VMID", "Name", "Status", "CPU", "Memory", "Disk", "Node"}
			rows := make([][]string, len(vms))
			for i, vm := range vms {
				rows[i] = []string{
					fmt.Sprintf("%d", vm.VMID), vm.Name, vm.Status,
					fmt.Sprintf("%d", vm.CPUs), formatBytes(vm.MaxMem),
					formatBytes(vm.MaxDisk), vm.Node,
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d VMs loaded", len(vms))}

		case viewCTView:
			cts, err := m.pveClient.ListContainers()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"CTID", "Name", "Status", "CPU", "Memory", "Disk"}
			rows := make([][]string, len(cts))
			for i, ct := range cts {
				rows[i] = []string{
					fmt.Sprintf("%d", ct.VMID), ct.Name, ct.Status,
					fmt.Sprintf("%d", ct.CPUs), formatBytes(ct.MaxMem),
					formatBytes(ct.MaxDisk),
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d containers loaded", len(cts))}

		case viewStorage:
			storage, err := m.pveClient.ListStorage()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Name", "Type", "Status", "Total", "Used", "Available", "%Used"}
			rows := make([][]string, len(storage))
			for i, s := range storage {
				rows[i] = []string{
					s.Storage, s.Type, s.Status,
					formatBytes(s.Total), formatBytes(s.Used),
					formatBytes(s.Avail), fmt.Sprintf("%.1f%%", s.Percent),
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d storage pools loaded", len(storage))}

		case viewNetwork:
			ifaces, err := m.pveClient.ListInterfaces(node)
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Name", "Type", "Address", "Active", "Autostart", "Comment"}
			rows := make([][]string, len(ifaces))
			for i, iface := range ifaces {
				active, auto := "no", "no"
				if iface.Active {
					active = "yes"
				}
				if iface.Autostart {
					auto = "yes"
				}
				rows[i] = []string{
					iface.Name, iface.Type, iface.Address, active, auto, iface.Comment,
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d interfaces loaded", len(ifaces))}

		case viewBackup:
			backups, err := m.pveClient.ListBackups(m.config.Defaults.Storage)
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Volume ID", "Size", "Format", "Created"}
			rows := make([][]string, len(backups))
			for i, bk := range backups {
				rows[i] = []string{
					bk.Volid, formatBytes(bk.Size), bk.Format, fmt.Sprintf("%d", bk.Ctime),
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d backups loaded", len(backups))}

		case viewCluster:
			nodes, err := m.pveClient.ListNodes()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Node", "Status", "CPU", "Memory", "Disk", "Uptime"}
			rows := make([][]string, len(nodes))
			for i, n := range nodes {
				uptime := fmt.Sprintf("%dd %dh", n.Uptime/86400, (n.Uptime%86400)/3600)
				rows[i] = []string{
					n.Node, n.Status,
					fmt.Sprintf("%.1f%%", n.CPU*100),
					fmt.Sprintf("%.1f%%", float64(n.Memory.Used)/float64(n.MaxMemory)*100),
					fmt.Sprintf("%.1f%%", float64(n.Disk.Used)/float64(n.MaxDisk)*100),
					uptime,
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d nodes in cluster", len(nodes))}

		case viewHACluster:
			resources, err := m.pveClient.ListHAResources()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Resource ID", "Type", "State", "Group", "Max Restart", "Max Relocate"}
			rows := make([][]string, len(resources))
			for i, r := range resources {
				rows[i] = []string{
					r.SID, r.Type, r.State, r.Group,
					fmt.Sprintf("%d", r.MaxRestart), fmt.Sprintf("%d", r.MaxRelocate),
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d HA resources", len(resources))}

		case viewFirewall:
			rules, err := m.pveClient.ListHostFirewallRules(node)
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"Pos", "Action", "Proto", "Source", "Destination", "Port", "Comment"}
			rows := make([][]string, len(rules))
			for i, r := range rules {
				rows[i] = []string{
					fmt.Sprintf("%d", r.Pos), r.Action, r.Proto, r.Source, r.Dest, r.DPort, r.Comment,
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d firewall rules", len(rules))}

		case viewUser:
			users, err := m.pveClient.ListUsers()
			if err != nil {
				return dataLoadedMsg{view: view, err: err}
			}
			headers := []string{"User ID", "Email", "Realm", "Enabled", "Groups", "Comment"}
			rows := make([][]string, len(users))
			for i, u := range users {
				enabled := "no"
				if u.Enable {
					enabled = "yes"
				}
				rows[i] = []string{
					u.UserID, u.Email, u.Realm, enabled, u.Groups, u.Comment,
				}
			}
			return dataLoadedMsg{view: view, headers: headers, rows: rows, message: fmt.Sprintf("%d users loaded", len(users))}

		case viewPassThru:
			entries := scanPCI()
			return dataLoadedMsg{view: view, headers: []string{"BDF", "Vendor", "Device", "IOMMU", "Driver", "Description"}, rows: entries, message: fmt.Sprintf("%d PCI devices found", len(entries))}

		default:
			return dataLoadedMsg{view: view}
		}
	}
}

func (m *Model) executeAction(action, label string) tea.Cmd {
	return m.executor.ExecuteAction(action, nil)
}

func (m *Model) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}
	if m.width == 0 || m.height == 0 {
		return "Initializing..."
	}

	var b strings.Builder
	b.WriteString(m.renderBreadcrumbs())
	b.WriteString("\n")

	var content string
	switch m.currentView {
	case viewMainMenu:
		content = m.renderMenu()
	case viewConfirm:
		content = m.renderConfirm()
	case viewForm:
		content = m.renderForm()
	case viewProgress:
		content = m.renderProgress()
	case viewLog:
		content = m.renderLog()
	default:
		content = m.renderCurrentView()
	}

	b.WriteString(content)
	b.WriteString("\n")
	b.WriteString(m.renderStatusBar())
	return b.String()
}

func (m *Model) renderBreadcrumbs() string {
	var parts []string
	parts = append(parts, TitleStyle.Render("swissknife"))
	for _, v := range m.previousViews {
		parts = append(parts, breadcrumbStyle.Render(string(v)))
	}
	parts = append(parts, sectionHeaderStyle.Render(string(m.currentView)))
	return strings.Join(parts, breadcrumbStyle.Render(" → "))
}

func (m *Model) renderStatusBar() string {
	var parts []string
	if m.isLoading {
		parts = append(parts, m.spinner.View()+statusStyle.Render(" Loading..."))
	} else if m.statusIsError {
		parts = append(parts, errorStyle.Render(m.statusMessage))
	} else if m.statusMessage != "" {
		parts = append(parts, statusStyle.Render(m.statusMessage))
	}
	parts = append(parts, helpBarStyle.Render("↑↓:nav  enter:select  q/esc:back  /:search  ctrl+c:quit"))
	return strings.Join(parts, "  ")
}

func (m *Model) renderCurrentView() string {
	switch m.currentView {
	case viewVMView:
		return m.renderVMView()
	case viewCTView:
		return m.renderCTView()
	case viewStorage:
		return m.renderStorageView()
	case viewNetwork:
		return m.renderNetworkView()
	case viewSnapshot:
		return m.renderSnapshotView()
	case viewBackup:
		return m.renderBackupView()
	case viewCluster:
		return m.renderClusterView()
	case viewHACluster:
		return m.renderHAClusterView()
	case viewFirewall:
		return m.renderFirewallView()
	case viewUser:
		return m.renderUserView()
	case viewMonitor:
		return m.renderMonitoringView()
	case viewPassThru:
		return m.renderPassthroughView()
	case viewCloudInit:
		return m.renderCloudInitView()
	case viewMaint:
		return m.renderMaintenanceView()
	case viewPerf:
		return m.renderPerformanceView()
	case viewHostSetup:
		return m.renderHostSetupView()
	case viewSettings:
		return m.renderSettingsView()
	case viewUtility:
		return m.renderUtilitiesView()
	default:
		return emptyStateStyle.Render("Unknown view")
	}
}

func (m *Model) renderTable(headers []string, rows [][]string) string {
	if len(rows) == 0 {
		if m.isLoading {
			return "  " + m.spinner.View() + " Loading...\n"
		}
		return emptyStateStyle.Render("  No data available")
	}

	var b strings.Builder

	headerRow := ""
	for _, h := range headers {
		headerRow += tableHeaderStyle.Render(padRight(h, 16))
	}
	b.WriteString(headerRow)
	b.WriteString("\n")

	visibleRows := m.height - 14
	if visibleRows < 3 {
		visibleRows = 10
	}

	start := m.tableCursor - visibleRows/2
	if start < 0 {
		start = 0
	}
	end := start + visibleRows
	if end > len(rows) {
		end = len(rows)
		start = end - visibleRows
		if start < 0 {
			start = 0
		}
	}

	for i := start; i < end; i++ {
		row := ""
		for j, cell := range rows[i] {
			w := 16
			if j < len(headers) {
				w = len(headers[j]) + 4
				if w < 16 {
					w = 16
				}
			}
			rendered := truncate(cell, w-2)
			if i == m.tableCursor {
				row += tableSelectedStyle.Render(padRight(rendered, w))
			} else {
				row += tableCellStyle.Render(padRight(rendered, w))
			}
		}
		b.WriteString(row)
		b.WriteString("\n")
	}

	scrollInfo := fmt.Sprintf("  %d-%d of %d", start+1, end, len(rows))
	b.WriteString(statusStyle.Render(scrollInfo))
	return b.String()
}
