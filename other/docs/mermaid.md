Mermaid 是一种文本渲染引擎,可以从简单的文本描述生成图表,序列图,甘特图,状态图,等等。它非常适合用在 Markdown 文档中。
这里给出一些 Mermaid 的用法示例:

mermaid flowchart 类似的语法中[]符号中间包含的时候不能包括()
例如
subgraph Kong
CP[Control Plane (CP)]
DP[Data Plane (DP)]
end
上面就是错误的写法

另外就是类似下面这种，后面的字符串中不能包含空格，必须是一个整体
Workspace3 --> |Contains| Configurations3

https://mermaid.live/
https://support.typora.io/Draw-Diagrams-With-Markdown/

## 流程图
```mermaid
graph LR
A[方形] -- 链接 --> B((圆))
B --> C{条件a}
C -->|a=1| D(结果1)
C -->|a=2| E(结果2)
F[横向流程图]
```
## 序列图
```mermaid
sequenceDiagram
对象1->>对象2: 消息1
对象2-->>对象1: 消息2
对象1->>对象3: 消息3
对象3--x对象2: 消息4
对象1-x对象3: 消息5
```
## 甘特图
```mermaid
gantt
       dateFormat  YYYY-MM-DD
       title 软件开发甘特图
       section 设计
       需求                      :done,    des1, 2014-01-06,2014-01-08
       原型                      :active,  des2, 2014-01-09, 3d
       UI设计                     :         des3, after des2, 5d
```    
## 状态图
```mermaid
stateDiagram
[*] --> 未启动
未启动 --> [*]
未启动 --> 运行中
运行中 --> 未启动
运行中 --> 等待输入 
等待输入 --> 运行中
等待输入 --> 结束
结束 --> [*]
```
Mermaid 还支持类图、用户旅程图等等。希望这个示例能给你提供一个 Mermaid 入门的参考。更详细的语法可以参考 Mermaid 官方文档

# flow Kong mtls
simple flow
```mermaid
graph LR
client-request -->kong-->upstream-->downstream
```

```mermaid
flowchart TB
A(client Request)-->|fqnd.domain|B(host)-->D(Kong CP Route)
A(client Request)-->|/abc/|C(path)-->D(Kong CP Route)
D(Kong CP Route)-->|Name cp-rout-name|E(Kong CP services)
A(client Request)-->E(Kong CP services)--> |nginx=local ?|F( upstream upstream-fqnd.svc.cluster.local) --> G(k8s svc)-->|deployment| H(Pod Service cert detail )
    subgraph upstreamcert
		subgraph service-cert
			H(Pod Service cert detail )-->J(ssl_certificate)
			 H(Pod Service cert detail )-->W(ssl_certificate_key)
		end
		subgraph proxy-cert
			 H(Pod Service cert detail )-->I(proxy_ssl_certificate)
 			 H(Pod Service cert detail )-->K(proxy_ssl_certificate_key)
     		H(Pod Service cert detail )-->L(proxy_ssl_trusted_certificate)
	    end
		subgraph proxy-pass
		proxy_pass--> https://nginx-fqnd
		end
    end
	subgraph downstream
	ingress-->svc-->|deployment|Pod
	Pod-->ssl_certificate
	Pod-->ssl_certificate_key
	Pod-->ssl_client_certificate
	end
upstreamcert --> downstream
A(client Request)-->|Through client cert nginx-fqnd |downstream
```
```mermaid
flowchart TB
style A fill:#f9f,stroke:#333,stroke-width:4px
style downstreamnginx fill:#f9f,stroke:#333,stroke-width:4px

A(client Request)-->|fqnd.domain|B(host)-->D(Kong CP Route)
A(client Request)-->|/abc/|C(path)-->D(Kong CP Route)
    subgraph Kong-CP
        D(Kong CP Route)-->|Name cp-rout-name|E(Kong CP services)
    end
    subgraph Kong-Service
        E(Kong CP services)--> |nginx=local ?|F(upstream-fqnd.svc.cluster.local) --> G(k8s svc)-->|deployment| H(Pod Service cert detail )
    end

    subgraph upstreamnginx
		subgraph service-cert
			H(Pod Service cert detail )-->J(ssl_certificate)
			 H(Pod Service cert detail )-->W(ssl_certificate_key)
		end
		subgraph proxy-cert
        		subgraph proxy-pass
		            proxy_pass--> nextnginx
		        end
			H(Pod Service cert detail )-->I(proxy_ssl_certificate)
 			H(Pod Service cert detail )-->K(proxy_ssl_certificate_key)
     		H(Pod Service cert detail )-->L(proxy_ssl_trusted_certificate)
	    end
    end
	subgraph downstreamnginx
	ingress-->|ssl-passthrough|svc-->|deployment|Pod
      subgraph pod-ssl-cert
	    Pod-->ssl_certificate
	    Pod-->ssl_certificate_key
	    Pod-->ssl_client_certificate
    end
	end
upstreamnginx -->|nginx proxy pass| downstreamnginx
A(client Request)-->|Through client cert nginx-fqnd |downstreamnginx
```


network
```mermaid
graph LR
  A[Namespace A] --> B[Namespace B]
  A --> B [label="allow" style="dashed"]
  B --> A [label="allow" style="dashed"]
  A --> * [label="deny" style="dashed"]
  B --> * [label="deny" style="dashed"]
  A --> .1[DNS]
  B --> .2[DNS]
```
