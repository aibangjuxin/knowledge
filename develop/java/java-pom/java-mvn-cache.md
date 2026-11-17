# Maven Cache Issues in Java/Spring Boot Projects

## Problem Description

一般有这样的问题都是什么原因可能造成的？有什么快速的办法可以解决这个问题，或者说有排查的过程

below errors:

When I use below 2 pipelines to do deployment, it failed at "deploy to DEV" stage, when I check the GCP log, it have

Logs Explorer - Logging - Google Cloud console

java. lang.NoSuchMethodError: org-yaml. snakeyaml. representer.Representer: method <init>()V

not found at

org.springframework.boot.env.OriginTrackedYamlLoader.createYaml(OriginTrackedYamlLoader-java

:76) ~[spring-boot-2.6.6.jar!/:2.6.6] at

org.springframework.boot.env.OriginTrackedYamlLoader.createYaml|OriginTrackedYamlLoader.java

:71) ~[spring-boot-2.6.6.jar!/:2.6.6]

below api can start up at local, according the pom dependency tree, the spring-boot version should be 2.7.10 instead of 2.6.6, could you please help check why the server still use the cached/old dependency?

---

## Overview

下面这个问题**本质上是一个典型的 Java / Spring Boot 依赖冲突 + 构建产物不一致问题**，在 CI/CD（尤其是多 pipeline、GKE 部署）场景里非常常见。

我按你要求给你一个**可落地的排查路径 + 快速止血方案**。

---

## 1. Problem Analysis (Core Cause)

### 1.1 Error Essence

```
java.lang.NoSuchMethodError:
org.yaml.snakeyaml.representer.Representer.<init>()V not found
```

This is **typical runtime dependency version incompatibility error**:

- **Compile time**: Using new version of snakeyaml
- **Runtime**: Classpath actually loads old version of snakeyaml
- Spring Boot **2.6.x / 2.7.x have different requirements for SnakeYAML constructor**

> ❗ NoSuchMethodError ≠ Compile error

> ❗ 100% is **Jar conflict / old dependency being loaded**

### 1.2 Key Exception Point (Very Important)

Log clearly shows:

```
[spring-boot-2.6.6.jar!/:2.6.6]
```

⚠️ **This indicates your final runtime artifact still contains spring-boot-2.6.6**

Even if you see locally:

```
spring-boot 2.7.10
```

**The Jar / Image deployed to GCP is not the version you think it is**

---

## 2. Most Common 5 Causes (Ranked by Probability)

### ✅ Cause 1 (90%): CI Pipeline Uses Cached Old Build Artifacts

**Typical scenario**

- Maven / Gradle cache
- Docker layer cache
- Artifact Registry / GCR image tag reuse (latest)

**Symptoms**

- Local OK
- CI OK
- Runtime reports old version

### ✅ Cause 2: Dockerfile Build Stage Does Not Trigger Repackaging

Example problem:

```
COPY target/app.jar app.jar
```

But:

- target/app.jar is actually the previous pipeline's artifact
- Maven does not actually execute repackage

### ✅ Cause 3: Parent POM / BOM Versions Not Unified in Multi-Module Projects

```
<parent>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-parent</artifactId>
  <version>2.6.6</version>
</parent>
```

But in submodules:

```
<spring-boot.version>2.7.10</spring-boot.version>
```

👉 **Parent POM takes precedence**

### ✅ Cause 4: Snakeyaml Version Pulled Down by Other Dependencies Explicitly or Implicitly

Common "culprits":

- spring-cloud
- swagger
- kafka
- Old commons-\*

### ✅ Cause 5: GKE Uses Old Image / Rollout Did Not Happen

- Deployment did not change image tag
- Pod actually did not rebuild
- Node pulls old image

---

## 3. Quick Fix Solutions (Immediately Available)

### ✅ Solution 1: Force Cleanup + Rebuild (Most Recommended)

#### Pipeline must include

```
mvn clean package -U
```

Or (Gradle):

```
./gradlew clean build --refresh-dependencies
```

### ✅ Solution 2: Disable Docker Cache (One-time Verification)

```
docker build --no-cache -t your-image:dev .
```

### ✅ Solution 3: Explicitly Pin SnakeYAML Version (Short-term Fallback)

```
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.yaml</groupId>
      <artifactId>snakeyaml</artifactId>
      <version>1.33</version>
    </dependency>
  </dependencies>
</dependencyManagement>
```

> ⚠️ This is **bleeding control solution, not root cause fix**

---

## 4. Standard Troubleshooting Process (Strongly Recommended to Follow in Order)

### Step 1: Confirm What Version is Actually in the Final Jar (Key)

```
jar tf app.jar | grep spring-boot
```

Or:

```
jar tf app.jar | grep snakeyaml
```

You'll **directly see 2.6.6 or 2.7.10**

### Step 2: Confirm Runtime Classpath in Container

```
kubectl exec -it pod-name -- sh
```

```
ls /app/libs | grep yaml
```

Or:

```
java -verbose:class -jar app.jar | grep snakeyaml
```

### Step 3: Maven Dependency Reverse Lookup (Focus)

```
mvn dependency:tree | grep snakeyaml
```

If you see multiple versions:

```
snakeyaml:1.26
snakeyaml:1.33
```

👉 **100% will fail**

### Step 4: Confirm Spring Boot True Source

```
mvn help:effective-pom | grep spring-boot
```

You'll see:

- Whether it's parent
- Or BOM
- Or overridden by dependencyManagement

### Step 5: Confirm Rollout Actually Happened at GKE Level

```
kubectl rollout status deploy your-app
kubectl describe pod your-pod | grep Image
```

---

## 5. Best Practices (Prevent Recurrence)

### ✅ 1: CI Force Fast Fail

```
mvn -DskipTests=false clean verify
```

### ✅ 2: Image Tag Prohibit Use of Latest

```
app:dev-20260102-commitSHA
```

### ✅ 3: Spring Boot / Cloud Version Matrix Check

| **Spring Boot** | **Recommended SnakeYAML** |
| --------------- | ------------------------- |
| 2.6.x           | 1.30                      |
| 2.7.x           | 1.33                      |

### ✅ 4: Build Artifact Verification (Very Important)

Add a step in pipeline:

```
java -jar app.jar --version
```

Or:

```
unzip -p app.jar META-INF/MANIFEST.MF
```

---

## 6. One-Sentence Summary

> **Not GCP cache issue, but build artifacts inconsistent with runtime artifacts**

> **Spring Boot 2.6.6 Jar is actually running, causing SnakeYAML constructor mismatch**

---

If willing, I can directly help you:

- **Review POM (parent + BOM)**
- **Check if Dockerfile has cache traps**
- **Give you a "dependency drift prevention" CI template**

You just need to paste one of them.

---

## Complete Solution Set ("Directly Implementable + Long-term Governance")

This is specifically for:

👉 **CI Pipeline uses cached old build artifacts**

👉 **Local OK / CI OK / Runtime reports old version**

👉 **Maven / Docker / GCR(latest) triple cache叠加**

I'll follow **Problem → Fix → Standard → Verification** four levels.

---

## 1. Problem Essence Review (First Unify Understanding)

> **CI success ≠ Runtime uses new build artifacts**

Your scenario essence is **"build pipeline cache failure at any layer"**:

```
Source code update
  ↓
Maven / Gradle cache (not refreshed)
  ↓
Docker layer cache (COPY reuse)
  ↓
Image tag reuse (latest)
  ↓
GKE Pod does not actually use new image
```

**As long as any intermediate layer reuses old content, it will cause:**

- Jar still contains spring-boot-2.6.6
- Runtime directly throws NoSuchMethodError

---

## 2. Complete Fix Solution (4 Layers)

### Layer 1: Build Tool Layer (Maven / Gradle)

#### ✅ Goal

**Ensure every CI build produces a new Jar**

#### ✅ Maven Standard Fix Solution (Recommended)

##### Pipeline must force use

```
mvn clean package -U
```

Explanation:

| **Parameter** | **Function**                      |
| ------------- | --------------------------------- |
| clean         | Delete target, avoid old jar      |
| -U            | Force refresh SNAPSHOT / metadata |
| package       | Trigger spring-boot repackage     |

#### 🚫 Error Example (Very Common)

```
mvn package
```

Problems:

- Does not clear target
- Does not refresh dependencies
- **Very prone to issues** when CI Workspace is reused

#### ✅ Gradle Corresponding Solution

```
./gradlew clean build --refresh-dependencies
```

#### 🔒 Recommended Enhancement (Prevent Hidden Failures)

Add in CI:

```
mvn help:effective-pom | grep spring-boot
```

If not expected version, **directly fail pipeline**

### Layer 2: Docker Build Layer (Easiest to Fall Into Pit)

#### 2.1 Dockerfile Structure Standardization (Strongly Recommended)

##### ❌ High-risk Dockerfile

```
COPY target/app.jar app.jar
```

Problem:

- As long as target/app.jar file timestamp does not change
- Docker will directly reuse layer

##### ✅ Correct Multi-stage Build (Best Practice)

```
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=builder /build/target/app.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
```

Advantages:

| **Advantage**             | **Explanation**                 |
| ------------------------- | ------------------------------- |
| Maven build in container  | Does not depend on CI Workspace |
| Target not reused         | Completely cut off old jar      |
| Docker cache controllable | Cache only when pom changes     |

#### 2.2 CI Forced Verification Stage (Very Important)

```
docker run --rm your-image java -jar /app/app.jar --version
```

> **Verify Jar actual version before push**

#### 2.3 Emergency Stop (One-time)

```
docker build --no-cache -t your-image:dev .
```

⚠️ For verification only, not recommended for long-term use

### Layer 3: Image Registry Layer (Artifact Registry / GCR)

#### ❌ High-risk Behavior (Must Prohibit)

```
image: your-app:latest
```

**latest = uncontrollable + un-auditable + un-rollbackable**

#### ✅ Standard Image Tag Strategy (Strongly Recommended)

```
your-app:
  dev-20260102-<git-sha>
  prod-20260102-<git-sha>
```

Example:

```
IMAGE_TAG=dev-$(date +%Y%m%d)-$(git rev-parse --short HEAD)
docker build -t us-docker.pkg.dev/proj/repo/app:$IMAGE_TAG .
docker push us-docker.pkg.dev/proj/repo/app:$IMAGE_TAG
```

#### ✅ GKE Deployment Force Use New Tag

```
spec:
  containers:
  - name: app
    image: us-docker.pkg.dev/proj/repo/app:dev-20260102-a1b2c3
    imagePullPolicy: IfNotPresent
```

#### 🚫 Do Not Rely On

```
imagePullPolicy: Always
```

👉 **It cannot solve the "Jar itself is old" problem**

### Layer 4: GKE Runtime Verification (Last Line of Defense)

#### 4.1 Confirm Pod Actually Uses Image

```
kubectl describe pod <pod> | grep Image
```

#### 4.2 Confirm Jar Content in Pod (Recommended)

```
kubectl exec -it <pod> -- sh
```

```
jar tf /app/app.jar | grep spring-boot
```

Or:

```
java -verbose:class -jar /app/app.jar | grep snakeyaml
```

#### 4.3 Force Rebuild (If Necessary)

```
kubectl rollout restart deploy your-app
```

---

## 3. CI Pipeline Standard Template (Directly Usable)

```
steps:
  - name: build
    script:
      - mvn clean package -U
      - jar tf target/app.jar | grep spring-boot

  - name: docker-build
    script:
      - IMAGE_TAG=dev-${CI_COMMIT_SHORT_SHA}
      - docker build -t app:$IMAGE_TAG .
      - docker run --rm app:$IMAGE_TAG java -jar /app/app.jar --version

  - name: docker-push
    script:
      - docker push app:$IMAGE_TAG

  - name: deploy
    script:
      - kubectl set image deploy/app app=app:$IMAGE_TAG
```

---

## 4. Long-term Governance Recommendations (Prevent Recurrence)

| **Layer** | **Rule**                    |
| --------- | --------------------------- |
| Maven     | Must clean                  |
| Docker    | Multi-stage build           |
| Image     | Disable latest              |
| CI        | Verify Jar after build      |
| GKE       | Tag change triggers rollout |

---

## 5. One-Sentence Summary (For External Use)

> **This is a typical CI build cache pollution problem**

> **Root cause is not GCP, but Jar build, Docker layer, Image tag three-layer cache叠加**

> **Solution must tighten from build, image, deployment three ends simultaneously**

---

If willing, I can next:

- 🔍 **Directly help review a Dockerfile**
- 🔍 **Give your existing CI Pipeline "cache prevention patches"**
- 🔍 **Output a "Platform-level Java Service Build Specification"**

Choose one, I'll give directly.

---

## Standardized Troubleshooting Information Collection Plan

This is for **"directly give to user / team"**, goal is only one:

> **With minimal back-and-forth, confirm once and for all whether CI used cache, whether it produced old Jar**

This is not a technical implementation plan, but **how you as platform / infrastructure side "correctly ask user for information"**.

---

## 1. Positioning Strategy (First Give You the Idea)

You have already made **correct judgment**:

- ❌ Do not dwell on Spring / SnakeYAML details
- ✅ Preliminary positioning to **CI build artifacts ≠ runtime artifacts**

So when you ask user for information, **must focus on these three points**:

```
1. When and at which step was Jar generated?
2. Did Docker reuse old layer?
3. Does GKE actually run new Image?
```

---

## 2. User's [Information Collection Checklist] — Directly Usable

> ✅ Suggest you **send to user as-is**

> This is platform perspective, very professional, will not cause other party's resistance

### 2.1 CI Pipeline Build Stage Information (Most Critical)

Please provide **complete build log** for following key points (not screenshot, is original log):

#### A. Maven / Gradle Execution Command

```
✔️ Complete mvn / gradle command
✔️ Whether includes clean / -U / --refresh-dependencies
```

Example (correct):

```
mvn clean package -U
```

Example (high-risk):

```
mvn package
```

#### B. Build Artifact Confirmation (Must)

Please add in CI and paste following output:

```
jar tf target/*.jar | grep spring-boot
```

Or:

```
unzip -p target/*.jar META-INF/MANIFEST.MF
```

**Purpose**: Confirm **actual Spring Boot version in Jar**

### 2.2 Docker Build Stage Information (90% of pit is here)

Please provide:

#### A. Complete Dockerfile

Pay special attention to:

```
COPY target/*.jar
```

And whether used:

```
--from=builder
```

#### B. Docker Build Log (Key Keywords)

Have user check and provide log lines containing following keywords:

```
Using cache
CACHED
#x CACHED
```

You can directly tell user:

> If build log contains Using cache, please paste all of them

#### C. Docker Build Command

```
docker build -t xxx .
```

Or:

```
docker build --no-cache
```

### 2.3 Image Tag & Push Information (Very Easy to Overlook)

Please provide:

```
✔️ Image complete name (with tag)
✔️ Push log
```

You need to focus on:

```
Successfully pushed
digest: sha256:xxxx
```

### 2.4 Deployment Stage (GKE / Cloud Run)

#### A. Image Used by Deployment

```
kubectl describe pod <pod> | grep Image
```

Or in Deployment YAML:

```
image: xxx:???
```

#### B. Whether Rollout Actually Happened

```
kubectl rollout history deploy <name>
```

### 2.5 Runtime Verification (Final Confirmation)

Have user **choose one** to execute in Pod:

```
jar tf /app/app.jar | grep spring-boot
```

Or:

```
java -verbose:class -jar /app/app.jar | grep snakeyaml
```

---

## 3. Keywords You Need to "Unlock" in Logs (Focus)

When looking at user CI logs, only focus on these keywords:

### 🔍 Maven / Gradle

```
Reactor Build Order
Skipping tests
BUILD SUCCESS
```

⚠️ But focus is whether has:

```
Cleaning target
Downloading from central
```

### 🔍 Docker

```
Using cache
CACHED
Step X/Y
COPY target
```

Once see:

```
COPY target/app.jar
 ---> Using cache
```

👉 **Can directly conclude: old Jar reused**

### 🔍 Image Tag

```
latest
dev
stable
```

As long as see latest, directly mark red

---

## 4. [Standard Positioning Language] You Can Give User

> You can copy and use directly 👇

> From current error, this is **runtime loaded old Spring Boot dependency** typical problem

> Preliminary judgment **not code problem**, but **CI build artifacts or Docker build stage reused cache**

> To further confirm, please provide following information (to confirm whether final running Jar is latest build):

1. > CI Maven / Gradle complete execution command
2. > CI jar tf target/\*.jar | grep spring-boot output
3. > Dockerfile text + docker build log (focus on whether Using cache appears)
4. > Actually deployed Image name (with tag)
5. > Pod internal view Jar version output

> With above information, can directly locate whether old build artifacts used due to cache.

---

## 5. Platform-side "Fallback Recommendation" (Optional but High Value)

You can additionally recommend user:

- In CI **temporarily add**

```
mvn clean package -U
docker build --no-cache
```

- If problem disappears 👉 **100% cache problem**

---

## 6. One-Sentence Summary (For Yourself)

> **This stage is not solving problem, but "converging evidence"**

> **What you want is: build command, Jar content, Docker cache hit point**

> **As long as these three points obtained, problem is basically over**

---

If willing, I can next help you:

- 🧩 **Design a platform-unified CI Debug Checklist (Markdown)**
- 🧩 **Help you solidify these check items into CI template**
- 🧩 **Simulate a user CI log, I'll help you quick read**

Choose one, I'll give directly.
