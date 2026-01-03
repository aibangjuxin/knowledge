在 Kubernetes 网络策略中，`[]` 和 `{}` 之间的区别在于它们允许的流量类型。`[]` 允许所有流量，而 `{}` 仅允许指定的流量。

例如，以下网络策略允许来自任何来源的任何流量：

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
spec:
  ingress:
  - {}
```
我们基本都是用上面这个

以下网络策略仅允许来自 pod 标签 `app: web` 的 pod 的流量：

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web
spec:
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
```

您可以使用网络策略来控制 pod 之间、pod 和服务之间以及 pod 和外部系统之间的流量。


要生成一个适用于动态IP地址的except部分的模板，您可以使用以下格式：

```
- ipBlock:
    cidr: <CIDR地址范围>
    except:
    - ip <排除的IP地址1>
    - ip <排除的IP地址2>
    ...
```

对于您的示例，您可以编写一个脚本来生成except部分，如下所示：

```python
except_ips = ["10.208.1.1", "10.208.33.1"]  # 动态IP地址列表
except_template = "- ip: {}"  # except部分的模板

except_section = ""
for ip in except_ips:
    except_section += except_template.format(ip) + "\n"

# 使用except_section替换您的网络策略中的except部分
network_policy = """
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-rt-egress
  namespace: lex
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 12.0.0.0/2
            except:
              {except_section}
        - ipBlock:
            cidr: 10.0.0.0/8
            except:
              {except_section}
"""

network_policy = network_policy.format(except_section=except_section.strip())

print(network_policy)
```

这将生成适用于动态IP地址列表的except部分的模板，您可以将其替换到您的网络策略中。


如果您想在Shell脚本中使用`dig +short fqdn`命令来生成动态IP列表，然后将其用于except部分的模板，可以尝试以下代码：

将此代码保存为Shell脚本文件（例如`generate_network_policy.sh`），然后通过运行`bash generate_network_policy.sh`来执行它。脚本将使用`dig +short fqdn`命令获取动态IP列表，并将其用于except部分的模板生成。然后，它将打印出完整的网络策略，您可以根据需要将其重定向到文件中或进一步处理。请确保将`fqdn`变量替换为您实际的FQDN

你想对给定的代码进行改造，使其根据不同的FQDN将IP添加到不同的`except_section`中。下面是修改后的代码：

```bash
#!/bin/bash

fqdn1="example.com"
fqdn2="example2.com"

# 使用dig命令获取动态IP列表
ip_list1=$(dig +short "$fqdn1" | grep -v "[a-z]")
ip_list2=$(dig +short "$fqdn2" | grep -v "[a-z]")

except_section1=""
while IFS= read -r ip; do
  except_section1+="    - $ip/32\n        "
done <<< "$ip_list1"

except_section2=""
while IFS= read -r ip; do
  except_section2+="    - $ip/32\n        "
done <<< "$ip_list2"

# 使用except_section1和except_section2替换您的网络策略中的except部分
network_policy=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-rt-egress
  namespace: lex
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 12.0.0.0/2
            except:
        $(echo -e "$except_section1")
        - ipBlock:
            cidr: 10.0.0.0/8
            except:
        $(echo -e "$except_section2")
EOF
)

echo "$network_policy"
```

在修改后的代码中，我添加了`fqdn1`和`fqdn2`作为两个不同的FQDN。通过分别使用`dig`命令获取每个FQDN的IP列表，并将其存储在`ip_list1`和`ip_list2`中。然后，我使用`except_section1`和`except_section2`分别将每个IP列表添加到不同的`except_section`中。最后，将这些修改后的变量插入到生成的网络策略模板中。



```bash
#!/bin/bash

fqdn1="example.com"
fqdn2="example2.com"
environment="dev"  # 环境变量，替换为实际的环境值

# 使用dig命令获取动态IP列表
ip_list1=$(dig +short "$fqdn1" | grep -v "[a-z]")
ip_list2=$(dig +short "$fqdn2" | grep -v "[a-z]")

except_section1=""
while IFS= read -r ip; do
  except_section1+="    - $ip/32\n        "
done <<< "$ip_list1"

except_section2=""
while IFS= read -r ip; do
  except_section2+="    - $ip/32\n        "
done <<< "$ip_list2"

# 根据环境选择相应的except_section
if [ "$environment" = "dev" ]; then
  except_section="$except_section1"
elif [ "$environment" = "prd" ]; then
  except_section="$except_section2"
fi

# 使用except_section替换您的网络策略中的except部分
network_policy=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-rt-egress
  namespace: lex
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 12.0.0.0/2
            except:
        $(echo -e "$except_section")
EOF
)

echo "$network_policy"

``` 
关于上面所有的ports except这种写法并不支持，所以都是错误的

好的,在 Kubernetes 中可以通过 NetworkPolicy 的 egress 规则来限制流出流量的端口范围:

1. 在 NetworkPolicy 的 spec 中定义egress规则

2. 在 egress 规则中使用 ports 字段定义允许的端口范围

例如,限制流量只能出口到 30000-32767 端口范围:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-policy
spec:
  podSelector: 
    matchLabels:
      app: webapp
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 30000
      endPort: 32767
```

上面使用 port 和 endPort 定义了一个端口范围 30000-32767。

此外,可以列出每个单独的端口:

```yaml
  ports:
  - port: 30000
  - port: 30301
  - port: 30302
```

或者合并使用端口范围和单独端口的方式。

这就实现了使用 NetworkPolicy 的 egress 规则限制流量的出口端口范围的功能。

另外,不能出口的端口可以通过设置一个空的 egress 规则 {} 来拒绝。


好的,可以通过以下方法实现:

1. 创建一个网络策略,匹配你要禁止访问该IP段的Pod的label:

    ```
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
     name: deny-egress
     namespace: $namespace
    spec:
     podSelector:
      matchLabels:
        access-level: restricted
     policyTypes:
     - Egress
     egress: []  
    ```

2. 在上面的默认网络策略中,通过except子句排除这些带有特定label的Pod:

    ```
    spec:
     podSelector: {}
     except:
      - podSelector: 
         matchLabels:
           access-level: restricted
    ```	

3. 为要禁止的Pod添加上面定义的label:
   ```
   labels:
     access-level: restricted
   ```

这样就可以实现 differentiate Pod 的网络策略,允许其他 Pod 访问该IP段,而禁止带有 restrict label 的 Pod 访问。

关键是通过 matchLabels 和 except 进行匹配和排除。

好的,这里是一个完整的示例:

```yaml
# 默认策略,允许所有 Pod 访问 199.36.153.4/30 段
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy  
metadata:
 name: allow-egress
 namespace: default
spec:
 podSelector: {}
 policyTypes:
 - Egress 
 egress:
 - to:
   - ipBlock:
      cidr: 199.36.153.4/30
   ports:
   - protocol: TCP
     port: 443 
 except:
 - podSelector: 
     matchLabels:
       access-level: restricted

---  

# 禁止标记的 Pod 访问该网段  
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
 name: deny-egress
 namespace: default
spec:
 podSelector:
   matchLabels:
     access-level: restricted
 policyTypes:
 - Egress
 egress: []

---

# 示例 Pod 定义  
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  labels:
    access-level: restricted  # 禁止这个 Pod 访问
spec:
  containers:
  - name: test
    image:  name: allow-rt-egress-l3-to-drn-scc
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 128.0.0.0/2
            except:
        $(echo -e "$except_section_other")
        - ipBlock:
            cidr: 10.0.0.0/8
            except:
        $(echo -e "$except_section_10")
EOF