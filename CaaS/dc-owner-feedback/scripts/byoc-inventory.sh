#!/usr/bin/env bash
# byoc-inventory.sh —— 存量 GKE 集群清单采集(只读)
#
# 安全性:仅调用 gcloud list/describe,不产生任何写操作。
# 建议先在非生产账号下跑通,确认输出字段无误。
#
# 用法:
#   ./byoc-inventory.sh > byoc-inventory.json
#
# 前置:gcloud auth 有效,且账号对目标项目有 container.clusters.get 权限。

set -euo pipefail

PROJECT="${PROJECT:?必须指定 PROJECT 环境变量,例:PROJECT=my-project ./byoc-inventory.sh}"
STABLE_CHANNEL="Stable"

echo "==> 采集项目 ${PROJECT} 的 GKE 集群…" >&2

gcloud container clusters list \
  --project "${PROJECT}" \
  --format=json > /tmp/byoc-clusters-raw.json

# 提取分类所需的最小字段集
jq '[
  .[] | {
    name:              .name,
    location:          .location,
    status:            .status,
    currentMasterVersion: .currentMasterVersion,
    releaseChannel:    (.releaseChannel.channel // "Unspecified"),
    # 网络模式:Autopilot 必须 private;Standard 可 private 或 public
    privateCluster:    (.privateClusterConfig // {} | has("enablePrivateEndpoint") | not),
    autopilotEnabled:  (.autopilot.enabled // false),
    # 版本 skew 校验需要节点池版本
    nodePoolVersions:  [(.nodePools[]?.version // "unknown")],
    # 集群创建时间(EOL 风险参考)
    createTime:        .createTime,
    # 标签:责任人 / 业务线通常挂在这里
    resourceLabels:    (.resourceLabels // {}),
    # 归属信息(GKE 里常常缺失,需从别处补)
    description:       (.description // ""),
    # Fleet 归组(rollout sequencing 前提)
    fleetMembership:   (.fleetMembership // "none"),
    # 备份/DR 证据
    backupConfig:      (.backupConfig // null),
    # 网络 Policy
    networkPolicyEnabled: ((.networkPolicy // {}).enabled // false),
    # Security posture 证据
    securityPostureConfig: (.securityPostureConfig // null)
  }
]' /tmp/byoc-clusters-raw.json
