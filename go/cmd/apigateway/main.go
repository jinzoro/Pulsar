package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rs/zerolog"
	"github.com/spf13/viper"

	"github.com/pulsar/internal/apiserver"
)

func main() {
	log := zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).
		With().
		Timestamp().
		Str("app", "apigateway").
		Logger()

	viper.SetConfigName("apigateway")
	viper.AddConfigPath(".")
	viper.AddConfigPath("$HOME/.config/swissknife")
	viper.AutomaticEnv()
	viper.SetEnvPrefix("APIGW")

	viper.SetDefault("listen", ":8443")
	viper.SetDefault("tls.enabled", false)
	viper.SetDefault("auth.enabled", false)
	viper.SetDefault("proxmox.url", "https://localhost:8006")
	viper.SetDefault("proxmox.user", "root@pam")

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			log.Fatal().Err(err).Msg("failed to read config file")
		}
	}

	cfg := apiserver.DefaultConfig()
	if v := viper.GetString("listen"); v != "" {
		cfg.Listen = v
	}
	cfg.TLS.Enabled = viper.GetBool("tls.enabled")
	cfg.TLS.Cert = viper.GetString("tls.cert")
	cfg.TLS.Key = viper.GetString("tls.key")
	cfg.Proxmox.URL = viper.GetString("proxmox.url")
	cfg.Proxmox.User = viper.GetString("proxmox.user")
	cfg.Proxmox.TokenID = viper.GetString("proxmox.token_id")
	cfg.Proxmox.TokenSecret = viper.GetString("proxmox.token_secret")
	cfg.Auth.Enabled = viper.GetBool("auth.enabled")
	cfg.Auth.APIKey = viper.GetString("auth.api_key")

	srv, err := apiserver.New(cfg)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create API server")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.Start(ctx); err != nil {
			log.Fatal().Err(err).Msg("server error")
		}
	}()

	<-quit
	log.Info().Msg("shutting down server...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatal().Err(err).Msg("server forced to shutdown")
	}

	log.Info().Msg("server stopped")
}
