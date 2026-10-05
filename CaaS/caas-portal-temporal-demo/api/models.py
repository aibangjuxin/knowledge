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

from pydantic import BaseModel, Field, field_validator


class CloudProvider(str, Enum):
    GCP = "gcp"
    AWS = "aws"
    ALIYUN = "aliyun"
    ONPREM = "onprem"


class Tier(str, Enum):
    AUTOPILOT = "autopilot"
    STANDARD = "standard"


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
    tier: Tier = Tier.AUTOPILOT
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
        return v


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
