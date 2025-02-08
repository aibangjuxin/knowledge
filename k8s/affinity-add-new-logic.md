
- [old api pod anti-affinity](#old-api-pod-anti-affinity)
- [New Logic](#new-logic)
- [理解这个步骤](#理解这个步骤)

# old api pod anti-affinity 
需求是将两个特定的 Deployment (api-authn 和 api-cicd) 避免部署在同一个 Node 上，同时保留原有的 Node 互斥和 Zone 亲和性策略。  这可以通过结合 PodAntiAffinity 和适当的 Label 选择器来实现。

这里提供一个可行的解决方案，并解释其原理和需要注意的地方：
old logic 
```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - nginx
          topologyKey: kubernetes.io/hostname
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 1
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app
                  operator: In
                  values:
                    - nginx
            topologyKey: topology.kubernetes.io/zone
  automountServiceAccountToken: false
```
# New Logic 
**解决方案:**

1. **为 `api-authn` 和 `api-cicd` Deployment 添加统一的 Label：**  这一步是关键，它允许我们创建一个通用的反亲和性规则。  例如，你可以添加一个标签 `app.kubernetes.io/component=api-group` 到两个 Deployment 的 Pod 模板中。

   * **api-authn Deployment (示例)：**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-authn
spec:
  selector:
    matchLabels:
      app: api-authn
      app.kubernetes.io/component: api-group  # 添加的 Label 这里不能添加,因为spec.selector字段不能修改,不能在deployment 更新时修改.具体来说来说，spec.selector字段定义了depployment的标签选择器，一旦创建后，这个字段就不可以修改了。
  template:
    metadata:
      labels:
        app: api-authn
        app.kubernetes.io/component: api-group  # 添加的 Label
    spec:
      # ... 其他配置 ...
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/component
                    operator: In
                    values:
                      - api-group  # 使用统一的 Label
              topologyKey: kubernetes.io/hostname
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - nginx #保持原来的配置，如果确实需要
                topologyKey: topology.kubernetes.io/zone
      automountServiceAccountToken: false
```

   * **api-cicd Deployment (示例)：**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-cicd
spec:
  selector:
    matchLabels:
      app: api-cicd
  template:
    metadata:
      labels:
        app: api-cicd
        app.kubernetes.io/component: api-group  # 添加的 Label
    spec:
      # ... 其他配置 ...
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/component
                    operator: In
                    values:
                      - api-group  # 使用统一的 Label
              topologyKey: kubernetes.io/hostname
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - nginx #保持原来的配置，如果确实需要
                topologyKey: topology.kubernetes.io/zone
      automountServiceAccountToken: false
```

2. **配置 `podAntiAffinity`：**  在两个 Deployment 的 Pod 模板中，`podAntiAffinity` 部分需要修改。 关键在于使用上面新加的Label(`app.kubernetes.io/component=api-group`) 作为 `labelSelector`。

   * `requiredDuringSchedulingIgnoredDuringExecution`:  这部分强制执行互斥规则。  任何带有 `app.kubernetes.io/component=api-group` 标签的 Pod 都不会被调度到与已存在具有相同标签的 Pod 所在的 Node 上。

   * `preferredDuringSchedulingIgnoredDuringExecution`:  这部分是软亲和性，尝试将 Pod 分布到不同的 Zone。

**解释:**

* **统一 Label:**  `app.kubernetes.io/component=api-group`  将 `api-authn` 和 `api-cicd` Deployment 的 Pod 归为同一组。  这是 `podAntiAffinity` 能够识别并执行互斥的基础。

* **`podAntiAffinity`:** `requiredDuringSchedulingIgnoredDuringExecution`  确保了调度器在调度 Pod 时，会考虑所有带有 `app.kubernetes.io/component=api-group` 标签的 Pod，并避免将它们放在同一个 Node 上。

* **保持现有 Zone 亲和性:**  `preferredDuringSchedulingIgnoredDuringExecution`  部分保持不变，继续尝试将 Pod 分布到不同的 Zone。

**注意事项:**

* **资源需求:**  如果 Node 的资源有限，`requiredDuringSchedulingIgnoredDuringExecution` 可能会导致 Pod 无法被调度。  确保你的 Node 有足够的资源来满足所有 Pod 的需求。
* **Label 选择器:**  仔细选择 Label Key 和 Value。  确保它们只匹配你想互斥的 Deployment 的 Pod。  错误的 Label 选择器可能导致不必要的限制。
* **测试:**  在生产环境中部署之前，务必在测试环境中验证该配置是否按预期工作。
* **可维护性:**  使用有意义且一致的 Label 命名规范，以便于未来的维护和管理。 使用 `app.kubernetes.io/*` 前缀是符合 Kubernetes 推荐标准的，这有助于提高可发现性和避免命名冲突。
* **滚动更新:** 滚动更新 Deployment 时，新 Pods 仍然会受到 `podAntiAffinity` 的限制，所以不必担心更新期间Pod会被调度到同一个 Node。

**总结:**

通过为 `api-authn` 和 `api-cicd` Deployment 添加一个通用的 Label，并在它们的 Pod 模板中使用 `podAntiAffinity` 与该 Label 配合，可以有效地防止这两个 Deployment 的 Pod 运行在同一个 Node 上，同时保持原有的 Zone 亲和性策略。  请务必根据你的实际环境调整 Label 和资源需求。


# 理解这个步骤


```bash
那么我看起来其实我的模版没有改变 仅仅是为 api-authn 和 api-cicd Deployment 添加统一的 Label：也就是同样命名的Label 我确保这个Label在我的工程里面唯一 仅仅打在api-authn 和 api-cicd Deployment 然后在后面的requiredDuringSchedulingIgnoredDuringExecution:这里通过这个Labels 来做requiredDuringSchedulingIgnoredDuringExecution  
其实我环境里面其他的所有API因为名字都是唯一的  
所以我使用的是这种格式
```




如果你确保 `{api-name}-{api-version}` 这个 Label 的组合在你的集群中是唯一的，并且只被 `api-authn` 和 `api-cicd` Deployment 使用，那么使用你提供的配置应该可以实现你的需求，即防止它们部署在同一个 Node 上，并且倾向于部署在不同的 Zone。

不过，针对你的配置，我还是有一些建议和需要强调的地方：

1. **风险评估：唯一性保证:**  你依赖 `{api-name}-{api-version}` 的组合的唯一性。 这是一个风险点。
   *  **未来的 API 版本：** 如果你未来添加了新的 API，或者修改了现有 API 的版本，你必须非常小心，确保新的 API 版本没有意外地使用相同的 `{api-name}-{api-version}` 组合。否则，它们将会错误地与 `api-authn` 和 `api-cicd` 发生互斥。
   * **人为错误：**  人为错误是不可避免的。如果有人不小心将相同的 `{api-name}-{api-version}` 标签应用到其他的 Pod 上，那么它也会受到这个 `podAntiAffinity` 的影响，这可能不是你期望的。

2. **Label 的命名规范:** 尽管你说 `{api-name}-{api-version}` 在你的环境中是唯一的，但最好还是遵循 Kubernetes 的推荐实践，使用更明确和规范的 Label Key。  前面提到的 `app.kubernetes.io/component` 就是一个好例子，或者你可以自定义一个更具体的，例如 `your-domain.com/api-group`。

3. **`requiredDuringSchedulingIgnoredDuringExecution` 的行为:**
   *  **硬性约束:** 请记住，`requiredDuringSchedulingIgnoredDuringExecution` 是一个硬性约束。  如果 Kubernetes 无法满足这个约束（例如，你的 Node 资源不足，或者由于其他的 `podAntiAffinity` 规则导致无法调度），那么 Pod 将会一直处于 Pending 状态。
   * **调试难度：** 复杂的 `podAntiAffinity` 规则可能会使调度问题难以调试。  如果你发现 Pod 无法调度，你需要仔细检查所有的 `podAntiAffinity` 和 `podAffinity` 规则，以及 Node 的资源情况。

4. **建议的改进方案 (更安全):**

   为了提高安全性和可维护性，我强烈建议你采纳我之前提出的建议，即：

   * **添加统一的 Label：** 例如，`app.kubernetes.io/api-type: critical`。只将这个 Label 添加到 `api-authn` 和 `api-cicd` Deployment 中。

   * **使用这个统一的 Label 配置 `podAntiAffinity`:**

     ```yaml
     spec:
       affinity:
         podAntiAffinity:
           requiredDuringSchedulingIgnoredDuringExecution:
             - labelSelector:
                 matchExpressions:
                   - key: app.kubernetes.io/api-type
                     operator: In
                     values:
                       - critical
               topologyKey: kubernetes.io/hostname
           preferredDuringSchedulingIgnoredDuringExecution:
             - weight: 1
               podAffinityTerm:
                 labelSelector:
                   matchExpressions:
                     - key: app
                       operator: In
                       values:
                         - nginx #保持原来的配置，如果确实需要
                 topologyKey: topology.kubernetes.io/zone
     ```

   这种方式的优点是：

   * **更明确的意图：**  `app.kubernetes.io/api-type: critical` 清楚地表明了这些 API 是关键的，需要避免部署在同一个 Node 上。
   * **更安全：**  即使你未来添加了新的 API，只要你不给它们添加 `app.kubernetes.io/api-type: critical` 标签，它们就不会受到这个 `podAntiAffinity` 的影响。
   * **更易于维护：**  这种方式更易于理解和维护。如果你想修改这个规则，你只需要修改一个地方 (`critical`这个label)，而不是每个 Deployment 中的 `{api-name}-{api-version}` 列表。

**总结:**

虽然你当前的方法在理论上可行，但它存在一定的风险。 为了提高安全性和可维护性，强烈建议使用统一的 Label 和更明确的命名规范。  在生产环境中部署之前，请务必进行充分的测试。

