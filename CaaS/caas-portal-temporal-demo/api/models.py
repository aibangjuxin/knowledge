"""Pydantic data models for the CaaS Portal Temporal Demo.

These models intentionally mirror `caas-portal.md` §二 审批流 input schema
and `gke-caas.md` ClusterRequest CRD fields. The demo only implements a
subset, but the shape matches production intent so that swapping the stub
for a real CaaS Controller is mostly a 1:1 mapping.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class CloudProvider(str, Enum):
    GCP = "gcp"
    AWS = "aws"
    ALIYUN = "aliyun"
    ONPREM = "onprem"


class Tier(str, Enum):
    # ⚠️ C3 修复(2026-10-05):Autopilot 已从 schema 移除,不再是 golden path。
    # DC 立场确认全量 Standard;`gke-caas.md` 的 CRD 已锁死 enum ["standard"]。
    # 保留这个单值 enum 而不是删掉字段,是为了:
    #   1) 保持请求结构向前兼容(旧客户端仍会发 tier 字段)
    #   2) 让"为什么没有 autopilot"在代码里可见,而不是靠 git 历史
    # 若将来某画像需要 Autopilot,应新增**画像 + 独立 module**,不是往回加 enum 值。
    STANDARD = "standard"


class Environment(str, Enum):
    """C9 配套:环境标识。prod 触发更严格的版本与 EOL 规则。"""

    PROD = "prod"
    STAGING = "staging"
    DEV = "dev"


class ReleaseChannel(str, Enum):
    """C9 修复:release channel 锁死 STABLE。"""

    STABLE = "STABLE"


class VersionStrategy(BaseModel):
    """C9 修复:对应 `gke-caas.md` CRD 的 versionStrategy 字段。"""

    channel: ReleaseChannel = ReleaseChannel.STABLE
    minor_upgrade_policy: Literal["auto", "manual-soak"] = "auto"
    eol_notice_days: int = Field(default=60, ge=30, le=180)
    allow_eol_emergency_exclusion: bool = False

    @field_validator("channel", mode="before")
    @classmethod
    def _no_other_channel(cls, v: object) -> object:
        # enum 已经挡住其它值;这里保留显式报错,是为了给出可读的错误信息
        # 而不是让调用方看到 "Input should be 'STABLE'"。
        if isinstance(v, str) and v.strip().upper() not in ("STABLE",):
            raise ValueError(
                f"release channel 锁定为 STABLE,收到 {v!r}。"
                "Rapid 排除在 GKE SLA 之外;Extended 与 DC 基线(Config Sync/Policy Controller)冲突。"
            )
        return v


class NetworkMode(str, Enum):
    PRIVATE = "private"
    PUBLIC = "public"


class GatewayStrategyMode(str, Enum):
    PER_NAMESPACE = "per-namespace"
    SHARED = "shared"
    PER_CLUSTER = "per-cluster"


class IsolationLevel(str, Enum):
    NAMESPACE = "namespace"
    CLUSTER = "cluster"


class ComplianceSpec(BaseModel):
    """Subset of `caas-compliance-baseline.md` §三 ClusterSpec.compliance field."""

    frameworks: list[str] = Field(
        default_factory=lambda: ["baseline"],
        description="baseline | pci-dss | pip | soc2 | iso27001",
    )
    data_residency_region_constraint: Literal["cn", "eu", "us", "any"] = "any"


class CostAllocationSpec(BaseModel):
    rule: Literal["usage-based", "static", "revenue-based"] = "usage-based"
    monthly_budget_usd: float = Field(default=5000.0, ge=0)


class GatewayStrategy(BaseModel):
    mode: GatewayStrategyMode = GatewayStrategyMode.PER_NAMESPACE
    initial_shards: int = Field(default=3, ge=1, le=20)


class NetworkSpec(BaseModel):
    mode: NetworkMode = NetworkMode.PRIVATE
    vpc: str = Field(min_length=1)
    subnet: str = Field(min_length=1)


class MultiTenancySpec(BaseModel):
    isolation_level: IsolationLevel
    teams: list[str] = Field(default_factory=list)


class ClusterRequestSpec(BaseModel):
    """Subset of ClusterRequest CRD from `gke-caas.md` ClusterSpec field."""

    cloud_provider: CloudProvider
    region: str = Field(pattern=r"^[a-z0-9-]+$")
    # ⚠️ C3 修复(2026-10-05):tier 锁死 standard,无 default。
    #   原为 `tier: Tier = Tier.AUTOPILOT` —— DC 立场是全量 Standard,
    #   这个默认值会让第一份请求就走错分支。理由见 `gke-caas.md` C3 章节。
    tier: Tier = Tier.STANDARD
    environment: Environment = Environment.PROD
    # C9 修复:versionStrategy 提升为显式字段(CRD 中已是 required)。
    version_strategy: VersionStrategy = Field(default_factory=VersionStrategy)
    network: NetworkSpec
    gateway_strategy: GatewayStrategy = Field(default_factory=GatewayStrategy)
    multi_tenancy: MultiTenancySpec
    compliance: ComplianceSpec = Field(default_factory=ComplianceSpec)
    cost_allocation: CostAllocationSpec = Field(default_factory=CostAllocationSpec)

    @field_validator("multi_tenancy")
    @classmethod
    def _teams_required_when_namespace(cls, v: MultiTenancySpec) -> MultiTenancySpec:
        # Mirror the CEL rule from `gke-caas.md` CEL § x-kubernetes-validations
        if v.isolation_level == IsolationLevel.NAMESPACE and not v.teams:
            raise ValueError("multi_tenancy.teams must be non-empty when isolation_level=namespace")
        # C3/C6 修复(2026-10-05):原 Autopilot CEL 规则失去判据(tier 已锁死),
        # 改为对 Standard 同样成立的隔离约束 —— 独占集群也必须知道归谁管。
        if v.isolation_level == IsolationLevel.CLUSTER and not v.teams:
            raise ValueError("multi_tenancy.teams must be non-empty when isolation_level=cluster")
        return v

    @model_validator(mode="after")
    def _prod_forbids_eol_emergency_exclusion(self) -> ClusterRequestSpec:
        # Mirror the C9 CEL rule:生产集群不得开启 allowEolEmergencyExclusion
        if (
            self.environment is Environment.PROD
            and self.version_strategy.allow_eol_emergency_exclusion
        ):
            raise ValueError(
                "生产集群不得开启 allow_eol_emergency_exclusion:"
                "官方不推荐该做法,紧急情况走 break-glass 流程"
            )
        return self


class ClusterRequestCreate(BaseModel):
    name: str = Field(pattern=r"^[a-z][a-z0-9-]{2,62}$", description="Cluster name")
    spec: ClusterRequestSpec


# --- Workflow output types ---


class WorkflowStage(str, Enum):
    PENDING = "pending"
    VALIDATING = "validating"
    APPROVAL_LEADER = "approval_team_leader"
    APPROVAL_PM = "approval_pm"
    APPROVAL_SECURITY = "approval_security_lead"
    APPROVAL_SRE = "approval_platform_sre"
    K8S_PROVISIONING = "k8s_provisioning"
    POLICY_INJECTION = "policy_injection"
    READY = "ready"
    FAILED = "failed"


class StageState(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    BLOCKED = "blocked"
    FAILED = "failed"


class StageRecord(BaseModel):
    key: WorkflowStage
    label: str
    state: StageState
    started_at: datetime | None = None
    ended_at: datetime | None = None
    actor: str | None = None
    detail: str | None = None


class StatusVisualization(BaseModel):
    """Payload for `caas-portal.md` §三 1 — Portal status feed."""

    request_name: str
    workflow_id: str
    current_stage: WorkflowStage
    current_state: StageState
    started_at: datetime
    updated_at: datetime
    elapsed_seconds: float
    expected_total_seconds: float
    stages: list[StageRecord]
    blocked_reason: str | None = None
    next_action: str | None = None


class K8sStubApplyRequest(BaseModel):
    """What we send to k8s_stub for the simulated Terraform apply."""

    name: str
    cloud_provider: CloudProvider
    region: str
    tier: Tier
    compliance_frameworks: list[str]
    estimated_monthly_cost_usd: float


class K8sStubApplyResponse(BaseModel):
    cluster_id: str
    status: Literal["Running", "Succeeded", "Failed"]
    estimated_completion_seconds: float


class FinalResult(BaseModel):
    approved: bool
    rejected_by: str | None = None
    cluster_id: str | None = None
    cluster_endpoint: str | None = None
