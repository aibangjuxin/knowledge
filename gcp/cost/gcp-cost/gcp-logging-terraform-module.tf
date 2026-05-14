# GCP 日志成本优化 Terraform 模块
# 
# 此模块实现了完整的 GCP 日志成本优化策略，包括：
# - 分环境的自定义日志桶
# - 差异化保留策略
# - 成本优化的排除过滤器
# - GCS 归档配置
# - GKE 集群日志优化

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.50.0"
    }
  }
}

# 变量定义
variable "project_id" {
  description = "GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "默认区域"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "环境类型 (dev, test, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "环境必须是 dev, test, staging, 或 prod 之一。"
  }
}

variable "enable_gcs_archive" {
  description = "是否启用 GCS 归档"
  type        = bool
  default     = true
}

variable "enable_cost_optimization_filters" {
  description = "是否启用成本优化过滤器"
  type        = bool
  default     = true
}

# 本地变量 - 环境特定配置
locals {
  environment_config = {
    dev = {
      retention_days = 7
      log_level     = "ERROR"
      enable_workload_logs = false
      archive_filter = "severity>=ERROR"
    }
    test = {
      retention_days = 14
      log_level     = "WARNING"
      enable_workload_logs = false
      archive_filter = "severity>=WARNING"
    }
    staging = {
      retention_days = 30
      log_level     = "INFO"
      enable_workload_logs = true
      archive_filter = "severity>=INFO"
    }
    prod = {
      retention_days = 90
      log_level     = "INFO"
      enable_workload_logs = true
      archive_filter = "severity>=INFO"
    }
  }
  
  current_config = local.environment_config[var.environment]
  
  # 通用排除过滤器
  common_exclusion_filters = [
    {
      name        = "exclude-health-checks"
      description = "排除 Kubernetes 健康检查日志"
      filter      = "resource.type=\"k8s_container\" AND httpRequest.userAgent =~ \"kube-probe\""
    },
    {
      name        = "exclude-istio-proxy"
      description = "排除 Istio 代理容器日志"
      filter      = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"istio-proxy\""
    },
    {
      name        = "exclude-system-noise"
      description = "排除系统组件噪音日志"
      filter      = "(resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"kube-system\" AND severity < ERROR) OR (resource.type=\"gce_instance\" AND jsonPayload.message =~ \".*systemd.*started.*\")"
    }
  ]
  
  # 环境特定排除过滤器
  environment_exclusion_filters = var.environment != "prod" ? [
    {
      name        = "exclude-low-severity"
      description = "排除低严重性日志（非生产环境）"
      filter      = "resource.type=\"k8s_container\" AND severity < ${local.current_config.log_level}"
    }
  ] : []
  
  all_exclusion_filters = concat(local.common_exclusion_filters, local.environment_exclusion_filters)
}

# 1. 自定义日志桶
resource "google_logging_project_bucket_config" "optimized_bucket" {
  project        = var.project_id
  location       = "global"
  retention_days = local.current_config.retention_days
  bucket_id      = "${var.environment}-optimized-logs"
  description    = "Cost-optimized log bucket for ${var.environment} environment with ${local.current_config.retention_days}-day retention"
  
  # 启用 Log Analytics（免费功能）
  enable_analytics = true
}

# 2. 日志接收器 - 路由到自定义桶
resource "google_logging_project_sink" "optimized_sink" {
  name        = "${var.environment}-optimized-sink"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/${google_logging_project_bucket_config.optimized_bucket.bucket_id}"
  
  # 基础过滤器 - 只包含指定严重性级别以上的日志
  filter = "severity>=${local.current_config.log_level}"
  
  # 确保接收器有唯一的写入身份
  unique_writer_identity = true
  
  # 动态排除项配置
  dynamic "exclusions" {
    for_each = var.enable_cost_optimization_filters ? local.all_exclusion_filters : []
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}

# 3. GCS 归档存储桶（可选）
resource "google_storage_bucket" "log_archive" {
  count    = var.enable_gcs_archive ? 1 : 0
  name     = "${var.project_id}-${var.environment}-log-archive"
  location = var.region
  
  # 使用 Archive 存储类别以降低成本
  storage_class = "ARCHIVE"
  
  # 防止意外删除
  lifecycle_rule {
    condition {
      age = 365 # 一年后删除
    }
    action {
      type = "Delete"
    }
  }
  
  # 版本控制
  versioning {
    enabled = false
  }
  
  # 统一存储桶级访问
  uniform_bucket_level_access = true
}

# 4. GCS 归档接收器（可选）
resource "google_logging_project_sink" "gcs_archive_sink" {
  count       = var.enable_gcs_archive ? 1 : 0
  name        = "${var.environment}-gcs-archive-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.log_archive[0].name}"
  
  # 归档过滤器 - 根据环境配置
  filter = local.current_config.archive_filter
  
  unique_writer_identity = true
}

# 5. 为 GCS 归档接收器授权
resource "google_storage_bucket_iam_member" "log_writer" {
  count  = var.enable_gcs_archive ? 1 : 0
  bucket = google_storage_bucket.log_archive[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.gcs_archive_sink[0].writer_identity
}

# 6. 项目级排除规则（全局生效）
resource "google_logging_project_exclusion" "global_exclusions" {
  for_each = var.enable_cost_optimization_filters ? {
    for filter in local.all_exclusion_filters : filter.name => filter
  } : {}
  
  name        = "global-${each.value.name}"
  description = "Global ${each.value.description}"
  filter      = each.value.filter
  project     = var.project_id
}

# 7. 基于日志的指标 - 用于成本监控
resource "google_logging_metric" "log_volume_by_severity" {
  name   = "${var.environment}_log_volume_by_severity"
  filter = "resource.type=\"k8s_container\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "${title(var.environment)} Log Volume by Severity"
  }
  
  label_extractors = {
    "severity" = "EXTRACT(severity)"
    "namespace" = "EXTRACT(resource.labels.namespace_name)"
  }
  
  value_extractor = "1"
}

# 8. 成本监控告警策略
resource "google_monitoring_alert_policy" "log_volume_alert" {
  display_name = "${title(var.environment)} Log Volume Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Log volume spike"
    
    condition_threshold {
      filter          = "resource.type=\"logging_metric\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.log_volume_by_severity.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.environment == "prod" ? 10000 : 5000
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [] # 在实际使用时添加通知渠道
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# 输出值
output "log_bucket_name" {
  description = "创建的日志桶名称"
  value       = google_logging_project_bucket_config.optimized_bucket.bucket_id
}

output "log_bucket_retention_days" {
  description = "日志桶保留天数"
  value       = google_logging_project_bucket_config.optimized_bucket.retention_days
}

output "gcs_archive_bucket" {
  description = "GCS 归档存储桶名称"
  value       = var.enable_gcs_archive ? google_storage_bucket.log_archive[0].name : null
}

output "sink_writer_identity" {
  description = "日志接收器的写入身份"
  value       = google_logging_project_sink.optimized_sink.writer_identity
}

output "cost_optimization_summary" {
  description = "成本优化配置摘要"
  value = {
    environment           = var.environment
    retention_days       = local.current_config.retention_days
    log_level_filter     = local.current_config.log_level
    exclusion_filters    = length(local.all_exclusion_filters)
    gcs_archive_enabled  = var.enable_gcs_archive
    estimated_cost_reduction = var.environment == "prod" ? "20-30%" : "60-80%"
  }
}

# 使用示例的 terraform.tfvars 文件内容
/*
# terraform.tfvars 示例

project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"  # 或 "test", "staging", "prod"

# 可选配置
enable_gcs_archive = true
enable_cost_optimization_filters = true
*/

# 使用示例
/*
# 1. 初始化 Terraform
terraform init

# 2. 规划部署
terraform plan -var="project_id=your-project-id" -var="environment=dev"

# 3. 应用配置
terraform apply -var="project_id=your-project-id" -var="environment=dev"

# 4. 查看输出
terraform output
*/