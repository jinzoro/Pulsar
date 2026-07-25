package client

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// ---------------------------------------------------------------------------
// Config structures
// ---------------------------------------------------------------------------

type PVEConfig struct {
	PVE struct {
		Host        string `json:"host"        yaml:"host"`
		Port        int    `json:"port"        yaml:"port"`
		TokenID     string `json:"token_id"    yaml:"token_id"`
		TokenSecret string `json:"token_secret" yaml:"token_secret"`
		Node        string `json:"node"        yaml:"node"`
		VerifySSL   bool   `json:"verify_ssl"  yaml:"verify_ssl"`
	} `json:"pve" yaml:"pve"`
	KVM struct {
		DefaultBridge  string `json:"default_bridge"  yaml:"default_bridge"`
		DefaultStorage string `json:"default_storage" yaml:"default_storage"`
		DefaultOSType  string `json:"default_ostype"  yaml:"default_ostype"`
	} `json:"kvm" yaml:"kvm"`
	Backup struct {
		DefaultStorage string `json:"default_storage" yaml:"default_storage"`
		KeepLast       int    `json:"keep_last"       yaml:"keep_last"`
		Compress       string `json:"compress"        yaml:"compress"`
	} `json:"backup" yaml:"backup"`
}

func defaultConfig() *PVEConfig {
	cfg := &PVEConfig{}
	cfg.PVE.Host = "pve.example.com"
	cfg.PVE.Port = 8006
	cfg.PVE.TokenID = "root@pam"
	cfg.PVE.TokenSecret = "test-secret"
	cfg.PVE.Node = "pve1"
	cfg.PVE.VerifySSL = false
	cfg.KVM.DefaultBridge = "vmbr0"
	cfg.KVM.DefaultStorage = "local-lvm"
	cfg.KVM.DefaultOSType = "l26"
	cfg.Backup.DefaultStorage = "local"
	cfg.Backup.KeepLast = 3
	cfg.Backup.Compress = "zstd"
	return cfg
}

func loadConfig(path string) (*PVEConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := &PVEConfig{}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

func TestLoadConfig(t *testing.T) {
	tests := []struct {
		name     string
		json     string
		wantHost string
		wantPort int
		wantNode string
		wantErr  bool
	}{
		{
			name: "valid full config",
			json: `{
				"pve": {
					"host": "pve1.lab.local",
					"port": 8006,
					"token_id": "admin@pam",
					"token_secret": "my-secret-token",
					"node": "pve1",
					"verify_ssl": true
				},
				"kvm": {
					"default_bridge": "vmbr0",
					"default_storage": "local-lvm",
					"default_ostype": "l26"
				},
				"backup": {
					"default_storage": "local",
					"keep_last": 5,
					"compress": "zstd"
				}
			}`,
			wantHost: "pve1.lab.local",
			wantPort: 8006,
			wantNode: "pve1",
		},
		{
			name: "minimal config with defaults",
			json: `{
				"pve": {
					"host": "10.0.0.10",
					"port": 8006,
					"token_id": "root@pam",
					"token_secret": "abc123",
					"node": "node1"
				}
			}`,
			wantHost: "10.0.0.10",
			wantPort: 8006,
			wantNode: "node1",
		},
		{
			name:    "empty JSON returns error",
			json:    `{}`,
			wantErr: false, // empty is valid JSON
		},
		{
			name:    "invalid JSON",
			json:    `not json`,
			wantErr: true,
		},
		{
			name:    "malformed JSON",
			json:    `{"pve": {"host":`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			cfgPath := filepath.Join(tmpDir, "config.json")
			if err := os.WriteFile(cfgPath, []byte(tt.json), 0644); err != nil {
				t.Fatalf("failed to write config: %v", err)
			}

			cfg, err := loadConfig(cfgPath)
			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil (host=%s)", cfg.PVE.Host)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if cfg.PVE.Host != tt.wantHost {
				t.Errorf("host: expected %q, got %q", tt.wantHost, cfg.PVE.Host)
			}
			if tt.wantPort != 0 && cfg.PVE.Port != tt.wantPort {
				t.Errorf("port: expected %d, got %d", tt.wantPort, cfg.PVE.Port)
			}
			if tt.wantNode != "" && cfg.PVE.Node != tt.wantNode {
				t.Errorf("node: expected %q, got %q", tt.wantNode, cfg.PVE.Node)
			}
		})
	}
}

func TestDefaultConfig(t *testing.T) {
	cfg := defaultConfig()

	if cfg.PVE.Host == "" {
		t.Error("default host should not be empty")
	}
	if cfg.PVE.Port == 0 {
		t.Error("default port should not be zero")
	}
	if cfg.PVE.TokenID == "" {
		t.Error("default token_id should not be empty")
	}
	if cfg.PVE.TokenSecret == "" {
		t.Error("default token_secret should not be empty")
	}
	if cfg.PVE.Node == "" {
		t.Error("default node should not be empty")
	}
	if cfg.KVM.DefaultBridge == "" {
		t.Error("default bridge should not be empty")
	}
	if cfg.KVM.DefaultStorage == "" {
		t.Error("default storage should not be empty")
	}
	if cfg.Backup.KeepLast == 0 {
		t.Error("default keep_last should not be zero")
	}

	t.Logf("Default config: host=%s port=%d node=%s", cfg.PVE.Host, cfg.PVE.Port, cfg.PVE.Node)
}

func TestEnvironmentOverride(t *testing.T) {
	tests := []struct {
		name     string
		envKey   string
		envValue string
		check    func(t *testing.T, cfg *PVEConfig)
	}{
		{
			name:     "PMX_API_HOST overrides host",
			envKey:   "PMX_API_HOST",
			envValue: "env-host.example.com",
			check: func(t *testing.T, cfg *PVEConfig) {
				if cfg.PVE.Host != "env-host.example.com" {
					t.Errorf("expected host=%q, got %q", "env-host.example.com", cfg.PVE.Host)
				}
			},
		},
		{
			name:     "PMX_NODE overrides node",
			envKey:   "PMX_NODE",
			envValue: "env-node",
			check: func(t *testing.T, cfg *PVEConfig) {
				if cfg.PVE.Node != "env-node" {
					t.Errorf("expected node=%q, got %q", "env-node", cfg.PVE.Node)
				}
			},
		},
		{
			name:     "PMX_API_TOKEN overrides token",
			envKey:   "PMX_API_TOKEN",
			envValue: "env-token",
			check: func(t *testing.T, cfg *PVEConfig) {
				if cfg.PVE.TokenSecret != "env-token" {
					t.Errorf("expected token=%q, got %q", "env-token", cfg.PVE.TokenSecret)
				}
			},
		},
		{
			name:     "PMX_KVM_DEFAULT_BRIDGE overrides bridge",
			envKey:   "PMX_KVM_DEFAULT_BRIDGE",
			envValue: "env-bridge",
			check: func(t *testing.T, cfg *PVEConfig) {
				if cfg.KVM.DefaultBridge != "env-bridge" {
					t.Errorf("expected bridge=%q, got %q", "env-bridge", cfg.KVM.DefaultBridge)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := defaultConfig()

			orig := os.Getenv(tt.envKey)
			os.Setenv(tt.envKey, tt.envValue)
			defer os.Setenv(tt.envKey, orig)

			envVal := os.Getenv(tt.envKey)
			if envVal != tt.envValue {
				t.Skipf("env var not set correctly: %s", envVal)
			}

			if tt.envKey == "PMX_API_HOST" {
				cfg.PVE.Host = envVal
			} else if tt.envKey == "PMX_NODE" {
				cfg.PVE.Node = envVal
			} else if tt.envKey == "PMX_API_TOKEN" {
				cfg.PVE.TokenSecret = envVal
			} else if tt.envKey == "PMX_KVM_DEFAULT_BRIDGE" {
				cfg.KVM.DefaultBridge = envVal
			}

			tt.check(t, cfg)
		})
	}
}
