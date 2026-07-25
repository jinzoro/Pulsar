// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"fmt"
	"net/url"
)

// User represents a Proxmox user.
type User struct {
	UserID  string `json:"userid"`
	Email   string `json:"email,omitempty"`
	Comment string `json:"comment,omitempty"`
	Enable  bool   `json:"enable"`
	Expire  int64  `json:"expire,omitempty"`
	Groups  string `json:"groups,omitempty"`
	Keys    string `keys:"keys,omitempty"`
	Realm   string `json:"realm,omitempty"`
}

// UserCreateRequest represents a request to create a user.
type UserCreateRequest struct {
	UserID  string `json:"userid"`
	Email   string `json:"email,omitempty"`
	Comment string `json:"comment,omitempty"`
	Enable  int    `json:"enable,omitempty"`
	Expire  int64  `json:"expire,omitempty"`
	Groups  string `json:"groups,omitempty"`
	Password string `json:"password,omitempty"`
}

// Token represents an API token.
type Token struct {
	TokenID string `json:"tokenid"`
	Comment string `json:"comment,omitempty"`
	Expire  int64  `json:"expire,omitempty"`
	Privsep int    `json:"privsep,omitempty"`
}

// ACL represents an ACL entry.
type ACL struct {
	Path     string `json:"path"`
	Realm    string `json:"realm"`
	UserID   string `json:"userid,omitempty"`
	Group    string `json:"group,omitempty"`
	RoleID   string `json:"roleid"`
}

// ListUsers returns all users.
func (c *Client) ListUsers() ([]User, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/access/users")
	if err != nil {
		return nil, fmt.Errorf("listing users: %w", err)
	}

	var users []User
	if err := decodeJSON(data, &users); err != nil {
		return nil, fmt.Errorf("decoding users: %w", err)
	}
	return users, nil
}

// CreateUser creates a new user.
func (c *Client) CreateUser(req UserCreateRequest) error {
	ctx := context.Background()
	_, err := c.Post(ctx, "/api2/json/access/users", req)
	if err != nil {
		return fmt.Errorf("creating user %s: %w", req.UserID, err)
	}
	return nil
}

// DeleteUser deletes a user.
func (c *Client) DeleteUser(userid string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/access/users/%s", url.PathEscape(userid))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting user %s: %w", userid, err)
	}
	return nil
}

// SetUserPassword sets a user's password.
func (c *Client) SetUserPassword(userid, password string) error {
	ctx := context.Background()
	body := map[string]string{
		"password": password,
	}
	path := fmt.Sprintf("/api2/json/access/users/%s/password", url.PathEscape(userid))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("setting password for user %s: %w", userid, err)
	}
	return nil
}

// EnableUser enables a user account.
func (c *Client) EnableUser(userid string) error {
	return c.setUserEnabled(userid, 1)
}

// DisableUser disables a user account.
func (c *Client) DisableUser(userid string) error {
	return c.setUserEnabled(userid, 0)
}

func (c *Client) setUserEnabled(userid string, enable int) error {
	ctx := context.Background()
	body := map[string]int{
		"enable": enable,
	}
	path := fmt.Sprintf("/api2/json/access/users/%s", url.PathEscape(userid))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("updating user %s enable state: %w", userid, err)
	}
	return nil
}

// ListTokens returns API tokens for a user.
func (c *Client) ListTokens(userid string) ([]Token, error) {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/access/users/%s/token", url.PathEscape(userid))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing tokens for user %s: %w", userid, err)
	}

	var tokens []Token
	if err := decodeJSON(data, &tokens); err != nil {
		return nil, fmt.Errorf("decoding tokens: %w", err)
	}
	return tokens, nil
}

// CreateToken creates a new API token for a user.
func (c *Client) CreateToken(userid, tokenid, comment string, privsep bool) (*Token, error) {
	ctx := context.Background()
	privsepInt := 0
	if privsep {
		privsepInt = 1
	}
	body := map[string]interface{}{
		"tokenid":  tokenid,
		"comment":  comment,
		"privsep":  privsepInt,
	}
	path := fmt.Sprintf("/api2/json/access/users/%s/token", url.PathEscape(userid))
	data, err := c.Post(ctx, path, body)
	if err != nil {
		return nil, fmt.Errorf("creating token for user %s: %w", userid, err)
	}

	var token Token
	if err := decodeJSON(data, &token); err != nil {
		return nil, fmt.Errorf("decoding token: %w", err)
	}
	return &token, nil
}

// DeleteToken deletes an API token.
func (c *Client) DeleteToken(userid, tokenid string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/access/users/%s/token/%s",
		url.PathEscape(userid), url.PathEscape(tokenid))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting token %s for user %s: %w", tokenid, userid, err)
	}
	return nil
}

// ListACL returns all ACL entries.
func (c *Client) ListACL() ([]ACL, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/access/acl")
	if err != nil {
		return nil, fmt.Errorf("listing ACL: %w", err)
	}

	var acls []ACL
	if err := decodeJSON(data, &acls); err != nil {
		return nil, fmt.Errorf("decoding ACL: %w", err)
	}
	return acls, nil
}

// AddACL adds an ACL entry.
func (c *Client) AddACL(path, realm, userid, group, roleid string) error {
	ctx := context.Background()
	body := map[string]string{
		"path":   path,
		"realm":  realm,
		"userid": userid,
		"group":  group,
		"roleid": roleid,
	}
	_, err := c.Post(ctx, "/api2/json/access/acl", body)
	if err != nil {
		return fmt.Errorf("adding ACL entry: %w", err)
	}
	return nil
}

// DeleteACL removes an ACL entry.
func (c *Client) DeleteACL(path, realm, userid, group, roleid string) error {
	ctx := context.Background()
	params := url.Values{}
	params.Set("path", path)
	params.Set("realm", realm)
	if userid != "" {
		params.Set("userid", userid)
	}
	if group != "" {
		params.Set("group", group)
	}
	params.Set("roleid", roleid)

	pathURL := fmt.Sprintf("/api2/json/access/acl?%s", params.Encode())
	_, err := c.Delete(ctx, pathURL)
	if err != nil {
		return fmt.Errorf("deleting ACL entry: %w", err)
	}
	return nil
}

// ListGroups returns all access groups.
func (c *Client) ListGroups() ([]map[string]interface{}, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/access/groups")
	if err != nil {
		return nil, fmt.Errorf("listing groups: %w", err)
	}

	var groups []map[string]interface{}
	if err := decodeJSON(data, &groups); err != nil {
		return nil, fmt.Errorf("decoding groups: %w", err)
	}
	return groups, nil
}

// ListRealms returns all authentication realms.
func (c *Client) ListRealms() ([]map[string]interface{}, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/access/domains")
	if err != nil {
		return nil, fmt.Errorf("listing realms: %w", err)
	}

	var realms []map[string]interface{}
	if err := decodeJSON(data, &realms); err != nil {
		return nil, fmt.Errorf("decoding realms: %w", err)
	}
	return realms, nil
}
