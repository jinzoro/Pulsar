// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

variable "pool_id" {
  type        = string
  description = "Pool ID / name"
}

variable "comment" {
  type        = string
  description = "Pool description"
  default     = ""
}

variable "members" {
  type        = list(number)
  description = "List of VM/container IDs to assign to the pool"
  default     = []
}
