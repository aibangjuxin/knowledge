"""Pure-Python tests that don't need Temporal — focus on data model and
validation, plus the k8s_stub happy/sad path."""

from __future__ import annotations

import pytest

from api.models import (
    ClusterRequestCreate,
    ClusterRequestSpec,
    ComplianceSpec,
    CostAllocationSpec,
    Environment,
    GatewayStrategy,
    MultiTenancySpec,
    NetworkSpec,
    ReleaseChannel,
    Tier,
    VersionStrategy,
)


def _good_spec() -> dict:
    return {
        "cloud_provider": "gcp",
        "region": "asia-east1",
        # C3 修复(2026-10-05):tier 锁死 standard(原为 autopilot)
        "tier": "standard",
        # C9 配套:environment 决定是否触发更严格的 EOL 规则
        "environment": "prod",
        "version_strategy": {
            "channel": "STABLE",
            "minor_upgrade_policy": "auto",
            "eol_notice_days": 60,
            "allow_eol_emergency_exclusion": False,
        },
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
    assert spec.tier == Tier.STANDARD
    assert spec.gateway_strategy.initial_shards == 3
    # C9:channel 锁死 STABLE,且默认版本策略可被继承
    assert spec.version_strategy.channel == ReleaseChannel.STABLE
    assert spec.version_strategy.eol_notice_days == 60


def test_clusterrequest_spec_rejects_autopilot():
    """C3 修复的回归测试:tier 锁死后,autopilot 必须被拒。

    这条测试存在的意义是**防止有人把 AUTOPILOT 加回 enum**。
    若将来真的要支持 Autopilot,应当先改 CRD 立场,再改这条测试 ——
    而不是直接删掉它。
    """
    spec = _good_spec()
    spec["tier"] = "autopilot"
    with pytest.raises(Exception):  # Pydantic raises ValidationError
        ClusterRequestSpec.model_validate(spec)


def test_version_strategy_rejects_non_stable_channel():
    """C9 修复的回归测试:channel 只能是 STABLE。"""
    spec = _good_spec()
    spec["version_strategy"]["channel"] = "RAPID"
    with pytest.raises(Exception):
        ClusterRequestSpec.model_validate(spec)


def test_prod_forbids_eol_emergency_exclusion():
    """C9 CEL 规则的生产侧实现:prod 不得开 allowEolEmergencyExclusion。"""
    spec = _good_spec()
    spec["version_strategy"]["allow_eol_emergency_exclusion"] = True
    with pytest.raises(Exception):
        ClusterRequestSpec.model_validate(spec)


def test_dev_allows_eol_emergency_exclusion():
    """同一条规则在 dev 下应放行 —— 证明它是按 environment 分支,不是无条件拒绝。"""
    spec = _good_spec()
    spec["environment"] = "dev"
    spec["version_strategy"]["allow_eol_emergency_exclusion"] = True
    parsed = ClusterRequestSpec.model_validate(spec)
    assert parsed.environment == Environment.DEV
    assert parsed.version_strategy.allow_eol_emergency_exclusion is True


def test_cluster_isolation_requires_teams():
    """C3/C6 修复:独占集群同样必须指定责任团队。"""
    spec = _good_spec()
    spec["multi_tenancy"] = {"isolation_level": "cluster", "teams": []}
    with pytest.raises(Exception):
        ClusterRequestSpec.model_validate(spec)


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
