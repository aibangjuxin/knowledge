# 05 — 动手实践:最小可运行 Operator 与 GitHub 交付链路

> 目标:跑通"GitHub push → CI 更新 CR → KubeOps Operator 调谐出 Deployment → Pod 滚动上线"。
> 环境要求:.NET 8+,一个 K8s 集群(kind / minikube / GKE 都行)。

---

## 1. 创建 Operator 项目

```bash
# 方式 A:用项目模板(推荐,自带示例 CR + Controller + Finalizer)
dotnet new install KubeOps.Templates
dotnet new operator -n MyOperator
cd MyOperator

# 方式 B:普通 console 项目,自己加包
dotnet new console -n MyOperator
dotnet add package KubeOps.Operator
```

模板项目结构大致是:

```
MyOperator/
├── Program.cs                    # 入口:AddKubernetesOperator().RegisterComponents().Run()
├── Entities/V1DemoEntity.cs     # CR 定义(C# class + [KubernetesEntity])
├── Controllers/
│   ├── V1DemoEntityController.cs
│   └── V1DemoEntityFinalizer.cs
└── config/                       # 构建期生成(见第 4 节)
```

---

## 2. 定义 CR(期望状态的载体)

```csharp
using KubeOps.Abstractions.Entities.Attributes;

[KubernetesEntity]
public class V1DemoEntity
{
    public string DeploymentName { get; set; } = "";
    public int Replicas { get; set; } = 1;
    public string Image { get; set; } = "nginx:1.27";
}
```

- `[KubernetesEntity]` 让 Roslyn 生成器产出 CRD YAML,并自动注册 controller
- CRD 的 `spec` 就是**期望状态**,Operator 只认它

生成出来的 CRD 长这样(示意):

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: demoentities.demo.kubeops.dev
spec:
  group: demo.kubeops.dev
  names:
    kind: V1DemoEntity
    plural: demoentities
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                deploymentName: { type: string }
                replicas: { type: integer }
                image: { type: string }
```

---

## 3. 写 Controller(唯一需要你写的业务逻辑)

```csharp
public class V1DemoEntityController(
    ILogger<V1DemoEntityController> logger,
    IKubernetesClient client) : IEntityController<V1DemoEntity>
{
    public async Task<ReconciliationResult<V1DemoEntity>> ReconcileAsync(
        V1DemoEntity entity, CancellationToken cancellationToken)
    {
        logger.LogInformation("Reconciling {Name}.", entity.Name());

        var name = entity.Spec.DeploymentName;
        var ns = entity.Namespace();

        var existing = await client.GetAsync<V1Deployment>(name, ns, cancellationToken);

        if (existing == null)
        {
            await client.CreateAsync(new V1Deployment
            {
                Metadata = new V1ObjectMeta { Name = name, NamespaceProperty = ns },
                Spec = new V1DeploymentSpec
                {
                    Replicas = entity.Spec.Replicas,
                    Selector = new V1LabelSelector
                    {
                        MatchLabels = new Dictionary<string, string> { ["app"] = name }
                    },
                    Template = new V1PodTemplateSpec
                    {
                        Metadata = new V1ObjectMeta
                        {
                            Labels = new Dictionary<string, string> { ["app"] = name }
                        },
                        Spec = new V1PodSpec
                        {
                            Containers = new[]
                            {
                                new V1Container
                                {
                                    Name = name,
                                    Image = entity.Spec.Image,
                                    Ports = new[] { new V1ContainerPort { ContainerPort = 80 } }
                                }
                            }
                        }
                    }
                }
            }, cancellationToken);
        }
        else if (existing.Spec.Replicas != entity.Spec.Replicas ||
                 existing.Spec.Template.Spec.Containers[0].Image != entity.Spec.Image)
        {
            existing.Spec.Replicas = entity.Spec.Replicas;
            existing.Spec.Template.Spec.Containers[0].Image = entity.Spec.Image;
            await client.UpdateAsync(existing, cancellationToken);
        }

        entity.Status.LastReconciled = DateTime.UtcNow;
        await client.UpdateStatusAsync(entity, cancellationToken);  // 不会再次触发自己

        return ReconciliationResult<V1DemoEntity>.Success(entity);
    }

    public async Task<ReconciliationResult<V1DemoEntity>> DeletedAsync(
        V1DemoEntity entity, CancellationToken cancellationToken)
    {
        // 仅通知性,不做清理 —— 清理请写 Finalizer
        logger.LogInformation("Entity {Name} was deleted.", entity.Name());
        return ReconciliationResult<V1DemoEntity>.Success(entity);
    }
}
```

**必须遵守的三条**:

1. **幂等**:跑 N 次结果一致
2. **只改 `spec` 和 `status`**:不要在调谐里改 label/annotation(不会触发,但也别依赖)
3. **清理放 Finalizer**

---

## 4. 生成 CRD / RBAC / 部署清单

```bash
# 全局安装 CLI
dotnet tool install --global KubeOps.Cli
# 或在项目内
dotnet new tool-manifest && dotnet tool install --local KubeOps.Cli

# 生成 CRD + RBAC + deployment + kustomization
kubeops generate

# 安装到集群(装 CRD、RBAC、Operator Deployment)
kubeops install

# 卸载
kubeops uninstall
```

生成的 `config/` 目录:

```
config/
├── crd/              # CRD
├── rbac/             # Role / ClusterRole / RoleBinding(从 [EntityRbac] 推导)
├── deployment.yaml   # Operator 自身
├── kustomization.yaml
└── namespace.yaml
```

**RBAC 从代码推导**:在 controller 上加 `[EntityRbac(typeof(V1DemoEntity), Verbs = RbacVerb.All)]`,
生成器会据此产出对应的权限规则 —— 这是"最小权限"能被真正执行的前提,而不是靠人肉维护 YAML。

---

## 5. 用 GitHub Actions 打通"push → 部署"

### 5.1 CI 侧:构建镜像 + 更新 CR

```yaml
# .github/workflows/deploy.yml
name: build-and-deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write        # 用 Workload Identity 换取集群凭据
    steps:
      - uses: actions/checkout@v4

      - name: Build & push image
        env:
          REGISTRY: ghcr.io/${{ github.repository }}
          TAG: ${{ github.sha }}
        run: |
          echo "$REGISTRY:$TAG" >> $GITHUB_ENV
          docker buildx build --push -t $REGISTRY:$TAG .

      - name: Update custom resource (期望状态)
        run: |
          kubectl patch v1demoentity demo \
            --type=merge \
            -p "{\"spec\":{\"image\":\"${{ env.REGISTRY }}:${{ env.TAG }}\"}}" \
            -n my-operator
```

要点:

- **镜像 tag 用 commit SHA**,不要 `latest` —— 要能精确回滚
- CI 只做两件事:**推镜像** + **更新 CR 的 spec**,不执行任何集群业务逻辑
- `kubectl patch` 改的是 `spec`,会触发 Operator 调谐;改 `status` 不会

> **凭据方式**:生产环境别把 kubeconfig 塞进 Secrets。用
> [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
> 或 [GitHub OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
> 让 CI 以**最小权限**短时身份访问集群,只允许 patch CR。
> (本仓库相关实践:`gcp/gke/`、`skills/gke-workload-identity/`)

### 5.2 Operator 侧:把 CR 翻译成 Deployment

CI 只更新了 CR,**真正的 Deployment 是 Operator 调谐出来的** —— 这就是 Operator 驱动范式的分工。

---

## 6. 本地验证(不用等 CI)

```bash
# 起一个本地集群
kind create cluster --name kubeops-demo

# 安装 Operator
kubeops install

# 提交一个 CR
kubectl apply -f - <<'EOF'
apiVersion: demo.kubeops.dev/v1
kind: V1DemoEntity
metadata:
  name: demo
  namespace: default
spec:
  deploymentName: demo
  replicas: 2
  image: nginx:1.27
EOF

# 看 Operator 调谐出了什么
kubectl get deployments                # demo 出现了
kubectl get pods                       # demo 的 pod 起来了
kubectl rollout status deployment/demo # Ready
```

改一下 CR 再看:

```bash
kubectl patch v1demoentity demo --type=merge -p '{"spec":{"image":"nginx:1.28"}}' -n default
kubectl rollout status deployment/demo  # 滚动更新
```

验证幂等与漂移自愈:

```bash
kubectl delete deployment demo          # 手动删,模拟漂移
kubectl get deployment demo             # Operator 会把它重建回来
```

---

## 7. 运维检查清单

| 检查项 | 命令 / 方法 |
|---|---|
| Operator Pod 是否健康 | `kubectl get pods -n <operator-ns>` |
| CRD 是否注册成功 | `kubectl get crd \| grep -i demo` |
| 调谐有没有在跑 | 看 OpenTelemetry 指标:调谐队列深度、reconciler 耗时、watcher 事件数 |
| 有没有报错 | `kubectl describe v1demoentity demo` 看 events;Operator 日志 |
| 权限够不够 | `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>` |
| 多副本是否重复调谐 | 确认 `LeaderElectionType.Single` 已配置 |
| CRD 升级安全 | 只新增版本;跨版本迁移配 conversion webhook;用真实对象副本回归 |

---

## 8. .NET Aspire 用户:Operator 也能当 AppHost 资源

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var k8s = builder.AddKubernetesEnvironment("k8s")
    .WithHelm(helm => helm
        .WithChartName("my-operator")
        .WithReleaseName("my-operator")
        .WithNamespace("operator-system"));

builder.AddKubeOps<Projects.MyOperatorProject>("operator")
    .RunWithKubernetes(k8s)
    .PublishAsKubernetesOperator(k8s);

builder.Build().Run();
```

```bash
aspire run --project src/MyApp.AppHost/MyApp.AppHost.csproj
aspire publish --project src/MyApp.AppHost/MyApp.AppHost.csproj --output-path ./artifacts/k8s
```

---

## 9. 常见报错与定位

| 现象 | 原因 | 处理 |
|---|---|---|
| `no matches for kind "V1DemoEntity"` | CRD 没装 | `kubeops install` 或 `kubectl apply -f config/crd/` |
| Operator 一直 `ImagePullBackOff` | 镜像 tag 错 / 缺 imagePullSecret | 检查 tag 与 `spec.imagePullSecrets` |
| 资源没被创建,日志也没错 | 调谐条件没满足 | 临时加 `logger.LogInformation` 打印 entity.Spec |
| 调谐无限循环 | 在调谐里改了会被去重外的字段 | 检查是否在改 spec(改 spec 本身是允许的,但要保证收敛) |
| 删除 CR 后 Deployment 残留 | 没写 Finalizer | 实现 `IEntityFinalizer<TEntity>` 并确保幂等 |
| CR 改了没反应 | 改的是 status / annotation | 改 `spec`;或调整 Reconcile Strategy |
| `KOG001` 编译错误 | 同时声明了 LabelSelector 和 FieldSelector | 拆成两个 controller |

---

## 参考

- Getting Started:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/getting-started>
- Examples:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/examples>
- CLI:<https://github.com/dotnet/dotnet-operator-sdk/blob/main/src/KubeOps.Cli/README.md>
- Troubleshooting:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/troubleshooting>
- .NET Aspire 集成:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/aspire>
- 官方示例仓库:<https://github.com/dotnet/dotnet-operator-sdk/tree/main/examples>
