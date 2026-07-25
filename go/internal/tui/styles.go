// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

const (
	colorPrimary    = "#7D56F4"
	colorPrimaryDim = "#5B3DBF"
	colorAccent     = "#FF6B6B"
	colorGreen      = "#50FA7B"
	colorYellow     = "#F1FA8C"
	colorRed        = "#FF5555"
	colorOrange     = "#FFB86C"
	colorCyan       = "#8BE9FD"
	colorPurple     = "#BD93F9"
	colorPink       = "#FF79C6"
	colorFg         = "#F8F8F2"
	colorFgDim      = "#6272A4"
	colorBg         = "#282A36"
	colorBgLight    = "#44475A"
	colorBgDark     = "#1E1F29"
	colorBorder     = "#6272A4"
	colorBorderDim  = "#3D3F4D"
	colorSelection  = "#44475A"
)

var (
	TitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color(colorFg)).
			Background(lipgloss.Color(colorPrimary)).
			Padding(0, 2).
			MarginBottom(1)

	menuStyle = lipgloss.NewStyle().
			PaddingLeft(2)

	activeItemStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFg)).
			Background(lipgloss.Color(colorPrimary)).
			Bold(true).
			Padding(0, 2).
			MarginRight(1)

	inactiveItemStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorFgDim)).
				Padding(0, 2).
				MarginRight(1)

	helpBarStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim)).
			BorderTop(true).
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color(colorBorderDim)).
			PaddingTop(0)

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim)).
			Padding(0, 1)

	errorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorRed)).
			Bold(true)

	successStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorGreen)).
			Bold(true)

	warningStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorYellow)).
			Bold(true)

	formFieldStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFg)).
			Padding(0, 1)

	formLabelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorCyan)).
			Bold(true).
			Width(20)

	formInputStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFg)).
			Background(lipgloss.Color(colorBgLight)).
			Padding(0, 1).
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color(colorBorder))

	formInputFocusedStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorFg)).
				Background(lipgloss.Color(colorBgLight)).
				Padding(0, 1).
				Border(lipgloss.NormalBorder()).
				BorderForeground(lipgloss.Color(colorPrimary))

	confirmStyle = lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(lipgloss.Color(colorPrimary)).
			Padding(1, 3)

	confirmButtonActiveStyle = lipgloss.NewStyle().
					Foreground(lipgloss.Color(colorBg)).
					Background(lipgloss.Color(colorGreen)).
					Bold(true).
					Padding(0, 2).
					MarginRight(1)

	confirmButtonInactiveStyle = lipgloss.NewStyle().
					Foreground(lipgloss.Color(colorFgDim)).
					Padding(0, 2).
					MarginRight(1)

	tableHeaderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorCyan)).
				Bold(true).
				BorderBottom(true).
				BorderStyle(lipgloss.NormalBorder()).
				BorderForeground(lipgloss.Color(colorBorder)).
				Padding(0, 1)

	tableCellStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFg)).
			Padding(0, 1)

	tableSelectedStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorFg)).
				Background(lipgloss.Color(colorSelection)).
				Padding(0, 1)

	viewportStyle = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color(colorBorder)).
			Padding(0, 1)

	viewportHeaderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorCyan)).
				Bold(true).
				MarginBottom(1)

	sparklineStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorGreen))

	sparkLabelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim)).
			Width(12)

	sparkValueStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFg)).
			Bold(true).
			Width(10).
			Align(lipgloss.Right)

	sectionHeaderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorPurple)).
				Bold(true).
				Underline(true).
				MarginBottom(1)

	dividerStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorBorderDim))

	logTimeStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim))

	logLevelInfoStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorGreen))

	logLevelWarnStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorYellow))

	logLevelErrorStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(colorRed))

	emptyStateStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim)).
			Italic(true).
			Padding(2, 4)

	breadcrumbStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorFgDim)).
			Padding(0, 1)
)

func statusColor(status string) lipgloss.Color {
	switch status {
	case "running", "active", "online", "online", "enabled":
		return lipgloss.Color(colorGreen)
	case "stopped", "inactive", "offline", "disabled":
		return lipgloss.Color(colorRed)
	case "paused", "migrating", "pending":
		return lipgloss.Color(colorYellow)
	default:
		return lipgloss.Color(colorFgDim)
	}
}

func statusDot(status string) string {
	style := lipgloss.NewStyle().Foreground(statusColor(status)).Bold(true)
	return style.Render("●")
}

func formatBytes(b int64) string {
	const (
		KB = 1024
		MB = 1024 * KB
		GB = 1024 * MB
		TB = 1024 * GB
	)
	switch {
	case b >= TB:
		return fmt.Sprintf("%.1f TB", float64(b)/float64(TB))
	case b >= GB:
		return fmt.Sprintf("%.1f GB", float64(b)/float64(GB))
	case b >= MB:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(MB))
	case b >= KB:
		return fmt.Sprintf("%.1f KB", float64(b)/float64(KB))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

func padRight(s string, width int) string {
	if len(s) >= width {
		return s[:width]
	}
	return s + lipgloss.NewStyle().Width(width-len(s)).Render("")
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	if max > 3 {
		return s[:max-3] + "..."
	}
	return s[:max]
}
