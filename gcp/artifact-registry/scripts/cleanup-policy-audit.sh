#!/usr/bin/env bash
#
# cleanup-policy-audit.sh
#
# 用途：对一个 Artifact Registry 仓库的 cleanup policy 做「静态评估 + 命中推演」。
#   1. 导出仓库当前生效的 cleanup policy（含 dry-run 开关、immutable tags）
#   2. 拉取全量 package / version 清单（含 createTime / updateTime / tag）
#   3. 按策略语义离线推演「哪些版本会被删、什么时候会被删」
#   4. 可选：与 GKE 工作负载实际引用的镜像做交叉比对，标出「删了会出事」的版本
#
# 说明：本脚本只读，不做任何删除操作。真实删除由 AR 后台作业按策略执行。
#
# 用法：
#   cleanup-policy-audit.sh --project PROJECT --location LOCATION --repository REPO \
#                           [--kube-context CTX] [--out DIR] [--json]
#
# 依赖：gcloud（已认证）、python3；加 --kube-context 时还需要 kubectl。

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: cleanup-policy-audit.sh --project PROJECT --location LOCATION --repository REPO
                               [--kube-context CTX] [--out DIR] [--json]

  --project PROJECT      GCP 项目 ID
  --location LOCATION    仓库区域，如 us-central1 / asia-east1
  --repository REPO      仓库 ID
  --kube-context CTX     可选：用该 context 采集 GKE 工作负载镜像引用并交叉比对
  --out DIR              输出目录（默认 ./ar-cleanup-audit-<timestamp>）
  --json                 额外输出 machine-readable 的推演结果 JSON
  -h, --help             显示帮助
EOF
}

PROJECT=""
LOCATION=""
REPOSITORY=""
KUBE_CONTEXT=""
OUT_DIR=""
JSON_OUT="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)      PROJECT="$2"; shift 2 ;;
    --location)     LOCATION="$2"; shift 2 ;;
    --repository)   REPOSITORY="$2"; shift 2 ;;
    --kube-context) KUBE_CONTEXT="$2"; shift 2 ;;
    --out)          OUT_DIR="$2"; shift 2 ;;
    --json)         JSON_OUT="1"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" || -z "$LOCATION" || -z "$REPOSITORY" ]]; then
  echo "ERROR: --project / --location / --repository 均为必填" >&2
  usage
  exit 2
fi

command -v gcloud >/dev/null 2>&1 || { echo "ERROR: 找不到 gcloud" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: 找不到 python3" >&2; exit 1; }

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="./ar-cleanup-audit-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUT_DIR/versions"

echo "==> 采集仓库元数据: ${LOCATION} / ${REPOSITORY} (project=${PROJECT})"
gcloud artifacts repositories describe "$REPOSITORY" \
  --project="$PROJECT" --location="$LOCATION" --format=json > "$OUT_DIR/repo.json"

echo "==> 采集 package 列表"
gcloud artifacts packages list \
  --repository="$REPOSITORY" --location="$LOCATION" --project="$PROJECT" \
  --format=json > "$OUT_DIR/packages.json"

echo "==> 采集 version 清单（含 createTime / tag）"
PKG_INDEX=0
while IFS= read -r pkg_name; do
  [[ -z "$pkg_name" ]] && continue
  gcloud artifacts versions list \
    --package="$pkg_name" \
    --repository="$REPOSITORY" --location="$LOCATION" --project="$PROJECT" \
    --format=json > "$OUT_DIR/versions/$(printf '%05d' "$PKG_INDEX").json" || \
    echo "    WARN: 无法读取 package ${pkg_name} 的 version（权限不足？）" >&2
  # tag 清单：非 Docker 格式会失败，属预期（这些格式没有 tag）
  gcloud artifacts tags list \
    --package="$pkg_name" \
    --repository="$REPOSITORY" --location="$LOCATION" --project="$PROJECT" \
    --format=json > "$OUT_DIR/versions/$(printf '%05d' "$PKG_INDEX").tags.json" 2>/dev/null || \
    echo '[]' > "$OUT_DIR/versions/$(printf '%05d' "$PKG_INDEX").tags.json"
  PKG_INDEX=$((PKG_INDEX + 1))
done < <(python3 - "$OUT_DIR/packages.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data:
    name = p.get("name", "")
    if "/packages/" in name:
        print(name.split("/packages/", 1)[1])
PY
)
echo "    共 ${PKG_INDEX} 个 package"

if [[ -n "$KUBE_CONTEXT" ]]; then
  echo "==> 采集 GKE 工作负载镜像引用 (context=${KUBE_CONTEXT})"
  command -v kubectl >/dev/null 2>&1 || { echo "ERROR: 找不到 kubectl" >&2; exit 1; }
  kubectl --context "$KUBE_CONTEXT" get deploy,statefulset,daemonset,replicaset,job,cronjob \
    -A -o json > "$OUT_DIR/kube_workloads.json" || \
    echo "    WARN: 采集工作负载失败" >&2
  kubectl --context "$KUBE_CONTEXT" get pods -A -o json > "$OUT_DIR/kube_pods.json" || \
    echo "    WARN: 采集 Pod 失败" >&2
fi

echo "==> 推演命中结果"
python3 - "$OUT_DIR" "$PROJECT" "$LOCATION" "$REPOSITORY" "$JSON_OUT" <<'PY'
import json, os, re, sys
from datetime import datetime, timezone, timedelta

out_dir, project, location, repository, json_out = sys.argv[1:6]
now = datetime.now(timezone.utc)


def load(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError:
            return default


def parse_duration(value):
    """支持 API 形式 '2592000s' / '3.5s' 与 policy 文件形式 '30d' / '12h' / '5m' / '90s'。"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    m = re.fullmatch(r"\s*([0-9]*\.?[0-9]+)\s*([smhd])\s*", str(value))
    if not m:
        return None
    num, unit = float(m.group(1)), m.group(2)
    factor = {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]
    return num * factor


def iso(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


repo = load(os.path.join(out_dir, "repo.json"), {})
policies_raw = repo.get("cleanupPolicies") or {}

# ---------- 策略归一化 ----------
policies = []
for pid, p in policies_raw.items():
    cond = p.get("condition") or {}
    mrv = p.get("mostRecentVersions") or {}
    policies.append({
        "id": pid,
        "action": (p.get("action") or "").upper(),
        "tagState": (cond.get("tagState") or "ANY").upper(),
        "tagPrefixes": cond.get("tagPrefixes") or [],
        "versionNamePrefixes": cond.get("versionNamePrefixes") or [],
        "packageNamePrefixes": cond.get("packageNamePrefixes") or [],
        "olderThan": cond.get("olderThan"),
        "newerThan": cond.get("newerThan"),
        "keepCount": mrv.get("keepCount"),
        "mrvPackagePrefixes": mrv.get("packageNamePrefixes") or [],
        "hasCondition": bool(cond),
        "hasMrv": bool(mrv),
    })

# ---------- 版本清单 ----------
versions = []
vdir = os.path.join(out_dir, "versions")
# tag -> version 映射（来自 gcloud artifacts tags list，作为 relatedTags 的补充/兜底）
tag_map = {}
for fname in sorted(os.listdir(vdir)) if os.path.isdir(vdir) else []:
    if not fname.endswith(".tags.json"):
        continue
    for t in load(os.path.join(vdir, fname), []) or []:
        vname = t.get("version") or ""
        tname = (t.get("name") or "").rsplit("/", 1)[-1]
        if vname and tname:
            tag_map.setdefault(vname, []).append(tname)

missing_tag_field = 0
for fname in sorted(os.listdir(vdir)) if os.path.isdir(vdir) else []:
    if not fname.endswith(".json") or fname.endswith(".tags.json"):
        continue
    blob = load(os.path.join(vdir, fname), {})
    for v in blob.get("versions", []):
        name = v.get("name", "")
        if "/packages/" not in name or "/versions/" not in name:
            continue
        pkg = name.split("/packages/", 1)[1].split("/versions/", 1)[0]
        vid = name.split("/versions/", 1)[1]
        tags = []
        if "relatedTags" in v:
            for t in v.get("relatedTags") or []:
                tname = (t.get("name") or "").rsplit("/", 1)[-1]
                if tname:
                    tags.append(tname)
        else:
            missing_tag_field += 1
        for t in tag_map.get(name, []):
            if t not in tags:
                tags.append(t)
        versions.append({
            "package": pkg,
            "version": vid,
            "createTime": v.get("createTime"),
            "updateTime": v.get("updateTime"),
            "tags": tags,
        })

if missing_tag_field:
    print("WARN: %d 个 version 未返回 relatedTags 字段，tag 状态可能不完整"
          "（已尝试用 tags list 兜底，建议用 dry run 复核）" % missing_tag_field)

# ---------- 匹配逻辑（与官方文档语义一致）----------
def matches(pol, v):
    reasons = []
    if not pol["hasCondition"]:
        return None
    ctag = v["createTime"]
    ct = iso(ctag)
    ts = pol["tagState"]
    if ts == "TAGGED":
        if not v["tags"]:
            return None
    elif ts == "UNTAGGED":
        if v["tags"]:
            return None
    if pol["tagPrefixes"]:
        if ts != "TAGGED":
            return None  # tagPrefixes 必须搭配 tagState=TAGGED，否则条件无法成立
        if not any(t.startswith(p) for t in v["tags"] for p in pol["tagPrefixes"]):
            return None
    if pol["versionNamePrefixes"]:
        if not any(v["version"].startswith(p) for p in pol["versionNamePrefixes"]):
            return None
    if pol["packageNamePrefixes"]:
        if not any(v["package"].startswith(p) for p in pol["packageNamePrefixes"]):
            return None
    older = parse_duration(pol["olderThan"])
    newer = parse_duration(pol["newerThan"])
    if older is not None:
        if ct is None or ct > now - timedelta(seconds=older):
            return None
    if newer is not None:
        if ct is None or ct < now - timedelta(seconds=newer):
            return None
    reasons.append("olderThan=%s" % pol["olderThan"] if older is not None else "")
    reasons = [r for r in reasons if r]
    return reasons or ["(无时间条件)"]


# most_recent_versions: 每个 package 保留最近 N 个
keep_by_count = set()
for pol in policies:
    if pol["action"] != "KEEP" or not pol["hasMrv"]:
        continue
    count = int(pol["keepCount"] or 0)
    prefixes = pol["mrvPackagePrefixes"]
    by_pkg = {}
    for v in versions:
        if prefixes and not any(v["package"].startswith(p) for p in prefixes):
            continue
        by_pkg.setdefault(v["package"], []).append(v)
    for _pkg, items in by_pkg.items():
        items.sort(key=lambda x: (iso(x["createTime"]) or datetime.min.replace(tzinfo=timezone.utc)),
                   reverse=True)
        for v in items[:count]:
            keep_by_count.add((v["package"], v["version"]))

to_delete = {}
kept = {}
for v in versions:
    key = (v["package"], v["version"])
    hit_delete, hit_keep = [], []
    for pol in policies:
        if pol["action"] == "DELETE":
            m = matches(pol, v)
            if m:
                hit_delete.append((pol["id"], m))
        elif pol["action"] == "KEEP":
            m = matches(pol, v)
            if m:
                hit_keep.append((pol["id"], m))
    if (v["package"], v["version"]) in keep_by_count:
        hit_keep.append(("keep-most-recent(count)", []))
    if hit_delete and not hit_keep:
        to_delete[key] = hit_delete
    elif hit_delete and hit_keep:
        kept[key] = (hit_delete, hit_keep)

# ---------- GKE 交叉比对 ----------
workload_images = []   # (kind, ns, name, image)
pod_images = []
wl = load(os.path.join(out_dir, "kube_workloads.json"), {})
if wl:
    for item in wl.get("items", []):
        kind = item.get("kind", "?")
        meta = item.get("metadata", {})
        ns, name = meta.get("namespace", ""), meta.get("name", "")
        spec = item.get("spec", {})
        tmpl = spec
        if kind == "CronJob":
            tmpl = spec.get("jobTemplate", {}).get("spec", {}).get("template", {})
        pod_spec = tmpl.get("template", {}).get("spec", {}) or spec.get("template", {}).get("spec", {})
        for c in (pod_spec.get("containers") or []) + (pod_spec.get("initContainers") or []):
            if c.get("image"):
                workload_images.append((kind, ns, name, c["image"]))
pods = load(os.path.join(out_dir, "kube_pods.json"), {})
if pods:
    for item in pods.get("items", []):
        meta = item.get("metadata", {})
        ns, name = meta.get("namespace", ""), meta.get("name", "")
        st = item.get("status", {})
        for c in (st.get("containerStatuses") or []) + (st.get("initContainerStatuses") or []):
            if c.get("image"):
                pod_images.append((ns, name, c.get("image", ""), c.get("imageID", "")))

def repo_prefix():
    return "%s-docker.pkg.dev/%s/%s/" % (location, project, repository)

prefix = repo_prefix()
usage_index = {}   # (pkg, tag-or-digest) -> [refs]
for kind, ns, name, image in workload_images:
    if not image.startswith(prefix):
        continue
    rest = image[len(prefix):]
    if "@" in rest:
        pkg, digest = rest.split("@", 1)
    elif ":" in rest:
        pkg, tag = rest.rsplit(":", 1)
        digest = None
    else:
        pkg, digest = rest, None
    key = (pkg, digest) if digest else (pkg, "tag:" + tag)
    usage_index.setdefault(key, []).append("spec:%s/%s %s" % (kind, ns, name))
for ns, name, image, imageid in pod_images:
    for candidate in (image, imageid):
        if not candidate or not candidate.startswith(prefix):
            continue
        rest = candidate[len(prefix):]
        if "@" in rest:
            pkg, digest = rest.split("@", 1)
            key = (pkg, digest)
        else:
            pkg, tag = rest.rsplit(":", 1) if ":" in rest else (rest, "")
            key = (pkg, "tag:" + tag)
        usage_index.setdefault(key, []).append("pod:%s/%s" % (ns, name))

# 标签 -> digest 映射
tag_to_digest = {}
digest_of_pkg = {}
for v in versions:
    for t in v["tags"]:
        tag_to_digest[(v["package"], "tag:" + t)] = v["version"]
    digest_of_pkg[(v["package"], v["version"])] = v["version"]

def refs_for(pkg, vid):
    refs = []
    for key, lst in usage_index.items():
        if key[0] != pkg:
            continue
        k = key[1]
        if k.startswith("tag:"):
            if tag_to_digest.get((pkg, k)) == vid:
                refs += lst
        elif k == vid:
            refs += lst
    return refs


def age_days(ts):
    ct = iso(ts)
    if not ct:
        return None
    return round((now - ct).total_seconds() / 86400, 1)


# ---------- 输出 ----------
print("")
print("=" * 78)
print("仓库: %s  项目: %s  区域: %s" % (repository, project, location))
print("格式: %s   模式: %s   大小: %s" % (
    repo.get("format"), repo.get("mode"), repo.get("sizeBytes")))
print("cleanupPolicyDryRun: %s   immutableTags: %s" % (
    repo.get("cleanupPolicyDryRun"),
    (repo.get("dockerConfig") or {}).get("immutableTags")))
print("-" * 78)
print("生效策略 (%d 条，仓库上限 10):" % len(policies))
for p in policies:
    bits = []
    if p["hasCondition"]:
        bits.append("tagState=%s" % p["tagState"])
        if p["tagPrefixes"]:
            bits.append("tagPrefixes=%s" % ",".join(p["tagPrefixes"]))
        if p["versionNamePrefixes"]:
            bits.append("versionNamePrefixes=%s" % ",".join(p["versionNamePrefixes"]))
        if p["packageNamePrefixes"]:
            bits.append("packageNamePrefixes=%s" % ",".join(p["packageNamePrefixes"]))
        if p["olderThan"]:
            bits.append("olderThan=%s" % p["olderThan"])
        if p["newerThan"]:
            bits.append("newerThan=%s" % p["newerThan"])
    if p["hasMrv"]:
        bits.append("mostRecentVersions.keepCount=%s" % p["keepCount"])
        if p["mrvPackagePrefixes"]:
            bits.append("mrv.packageNamePrefixes=%s" % ",".join(p["mrvPackagePrefixes"]))
    print("  - [%s] %s  %s" % (p["action"], p["id"], " ".join(bits)))
print("-" * 78)
print("版本总数: %d   会被删除: %d   因 keep 策略保留: %d" % (
    len(versions), len(to_delete), len(kept)))

if to_delete:
    print("")
    print("%-38s %-16s %-12s %-8s %s" % ("PACKAGE", "VERSION", "AGE(d)", "TAGS", "命中策略 / 引用"))
    for (pkg, vid), hits in sorted(to_delete.items(), key=lambda kv: kv[0]):
        v = next(x for x in versions if x["package"] == pkg and x["version"] == vid)
        tags = ",".join(v["tags"]) or "-"
        pol = ",".join(h[0] for h in hits)
        refs = refs_for(pkg, vid)
        ref_s = ("  ⚠ 仍被引用: " + "; ".join(sorted(set(refs)))) if refs else ""
        print("%-38s %-16s %-12s %-8s %s%s" % (
            pkg[:38], vid[:16], age_days(v["createTime"]), tags[:8], pol, ref_s))

if json_out:
    result = {
        "repository": repository,
        "project": project,
        "location": location,
        "dryRun": repo.get("cleanupPolicyDryRun"),
        "immutableTags": (repo.get("dockerConfig") or {}).get("immutableTags"),
        "policies": policies,
        "totalVersions": len(versions),
        "toDelete": [
            {
                "package": pkg,
                "version": vid,
                "createTime": next(x["createTime"] for x in versions
                                   if x["package"] == pkg and x["version"] == vid),
                "tags": next(x["tags"] for x in versions
                             if x["package"] == pkg and x["version"] == vid),
                "matchedPolicies": [h[0] for h in hits],
                "stillReferencedBy": refs_for(pkg, vid),
            }
            for (pkg, vid), hits in sorted(to_delete.items())
        ],
    }
    with open(os.path.join(out_dir, "simulation.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)
    print("")
    print("machine-readable 结果: %s" % os.path.join(out_dir, "simulation.json"))
print("=" * 78)
PY

echo "==> 原始数据保留在: $OUT_DIR"
