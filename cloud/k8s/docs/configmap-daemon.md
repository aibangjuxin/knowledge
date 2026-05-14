- configmap 
- 1 先删除configmap 
- 2 确保daemonset都生效
```bash
for podname in `kubectl get pod -n kube-system|grep ip-masq-agent|awk '{print$1}'`;do kubectl exec $podname -n kube-system -- cat /etc/config/ip-masq-agent;done 
```
- 3 Tesing make sure is ok
kubectl exec `kubectl get pod -n cap-core |grep pod-name|awk '{print$1}'` -n cap-core -- curl -v fqdn:22
- 4 apply new configmap  ip-masq.sh
- 5 验证这个配置文件都存在在POD里面
for podname in `kubectl get pod -n kube-system|grep ip-masq-agent|awk '{print$1}'`;do kubectl exec $podname -n kube-system -- cat /etc/config/ip-masq-agent;done
- 6 Tesing 22 
```bash
 kubectl describe cm ip-masq-agent -n kube-system && kubectl exec `kubectl get pod -n cap-core |grep pod-name|awk '{print$1}'` -n cap-core -- curl -v fqdn:22
```
在Kubernetes中，如果你想在DaemonSet中使用ConfigMap并使其生效，以下是一些建议的操作步骤：

1. 创建一个ConfigMap对象，其中包含你想要在DaemonSet中使用的配置数据。你可以使用`kubectl create configmap`命令或通过定义一个YAML文件来创建ConfigMap。

2. 在DaemonSet的Pod模板中，将ConfigMap挂载为一个卷。你可以使用`volumeMounts`字段指定将ConfigMap挂载到Pod的哪个路径下。

3. 在Pod模板的卷配置中，指定挂载的ConfigMap的名称和路径。你可以使用`volumes`字段来定义这个卷。

4. 在DaemonSet的Pod模板的`spec`部分中，定义`volumeMounts`和`volumes`字段，以将ConfigMap挂载到Pod中。

5. 在DaemonSet的更新策略中，确保配置更新会触发Pod的重启。你可以使用`rollingUpdate`策略并设置`maxUnavailable`和`maxSurge`字段来控制更新过程中的Pod可用性。

验证ConfigMap是否已生效的一种方法是检查DaemonSet中的Pod是否重新启动以应用更新的配置。你可以使用以下步骤来验证：

1. 运行`kubectl get daemonset <daemonset-name>`命令来获取DaemonSet的详细信息，确保它处于运行状态。

2. 使用`kubectl describe daemonset <daemonset-name>`命令来查看DaemonSet的描述信息，确认Pod的重启策略是否已配置为使更新的ConfigMap生效。

3. 运行`kubectl get pods -l <label-selector>`命令，其中`<label-selector>`是用于选择DaemonSet中Pod的标签选择器，以获取Pod的详细信息。

4. 检查Pod的事件和日志，确保Pod已重新启动并成功应用了更新的ConfigMap。

如果你想对DaemonSet的Pod进行重启操作，你可以使用以下步骤：

1. 运行`kubectl get daemonset <daemonset-name>`命令来获取DaemonSet的详细信息，确保它处于运行状态。

2. 运行`kubectl rollout restart daemonset <daemonset-name>`命令来重启DaemonSet中的所有Pod。

请注意，重启操作会使DaemonSet中的所有Pod重新创建，因此确保在进行此操作时没有不可接受的服务中断。

这些是使用ConfigMap在DaemonSet中进行配置更改和验证的一些建议操作。你可以根据你的具体需求和环境进行适当调整。
# configmap
对Kubernetes configmap资源的修改要想生效,通常有以下几种方法:
- 1. 重启使用该ConfigMap的Pod。这是最简单的方法,修改ConfigMap后,Pod重启会自动加载新的ConfigMap,实现修改生效。
- 2. 使用kubectl rolling-update重启Deployment。如果ConfigMap被Deployment引用,可以对Deployment进行rolling update,这将重启Pod,实现ConfigMap修改生效。
- 3. 使用volumeMount挂载ConfigMap作为volume。Pod启动时会使用volume中的最新ConfigMap,所以修改后无需重启Pod,直接生效。
- 4. 使用subPath挂载ConfigMap中的特定文件。与方法3类似,直接生效。
- 5. 使用envFrom引用ConfigMap。将引用了ConfigMap的环境变量更新到最新值,也能实现直接生效。
- 综上,对于DaemonSet也是一样,最简单的就是重启DaemonSet或其管理的Pod。但是,有几点注意事项:
    - 1. 由于DaemonSet控制器会维持指定数量的Pod副本,重启DaemonSet不会重启所有Pod,有可能导致部分Pod使用旧的ConfigMap。这种情况下,最好重启DaemonSet控制器所在的Node节点。
    - 2. 如果DaemonSet使用statefulset,重启Pod可能会导致状态丢失,需要谨慎操作。
    - 3. 使用volumeMount、subPath或envFrom等方法可以避免重启Pod,直接生效ConfigMap修改。但需要在DaemonSet的Pod spec中添加相应的配置。
    - 4. 对Node进行滚动更新也可以重启DaemonSet Pod,实现ConfigMap修改生效。但存在上述状态丢失等风险,也需要加入恰当配置。
    所以,总体来说,对DaemonSet使用ConfigMap,如果要修改ConfigMap并直接生效,除非使用volume等直接生效的方法,否则最佳方式还是尽量避免大范围重启Pod。你可以:
- 1. 只重启特定Node节点
- 2. 只重启部分Pod,逐步达到全部生效 
- 3. 使用DaemonSet的updateStrategy进行滚动更新



### Kubernetes中,DaemonSet使用ConfigMap

1. 使用volumeMount或subPath直接挂载ConfigMap。这种方式修改ConfigMap后可以直接生效,无需重启Pod。
配置示例:
```yaml
volumes:
- name: config
  configMap:
    name: example-config

volumeMounts:
- name: config
  mountPath: /etc/config
```
2. 使用envFrom引用ConfigMap中的环境变量。修改ConfigMap后,环境变量的值会自动更新,实现直接生效。
配置示例:
```yaml 
envFrom:
- configMapRef:
    name: example-config
```
3. 选择性重启部分Pod或Node。比如根据ConfigMap修改的内容,只重启相关Pod或只重启特定Node上的Pod。这可以避免大范围重启导致的问题。
4. 启用DaemonSet的滚动更新。使用kubectl rolling-update重启DaemonSet。这将逐渐重启Pod,避免同时重启大量Pod。
```bash
kubectl rolling-update daemonset example-daemonset
```

5. 重启DaemonSet控制器。直接重启管理DaemonSet的控制器,这将导致DaemonSet创建新的Pod,默认会用最新的ConfigMap。但要考虑状态丢失问题。
```bash 
kubectl get pod -l k8s-app=kube-daemonset-controller -n kube-system -o name | cut -d'/' -f2 | xargs kubectl delete pod -n kube-system
```
6. 备份并修订原ConfigMap YAML。这避免了直接修改现有ConfigMap,而是重新创建一个,保证DaemonSet中的所有Pod都使用新的ConfigMap。但前提是ConfigMap没有被其他工作负载引用。
以上就是我对DaemonSet使用ConfigMap并动态修改生效的几点建议。总体来说,推荐尽量采用1-3方式实现优雅修改,避免大范围重启Pod带来的问题。但对于ConfigMap修改频繁或修改比较彻底的情况,4-6方式也可选择。

ip-masq-agent是Kubernetes集群的一个addon,用于在集群中配置IP伪装(masquerade),使集群内部Pod可以访问外部网络。
重启ip-masq-agent Pod需要注意以下几点:
1. ip-masq-agent使用DaemonSet运行,重启Pod会导致网络中断,需要谨慎操作。
2. ip-masq-agent需要以hostNetwork模式运行,并且是类型为hostPort的服务。重启时可能会占用Node端口,导致服务短暂不可用。
3. ip-masq-agent绑定了Node IP,修改配置需要谨慎,以免导致Node IP变更等问题。
所以,重启ip-masq-agent Pod的安全建议如下:
1. 启用ip-masq-agent的滚动更新。使用kubectl rolling-update ip-masq-agent-ds命令,这将逐步重启ip-masq-agent Pod,避免大面积网络中断。
```bash
kubectl rolling-update daemonset ip-masq-agent-ds
```
2. 只重启部分Node节点。如果ip-masq-agent的配置或镜像有更新,建议只重启部分Node,然后观察一段时间确认无问题后再重启其余Node。这也可以避免集群范围的网络中断。
