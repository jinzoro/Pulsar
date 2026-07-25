// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

resource "proxmox_virtual_environment_network_linux_bridge" "this" {
  count = var.type == "bridge" ? 1 : 0

  node_name = var.target_node
  name      = var.name
  comment   = var.comment

  address = var.address != "" ? var.address : null
  cidr    = var.cidr != "" ? var.cidr : null
  gateway = var.gateway != "" ? var.gateway : null

  autostart = var.autostart
  enabled   = var.enabled

  dynamic "vlan" {
    for_each = var.vlan_id != null ? [var.vlan_id] : []
    content {
      vlan_id = vlan.value
    }
  }

  bridge_ports = var.bridge_ports != "" ? var.bridge_ports : null
  bridge_stp   = var.bridge_stp
  bridge_fd    = var.bridge_fd

  comments   = var.comments
}

resource "proxmox_virtual_environment_network_linux_bond" "this" {
  count = var.type == "bond" ? 1 : 0

  node_name = var.target_node
  name      = var.name
  comment   = var.comment

  address = var.address != "" ? var.address : null
  cidr    = var.cidr != "" ? var.cidr : null
  gateway = var.gateway != "" ? var.gateway : null

  autostart = var.autostart
  enabled   = var.enabled

  bond_mode    = var.bond_mode
  bond_policy  = var.bond_policy
  bond_primary = var.bond_primary
  bond_members = var.bond_members
  bond_xmit_hash_policy = var.bond_xmit_hash_policy

  comments = var.comments
}

resource "proxmox_virtual_environment_network_linux_vlan" "this" {
  count = var.type == "vlan" ? 1 : 0

  node_name = var.target_node
  name      = var.name
  comment   = var.comment

  address = var.address != "" ? var.address : null
  cidr    = var.cidr != "" ? var.cidr : null
  gateway = var.gateway != "" ? var.gateway : null

  autostart = var.autostart
  enabled   = var.enabled

  vlan_id    = var.vlan_id
  interface  = var.vlan_interface

  comments = var.comments
}
