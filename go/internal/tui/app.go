// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rs/zerolog"

	"github.com/proxmox-kvm-swissknife/internal/config"
)

// NewApp creates a new TUI application using the full Model system.
func NewApp(cfg *config.Config, log zerolog.Logger) (*Model, error) {
	m, err := NewModel(cfg, log)
	if err != nil {
		return nil, fmt.Errorf("failed to create TUI model: %w", err)
	}
	return m, nil
}

// Run starts the TUI program with alt screen.
func Run(cfg *config.Config, log zerolog.Logger) error {
	app, err := NewApp(cfg, log)
	if err != nil {
		return err
	}

	p := tea.NewProgram(app, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "TUI exited with error: %v\n", err)
		return err
	}
	return nil
}
