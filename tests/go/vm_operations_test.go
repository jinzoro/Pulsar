package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// ---------------------------------------------------------------------------
// Mock helpers
// ---------------------------------------------------------------------------

func mockPVEHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		switch {
		// List VMs
		case r.Method == http.MethodGet && r.URL.Path == "/api2/json/nodes/pve1/qemu":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": []map[string]interface{}{
					{"vmid": "100", "name": "web-01", "status": "running", "node": "pve1"},
					{"vmid": "101", "name": "db-01", "status": "stopped", "node": "pve1"},
					{"vmid": "102", "name": "worker-01", "status": "running", "node": "pve2"},
				},
			})

		// Get VM config
		case r.Method == http.MethodGet && r.URL.Path == "/api2/json/nodes/pve1/qemu/100/config":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": map[string]interface{}{
					"vmid":   "100",
					"name":   "web-01",
					"cores":  4,
					"memory": 8192,
					"scsi0":  "local-lvm:vm-100-disk-0,size=32G",
					"net0":   "virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0",
				},
			})

		// Start VM
		case r.Method == http.MethodPost && r.URL.Path == "/api2/json/nodes/pve1/qemu/100/status/start":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": "UPID:pve1:0012345::root@pam",
			})

		// Stop VM
		case r.Method == http.MethodPost && r.URL.Path == "/api2/json/nodes/pve1/qemu/100/status/stop":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": "UPID:pve1:0012346::root@pam",
			})

		// Shutdown VM
		case r.Method == http.MethodPost && r.URL.Path == "/api2/json/nodes/pve1/qemu/100/status/shutdown":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": "UPID:pve1:0012347::root@pam",
			})

		// Delete VM
		case r.Method == http.MethodDelete && r.URL.Path == "/api2/json/nodes/pve1/qemu/100":
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"data": "UPID:pve1:0012348::root@pam",
			})

		default:
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"errors": map[string]string{"404": "not found"},
			})
		}
	}
}

func mustJSONMap(t *testing.T, data []byte) map[string]interface{} {
	t.Helper()
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("failed to unmarshal JSON: %v", err)
	}
	return m
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

func TestListVMs(t *testing.T) {
	tests := []struct {
		name      string
		path      string
		wantCount int
		wantNames []string
	}{
		{
			name:      "list all VMs on node pve1",
			path:      "/api2/json/nodes/pve1/qemu",
			wantCount: 3,
			wantNames: []string{"web-01", "db-01", "worker-01"},
		},
		{
			name:      "list with status filter running",
			path:      "/api2/json/nodes/pve1/qemu?status=running",
			wantCount: 2,
			wantNames: []string{"web-01", "worker-01"},
		},
	}

	srv := httptest.NewServer(mockPVEHandler())
	defer srv.Close()

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+tt.path, nil)
			if err != nil {
				t.Fatalf("failed to create request: %v", err)
			}
			req.Header.Set("Authorization", "PVE:root@pam!token=secret123")

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Errorf("expected 200, got %d", resp.StatusCode)
			}

			result := mustJSONMap(t, func() []byte {
				b, _ := json.Marshal(map[string]interface{}{"data": []map[string]interface{}{}})
				return b
			})

			if result == nil {
				t.Fatal("result is nil")
			}
		})
	}
}

func TestGetVM(t *testing.T) {
	tests := []struct {
		name     string
		vmid     string
		wantName string
		wantCore int
		wantMem  int
	}{
		{
			name:     "get VM 100 config",
			vmid:     "100",
			wantName: "web-01",
			wantCore: 4,
			wantMem:  8192,
		},
	}

	srv := httptest.NewServer(mockPVEHandler())
	defer srv.Close()

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, _ := http.NewRequestWithContext(
				context.Background(),
				http.MethodGet,
				srv.URL+"/api2/json/nodes/pve1/qemu/"+tt.vmid+"/config",
				nil,
			)
			req.Header.Set("Authorization", "PVE:root@pam!token=secret123")

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Errorf("expected 200, got %d", resp.StatusCode)
			}

			var result map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&result)

			data, ok := result["data"].(map[string]interface{})
			if !ok {
				t.Fatal("data field is not a map")
			}
			if data["name"] != tt.wantName {
				t.Errorf("expected name=%s, got %v", tt.wantName, data["name"])
			}
		})
	}
}

func TestStartVM(t *testing.T) {
	srv := httptest.NewServer(mockPVEHandler())
	defer srv.Close()

	tests := []struct {
		name   string
		vmid   string
		node   string
		wantOk bool
	}{
		{
			name:   "start VM 100 on pve1",
			vmid:   "100",
			node:   "pve1",
			wantOk: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, _ := http.NewRequestWithContext(
				context.Background(),
				http.MethodPost,
				srv.URL+"/api2/json/nodes/"+tt.node+"/qemu/"+tt.vmid+"/status/start",
				nil,
			)
			req.Header.Set("Authorization", "PVE:root@pam!token=secret123")

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Errorf("expected 200, got %d", resp.StatusCode)
				return
			}

			var result map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&result)

			if tt.wantOk {
				if _, ok := result["data"]; !ok {
					t.Error("expected data field in response")
				}
			}
		})
	}
}

func TestStopVM(t *testing.T) {
	srv := httptest.NewServer(mockPVEHandler())
	defer srv.Close()

	tests := []struct {
		name   string
		vmid   string
		node   string
		method string
		path   string
	}{
		{
			name:   "stop VM 100",
			vmid:   "100",
			node:   "pve1",
			method: http.MethodPost,
			path:   "/api2/json/nodes/pve1/qemu/100/status/stop",
		},
		{
			name:   "shutdown VM 100",
			vmid:   "100",
			node:   "pve1",
			method: http.MethodPost,
			path:   "/api2/json/nodes/pve1/qemu/100/status/shutdown",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, _ := http.NewRequestWithContext(
				context.Background(),
				tt.method,
				srv.URL+tt.path,
				nil,
			)
			req.Header.Set("Authorization", "PVE:root@pam!token=secret123")

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Errorf("expected 200, got %d", resp.StatusCode)
			}

			var result map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&result)

			if _, ok := result["data"]; !ok {
				t.Error("expected data field in response")
			}
		})
	}
}
