// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

variable "target_node" {
  type        = string
  description = "Proxmox node name"
}

variable "type" {
  type        = string
  description = "Network type: bridge, bond, or vlan"
  default     = "bridge"

  validation {
    condition     = contains(["bridge", "bond", "vlan"], var.type)
    error_message = "Type must be one of: bridge, bond, vlan."
  }
}

variable "name" {
  type        = string
  description = "Interface name"
}

variable "comment" {
  type        = string
  description = "Interface comment"
  default     = ""
}

variable "address" {
  type        = string
  description = "IPv4 address"
  default     = ""
}

variable "cidr" {
  type        = string
  description = "IPv4 CIDR notation"
  default     = ""
}

variable "gateway" {
  type        = string
  description = "IPv4 gateway"
  default     = ""
}

variable "autostart" {
  type        = bool
  description = "Start interface on boot"
  default     = true
}

variable "enabled" {
  type        = bool
  description = "Enable interface"
  default     = true
}

variable "vlan_id" {
  type        = number
  description = "VLAN ID"
  default     = null
}

variable "vlan_interface" {
  type        = string
  description = "Parent interface for VLAN"
  default     = ""
}

variable "bridge_ports" {
  type        = string
  description = "Bridge member ports (space-separated)"
  default     = ""
}

variable "bridge_stp" {
  type        = bool
  description = "Enable STP on bridge"
  default     = false
}

variable "bridge_fd" {
  type        = number
  description = "Bridge forward delay"
  default     = 0
}

variable "bond_mode" {
  type        = string
  description = "Bond mode (balance-rr, active-backup, balance-xor, broadcast, 802.3ad, balance-tlb, balance-alb)"
  default     = "balance-rr"
}

variable "bond_policy" {
  type        = string
  description = "Bond XMIT hash policy"
  default     = ""
}

variable "bond_primary" {
  type        = string
  description = "Primary bond member"
  default     = ""
}

variable "bond_members" {
  type        = list(string)
  description = "List of bond member interfaces"
  default     = []
}

variable "bond_xmit_hash_policy" {
  type        = string
  description = "Bond transmit hash policy"
  default     = ""
}

variable "comments" {
  type        = list(string)
  description = "Additional comments"
  default     = []
}
