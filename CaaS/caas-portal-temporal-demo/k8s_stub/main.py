"""K8S Stub — a tiny "CaaS Controller" mock.

Accepts an `apply` request, simulates a slow Terraform/GKE provisioning
that takes 3-6 seconds, then returns "Succeeded". Mirrors the contract
the real CaaS Controller would expose to the Temporal workflow activity.

This is the artifact you would replace when wiring a real Provider:
  - Apply to GKE via gcloud Container API (`caas-providers.md` §三)
  - Apply to EKS via Terraform (`caas-cluster-api.md`)
  - Apply to ACK via ACK OpenAPI
  - Apply to onprem via ClusterRegistration CRD (`caas-onprem.md`)
"""

from __future__ import annotations

import asyncio
import os
import random
import time
import uuid
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="CaaS K8S Stub", version="0.1.0")

# In-memory state — fine for demo; real CaaS would persist on the cluster side.
_APPLIES: dict[str, dict] = {}

# Probability the stub fails (to demo error handling). Set 0 for happy path.
_FAILURE_RATE = float(os.getenv("K8S_STUB_FAILURE_RATE", "0"))
_APPLY_MIN_SECONDS = float(os.getenv("K8S_STUB_APPLY_MIN_SECONDS", "3"))
_APPLY_MAX_SECONDS = float(os.getenv("K8S_STUB_APPLY_MAX_SECONDS", "6"))


class ApplyRequest(BaseModel):
    name: str
    cloud_provider: str
    region: str
    tier: str
    compliance_frameworks: list[str] = Field(default_factory=list)
    estimated_monthly_cost_usd: float = 0.0


class ApplyResponse(BaseModel):
    cluster_id: str
    status: Literal["Running", "Succeeded", "Failed"]
    estimated_completion_seconds: float
    endpoint: str | None = None


class StatusResponse(BaseModel):
    cluster_id: str
    status: Literal["Running", "Succeeded", "Failed"]
    error: str | None = None
    endpoint: str | None = None


@app.post("/apply", response_model=ApplyResponse)
async def apply(req: ApplyRequest) -> ApplyResponse:
    cluster_id = f"caas-{req.cloud_provider}-{req.region}-{uuid.uuid4().hex[:8]}"
    duration = random.uniform(_APPLY_MIN_SECONDS, _APPLY_MAX_SECONDS)
    will_fail = random.random() < _FAILURE_RATE

    _APPLIES[cluster_id] = {
        "status": "Running",
        "starts_at": time.time(),
        "duration": duration,
        "will_fail": will_fail,
        "req": req.model_dump(),
        "endpoint": f"https://{cluster_id}.caas.invalid:6443",
    }
    return ApplyResponse(
        cluster_id=cluster_id,
        status="Running",
        estimated_completion_seconds=duration,
    )


@app.get("/status/{cluster_id}", response_model=StatusResponse)
async def status(cluster_id: str) -> StatusResponse:
    rec = _APPLIES.get(cluster_id)
    if rec is None:
        raise HTTPException(status_code=404, detail=f"cluster_id {cluster_id!r} unknown")

    if rec["status"] != "Running":
        return StatusResponse(
            cluster_id=cluster_id,
            status=rec["status"],
            error=rec.get("error"),
            endpoint=rec.get("endpoint"),
        )

    elapsed = time.time() - rec["starts_at"]
    if elapsed < rec["duration"]:
        return StatusResponse(cluster_id=cluster_id, status="Running")

    # Apply completes
    if rec["will_fail"]:
        rec["status"] = "Failed"
        rec["error"] = "stub: simulated provisioning failure (set K8S_STUB_FAILURE_RATE=0 to disable)"
    else:
        rec["status"] = "Succeeded"
    return StatusResponse(
        cluster_id=cluster_id,
        status=rec["status"],
        error=rec.get("error"),
        endpoint=rec.get("endpoint"),
    )


@app.delete("/apply/{cluster_id}")
async def cleanup(cluster_id: str) -> dict:
    if cluster_id in _APPLIES:
        del _APPLIES[cluster_id]
    return {"deleted": cluster_id}


@app.get("/_health")
async def health() -> dict:
    return {"ok": True, "open_applies": len(_APPLIES)}
