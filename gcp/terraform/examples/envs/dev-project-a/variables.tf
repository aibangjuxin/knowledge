# envs/dev/project-a/variables.tf
variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "dev-cluster-a"
}

variable "node_count" {
  description = "Initial GKE node count"
  type        = number
  default     = 2
}

variable "domain_name" {
  description = "Public domain for the GLB"
  type        = string
  default     = "api-dev.project-a.example.com"
}
