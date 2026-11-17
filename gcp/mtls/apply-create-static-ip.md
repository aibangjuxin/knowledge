好的，在 Google Cloud Platform (GCP) 中，你可以使用 `gcloud` 命令行工具来申请（创建）一个静态外部 IP 地址，该地址稍后可以分配给你的 Google Cloud Load Balancer (GLB)。

你需要根据你的负载均衡器类型确定是需要 **全局 (Global)** 静态 IP 还是 **区域 (Regional)** 静态 IP：

*   **全局外部 HTTP(S) 负载均衡器 (包括传统和基于 Envoy 的)**、**全局外部 HTTP(S) 负载均衡器 (经典版)**、**SSL 代理负载均衡器**、**TCP 代理负载均衡器**：需要 **全局** 静态 IP 地址。
*   **区域外部 HTTP(S) 负载均衡器**、**外部 TCP/UDP 网络负载均衡器**：需要 **区域** 静态 IP 地址。

以下是创建这两种类型静态 IP 的 `gcloud` 命令：

**1. 创建全局 (Global) 静态外部 IP 地址**

   这个命令适用于全局负载均衡器。

   ```bash
   gcloud compute addresses create [ADDRESS_NAME] \
       --global \
       --ip-version=IPV4  # 或者 --ip-version=IPV6 如果你需要IPv6
       # --network-tier=PREMIUM  # 全局IP通常需要 Premium Tier，这是默认值，可以省略
       # --description="[描述信息]" # 可选：添加描述
   ```

   **参数说明:**

   *   `[ADDRESS_NAME]`: 你为这个静态 IP 地址指定的名称（例如 `my-glb-static-ip`）。这个名称在你的项目中必须是唯一的（全局范围内）。
   *   `--global`: 明确指定这是一个全局 IP 地址。
   *   `--ip-version=IPV4`: 指定创建 IPv4 地址。如果你需要 IPv6，请使用 `IPV6`。如果省略，默认为 IPv4。
   *   `--network-tier=PREMIUM`: 全局 IP 地址通常与 Premium 网络层级关联，以利用 Google 的全球网络。这是默认选项，通常不需要显式指定。Standard 层级不支持全局 IP。
   *   `--description="[描述信息]"`: (可选) 为这个 IP 地址添加一个描述，方便管理。

   **示例:**

   ```bash
   gcloud compute addresses create my-global-lb-ip --global --description="Static IP for Global HTTP(S) LB"
   ```

**2. 创建区域 (Regional) 静态外部 IP 地址**

   这个命令适用于区域负载均衡器。

   ```bash
   gcloud compute addresses create [ADDRESS_NAME] \
       --region=[REGION_NAME] \
       --ip-version=IPV4  # 或者 --ip-version=IPV6 如果你需要IPv6
       # --network-tier=PREMIUM # 或者 --network-tier=STANDARD，根据需要选择
       # --description="[描述信息]" # 可选：添加描述
   ```

   **参数说明:**

   *   `[ADDRESS_NAME]`: 你为这个静态 IP 地址指定的名称（例如 `my-regional-lb-ip`）。这个名称在指定的区域内必须是唯一的。
   *   `--region=[REGION_NAME]`: 指定 IP 地址所属的区域（例如 `us-central1`、`asia-east1`）。你需要将其替换为你的负载均衡器所在的区域。
   *   `--ip-version=IPV4`: 指定创建 IPv4 地址。如果你需要 IPv6，请使用 `IPV6`。如果省略，默认为 IPv4。
   *   `--network-tier=PREMIUM` 或 `--network-tier=STANDARD`: 区域 IP 地址可以选择 Premium 或 Standard 网络层级。Premium 利用 Google 全球网络进行出站，Standard 则通过公共互联网。根据你的需求和成本考虑选择。如果省略，默认为 Premium。
   *   `--description="[描述信息]"`: (可选) 为这个 IP 地址添加一个描述。

   **示例:**

   ```bash
   gcloud compute addresses create my-regional-lb-ip \
       --region=us-central1 \
       --network-tier=PREMIUM \
       --description="Static IP for Regional Network LB in us-central1"
   ```

**执行命令前的准备:**

1.  **安装 `gcloud` CLI:** 确保你的机器上安装了 Google Cloud SDK。
2.  **认证:** 使用 `gcloud auth login` 登录你的 Google Cloud 账户。
3.  **设置项目:** 使用 `gcloud config set project [YOUR_PROJECT_ID]` 设置你想要操作的项目。

**重要提示:**

*   这个命令只是 **创建（预留）** 了静态 IP 地址。它还 **没有** 分配给任何负载均衡器。
*   你需要在创建或更新负载均衡器的**转发规则 (Forwarding Rule)** 时，将这个预留的静态 IP 地址指定给它。
    *   对于**新的**负载均衡器，在创建转发规则时使用 `--address [ADDRESS_NAME]` (全局 LB) 或 `--address=[ADDRESS_NAME] --region=[REGION_NAME]` (区域 LB)。
    *   对于**现有的**负载均衡器，你需要更新其转发规则来使用这个新的静态 IP。

*   在 IP 地址未分配给资源（如负载均衡器转发规则、VM 实例等）时，GCP 可能会收取少量费用。

执行成功后，`gcloud` 会输出创建的静态 IP 地址的详细信息，包括实际分配到的 IP 地址值。你可以使用 `gcloud compute addresses list` 或 `gcloud compute addresses describe [ADDRESS_NAME] --global/--region=[REGION_NAME]` 来查看已创建的地址。