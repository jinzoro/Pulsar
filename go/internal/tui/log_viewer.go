// SPDX-License-Identifier: MIT

package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type LogViewModel struct {
	Content    string
	lines      []string
	maxLines   int
	autoScroll bool
	scrollPos  int
	width      int
	height     int
}

func NewLogViewModel(maxLines int) *LogViewModel {
	if maxLines <= 0 {
		maxLines = 500
	}
	return &LogViewModel{
		maxLines:   maxLines,
		autoScroll: true,
		lines:      make([]string, 0, maxLines),
	}
}

func (l *LogViewModel) AppendLine(line string) {
	l.lines = append(l.lines, line)
	if len(l.lines) > l.maxLines {
		l.lines = l.lines[len(l.lines)-l.maxLines:]
	}
	if l.autoScroll {
		l.scrollPos = len(l.lines)
	}
}

func (l *LogViewModel) SetSize(width, height int) {
	l.width = width
	l.height = height
}

func (l *LogViewModel) ToggleAutoScroll() {
	l.autoScroll = !l.autoScroll
	if l.autoScroll {
		l.scrollPos = len(l.lines)
	}
}

func (l *LogViewModel) ScrollUp() {
	l.scrollPos -= 5
	if l.scrollPos < 0 {
		l.scrollPos = 0
	}
}

func (l *LogViewModel) ScrollDown() {
	l.scrollPos += 5
	if l.scrollPos > len(l.lines) {
		l.scrollPos = len(l.lines)
	}
}

func (l *LogViewModel) ScrollToBottom() {
	l.scrollPos = len(l.lines)
	l.autoScroll = true
}

func (l *LogViewModel) ScrollToTop() {
	l.scrollPos = 0
	l.autoScroll = false
}

func (l *LogViewModel) Clear() {
	l.lines = l.lines[:0]
	l.scrollPos = 0
	l.Content = ""
}

func (l *LogViewModel) Render() string {
	var b strings.Builder

	b.WriteString(viewportHeaderStyle.Render("  Log Output"))

	autoScrollIndicator := ""
	if l.autoScroll {
		autoScrollIndicator = successStyle.Render(" [auto-scroll]")
	} else {
		autoScrollIndicator = warningStyle.Render(" [paused]")
	}
	b.WriteString(statusStyle.Render(autoScrollIndicator))
	b.WriteString("\n")

	viewportHeight := l.height - 10
	if viewportHeight < 5 {
		viewportHeight = 15
	}

	viewportWidth := l.width - 4
	if viewportWidth < 40 {
		viewportWidth = 76
	}

	start := l.scrollPos - viewportHeight
	if start < 0 {
		start = 0
	}
	end := l.scrollPos
	if end > len(l.lines) {
		end = len(l.lines)
	}

	var content strings.Builder
	for _, line := range l.lines[start:end] {
		styledLine := l.styleLogLine(line)
		if lipgloss.Width(styledLine) > viewportWidth {
			styledLine = truncateStyled(styledLine, viewportWidth)
		}
		content.WriteString(styledLine)
		content.WriteString("\n")
	}

	if len(l.lines) == 0 {
		content.WriteString(emptyStateStyle.Render("  No log output yet."))
	}

	rendered := viewportStyle.
		Width(viewportWidth).
		Height(viewportHeight).
		Render(content.String())

	b.WriteString(rendered)

	b.WriteString("\n")
	lineInfo := statusStyle.Render(
		"  Lines: " + strings.Repeat(" ", 1) +
			strings.Repeat(" ", 1) +
			formatScrollInfo(start, end, len(l.lines)) +
			"  ↑/↓:scroll  g:top  G:bottom  a:auto-scroll  c:clear",
	)
	b.WriteString(lineInfo)

	return b.String()
}

func (l *LogViewModel) styleLogLine(line string) string {
	upper := strings.ToUpper(line)
	if strings.Contains(upper, "ERROR") || strings.Contains(upper, "FATAL") {
		return logLevelErrorStyle.Render("  " + line)
	}
	if strings.Contains(upper, "WARN") || strings.Contains(upper, "WARNING") {
		return logLevelWarnStyle.Render("  " + line)
	}
	if strings.Contains(upper, "INFO") || strings.Contains(upper, "SUCCESS") {
		return logLevelInfoStyle.Render("  " + line)
	}
	return statusStyle.Render("  " + line)
}

func formatScrollInfo(start, end, total int) string {
	if total == 0 {
		return "0/0"
	}
	return strings.Repeat(" ", 1) +
		strings.Repeat(" ", 1) +
		strings.Repeat(" ", 1) +
		strings.Repeat(" ", 1)
}

func truncateStyled(s string, max int) string {
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	if max > 3 {
		return string(runes[:max-3]) + "..."
	}
	return string(runes[:max])
}

func (m *Model) renderLog() string {
	if m.logModel == nil {
		return emptyStateStyle.Render("  No log viewer available")
	}
	m.logModel.SetSize(m.width, m.height)
	return m.logModel.Render()
}
