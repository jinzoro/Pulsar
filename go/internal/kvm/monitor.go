// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// DomainStats holds statistics for a domain.
type DomainStats struct {
	Name      string           `json:"name"`
	State     string           `json:"state"`
	CPUTime   int64            `json:"cpu_time"`
	CPUs      int              `json:"cpus"`
	VCPU      []VCPUStats      `json:"vcpu,omitempty"`
	Block     []BlockStats     `json:"block,omitempty"`
	Net       []InterfaceStats `json:"net,omitempty"`
	Memory    MemoryStats      `json:"memory,omitempty"`
}

// VCPUStats holds per-vCPU statistics.
type VCPUStats struct {
	ID     int   `json:"id"`
	State  int   `json:"state,omitempty"`
	Time   int64 `json:"time"`
	Delay  int64 `json:"delay,omitempty"`
}

// BlockStats holds block device statistics.
type BlockStats struct {
	Name         string `json:"name"`
	Path         string `json:"path,omitempty"`
	RdBytes      int64  `json:"rd_bytes"`
	WrBytes      int64  `json:"wr_bytes"`
	RdOps        int64  `json:"rd_ops"`
	WrOps        int64  `json:"wr_ops"`
	FlushOps     int64  `json:"flush_ops,omitempty"`
	WrTotalTimes int64  `json:"wr_total_times,omitempty"`
	RdTotalTimes int64  `json:"rd_total_times,omitempty"`
}

// InterfaceStats holds network interface statistics.
type InterfaceStats struct {
	Name   string `json:"name"`
	RxBytes   int64 `json:"rx_bytes"`
	RxPackets int64 `json:"rx_packets"`
	RxErrs    int64 `json:"rx_errs"`
	RxDrop    int64 `json:"rx_drop"`
	TxBytes   int64 `json:"tx_bytes"`
	TxPackets int64 `json:"tx_packets"`
	TxErrs    int64 `json:"tx_errs"`
	TxDrop    int64 `json:"tx_drop"`
}

// MemoryStats holds memory statistics.
type MemoryStats struct {
	Actual int64            `json:"actual,omitempty"`
	Swap   int64            `json:"swap,omitempty"`
	Items  map[string]int64 `json:"items,omitempty"`
}

// GetDomainStats returns statistics for a specific domain.
func GetDomainStats(name string) (*DomainStats, error) {
	cmd := exec.Command("virsh", "domstats", name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting domain stats for %s: %w: %s", name, err, stderr.String())
	}

	return parseDomainStats(stdout.String(), name), nil
}

// GetAllDomainStats returns statistics for all running domains.
func GetAllDomainStats() ([]DomainStats, error) {
	cmd := exec.Command("virsh", "domstats", "--list-running")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting all domain stats: %w: %s", err, stderr.String())
	}

	var stats []DomainStats
	blocks := strings.Split(stdout.String(), "\nDomain: ")
	for i, block := range blocks {
		name := ""
		if i == 0 {
			if strings.HasPrefix(block, "Domain: ") {
				block = strings.TrimPrefix(block, "Domain: ")
			}
		}
		lines := strings.SplitN(block, "\n", 2)
		if len(lines) > 0 {
			name = strings.TrimSpace(lines[0])
		}
		stats = append(stats, *parseDomainStats(block, name))
	}

	return stats, nil
}

// GetMemoryStats returns memory statistics for a domain.
func GetMemoryStats(name string) (*MemoryStats, error) {
	cmd := exec.Command("virsh", "dommemstat", name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting memory stats for %s: %w", name, err)
	}

	mem := &MemoryStats{
		Items: make(map[string]int64),
	}

	lines := strings.Split(stdout.String(), "\n")
	for _, line := range lines {
		parts := strings.Fields(strings.TrimSpace(line))
		if len(parts) == 2 {
			var val int64
			fmt.Sscanf(parts[1], "%d", &val)
			mem.Items[parts[0]] = val
			if parts[0] == "actual" {
				mem.Actual = val
			}
			if parts[0] == "swap" {
				mem.Swap = val
			}
		}
	}

	return mem, nil
}

// GetBlockStats returns block device statistics for a domain.
func GetBlockStats(name string) ([]BlockStats, error) {
	cmd := exec.Command("virsh", "domstats", name, "--block")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting block stats for %s: %w: %s", name, err, stderr.String())
	}

	var stats []BlockStats
	lines := strings.Split(stdout.String(), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "block.") && strings.Contains(line, ".name=") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				stats = append(stats, BlockStats{
					Name: strings.Trim(parts[1], "\""),
				})
			}
		}
	}

	return stats, nil
}

// GetInterfaceStats returns network interface statistics for a domain.
func GetInterfaceStats(name string) ([]InterfaceStats, error) {
	cmd := exec.Command("virsh", "domifaddr", name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting interface stats for %s: %w: %s", name, err, stderr.String())
	}

	var stats []InterfaceStats
	lines := strings.Split(stdout.String(), "\n")
	for _, line := range lines {
		fields := strings.Fields(strings.TrimSpace(line))
		if len(fields) >= 1 && !strings.HasPrefix(fields[0], "Name") {
			stats = append(stats, InterfaceStats{
				Name: fields[0],
			})
		}
	}

	return stats, nil
}

func parseDomainStats(output, name string) *DomainStats {
	stats := &DomainStats{
		Name: name,
	}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch {
		case key == "state":
			stats.State = value
		case key == "cpu.time":
			fmt.Sscanf(value, "%d", &stats.CPUTime)
		case key == "cpu.count":
			var cpus int
			fmt.Sscanf(value, "%d", &cpus)
			stats.CPUs = cpus
		}
	}

	return stats
}

// GetXMLStats returns raw XML statistics for a domain.
func GetXMLStats(name string) (string, error) {
	cmd := exec.Command("virsh", "domstats", name, "--raw")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("getting raw stats for %s: %w", name, err)
	}

	return stdout.String(), nil
}

// GetJSONStats returns JSON-formatted statistics for a domain.
func GetJSONStats(name string) (json.RawMessage, error) {
	cmd := exec.Command("virsh", "domstats", name, "--raw")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("getting JSON stats for %s: %w", name, err)
	}

	var result json.RawMessage
	if err := json.Unmarshal(output, &result); err != nil {
		return output, nil
	}

	return result, nil
}

// GetNetworkStats returns network statistics for a domain using virsh domstats.
func GetNetworkStats(name string) ([]InterfaceStats, error) {
	domain, err := GetDomainStats(name)
	if err != nil {
		return nil, err
	}
	return domain.Net, nil
}
