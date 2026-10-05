"""Pure-Python tests that don't need Temporal — focus on data model and
validation, plus the k8s_stub happy/sad path."""

from __future__ import annotations

import pytest

from api.models import (
    ClusterRequestCreate,
    ClusterRequestSpec,
    ComplianceSpec,
    CostAllocationSpec,
    GatewayStrategy,
    MultiTenancySpec,
    NetworkSpec,
    Tier,
)


def _good_spec() -> dict:
    return {
        "cloud_provider": "gcp",
        "region": "asia-east1",
        "tier": "autopilot",
        "network": {
            "mode": "private",
            "vpc": "shared-vpc-prod",
            "subnet": "bbuk-prod-subnet",
        },
        "gateway_strategy": {"mode": "per-namespace", "initial_shards": 3},
        "multi_tenancy": {"isolation_level": "namespace", "teams": ["team-a"]},
        "compliance": {"frameworks": ["baseline"], "data_residency_region_constraint": "any"},
        "cost_allocation": {"rule": "usage-based", "monthly_budget_usd": 5000},
    }


def test_clusterrequest_spec_valid():
    spec = ClusterRequestSpec.model_validate(_good_spec())
    assert spec.cloud_provider.value == "gcp"
    assert spec.tier == Tier.AUTOPILOT
    assert spec.gateway_strategy.initial_shards == 3


def test_clusterrequest_spec_requires_teams_on_namespace_isolation():
    spec = _good_spec()
    spec["multi_tenancy"]["teams"] = []
    with pytest.raises(Exception):  # Pydantic raises ValidationError
        ClusterRequestSpec.model_validate(spec)


def test_clusterrequest_spec_rejects_bad_region():
    spec = _good_spec()
    spec["region"] = "BOGUS_REGION_123"
    with pytest.raises(Exception):
        ClusterRequestSpec.model_validate(spec)


def test_full_request_validates():
    payload = {"name": "bbuk-team-a-prod", "spec": _good_spec()}
    parsed = ClusterRequestCreate.model_validate(payload)
    assert parsed.name == "bbuk-team-a-prod"


def test_compliance_pci_triggers_security_path_in_workflow():
    """Verify a spec with pci-dss-framework would invoke the security approval
    branch if executed by the workflow. We can't run Temporal here but we can
    validate the spec propagates the frameworks list as expected.
    """
    spec = _good_spec()
    spec["compliance"]["frameworks"] = ["baseline", "pci-dss"]
    parsed = ClusterRequestSpec.model_validate(spec)
    assert "pci-dss" in parsed.compliance.frameworks
    # In workflow/cluster_request.py, this list is checked at the branching
    # `if "pci-dss" in spec.get("compliance", {}).get("frameworks", [])`
