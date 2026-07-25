// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

variable "pm_api_url" {
  type        = string
  description = "Proxmox API endpoint URL"
  default     = "https://pve.example.com:8006/api2/json"
}

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID"
  default     = "automation@pam!terraform"
}

variable "pm_api_token_secret" {
  type      = string
  description = "Proxmox API token secret"
  default   = ""
  sensitive = true
}

variable "pm_api_tls_insecure" {
  type        = bool
  description = "Skip TLS verification"
  default     = false
}

variable "pm_node" {
  type        = string
  description = "Proxmox node name"
  default     = "pve"
}

variable "vms" {
  type = map(object({
    name           = string
    vmid           = optional(number, 0)
    cpu_cores      = optional(number, 2)
    cpu_sockets    = optional(number, 1)
    memory         = optional(number, 2048)
    disk_size      = optional(number, 32)
    disk_storage   = optional(string, "local-lvm")
    template_id    = number
    clone_full     = optional(bool, true)
    ci_user        = optional(string, "")
    ci_password    = optional(string, "")
    ci_ssh_keys    = optional(string, "")
    ci_ip          = optional(string, "")
    ci_gateway     = optional(string, "")
    ci_nameserver  = optional(string, "")
    ci_domain      = optional(string, "")
    network_bridge = optional(string, "vmbr0")
    network_model  = optional(string, "virtio")
    tags           = optional(string, "")
    description    = optional(string, "")
    agent          = optional(bool, true)
    bios           = optional(string, "seabios")
    machine_type   = optional(string, "")
  }))
  description = "Map of VMs to create"
  default     = {}
}

variable "containers" {
  type = map(object({
    hostname       = string
    vmid           = optional(number, 0)
    ostemplate     = string
    os_type        = optional(string, "ubuntu")
    password       = optional(string, "")
    ssh_keys       = optional(string, "")
    unprivileged   = optional(bool, true)
    cpu_cores      = optional(number, 1)
    memory         = optional(number, 512)
    swap           = optional(number, 512)
    rootfs_size    = optional(string, "8")
    rootfs_storage = optional(string, "local-lvm")
    network_bridge = optional(string, "vmbr0")
    ip_address     = optional(string, "")
    ip_gateway     = optional(string, "")
    dns_nameserver = optional(string, "")
    dns_domain     = optional(string, "")
  }))
  description = "Map of containers to create"
  default     = {}
}

variable "networks" {
  type = map(object({
    type           = optional(string, "bridge")
    name           = string
    comment        = optional(string, "")
    address        = optional(string, "")
    cidr           = optional(string, "")
    gateway        = optional(string, "")
    vlan_id        = optional(number, null)
    vlan_interface = optional(string, "")
    bridge_ports   = optional(string, "")
    bridge_stp     = optional(bool, false)
    bridge_fd      = optional(number, 0)
    bond_mode      = optional(string, "balance-rr")
    bond_members   = optional(list(string), [])
  }))
  description = "Map of network interfaces to create"
  default     = {}
}

variable "pools" {
  type = map(object({
    pool_id = string
    comment = optional(string, "")
    members = optional(list(number), [])
  }))
  description = "Map of resource pools to create"
  default     = {}
}
