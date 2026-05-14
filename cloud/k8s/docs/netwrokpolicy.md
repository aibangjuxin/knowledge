
network-policy
# Last
```mermaid
graph LR
subgraph Namespace Network policy
    subgraph Ingress
        subgraph Ingress Policy
            limitFromNamespace -.-> ingressPolicy
            limitFromLabels -.-> ingressPolicy
            allowFromX -.-> ingressPolicy 
        end
        
        subgraph Limit From Namespace
            namespaceSelector -.-> limitFromNamespace
        end
        
        subgraph Limit From Labels
           podLabels -.-> limitFromLabels
           namespaceLabels -.-> limitFromLabels 
        end

        subgraph Allow From X
           allowFromNamespace -.-> allowFromX
           allowFromIP -.-> allowFromX
           allowFromPod -.-> allowFromX    
        end
  end

  subgraph Egress 
       egressPolicy -.-> limitToExternal
       egressPolicy -.-> limitToInternal
  end  
end
```

Kubernetes命名空间范围内的网络策略基础配置,默认情况下,我的namespace禁止任何ingress and egress 让我来详细解释一下:

Namespace Network Policy子图:定义了命名空间级别的网络策略
- Ingress子图:定义了入站规则
- Ingress Policy子图:入站策略规则
- Limit From Namespace子图:基于命名空间选择器的限制源
- Limit From Labels子图:基于标签选择器的限制源
- Allow From X子图:明确允许的源
- Egress子图:定义了出站规则
- Egress Policy子图:出站策略规则
- Limit To External子图:限制到外部的出站流量
- Limit To Internal子图:限制到内部的出站流量


```mermaid
graph TD
    subgraph Basic Policies
        applyBasicPolicies --> ingressPolicy
        applyBasicPolicies --> egressPolicy
    end

    subgraph Ingress Policy
        ingressPolicy --> limitToNamespace
        ingressPolicy --> limitToLabels
        ingressPolicy --> allowFromX
    end

    subgraph Egress Policy
        egressPolicy --> limitToExternal
        egressPolicy --> limitToInternal
        egressPolicy --> denyToX
    end

    subgraph Limit To Namespace
        limitToNamespace --> namespaceSelector
    end

    subgraph Limit To Labels
        limitToLabels --> podLabels
    end

    subgraph Allow From X
        allowFromX --> allowFromNamespace
        allowFromX --> allowFromIP
        allowFromX --> allowFromPod
    end

    subgraph Deny To X
        denyToX --> denyToNamespace
        denyToX --> denyToIP
        denyToX --> denyToPod
    end
```

入站规则:限制源和允许源
出站规则:限制流向

```mermaid
graph TB
    applyBasicPolicies-->ingressPolicy
    applyBasicPolicies-->egressPolicy
    ingressPolicy-->limitToNamespace
    ingressPolicy-->limitToLabels
    ingressPolicy-->allowFromX

    egressPolicy-->limitToExternal
    egressPolicy-->limitToInternal
    egressPolicy-->denyToX

    limitToNamespace-->namespaceSelector
    limitToLabels-->podLabels

    allowFromX-->allowFromNamespace
    allowFromX-->allowFromIP
    allowFromX-->allowFromPod

    denyToX-->denyToNamespace
    denyToX-->denyToIP
    denyToX-->denyToPod
```



### dadada
```mermaid
graph TD
    subgraph Basic Policies
        applyBasicPolicies --> ingressPolicy
        applyBasicPolicies --> egressPolicy
    end

    subgraph Ingress Policy
        ingressPolicy --> limitToNamespace
        ingressPolicy --> limitToLabels
        ingressPolicy --> allowFromX
    end

    subgraph Egress Policy
        egressPolicy --> limitToExternal
        egressPolicy --> limitToInternal
    end

    subgraph Limit To Namespace
        limitToNamespace --> namespaceSelector
    end

    subgraph Limit To Labels
        limitToLabels --> podLabels
    end

    subgraph Allow From X
        allowFromX --> allowFromNamespace
        allowFromX --> allowFromIP
        allowFromX --> allowFromPod
    end
```
## this is base rule
我仅仅想要改变下箭头的方向关于 limitFromLabels 到ingressPolicy可以么 
 limitFromNamespace到ingressPolicy

```mermaid
graph TD
    subgraph Basic Policies
        applyBasicPolicies --> ingressPolicy
        applyBasicPolicies --> egressPolicy
    end

    subgraph Ingress Policy
        ingressPolicy --> limitFromNamespace
        ingressPolicy --> limitFromLabels
        ingressPolicy --> allowFromX
    end

    subgraph Egress Policy
        egressPolicy --> limitToExternal
        egressPolicy --> limitToInternal
    end

    subgraph Limit To Namespace
        limitFromNamespace --> namespaceSelector
    end

    subgraph Limit To Labels
        limitFromLabels --> podLabels
    end

    subgraph Allow From X
        allowFromX --> allowFromNamespace
        allowFromX --> allowFromIP
        allowFromX --> allowFromPod
    end
```

我期待的结果是下面这样的,能否帮我优化显示效果?
```mermaid
graph TD
    subgraph Basic Policies
        applyBasicPolicies --> ingressPolicy
        applyBasicPolicies --> egressPolicy
    end

    subgraph Ingress Policy
        limitFromNamespace --> ingressPolicy 
        limitFromLabels --> ingressPolicy
        allowFromX --> ingressPolicy
    end

    subgraph Egress Policy
        egressPolicy --> limitToExternal
        egressPolicy --> limitToInternal
    end

    subgraph Limit From Namespace
         namespaceSelector --> limitFromNamespace
    end

    subgraph Limit From Labels
        podLabels --> limitFromLabels
    end

    subgraph Allow From X
        allowFromNamespace --> allowFromX
        allowFromIP -->  allowFromX
        allowFromPod -->   allowFromX
    end
```
- 3.5
是否能重新排版下面这个结果.让其在同
```mermaid
graph LR
    subgraph Ingress Policy
        limitFromNamespace --> ingressPolicy 
        limitFromLabels --> ingressPolicy
        allowFromX --> ingressPolicy
    end

    subgraph Egress Policy
        egressPolicy --> limitToExternal
        egressPolicy --> limitToInternal
    end

        subgraph Basic Policies
        applyBasicPolicies --> ingressPolicy
        applyBasicPolicies --> egressPolicy
    end

    subgraph Limit From Namespace
        namespaceSelector --> limitFromNamespace
    end

    subgraph Limit From Labels
        podLabels --> limitFromLabels
    end

    subgraph Allow From X
        allowFromNamespace --> allowFromX
        allowFromIP --> allowFromX
        allowFromPod --> allowFromX
    end
```


```mermaid
graph TB
    k8sPolicy[K8s Network Policy] --> policyBasics[Policy Basics]
    policyBasics --> understandTypes
    policyBasics --> labelingSelecting
    policyBasics --> defaultDenyModel

    k8sPolicy --> applyBasicPolicies
    applyBasicPolicies --> ingressEgressRules
    applyBasicPolicies --> portLimit
    applyBasicPolicies --> interPodTraffic 

    k8sPolicy --> advancedFeatures 
    advancedFeatures --> precedencePriority
    advancedFeatures --> namespaceSelectors
    advancedFeatures --> interNamespace

    k8sPolicy --> integratePlugins
    integratePlugins --> cniImplementations
    integratePlugins --> kubeProxyInteraction

    k8sPolicy --> bestPractices
    bestPractices --> policyOverPermissive
    bestPractices --> saneDefaults
    bestPractices --> policyAudit
    bestPractices --> validateContinuously

```




```mermaid
graph LR
subgraph Namespace A
    id1(Pods)
end

subgraph Namespace B
    id2(Pods)
end

id1 -- DNS --> id3(kube-dns)
id2 -- DNS --> id3

id1-.->|Egress|o1(Allow)
o1-.->|Ingress|id2

style id1 fill:#f9f,stroke:#333
style id2 fill:#ff9,stroke:#333  
style id3 fill:#f9f,stroke:#333
style o1 fill:#bbf,stroke:#222
```


```mermaid
graph TB
subgraph Namespace A
    id1(Pods)
end

subgraph Namespace B
    id2(Pods)
end 

id1 -- DNS --> id3(kube-dns)
id2 -- DNS --> id3

id1-->|Egress|o1(Allow)-->|Ingress|id2

style id1 fill:#f9f,stroke:#333
style id2 fill:#ff9,stroke:#333
style id3 fill:#f9f,stroke:#333

```

```mermaid
graph LR
subgraph Namespace A
    id1(Pods)
end

subgraph Namespace B
    id2(Pods)
end

id1-.->|Egress|o1(Allow)
o1-.->|Ingress|id2

```


```mermaid
graph TB
subgraph Namespace A
    id1(Pods)
    id1a>Default Deny ALL ]
end

subgraph Namespace B  
    id2(Pods)
    id2b>Default Deny ALL ]
end

id1 -- DNS --> id3(kube-dns)  
id2 -- DNS --> id3

id1-.->|Egress|o1(Allow)
o1-.->|Ingress|id2

style id1 fill:#f9f,stroke:#333  
style id2 fill:#ff9,stroke:#333
style id3 fill:#f9f,stroke:#333
style o1 fill:#bbf,stroke:#222

```


```mermaid
graph TB

subgraph Namespace A
    style id1 fill:#f9f,stroke:#333;
    id1(Pods)
    id1a>Default Deny]
end

subgraph Namespace B  
    style id2 fill:#ff9,stroke:#333;
    id2(Pods)
    id2b>Default Deny]
end

subgraph DNS_Server
    style id3 fill:#f9f,stroke:#333;
    id3(kube-dns)
end

id1 -- DNS --> id3
id2 -- DNS --> id3

id1-.->|Egress|o1(Allow)
o1-.->|Ingress|id2

style o1 fill:#bbf,stroke:#222;
```

- dd
```mermaid
graph LR
  A[Network Policies]
  A --> |type|B[Ingress]
  A --> |type|C[Egress]
  B --> D[Deny]
  B --> E[Allow]
  C --> F[Deny]
  C --> G[ALlow]
  A --> Selectors
  Selectors --> Podselect
  Selectors --> namespaceselect
  Selectors --> Labelselect

```

# other 
```
mindmap
  root((network Policy))
    Policy Type
      ingress
      ::icon(fa fa-book)
      egress
      ::icon(fa fa-thumbs-o-up) 
    Action
      Deny
      Allow
    Labels
      namespace </br> Select
      Pod Select
    Traffic
      From
        source
        destination
      to
        source
        destination
```


