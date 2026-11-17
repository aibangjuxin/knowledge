reference
- [labels-best-practices](./labels-best-practices.md)
- Helm 的 `_helper.tpl` 中定义一个包含 `selectorLabels` 的 `metadata.labels`，
- 它模糊了“标识 Deployment 对象”和“标识它管理的 Pod”这两个不同目的。查询 `app.kubernetes.io/name=my-app` 可能会同时返回 Deployment 和 Pod，虽然能工作，但在逻辑上是不清晰的。