// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type FormField struct {
	Label       string
	Value       string
	Placeholder string
	Type        string
	Options     []string
	Required    bool
	Validator   func(string) error
}

type FormModel struct {
	Fields   []FormField
	Cursor   int
	Title    string
	OnSubmit func(map[string]string) tea.Cmd
	OnCancel func() tea.Cmd
	focused  bool
}

func NewFormModel(title string, fields []FormField, onSubmit func(map[string]string) tea.Cmd, onCancel func() tea.Cmd) *FormModel {
	return &FormModel{
		Fields:   fields,
		Cursor:   0,
		Title:    title,
		OnSubmit: onSubmit,
		OnCancel: onCancel,
		focused:  true,
	}
}

func (f *FormModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "tab", "down":
			f.Cursor++
			if f.Cursor >= len(f.Fields) {
				f.Cursor = 0
			}
			return f, nil

		case "shift+tab", "up":
			f.Cursor--
			if f.Cursor < 0 {
				f.Cursor = len(f.Fields) - 1
			}
			return f, nil

		case "enter":
			return f, f.submit()

		case "esc":
			if f.OnCancel != nil {
				return f, f.OnCancel()
			}
			return f, nil

		case "left":
			if f.Cursor < len(f.Fields) && f.Fields[f.Cursor].Type == "select" {
				field := &f.Fields[f.Cursor]
				idx := f.findOptionIndex(field)
				idx--
				if idx < 0 {
					idx = len(field.Options) - 1
				}
				if idx >= 0 && idx < len(field.Options) {
					field.Value = field.Options[idx]
				}
			}
			return f, nil

		case "right":
			if f.Cursor < len(f.Fields) && f.Fields[f.Cursor].Type == "select" {
				field := &f.Fields[f.Cursor]
				idx := f.findOptionIndex(field)
				idx++
				if idx >= len(field.Options) {
					idx = 0
				}
				if idx < len(field.Options) {
					field.Value = field.Options[idx]
				}
			}
			return f, nil

		case " ":
			if f.Cursor < len(f.Fields) && f.Fields[f.Cursor].Type == "checkbox" {
				field := &f.Fields[f.Cursor]
				if field.Value == "true" {
					field.Value = "false"
				} else {
					field.Value = "true"
				}
			}
			return f, nil
		}

		if f.Cursor < len(f.Fields) {
			field := &f.Fields[f.Cursor]
			if field.Type == "text" {
				switch msg.String() {
				case "backspace":
					if len(field.Value) > 0 {
						field.Value = field.Value[:len(field.Value)-1]
					}
				default:
					if len(msg.String()) == 1 {
						field.Value += msg.String()
					}
				}
			}
		}
	}

	return f, nil
}

func (f *FormModel) findOptionIndex(field *FormField) int {
	for i, opt := range field.Options {
		if opt == field.Value {
			return i
		}
	}
	return 0
}

func (f *FormModel) submit() tea.Cmd {
	for _, field := range f.Fields {
		if field.Required && field.Value == "" {
			return func() tea.Msg {
				return actionCompleteMsg{
					action: "validation",
					err:    fmt.Errorf("%s is required", field.Label),
				}
			}
		}
		if field.Validator != nil {
			if err := field.Validator(field.Value); err != nil {
				return func() tea.Msg {
					return actionCompleteMsg{
						action: "validation",
						err:    err,
					}
				}
			}
		}
	}

	values := make(map[string]string)
	for _, field := range f.Fields {
		values[field.Label] = field.Value
	}

	if f.OnSubmit != nil {
		return f.OnSubmit(values)
	}
	return nil
}

func (f *FormModel) Render() string {
	var b strings.Builder

	b.WriteString(sectionHeaderStyle.Render("  " + f.Title))
	b.WriteString("\n\n")

	for i, field := range f.Fields {
		isFocused := i == f.Cursor

		label := formLabelStyle.Render(fmt.Sprintf("%-18s", field.Label+":"))
		if field.Required {
			label += errorStyle.Render(" *")
		}

		var input string
		switch field.Type {
		case "text":
			if isFocused {
				input = formInputFocusedStyle.Width(40).Render(field.Value + "█")
			} else {
				display := field.Value
				if display == "" {
					display = field.Placeholder
					input = formInputStyle.Width(40).Render(
						lipgloss.NewStyle().Foreground(lipgloss.Color(colorFgDim)).Render(display),
					)
				} else {
					input = formInputStyle.Width(40).Render(display)
				}
			}

		case "select":
			if len(field.Options) > 0 {
				selected := field.Value
				if selected == "" {
					selected = field.Options[0]
					field.Value = selected
				}
				nav := statusStyle.Render(" ◀ ") + lipgloss.NewStyle().Bold(true).Render(selected) + statusStyle.Render(" ▶ ")
				if isFocused {
					input = formInputFocusedStyle.Render(nav)
				} else {
					input = formInputStyle.Render(nav)
				}
			}

		case "checkbox":
			check := "[ ]"
			if field.Value == "true" {
				check = successStyle.Render("[✓]")
			}
			if isFocused {
				input = formInputFocusedStyle.Render(" " + check + " ")
			} else {
				input = formInputStyle.Render(" " + check + " ")
			}
		}

		b.WriteString(fmt.Sprintf("  %s %s\n\n", label, input))
	}

	b.WriteString("\n")
	b.WriteString("  " + helpBarStyle.Render("tab/↑↓: navigate  enter: submit  esc: cancel"))
	if f.Cursor == len(f.Fields) {
		b.WriteString("  " + activeItemStyle.Render("  [SUBMIT]"))
	}

	return b.String()
}

func (m *Model) renderForm() string {
	if m.formFields == nil {
		return emptyStateStyle.Render("  No form to display")
	}

	form := NewFormModel(m.formTitle, m.formFields, m.formHandler, func() tea.Cmd {
		return m.goBack()
	})
	form.Cursor = m.formCursor

	return form.Render()
}
