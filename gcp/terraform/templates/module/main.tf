# modules/<name>/main.tf
# 主资源定义 — 单文件 < 200 行最佳;超过则按资源类型拆成 <resource>.tf

resource "google_<resource_type>" "primary" {
  name        = var.resource_name
  project     = var.project_id
  region      = var.region

  # ... 资源特定字段

  labels = var.labels
}
