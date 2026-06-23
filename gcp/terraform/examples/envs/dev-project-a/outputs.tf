# envs/dev/project-a/outputs.tf
output "cluster_endpoint" {
  description = "GKE cluster endpoint (host:port) for kubectl access"
  value       = module.gke.cluster_endpoint
}

output "cluster_id" {
  description = "GKE cluster ID, for downstream kubernetes provider config"
  value       = module.gke.cluster_id
}

output "project_id" {
  description = "Project ID this env deployed to"
  value       = local.project_id
}

output "glb_ip" {
  description = "Public GLB static IP (point your DNS A record here)"
  value       = module.glb_public.global_ip
}

output "domain" {
  description = "Public domain for the GLB"
  value       = var.domain_name
}
