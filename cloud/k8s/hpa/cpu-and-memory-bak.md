
- [Horizontal Pod Autoscaler (HPA) 详解](#horizontal-pod-autoscaler-hpa-详解)
  - [公式：](#公式)
  - [describe information](#describe-information)
    - [分析 CPU](#分析-cpu)
    - [分析 Memory](#分析-memory)
    - [结论](#结论)
- [HPA 配置](#hpa-配置)
  - [CPU 扩容和缩容的触发条件](#cpu-扩容和缩容的触发条件)
    - [1. 从1个副本扩容到2个副本的条件 825%](#1-从1个副本扩容到2个副本的条件-825)
    - [2. 从2个副本扩容到3个副本的条件 825%](#2-从2个副本扩容到3个副本的条件-825)
    - [3. 从3个副本缩容到2个副本的条件 500%](#3-从3个副本缩容到2个副本的条件-500)
    - [4. 从2个副本缩容到1个副本的条件 375%](#4-从2个副本缩容到1个副本的条件-375)
    - [验证结论](#验证结论)
  - [Memory扩容和缩容的触发条件](#memory扩容和缩容的触发条件)
    - [1. 从1个副本扩容到2个副本的条件 88%](#1-从1个副本扩容到2个副本的条件-88)
    - [2. 从2个副本扩容到3个副本的条件 88%](#2-从2个副本扩容到3个副本的条件-88)
    - [3. 从3个副本缩容到2个副本的条件 53%](#3-从3个副本缩容到2个副本的条件-53)
    - [4. 从2个副本缩容到1个副本的条件 40%](#4-从2个副本缩容到1个副本的条件-40)
    - [验证结论](#验证结论-1)
  - [Memory扩容和缩容的触发条件 averageValue 800Mi](#memory扩容和缩容的触发条件-averagevalue-800mi)
    - [1.从1个副本扩容到2个副本的条件 880Mi](#1从1个副本扩容到2个副本的条件-880mi)
    - [2. 从2个副本扩容到3个副本的条件 880Mi](#2-从2个副本扩容到3个副本的条件-880mi)
    - [3.从3个副本缩容到2个副本的条件 533Mi](#3从3个副本缩容到2个副本的条件-533mi)
    - [4.从2个副本缩容到1个副本的条件 400Mi](#4从2个副本缩容到1个副本的条件-400mi)
- [关键点:](#关键点)


# Horizontal Pod Autoscaler (HPA) 详解

Horizontal Pod Autoscaler (HPA) 通过监控 Pod 的资源平均利用率（如 CPU、内存等）来动态调整 Pod 的副本数量。其基本工作原理如下：

## 公式：

$$
\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil
$$

- split line 

$$
\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil
$$


其中，ceil 表示向上取整。

## describe information
- `kubectl describe hpa aibang-deployment-hpa -n aibang`
```bash
Name:                   aibang-deployment-hpa
Namespace:              aibang
Labels:                 <none>
Annotations:            <none>
CreationTimestamp:      Mon, 20 Mar 2023 10:47:18 +0800
Reference:              Deployment/aibang-deployment
Metrics:                ( current / target )
  resource cpu on pods (as a percentage of request) 15%(15m)/750%
  resource memory on pods (as a percentage of request) 58%(367126528)/80%
Min replicas:           1
Max replicas:           5
Replicas:               2 current / 2 desired
Conditions:
  Type            Status  Reason              Message
  ----            ------  ------              -------
  AwaitingScaled  
True   InitialDelay  Waiting for initial metrics to be available
  ScalingActive   True    New size: 2; reason: CPU utilization (percentage of request) above target
Events:           <none>
```

- kubectl get hpa aibang-deployment-hpa -n aibang
```bash
NAME                     REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
aibang-deployment-hpa   Deployment/aibang-deployment   15%/750%, 58%/80%   1         5         2         10m
```

根据kubernets官方文档,如果创建Horizontal Pod Autoscaler时 指定了多个指标，那么会按照每个指标分别计算扩缩的副本数，然后选择最大的那个值进行扩缩
,比如我的场景中,内存计算后为最大值,因此理论上进行扩缩,但取最大值为2,因此副本数为2,保持不变


对于我上面的配置，HPA 将根据 CPU 和内存的平均利用率来调整 Pod 的副本数量。

### 分析 CPU
- 从2个副本缩容到1个副本的条件 375%

$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{375}{750} \right) \right\rceil = \left\lceil 0.5 \right\rceil = 1
$$


所以，当 CPU 平均利用率低于 375% 时，HPA 将删除一个副本。

### 分析 Memory
- 从2个副本缩容到1个副本的条件 40%

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{40}{80} \right) \right\rceil = \left\lceil 0.5 \right\rceil = 1
$$


所以，当内存平均利用率低于 40% 时，HPA 将删除一个副本。


### 结论
虽然CPU 平均利用率低于375%，但内存平均利用率为58%，因此HPA将选择内存平均利用率的计算结果作为最终的副本数，即2个副本。

# HPA 配置

```yaml
apiVersion: autoscaling/v1
r
metadata:
  name: aibang-deployment-hpa
  namespace: aibang
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: aibang-deployment
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 750
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## CPU 扩容和缩容的触发条件

### 1. 从1个副本扩容到2个副本的条件 825%

- **当前副本**：1
- **设定目标 CPU 平均利用率**：750%
- **扩容条件**：750% * 1.1 = 825%

具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{825}{750} \right) \right\rceil = \left\lceil 1.1 \right\rceil = 2
$$


所以，当 CPU 平均利用率超过 825% 时，HPA 将创建第二个副本。

### 2. 从2个副本扩容到3个副本的条件 825%

- **当前副本**：2
- **设定目标 CPU 平均利用率**：750%
- **扩容条件**：750% * 1.1 = 825%

具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{825}{750} \right) \right\rceil = \left\lceil 2.2 \right\rceil = 3
$$


所以，当 CPU 平均利用率超过 825% 时，HPA 将创建第三个副本。

### 3. 从3个副本缩容到2个副本的条件 500%

- **当前副本**：3
- **设定目标 CPU 平均利用率**：750%
- **缩容条件**：750% * 0.9 = 675%

具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{675}{750} \right) \right\rceil = \left\lceil 2.7 \right\rceil = 3
$$


所以，当 CPU 平均利用率低于 675% 时，HPA 将不会立即删除一个副本。

再看下如果是500%的情况：

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{500}{750} \right) \right\rceil = \left\lceil 3 \times 0.6666 \right\rceil = 2
$$


所以，当 CPU 平均利用率低于 500% 时，HPA 将删除一个副本，副本数变为 2。


### 4. 从2个副本缩容到1个副本的条件 375%

- **当前副本**：2
- **设定目标 CPU 平均利用率**：750%
- **缩容条件**：750% * 0.9 = 675%

具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{675}{750} \right) \right\rceil = \left\lceil 2 \times 0.9 \right\rceil = 2
$$


所以，当 CPU 平均利用率低于 675% 时，HPA 将不会立即删除一个副本。

再看下如果是500%的情况：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{500}{750} \right) \right\rceil = \left\lceil 2 \times 0.6666 \right\rceil = 2
$$


所以，当 CPU 平均利用率低于 500% 时，HPA 将不会立即删除一个副本。

所以再看下如果是375%的情况:

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{375}{750} \right) \right\rceil = \left\lceil 2 \times 0.5 \right\rceil = 1
$$


所以，当 CPU 平均利用率低于 375% 时，HPA 将删除一个副本，副本数变为 1。


### 验证结论

根据上面的分析和计算，您的结论是正确的：

1. 从1个副本扩容到2个副本的条件是 CPU 平均利用率超过 825%。
2. 从2个副本扩容到3个副本的条件是 CPU 平均利用率超过 825%。
3. 从3个副本缩容到2个副本的条件是 CPU 平均利用率低于 500%。
4. 从2个副本缩容到1个副本的条件是 CPU 平均利用率低于 375%。

## Memory扩容和缩容的触发条件

公式：desiredReplicas = ceil[currentReplicas * (currentMetricValue / desiredMetricValue)]
其中，ceil 表示向上取整。

根据您的 HPA 配置，当内存平均利用率超过 80% 时，HPA 将尝试增加副本数量。具体来说，当内存平均利用率超过 80% 时，HPA 将根据以下公式计算所需的副本数量：


代入原始公式验证：
desiredReplicas = ceil[3 * (50 / 80)]
               = ceil[3 * 0.625]
               = ceil[1.875]
               = 2

### 1. 从1个副本扩容到2个副本的条件 88%
- **当前副本**：1
- **设定目标内存平均利用率**：80%
- **扩容条件**：80% * 1.1 = 88%
具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{88}{80} \right) \right\rceil = \left\lceil 1.1 \right\rceil = 2
$$


所以，当内存平均利用率超过 88% 时，HPA 将创建第二个副本。
例如 当内存平均利用率超过 90%的时候

$$
 \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{90}{80} \right) \right\rceil = \left\lceil 1.125 \right\rceil = 2
$$


所以，当内存平均利用率超过 90% 时，HPA 将创建第二个副本。

### 2. 从2个副本扩容到3个副本的条件 88%
- **当前副本**：2
- **设定目标内存平均利用率**：80%
- **扩容条件**：80% * 1.1 = 88%
具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{88}{80} \right) \right\rceil = \left\lceil 2.2 \right\rceil = 3
$$



### 3. 从3个副本缩容到2个副本的条件 53%
- **当前副本**：3
- **设定目标内存平均利用率**：80%
- **缩容条件**：80% * 0.9 = 72%
具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{72}{80} \right) \right\rceil = \left\lceil 2.7 \right\rceil = 3
$$


所以，当内存平均利用率低于 72% 时，HPA 将不会立即删除一个副本。

再看下如果是70%的情况：

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{70}{80} \right) \right\rceil = \left\lceil 2.625 \right\rceil = 3
$$


所以，当内存平均利用率低于 70% 时，HPA 将不会立即删除一个副本。

再看下如果是60%的情况:

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{60}{80} \right) \right\rceil = \left\lceil 2.25 \right\rceil = 3
$$


所以，当内存平均利用率低于 60% 时，HPA 将不会立即删除一个副本。


再看下如果是55%的情况:

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{55}{80} \right) \right\rceil = \left\lceil 2.0625 \right\rceil = 3
$$

所以，当内存平均利用率低于 55% 时，HPA 将不会立即删除一个副本。


再看下如果是53%的情况:

$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{53}{80} \right) \right\rceil = \left\lceil 1.9875 \right\rceil = 2
$$

所以，当内存平均利用率低于 53% 时，HPA 将删除一个副本，副本数变为 2。


### 4. 从2个副本缩容到1个副本的条件 40%
- **当前副本**：2
- **设定目标内存平均利用率**：80%
- **缩容条件**：80% * 0.9 = 72%
具体公式如下：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{72}{80} \right) \right\rceil = \left\lceil 1.8 \right\rceil = 2
$$

所以，当内存平均利用率低于 72% 时，HPA 将不会立即删除一个副本。

再看下如果是70%的情况：

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{70}{80} \right) \right\rceil = \left\lceil 1.75 \right\rceil = 2
$$


所以，当内存平均利用率低于 70% 时，HPA 将不会立即删除一个副本。

再看下如果是60%的情况:

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{60}{80} \right) \right\rceil = \left\lceil 1.5 \right\rceil = 2
$$

所以，当内存平均利用率低于 60% 时，HPA 将不会立即删除一个副本。

再看下如果是55%的情况:

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{55}{80} \right) \right\rceil = \left\lceil 1.375 \right\rceil = 2
$$

所以，当内存平均利用率低于 55% 时，HPA 将不会立即删除一个副本。

再看下如果是50%的情况:

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{50}{80} \right) \right\rceil = \left\lceil 1.25 \right\rceil = 2
$$


所以，当内存平均利用率低于 50% 时，HPA 将不会立即删除一个副本。

再看下如果是40%的情况:

$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{40}{80} \right) \right\rceil = \left\lceil 1 \right\rceil = 1
$$


所以，当内存平均利用率低于 40% 时，HPA 将删除一个副本，副本数变为 1。

### 验证结论
根据上面的分析和计算，您的结论是正确的：

1. 从1个副本扩容到2个副本的条件是 内存平均利用率超过 88%。
2. 从2个副本扩容到3个副本的条件是 内存平均利用率超过 88%。
3. 从3个副本缩容到2个副本的条件是 内存平均利用率低于 53%。
4. 从2个副本缩容到1个副本的条件是 内存平均利用率低于 40%。


## Memory扩容和缩容的触发条件 averageValue 800Mi
• 算法同样适用于
$$
\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil
$$

### 1.从1个副本扩容到2个副本的条件 880Mi

$$
 \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{880}{800} \right) \right\rceil = \left\lceil 1.1 \right\rceil = 2
$$

所以，当内存使用量超过 880Mi 时，HPA 将创建第二个副本。


### 2. 从2个副本扩容到3个副本的条件 880Mi
$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{880}{800} \right) \right\rceil = \left\lceil 2.2 \right\rceil = 3
$$

所以，当内存使用量超过 880Mi 时，HPA 将创建第三个副本。

### 3.从3个副本缩容到2个副本的条件 533Mi
$$
 \text{desiredReplicas} = \left\lceil 3 \times \left( \frac{533}{800} \right) \right\rceil = \left\lceil 1.6425 \right\rceil = 2
$$

所以，当内存使用量低于 533Mi 时，HPA 将删除一个副本，副本数变为 2。

### 4.从2个副本缩容到1个副本的条件 400Mi
$$
 \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{400}{800} \right) \right\rceil = \left\lceil 1 \right\rceil = 1
$$

所以，当内存使用量低于 400Mi 时，HPA 将删除一个副本，副本数变为 1。


# 关键点:
1. HPA 在扩容时会考虑 10% 的容差,但在缩容时会更保守。
2. 向上取整(⌈ ⌉)确保了副本数始终是整数。
3. HPA 在缩容时比扩容更谨慎,这有助于防止资源波动导致的频繁伸缩。

总的来说,您的理解是正确的,只是在具体数值的计算上需要小心。HPA 的行为确实如您所描述,会根据当前的资源使用情况动态调整副本数,以保持资源平均利用率接近目标值[1].

Citations:
[1] https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
[2] https://kubernetes.io/ja/docs/tasks/run-application/horizontal-pod-autoscale/
[3] https://kubernetes.io/ja/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
[4] https://qiita.com/sheepland/items/37ea0b77df9a4b4c9d80
[5] https://blog.studysapuri.jp/entry/2020/04/10/hpa
