"""Temporal Activities — the actual work performed when the workflow needs
something external (HTTP call, IM notification, K8S API call).

Activities are the *real* workhorses; workflows are just the orchestration graph.
Each activity must be idempotent (Temporal may retry), so we lean on the
K8S stub which already handles `name`-scoped idempotency.

Mapping back to `caas-portal.md` §二:
  - validate_compliance_and_cost  → Activity _validate
  - request_human_approval         → Activity _request_approval
                                     (manual OR auto-approve based on ENABLE_AUTO_APPROVAL)
  - trigger_k8s_apply              → Activity _apply_to_k8s_stub
  - apply_policy_baseline          → Activity _apply_policy_baseline (stubbed inline)
"""

from __future__ import annotations

import asyncio
import os
from datetime import datetime, timezone

import httpx

from ..api.models import (
    ClusterRequestSpec,
    K8sStubApplyRequest,
    K8sStubApplyResponse,
    StageRecord,
    StageState,
    StatusVisualization,
    WorkflowStage,
)
from temporalio import activity

# Lazy import: the FastAPI app's StatusStore is the in-process pub/sub of the
# demo. In a real CaaS, status would live in the K8S ClusterRequest CRD and
# the workflow would Update Resource via the K8S API (see `gke-caas.md`).
try:
    from ..api.main import store as _status_store
except Exception:
    _status_store = None  # type: ignore[assignment]


K8S_STUB_URL = os.getenv("K8S_STUB_URL", "http://k8s_stub:8010")
ENABLE_AUTO_APPROVAL = os.getenv("ENABLE_AUTO_APPROVAL", "true").lower() == "true"
APPROVAL_DELAY = float(os.getenv("APPROVAL_DELAY_SECONDS", "1.5"))


def _update_status(
    name: str,
    workflow_id: str,
    started_at: datetime,
    expected_total_seconds: float,
    current_stage: WorkflowStage,
    new_state: StageState,
    *,
    actor: str | None = None,
    detail: str | None = None,
) -> None:
    """Build the next StatusVisualization from the existing one and publish it.

    If the store is unavailable (e.g. running outside FastAPI), this is a no-op.
    """
    if _status_store is None:
        return
    latest = _status_store.latest(name)
    if latest is None:
        return
    now = datetime.now(timezone.utc)
    next_stages: list[StageRecord] = []
    for stage in latest.stages:
        rec = stage
        if rec.key == current_stage:
            if new_state == StageState.RUNNING and rec.started_at is None:
                rec.started_at = now
            if new_state in {StageState.SUCCEEDED, StageState.FAILED}:
                rec.ended_at = now
            rec.state = new_state
            rec.actor = actor or rec.actor
            rec.detail = detail or rec.detail
        next_stages.append(rec)
    new_viz = latest.model_copy(
        update={
            "current_stage": current_stage,
            "current_state": new_state,
            "updated_at": now,
            "elapsed_seconds": (now - started_at).total_seconds(),
            "expected_total_seconds": expected_total_seconds,
            "stages": next_stages,
            "next_action": _next_action_text(current_stage, new_state),
        }
    )
    _status_store.put(new_viz)


def _next_action_text(stage: WorkflowStage, state: StageState) -> str:
    if state != StageState.RUNNING:
        return None  # type: ignore[return-value]
    return {
        WorkflowStage.VALIDATING: "校验合规 + 估算成本",
        WorkflowStage.APPROVAL_LEADER: "等待团队 leader 审批",
        WorkflowStage.APPROVAL_PM: "等待 PM 审批",
        WorkflowStage.APPROVAL_SECURITY: "等待 Security lead 审批",
        WorkflowStage.APPROVAL_SRE: "等待平台 SRE 终审",
        WorkflowStage.K8S_PROVISIONING: "等待基础设施部署完成",
        WorkflowStage.POLICY_INJECTION: "等待合规基线注入完成",
        WorkflowStage.READY: "就绪",
    }.get(stage, "进行中")


# --- Activities ---


@activity.defn(name="_validate")
async def validate_compliance_and_cost(
    name: str,
    spec: dict,
    workflow_id: str,
    started_at_iso: str,
) -> dict:
    """Validate spec + estimate cost.

    Real impl would call into:
      - `caas-compliance-baseline.md` Compliance Bot for spec → framework checks
      - `caas-finops.md` Cost Estimator for monthly cost
    """
    started_at = datetime.fromisoformat(started_at_iso)
    _update_status(
        name, workflow_id, started_at, 45.0,
        WorkflowStage.VALIDATING, StageState.RUNNING,
    )
    parsed = ClusterRequestSpec(**spec)

    # demo: fail-fast on autopilot + public network (mirrors CEL rule)
    if parsed.tier.value == "autopilot" and parsed.network.mode.value == "public":
        _update_status(
            name, workflow_id, started_at, 45.0,
            WorkflowStage.VALIDATING, StageState.FAILED,
            detail="Autopilot + public network is not allowed (mirror CEL rule)",
        )
        raise ValueError("autopilot+public network disallowed by ClusterSpec validation")

    # demo cost estimate using same logic as api/main.py
    estimated = (
        float(os.getenv("COST_PER_VCPU_MONTH", "20")) * 4
        + float(os.getenv("COST_PER_GB_MEM_MONTH", "4")) * 16
        + float(os.getenv("COST_PER_LB_MONTH", "20"))
    )
    if "baseline" not in parsed.compliance.frameworks or len(parsed.compliance.frameworks) > 1:
        estimated += float(os.getenv("COMPLIANCE_OVERHEAD_USD", "15"))

    await asyncio.sleep(0.5)  # pretend we're computing
    _update_status(
        name, workflow_id, started_at, 45.0,
        WorkflowStage.VALIDATING, StageState.SUCCEEDED,
        detail=f"monthly_usd≈{estimated:.2f}",
    )
    return {"estimated_monthly_cost_usd": round(estimated, 2), "estimated": True}


@activity.defn(name="_request_approval")
async def request_human_approval(
    name: str,
    workflow_id: str,
    started_at_iso: str,
    stage: str,
    role: str,
    sla_hours: float,
) -> str:
    """Simulate a human approval decision.

    ENABLE_AUTO_APPROVAL=true path: sleep then return 'approve'.
    Production path (per `caas-portal.md` §二): send webhook to IM, wait for
    a Signal response from the user clicking approve/reject in chat.
    """
    started_at = datetime.fromisoformat(started_at_iso)
    try:
        wf_stage = WorkflowStage(stage)
    except ValueError as exc:
        raise ValueError(f"unknown approval stage: {stage!r}") from exc
    _update_status(
        name, workflow_id, started_at, 45.0,
        wf_stage, StageState.RUNNING,
        actor=f"role:{role}",
        detail=f"SLA {sla_hours}h (demo auto-approve in {APPROVAL_DELAY}s)",
    )

    if ENABLE_AUTO_APPROVAL:
        await asyncio.sleep(APPROVAL_DELAY)
        decision = "approve"
        approver = f"demo-auto-{role}@company.com"
        _update_status(
            name, workflow_id, started_at, 45.0,
            wf_stage, StageState.SUCCEEDED,
            actor=approver,
        )
        return "approve"

    # Manual path: real CaaS would await a Signal here. demo just blocks.
    await asyncio.sleep(60 * 60 * 24)  # effectively infinite; demo uses auto-approval
    return "approve"  # pragma: no cover


@activity.defn(name="_apply_to_k8s_stub")
async def apply_to_k8s_stub(
    name: str,
    workflow_id: str,
    started_at_iso: str,
    apply_request: dict,
) -> dict:
    """POST to K8S stub; in real CaaS this is the Terraform / CAPI call."""
    started_at = datetime.fromisoformat(started_at_iso)
    _update_status(
        name, workflow_id, started_at, 45.0,
        WorkflowStage.K8S_PROVISIONING, StageState.RUNNING,
    )

    parsed = K8sStubApplyRequest(**apply_request)
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(f"{K8S_STUB_URL}/apply", json=parsed.model_dump())
        resp.raise_for_status()
        data = resp.json()

    result = K8sStubApplyResponse(**data)
    # poll until success/fail (stub completes in 3-6s)
    for _ in range(15):
        async with httpx.AsyncClient(timeout=10.0) as client:
            status_resp = await client.get(f"{K8S_STUB_URL}/status/{result.cluster_id}")
            status_resp.raise_for_status()
            status_data = status_resp.json()
        if status_data["status"] == "Succeeded":
            _update_status(
                name, workflow_id, started_at, 45.0,
                WorkflowStage.K8S_PROVISIONING, StageState.SUCCEEDED,
                detail=f"cluster_id={result.cluster_id}",
            )
            return status_data
        if status_data["status"] == "Failed":
            _update_status(
                name, workflow_id, started_at, 45.0,
                WorkflowStage.K8S_PROVISIONING, StageState.FAILED,
                detail=status_data.get("error", ""),
            )
            raise RuntimeError(f"K8S stub failed: {status_data.get('error')}")
        await asyncio.sleep(1.0)

    raise TimeoutError("K8S stub did not complete in time")


@activity.defn(name="_apply_policy_baseline")
async def apply_policy_baseline(
    name: str,
    workflow_id: str,
    started_at_iso: str,
    cluster_id: str,
    frameworks: list[str],
) -> dict:
    """Apply Kyverno/OGA policies to the new cluster — stubbed.

    Real impl:
      - render Kyverno ClusterPolicy from frameworks (see `caas-compliance-baseline.md` §二)
      - push via ClusterResourceSet (CAPI path) OR direct API apply

    For demo we just sleep + mark success.
    """
    started_at = datetime.fromisoformat(started_at_iso)
    _update_status(
        name, workflow_id, started_at, 45.0,
        WorkflowStage.POLICY_INJECTION, StageState.RUNNING,
    )
    await asyncio.sleep(1.0)
    _update_status(
        name, workflow_id, started_at, 45.0,
        WorkflowStage.POLICY_INJECTION, StageState.SUCCEEDED,
        detail=f"frameworks={','.join(frameworks)}",
    )
    return {"applied": frameworks, "cluster_id": cluster_id}
