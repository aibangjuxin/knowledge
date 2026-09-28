"""FastAPI app: HTTP entry surface for the CaaS Portal demo.

Two endpoints:
  - POST /api/v1/requests: submit a ClusterRequest, kicks off Temporal workflow
  - GET  /api/v1/requests/{name}/status: poll-based status fetch
  - GET  /api/v1/requests/{name}/stream: SSE stream of stage transitions
  - POST /api/v1/approvals/{name}/{stage}: manual approval endpoint
      (only used when ENABLE_AUTO_APPROVAL=false)

Real-world extension (see ../caas-portal.md §二):
  - Replace ENABLE_AUTO_APPROVAL with a real IM webhook that requires humans
  - Replace k8s_stub with real GKE/EKS Adapter (see ../caas-providers.md)
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

from temporalio.client import Client as TemporalClient

from .models import (
    ClusterRequestCreate,
    K8sStubApplyRequest,
    K8sStubApplyResponse,
    StageRecord,
    StageState,
    StatusVisualization,
    WorkflowStage,
)

TEMPORAL_ADDRESS = os.getenv("TEMPORAL_ADDRESS", "temporal:7233")
TEMPORAL_NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "caas-cluster-request-tq")

app = FastAPI(title="CaaS Portal API", version="0.1.0")


# --- Temporal client lifecycle ---


@app.on_event("startup")
async def _startup() -> None:
    """Connect lazily on first request to avoid blocking docker compose boot."""
    app.state.temporal = None  # type: ignore[attr-defined]


async def get_temporal_client() -> TemporalClient:
    client = getattr(app.state, "temporal", None)  # type: ignore[attr-defined]
    if client is None:
        client = await TemporalClient.connect(
            target_host=TEMPORAL_ADDRESS,
            namespace=TEMPORAL_NAMESPACE,
        )
        app.state.temporal = client  # type: ignore[attr-defined]
    return client  # type: ignore[return-value]


# --- Status store (in-memory; real CaaS would persist to DB / K8S informer) ---
# In a real CaaS, you would NOT keep in-memory status; status is sourced from
# K8S informer on the corresponding ClusterRequest CRD (`gke-caas.md`).
# We use this dict only to feed the SSE stream here in the demo.
class StatusStore:
    def __init__(self) -> None:
        self._latest: dict[str, StatusVisualization] = {}
        self._subscribers: dict[str, list] = {}

    def put(self, viz: StatusVisualization) -> None:
        self._latest[viz.request_name] = viz
        for q in self._subscribers.get(viz.request_name, []):
            q.append(viz.model_dump_json())

    def latest(self, name: str) -> StatusVisualization | None:
        return self._latest.get(name)

    def subscribe(self, name: str) -> list:
        q: list = []
        self._subscribers.setdefault(name, []).append(q)
        return q


store = StatusStore()


# --- Helpers ---


def _estimate_monthly_cost(spec: dict) -> float:
    """Rough cost estimator inspired by `caas-finops.md` §五 / 4.

    Real implementation would query historical clusters in FinOps warehouse.
    For demo, we just apply a rule of thumb: small overhead fixed cost +
    per-vCPU/GB estimate. Re-running estimate per spec so the user sees the
    number before they submit.
    """
    vc = float(os.getenv("COST_PER_VCPU_MONTH", "20"))
    mc = float(os.getenv("COST_PER_GB_MEM_MONTH", "4"))
    lb = float(os.getenv("COST_PER_LB_MONTH", "20"))
    co = float(os.getenv("COMPLIANCE_OVERHEAD_USD", "15"))

    # demo defaults: 4 vCPU × 16GB × 1 cluster + 1 LB
    base = vc * 4 + mc * 16 + lb

    compliance = co if spec.get("compliance", {}).get("frameworks", ["baseline"]) != ["baseline"] else 0
    return round(base + compliance, 2)


# --- Endpoints ---


@app.post("/api/v1/requests", status_code=201)
async def submit_request(payload: ClusterRequestCreate, request: Request) -> dict:
    client = await get_temporal_client()

    # 1. Pre-flight cost estimate
    estimated_cost = _estimate_monthly_cost(payload.spec.model_dump())

    # 2. Initialize status entry so UI can render immediately
    initial = StatusVisualization(
        request_name=payload.name,
        workflow_id=f"caas-{payload.name}-{uuid.uuid4().hex[:6]}",
        current_stage=WorkflowStage.PENDING,
        current_state=StageState.PENDING,
        started_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
        elapsed_seconds=0.0,
        expected_total_seconds=45.0,
        stages=[
            StageRecord(key=WorkflowStage.VALIDATING, label="校验中", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.APPROVAL_LEADER, label="团队 Leader 审批", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.APPROVAL_PM, label="PM 审批(仅 prod)", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.APPROVAL_SECURITY, label="Security 审批(仅 pci-dss)", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.APPROVAL_SRE, label="平台 SRE 终审", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.K8S_PROVISIONING, label="基础设施部署(Terraform stub)", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.POLICY_INJECTION, label="合规基线注入", state=StageState.PENDING),
            StageRecord(key=WorkflowStage.READY, label="集群 Ready", state=StageState.PENDING),
        ],
        next_action="等待工作流启动",
    )
    store.put(initial)

    # 3. Kick off Temporal workflow
    handle = await client.start_workflow(
        "ClusterRequestWorkflow",
        payload.model_dump(),
        id=initial.workflow_id,
        task_queue=TASK_QUEUE,
        # Default id_reuse_policy is ALLOW_DUPLICATE which is what we want
        # for a one-shot request (see Temporal docs).
    )

    # 4. Return workflow handle + estimate to caller
    return {
        "workflow_id": initial.workflow_id,
        "request_name": payload.name,
        "estimated_monthly_cost_usd": estimated_cost,
        "status_url": f"/api/v1/requests/{payload.name}/status",
        "stream_url": f"/api/v1/requests/{payload.name}/stream",
        "run_id": handle.run_id,
    }


@app.get("/api/v1/requests/{name}/status", response_model=StatusVisualization)
async def get_status(name: str) -> StatusVisualization:
    viz = store.latest(name)
    if viz is None:
        raise HTTPException(status_code=404, detail=f"ClusterRequest {name!r} not found")
    return viz


@app.post("/api/v1/approvals/{name}/{stage}")
async def manual_approval(name: str, stage: str, payload: dict) -> dict:
    """Manual approval — used only when ENABLE_AUTO_APPROVAL=false.

    Body shape: {"decision": "approve"|"reject", "approver": "user@company.com",
                  "comment": "optional"}
    """
    client = await get_temporal_client()

    viz = store.latest(name)
    if viz is None:
        raise HTTPException(status_code=404, detail=f"ClusterRequest {name!r} not found")

    try:
        wf_stage = WorkflowStage(stage)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"unknown stage: {stage}") from exc

    handle = client.get_workflow_handle(viz.workflow_id)
    await handle.signal(
        "manual_decision",
        {
            "stage": wf_stage.value,
            "decision": payload.get("decision", "approve"),
            "approver": payload.get("approver", "unknown@company.com"),
            "comment": payload.get("comment", ""),
        },
    )
    return {"received": True}


@app.get("/api/v1/requests/{name}/stream")
async def stream_status(name: str, request: Request):
    """SSE stream — emits new StatusVisualization JSON whenever state changes.

    This is what the frontend uses for live status bar updates.
    """
    from sse_starlette.sse import EventSourceResponse

    queue = store.subscribe(name)

    async def event_gen():
        # Send current snapshot immediately
        viz = store.latest(name)
        if viz is not None:
            yield {"event": "status", "data": viz.model_dump_json()}
        # Then poll the queue every 0.5s
        while True:
            if await request.is_disconnected():
                break
            await asyncio_sleep_safe(0.5)
            if queue:
                payload = queue.pop(0)
                yield {"event": "status", "data": payload}

    return EventSourceResponse(event_gen())


async def asyncio_sleep_safe(seconds: float) -> None:
    import asyncio
    await asyncio.sleep(seconds)


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


# Tiny shim so the doc-import above doesn't yell at editors
__all__ = [
    "app",
    "submit_request",
    "get_status",
    "manual_approval",
    "stream_status",
    "store",
    "get_temporal_client",
]
