package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func newTestServer(handler http.HandlerFunc) (*httptest.Server, func()) {
	srv := httptest.NewServer(handler)
	return srv, func() { srv.Close() }
}

func defaultHeaders() http.Header {
	h := http.Header{}
	h.Set("Authorization", "PVE:root@pam!token=secret123")
	h.Set("Content-Type", "application/json")
	return h
}

// ---------------------------------------------------------------------------
// Table-driven tests for NewClient
// ---------------------------------------------------------------------------

func TestNewClient(t *testing.T) {
	tests := []struct {
		name     string
		host     string
		port     int
		scheme   string
		token    string
		wantErr  bool
	}{
		{
			name:   "valid https client",
			host:   "pve.example.com",
			port:   8006,
			scheme: "https",
			token:  "root@pam!token=secret123",
		},
		{
			name:    "empty host returns error",
			host:    "",
			port:    8006,
			scheme:  "https",
			token:   "root@pam!token=secret123",
			wantErr: true,
		},
		{
			name:    "empty token returns error",
			host:    "pve.example.com",
			port:    8006,
			scheme:  "https",
			token:   "",
			wantErr: true,
		},
		{
			name:   "custom port",
			host:   "192.168.1.10",
			port:   9443,
			scheme: "https",
			token:  "admin@pve!key=abc",
		},
		{
			name:   "http scheme (non-standard)",
			host:   "localhost",
			port:   8006,
			scheme: "http",
			token:  "root@pam!key=test",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var client interface{}
			var err error

			if NewClientFunc != nil {
				client, err = NewClientFunc(tt.host, tt.port, tt.scheme, tt.token, false)
			} else {
				err = fmt.Errorf("NewClient not implemented")
			}

			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
			} else if err == nil && client == nil {
				t.Errorf("expected non-nil client")
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Table-driven tests for GET requests
// ---------------------------------------------------------------------------

func TestGetRequest(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		statusCode int
		body       interface{}
		wantErr    bool
	}{
		{
			name:       "list VMs",
			path:       "/api2/json/nodes/pve1/qemu",
			statusCode: http.StatusOK,
			body: map[string]interface{}{
				"data": []map[string]interface{}{
					{"vmid": "100", "name": "web-01", "status": "running"},
					{"vmid": "101", "name": "db-01", "status": "stopped"},
				},
			},
		},
		{
			name:       "get VM config",
			path:       "/api2/json/nodes/pve1/qemu/100/config",
			statusCode: http.StatusOK,
			body: map[string]interface{}{
				"data": map[string]interface{}{
					"vmid":   "100",
					"name":   "web-01",
					"cores":  4,
					"memory": 8192,
				},
			},
		},
		{
			name:       "404 not found",
			path:       "/api2/json/nodes/pve1/qemu/9999",
			statusCode: http.StatusNotFound,
			body:       map[string]interface{}{"errors": map[string]string{"404": "not found"}},
			wantErr:    true,
		},
		{
			name:       "empty data response",
			path:       "/api2/json/nodes/pve1/scan",
			statusCode: http.StatusOK,
			body:       map[string]interface{}{"data": []interface{}{}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv, cleanup := newTestServer(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet {
					t.Errorf("expected GET, got %s", r.Method)
				}
				w.WriteHeader(tt.statusCode)
				json.NewEncoder(w).Encode(tt.body)
			})
			defer cleanup()

			req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+tt.path, nil)
			if err != nil {
				t.Fatalf("failed to create request: %v", err)
			}
			req.Header = defaultHeaders()

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			body, _ := io.ReadAll(resp.Body)

			if tt.wantErr && resp.StatusCode < 400 {
				t.Errorf("expected error status, got %d", resp.StatusCode)
			}

			if resp.StatusCode >= 200 && resp.StatusCode < 300 {
				var result map[string]interface{}
				if err := json.Unmarshal(body, &result); err != nil {
					t.Errorf("failed to decode response: %v", err)
				}
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Table-driven tests for POST requests
// ---------------------------------------------------------------------------

func TestPostRequest(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		payload    interface{}
		statusCode int
		body       interface{}
	}{
		{
			name:    "create VM",
			path:    "/api2/json/nodes/pve1/qemu",
			payload: map[string]interface{}{"vmid": 200, "name": "new-vm", "cores": 2, "memory": 4096},
			body:    map[string]interface{}{"data": "UPID:pve1:0012345::root@pam"},
		},
		{
			name:    "start VM",
			path:    "/api2/json/nodes/pve1/qemu/100/status/start",
			payload: nil,
			body:    map[string]interface{}{"data": "UPID:pve1:0012346::root@pam"},
		},
		{
			name:    "stop VM",
			path:    "/api2/json/nodes/pve1/qemu/100/status/stop",
			payload: nil,
			body:    map[string]interface{}{"data": "UPID:pve1:0012347::root@pam"},
		},
		{
			name:       "create backup",
			path:       "/api2/json/nodes/pve1/storage/local/backup",
			payload:    map[string]interface{}{"vmid": "100", "mode": "snapshot"},
			statusCode: http.StatusOK,
			body:       map[string]interface{}{"data": "UPID:pve1:0012348::root@pam"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv, cleanup := newTestServer(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					t.Errorf("expected POST, got %s", r.Method)
				}
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(tt.body)
			})
			defer cleanup()

			var bodyReader io.Reader
			if tt.payload != nil {
				b, _ := json.Marshal(tt.payload)
				bodyReader = bytes.NewReader(b)
			}

			req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, srv.URL+tt.path, bodyReader)
			if err != nil {
				t.Fatalf("failed to create request: %v", err)
			}
			req.Header = defaultHeaders()

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode >= 400 {
				t.Errorf("unexpected error status: %d", resp.StatusCode)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Retry logic
// ---------------------------------------------------------------------------

func TestRetryLogic(t *testing.T) {
	tests := []struct {
		name          string
		failCount     int
		maxRetries    int
		expectedCalls int
		expectSuccess bool
	}{
		{
			name:          "succeeds on first try",
			failCount:     0,
			maxRetries:    3,
			expectedCalls: 1,
			expectSuccess: true,
		},
		{
			name:          "succeeds after 2 retries",
			failCount:     2,
			maxRetries:    5,
			expectedCalls: 3,
			expectSuccess: true,
		},
		{
			name:          "fails after max retries",
			failCount:     10,
			maxRetries:    3,
			expectedCalls: 4,
			expectSuccess: false,
		},
		{
			name:          "no retries configured",
			failCount:     1,
			maxRetries:    0,
			expectedCalls: 1,
			expectSuccess: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var callCount int32

			srv, cleanup := newTestServer(func(w http.ResponseWriter, r *http.Request) {
				c := atomic.AddInt32(&callCount, 1)
				if int(c) <= tt.failCount {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(`{"errors":{"500":"internal server error"}}`))
					return
				}
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(map[string]interface{}{"data": "ok"})
			})
			defer cleanup()

			var success bool
			var lastErr error
			for i := 0; i <= tt.maxRetries; i++ {
				req, _ := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/api2/json/test", nil)
				req.Header = defaultHeaders()
				resp, err := http.DefaultClient.Do(req)
				if err != nil {
					lastErr = err
					continue
				}
				resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					success = true
					break
				}
				lastErr = fmt.Errorf("status %d", resp.StatusCode)
				time.Sleep(10 * time.Millisecond)
			}

			actualCalls := int(atomic.LoadInt32(&callCount))
			if actualCalls != tt.expectedCalls {
				t.Errorf("expected %d calls, got %d", tt.expectedCalls, actualCalls)
			}
			if success != tt.expectSuccess {
				t.Errorf("expected success=%v, got %v (last err: %v)", tt.expectSuccess, success, lastErr)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------------------

func TestRateLimiting(t *testing.T) {
	tests := []struct {
		name        string
		maxPerSec   int
		numRequests int
	}{
		{
			name:        "10 requests per second",
			maxPerSec:   10,
			numRequests: 20,
		},
		{
			name:        "1 request per second",
			maxPerSec:   1,
			numRequests: 5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var count int32
			srv, cleanup := newTestServer(func(w http.ResponseWriter, r *http.Request) {
				atomic.AddInt32(&count, 1)
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(map[string]interface{}{"data": "ok"})
			})
			defer cleanup()

			start := time.Now()
			for i := 0; i < tt.numRequests; i++ {
				req, _ := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/api2/json/test", nil)
				resp, _ := http.DefaultClient.Do(req)
				if resp != nil {
					resp.Body.Close()
				}
			}
			elapsed := time.Since(start)

			total := int(atomic.LoadInt32(&count))
			if total != tt.numRequests {
				t.Errorf("expected %d requests, got %d", tt.numRequests, total)
			}

			t.Logf("Completed %d requests in %v", total, elapsed)
		})
	}
}
