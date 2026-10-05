"""Temporal Workflow — the orchestration graph that mirrors the "approval flow"
sequence diagram in `caas-portal.md` §二.

KEY DESIGN NOTES (see `caas-portal.md` for context):
- This is a *workflow*, not an *activity*: only call activities + decide
  branching; never do I/O directly.
- All long-running waits (e.g. waiting for an IM response) would normally
  use a Temporal Signal + asyncio.Event. In demo we always auto-approve so
  the wait is minimal.
- We use a workflow_id derived from the request name + a tiny uuid suffix
  so that the demo is robust against re-submission in case of network blips.
"""

from __future__ import annotations

from datetime import timedelta

from temporalio import workflow

# Import activities through the @activity.defn name (string ref avoids heavy
# imports at workflow start time which can interfere with Temporal replay).
with workflow.unsafe.imports_passed_through():
    from .activities import (
        apply_policy_baseline,
        apply_to_k8s_stub,
        request_human_approval,
        validate_compliance_and_cost,
    )


# ---- State helpers ----
#
# In this slim demo we don't use Signal/Query methods; queries can be added
# later by defining methods decorated with @workflow.query on the class.
# Keeping the manual_decision signal flow described in api/main.py requires
# adding a Signal method to ClusterRequestWorkflow which is straightforward
# but not strictly needed for the auto-approval demo path.


@workflow.defn(name="ClusterRequestWorkflow")
class ClusterRequestWorkflow:
    """Approval + provisioning state machine for one ClusterRequest."""

    def __init__(self) -> None:
        self._state: dict = {"stages": [], "decision": None}

    async def _record(self, stage: str, status: str) -> None:
        self._state["stages"].append(
            {"stage": stage, "status": status, "at": workflow.now().isoformat()}
        )

    async def _request_approval(
        self,
        stage: str,
        role: str,
        sla_hours: float,
        *,
        request_name: str,
        workflow_id: str,
        started_at_iso: str,
    ) -> str:
        decision: str = await workflow.execute_activity(
            request_human_approval,
            args=[request_name, workflow_id, started_at_iso, stage, role, sla_hours],
            start_to_close_timeout=timedelta(hours=sla_hours + 1),
            retry_policy=workflow.RetryPolicy(maximum_attempts=3),
        )
        return decision

    @workflow.run
    async def run(self, payload: dict) -> dict:
        spec = payload["spec"]
        request_name = payload["name"]
        workflow_id = workflow.info().workflow_id
        started_at = workflow.now()
        started_at_iso = started_at.isoformat()

        self._state.update(
            {
                "request_name": request_name,
                "workflow_id": workflow_id,
                "started_at_iso": started_at_iso,
                "stages": [],
                "decision": None,
            }
        )

        # 1. Validate
        await self._record("validate", "running")
        try:
            validate_result = await workflow.execute_activity(
                validate_compliance_and_cost,
                args=[request_name, spec, workflow_id, started_at_iso],
                start_to_close_timeout=timedelta(seconds=30),
                retry_policy=workflow.RetryPolicy(maximum_attempts=2),
            )
        except Exception as exc:  # noqa: BLE001
            await self._record("validate", f"failed: {exc}")
            self._state["decision"] = "rejected_by:validation"
            return {"approved": False, "rejected_by": "validation", "error": str(exc)}
        await self._record("validate", "ok")

        # 2. Team leader approval
        decision = await self._request_approval(
            "approval_team_leader",
            "team_leader",
            2.0,
            request_name=request_name,
            workflow_id=workflow_id,
            started_at_iso=started_at_iso,
        )
        if decision != "approve":
            await self._record("approval_team_leader", f"rejected: {decision}")
            self._state["decision"] = "rejected_by:team_leader"
            return {"approved": False, "rejected_by": "team_leader"}

        # 3. PM approval (only prod) — would be checked via spec["tier"]
        # here in the full ClusterRequestSpec, omitted in this slim demo

        # 4. Security approval (only PCI-DSS frameworks present)
        if "pci-dss" in spec.get("compliance", {}).get("frameworks", []):
            decision = await self._request_approval(
                "approval_security_lead",
                "security_lead",
                24.0,
                request_name=request_name,
                workflow_id=workflow_id,
                started_at_iso=started_at_iso,
            )
            if decision != "approve":
                await self._record("approval_security_lead", f"rejected: {decision}")
                self._state["decision"] = "rejected_by:security_lead"
                return {"approved": False, "rejected_by": "security_lead"}

        # 5. Platform SRE final approval
        decision = await self._request_approval(
            "approval_platform_sre",
            "platform_sre",
            4.0,
            request_name=request_name,
            workflow_id=workflow_id,
            started_at_iso=started_at_iso,
        )
        if decision != "approve":
            await self._record("approval_platform_sre", f"rejected: {decision}")
            self._state["decision"] = "rejected_by:platform_sre"
            return {"approved": False, "rejected_by": "platform_sre"}

        # 6. Apply to K8S stub (real impl = Terraform / CAPI)
        await self._record("k8s_provisioning", "running")
        apply_req = {
            "name": request_name,
            "cloud_provider": spec["cloud_provider"],
            "region": spec["region"],
            "tier": spec["tier"],
            "compliance_frameworks": spec.get("compliance", {}).get("frameworks", []),
            "estimated_monthly_cost_usd": validate_result["estimated_monthly_cost_usd"],
        }
        try:
            k8s_result = await workflow.execute_activity(
                apply_to_k8s_stub,
                args=[request_name, workflow_id, started_at_iso, apply_req],
                start_to_close_timeout=timedelta(minutes=10),
                retry_policy=workflow.RetryPolicy(maximum_attempts=2),
            )
        except Exception as exc:  # noqa: BLE001
            await self._record("k8s_provisioning", f"failed: {exc}")
            self._state["decision"] = "failed:k8s_provisioning"
            return {"approved": True, "applied": False, "error": str(exc)}
        await self._record("k8s_provisioning", "ok")

        cluster_id = k8s_result["cluster_id"]

        # 7. Apply policy baseline (Kyverno/OGA via ClusterResourceSet, real impl)
        await workflow.execute_activity(
            apply_policy_baseline,
            args=[
                request_name,
                workflow_id,
                started_at_iso,
                cluster_id,
                spec.get("compliance", {}).get("frameworks", []),
            ],
            start_to_close_timeout=timedelta(minutes=5),
            retry_policy=workflow.RetryPolicy(maximum_attempts=2),
        )
        await self._record("policy_baseline", "ok")

        # 8. Ready
        await self._record("ready", "ok")
        self._state["decision"] = "approved"
        return {
            "approved": True,
            "applied": True,
            "cluster_id": cluster_id,
            "cluster_endpoint": k8s_result.get("endpoint"),
            "estimated_monthly_cost_usd": validate_result["estimated_monthly_cost_usd"],
        }

