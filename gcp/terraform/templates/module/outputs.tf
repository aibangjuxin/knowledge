# modules/<name>/outputs.tf
# 只 output 下游真正需要的值,不要把内部 resource 的所有属性都 output

output "id" {
  description = "Resource ID"
  value       = google_<resource_type>.primary.id
}

output "self_link" {
  description = "Resource self_link (for cross-module references)"
  value       = google_<resource_type>.primary.self_link
}
