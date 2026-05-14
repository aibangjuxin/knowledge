# Debugging Guide: `package com.github.tomakehurst.wiremock.client does not exist`

当在 CI/CD Pipeline 中遇到 `package ... does not exist` 错误，但在本地开发环境一切正常时，问题几乎总是出在 **构建环境的差异** 上。本文档旨在提供一个完整的排查思路和解决方案，帮助你定位并解决此类问题。

## 1. 问题现象与核心结论

- **错误信息**: `package com.github.tomakehurst.wiremock.client does not exist`
- **环境**: 在 Pipeline CI 中构建时失败。
- **对比**: 在本地环境中构建和测试均成功。
- **核心结论**: CI 构建环境无法下载或找到 `wiremock` 的依赖包（JAR 文件）。

## 2. 根本原因分析：为什么 CI 环境找不到包？

Java 编译器在编译代码时，需要找到所有 `import` 语句对应的类定义。这个错误意味着编译器在指定的 `classpath` 中没有找到 `com.github.tomakehurst.wiremock.client` 这个类。

在 Maven 或 Gradle 项目中，`classpath` 是由构建工具根据 `pom.xml` 或 `build.gradle` 中定义的依赖自动管理的。因此，找不到包的直接原因就是 **依赖没有被成功下载到 CI 环境的本地仓库中**。

可能导致此问题的环境差异包括：

| 差异点                 | 本地环境 (通常成功)                                                              | CI/CD 环境 (可能失败)                                                                                             |
| ---------------------- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **依赖缓存**           | `~/.m2/repository` 或 `~/.gradle/caches` 中已存在历史下载的依赖包。                  | 通常是全新或隔离的环境，每次都需要重新下载依赖。                                                                    |
| **仓库配置 (`Repository`)** | 可能直接从公共仓库（如 Maven Central）下载。                                       | 常常被强制通过公司内部的私有仓库（如 Nexus, Artifactory）下载，该仓库可能没有同步 `wiremock` 包。                 |
| **网络访问**           | 开发网络通常比较开放，可以直接访问外部仓库。                                       | CI Runner 可能位于受限网络中，防火墙或网络策略会阻止对外部仓库（如 `repo.maven.apache.org`）的直接访问。        |
| **构建配置文件**       | 使用本地的 `~/.m2/settings.xml`。                                                  | CI 系统通常会注入一个全局的、标准化的 `settings.xml`，这个配置会覆盖项目或用户的设置，强制使用特定的镜像（Mirror）。 |
| **认证与授权**         | 本地环境可能已经配置好了访问私有仓库的凭证。                                       | CI 环境可能没有正确配置凭证，导致无法从需要认证的私有仓库下载。                                                   |

## 3. 排查步骤：从上到下定位问题

请在你的 CI/CD Pipeline 中按以下步骤执行诊断。

### 步骤 1: 确认依赖已在 `pom.xml` 中正确声明

首先，确保你的 `pom.xml` 文件中包含了 `wiremock` 的依赖。通常是 `wiremock-jre8`。

```xml
<dependency>
    <groupId>com.github.tomakehurst</groupId>
    <artifactId>wiremock-jre8</artifactId>
    <version>2.35.0</version> <!-- 请使用你的项目指定的版本 -->
    <scope>test</scope> <!-- 通常只在测试范围使用 -->
</dependency>
```

> **注意**: 如果 `scope` 是 `test`，请确保 CI 执行的是包含测试编译的构建阶段（如 `mvn package` 或 `mvn verify`），而不是 `mvn compile`。

### 步骤 2: 使用 Debug 模式重新运行构建

在 CI 的构建命令中增加 `-X` (Maven) 或 `--debug` (Gradle) 参数，以获取详细的日志输出。

- **Maven**: `mvn clean package -X`
- **Gradle**: `gradle clean build --debug`

然后，在构建日志中搜索以下关键字：

- `Downloading from:` 查看正在从哪个仓库下载。
- `Could not resolve dependencies` 或 `Failed to collect dependencies`
- `Could not find artifact com.github.tomakehurst:wiremock-jre8`
- `Failed to download`

这些日志会明确告诉你构建工具尝试从哪个 URL 下载，以及失败的原因。

### 步骤 3: 检查 CI 环境的有效仓库配置

CI 环境的仓库配置是排查的重中之重。

#### 对于 Maven:

在 CI 的脚本中增加一个诊断命令，打印出当前构建实际生效的配置：

```bash
# 这个命令会打印出所有合并后的配置，包括全局 settings.xml 和项目 pom.xml
mvn help:effective-settings
```

查看输出中的 `<mirrors>` 和 `<repositories>` 部分。确认：

1.  **镜像地址 (`<mirrorOf>`)**: 是否有 `*` 或 `central` 的镜像指向了公司内部的 Nexus/Artifactory？
2.  **仓库 URL**: 该 URL 是否可以正常访问？

#### 对于 Gradle:

检查 `build.gradle` 或 `settings.gradle` 中的 `repositories {}` 块。确认 CI 环境变量或 `init.gradle` 脚本没有覆盖这些配置。

### 步骤 4: 在 CI 环境中测试网络连通性

如果可能，在 CI 构建脚本中增加一个网络测试步骤，以确认构建容器可以访问目标仓库。

```bash
# 假设从 effective-settings 中看到的仓库 URL 是 https://nexus.my-company.com/repository/maven-public/
# 使用 curl 测试网络连通性
curl -v https://nexus.my-company.com/repository/maven-public/
```

如果 `curl` 失败或超时，说明是网络策略或防火墙问题，需要联系网络或运维团队解决。

### 步骤 5: 检查私有仓库中是否存在目标包

如果 CI 配置了私有仓库（Nexus/Artifactory），请登录其 Web UI，并搜索 `wiremock-jre8`。

- **确认是否存在**: 确保你 `pom.xml` 中指定的版本已被同步到私有仓库。
- **确认路径是否正确**: 检查仓库中的 GroupId, ArtifactId, Version 是否与 `pom.xml` 完全匹配。

如果不存在，你需要请求仓库管理员添加对 `wiremock` 的代理或手动上传。

### 步骤 6: 分析依赖树

在 CI 环境中运行依赖树命令，查看 `wiremock` 是否因为版本冲突而被忽略。

- **Maven**: `mvn dependency:tree`
- **Gradle**: `gradle dependencies`

在输出中搜索 `wiremock`，检查是否有 `omitted for conflict` 或其他异常信息。

## 4. 解决方案流程图

```mermaid
graph TD
    A[开始: CI 构建失败, 提示 "package does not exist"] --> B{本地是否成功?};
    B -- 是 --> C[确认 `pom.xml` 或 `build.gradle` 中已声明依赖];
    C --> D[在 CI 中执行 `mvn clean package -X` 获取详细日志];
    D --> E{日志中是否有 "Could not find artifact" 或 "Failed to download"?};
    E -- 是 --> F[执行 `mvn help:effective-settings` 查看有效仓库配置];
    F --> G{仓库是否为内部 Nexus/Artifactory?};
    G -- 是 --> H[登录 Nexus UI, 搜索 `wiremock` 指定版本是否存在];
    H -- 存在 --> I[在 CI 环境中用 `curl` 测试 Nexus URL 是否可达];
    I -- 不可达 --> J[**解决方案**: 网络/防火墙问题, 联系运维];
    I -- 可达 --> K[**解决方案**: 凭证问题或依赖冲突, 检查 `settings.xml` 凭证和 `mvn dependency:tree`];
    H -- 不存在 --> L[**解决方案**: 请求仓库管理员添加 `wiremock` 代理或手动上传];
    G -- 否 (如 Maven Central) --> M[在 CI 环境中用 `curl` 测试 `repo.maven.apache.org` 是否可达];
    M -- 不可达 --> J;
    M -- 可达 --> N[**解决方案**: 可能是 DNS 或其他罕见网络问题];
    E -- 否 --> O[检查 `scope` 是否为 `test` 且 CI 执行了测试阶段];
    B -- 否 --> P[本地环境也失败, 属于常规依赖问题, 检查本地配置];
```

通过以上步骤，你应该能够系统地定位并解决 CI 环境中的依赖问题。
