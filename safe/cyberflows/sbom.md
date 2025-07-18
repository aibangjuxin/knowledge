gcloud artifacts sbom 是 Google Cloud 提供的命令，用于从 **Google Artifact Registry (GAR)** 中获取 SBOM（Software Bill of Materials，软件物料清单）。它目前支持导出 **Docker 镜像** 的 SBOM，格式为 **CycloneDX JSON** 或 **SPDX JSON**，内容主要用于分析该镜像中包含哪些依赖、组件版本、来源等信息。

---

## **✅ 使用前提**

  

你需要满足以下前提条件：

1. **镜像已上传到 GAR**（并且在支持 Container Analysis 的区域）
    
2. **启用了以下 API**：
    
    - containeranalysis.googleapis.com
        
    - artifactregistry.googleapis.com
        
    
3. 安装了最新版本的 gcloud CLI，并已运行 gcloud auth login / gcloud init。
    

---

## **✅ 基本命令结构**

```
gcloud artifacts sbom list \
  --package="LOCATION-docker.pkg.dev/PROJECT-ID/REPO/IMAGE@DIGEST" \
  --format=json
```

---

## **🔍 参数说明**

|**参数项**|**说明**|
|---|---|
|--package|必填，格式为：[LOCATION]-docker.pkg.dev/[PROJECT]/[REPO]/[IMAGE]@sha256:<digest>|
|--format|可选，可设置为 json、yaml，默认是 json|
|--location|镜像所在区域，例如 us, europe-west2，通常在 package 路径中包含|

---

## **🧪 示例流程（实战）**

  

假设你已将如下镜像上传至 GAR：

```
europe-west2-docker.pkg.dev/my-project/my-repo/my-app@sha256:1234abcd...
```

你可以这样拉取 SBOM：

```
gcloud artifacts sbom list \
  --package="europe-west2-docker.pkg.dev/my-project/my-repo/my-app@sha256:1234abcd..." \
  --format=json
```

输出会类似于：

```
[
  {
    "name": "projects/my-project/locations/europe-west2/occurrences/abcdef123456...",
    "noteName": "projects/goog-analysis/notes/cyclonedx",
    "kind": "DISCOVERY",
    "remediation": "",
    "sbom": {
      "type": "cyclonedx",
      "version": "1.4",
      ...
    }
  }
]
```

---

## **🎯 如何获取镜像 digest？**

  

你可以通过以下命令获取镜像的 digest：

```
gcloud artifacts docker images list europe-west2-docker.pkg.dev/my-project/my-repo
```

输出类似：

```
IMAGE                                           DIGEST                                TAGS
europe-west2-docker.pkg.dev/.../my-app          sha256:1234abcd...                    latest
```

---

## **🧩 SBOM 文件下载（目前不支持直接导出文件）**

  

目前 gcloud artifacts sbom 仅列出 **SBOM Metadata 的 Occurrence 信息**，如你想获取 **完整 CycloneDX 文件**，推荐做法：

  

### **✅ 1. 在 CI 阶段用 Syft 自行生成 SBOM：**

```
syft europe-west2-docker.pkg.dev/my-project/my-repo/my-app:latest -o cyclonedx-json > sbom.json
```

### **✅ 2. 或使用 Container Analysis API 直接下载 Occurrence 内容（高级用法）**

---

## **⚠️ 注意事项**

- 当前 SBOM 支持仅限于 **Docker 镜像**，不能用于 Maven/NPM 等非容器包。
    
- 只有使用 GAR 存储容器镜像，并启用了 Container Analysis，才能看到 SBOM。
    

---

## **📌 推荐搭配（实战组合）**

|**动作**|**工具**|
|---|---|
|生成镜像|Docker / Cloud Build|
|上传到 GAR|docker push or gcloud|
|获取 SBOM 元数据|gcloud artifacts sbom list|
|本地生成 SBOM|syft <image>|
|扫描漏洞|grype sbom:sbom.json|

---

是否需要我帮你生成一个完整流程的 shell 脚本？比如：

- 获取镜像 digest
    
- 拉取 SBOM 元信息
    
- 或用 Syft 生成完整 SBOM + 扫描报告？