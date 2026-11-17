# DNS域名长度规范

本文档详细说明DNS域名的长度限制，包括总长度和标签（Label）长度的规范。

## 核心规范 (RFC 1035)

### 1. 标签（Label）长度限制

**标签定义**：标签是域名中由点（`.`）分隔的每一段。

例如：`f.a.b.c.com`
- `f` 是一个标签
- `a` 是一个标签
- `b` 是一个标签
- `c` 是一个标签
- `com` 是一个标签

**标签长度限制**：
- **最大长度**：63 字符（63 octets/bytes）
- **最小长度**：1 字符
- **有效字符**：
  - 字母：a-z, A-Z（不区分大小写）
  - 数字：0-9
  - 连字符：`-`（但不能作为标签的开头或结尾）

### 2. 完整域名（FQDN）总长度限制

**在线格式（Wire Format）**：
- 最大 **255 octets**（包括长度字节和空终止符）

**人类可读格式（Human-Readable Format）**：
- 实际最大 **253 字符**
- 这是因为线格式包含：
  - 每个标签的长度字节（1 byte per label）
  - 根域的空终止符（1 byte）

### 3. 实际示例

#### 示例 1：`f.a.b.c.com`
```
标签分析：
- f     → 1 字符 ✓
- a     → 1 字符 ✓
- b     → 1 字符 ✓
- c     → 1 字符 ✓
- com   → 3 字符 ✓

总长度：1 + 1 + 1 + 1 + 1 + 3 + 4（点） = 11 字符 ✓
```

#### 示例 2：最大标签长度
```
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.com
└────────────────────────63个字符────────────────────────┘

这是有效的，因为第一个标签正好是63字符。
```

#### 示例 3：超出标签长度限制（无效）
```
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa64.com
└────────────────────────64个字符────────────────────────┘
❌ 无效：第一个标签超过63字符
```

#### 示例 4：接近总长度限制
```
最长的有效FQDN示例（253字符）：
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.cccccccccccccccccccccccccccccccccccccccccccccccccccc.dddddddddddddddddddddddddddddddddddddddddddddddddddd.eeeeeeeeeeeeeeeeeeeeeeeeeeeee.com

每个标签 ≤ 63字符
总长度 ≤ 253字符
```

## 长度计算规则

### 人类可读格式计算
```
总长度 = Σ(每个标签的长度) + (点的数量)
```

例如：`www.example.com`
- 标签长度：3 + 7 + 3 = 13
- 点的数量：2
- 总长度：13 + 2 = 15 字符

### 线格式（Wire Format）计算
```
线格式长度 = Σ(1字节长度前缀 + 标签字节) + 1字节空终止符
```

例如：`www.example.com`
```
[3]www[7]example[3]com[0]
├─┘   ├──────┘   ├─┘ └─ 空终止符
1+3 + 1+7      + 1+3 + 1 = 17 bytes
```

## 常见场景的长度限制

### Kubernetes Service DNS

Kubernetes中的Service DNS遵循相同的RFC 1035规范：

```
<service-name>.<namespace>.svc.cluster.local
```

**限制**：
- `service-name`：最多 63 字符
- `namespace`：最多 63 字符
- 完整FQDN：最多 253 字符

**示例**：
```
my-very-long-service-name-with-many-characters-12345678901234.my-long-namespace-name.svc.cluster.local
└──────────────────────63字符以内─────────────────────┘└──────63字符以内──────┘
```

### GCP Cloud DNS

GCP Cloud DNS同样遵循RFC 1035：
- 标签最大长度：63 字符
- FQDN最大长度：253 字符

### 子域名层级限制

虽然RFC 1035没有明确限制层级数量，但总长度限制（253字符）实际限制了层级深度。

**理论最大层级**（每个标签1字符）：
```
a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z...
```
最多约 **127 层**（253字符 ÷ 2 = 126.5）

## 验证工具

### Shell脚本验证
```bash
#!/bin/bash

# 验证域名长度
validate_dns_name() {
    local domain="$1"
    local total_length=${#domain}
    
    # 检查总长度
    if [ $total_length -gt 253 ]; then
        echo "❌ 域名总长度超出限制: ${total_length} > 253"
        return 1
    fi
    
    # 检查每个标签长度
    IFS='.' read -ra labels <<< "$domain"
    for label in "${labels[@]}"; do
        local label_length=${#label}
        if [ $label_length -gt 63 ]; then
            echo "❌ 标签 '$label' 长度超出限制: ${label_length} > 63"
            return 1
        fi
        if [ $label_length -eq 0 ]; then
            echo "❌ 标签不能为空"
            return 1
        fi
    done
    
    echo "✓ 域名合法: ${domain} (总长度: ${total_length})"
    return 0
}

# 测试
validate_dns_name "f.a.b.c.com"
validate_dns_name "www.example.com"
```

### Python验证
```python
def validate_dns_name(domain):
    """验证DNS域名长度"""
    # 检查总长度
    if len(domain) > 253:
        return False, f"总长度 {len(domain)} 超过 253"
    
    # 检查标签长度
    labels = domain.split('.')
    for label in labels:
        if len(label) > 63:
            return False, f"标签 '{label}' 长度 {len(label)} 超过 63"
        if len(label) == 0:
            return False, "标签不能为空"
    
    return True, "域名合法"

# 测试
print(validate_dns_name("f.a.b.c.com"))
# 输出: (True, '域名合法')
```

## 常见问题

### Q1: 为什么是253而不是255？
A: Wire format中包括：
- 每个标签前的长度字节（1 byte per label）
- 根域的空终止符（1 byte）
- 这两个字节占用了255中的2个，剩余253可用于人类可读字符

### Q2: 子域名可以有多少层？
A: 理论上没有硬性层级限制，但受总长度253字符的约束。如果每个标签都是1字符，最多约127层。

### Q3: 国际化域名（IDN）如何计算长度？
A: IDN在Wire format中使用Punycode编码（如 `xn--...`），长度计算基于编码后的ASCII表示。

### Q4: 大小写是否影响长度？
A: DNS不区分大小写，`Example.COM` 和 `example.com` 长度相同。

## 实践建议

1. **保持简短**：虽然最大限制是253字符，但更短的域名更易记忆和输入
2. **避免极限**：不要使用接近63字符的标签
3. **验证输入**：在应用层验证用户输入的域名长度
4. **考虑兼容性**：某些老系统可能有更严格的限制
5. **Kubernetes命名**：Service和Namespace名称应保持在63字符以内

## 参考资料

- [RFC 1035](https://www.ietf.org/rfc/rfc1035.txt) - Domain Names - Implementation and Specification
- [RFC 1123](https://www.ietf.org/rfc/rfc1123.txt) - Requirements for Internet Hosts
- [ICANN - Domain Name Length](https://www.icann.org/resources/pages/domain-name-length-2021-06-17-en)

## 总结

| 项目 | 最大长度 | 备注 |
|------|---------|------|
| 单个标签（Label） | 63 字符 | 点之间的部分 |
| 完整域名（FQDN） | 253 字符 | 人类可读格式 |
| Wire Format | 255 octets | 包含长度字节和终止符 |
| 标签层级 | 无硬性限制 | 受总长度约束，理论最多~127层 |
| 有效字符 | a-z, A-Z, 0-9, `-` | 连字符不能在开头或结尾 |

---

## 可视化图表

### 1. DNS域名结构和长度限制

```mermaid
graph TB
    subgraph "DNS域名示例: www.example.com"
        A["完整域名 FQDN"]
        A --> B["标签1: www<br/>长度: 3字符"]
        A --> C["标签2: example<br/>长度: 7字符"]
        A --> D["标签3: com<br/>长度: 3字符"]
        
        B --> B1["✓ 最大63字符"]
        C --> C1["✓ 最大63字符"]
        D --> D1["✓ 最大63字符"]
    end
    
    A --> E["总长度: 15字符<br/>3 + 1 + 7 + 1 + 3 = 15"]
    E --> F["✓ 最大253字符"]
    
    style A fill:#e1f5fe
    style B fill:#c8e6c9
    style C fill:#c8e6c9
    style D fill:#c8e6c9
    style E fill:#fff9c4
    style F fill:#a5d6a7
```

### 2. 长度限制规则

```mermaid
graph LR
    subgraph "标签长度规则"
        L1["单个标签"] --> L2{"长度检查"}
        L2 -->|"≤ 63字符"| L3["✓ 合法"]
        L2 -->|"> 63字符"| L4["✗ 非法"]
    end
    
    subgraph "总长度规则"
        T1["完整域名"] --> T2{"长度检查"}
        T2 -->|"≤ 253字符"| T3["✓ 合法"]
        T2 -->|"> 253字符"| T4["✗ 非法"]
    end
    
    style L3 fill:#a5d6a7
    style L4 fill:#ef9a9a
    style T3 fill:#a5d6a7
    style T4 fill:#ef9a9a
```

### 3. Wire Format vs Human-Readable Format

```mermaid
graph TB
    subgraph "Human-Readable Format: www.example.com"
        H1["www"] --> H2["."]
        H2 --> H3["example"]
        H3 --> H4["."]
        H4 --> H5["com"]
        H6["总计: 15字符"]
    end
    
    subgraph "Wire Format 255 octets"
        W1["长度字节<br/>3"] --> W2["www<br/>3 bytes"]
        W2 --> W3["长度字节<br/>7"] --> W4["example<br/>7 bytes"]
        W4 --> W5["长度字节<br/>3"] --> W6["com<br/>3 bytes"]
        W6 --> W7["空终止符<br/>0"]
        W8["总计: 1+3+1+7+1+3+1 = 17 bytes"]
    end
    
    H1 -.对应.-> W2
    H3 -.对应.-> W4
    H5 -.对应.-> W6
    
    style H1 fill:#c8e6c9
    style H3 fill:#c8e6c9
    style H5 fill:#c8e6c9
    style W2 fill:#bbdefb
    style W4 fill:#bbdefb
    style W6 fill:#bbdefb
    style W7 fill:#ffccbc
```

### 4. 域名验证流程图

```mermaid
flowchart TD
    Start["输入域名"] --> Split["按点分割成标签"]
    Split --> CheckTotal{"总长度 ≤ 253?"}
    
    CheckTotal -->|否| Error1["❌ 错误:<br/>总长度超限"]
    CheckTotal -->|是| LoopStart["遍历每个标签"]
    
    LoopStart --> CheckEmpty{"标签非空?"}
    CheckEmpty -->|否| Error2["❌ 错误:<br/>空标签"]
    CheckEmpty -->|是| CheckLen{"标签长度 ≤ 63?"}
    
    CheckLen -->|否| Error3["❌ 错误:<br/>标签超长"]
    CheckLen -->|是| CheckChar{"有效字符?"}
    
    CheckChar -->|否| Error4["❌ 错误:<br/>非法字符"]
    CheckChar -->|是| HasMore{"还有标签?"}
    
    HasMore -->|是| LoopStart
    HasMore -->|否| Success["✓ 域名合法"]
    
    style Start fill:#e1f5fe
    style Success fill:#a5d6a7
    style Error1 fill:#ef9a9a
    style Error2 fill:#ef9a9a
    style Error3 fill:#ef9a9a
    style Error4 fill:#ef9a9a
```

### 5. 实际示例对比

```mermaid
graph TB
    subgraph "合法示例"
        V1["f.a.b.c.com<br/>总长度: 11字符<br/>最长标签: 3字符 com"]
        V2["www.example.com<br/>总长度: 15字符<br/>最长标签: 7字符 example"]
        V3["my-service.namespace.svc.cluster.local<br/>总长度: 42字符<br/>最长标签: 10字符 my-service"]
    end
    
    subgraph "非法示例"
        I1["标签超长<br/>aaaaa...64字符...aaaaa.com<br/>❌ 单个标签 > 63字符"]
        I2["总长度超限<br/>very.very.very...254字符...long.domain<br/>❌ 总长度 > 253字符"]
        I3["空标签<br/>www..example.com<br/>❌ 连续两个点"]
    end
    
    style V1 fill:#c8e6c9
    style V2 fill:#c8e6c9
    style V3 fill:#c8e6c9
    style I1 fill:#ffccbc
    style I2 fill:#ffccbc
    style I3 fill:#ffccbc
```

### 6. Kubernetes Service DNS示例

```mermaid
graph LR
    subgraph "Kubernetes Service FQDN结构"
        K1["service-name<br/>最大63字符"] --> K2["."]
        K2 --> K3["namespace<br/>最大63字符"]
        K3 --> K4["."]
        K4 --> K5["svc"]
        K5 --> K6["."]
        K6 --> K7["cluster"]
        K7 --> K8["."]
        K8 --> K9["local"]
    end
    
    subgraph "示例"
        E1["my-app.production.svc.cluster.local<br/>✓ 合法"]
        E2["very-long-service-name-123456789012345678901234567890123456789012.prod.svc.cluster.local<br/>✓ 合法 63字符标签"]
        E3["超长服务名...65字符...超长.prod.svc.cluster.local<br/>❌ 非法 标签>63"]
    end
    
    style K1 fill:#bbdefb
    style K3 fill:#bbdefb
    style E1 fill:#c8e6c9
    style E2 fill:#c8e6c9
    style E3 fill:#ffccbc
```

### 7. 长度计算公式

```mermaid
graph TB
    subgraph "人类可读格式长度计算"
        H["总长度 = Σ标签长度 + 点的数量"]
        H1["示例: www.example.com"]
        H2["= 3 + 7 + 3 + 2点"]
        H3["= 15字符"]
        H --> H1 --> H2 --> H3
    end
    
    subgraph "Wire Format长度计算"
        W["总长度 = Σ长度字节 + 标签字节 + 空终止符"]
        W1["示例: www.example.com"]
        W2["= 1+3 + 1+7 + 1+3 + 1"]
        W3["= 17 bytes"]
        W --> W1 --> W2 --> W3
    end
    
    style H fill:#e1f5fe
    style H3 fill:#a5d6a7
    style W fill:#fff3e0
    style W3 fill:#a5d6a7
```
