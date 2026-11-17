# Module `<name>`

> 用途一句话描述 — 这个 module 管什么资源,适用什么场景。

## 用法

```hcl
module "<name>" {
  source = "../../modules/<name>"

  # 必填
  project_id = "my-project"
  region     = "us-central1"

  # 可选(常用)
  cluster_name = "my-cluster"
  node_count   = 2
}
```

## Variables

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_id` | `string` | — | ✅ | GCP project ID |
| `region` | `string` | — | ✅ | GCP region |
| `cluster_name` | `string` | — | ❌ | Resource name |
| `node_count` | `number` | `2` | ❌ | Initial count |

## Outputs

| Name | Description |
|---|---|
| `cluster_id` | Resource ID, for downstream `kubernetes` provider config |
| `cluster_endpoint` | host:port for `kubectl` access |

## 例子

参见 `examples/complete/main.tf`。

## 注意事项

- 创建后删除 **不会** 删除挂在上面的 K8s 资源(无 lifecycle.prevent_destroy)
- 修改 `cluster_name` 会触发 `terraform destroy + create`(要 rename 改用 `moved` block)
