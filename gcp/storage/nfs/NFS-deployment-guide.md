# NFS 挂载实施指南(精简版)

> **本节是"具体怎么实施 NFS 挂载到 GKE Pod"的精简操作指南**,面向 infra-gcp / 业务方 reviewer。
>
> **架构师 lane 边界**:本文档**只描述实施步骤和 YAML 模板**,**不执行任何 apply**。实际由 infra-gcp 用专属 SA 执行。

---

## 0. 🚨 安全门控 —— 业务方 + infra-gcp 必读(优先级最高)

> **🚨 重要:NFS 默认明文传输,直接违反企业安全规范。**
>
> **NFSv3 / NFSv4.0 / v4.1 / v4.2 全系列默认都是明文**(协议设计哲学:NFS 假设在可信内网跑)。
>
> **绝不允许生产环境用明文 NFS**。

### 安全门控表(业务方 + infra-gcp 必填,不勾选不能 apply)

| # | 强制问题 | 业务方答 | infra-gcp 验证 |
|---|---|---|---|
| G-Enc-1 | 你选哪种加密方案? | ☐ NFS-over-TLS(`xprtsec=tls`,Linux 6.5+)<br>☐ WireGuard 隧道<br>☐ IPsec 隧道 | 必须勾选一项 |
| G-Enc-2 | 加密方案覆盖范围? | ☐ 仅 Pod → NFS server 链路<br>☐ Pod → NFS server + NFS server 内部 | 至少前一项 |
| G-Enc-3 | NFS server 是否支持所选方案? | ☐ 已验证(server OS + 版本号)<br>☐ 已验证隧道可达性 | 必须验证 |
| G-Enc-4 | 走公网 / VPN 链路? | ☐ 否(纯内网)<br>☐ 是(必须配加密)| 走公网 = 强制加密 |

**任一项未勾选或答"否"** → **暂停**,先解决加密层。

### 业务方/infra-gcp 必读的安全判断

| 链路情况 | 推荐 | 原因 |
|---|---|---|
| 纯内网 + 一般数据 + 接受明文 | ⚠ **仍需 WireGuard**(防内网嗅探)| 内网也有风险(恶意软件、误配 ACL)|
| 纯内网 + 敏感数据(PII / 财务 / 凭证)| **WireGuard 必配** | 合规要求 |
| 走公网 / VPN / 跨 region | **WireGuard / IPsec 必配** | 网络层加密 |
| Linux 6.5+ + 客户端 + 服务端 | **NFS-over-TLS(`xprtsec=tls`)**| 协议层加密,推荐 |
| 老 Linux 5.x / 6.4 kernel | **WireGuard 隧道** | kTLS 不可用 |
| 企业 NAS 设备(NetApp / Isilon)| **看设备支持** | 部分支持 kTLS,部分只支持明文 |

> **🚨 关键判断**:业务方如果写"先用明文 NFS,后期再补加密"——**不允许**。**先配加密,再 apply**。

### 4 种加密方案对比

| # | 方案 | 加密层 | 适合场景 | 复杂度 | 推荐度 |
|---|---|---|---|---|---|
| 1 | **NFS-over-TLS(`xprtsec=tls`)** | 协议层 | Linux 6.5+ 客户端 + 服务端,内网或专线 | 中(证书管理) | ⭐⭐⭐ 推荐 |
| 2 | **Kerberos(`sec=krb5p`)** | 协议层 | 已有 AD 域 + NFS Kerberos 部署 | 高(AD 集成) | ⚠ 配置复杂,几乎不用 |
| 3 | **WireGuard 隧道** | 网络层 | 任何 NFS server(老 / 新 / 异构),跨网段 | 中(隧道配置) | ⭐⭐⭐ 推荐(兜底) |
| 4 | **IPsec VPN** | 网络层 | 多 VPC 跨 project 场景 | 高(VPC 配通)| ⚠ 重,仅大企业用 |

**架构师推荐**:**首选 NFS-over-TLS**(协议层,干净),**次选 WireGuard 隧道**(网络层,通用)。

---

## 1. NFS 跟 SMB 关键差异速查

| 维度 | SMB(ADR-009) | NFS(本指南)|
|---|---|---|
| 协议端口 | TCP 445 | **TCP 2049** |
| CSI driver | `smb.csi.k8s.io` | **`nfs.csi.k8s.io`** |
| 鉴权 | user/pass + signing | **无原生鉴权**(IP 白名单 + UID)|
| 加密(协议层) | SMB 3.0+ AES-CCM/GCM(默认) | **默认明文,需额外配 NFS-over-TLS 或 WireGuard** |
| Secret 凭据 | 需要 SMB user/pass | **不需要**(NFS 无凭据)|
| Pod spec 复杂度 | 较高 | 较简单 |
| Linux 节点支持 | 需 cifs-utils 镜像 | **Linux 内核原生支持** |

**关键点**:**NFS 没有 user/pass**,所以 NFS 场景下 **K8s Secret 不需要**(vs SMB 必须有 Secret)。

---

## 2. 实施前必查(infra-gcp 准备)

### 2.1 NFS server 可达性

```bash
# 1. TCP 端口测试
nc -zv <nfs-server-ip> 2049
# 期望:succeeded

# 2. NFS 协议握手
showmount -e <nfs-server-ip>
# 期望:看到 export 列表,例如:
#   /vol/data   <client-cidr>
#   /vol/config <client-cidr>

# 3. 防火墙白名单
# 问 IT:GKE Node CIDR 段是否在 NFS server 防火墙白名单内
# 一般 GKE Node CIDR 类似 10.40.0.0/16(看 cluster 配置)
```

### 2.2 性能与容量

- 跟 IT 确认 NFS server 容量 + IOPS 配额
- 单 Pod mount 数量建议 ≤ 5(太多 mount 影响 mount namespace)

---

## 3. PV 创建方式(NFS 静态方式,推荐)

### 3.1 方式 A:静态 PV + 静态 PVC(简单场景)

**适合**:NFS server 固定、export 固定、单 tenant 单 mount。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs-app
  labels:
    tenant: tnt-001
    storage-type: nfs
    managed-by: infra-gcp
spec:
  capacity:
    storage: 100Gi                # 标称容量(实际由 NFS server 决定)
  accessModes:
  - ReadOnlyMany                  # 跟 SMB 一样默认 ro
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""            # 静态 PV,不用 SC
  csi:
    driver: nfs.csi.k8s.io       # ← 关键:CSI driver 名字
    volumeHandle: "nfs-app-volume-001"   # ← 唯一标识,任意字符串
    volumeAttributes:
      server: "<nfs-server-ip>"   # ← NFS server IP
      share: "/vol/data/app"     # ← NFS export 路径
    # NFS 不需要 fsType(linux 内核自动探测)
    # NFS 不需要 nodePublishSecretRef(无凭据)
```

```yaml
# 配套 PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nfs-app
  namespace: api-ns
  labels:
    tenant: tnt-001
spec:
  volumeName: pv-nfs-app          # 绑到 PV
  accessModes: [ReadOnlyMany]
  resources:
    requests:
      storage: 10Gi
  storageClassName: ""
```

### 3.2 方式 B:动态 PV(StorageClass + NFS Provisioner)

**适合**:多 tenant 共享 NFS server,需要按需创建子目录。

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-dynamic
provisioner: nfs.csi.k8s.io
parameters:
  server: "<nfs-server-ip>"
  share: "/vol/data"
  subDir: "${pvc.metadata.namespace}-${pvc.metadata.name}"
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
  - sec=sys
```

**关键**:`subDir` 模板自动按 namespace + PVC 名字生成子目录,避免手动建子目录。

---

## 4. Pod 引用 PVC(NFS 场景比 SMB 简单)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-with-nfs
  namespace: api-ns
  labels:
    app: api
    role: nfs-consumer
    tenant: tnt-001
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
      role: nfs-consumer
  template:
    metadata:
      labels:
        app: api
        role: nfs-consumer
        tenant: tnt-001
    spec:
      # NFS 场景不需要 serviceAccountName(无 GCP API 调用)
      # NFS 场景不需要 Secret(无凭据)
      containers:
      - name: api
        image: <业务方镜像:tag>
        volumeMounts:
        - name: nfs-app-folder
          mountPath: /mnt/nfs
          readOnly: true             # 默认 ro,同 NAS
        # ⚠ 红线 2:应用代码不写 logger.info(f"read {filepath}")
        # ⚠ 红线 4:不挂 ConfigMap / Secret 引用 NFS 内容
      volumes:
      - name: nfs-app-folder
        persistentVolumeClaim:
          claimName: pvc-nfs-app
```

**关键差异 vs SMB Deployment**:
- ❌ **不需要** `serviceAccountName`(NFS 不调 GCP API)
- ❌ **不需要** Secret mount(SMB 必须,NFS 不需要)
- ✅ 仍然需要 PVC / PV / namespace / labels

---

## 5. NetworkPolicy(必配)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-nfs-consumer-egress
  namespace: api-ns
spec:
  podSelector:
    matchLabels:
      role: nfs-consumer
  policyTypes: [Egress]
  egress:
  # 允许到 NFS server 的 2049 TCP
  - to:
    - ipBlock:
        cidr: 10.20.0.0/16          # ← infra-gcp 填实际 NFS server CIDR
    ports:
    - protocol: TCP
      port: 2049
  # 允许 DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      ports:
    - protocol: UDP
      port: 53
```

---

## 6. 4 红线自检(NFS 场景)

```bash
# 红线 1:不持久化到 GCP 服务
grep -E "gcs|firestore|bigquery|cloudsql" deployment.yaml
# 期望:无输出

# 红线 2:不写 log / metric 暴露
grep -E "nfs.*path|/mnt/nfs" deployment.yaml log_schema.yaml
# 期望:无输出(mountPath 字段是合法的)

# 红线 3:不主动观察用户行为
grep -E "audit.*file_path" deployment.yaml
# 期望:无输出

# 红线 4:Pod lifecycle 与 NAS 解耦
grep -E "configMapRef.*nfs|secretRef.*nfs" deployment.yaml
# 期望:无输出
```

---

## 7. 常见错误

### ❌ 错误 1:在 PV 里加 `fsType` 或 `nodePublishSecretRef`

```yaml
# ❌ 不要写这些字段
csi:
  driver: nfs.csi.k8s.io
  volumeHandle: ...
  fsType: nfs                    # ← NFS 模式自动探测,不要写
  nodePublishSecretRef:          # ← NFS 无凭据,不要写
    name: nfs-secret
```

**修正**:删除 `fsType` 和 `nodePublishSecretRef`,只留 `driver` / `volumeHandle` / `volumeAttributes`。

### ❌ 错误 2:Deployment 里 mount NFS 为 rw 但没评估

```yaml
# ❌ 默认应该是 ro,改 rw 需要 PM 评估
volumeMounts:
- name: nfs-app-folder
  mountPath: /mnt/nfs
  readOnly: false               # ← 改 rw 必须先 PM 评估
```

**修正**:默认 `readOnly: true`,改 rw 走 PM + Manager 评估流程。

### ❌ 错误 3:多个 Pod 共享同一个 NFS rw mount

```yaml
# ❌ 多 Pod rw 共享 = 数据竞争 + 审计混乱
replicas: 3
volumeMounts:
- name: nfs-data
  mountPath: /mnt/nfs
  readOnly: false               # ← 多 Pod rw 写同一目录
```

**修正**:默认 `replicas: 1` + `readOnly: true`。需要多 Pod 共享 = 业务方额外评估 + 用 ReadWriteOnce + PodAntiAffinity。

### ❌ 错误 4:NFS server IP 写错

```yaml
# ❌ 写错 IP,Pod 启动后 mount 失败
volumeAttributes:
  server: "10.20.0.1"          # ← 应该是 10.20.0.100
```

**修正**:infra-gcp 必须先 `showmount -e` 验证 server IP 可达 + export 正确。

---

## 8. NFS 性能优化(可选)

| 选项 | 何时用 | 副作用 |
|---|---|---|
| `mountOptions: [hard]` | **默认推荐** | NFS server 挂了,client 持续重试 |
| `mountOptions: [soft]` | 短暂故障可容忍 | NFS server 挂了,client 报 I/O error |
| `mountOptions: [nfsvers=4.1]` | 大文件 + 高并发 | 需要 NFS server 支持 NFSv4.1 |
| `mountOptions: [sec=sys]` | 默认(标准 UNIX auth) | Linux UID/GID 必须与 NFS server 匹配 |
| `mountOptions: [xprtsec=tls]` | **🚨 必配(2026 安全要求)** | 协议层 TLS 加密,Linux 6.5+;详见 §0 安全门控 + §7.5 |

### 7.5 NFS 加密实施细节(🚨 必读)

> **这一节是"如何实际启用 NFS 加密"的具体操作指南**。业务方 / infra-gcp 必读 —— 不配置加密不允许 apply。

#### 7.5.1 前提条件(2026 现状)

| 条件 | Linux kernel | RHEL | Ubuntu |
|---|---|---|---|
| kTLS(协议层 TLS) | 6.5+(2023-09) | 9.6+ 推荐 | 24.04 LTS 推荐 |
| `tlshd` daemon | 来自 `ktls-utils` 包 | `dnf install ktls-utils` | `apt install ktls-utils` |
| NFS server 支持 | 取决于 server OS | RHEL 9.6+ 全面支持 | Ubuntu 24.04+ 推荐 |
| 一手参考 | [Arch Wiki NFS TLS](https://wiki.archlinux.org/title/NFS) | [Red Hat Solution 7079884](https://access.redhat.com/solutions/7079884) |  |

#### 7.5.2 方案 A:NFS-over-TLS(协议层,推荐)

**服务端(NFS server)**:
```bash
# 1. 安装
sudo dnf install nfs-utils ktls-utils  # RHEL
# 或: sudo apt install nfs-common ktls-utils  # Ubuntu 24.04+

# 2. 启动 tlshd
sudo systemctl enable --now tlshd.service

# 3. 配置 tlshd 信任客户端证书(用企业 CA)
cat > /etc/tlshd.conf <<EOF
[authenticate.client]
x509.certificate=/etc/pki/tls/certs/nfs-server.crt
x509.private_key=/etc/pki/tls/private/nfs-server.key
EOF

# 4. 标准 NFS 导出(无变化)
echo "/vol/data 10.0.0.0/8(rw,sync,no_subtree_check,sec=sys)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

**客户端(GKE Node)**:
```bash
# 1. GKE Node 镜像预装 ktls-utils(需 Custom Node Image,infra-gcp 负责)

# 2. 启动 tlshd
sudo systemctl enable --now tlshd.service

# 3. 配置 tlshd 信任服务端 CA
cat > /etc/tlshd.conf <<EOF
[authenticate.client]
x509.truststore=/etc/pki/ca-trust/source/anchors/nfs-ca.crt
EOF
```

**K8s PV 模板(NFS-over-TLS)**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs-tls-app
spec:
  capacity: { storage: 100Gi }
  accessModes: [ReadOnlyMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  csi:
    driver: nfs.csi.k8s.io
    volumeHandle: "nfs-tls-app-volume-001"
    volumeAttributes:
      server: "<nfs-server-ip>"
      share: "/vol/data/app"
  mountOptions:
    - xprtsec=tls           # ← 关键:协议层 TLS 加密
    - sec=sys
    - hard
    - nfsvers=4.2           # ← kTLS 需要 NFS 4.2+
```

#### 7.5.3 方案 B:WireGuard 隧道(网络层,老 NFS 通用)

```bash
# 1. 在 NFS server 和 GKE Node 两侧都装 WireGuard
sudo apt install wireguard

# 2. NFS server 侧
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.99.0.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/server.key)

[Peer]
PublicKey = <client-public-key>   # ← GKE Node 的公钥
AllowedIPs = 10.99.0.2/32
EOF
sudo systemctl enable --now wg-quick@wg0

# 3. GKE Node 侧(同款,endpoint 指向 server)
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.99.0.2/24
PrivateKey = /etc/wireguard/client.key

[Peer]
PublicKey = <server-public-key>
Endpoint = <nfs-server-public-ip>:51820
AllowedIPs = 10.20.0.0/16   # ← NFS server 内网段
PersistentKeepalive = 25
EOF
sudo systemctl enable --now wg-quick@wg0

# 4. 验证
wg show
# 期望:看到 peer,latest handshake 不为 None
```

**WireGuard 模式下,K8s PV 配普通 mount 即可**(隧道层已加密):
```yaml
mountOptions:
  - hard
  - nfsvers=4.2
  # 无需 xprtsec=tls(隧道层已加密)
```

#### 7.5.4 验证清单(infra-gcp apply 前必跑)

```bash
# 1. 验证加密状态(必须看到 tls 标记)
ss -tna | grep nfs
# 期望(方案 A):ESTAB ... tls
# 期望(方案 B):ESTAB ... (隧道 IP,看不到 nfs 字样)

# 2. 验证 WireGuard 握手(方案 B)
wg show
# 期望:peer 行 latest handshake: 几秒前

# 3. 抓包验证(强证据)
sudo tcpdump -i any -nn -s 0 -w /tmp/nfs.pcap 'host <nfs-server-ip> and port 2049'
# 跑一次 ls /mnt/nfs
tcpdump -r /tmp/nfs.pcap -A | head -50
# 期望:看不到明文 NFS RPC 数据(方案 A 或 B 都应加密)

# 4. 4 红线自检
grep -E "gcs|firestore|bigquery|cloudsql" deployment.yaml    # R1
grep -E "nfs.*path|/mnt/nfs" deployment.yaml                  # R2
grep -E "xprtsec=tls|wireguard|wg-quick" deployment.yaml node-setup.sh  # 🚨 R-Enc 必须命中
# 期望:看到至少一项加密配置
```

#### 7.5.5 关键判断(业务方 + infra-gcp 必读)

> **🚨 "NFS 用明文"= 违反企业安全规范。**
>
> - **业务方**:**不能**写"先明文跑通,后期加加密"——**明文 NFS 不允许 apply**
> - **infra-gcp**:**NFS-over-TLS 或 WireGuard 必须**在 apply 之前就位
> - **验证**:`ss -tna | grep nfs` 必须看到 `tls` 标记,或 `wg show` 必须显示 handshake
> - **如果不保证加密,这次 NFS 探索**应当暂停**,先解决加密层再继续**

---
| `mountOptions: [actimeo=30]` | 减少属性缓存 | 实时性要求高的场景 |

**推荐**:`hard, nfsvers=4.1, sec=sys`(除非有具体原因用别的)。

---

## 9. 故障排查 quick reference

| 现象 | 可能原因 | 修复 |
|---|---|---|
| Pod 启动后 `ls /mnt/nfs` 空 | NFS server IP 错 / export 路径错 / 防火墙 | `showmount -e <server>` 验证 + 问 IT 防火墙 |
| `kubectl describe pod` 报 `FailedMount` | mount timeout(NFS server 不可达)| `nc -zv <nfs-server> 2049` |
| Pod 写入文件失败,read 成功 | mount 是 ro(默认) | 业务方确认 + 改 rw 走 PM 评估 |
| 多个 Pod 数据竞争 | replicas > 1 + rw mount | 改 ro,或业务方额外评估 |
| 性能慢 | NFS 走 WAN / 大量小文件 | 加缓存层 / 换文件格式 / 改用 Filestore |

---

## 10. infra-gcp 必跑的自检命令

```bash
# PV 创建后
kubectl get pv pv-nfs-app -o yaml | grep -E "driver|volumeAttributes"
# 期望:csi.driver = nfs.csi.k8s.io

# PVC 绑定后
kubectl get pvc pvc-nfs-app -n api-ns -o jsonpath='{.status.phase}'
# 期望:Bound

# Pod 启动后
kubectl exec -it <pod-name> -n api-ns -- mount | grep nfs
# 期望:看到 <nfs-server>:/vol/data/app on /mnt/nfs type nfs

# 4 红线自检
grep -E "gcs|firestore|bigquery|cloudsql" deployment.yaml
grep -E "nfs.*path|/mnt/nfs" deployment.yaml
grep -E "configMapRef.*nfs|secretRef.*nfs" deployment.yaml
# 期望:全部无输出
```

---

> **作者声明**:本文档只描述实施流程,**不执行 apply**。实际部署由 infra-gcp 用专属 SA 执行,详见 [ADR-009 §13](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#13-bot-协作纪律--agent-vs-真人身份边界2026-08-28-review-沉淀) Bot 协作纪律。