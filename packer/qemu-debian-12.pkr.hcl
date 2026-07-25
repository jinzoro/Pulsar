// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "ssh_user" {
  type        = string
  description = "SSH username for provisioning"
  default     = "debian"
}

variable "ssh_password" {
  type      = string
  description = "SSH password for provisioning"
  default   = ""
  sensitive = true
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

variable "output_directory" {
  type        = string
  description = "Output directory for the image"
  default     = "output-debian-12"
}

variable "output_format" {
  type        = string
  description = "Output format (qcow2, raw, vdi, vmdk)"
  default     = "qcow2"
}

variable "iso_url" {
  type        = string
  description = "ISO download URL"
  default     = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type        = string
  description = "ISO checksum"
  default     = "sha256:32b5b1b20ed4ae0c0e4e580e83a1c7cf5c95f6a58a83e9c1c5e7e9f1d3b8c4a2"
}

variable "http_directory" {
  type        = string
  description = "HTTP directory for cloud-init"
  default     = "http"
}

variable "ci_user" {
  type        = string
  description = "Cloud-init default user"
  default     = "debian"
}

variable "ci_password" {
  type      = string
  description = "Cloud-init default password"
  default   = ""
  sensitive = true
}

variable "shutdown_command" {
  type        = string
  description = "Shutdown command"
  default     = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
}

source "qemu" "debian" {
  vm_name          = "debian-12-${local.timestamp}"
  output_directory = var.output_directory
  format           = var.output_format
  accelerator      = "kvm"

  cpus      = var.cpus
  cpu_model = "host"
  memory    = var.memory
  net_device_type = "virtio-net"

  disk_size      = var.disk_size
  disk_discard   = "unmap"
  disk_cache      = "none"
  disk_interface  = "virtio-scsi-pci"
  disk_compression = true
  disk_detect_zeroes = "unmap"

  boot_wait    = "5s"
  boot_command = [
    "<wait5>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ",
    "<enter><wait>",
    "<f10>"
  ]

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  http_directory = var.http_directory

  ssh_username = var.ssh_user
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"
  ssh_handshake_attempts = 30
  ssh_pty = true

  shutdown_command = var.shutdown_command

  qemuargs = [
    ["-cpu", "host"],
    ["-device", "virtio-scsi-pci,id=scsi0"],
    ["-device", "virtio-net-pci,netdev=net0"],
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"]
  ]

  headless = false
  vnc_disable_password = true
  vnc_bind_address = "0.0.0.0"

  vm_interface     = ""
  display          = "none"
}

build {
  sources = ["source.qemu.debian"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y qemu-guest-agent open-vm-tools",
      "sudo systemctl enable qemu-guest-agent",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
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

  post-processor "compress" {
    compression_level = 6
    keep_input        = false
    output            = "{{ .OutputDirectory }}/{{ .BuildName }}.${var.output_format}.gz"
  }
}
