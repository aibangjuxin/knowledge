# modules/<name>/examples/complete/main.tf
# 一个完整 module 调用示例,用于 module 单元测试 / docs 演示

module "<name>" {
  source = "../../"

  project_id   = "example-project"
  region       = "us-central1"
  resource_name = "example-resource"

  labels = {
    env     = "test"
    example = "complete"
  }
}

output "id" {
  value = module.<name>.id
}
