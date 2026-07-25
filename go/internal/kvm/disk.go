// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// DiskInfo holds information about a disk image.
type DiskInfo struct {
	Format      string `json:"format"`
	VirtualSize string `json:"virtual-size"`
	FileSize    string `json:"file-size"`
	Filename    string `json:"filename"`
	ClusterSize string `json:"cluster-size,omitempty"`
	DirtyFlag   bool   `json:"dirty-flag,omitempty"`
}

// CreateDisk creates a new disk image.
func CreateDisk(path, size, format string) error {
	if format == "" {
		format = "qcow2"
	}

	cmd := exec.Command("qemu-img", "create", "-f", format, path, size)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("creating disk %s: %w: %s", path, err, stderr.String())
	}
	return nil
}

// ResizeDisk resizes a disk image.
func ResizeDisk(path, size string) error {
	cmd := exec.Command("qemu-img", "resize", path, size)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("resizing disk %s: %w: %s", path, err, stderr.String())
	}
	return nil
}

// ConvertDisk converts a disk image from one format to another.
func ConvertDisk(source, dest, format string) error {
	if format == "" {
		format = "qcow2"
	}

	cmd := exec.Command("qemu-img", "convert", "-f", detectFormat(source), "-O", format, source, dest)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("converting disk %s to %s: %w: %s", source, dest, err, stderr.String())
	}
	return nil
}

// DiskInfo returns information about a disk image.
func DiskInfo(path string) (*DiskInfo, error) {
	cmd := exec.Command("qemu-img", "info", "--output=json", path)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting disk info for %s: %w: %s", path, err, stderr.String())
	}

	var info DiskInfo
	if err := json.Unmarshal(stdout.Bytes(), &info); err != nil {
		return nil, fmt.Errorf("parsing disk info: %w", err)
	}
	return &info, nil
}

// SnapshotDisk creates a snapshot of a disk image.
func SnapshotDisk(path, snapshotFile string) error {
	cmd := exec.Command("qemu-img", "snapshot", "-c", snapshotFile, path)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("snapshotting disk %s: %w: %s", path, err, stderr.String())
	}
	return nil
}

// RevertDiskSnapshot reverts a disk to a snapshot.
func RevertDiskSnapshot(path, snapshotFile string) error {
	cmd := exec.Command("qemu-img", "snapshot", "-a", snapshotFile, path)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("reverting disk %s to snapshot %s: %w: %s", path, snapshotFile, err, stderr.String())
	}
	return nil
}

// DeleteDiskSnapshot deletes a snapshot from a disk image.
func DeleteDiskSnapshot(path, snapshotFile string) error {
	cmd := exec.Command("qemu-img", "snapshot", "-d", snapshotFile, path)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("deleting snapshot %s from disk %s: %w: %s", snapshotFile, path, err, stderr.String())
	}
	return nil
}

// ListDiskSnapshots lists all snapshots in a disk image.
func ListDiskSnapshots(path string) ([]map[string]interface{}, error) {
	cmd := exec.Command("qemu-img", "snapshot", "-l", "--output=json", path)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing snapshots for %s: %w: %s", path, err, stderr.String())
	}

	var snapshots []map[string]interface{}
	if err := json.Unmarshal(stdout.Bytes(), &snapshots); err != nil {
		return nil, fmt.Errorf("parsing snapshots: %w", err)
	}
	return snapshots, nil
}

// CheckDisk checks the integrity of a disk image.
func CheckDisk(path string) error {
	cmd := exec.Command("qemu-img", "check", path)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("checking disk %s: %w: %s", path, err, stderr.String())
	}
	return nil
}

// RebaseDisk rebases a disk image to a new backing file.
func RebaseDisk(path, backingFile string) error {
	args := []string{"rebase"}
	if backingFile == "" {
		args = append(args, "-u")
	} else {
		args = append(args, "-b", backingFile)
	}
	args = append(args, path)

	cmd := exec.Command("qemu-img", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("rebasing disk %s: %w: %s", path, err, stderr.String())
	}
	return nil
}

func detectFormat(path string) string {
	cmd := exec.Command("qemu-img", "info", "--output=json", path)
	output, err := cmd.Output()
	if err != nil {
		return "raw"
	}

	var info struct {
		Format string `json:"format"`
	}
	if err := json.Unmarshal(output, &info); err != nil {
		return "raw"
	}
	return info.Format
}

// BackupDisk creates a full backup of a disk image.
func BackupDisk(source, dest string) error {
	cmd := exec.Command("qemu-img", "convert", "-f", detectFormat(source), "-O", "qcow2", source, dest)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("backing up disk %s to %s: %w: %s", source, dest, err, stderr.String())
	}
	return nil
}

// CompareDisks compares two disk images.
func CompareDisks(source1, source2 string) error {
	cmd := exec.Command("qemu-img", "compare", source1, source2)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if strings.Contains(stderr.String(), "Images are identical") {
			return nil
		}
		return fmt.Errorf("comparing disks: %w: %s", err, stderr.String())
	}
	return nil
}
