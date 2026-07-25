// SPDX-License-Identifier: MIT

package proxmox

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Client is an HTTP client for the Proxmox VE API.
type Client struct {
	baseURL    string
	user       string
	tokenID    string
	tokenSecret string
	httpClient *http.Client
	retryCount int
	retryDelay time.Duration
	mu         sync.Mutex
	tokens     float64
	maxTokens  float64
	refillRate float64
	lastRefill time.Time
}

// APIResponse represents a standard Proxmox API response.
type APIResponse struct {
	Data json.RawMessage `json:"data"`
	Errors map[string]interface{} `json:"errors,omitempty"`
}

// New creates a new Proxmox API client.
func New(apiURL, user, tokenID, tokenSecret string) (*Client, error) {
	if apiURL == "" {
		return nil, fmt.Errorf("API URL is required")
	}

	apiURL = strings.TrimRight(apiURL, "/")

	c := &Client{
		baseURL:    apiURL,
		user:       user,
		tokenID:    tokenID,
		tokenSecret: tokenSecret,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        20,
				IdleConnTimeout:     90 * time.Second,
				TLSHandshakeTimeout: 10 * time.Second,
			},
		},
		retryCount: 3,
		retryDelay: 1 * time.Second,
		tokens:     10,
		maxTokens:  10,
		refillRate: 10.0,
		lastRefill: time.Now(),
	}

	return c, nil
}

// SetTimeout sets the HTTP client timeout.
func (c *Client) SetTimeout(timeout time.Duration) {
	c.httpClient.Timeout = timeout
}

// refillTokens refills the token bucket for rate limiting.
func (c *Client) refillTokens() {
	now := time.Now()
	elapsed := now.Sub(c.lastRefill).Seconds()
	c.tokens += elapsed * c.refillRate
	if c.tokens > c.maxTokens {
		c.tokens = c.maxTokens
	}
	c.lastRefill = now
}

// acquireToken waits for a rate limit token.
func (c *Client) acquireToken() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.refillTokens()
	if c.tokens >= 1 {
		c.tokens--
		return
	}

	waitTime := time.Duration((1 - c.tokens) / c.refillRate * float64(time.Second))
	c.mu.Unlock()
	time.Sleep(waitTime)
	c.mu.Lock()
	c.tokens = 0
}

func (c *Client) authHeaders() map[string]string {
	headers := make(map[string]string)

	if c.tokenID != "" && c.tokenSecret != "" {
		headers["Authorization"] = fmt.Sprintf("PVEAPIToken=%s=%s", c.tokenID, c.tokenSecret)
	}

	return headers
}

func (c *Client) doRequest(ctx context.Context, method, path string, body interface{}) (json.RawMessage, error) {
	c.acquireToken()

	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshaling request body: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	u := fmt.Sprintf("%s%s", c.baseURL, path)

	var lastErr error
	for attempt := 0; attempt <= c.retryCount; attempt++ {
		if attempt > 0 {
			backoff := c.retryDelay * time.Duration(math.Pow(2, float64(attempt-1)))
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
			}
		}

		req, err := http.NewRequestWithContext(ctx, method, u, reqBody)
		if err != nil {
			return nil, fmt.Errorf("creating request: %w", err)
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json")
		for k, v := range c.authHeaders() {
			req.Header.Set(k, v)
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("executing request: %w", err)
			continue
		}

		respBody, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			lastErr = fmt.Errorf("reading response: %w", err)
			continue
		}

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			var apiResp APIResponse
			if err := json.Unmarshal(respBody, &apiResp); err != nil {
				return nil, fmt.Errorf("parsing response: %w", err)
			}
			return apiResp.Data, nil
		}

		if resp.StatusCode == http.StatusTooManyRequests {
			lastErr = fmt.Errorf("rate limited (HTTP 429)")
			continue
		}

		if resp.StatusCode >= 500 {
			lastErr = fmt.Errorf("server error (HTTP %d): %s", resp.StatusCode, string(respBody))
			continue
		}

		return nil, fmt.Errorf("API error (HTTP %d): %s", resp.StatusCode, string(respBody))
	}

	return nil, fmt.Errorf("all %d retries exhausted: %w", c.retryCount, lastErr)
}

func (c *Client) Get(ctx context.Context, path string) (json.RawMessage, error) {
	return c.doRequest(ctx, http.MethodGet, path, nil)
}

func (c *Client) Post(ctx context.Context, path string, body interface{}) (json.RawMessage, error) {
	return c.doRequest(ctx, http.MethodPost, path, body)
}

func (c *Client) Put(ctx context.Context, path string, body interface{}) (json.RawMessage, error) {
	return c.doRequest(ctx, http.MethodPut, path, body)
}

func (c *Client) Delete(ctx context.Context, path string) (json.RawMessage, error) {
	return c.doRequest(ctx, http.MethodDelete, path, nil)
}

func (c *Client) nodePath(node, suffix string) string {
	if node == "" {
		node = "localhost"
	}
	return fmt.Sprintf("/api2/json/nodes/%s%s", url.PathEscape(node), suffix)
}

func (c *Client) vmPath(node, vmtype, vmid, suffix string) string {
	return fmt.Sprintf("%s/%s/%s%s", c.nodePath(node, ""), vmtype, vmid, suffix)
}

func decodeJSON(data json.RawMessage, target interface{}) error {
	return json.Unmarshal(data, target)
}
