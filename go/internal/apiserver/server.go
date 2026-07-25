package apiserver

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/proxmox-kvm-swissknife/internal/proxmox"
)

// Server is the REST API gateway for Proxmox VE.
type Server struct {
	config  Config
	client  *proxmox.Client
	logger  zerolog.Logger
	metrics Metrics
	mux     *http.ServeMux
	server  *http.Server
}

// New creates a new API server instance.
func New(cfg Config) (*Server, error) {
	client, err := proxmox.New(cfg.Proxmox.URL, cfg.Proxmox.User, cfg.Proxmox.TokenID, cfg.Proxmox.TokenSecret)
	if err != nil {
		return nil, fmt.Errorf("creating proxmox client: %w", err)
	}

	s := &Server{
		config: cfg,
		client: client,
		logger: log.With().Str("component", "api-gateway").Logger(),
		metrics: Metrics{
			RequestCount: prometheus.NewCounterVec(
				prometheus.CounterOpts{
					Name: "apigateway_requests_total",
					Help: "Total API requests",
				},
				[]string{"method", "path", "status"},
			),
			RequestDuration: prometheus.NewHistogramVec(
				prometheus.HistogramOpts{
					Name:    "apigateway_request_duration_seconds",
					Help:    "API request duration in seconds",
					Buckets: prometheus.DefBuckets,
				},
				[]string{"method", "path"},
			),
			ActiveRequests: prometheus.NewGauge(
				prometheus.GaugeOpts{
					Name: "apigateway_active_requests",
					Help: "Active API requests",
				},
			),
		},
	}

	prometheus.MustRegister(s.metrics.RequestCount)
	prometheus.MustRegister(s.metrics.RequestDuration)
	prometheus.MustRegister(s.metrics.ActiveRequests)

	s.registerRoutes()
	return s, nil
}

// Client returns the underlying Proxmox client.
func (s *Server) Client() *proxmox.Client {
	return s.client
}

func (s *Server) registerRoutes() {
	mux := http.NewServeMux()

	// Health
	mux.HandleFunc("GET /api/v1/health", s.handleHealth)

	// Status
	mux.HandleFunc("GET /api/v1/status", s.wrap(s.handleClusterStatus))

	// Nodes
	mux.HandleFunc("GET /api/v1/nodes", s.wrap(s.handleListNodes))
	mux.HandleFunc("GET /api/v1/nodes/{node}", s.wrap(s.handleGetNode))
	mux.HandleFunc("GET /api/v1/nodes/{node}/status", s.wrap(s.handleGetNodeStatus))
	mux.HandleFunc("GET /api/v1/nodes/{node}/services", s.wrap(s.handleNodeServices))

	// VMs
	mux.HandleFunc("GET /api/v1/vms", s.wrap(s.handleListVMs))
	mux.HandleFunc("GET /api/v1/vms/{vmid}", s.wrap(s.handleGetVM))
	mux.HandleFunc("POST /api/v1/vms", s.wrap(s.handleCreateVM))
	mux.HandleFunc("DELETE /api/v1/vms/{vmid}", s.wrap(s.handleDeleteVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/start", s.wrap(s.handleStartVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/stop", s.wrap(s.handleStopVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/shutdown", s.wrap(s.handleShutdownVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/clone", s.wrap(s.handleCloneVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/resize", s.wrap(s.handleResizeVM))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/migrate", s.wrap(s.handleMigrateVM))
	mux.HandleFunc("GET /api/v1/vms/{vmid}/config", s.wrap(s.handleGetVMConfig))
	mux.HandleFunc("PUT /api/v1/vms/{vmid}/config", s.wrap(s.handleSetVMConfig))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/monitor", s.wrap(s.handleMonitorVM))

	// Snapshots
	mux.HandleFunc("GET /api/v1/vms/{vmid}/snapshots", s.wrap(s.handleListSnapshots))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/snapshots", s.wrap(s.handleCreateSnapshot))
	mux.HandleFunc("DELETE /api/v1/vms/{vmid}/snapshots/{snapname}", s.wrap(s.handleDeleteSnapshot))
	mux.HandleFunc("POST /api/v1/vms/{vmid}/snapshots/{snapname}/rollback", s.wrap(s.handleRollbackSnapshot))

	// Containers
	mux.HandleFunc("GET /api/v1/containers", s.wrap(s.handleListContainers))
	mux.HandleFunc("GET /api/v1/containers/{ctid}", s.wrap(s.handleGetContainer))
	mux.HandleFunc("POST /api/v1/containers", s.wrap(s.handleCreateContainer))
	mux.HandleFunc("DELETE /api/v1/containers/{ctid}", s.wrap(s.handleDeleteContainer))
	mux.HandleFunc("POST /api/v1/containers/{ctid}/start", s.wrap(s.handleStartContainer))
	mux.HandleFunc("POST /api/v1/containers/{ctid}/stop", s.wrap(s.handleStopContainer))
	mux.HandleFunc("POST /api/v1/containers/{ctid}/shutdown", s.wrap(s.handleShutdownContainer))

	// Storage
	mux.HandleFunc("GET /api/v1/storage", s.wrap(s.handleListStorage))
	mux.HandleFunc("GET /api/v1/nodes/{node}/storage/{storage}/content", s.wrap(s.handleStorageContent))
	mux.HandleFunc("POST /api/v1/storage", s.wrap(s.handleAddStorage))
	mux.HandleFunc("DELETE /api/v1/storage/{storage}", s.wrap(s.handleRemoveStorage))

	// Pools
	mux.HandleFunc("GET /api/v1/pools", s.wrap(s.handleListPools))
	mux.HandleFunc("POST /api/v1/pools", s.wrap(s.handleCreatePool))
	mux.HandleFunc("DELETE /api/v1/pools/{poolid}", s.wrap(s.handleDeletePool))

	// Cluster
	mux.HandleFunc("GET /api/v1/cluster/status", s.wrap(s.handleClusterStatus))
	mux.HandleFunc("GET /api/v1/cluster/resources", s.wrap(s.handleClusterResources))
	mux.HandleFunc("GET /api/v1/cluster/log", s.wrap(s.handleClusterLog))
	mux.HandleFunc("GET /api/v1/cluster/options", s.wrap(s.handleClusterOptions))

	// Backups
	mux.HandleFunc("GET /api/v1/backups", s.wrap(s.handleListBackups))
	mux.HandleFunc("POST /api/v1/backups/{vmid}/now", s.wrap(s.handleBackupNow))

	// Network
	mux.HandleFunc("GET /api/v1/nodes/{node}/network", s.wrap(s.handleListNodeNetwork))
	mux.HandleFunc("POST /api/v1/nodes/{node}/network", s.wrap(s.handleCreateNetwork))

	// Firewall
	mux.HandleFunc("GET /api/v1/nodes/{node}/firewall/rules", s.wrap(s.handleFirewallRules))
	mux.HandleFunc("POST /api/v1/nodes/{node}/firewall/rules", s.wrap(s.handleAddFirewallRule))

	// HA
	mux.HandleFunc("GET /api/v1/ha/groups", s.wrap(s.handleHAGroups))
	mux.HandleFunc("POST /api/v1/ha/groups", s.wrap(s.handleCreateHAGroup))
	mux.HandleFunc("GET /api/v1/ha/resources", s.wrap(s.handleHAResources))

	// Metrics
	mux.HandleFunc("GET /api/v1/metrics/nodes", s.wrap(s.handleNodeMetrics))
	mux.HandleFunc("GET /api/v1/metrics/cluster", s.wrap(s.handleClusterMetrics))

	// Prometheus metrics
	mux.Handle("GET /metrics", promhttp.Handler())

	s.mux = mux
}

// Start begins the HTTP server.
func (s *Server) Start(ctx context.Context) error {
	handler := s.withMiddleware(s.mux)

	s.server = &http.Server{
		Addr:         s.config.Listen,
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	s.logger.Info().Str("listen", s.config.Listen).Msg("starting API gateway")

	if s.config.TLS.Enabled {
		return s.server.ListenAndServeTLS(s.config.TLS.Cert, s.config.TLS.Key)
	}
	return s.server.ListenAndServe()
}

// Shutdown gracefully shuts down the server.
func (s *Server) Shutdown(ctx context.Context) error {
	return s.server.Shutdown(ctx)
}

// withMiddleware wraps the mux with all middleware.
func (s *Server) withMiddleware(next http.Handler) http.Handler {
	return s.withMetrics(
		s.withLogger(
			s.withCORS(
				s.withRequestID(
					s.withAuth(next),
				),
			),
		),
	)
}

// --- Middleware ---

func (s *Server) withAuth(next http.Handler) http.Handler {
	if !s.config.Auth.Enabled {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/v1/health" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		key := r.Header.Get("X-API-Key")
		if key == "" {
			key = r.Header.Get("Authorization")
			if strings.HasPrefix(key, "Bearer ") {
				key = strings.TrimPrefix(key, "Bearer ")
			}
		}

		if s.config.Auth.APIKey != "" {
			if subtle.ConstantTimeCompare([]byte(key), []byte(s.config.Auth.APIKey)) != 1 {
				s.writeError(w, http.StatusUnauthorized, "invalid or missing API key")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lrw := &loggingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(lrw, r)
		s.logger.Info().
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Int("status", lrw.statusCode).
			Dur("duration", time.Since(start)).
			Str("remote", r.RemoteAddr).
			Msg("request")
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Key")
		w.Header().Set("Access-Control-Max-Age", "86400")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			id = fmt.Sprintf("req-%d", time.Now().UnixNano())
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withMetrics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.metrics.ActiveRequests.Inc()
		defer s.metrics.ActiveRequests.Dec()

		start := time.Now()
		lrw := &loggingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(lrw, r)

		duration := time.Since(start).Seconds()
		path := r.URL.Path
		s.metrics.RequestCount.WithLabelValues(r.Method, path, http.StatusText(lrw.statusCode)).Inc()
		s.metrics.RequestDuration.WithLabelValues(r.Method, path).Observe(duration)
	})
}

// --- Helpers ---

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (lrw *loggingResponseWriter) WriteHeader(code int) {
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

type handlerFunc func(w http.ResponseWriter, r *http.Request) (interface{}, error)

func (s *Server) wrap(fn handlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		data, err := fn(w, r)
		if err != nil {
			s.writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		s.writeJSON(w, http.StatusOK, APIResponse{
			Success: true,
			Data:    data,
		})
	}
}

func (s *Server) writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func (s *Server) writeError(w http.ResponseWriter, status int, msg string) {
	s.logger.Warn().Int("status", status).Str("error", msg).Msg("api error")
	s.writeJSON(w, status, APIResponse{
		Success: false,
		Error:   msg,
	})
}

func (s *Server) vmid(r *http.Request) string {
	return r.PathValue("vmid")
}

func (s *Server) node(r *http.Request) string {
	if n := r.PathValue("node"); n != "" {
		return n
	}
	return ""
}

// parseBody decodes JSON request body into the given target.
func parseBody(r *http.Request, target interface{}) error {
	if r.Body == nil {
		return fmt.Errorf("request body is required")
	}
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(target)
}
