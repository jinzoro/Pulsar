// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "api_url" {
  type        = string
  description = "Proxmox API URL"
  default     = "https://pve.example.com:8006/api2/json"
}

variable "token_id" {
  type        = string
  description = "Proxmox API token ID"
  default     = "automation@pam!packer-token"
}

variable "token_secret" {
  type      = string
  description = "Proxmox API token secret"
  default     = ""
  sensitive   = true
}

variable "node" {
  type        = string
  description = "Proxmox node name"
  default     = "pve"
}

variable "storage" {
  type        = string
  description = "Proxmox storage pool"
  default     = "local-lvm"
}

variable "ssh_user" {
  type        = string
  description = "SSH username for provisioning"
  default     = "rocky"
}

variable "ssh_password" {
  type      = string
  description = "SSH password for provisioning"
  default   = ""
  sensitive = true
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "rocky-9-template"
}

variable "vmid" {
  type        = number
  description = "Proxmox VM ID (0 for auto)"
  default     = 0
}

variable "disk_size" {
  type        = string
  description = "Disk size"
  default     = "32G"
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "cpus" {
  type        = number
  description = "Number of CPUs"
  default     = 2
}

variable "ci_user" {
  type        = string
  description = "Cloud-init default user"
  default     = "rocky"
}

variable "ci_password" {
  type      = string
  description = "Cloud-init default password"
  default   = ""
  sensitive = true
}

variable "ci_ssh_key" {
  type      = string
  description = "Cloud-init SSH public key"
  default   = ""
}

variable "ci_ip" {
  type        = string
  description = "Cloud-init static IP (CIDR)"
  default     = ""
}

variable "ci_gateway" {
  type        = string
  description = "Cloud-init gateway"
  default     = ""
}

variable "ci_nameserver" {
  type        = string
  description = "Cloud-init nameserver"
  default     = ""
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
  vm_name   = "${var.template_name}-${local.timestamp}"
}

source "proxmox-iso" "rocky" {
  proxmox_url              = var.api_url
  username                 = var.token_id
  token                    = var.token_secret
  node                     = var.node
  insecure_connection      = true

  vm_name    = local.vm_name
  vm_id      = var.vmid
  cpu_type   = "host"
  cores      = var.cpus
  memory     = var.memory
  scsihw     = "virtio-scsi-single"

  disks {
    disk_size    = var.disk_size
    storage      = var.storage
    type         = "scsi"
    format       = "raw"
    io_thread    = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  iso_file         = "local:iso/Rocky-9.6-x86_64-boot.iso"
  iso_storage_pool = "local"
  iso_checksum     = "sha256:e2c7d2d8c2f09a1b9b40b3c1e3f5a9d8b7c6e4f3a2b1c0d9e8f7a6b5c4d3e2f1"

  cicustom = "user-data=snippets/cloud-init/user-data.yaml,network=snippets/cloud-init/network-config.yaml"
  cicloud  = false

  boot_wait = "10s"
  boot_command = [
    "<wait10>",
    "inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<enter>"
  ]

  http_directory = "http"

  ssh_username = var.ssh_user
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"
  ssh_handshake_attempts = 30

  unmount_iso = true

  template_name        = local.vm_name
  template_description = "Rocky Linux 9 - built ${local.timestamp}"
  tags                 = "packer;rocky;9"

  cloud_init              = true
  cloud_init_storage_pool = var.storage
}

build {
  sources = ["source.proxmox-iso.rocky"]

  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y qemu-guest-agent open-vm-tools",
      "sudo systemctl enable qemu-guest-agent",
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo truncate -s 0 /var/lib/dbus/machine-id",
      "sudo sync"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo rm -rf /var/log/cloud-init*.log",
      "sudo rm -rf /tmp/*",
      "sudo sync"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S -E bash '{{ .Path }}'"
  }
}
