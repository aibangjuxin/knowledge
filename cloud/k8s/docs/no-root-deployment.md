# summary
在 GKE（Google Kubernetes Engine）中以非 root 用户运行 Deployment 时，需要注意以下几点：

1. 应在容器镜像中创建一个非 root 用户，并在容器启动时切换到该用户的身份来运行应用程序。
2. 应保证应用程序和容器中其他相关文件夹的权限为非 root 用户。
3. 在配置 Deployment 的时候需要指定运行该 Deployment 的用户为非 root 用户。
4. 在 Pod 安全策略中指定运行容器的用户为非 root 用户。

具体实现方法如下：

1. 应在容器镜像中创建一个非 root 用户，并在容器启动时切换到该用户的身份来运行应用程序。

与 Dockerfile 中创建非 root 用户类似，需要在容器镜像中创建一个非 root 用户，并在启动容器时以该用户的身份启动应用程序。可以在 Dockerfile 中使用 USER 命令设置容器的默认用户，例如：

RUN useradd -m myuser
USER myuser

然后再使用 CMD 或 ENTRYPOINT 命令指定需要运行的应用程序。

1. 应保证应用程序和容器中其他相关文件夹的权限为非 root 用户。

容器镜像中应用程序和其他相关文件夹的权限也应该为非 root 用户，以确保在切换到非 root 用户身份后，容器能够正常读写相关文件。可以使用 chown 命令修改文件或文件夹的所有者和权限，例如：

RUN chown -R myuser:myuser /app

1. 在配置 Deployment 的时候需要指定运行该 Deployment 的用户为非 root 用户。

在配置 Deployment 时，需要在 spec.template.spec.containers.securityContext 字段中指定运行该 Deployment 的用户为非 root 用户。例如：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      securityContext:
        runAsUser: 1000
      containers:
        - name: my-container
          image: my-image
          ports:
            - containerPort: 8080
```
在上述配置中，runAsUser: 1000 字段指定运行该 Deployment 的用户为 UID 为 1000 的用户。

1. 在 Pod 安全策略中指定运行容器的用户为非 root 用户。

如果使用了 Pod 安全策略（Pod Security Policy），则需要在 Pod 安全策略中指定运行容器的用户为非 root 用户。例如：
```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: my-psp
spec:
  runAsUser:
    rule: 'MustRunAsNonRoot'
```
在上述配置中，runAsUser 字段指定容器必须以非 root 用户的身份运行。需要在使用该 Pod 安全策略的 Pod 中指定一个非 root 用户来运行容器。

在GKE中以非root用户运行Deployment需要注意以下几点:
# 指定非root用户
在Deployment的spec中指定securityContext,设置runAsUser为非root用户ID:
```yaml
spec:
  securityContext:
    runAsUser: 1000  # 非root用户ID
```
# 设置文件系统权限
由于默认挂载的emptyDir是777权限,需要在volume中设置fsGroup来指定文件的group ID,并设置权限为用户可读写:
```yaml
volumeMounts:
  - name: cache-volume
    mountPath: /cache
    fsGroup: 1000  # 和runAsUser的ID相同

volumes:
  - name: cache-volume
    emptyDir: {}
```
# 设置image的USER指令
在Dockerfile中使用USER指令设置启动用户,以避免在 image build 过程中创建 root 拥有的文件:
Dockerfile
USER 1000  # 和runAsUser的ID相同
# 确保容器内进程可执行
使用initContainer设置权限,确保容器内关键进程对非root用户可执行:
```yaml
initContainers:
  - name: init-permissions
    image: busybox:1.30
    command: ["sh", "-c", "chown -R 1000:1000 /some/dir"]
    volumeMounts:
    - name: some-volume
      mountPath: /some/dir
```
# 确保Secret可读取
当Pod使用Secret时,需要设置fsGroup来使Secret中的文件的group ID与runAsUser的ID相同,并设置权限为用户可读:
```yaml
volumes:
  - name: secret-volume
    secret:
      secretName: mysecret
volumeMounts:
  - name: secret-volume
    mountPath: /secrets
    fsGroup: 1000  # 和runAsUser的ID相同
```

Here are some things to pay attention to when running deployment as a non root user in GKE:


## Things to pay attention to when running deployment as a non root user in GKE

* **Use a service account that has the appropriate permissions.** The service account you use to run the deployment must have the appropriate permissions to access the Kubernetes API. You can create a service account with the necessary permissions using the `gcloud` command-line tool.
* **Use a Pod Security Policy (PSP) to restrict the capabilities of the pods that are deployed.** A PSP can be used to restrict the capabilities of pods, such as the ability to mount volumes or run privileged containers. This can help to prevent unauthorized users from gaining access to your cluster.
* **Use a role-based access control (RBAC) policy to control who can access the Kubernetes API.** An RBAC policy can be used to control who can access the Kubernetes API, and what actions they can take. This can help to prevent unauthorized users from making changes to your cluster.
* **Monitor your cluster for suspicious activity.** It is important to monitor your cluster for suspicious activity, such as pods that are running unauthorized processes or that are consuming excessive resources. You can use the Kubernetes dashboard or a third-party monitoring tool to monitor your cluster.

By following these tips, you can help to protect your GKE cluster from unauthorized users.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: simple-deployment
spec:
  selector:
    matchLabels:
      app: simple
  replicas: 1
  template:
    metadata:
      labels:
        app: simple
    spec:
      containers:
      - name: simple
        image: busybox
        command: ["/bin/sh", "-c", "echo 'Hello, world!'"]
        securityContext:
          runAsUser: 1000
```
# need deployment setting securityContext: runAsUser: ?
The `runAsUser` field in the `securityContext` object of a deployment spec specifies the user ID that the container will run as. The value of this field must be a positive integer. If the field is omitted, the container will run as root.

For example, the following deployment spec will create a deployment with a single pod that runs the nginx image as user 1000:

```yanl
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        securityContext:
          runAsUser: 1000
```

The `runAsUser` field can also be used to run a container as a group. To do this, you can specify the group ID in the field, followed by a colon and the user ID. For example, the following deployment spec will create a deployment with a single pod that runs the nginx image as user 1000 in group 1000:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        securityContext:
          runAsUser: 1000:1000
```

The `runAsUser` field is a powerful way to control the permissions that a container has on the host. By specifying a non-root user for the container, you can help to prevent unauthorized access to the host's resources.

在 GKE（Google Kubernetes Engine）中以非 root 用户运行 Deployment 时，需要注意以下事项：

1. **用户权限**：确保非 root 用户具有足够的权限来创建和管理 Deployment。在 GKE 中，可以通过将用户添加到适当的 RBAC（Role-Based Access Control）角色或集群角色来授予所需的权限。

2. **容器权限**：非 root 用户默认没有权限在容器内以 root 身份运行。如果 Deployment 中的容器需要以 root 身份运行，请确保在容器的 SecurityContext 中设置 `runAsUser: 0`。

3. **镜像准备**：在创建 Deployment 之前，确保使用的容器镜像可以在非 root 用户下正常运行。这可能需要对镜像进行调整，以确保它适用于以非 root 用户身份运行。

4. **资源限制**：非 root 用户可能受到一些安全限制，因此在创建 Deployment 时，需要确保为该用户分配足够的资源限制，以避免资源不足导致的问题。

5. **日志和监控**：确保非 root 用户具有适当的权限来查看和访问与 Deployment 相关的日志和监控信息。这可以通过为用户分配适当的角色或配置日志和监控服务来实现。

当以非 root 用户运行 Deployment 时，可以通过在 Deployment 的 Pod 模板中设置 `securityContext` 字段来指定容器的运行用户。以下是一个示例的 Deployment YAML 文件，其中包含了一些特殊设置：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      securityContext:
        runAsUser: 1000    # 设置容器运行的用户 ID
      containers:
        - name: my-container
          image: my-image
          securityContext:
            allowPrivilegeEscalation: false   # 禁止特权升级
            capabilities:
              drop:
                - ALL    # 丢弃所有特权
          ports:
            - containerPort: 80
```

在上述示例中，我们设置了以下特殊设置：

- `securityContext.runAsUser: 1000`：将容器运行的用户 ID 设置为 1000，即非 root 用户的 UID。可以根据需要修改为适当的用户 ID。

- `securityContext.allowPrivilegeEscalation: false`：禁止特权升级，防止容器内的进程获取额外的特权权限。

- `securityContext.capabilities.drop: [ALL]`：丢弃容器的所有特权，以增加安全性。

这些设置可以根据您的需求进行调整，确保适合您的应用程序和安全要求。

`securityContext` 并非必须设置的字段，但在某些情况下，它可以提供额外的安全性和控制选项。它用于定义 Pod 或容器的安全上下文配置。

以下是一些常见的用例，可以考虑在 `securityContext` 中进行设置：

1. **非 root 用户**：如果您希望在非 root 用户下运行容器，可以使用 `securityContext` 中的 `runAsUser` 字段指定非 root 用户的用户 ID。

2. **特权限制**：通过设置 `securityContext` 中的 `allowPrivilegeEscalation` 字段为 `false`，可以禁止容器内的进程获取额外的特权权限。

3. **特权丢弃**：使用 `securityContext` 中的 `capabilities.drop` 字段可以丢弃容器的特权，防止容器内的进程执行危险的操作。

4. **安全上下文共享**：如果您的 Deployment 中的多个容器需要共享相同的安全上下文配置，您可以在 Pod 模板的顶层设置 `securityContext`，从而避免在每个容器中重复定义。

请注意，这些设置取决于您的具体需求和安全策略。在某些情况下，根据您的应用程序和环境，可能并不需要进行特殊的 `securityContext` 设置。因此，在决定是否设置 `securityContext` 时，建议根据您的需求进行评估和决策。

No, securityContext does not have to be set. However, it is strongly recommended that you do set it. By setting securityContext, you can help to prevent unauthorized access to the host's resources and prevent containers from running with excessive privileges.

The securityContext field contains a number of settings that control the permissions that a container has on the host. Some of the most important settings include:

* runAsUser: This setting specifies the user ID that the container will run as.
* fsGroup: This setting specifies the group ID that the container will run as.
* capabilities: This setting specifies the capabilities that the container will have.
* privileged: This setting specifies whether the container will run with root privileges.

If you do not set securityContext, the container will run as root by default. This means that the container will have full access to the host's resources. This can be a security risk, as it allows the container to access sensitive data or to damage the host.

It is important to note that securityContext is not a silver bullet. It is just one layer of security that you should use to protect your Kubernetes cluster. You should also use other security measures, such as Pod Security Policies, RBAC, and network security, to protect your cluster.

Here are some additional tips for using securityContext:

* Use a non-root user for all containers. This will help to prevent unauthorized access to the host's resources.
* Set the fsGroup to the same value as runAsUser. This will help to prevent containers from modifying files that they should not be able to modify.
* Limit the capabilities that containers have. This will help to prevent containers from performing actions that they should not be able to perform.
* Do not set privileged to true. This will allow containers to run with root privileges, which can be a security risk.

By following these tips, you can help to improve the security of your Kubernetes cluster.


在GKE中运行非root Deployment,设置securityContext是非常推荐的,但不绝对必须。
如果不设置securityContext,Deployment会默认使用root用户运行,这会有以下影响:
1. 容器内进程和文件默认都是root用户所有,这增加了安全风险。
2. 当Pod使用emptyDir,Secret等存储卷时,由于默认权限是777,导致root用户可以读取和写入非root用户的数据。
3.  without a securityContext, all files created by the build or run stages are owned by root and cannot be read by non-root users.
所以,推荐至少设置securityContext的runAsNonRoot为true,禁止用root用户运行容器:
yaml
securityContext:
  runAsNonRoot: true
如果要用特定非root用户运行,则设置runAsUser:
yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
除此之外,根据你的应用需要,可能还需要设置其他选项,比如fsGroup,seLinuxOptions等,来控制文件权限、版本号等。
总之,设置securityContext可以带来更高的安全性和容器隔离性,所以在GKE中运行非root Deployment时是非常推荐的配置。但如果应用本身设计已经考虑到安全隐患,或者出于其他原因实在不能设置,也不会建立根本阻止Deployment运行。
所以,可以这样理解:推荐尽量设置,但不绝对必须。根据应用的具体需求和风险来斟酌设置相关的securityContext配置

When running deployments as a non-root user in GKE (Google Kubernetes Engine), it is important to note the following:

* **Use a service account that has the appropriate permissions.** The service account you use to run the deployment must have the appropriate permissions to access the Kubernetes API. You can create a service account with the necessary permissions using the `gcloud` command-line tool.
* **Use a Pod Security Policy (PSP) to restrict the capabilities of the pods that are deployed.** A PSP can be used to restrict the capabilities of pods, such as the ability to mount volumes or run privileged containers. This can help to prevent unauthorized users from gaining access to your cluster.
* **Use a role-based access control (RBAC) policy to control who can access the Kubernetes API.** An RBAC policy can be used to control who can access the Kubernetes API, and what actions they can take. This can help to prevent unauthorized users from making changes to your cluster.
* **Monitor your cluster for suspicious activity.** It is important to monitor your cluster for suspicious activity, such as pods that are running unauthorized processes or that are consuming excessive resources. You can use the Kubernetes dashboard or a third-party monitoring tool to monitor your cluster.

By following these tips, you can help to protect your GKE cluster from unauthorized users.

Additionally, here are some specific things to keep in mind when running deployments as a non-root user in GKE:

* **Use the `runAsUser` field in the `securityContext` object of the deployment spec to specify the user ID that the container will run as.** The value of this field must be a positive integer. If the field is omitted, the container will run as root.
* **Use the `fsGroup` field in the `securityContext` object of the deployment spec to specify the group ID that the container will run as.** This will help to prevent containers from modifying files that they should not be able to modify.
* **Limit the capabilities that containers have.** This will help to prevent containers from performing actions that they should not be able to perform.
* **Do not set `privileged` to true.** This will allow containers to run with root privileges, which can be a security risk.

By following these tips, you can help to improve the security of your GKE deployments

这里是在 GKE 上部署一个 no-root 容器的 Markdown 格式说明:

# 在 GKE 上部署 no-root 容器

## 创建 Kubernetes 集群

使用 Google Cloud SDK 创建一个启用 Pod 安全策略的 GKE 集群:

bash
gcloud container clusters create my-cluster --pod-security-policy


## 编写 Pod 安全策略 YAML 文件

创建一个 pod-security-policy.yaml 文件:

yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: nonroot
spec:
  privileged: false 
  runAsUser: 
    rule: MustRunAsNonRoot
  fsGroup:
    rule: MustRunAs 
    ranges:
    - max: 65535   


这个策略要求 Pod 必须以非 root 用户运行,禁止特权模式。

## 创建 Pod 安全策略

使用 kubectl 命令创建 Pod 安全策略:

bash
kubectl apply -f pod-security-policy.yaml


## 编写 Deployment YAML 文件

Deployment YAML 文件需要添加 podSecurityPolicy 指定使用 nonroot 这个 Pod 安全策略:

yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      securityContext:
        runAsNonRoot: true  
      containers:
      - name: my-app
        image: http://gcr.io/my-project/my-app
      podSecurityPolicy:
        name: nonroot 
          

## 部署应用

使用 kubectl 命令部署应用:

bash
kubectl apply -f Deployment.yaml


至此,我们完成了在 GKE 上使用 Pod 安全策略部署一个 no-root 容器的全过程。这可以确保应用运行在一个更加安全隔离的环境中。.
