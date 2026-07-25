// SPDX-License-Identifier: MIT

package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type ConfirmModel struct {
	Message  string
	Confirmed bool
	Cursor   int
	OnYes    func() tea.Cmd
	OnNo     func() tea.Cmd
}

func NewConfirmModel(message string, onYes, onNo func() tea.Cmd) *ConfirmModel {
	return &ConfirmModel{
		Message:  message,
		Confirmed: false,
		Cursor:   0,
		OnYes:    onYes,
		OnNo:     onNo,
	}
}

func (c *ConfirmModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "left", "h":
			if c.Cursor > 0 {
				c.Cursor--
			}
			return c, nil

		case "right", "l":
			if c.Cursor < 1 {
				c.Cursor++
			}
			return c, nil

		case "enter":
			if c.Cursor == 0 {
				c.Confirmed = true
				if c.OnYes != nil {
					return c, c.OnYes()
				}
			} else {
				c.Confirmed = false
				if c.OnNo != nil {
					return c, c.OnNo()
				}
			}
			return c, nil

		case "esc":
			c.Confirmed = false
			if c.OnNo != nil {
				return c, c.OnNo()
			}
			return c, nil

		case "y":
			c.Cursor = 0
			c.Confirmed = true
			if c.OnYes != nil {
				return c, c.OnYes()
			}
			return c, nil

		case "n":
			c.Cursor = 1
			c.Confirmed = false
			if c.OnNo != nil {
				return c, c.OnNo()
			}
			return c, nil
		}
	}

	return c, nil
}

func (c *ConfirmModel) Render() string {
	var b strings.Builder

	message := lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorFg)).
		Bold(true).
		Padding(0, 1).
		Render(c.Message)

	yesBtn := confirmButtonInactiveStyle.Render("  Yes  ")
	noBtn := confirmButtonInactiveStyle.Render("  No  ")

	if c.Cursor == 0 {
		yesBtn = confirmButtonActiveStyle.Render("  Yes  ")
	} else {
		noBtn = confirmButtonActiveStyle.Render("  No  ")
	}

	buttons := lipgloss.JoinHorizontal(lipgloss.Center, yesBtn, noBtn)

	content := lipgloss.JoinVertical(
		lipgloss.Center,
		message,
		"",
		buttons,
	)

	dialog := confirmStyle.Render(content)

	verticalPad := (c.height() - 8) / 2
	if verticalPad > 0 {
		b.WriteString(strings.Repeat("\n", verticalPad))
	}

	horizontalPad := (c.width() - lipgloss.Width(dialog)) / 2
	if horizontalPad > 0 {
		b.WriteString(strings.Repeat(" ", horizontalPad))
	}

	b.WriteString(dialog)

	return b.String()
}

func (c *ConfirmModel) height() int {
	return 24
}

func (c *ConfirmModel) width() int {
	return 80
}

func (m *Model) renderConfirm() string {
	confirm := NewConfirmModel(
		m.confirmMessage,
		func() tea.Cmd {
			m.currentView = m.previousViews[len(m.previousViews)-1]
			m.previousViews = m.previousViews[:len(m.previousViews)-1]
			return m.confirmAction
		},
		func() tea.Cmd {
			m.currentView = m.previousViews[len(m.previousViews)-1]
			m.previousViews = m.previousViews[:len(m.previousViews)-1]
			m.statusMessage = "Cancelled"
			m.statusIsError = false
			return nil
		},
	)
	confirm.Cursor = m.confirmCursor
	return confirm.Render()
}

func (m *Model) showConfirm(message string, action tea.Cmd) {
	m.confirmMessage = message
	m.confirmAction = action
	m.confirmCursor = 0
	m.previousViews = append(m.previousViews, m.currentView)
	m.currentView = viewConfirm
}


