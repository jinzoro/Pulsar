// SPDX-License-Identifier: MIT

package config

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/spf13/viper"
)

// Config holds all application configuration.
type Config struct {
	Proxmox       ProxmoxConfig       `mapstructure:"proxmox"`
	KVM           KVMConfig           `mapstructure:"kvm"`
	Defaults      DefaultsConfig      `mapstructure:"defaults"`
	Notifications NotificationsConfig `mapstructure:"notifications"`
	Alerts        AlertsConfig        `mapstructure:"alerts"`
	TUI           TUIConfig           `mapstructure:"tui"`
	SSH           SSHConfig           `mapstructure:"ssh"`
}

// ProxmoxConfig holds Proxmox API connection settings.
type ProxmoxConfig struct {
	APIURL         string        `mapstructure:"api_url"`
	User           string        `mapstructure:"user"`
	APITokenID     string        `mapstructure:"api_token_id"`
	APITokenSecret string        `mapstructure:"api_token_secret"`
	Timeout        time.Duration `mapstructure:"timeout"`
	Insecure       bool          `mapstructure:"insecure"`
	RetryCount     int           `mapstructure:"retry_count"`
	RetryDelay     time.Duration `mapstructure:"retry_delay"`
	RateLimit      float64       `mapstructure:"rate_limit"`
	Node           string        `mapstructure:"node"`
}

// KVMConfig holds KVM/libvirt connection settings.
type KVMConfig struct {
	LibvirtURI string `mapstructure:"libvirt_uri"`
	QMPSocket  string `mapstructure:"qmp_socket"`
	Emulator   string `mapstructure:"emulator"`
}

// DefaultsConfig holds default settings for operations.
type DefaultsConfig struct {
	CPU       int    `mapstructure:"cpu"`
	Memory    int    `mapstructure:"memory"`
	DiskSize  string `mapstructure:"disk_size"`
	Network   string `mapstructure:"network"`
	Storage   string `mapstructure:"storage"`
	OS        string `mapstructure:"os"`
	ScsiHW   string `mapstructure:"scsihw"`
	Bios      string `mapstructure:"bios"`
	Machine   string `mapstructure:"machine"`
}

// NotificationsConfig holds notification settings.
type NotificationsConfig struct {
	Enabled  bool   `mapstructure:"enabled"`
	Webhook  string `mapstructure:"webhook"`
	Email    string `mapstructure:"email"`
	Slack    string `mapstructure:"slack"`
}

// AlertsConfig holds alerting thresholds.
type AlertsConfig struct {
	CPUThreshold    float64 `mapstructure:"cpu_threshold"`
	MemoryThreshold float64 `mapstructure:"memory_threshold"`
	DiskThreshold   float64 `mapstructure:"disk_threshold"`
}

// TUIConfig holds TUI display settings.
type TUIConfig struct {
	Theme    string `mapstructure:"theme"`
	LogLevel string `mapstructure:"log_level"`
	Refresh  int    `mapstructure:"refresh"`
}

// SSHConfig holds SSH connection defaults.
type SSHConfig struct {
	User       string        `mapstructure:"user"`
	Port       int           `mapstructure:"port"`
	KeyFile    string        `mapstructure:"key_file"`
	Timeout    time.Duration `mapstructure:"timeout"`
	StrictHost bool          `mapstructure:"strict_host_key_checking"`
}

// Default returns a Config with default values.
func Default() *Config {
	return &Config{
		Proxmox: ProxmoxConfig{
			APIURL:     "https://localhost:8006",
			User:       "root@pam",
			Timeout:    30 * time.Second,
			RetryCount: 3,
			RetryDelay: 1 * time.Second,
			RateLimit:  10.0,
			Node:       "pve",
		},
		KVM: KVMConfig{
			LibvirtURI: "qemu:///system",
			Emulator:   "/usr/bin/qemu-system-x86_64",
		},
		Defaults: DefaultsConfig{
			CPU:     2,
			Memory:  2048,
			DiskSize: "32G",
			Network: "vmbr0",
			Storage: "local-lvm",
			OS:      "l26",
			ScsiHW:  "virtio-scsi-pci",
			Bios:    "seabios",
			Machine: "q35",
		},
		Notifications: NotificationsConfig{
			Enabled: false,
		},
		Alerts: AlertsConfig{
			CPUThreshold:    90.0,
			MemoryThreshold: 85.0,
			DiskThreshold:   90.0,
		},
		TUI: TUIConfig{
			Theme:    "default",
			LogLevel: "info",
			Refresh:  5,
		},
		SSH: SSHConfig{
			User:       "root",
			Port:       22,
			KeyFile:    filepath.Join(os.Getenv("HOME"), ".ssh", "id_rsa"),
			Timeout:    10 * time.Second,
			StrictHost: true,
		},
	}
}

// Load reads configuration from a file, environment variables, and defaults.
func Load(path string) (*Config, error) {
	cfg := Default()
	v := viper.New()

	v.SetConfigType("yaml")
	v.AutomaticEnv()

	v.SetDefault("proxmox.api_url", cfg.Proxmox.APIURL)
	v.SetDefault("proxmox.user", cfg.Proxmox.User)
	v.SetDefault("proxmox.timeout", cfg.Proxmox.Timeout)
	v.SetDefault("proxmox.retry_count", cfg.Proxmox.RetryCount)
	v.SetDefault("proxmox.retry_delay", cfg.Proxmox.RetryDelay)
	v.SetDefault("proxmox.rate_limit", cfg.Proxmox.RateLimit)
	v.SetDefault("kvm.libvirt_uri", cfg.KVM.LibvirtURI)
	v.SetDefault("defaults.cpu", cfg.Defaults.CPU)
	v.SetDefault("defaults.memory", cfg.Defaults.Memory)
	v.SetDefault("defaults.disk_size", cfg.Defaults.DiskSize)
	v.SetDefault("defaults.network", cfg.Defaults.Network)
	v.SetDefault("defaults.storage", cfg.Defaults.Storage)
	v.SetDefault("tui.theme", cfg.TUI.Theme)
	v.SetDefault("tui.log_level", cfg.TUI.LogLevel)
	v.SetDefault("tui.refresh", cfg.TUI.Refresh)
	v.SetDefault("ssh.user", cfg.SSH.User)
	v.SetDefault("ssh.port", cfg.SSH.Port)

	if path == "" {
		home, err := os.UserHomeDir()
		if err == nil {
			v.AddConfigPath(filepath.Join(home, ".config", "swissknife"))
			v.AddConfigPath(home)
		}
		v.SetConfigName("config")
	} else {
		v.SetConfigFile(path)
	}

	_ = v.ReadInConfig()

	if v.IsSet("proxmox.api_url") {
		cfg.Proxmox.APIURL = v.GetString("proxmox.api_url")
	}
	if v.IsSet("proxmox.user") {
		cfg.Proxmox.User = v.GetString("proxmox.user")
	}
	if v.IsSet("proxmox.api_token_id") {
		cfg.Proxmox.APITokenID = v.GetString("proxmox.api_token_id")
	}
	if v.IsSet("proxmox.api_token_secret") {
		cfg.Proxmox.APITokenSecret = v.GetString("proxmox.api_token_secret")
	}
	if v.IsSet("proxmox.insecure") {
		cfg.Proxmox.Insecure = v.GetBool("proxmox.insecure")
	}
	if v.IsSet("proxmox.node") {
		cfg.Proxmox.Node = v.GetString("proxmox.node")
	}
	if v.IsSet("kvm.libvirt_uri") {
		cfg.KVM.LibvirtURI = v.GetString("kvm.libvirt_uri")
	}
	if v.IsSet("kvm.qmp_socket") {
		cfg.KVM.QMPSocket = v.GetString("kvm.qmp_socket")
	}
	if v.IsSet("defaults.cpu") {
		cfg.Defaults.CPU = v.GetInt("defaults.cpu")
	}
	if v.IsSet("defaults.memory") {
		cfg.Defaults.Memory = v.GetInt("defaults.memory")
	}
	if v.IsSet("defaults.disk_size") {
		cfg.Defaults.DiskSize = v.GetString("defaults.disk_size")
	}
	if v.IsSet("defaults.network") {
		cfg.Defaults.Network = v.GetString("defaults.network")
	}
	if v.IsSet("defaults.storage") {
		cfg.Defaults.Storage = v.GetString("defaults.storage")
	}
	if v.IsSet("notifications.enabled") {
		cfg.Notifications.Enabled = v.GetBool("notifications.enabled")
	}
	if v.IsSet("notifications.webhook") {
		cfg.Notifications.Webhook = v.GetString("notifications.webhook")
	}
	if v.IsSet("alerts.cpu_threshold") {
		cfg.Alerts.CPUThreshold = v.GetFloat64("alerts.cpu_threshold")
	}
	if v.IsSet("alerts.memory_threshold") {
		cfg.Alerts.MemoryThreshold = v.GetFloat64("alerts.memory_threshold")
	}
	if v.IsSet("alerts.disk_threshold") {
		cfg.Alerts.DiskThreshold = v.GetFloat64("alerts.disk_threshold")
	}
	if v.IsSet("tui.theme") {
		cfg.TUI.Theme = v.GetString("tui.theme")
	}
	if v.IsSet("tui.log_level") {
		cfg.TUI.LogLevel = v.GetString("tui.log_level")
	}
	if v.IsSet("tui.refresh") {
		cfg.TUI.Refresh = v.GetInt("tui.refresh")
	}
	if v.IsSet("ssh.user") {
		cfg.SSH.User = v.GetString("ssh.user")
	}
	if v.IsSet("ssh.port") {
		cfg.SSH.Port = v.GetInt("ssh.port")
	}
	if v.IsSet("ssh.key_file") {
		cfg.SSH.KeyFile = v.GetString("ssh.key_file")
	}

	return cfg, nil
}

// LoadFromEnv overrides config values from environment variables.
func LoadFromEnv(cfg *Config) {
	if val := os.Getenv("PMX_API_URL"); val != "" {
		cfg.Proxmox.APIURL = val
	}
	if val := os.Getenv("PMX_API_USER"); val != "" {
		cfg.Proxmox.User = val
	}
	if val := os.Getenv("PMX_API_TOKEN_ID"); val != "" {
		cfg.Proxmox.APITokenID = val
	}
	if val := os.Getenv("PMX_API_TOKEN_SECRET"); val != "" {
		cfg.Proxmox.APITokenSecret = val
	}
	if val := os.Getenv("PMX_NODE"); val != "" {
		cfg.Proxmox.Node = val
	}
	if val := os.Getenv("KVM_LIBVIRT_URI"); val != "" {
		cfg.KVM.LibvirtURI = val
	}
	if val := os.Getenv("KVM_QMP_SOCKET"); val != "" {
		cfg.KVM.QMPSocket = val
	}
	if val := os.Getenv("SWISSKNIFE_LOG_LEVEL"); val != "" {
		cfg.TUI.LogLevel = val
	}
	if val := os.Getenv("SSH_USER"); val != "" {
		cfg.SSH.User = val
	}
	if val := os.Getenv("SSH_KEY_FILE"); val != "" {
		cfg.SSH.KeyFile = val
	}
}

// Validate checks the configuration for required fields.
func (c *Config) Validate() error {
	if c.Proxmox.APIURL == "" {
		return fmt.Errorf("proxmox.api_url is required")
	}
	if c.Proxmox.User == "" && c.Proxmox.APITokenID == "" {
		return fmt.Errorf("either proxmox.user or proxmox.api_token_id is required")
	}
	if c.Defaults.CPU < 1 {
		return fmt.Errorf("defaults.cpu must be >= 1")
	}
	if c.Defaults.Memory < 64 {
		return fmt.Errorf("defaults.memory must be >= 64 MB")
	}
	if c.TUI.Refresh < 1 {
		return fmt.Errorf("tui.refresh must be >= 1 second")
	}
	return nil
}
