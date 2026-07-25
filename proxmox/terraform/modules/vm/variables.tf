// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

variable "target_node" {
  type        = string
  description = "Proxmox node name"
}

variable "name" {
  type        = string
  description = "VM name"
}

variable "vmid" {
  type        = number
  description = "Proxmox VM ID (0 for auto-assign)"
  default     = 0
}

variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores per socket"
  default     = 2
}

variable "cpu_sockets" {
  type        = number
  description = "Number of CPU sockets"
  default     = 1
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB"
  default     = 32
}

variable "disk_storage" {
  type        = string
  description = "Datastore for the disk"
  default     = "local-lvm"
}

variable "template_id" {
  type        = number
  description = "Source template VM ID to clone from"
}

variable "clone_full" {
  type        = bool
  description = "Create a full clone (true) or linked clone (false)"
  default     = true
}

variable "ci_user" {
  type        = string
  description = "Cloud-init username"
  default     = ""
}

variable "ci_password" {
  type      = string
  description = "Cloud-init password"
  default   = ""
  sensitive = true
}

variable "ci_ssh_keys" {
  type        = string
  description = "Cloud-init SSH public key"
  default     = ""
}

variable "ci_ip" {
  type        = string
  description = "Cloud-init static IP with CIDR (e.g. 10.0.0.10/24)"
  default     = ""
}

variable "ci_gateway" {
  type        = string
  description = "Cloud-init gateway"
  default     = ""
}

variable "ci_nameserver" {
  type        = string
  description = "Cloud-init nameserver IP"
  default     = ""
}

variable "ci_domain" {
  type        = string
  description = "Cloud-init domain name"
  default     = ""
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "network_model" {
  type        = string
  description = "Network adapter model"
  default     = "virtio"
}

variable "tags" {
  type        = string
  description = "Comma-separated tags"
  default     = ""
}

variable "description" {
  type        = string
  description = "VM description"
  default     = ""
}

variable "agent" {
  type        = bool
  description = "Enable QEMU guest agent"
  default     = true
}

variable "bios" {
  type        = string
  description = "BIOS type (seabios, ovmf)"
  default     = "seabios"
}

variable "machine_type" {
  type        = string
  description = "Machine type (e.g. q35, i440fx)"
  default     = ""
}
