// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rs/zerolog"

	"github.com/pulsar/internal/config"
	"github.com/pulsar/internal/tui"
)

func main() {
	cfg, err := config.Load("")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	log := zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).
		With().
		Timestamp().
		Str("app", "swissknife").
		Logger()

	if cfg.TUI.LogLevel != "" {
		level, lerr := zerolog.ParseLevel(cfg.TUI.LogLevel)
		if lerr == nil {
			log = log.Level(level)
		}
	}

	log.Info().
		Str("version", "1.0.0").
		Msg("starting Pulsar TUI")

	app, err := tui.NewApp(cfg, log)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to initialize TUI")
	}

	p := tea.NewProgram(app, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		log.Fatal().Err(err).Msg("TUI exited with error")
	}
}
