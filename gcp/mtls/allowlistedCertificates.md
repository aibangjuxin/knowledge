

好的，这是一个基于 Google Cloud Storage (GCS) Buckets 实现的多 CA 证书指纹信任配置架构设计，满足您的特定要求（仅使用 Buckets，动态更新，onboarding 时处理，指纹校验，处理根证书和中间证书）。

**核心理念**

我们将使用 GCS Bucket 的对象（Object）本身来表示信任。每个受信任的 CA 证书（这里我们主要关注根证书，因为它是信任链的起点）的指纹将作为一个 GCS 对象的名称（或路径的一部分）。检查一个 CA 是否受信任就变成了检查 GCS 中是否存在一个特定名称的对象。添加信任就是创建一个新的对象。

**架构组件**

1.  **Trust Config Bucket (GCS):**
    *   一个专门的 GCS Bucket 用于存储信任配置。
    *   **名称示例:** `your-project-id-trust-config-bucket`
    *   **结构:** 我们将在 Bucket 内使用一个特定的前缀（模拟目录）来存放指纹。
        *   **前缀:** `trusted-ca-fingerprints/`
        *   **对象命名:** `trusted-ca-fingerprints/<fingerprint_algorithm>/<certificate_fingerprint>`
            *   `fingerprint_algorithm`: 使用的指纹算法（例如 `sha256`）。这有助于未来可能支持多种算法。
            *   `certificate_fingerprint`: 计算出的证书指纹（十六进制字符串）。
        *   **对象内容:** 对象的内容可以为空，或者存储该证书本身（用户提供的根证书文件），或者存储一些元数据（如添加时间、颁发者信息等，但这会增加复杂度，如果不需要可以保持为空或存储证书本身）。存储证书本身可能更有用，方便未来审计或检索。

2.  **Onboarding Pipeline Step (脚本/代码):**
    *   这是在用户 onboarding 流程中执行的一个逻辑单元（可以是 Cloud Build 步骤、Cloud Functions（如果允许，但您排除了其他服务，所以假设是 pipeline 内的脚本）、或者任何能执行脚本和与 GCS 交互的环境）。
    *   **职责:**
        *   接收用户提供的根证书（必需）和中间证书（可选，但通常一起提供）。
        *   **计算指纹:** 使用标准工具（如 `openssl`）计算根证书的指纹。选择一个标准算法，例如 SHA-256。
            ```bash
            # 示例: 计算 PEM 格式根证书的 SHA-256 指纹
            openssl x509 -in root_certificate.pem -noout -fingerprint -sha256 | sed 's/SHA256 Fingerprint=//g' | tr -d ':' | tr '[:upper:]' '[:lower:]'
            # 注意：处理输出格式以获得纯小写十六进制指纹
            ```
        *   **构造 GCS 对象路径:** 基于计算出的指纹和选择的算法，构建目标 GCS 对象的完整路径。
            *   例如：`gs://your-project-id-trust-config-bucket/trusted-ca-fingerprints/sha256/abcdef1234567890...`
        *   **检查存在性:** 使用 `gsutil` 或 GCS 客户端库尝试访问（例如，`stat`）该 GCS 对象。
            ```bash
            # 示例: 使用 gsutil stat 检查对象是否存在
            # 如果对象存在，命令成功 (exit code 0)
            # 如果对象不存在，命令失败 (non-zero exit code)
            gsutil -q stat gs://your-project-id-trust-config-bucket/trusted-ca-fingerprints/sha256/<calculated_fingerprint>
            ```
        *   **添加信任（如果不存在）:** 如果 `gsutil stat` 返回非零退出码（表示对象不存在），则将用户的根证书上传到该 GCS 路径。
            ```bash
            # 示例: 上传根证书作为对象内容，对象名为指纹
            # $fingerprint 变量包含之前计算出的小写十六进制指纹
            # $user_root_cert_path 指向用户提供的根证书文件
            fingerprint=$(openssl x509 -in $user_root_cert_path -noout -fingerprint -sha256 | sed 's/SHA256 Fingerprint=//g' | tr -d ':' | tr '[:upper:]' '[:lower:]')
            target_path="gs://your-project-id-trust-config-bucket/trusted-ca-fingerprints/sha256/${fingerprint}"

            # 检查是否存在
            gsutil -q stat $target_path
            if [ $? -ne 0 ]; then
              echo "Fingerprint ${fingerprint} not found. Adding to trust store..."
              gsutil cp $user_root_cert_path $target_path
              echo "Successfully added CA with fingerprint ${fingerprint}."
            else
              echo "CA with fingerprint ${fingerprint} already exists in the trust store."
            fi
            ```
        *   **处理中间证书:** 中间证书通常不直接用于建立信任锚点（那是根证书的职责），但它们对于验证完整的证书链是必要的。此架构主要关注“信任配置”本身（即信任哪些根 CA 指纹）。如果需要存储中间证书供后续验证逻辑使用，可以考虑：
            *   **方案 A (简单):** 忽略。信任配置只关心根指纹。验证逻辑在需要时自行获取中间证书（可能来自客户端提供的链，或其他来源）。
            *   **方案 B (存储):** 在 onboarding 时，将中间证书也上传到 Bucket，可能使用不同的前缀或命名约定，例如 `gs://your-project-id-trust-config-bucket/intermediate-certs/<some_identifier>/`。但这超出了“信任配置”的核心范围，增加了复杂性。**根据您的要求，我们仅处理根证书指纹用于信任配置。**

**工作流程 (Onboarding)**

1.  用户通过 onboarding 界面或 API 提供其根证书和中间证书。
2.  Onboarding Pipeline 启动，触发信任配置处理步骤。
3.  脚本接收证书文件。
4.  脚本计算根证书的 SHA-256 指纹。
5.  脚本构造 GCS 对象路径：`gs://<bucket>/trusted-ca-fingerprints/sha256/<fingerprint>`。
6.  脚本执行 `gsutil stat` 检查该对象是否存在。
7.  **Case A: 对象不存在:**
    *   脚本执行 `gsutil cp` 将根证书文件上传到该 GCS 路径。
    *   信任建立成功。Pipeline 继续。
8.  **Case B: 对象已存在:**
    *   脚本记录（或忽略）该 CA 已被信任。
    *   Pipeline 继续。

**动态更新**

*   **添加新的 CA:** 任何时候一个新的用户 onboarding，如果其根 CA 指纹不在 Bucket 中，上述流程会自动添加它。这就是动态添加新信任的方式。
*   **移除 CA (吊销信任):** 需要一个单独的管理流程（可能是一个手动操作或管理员脚本）来删除 GCS Bucket 中对应的指纹对象。例如：
    ```bash
    gsutil rm gs://your-project-id-trust-config-bucket/trusted-ca-fingerprints/sha256/<fingerprint_to_remove>
    ```
*   **更新 CA (例如，根证书续期，指纹改变):** 这本质上是移除了旧指纹（如果需要）并添加了新指纹。如果新旧根证书并行有效一段时间，则两个指纹对象可以共存。

**优势**

*   **简单:** 核心逻辑非常简单，依赖基础的 GCS 操作。
*   **无服务器/无数据库:** 完全符合只使用 Bucket 的要求。
*   **动态:** 添加信任是原子性的对象创建操作。移除也是原子性的对象删除操作。读取信任状态（检查对象是否存在）也非常快。
*   **可扩展:** GCS 本身具有高可用性和扩展性。理论上可以存储大量的指纹对象。
*   **成本效益:** GCS 存储成本相对较低，操作费用也通常不高（取决于使用频率）。

**注意事项与潜在改进**

*   **权限 (IAM):** 执行 Pipeline 的服务账号需要对 Trust Config Bucket 具有 `storage.objects.get` (用于 stat) 和 `storage.objects.create` (用于 cp) 的权限。移除信任则需要 `storage.objects.delete` 权限。确保权限最小化。
*   **并发:** `gsutil cp` 在对象不存在时创建，如果存在则覆盖。`gsutil stat` + `gsutil cp` 不是一个严格的原子 "check-and-set" 操作。在极高并发的 onboarding 场景下，两个进程可能同时检查到对象不存在，然后都尝试创建。GCS 的对象创建具有最终一致性，并且写操作通常是 "last writer wins"。在这种特定场景下（创建相同名称的对象，内容也相同或相似），结果通常是可接受的（对象被创建/覆盖），但需要意识到这一点。如果需要更强的原子性保证，可以使用 GCS 对象的 `generation` 和 `metageneration` 前置条件 (`precondition` flags in `gsutil` or client libraries)，但这会增加复杂性。对于 onboarding 场景（一次性操作），简单的 `stat` 后 `cp` 通常足够。
*   **指纹算法:** 硬编码 `sha256` 可能不够灵活。可以将算法作为配置传入脚本，或支持从证书本身推断（不推荐）。明确使用 `sha256` 并在路径中体现是比较好的实践。
*   **垃圾回收:** 如果 CA 证书过期并且不再需要信任，需要有机制（可能是定期的清理脚本）来移除过期的指纹对象。这需要对象内容包含证书本身或其过期日期元数据。如果对象内容为空，则无法自动清理。
*   **中间证书的处理:** 如前所述，此设计侧重于根 CA 指纹信任。实际的证书链验证逻辑（可能在别处）需要能访问到中间证书。确保存储或传递这些证书的方式与验证逻辑兼容。

**总结**

这个架构利用 GCS 的基本对象存储功能，将每个受信任的 CA 根证书指纹映射为一个 GCS 对象。通过检查对象是否存在来判断 CA 是否受信任，通过创建对象来添加信任。这满足了您使用 GCS Buckets 作为唯一存储、支持多 CA、动态更新（通过添加/删除对象）以及在 onboarding 流程中处理的要求，同时避免了额外的 GCP 服务。


# design

直接回答
	•	研究表明，可以通过 Google Cloud Certificate Manager 和 Google Cloud Storage (GCS) 存储桶设计支持多个 CA 验证的信任配置架构，并实现动态更新。
	•	看起来可能需要手动管理 CA 列表以避免重复，但没有数据库，仅使用存储桶即可。
	•	证据倾向于通过 YAML 文件在 GCS 存储桶中管理信任配置，并使用 Certificate Manager API 更新。
架构概述
您可以使用 Google Cloud Certificate Manager 来创建和管理支持多个证书颁发机构 (CA) 的信任配置。每个信任配置可以包含多个证书，例如信任锚点、中间 CA 和允许列表证书，通过 pemCertificate 字段实现。
动态更新
将信任配置定义存储在 GCS 存储桶中的 YAML 文件中。通过脚本或 CI/CD 管道：
	•	从存储桶中检索当前 YAML 文件。
	•	检查新 CA 是否已存在于列表中。
	•	如果不存在，更新 YAML 文件并上传回存储桶。
	•	使用更新后的 YAML 文件通过 Certificate Manager 的 API 或 CLI 导入或更新信任配置。
检查现有 CA
在添加新 CA 时，解析存储桶中的 YAML 文件或使用 Certificate Manager API 获取当前配置，以检查 CA 是否已存在。这样可以避免重复。
为什么这可行
这种方法避免使用数据库，仅依赖 GCS 存储桶管理配置，并利用 Certificate Manager 处理实际的信任验证。确保存储桶的安全性以保护敏感证书数据。
支持的资源包括：
	•	Manage trust configs | Certificate Manager | Google Cloud
	•	Certificate Manager API | Google Cloud

详细报告
背景与需求分析
用户请求设计一个 Google 工程中的信任配置架构，支持多个 CA 验证，并能够动态更新。关键要求包括：
	•	支持多个 CA 验证。
	•	实现动态更新。
	•	不使用数据库，仅使用存储桶。
	•	在插入数据时，需判断原有的 CA 是否已存在。
基于 2025 年 4 月 18 日的最新信息，我们研究了 Google Cloud 的相关服务，特别是 Certificate Manager 和 Google Cloud Storage (GCS)，以满足这些需求。
架构设计
支持多个 CA 验证
Google Cloud Certificate Manager 提供信任配置（trust configs）功能，用于管理 mTLS 场景中的证书验证。根据 Manage trust configs | Certificate Manager | Google Cloud，信任配置支持多个 CA，通过以下方式实现：
	•	使用多个 pemCertificate 字段定义信任锚点（root CAs）、中间 CA 和允许列表证书。
	•	例如，YAML 文件中可以包含：name: "TRUST_CONFIG_ID"
	•	trustStores:
	•	- trustAnchors:
	•	  - pemCertificate: "CERTIFICATE_PEM_PAYLOAD_1"
	•	  - pemCertificate: "CERTIFICATE_PEM_PAYLOAD_2"
	•	intermediateCas:
	•	  - pemCertificate: "INTER_CERT_PEM_PAYLOAD"
	•	allowlistedCertificates:
	•	  - pemCertificate: "ALLOWLISTED_CERT1"
	•	  - pemCertificate: "ALLOWLISTED_CERT2"
	•	
	•	每个 pemCertificate 字段对应一个证书，确保支持多个 CA 验证。证书需可解析、证明私钥所有权，并符合 SAN 字段约束（参考 RFC 7468）。
动态更新与存储桶使用
用户明确要求不使用数据库，仅使用存储桶。研究表明，Certificate Manager 支持通过 YAML 文件导出和导入信任配置，这与 GCS 存储桶的使用兼容：
	•	导出命令：gcloud certificate-manager trust-configs export TRUST_CONFIG_ID --project=PROJECT_ID --destination=TRUST_CONFIG_FILE --location=LOCATION
	•	导入命令：gcloud certificate-manager trust-configs import TRUST_CONFIG_ID --project=PROJECT_ID --source=TRUST_CONFIG_FILE --location=LOCATION
	•	API 方法也支持更新，例如 PATCH /v1/projects/PROJECT_ID/locations/LOCATION/trustConfigs/TRUST_CONFIG_ID?update_mask=*。
因此，架构设计如下：
	•	将信任配置的 YAML 文件存储在 GCS 存储桶中。
	•	实现一个自动化流程（例如脚本、CI/CD 管道或 Cloud Function）：
	1	从 GCS 存储桶中检索当前信任配置的 YAML 文件。
	2	解析文件，检查新 CA 是否已存在（见下文）。
	3	如果不存在，更新 YAML 文件，添加新 CA 的证书。
	4	将更新后的 YAML 文件上传回 GCS 存储桶。
	5	使用更新后的 YAML 文件通过 Certificate Manager API 或 CLI 更新信任配置。
这种方法确保动态更新，且仅依赖存储桶，无需数据库。
检查现有 CA
用户要求在插入数据时判断原有的 CA 是否已存在。由于不使用数据库，检查逻辑需基于存储桶中的 YAML 文件或 Certificate Manager 的当前配置：
	•	基于 YAML 文件：解析存储桶中的 YAML 文件，检查 trustAnchors、intermediateCas 和 allowlistedCertificates 下的 pemCertificate 列表，判断新 CA 的证书是否已存在。
	•	基于 Certificate Manager API：使用 get 方法（GET /v1/projects/PROJECT_ID/locations/LOCATION/trustConfigs/TRUST_CONFIG_ID）检索当前信任配置，检查证书列表。
考虑到存储桶中的 YAML 文件是配置的源头，建议优先检查 YAML 文件以保持一致性。如果发现重复，可避免添加；否则，更新文件并同步到 Certificate Manager。
安全与实践
由于信任配置涉及敏感证书数据，需确保 GCS 存储桶的安全性：
	•	配置适当的 IAM 权限，仅允许授权用户或服务访问。
	•	考虑启用存储桶的版本控制，以支持回滚和审计。
此外，Certificate Manager 内部可能使用数据库存储信任配置，但从用户视角，仅与 GCS 存储桶交互，满足“不使用数据库”的要求。
技术细节与支持
API 与 CLI 支持
Certificate Manager 的 REST API 提供了以下相关方法（参考 Certificate Manager API | Google Cloud）：
API 方法
HTTP 方法
端点
描述
create
POST
/v1/{parent=projects//locations/}/trustConfigs
创建新信任配置，支持多个 CA
patch
PATCH
/v1/{trustConfig.name=projects//locations//trustConfigs/*}
更新现有信任配置，支持动态更新
get
GET
/v1/{name=projects//locations//trustConfigs/*}
获取当前信任配置，用于检查现有 CA
这些方法支持通过 JSON 或 YAML 文件管理配置，兼容 GCS 存储桶的工作流。
示例工作流
假设存储桶名为 trust-config-bucket，YAML 文件路径为 configs/trust-config.yaml：
	1	检索文件：gsutil cp gs://trust-config-bucket/configs/trust-config.yaml ./trust-config.yaml
	2	解析 YAML，检查新 CA：
	◦	使用 Python 或其他工具解析 YAML，检查 pemCertificate 列表。
	◦	如果新 CA 不存在，添加新证书，例如：allowlistedCertificates:
	◦	  - pemCertificate: "NEW_CERT_PEM"
	◦	
	3	上传更新：gsutil cp trust-config.yaml gs://trust-config-bucket/configs/trust-config.yaml
	4	更新 Certificate Manager：gcloud certificate-manager trust-configs import TRUST_CONFIG_ID --project=PROJECT_ID --source=trust-config.yaml --location=LOCATION
局限与注意事项
	•	目前，Certificate Manager 的文档未明确说明如何处理重复 CA。如果添加重复证书，可能不会引发错误，但建议用户在更新前手动检查以避免冗余。
	•	动态更新的触发机制（例如文件更改检测）需用户自行实现，可能涉及 Cloud Functions 或其他事件驱动服务。
结论
通过将信任配置存储在 GCS 存储桶的 YAML 文件中，并利用 Certificate Manager 的 API 和 CLI 进行管理，可以实现支持多个 CA 验证的架构，并支持动态更新。检查现有 CA 可通过解析 YAML 文件实现，满足不使用数据库的要求。这种方法灵活且可扩展，适合 Google 工程环境。
关键引用
	•	Manage trust configs | Certificate Manager | Google Cloud
	•	Certificate Manager API | Google Cloud




# allowlistedCertificates

关键要点
	•	研究表明，allowlistedCertificates 是 Google Cloud Certificate Manager 信任配置中的一个字段，用于指定始终有效的特定证书。
	•	证据倾向于，pemCertificate 字段应包含完整的 PEM 编码证书，包括开头和结尾标记。
	•	看起来，YAML 文件中可以使用 | 符号来保留多行格式，方便阅读。

`allowlistedCertificates` 的解释
什么是 allowlistedCertificates？allowlistedCertificates 是一个字段，用于在信任配置中指定一组特定的证书。这些证书会被视为始终有效，即使它们已过期，只要满足以下条件：
	•	证书格式正确（可解析）。
	•	证书证明了私钥所有权。
	•	证书的 SAN（Subject Alternative Name）字段符合特定约束。
pemCertificate 字段的内容pemCertificate 字段应该包含证书的 PEM 编码格式。PEM 是一种以 base64 编码的文本格式，用于存储加密对象，如证书。它的典型格式包括：
	•	开头标记：-----BEGIN CERTIFICATE-----
	•	base64 编码的证书内容。
	•	结尾标记：-----END CERTIFICATE-----
例如，一个 PEM 编码证书可能如下所示：
-----BEGIN CERTIFICATE-----
MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
...
-----END CERTIFICATE-----
示例假设你有一个名为 allowlisted.cert 的文件，内容如下：
-----BEGIN CERTIFICATE-----
MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
...
-----END CERTIFICATE-----
在 YAML 文件中，你可以这样指定：
allowlistedCertificates:
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
      BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
      b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
      HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
      BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
      dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
      CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
      ...
      -----END CERTIFICATE-----

详细报告
背景与需求分析
用户要求对 Google Cloud Certificate Manager 的信任配置（trust configs）中的 allowlistedCertificates 部分进行详细解释，特别是 pemCertificate 字段的格式和示例。用户希望了解：
	•	allowlistedCertificates 的作用。
	•	pemCertificate 应该包含什么内容。
	•	一个具体的示例。
通过查询 Google Cloud 的官方文档，我们可以确认以下信息，并提供详细的解释和示例。
`allowlistedCertificates` 的作用与特性
allowlistedCertificates 是信任配置中的一个字段，用于指定一组特定的证书。这些证书将被视为始终有效，即使它们已过期，只要满足以下条件：
	•	证书是可解析的（即格式正确）。
	•	证书证明了私钥所有权（通常通过证书签名链）。
	•	证书的 SAN（Subject Alternative Name）字段符合特定的约束。
根据 Manage trust configs | Certificate Manager | Google Cloud，这些证书不需要依赖信任存储（trust store），它们本身就被视为有效。这意味着，即使证书已过期，只要在允许列表中，系统仍会接受它们。
此外，文档提到，可以通过多个 pemCertificate 字段来封装多个证书，每个证书对应一个实例。例如：
allowlistedCertificates:
  - pemCertificate: "ALLOWLISTED_CERT1"
  - pemCertificate: "ALLOWLISTED_CERT2"
这里的 “ALLOWLISTED_CERT1” 和 “ALLOWLISTED_CERT2” 是占位符，实际应替换为具体的 PEM 编码证书。
`pemCertificate` 的格式
pemCertificate 字段应该包含证书的 PEM 编码格式。PEM（Privacy-Enhanced Mail）是一种以 base64 编码的文本格式，用于存储加密对象，如证书。根据 RFC 7468，PEM 格式的证书通常包括：
	•	开头标记：-----BEGIN CERTIFICATE-----
	•	base64 编码的证书内容。
	•	结尾标记：-----END CERTIFICATE-----
例如，一个典型的 PEM 编码证书可能如下所示：
-----BEGIN CERTIFICATE-----
MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
...
-----END CERTIFICATE-----
在 YAML 文件中，pemCertificate 的内容可以是多行字符串，使用 | 符号来保留原始格式。例如：
allowlistedCertificates:
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
      BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
      b3VwIFNlY3VyaXR5IFNlrnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
      HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
      BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
      dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
      CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
      ...
      -----END CERTIFICATE-----
示例与实践
假设你有一个名为 allowlisted.cert 的文件，内容如下：
-----BEGIN CERTIFICATE-----
MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
...
-----END CERTIFICATE-----
在信任配置的 YAML 文件中，你可以这样指定：
name: "TRUST_CONFIG_ID"
trustStores:
  - allowlistedCertificates:
      - pemCertificate: |
          -----BEGIN CERTIFICATE-----
          MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
          BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
          b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
          HhcNMTYwODA1MTMxMjU1WhcNMTkwODA1MTMxMjU1WjCBpjELMAkGA1UEBhMCR0IxDzAN
          BgNVBAgMBlxvbmRvbjENMAsGA1UECgwEV2lzZTEcMBoGA1UECwwTR3JvdXAgU2VjdXJp
          dHkgU2VydmljZTEbMBkGA1UEAwwSUGF5bWVudCBTZXJ2ZXIgLSBBMTAvBgkqhkiG9w0B
          CQEWEmluZm9Ad2lzZS5jby5nYjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABL8d9aZ+
          ...
          -----END CERTIFICATE-----
注意事项与最佳实践
	•	确保证书是有效的，并且符合 SAN 字段的约束。
	•	在 YAML 文件中，使用 | 符号可以保留多行格式，使 PEM 证书更易读。
	•	如果需要多个允许列表证书，可以添加多个 pemCertificate 条目。
	•	根据 Set up frontend mTLS with user-provided certificates | Load Balancing | Google Cloud，在某些脚本场景中，可能需要将 PEM 证书格式化为单行，但对于 YAML 文件，多行格式通常更合适。
技术细节与支持
Certificate Manager 的 REST API 和 CLI 都支持通过 YAML 文件管理信任配置。例如：
	•	导入命令：gcloud certificate-manager trust-configs import TRUST_CONFIG_ID --project=PROJECT_ID --source=TRUST_CONFIG_FILE --location=LOCATION
	•	API 方法：PATCH /v1/projects/PROJECT_ID/locations/LOCATION/trustConfigs/TRUST_CONFIG_ID?update_mask=*
这些方法支持 allowlistedCertificates 的配置，确保动态更新和多证书支持。
总结
通过以上解释和示例，用户可以清楚地了解 allowlistedCertificates 的作用以及 pemCertificate 的格式和使用方式。建议在实际操作中，确保证书格式正确，并参考官方文档以确保符合最佳实践。
关键引用
	•	Manage trust configs | Certificate Manager | Google Cloud
	•	Set up frontend mTLS with user-provided certificates | Load Balancing | Google Cloud
	•	RFC 7468



# allowlistedCertificates using what
关键要点
	•	研究表明，allowlistedCertificates 通常用于 mTLS 场景中的客户端证书。
	•	证据倾向于，这些证书由客户端呈现，服务器始终接受它们为有效。
	•	看起来，allowlistedCertificates 不会用于服务器证书，专注于客户端验证。
直接回答
allowlistedCertificates 使用的是什么证书？allowlistedCertificates 部分通常包含客户端证书（client certificates），这些证书在互信 TLS（mTLS）认证中由客户端提供给服务器。服务器会始终将这些证书视为有效，即使它们已过期（只要满足某些条件，如格式正确和证明私钥所有权）。这允许服务器对特定客户端进行特殊信任，而无需依赖完整的证书链。
为什么是客户端证书？在 mTLS 场景中，服务器需要验证客户端的证书，而 allowlistedCertificates 正是为此设计的，用于确保某些特定客户端证书始终被接受。这与默认的信任锚点（root certificates）和中间 CA 证书不同，后者用于标准的证书链验证。
支持的资源
	•	更多详情请参考 Manage trust configs 和 Set up frontend mTLS。

详细报告
背景与需求分析
用户询问 Google Cloud Certificate Manager 的信任配置（trust config）中的 allowlistedCertificates 部分通常使用什么类型的证书。基于 2025 年 4 月 18 日的最新信息，我们研究了相关文档，特别是 Certificate Manager 和 Load Balancing 的官方页面，以确认 allowlistedCertificates 的用途和证书类型。
`allowlistedCertificates` 的作用与特性
allowlistedCertificates 是信任配置中的一个字段，用于指定一组特定的证书，这些证书会被视为始终有效，即使它们已过期，只要满足以下条件：
	•	证书是可解析的（格式正确）。
	•	证书证明了私钥所有权。
	•	证书的 SAN（Subject Alternative Name）字段符合特定的约束（参考 RFC 7468）。
这些证书不需要依赖信任存储（trust store），它们本身就被视为有效。这意味着，服务器在 mTLS 场景中会直接接受这些证书，而无需进行标准的基于信任锚点和中间 CA 的验证。
证书类型的确认
研究表明，allowlistedCertificates 中的证书通常是客户端证书（client certificates）。以下是详细分析：
	1	mTLS 场景中的角色
	◦	在互信 TLS（mTLS）中，客户端和服务器都需要通过证书相互验证。客户端向服务器呈现证书，服务器使用信任配置来验证这些证书。
	◦	因此，allowlistedCertificates 的主要用途是帮助服务器验证客户端的身份，允许某些特定客户端证书始终被接受。
	2	文档支持
	◦	在 Manage trust configs | Certificate Manager | Google Cloud 中，明确提到：
	▪	“allowlistedCertificates: A list of certificates that are always considered valid.”
	▪	在使用案例中，提到“允许列出特定的客户端证书”（Allowlist specific client certificates）。
	◦	在 Set up frontend mTLS with user-provided certificates | Load Balancing | Google Cloud 中，提到可以通过创建自签名证书（self-signed certificate）并将其添加到 allowlistedCertificates 中，这明确指向客户端证书的处理。
	3	为什么不是服务器证书？
	◦	服务器证书（server certificates）通常由客户端验证，客户端会使用其自身的信任存储（trust store）来验证服务器的证书。
	◦	信任配置是服务器端的资源，专注于验证客户端证书，因此 allowlistedCertificates 不会包含服务器证书。
	4	具体示例与实践
	◦	在设置 mTLS 的过程中，用户可以创建自签名证书（如通过 OpenSSL），并将其添加到 allowlistedCertificates 中。例如：
	▪	使用命令 openssl req -x509 -new -sha256 -newkey rsa:2048 -nodes -days 3650 -subj '/CN=localhost' -keyout allowlisted.key -out allowlisted.cert 创建自签名证书。
	▪	然后，将该证书的 PEM 编码内容添加到信任配置的 YAML 文件中：allowlistedCertificates:
	▪	  - pemCertificate: |
	▪	      -----BEGIN CERTIFICATE-----
	▪	      MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
	▪	      BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
	▪	      b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
	▪	      ...
	▪	      -----END CERTIFICATE-----
	▪	
	◦	这里创建的证书是客户端证书，用于服务器验证。
技术细节与支持
以下是与 allowlistedCertificates 相关的技术细节：
主题
详情
证书格式
PEM 编码，包含 -----BEGIN CERTIFICATE----- 和 -----END CERTIFICATE----- 标记。
验证条件
可解析、证明私钥所有权、SAN 字段符合 RFC 7468 约束。
使用场景
mTLS 场景中，服务器始终接受特定客户端证书。
配置方式
通过 YAML 文件或 Certificate Manager API 添加到信任配置。
Certificate Manager 的 REST API 和 CLI 都支持管理 allowlistedCertificates，例如：
	•	导入命令：gcloud certificate-manager trust-configs import TRUST_CONFIG_ID --project=PROJECT_ID --source=TRUST_CONFIG_FILE --location=LOCATION
	•	API 方法：PATCH /v1/projects/PROJECT_ID/locations/LOCATION/trustConfigs/TRUST_CONFIG_ID?update_mask=*
局限与注意事项
	•	allowlistedCertificates 仅适用于客户端证书，不支持服务器证书。
	•	用户需确保添加的证书符合格式要求，并考虑安全性（如存储桶权限）以保护敏感证书数据。
结论
通过分析官方文档和相关资源，allowlistedCertificates 中的证书通常是客户端证书，用于 mTLS 场景中让服务器始终接受特定客户端的证书。这与默认的信任锚点和中间 CA 证书不同，后者用于标准的证书链验证。
关键引用
	•	Manage trust configs Certificate Manager Google Cloud
	•	Set up frontend mTLS with user-provided certificates Load Balancing Google Cloud




# must need allowlistedCertificates
关键要点
	•	研究表明，allowlistedCertificates 通常用于 mTLS 场景中的客户端证书。
	•	证据倾向于，这些证书由客户端呈现，服务器始终接受它们为有效。
	•	看起来，allowlistedCertificates 不会用于服务器证书，专注于客户端验证。
直接回答
allowlistedCertificates 使用的是什么证书？allowlistedCertificates 部分通常包含客户端证书（client certificates），这些证书在互信 TLS（mTLS）认证中由客户端提供给服务器。服务器会始终将这些证书视为有效，即使它们已过期（只要满足某些条件，如格式正确和证明私钥所有权）。这允许服务器对特定客户端进行特殊信任，而无需依赖完整的证书链。
为什么是客户端证书？在 mTLS 场景中，服务器需要验证客户端的证书，而 allowlistedCertificates 正是为此设计的，用于确保某些特定客户端证书始终被接受。这与默认的信任锚点（root certificates）和中间 CA 证书不同，后者用于标准的证书链验证。
支持的资源
	•	更多详情请参考 Manage trust configs 和 Set up frontend mTLS。

详细报告
背景与需求分析
用户询问 Google Cloud Certificate Manager 的信任配置（trust config）中的 allowlistedCertificates 部分通常使用什么类型的证书。基于 2025 年 4 月 18 日的最新信息，我们研究了相关文档，特别是 Certificate Manager 和 Load Balancing 的官方页面，以确认 allowlistedCertificates 的用途和证书类型。
`allowlistedCertificates` 的作用与特性
allowlistedCertificates 是信任配置中的一个字段，用于指定一组特定的证书，这些证书会被视为始终有效，即使它们已过期，只要满足以下条件：
	•	证书是可解析的（格式正确）。
	•	证书证明了私钥所有权。
	•	证书的 SAN（Subject Alternative Name）字段符合特定的约束（参考 RFC 7468）。
这些证书不需要依赖信任存储（trust store），它们本身就被视为有效。这意味着，服务器在 mTLS 场景中会直接接受这些证书，而无需进行标准的基于信任锚点和中间 CA 的验证。
证书类型的确认
研究表明，allowlistedCertificates 中的证书通常是客户端证书（client certificates）。以下是详细分析：
	1	mTLS 场景中的角色
	◦	在互信 TLS（mTLS）中，客户端和服务器都需要通过证书相互验证。客户端向服务器呈现证书，服务器使用信任配置来验证这些证书。
	◦	因此，allowlistedCertificates 的主要用途是帮助服务器验证客户端的身份，允许某些特定客户端证书始终被接受。
	2	文档支持
	◦	在 Manage trust configs | Certificate Manager | Google Cloud 中，明确提到：
	▪	“allowlistedCertificates: A list of certificates that are always considered valid.”
	▪	在使用案例中，提到“允许列出特定的客户端证书”（Allowlist specific client certificates）。
	◦	在 Set up frontend mTLS with user-provided certificates | Load Balancing | Google Cloud 中，提到可以通过创建自签名证书（self-signed certificate）并将其添加到 allowlistedCertificates 中，这明确指向客户端证书的处理。
	3	为什么不是服务器证书？
	◦	服务器证书（server certificates）通常由客户端验证，客户端会使用其自身的信任存储（trust store）来验证服务器的证书。
	◦	信任配置是服务器端的资源，专注于验证客户端证书，因此 allowlistedCertificates 不会包含服务器证书。
	4	具体示例与实践
	◦	在设置 mTLS 的过程中，用户可以创建自签名证书（如通过 OpenSSL），并将其添加到 allowlistedCertificates 中。例如：
	▪	使用命令 openssl req -x509 -new -sha256 -newkey rsa:2048 -nodes -days 3650 -subj '/CN=localhost' -keyout allowlisted.key -out allowlisted.cert 创建自签名证书。
	▪	然后，将该证书的 PEM 编码内容添加到信任配置的 YAML 文件中：allowlistedCertificates:
	▪	  - pemCertificate: |
	▪	      -----BEGIN CERTIFICATE-----
	▪	      MIICwjCCAaqgAwIBAgIVAMIIuwK+MDowDQYJKoZIhvcNAQELBQAwgYQxCzAJBgNV
	▪	      BAYTAkdCMQ8wDQYDVQQIDAZMb25kb24xDTALBgNVBAoMBFdpc2UxHDAaBgNVBAsME0dy
	▪	      b3VwIFNlY3VyaXR5IFNlcnZpY2UxHzAdBgNVBAMMFlNlbGYgU2lnbmVkIENBIC0gRzIw
	▪	      ...
	▪	      -----END CERTIFICATE-----
	▪	
	◦	这里创建的证书是客户端证书，用于服务器验证。
技术细节与支持
以下是与 allowlistedCertificates 相关的技术细节：
主题
详情
证书格式
PEM 编码，包含 -----BEGIN CERTIFICATE----- 和 -----END CERTIFICATE----- 标记。
验证条件
可解析、证明私钥所有权、SAN 字段符合 RFC 7468 约束。
使用场景
mTLS 场景中，服务器始终接受特定客户端证书。
配置方式
通过 YAML 文件或 Certificate Manager API 添加到信任配置。
Certificate Manager 的 REST API 和 CLI 都支持管理 allowlistedCertificates，例如：
	•	导入命令：gcloud certificate-manager trust-configs import TRUST_CONFIG_ID --project=PROJECT_ID --source=TRUST_CONFIG_FILE --location=LOCATION
	•	API 方法：PATCH /v1/projects/PROJECT_ID/locations/LOCATION/trustConfigs/TRUST_CONFIG_ID?update_mask=*
局限与注意事项
	•	allowlistedCertificates 仅适用于客户端证书，不支持服务器证书。
	•	用户需确保添加的证书符合格式要求，并考虑安全性（如存储桶权限）以保护敏感证书数据。
结论
通过分析官方文档和相关资源，allowlistedCertificates 中的证书通常是客户端证书，用于 mTLS 场景中让服务器始终接受特定客户端的证书。这与默认的信任锚点和中间 CA 证书不同，后者用于标准的证书链验证。
关键引用
	•	Manage trust configs Certificate Manager Google Cloud
	•	Set up frontend mTLS with user-provided certificates Load Balancing Google Cloud

