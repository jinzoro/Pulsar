// SPDX-License-Identifier: MIT

package kvm

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"
)

// QMPClient communicates with QEMU via the QMP protocol.
type QMPClient struct {
	socket   string
	conn     net.Conn
	reader   *bufio.Reader
	mu       sync.Mutex
	connected bool
}

// QMPResponse represents a response from the QMP monitor.
type QMPResponse struct {
	Return json.RawMessage `json:"return,omitempty"`
	Error  *QMPError       `json:"error,omitempty"`
	Event  string          `json:"event,omitempty"`
	Data   json.RawMessage `json:"data,omitempty"`
}

// QMPError represents a QMP error.
type QMPError struct {
	Class string `json:"class"`
	Desc  string `json:"desc"`
}

// QMPStatus represents VM status from QMP.
type QMPStatus struct {
	Running    bool   `json:"running"`
	Singlestep bool   `json:"singlestep,omitempty"`
	Status     string `json:"status"`
}

// NewQMPClient creates a new QMP client.
func NewQMPClient(socket string) *QMPClient {
	return &QMPClient{
		socket: socket,
	}
}

// Connect establishes a connection to the QMP monitor.
func (q *QMPClient) Connect() error {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.connected {
		return nil
	}

	conn, err := net.DialTimeout("unix", q.socket, 5*time.Second)
	if err != nil {
		return fmt.Errorf("connecting to QMP socket %s: %w", q.socket, err)
	}

	q.conn = conn
	q.reader = bufio.NewReader(conn)
	q.connected = true

	// Read the greeting
	var greeting map[string]interface{}
	if err := q.readJSON(&greeting); err != nil {
		q.conn.Close()
		q.connected = false
		return fmt.Errorf("reading QMP greeting: %w", err)
	}

	// Send capabilities negotiation
	if err := q.sendCommand("qmp_capabilities", nil); err != nil {
		q.conn.Close()
		q.connected = false
		return fmt.Errorf("negotiating QMP capabilities: %w", err)
	}

	return nil
}

// Close closes the QMP connection.
func (q *QMPClient) Close() {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.conn != nil {
		q.conn.Close()
		q.connected = false
	}
}

// Execute sends a QMP command and returns the result.
func (q *QMPClient) Execute(command string, arguments interface{}) (json.RawMessage, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if !q.connected {
		return nil, fmt.Errorf("not connected to QMP")
	}

	if err := q.sendCommand(command, arguments); err != nil {
		return nil, err
	}

	var response QMPResponse
	if err := q.readJSON(&response); err != nil {
		return nil, fmt.Errorf("reading QMP response: %w", err)
	}

	if response.Error != nil {
		return nil, fmt.Errorf("QMP error: %s: %s", response.Error.Class, response.Error.Desc)
	}

	return response.Return, nil
}

// QueryStatus returns the current VM status.
func (q *QMPClient) QueryStatus() (*QMPStatus, error) {
	data, err := q.Execute("query-status", nil)
	if err != nil {
		return nil, fmt.Errorf("querying status: %w", err)
	}

	var status QMPStatus
	if err := json.Unmarshal(data, &status); err != nil {
		return nil, fmt.Errorf("parsing status: %w", err)
	}
	return &status, nil
}

// Stop stops the VM.
func (q *QMPClient) Stop() error {
	_, err := q.Execute("stop", nil)
	return err
}

// Cont resumes the VM.
func (q *QMPClient) Cont() error {
	_, err := q.Execute("cont", nil)
	return err
}

// Quit requests the VM to quit.
func (q *QMPClient) Quit() error {
	_, err := q.Execute("quit", nil)
	return err
}

// Reset performs a reset of the VM.
func (q *QMPClient) Reset() error {
	_, err := q.Execute("system_reset", nil)
	return err
}

// PowerDown performs a power down of the VM.
func (q *QMPClient) PowerDown() error {
	_, err := q.Execute("system_powerdown", nil)
	return err
}

// Screendump takes a screenshot of the VM display.
func (q *QMPClient) Screendump(filename string) error {
	args := map[string]string{
		"filename": filename,
	}
	_, err := q.Execute("screendump", args)
	return err
}

// SendKey sends a key press to the VM.
func (q *QMPClient) SendKey(keys string, holdTime int) error {
	args := map[string]interface{}{
		"keys":     keys,
		"hold-time": holdTime,
	}
	_, err := q.Execute("send-key", args)
	return err
}

// QueryBlock returns block device information.
func (q *QMPClient) QueryBlock() (json.RawMessage, error) {
	return q.Execute("query-block", nil)
}

// QueryCPUs returns CPU information.
func (q *QMPClient) QueryCPUs() (json.RawMessage, error) {
	return q.Execute("query-cpus-fast", nil)
}

// QueryMemory returns memory information.
func (q *QMPClient) QueryMemory() (json.RawMessage, error) {
	return q.Execute("query-memory-size-summary", nil)
}

// QueryNetwork returns network information.
func (q *QMPClient) QueryNetwork() (json.RawMessage, error) {
	return q.Execute("query-network", nil)
}

// QueryMachines returns available machine types.
func (q *QMPClient) QueryMachines() (json.RawMessage, error) {
	return q.Execute("query-machines", nil)
}

// QueryVersion returns QEMU version information.
func (q *QMPClient) QueryVersion() (json.RawMessage, error) {
	return q.Execute("query-version", nil)
}

// SetLink sets the link state of a network device.
func (q *QMPClient) SetLink(name string, up bool) error {
	args := map[string]interface{}{
		"name": name,
		"up":   up,
	}
	_, err := q.Execute("set_link", args)
	return err
}

// ChangeDriveSize changes the size of a drive.
func (q *QMPClient) ChangeDriveSize(device, size string) error {
	args := map[string]interface{}{
		"device": device,
		"size":   size,
	}
	_, err := q.Execute("block_resize", args)
	return err
}

// SnapshotCreate creates a live snapshot.
func (q *QMPClient) SnapshotCreate(device, snapshotFile, format string) error {
	args := map[string]interface{}{
		"device":     device,
		"snapshot-file": snapshotFile,
		"format":     format,
	}
	_, err := q.Execute("blockdev-snapshot-sync", args)
	return err
}

// SnapshotDelete deletes a snapshot.
func (q *QMPClient) SnapshotDelete(device, snapshotFile string) error {
	args := map[string]interface{}{
		"device":        device,
		"statefile":     snapshotFile,
	}
	_, err := q.Execute("blockdev-snapshot-delete-sync-id", args)
	return err
}

func (q *QMPClient) sendCommand(command string, arguments interface{}) error {
	cmd := map[string]interface{}{
		"execute": command,
	}
	if arguments != nil {
		cmd["arguments"] = arguments
	}

	data, err := json.Marshal(cmd)
	if err != nil {
		return fmt.Errorf("marshaling command: %w", err)
	}

	data = append(data, '\n')
	_, err = q.conn.Write(data)
	if err != nil {
		return fmt.Errorf("writing command: %w", err)
	}

	return nil
}

func (q *QMPClient) readJSON(target interface{}) error {
	line, err := q.reader.ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("reading line: %w", err)
	}

	line = []byte(strings.TrimSpace(string(line)))
	if len(line) == 0 {
		return fmt.Errorf("empty response")
	}

	return json.Unmarshal(line, target)
}
