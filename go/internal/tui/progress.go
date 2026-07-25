// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type ProgressModel struct {
	CurrentStep string
	Steps       []string
	Progress    float64
	IsComplete  bool
	Error       error
	width       int
	spinnerFrame int
	spinnerChars []string
}

func NewProgressModel() *ProgressModel {
	return &ProgressModel{
		Progress:     0,
		width:        60,
		spinnerChars: []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
	}
}

func (p *ProgressModel) SetWidth(w int) {
	p.width = w
}

func (p *ProgressModel) SetStep(step string) {
	p.CurrentStep = step
	found := false
	for i, s := range p.Steps {
		if s == step {
			p.Progress = float64(i) / float64(len(p.Steps))
			found = true
			break
		}
	}
	if !found {
		p.Steps = append(p.Steps, step)
		p.Progress = float64(len(p.Steps)-1) / float64(len(p.Steps))
	}
}

func (p *ProgressModel) SetProgress(progress float64) {
	p.Progress = progress
	if progress >= 1.0 {
		p.IsComplete = true
	}
}

func (p *ProgressModel) Complete() {
	p.Progress = 1.0
	p.IsComplete = true
}

func (p *ProgressModel) Fail(err error) {
	p.Error = err
	p.IsComplete = true
}

func (p *ProgressModel) advanceSpinner() string {
	ch := p.spinnerChars[p.spinnerFrame%len(p.spinnerChars)]
	p.spinnerFrame++
	return lipgloss.NewStyle().Foreground(lipgloss.Color(colorPrimary)).Render(ch)
}

func (p *ProgressModel) Render() string {
	var b strings.Builder

	b.WriteString(sectionHeaderStyle.Render("  Progress"))
	b.WriteString("\n\n")

	barWidth := p.width - 10
	if barWidth < 20 {
		barWidth = 40
	}

	filled := int(p.Progress * float64(barWidth))
	if filled > barWidth {
		filled = barWidth
	}

	bar := lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorPrimaryDim)).
		Render(strings.Repeat("█", filled)) +
		lipgloss.NewStyle().
			Foreground(lipgloss.Color(colorBorderDim)).
			Render(strings.Repeat("░", barWidth-filled))

	pct := fmt.Sprintf("%.0f%%", p.Progress*100)

	b.WriteString(fmt.Sprintf("  [%s] %s\n\n", bar, pct))

	if p.CurrentStep != "" {
		b.WriteString(fmt.Sprintf("  %s %s\n\n", statusStyle.Render("Step:"), p.CurrentStep))
	}

	for _, step := range p.Steps {
		icon := "  "
		if step == p.CurrentStep && !p.IsComplete {
			icon = p.advanceSpinner() + " "
		} else if p.IsComplete && p.Error == nil {
			icon = successStyle.Render("✓") + " "
		} else if step == p.CurrentStep && p.Error != nil {
			icon = errorStyle.Render("✕") + " "
		} else {
			icon = statusStyle.Render("○") + " "
		}
		b.WriteString(fmt.Sprintf("  %s%s\n", icon, step))
	}

	if p.IsComplete {
		b.WriteString("\n")
		if p.Error != nil {
			b.WriteString("  " + errorStyle.Render(fmt.Sprintf("Failed: %v", p.Error)))
		} else {
			b.WriteString("  " + successStyle.Render("Complete!"))
		}
	}

	return b.String()
}

func (m *Model) renderProgress() string {
	if m.progressModel == nil {
		return emptyStateStyle.Render("  No operation in progress")
	}
	return m.progressModel.Render()
}
