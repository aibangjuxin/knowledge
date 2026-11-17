# modules/<name>/variables.tf
# 所有 input variable 必须有 description;有规则用 validation 块

variable "project_id" {
  description = "GCP project ID hosting the resource"
  type        = string
}

variable "region" {
  description = "GCP region. e.g. us-central1"
  type        = string
}

variable "resource_name" {
  description = "Name of the resource. Must be unique within project/region"
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,38}$", var.resource_name))
    error_message = "resource_name must start with lowercase letter, max 39 chars, only [a-z0-9-]."
  }
}

variable "labels" {
  description = "Labels to apply to the resource"
  type        = map(string)
  default     = {}
}
