// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

variable "target_node" {
  type        = string
  description = "Proxmox node name"
}

variable "vmid" {
  type        = number
  description = "Container ID (0 for auto-assign)"
  default     = 0
}

variable "hostname" {
  type        = string
  description = "Container hostname"
}

variable "description" {
  type        = string
  description = "Container description"
  default     = ""
}

variable "ostemplate" {
  type        = string
  description = "OS template file (e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
}

variable "os_type" {
  type        = string
  description = "OS type (ubuntu, debian, alpine, archlinux, centos, fedora, rocky, oracle, suse, gentoo, opensuse)"
  default     = "ubuntu"
}

variable "password" {
  type      = string
  description = "Root password"
  default   = ""
  sensitive = true
}

variable "ssh_keys" {
  type        = string
  description = "SSH public keys (newline separated)"
  default     = ""
}

variable "unprivileged" {
  type        = bool
  description = "Run container unprivileged"
  default     = true
}

variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 1
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 512
}

variable "swap" {
  type        = number
  description = "Swap in MB"
  default     = 512
}

variable "rootfs_size" {
  type        = string
  description = "Root filesystem size (e.g. 8)"
  default     = "8"
}

variable "rootfs_storage" {
  type        = string
  description = "Datastore for root filesystem"
  default     = "local-lvm"
}

variable "mount_point" {
  type        = string
  description = "Mount point (datastore:path:size)"
  default     = ""
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "features_nesting" {
  type        = bool
  description = "Enable nesting feature"
  default     = false
}

variable "features_fuse" {
  type        = bool
  description = "Enable FUSE feature"
  default     = false
}

variable "features_keyctl" {
  type        = bool
  description = "Enable keyctl feature"
  default     = false
}

variable "ip_address" {
  type        = string
  description = "Static IP with CIDR"
  default     = ""
}

variable "ip_gateway" {
  type        = string
  description = "Gateway IP"
  default     = ""
}

variable "dns_nameserver" {
  type        = string
  description = "DNS nameserver"
  default     = ""
}

variable "dns_domain" {
  type        = string
  description = "DNS domain"
  default     = ""
}
