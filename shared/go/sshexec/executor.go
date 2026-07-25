// =============================================================================
// executor.go — SSH command execution for Pulsar
// =============================================================================
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Pulsar contributors
// =============================================================================
// Provides the sshexec package for running commands on local and remote hosts
// via os/exec (local) and SSH with known_hosts verification.
// =============================================================================

package sshexec

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// Result holds the output of a single command execution.
// ---------------------------------------------------------------------------

// Result contains the stdout, stderr, and error from a command execution.
type Result struct {
	Stdout string
	Stderr string
	Error  error
}

// Success returns true if the command exited with a zero status code.
func (r Result) Success() bool {
	return r.Error == nil
}

// ---------------------------------------------------------------------------
// Executor drives command execution on local and remote hosts.
// ---------------------------------------------------------------------------

// Executor executes shell commands on a target host via SSH or locally.
type Executor struct {
	Host    string
	User    string
	KeyPath string
	Timeout time.Duration
	Retries int
}

// New creates a new Executor targeting the given host with the specified user.
func New(host, user string) *Executor {
	return &Executor{
		Host:    host,
		User:    user,
		KeyPath: "",
		Timeout: 30 * time.Second,
		Retries: 3,
	}
}

// WithKeyPath sets the SSH private key path and returns the executor for
// method chaining.
func (e *Executor) WithKeyPath(path string) *Executor {
	e.KeyPath = path
	return e
}

// WithTimeout sets the command execution timeout and returns the executor
// for method chaining.
func (e *Executor) WithTimeout(timeout time.Duration) *Executor {
	e.Timeout = timeout
	return e
}

// WithRetries sets the number of retry attempts and returns the executor for
// method chaining.
func (e *Executor) WithRetries(n int) *Executor {
	e.Retries = n
	return e
}

// ---------------------------------------------------------------------------
// Local execution
// ---------------------------------------------------------------------------

// ExecuteLocal runs a command on the local machine via os/exec and returns
// stdout, stderr, and any error.
func ExecuteLocal(command string) (string, string, error) {
	cmd := exec.Command("bash", "-c", command)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// ---------------------------------------------------------------------------
// Remote execution via SSH
// ---------------------------------------------------------------------------

// sshArgs builds the SSH command vector for the target host.
func (e *Executor) sshArgs(command string) []string {
	args := []string{
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=10",
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", fmt.Sprintf("ServerAliveInterval=%d", max(e.Timeout.Seconds()/5, 5)),
		"-o", "ServerAliveCountMax=3",
	}
	if e.KeyPath != "" {
		args = append(args, "-i", e.KeyPath)
	}
	args = append(args, fmt.Sprintf("%s@%s", e.User, e.Host), command)
	return args
}

// Execute runs a command on the remote host via SSH, retrying up to
// e.Retries times on failure.  Returns stdout, stderr, and error.
func (e *Executor) Execute(command string) (string, string, error) {
	var lastErr error

	for attempt := 1; attempt <= e.Retries; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), e.Timeout)
		defer cancel()

		args := e.sshArgs(command)
		cmd := exec.CommandContext(ctx, "ssh", args...)

		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		err := cmd.Run()
		if err == nil {
			return stdout.String(), stderr.String(), nil
		}

		lastErr = fmt.Errorf(
			"ssh attempt %d/%d failed for %s@%s: %w\nstderr: %s",
			attempt, e.Retries, e.User, e.Host, err,
			strings.TrimSpace(stderr.String()),
		)

		// Don't sleep after the last attempt
		if attempt < e.Retries {
			backoff := time.Duration(1<<uint(attempt)) * time.Second
			if backoff > 10*time.Second {
				backoff = 10 * time.Second
			}
			time.Sleep(backoff)
		}
	}

	return "", "", lastErr
}

// ExecuteWithStdin runs a command on the remote host via SSH, sending
// input on stdin.  Returns stdout, stderr, and error.
func (e *Executor) ExecuteWithStdin(command string, input string) (string, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), e.Timeout)
	defer cancel()

	args := e.sshArgs(command)
	cmd := exec.CommandContext(ctx, "ssh", args...)

	cmd.Stdin = strings.NewReader(input)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// ---------------------------------------------------------------------------
// Parallel execution
// ---------------------------------------------------------------------------

// ExecuteParallel runs the same command on multiple remote hosts
// concurrently and returns a map of host -> Result.
func (e *Executor) ExecuteParallel(command string, hosts []string) map[string]Result {
	results := make(map[string]Result, len(hosts))
	var mu sync.WaitGroup
	var muResults sync.Mutex

	for _, host := range hosts {
		mu.Add(1)
		go func(h string) {
			defer mu.Done()

			executor := New(h, e.User).
				WithKeyPath(e.KeyPath).
				WithTimeout(e.Timeout).
				WithRetries(e.Retries)

			stdout, stderr, err := executor.Execute(command)

			muResults.Lock()
			results[h] = Result{
				Stdout: stdout,
				Stderr: stderr,
				Error:  err,
			}
			muResults.Unlock()
		}(host)
	}

	mu.Wait()
	return results
}

// ---------------------------------------------------------------------------
// Script execution
// ---------------------------------------------------------------------------

// ExecuteScript reads a local script file and executes it on the remote
// host via SSH.
func (e *Executor) ExecuteScript(scriptPath string, args ...string) (string, string, error) {
	// Read the local script file
	readCmd := exec.Command("cat", scriptPath)
	var scriptContent bytes.Buffer
	readCmd.Stdout = &scriptContent
	if err := readCmd.Run(); err != nil {
		return "", "", fmt.Errorf("failed to read script %s: %w", scriptPath, err)
	}

	// Build the remote bash command
	remoteCmd := "bash -s"
	if len(args) > 0 {
		// Shell-escape each argument
		escaped := make([]string, len(args))
		for i, a := range args {
			escaped[i] = fmt.Sprintf("%q", a)
		}
		remoteCmd += " " + strings.Join(escaped, " ")
	}

	return e.ExecuteWithStdin(remoteCmd, scriptContent.String())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// max returns the larger of two integers.
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
