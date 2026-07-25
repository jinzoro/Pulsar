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

variable "winrm_user" {
  type        = string
  description = "WinRM username"
  default     = "Administrator"
}

variable "winrm_password" {
  type      = string
  description = "WinRM password"
  default   = ""
  sensitive = true
}

variable "template_name" {
  type        = string
  description = "Name of the resulting template"
  default     = "windows-2022-template"
}

variable "vmid" {
  type        = number
  description = "Proxmox VM ID (0 for auto)"
  default     = 0
}

variable "disk_size" {
  type        = string
  description = "Disk size"
  default     = "60G"
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 4096
}

variable "cpus" {
  type        = number
  description = "Number of CPUs"
  default     = 4
}

variable "admin_password" {
  type      = string
  description = "Windows Administrator password"
  default   = ""
  sensitive = true
}

variable "product_key" {
  type      = string
  description = "Windows product key"
  default   = ""
  sensitive = true
}

variable "vm_net_ipv4_address" {
  type        = string
  description = "Static IP address for the VM"
  default     = "10.0.0.100/24"
}

variable "vm_net_ipv4_gateway" {
  type        = string
  description = "Gateway for the VM"
  default     = "10.0.0.1"
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
  vm_name   = "${var.template_name}-${local.timestamp}"
}

source "proxmox-iso" "windows" {
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
  os         = "win11"

  bios = "ovmf"

  efi_config {
    efi_storage_pool  = var.storage
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  disks {
    disk_size    = var.disk_size
    storage      = var.storage
    type         = "scsi"
    format       = "raw"
    io_thread    = true
    cache        = "none"
    disk_emulation = "ssd"
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  iso_file         = "local:iso/WinServer2022.iso"
  iso_storage_pool = "local"
  iso_checksum     = "sha256:47ac0e5c0e23d6a0f2e7b6f20b6e3b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a"

  floppy_files = [
    "autounattend.xml"
  ]

  boot_wait = "5s"
  boot_command = [
    "<wait30>"
  ]

  communicator   = "winrm"
  winrm_username = var.winrm_user
  winrm_password = var.winrm_password
  winrm_timeout  = "60m"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_port     = 5986

  http_directory = "http"

  unmount_iso = true

  template_name        = local.vm_name
  template_description = "Windows Server 2022 - built ${local.timestamp}"
  tags                 = "packer;windows;2022"

  cloud_init              = false
  cloud_init_storage_pool = var.storage
}

build {
  sources = ["source.proxmox-iso.windows"]

  provisioner "powershell" {
    elevated_user     = var.winrm_user
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Installing QEMU Guest Agent...'",
      "Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V' -ErrorAction SilentlyContinue | Out-Null",
      "if (Test-Path 'C:\\Program Files\\qemu-ga\\qemu-ga.exe') { & 'C:\\Program Files\\qemu-ga\\qemu-ga.exe' }"
    ]
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_user
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Enabling RDP...'",
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",
      "Write-Host 'Configuring WinRM...'",
      "winrm quickconfig -force",
      "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'",
      "winrm set winrm/config/service/auth '@{Basic=\"true\"}'"
    ]
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_user
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Enabling SSH...'",
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Name 'DefaultShell' -Value 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' -PropertyType String -Force"
    ]
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_user
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Running Windows Update...'",
      "Install-Module PSWindowsUpdate -Force -SkipPublisherCheck",
      "Get-WindowsUpdate -AcceptAll -Install -AutoReboot",
      "Write-Host 'Disabling unnecessary services...'",
      "Set-Service -Name 'SysMain' -StartupType Disabled -Status Stopped",
      "Set-Service -Name 'WSearch' -StartupType Disabled -Status Stopped",
      "Write-Host 'Setting power plan to High Performance...'",
      "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    ]
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_user
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Cleaning up temp files...'",
      "Remove-Item -Path $env:TEMP\\* -Recurse -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "Clear-RecycleBin -Force -ErrorAction SilentlyContinue",
      "Write-Host 'Sysprepping...'",
      "& C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /quit /mode:vm"
    ]
  }
}
