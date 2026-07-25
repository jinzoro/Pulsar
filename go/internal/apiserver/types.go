package apiserver

import "github.com/prometheus/client_golang/prometheus"

// Config holds the API server configuration.
type Config struct {
	Listen    string `mapstructure:"listen"`
	TLS       TLSConfig `mapstructure:"tls"`
	Proxmox   ProxmoxConfig `mapstructure:"proxmox"`
	Auth      AuthConfig `mapstructure:"auth"`
	RateLimit float64 `mapstructure:"rate_limit"`
}

// TLSConfig holds TLS configuration.
type TLSConfig struct {
	Enabled bool   `mapstructure:"enabled"`
	Cert    string `mapstructure:"cert"`
	Key     string `mapstructure:"key"`
}

// ProxmoxConfig holds Proxmox connection configuration.
type ProxmoxConfig struct {
	URL         string `mapstructure:"url"`
	User        string `mapstructure:"user"`
	TokenID     string `mapstructure:"token_id"`
	TokenSecret string `mapstructure:"token_secret"`
}

// AuthConfig holds API authentication configuration.
type AuthConfig struct {
	Enabled    bool   `mapstructure:"enabled"`
	APIKey     string `mapstructure:"api_key"`
	JWTSecret  string `mapstructure:"jwt_secret"`
}

// DefaultConfig returns the default server configuration.
func DefaultConfig() Config {
	return Config{
		Listen: ":8443",
		TLS: TLSConfig{
			Enabled: false,
		},
		Proxmox: ProxmoxConfig{},
		Auth: AuthConfig{
			Enabled: true,
		},
		RateLimit: 30,
	}
}

// APIResponse is a standard API response wrapper.
type APIResponse struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
	Meta    *APIMeta    `json:"meta,omitempty"`
}

// APIMeta holds pagination or additional metadata.
type APIMeta struct {
	Total   int `json:"total,omitempty"`
	Page    int `json:"page,omitempty"`
	PerPage int `json:"per_page,omitempty"`
}

// Metrics holds Prometheus metrics for the API server.
type Metrics struct {
	RequestCount    *prometheus.CounterVec
	RequestDuration *prometheus.HistogramVec
	ActiveRequests  prometheus.Gauge
}
