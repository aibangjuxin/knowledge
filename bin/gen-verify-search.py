#!/usr/bin/env python3
"""Regenerate verify-search.md — the index of verification scripts and knowledge docs.

The index lists every ``*.sh`` verification script and ``*.md`` document in the
repository, grouped by topic, with a short description extracted from the file
itself (header comment for scripts, first meaningful line for documents).

Usage:
    python3 bin/gen-verify-search.py            # rewrite verify-search.md
    python3 bin/gen-verify-search.py --check    # exit 1 if the index is stale
    python3 bin/gen-verify-search.py --stats    # only print per-section counts
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "verify-search.md"

# Directories that never belong in the index.
SKIP_DIRS = {"skills", "node_modules", "__pycache__", ".git"}
# The index itself is not part of the index.
SKIP_FILES = {"verify-search.md"}

# ---------------------------------------------------------------------------
# Topic rules. Longest matching prefix wins; the last rule per file type is
# the fallback bucket.
# ---------------------------------------------------------------------------

SHELL_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("Ali Cloud Scripts", ("cloud/ali",)),
    ("AWS Scripts", ("cloud/aws",)),
    ("Docker/Container Scripts", ("cloud/docker", "devops/docker")),
    ("K8s Pod/Health Check Scripts", ("cloud/k8s",)),
    ("CI/CD Pipeline Scripts", ("develop/pipeline",)),
    ("DevOps/Platform Scripts", ("devops",)),
    ("Java/Debug Scripts", ("develop/java",)),
    ("Develop Tool Scripts", ("develop",)),
    ("GitOps / Argo CD Scripts", ("gcp/ucp",)),
    ("GCP ASM/Istio Scripts", ("gcp/asm",)),
    ("GCP Cloud Run Scripts", ("gcp/cloud-run",)),
    ("GCP GCE/MIG Scripts", ("gcp/gce",)),
    ("GCP LB/GLB/Ingress Scripts", ("gcp/lb", "gcp/glb", "gcp/ingress", "gcp/gateway")),
    ("GCP Cloud Armor Scripts", ("gcp/cloud-armor",)),
    ("GCP DNS Migration Scripts", ("gcp/migrate-gcp",)),
    ("GCP Secret Manager Scripts", ("gcp/secret-manage",)),
    ("GCP Service Account / IAM Check Scripts", ("gcp/sa",)),
    ("GCS Bucket Check Scripts", ("gcp/buckets", "gcp/storage")),
    ("GCP Network/PSC Scripts", ("gcp/network", "gcp/psa-psc")),
    ("GCP Logging/Pub/Sub Scripts", ("gcp/logs", "gcp/pub-sub", "gcp/firestore")),
    ("GCP BigQuery/SQL Scripts", ("gcp/bigquery", "gcp/sql")),
    ("GCP General/Info Scripts", ("gcp",)),
    ("Gateway/Kong Check Scripts", ("gateway",)),
    ("SSL/TLS Check Scripts", ("gcp/mtls", "safe/ssl", "safe/cert")),
    ("Network/Egress/Squid Scripts", ("webservice/egress", "webservice/squid")),
    ("Nginx/Web Service Scripts", ("webservice/nginx", "webservice/apache")),
    ("Linux/Optimization Scripts", ("linux/linux-os-optimize", "linux/docs", "linux/network", "linux/dns")),
    ("Git Workflow Scripts", ("linux/howgit",)),
    ("Shell Script Utility Scripts", ("linux/shell-script", "linux/scripts", "shortcut", "scripts", "bin")),
    ("Database/Redis/SQL Scripts", ("database",)),
    ("Security Scripts", ("safe",)),
    ("SRE/Monitoring Scripts", ("sre",)),
    ("macOS/iOS Scripts", ("macos",)),
    ("Other Scripts", ()),  # fallback
]

DOC_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("Ali Cloud Documentation", ("cloud/ali",)),
    ("AWS Documentation", ("cloud/aws",)),
    ("Container/Docker Documentation", ("cloud/docker", "devops/docker")),
    ("K8s Documentation", ("cloud/k8s",)),
    ("CI/CD Pipeline Documentation", ("develop/pipeline",)),
    ("DevOps/Platform Documentation", ("devops",)),
    ("GitOps / Argo CD Documentation", ("gcp/ucp",)),
    ("GCP ASM/Istio Documentation", ("gcp/asm",)),
    ("GCP Cloud Run Documentation", ("gcp/cloud-run",)),
    ("GCP GCE/MIG Documentation", ("gcp/gce",)),
    ("GCP LB/GLB/Ingress Documentation", ("gcp/lb", "gcp/glb", "gcp/ingress", "gcp/gateway")),
    ("GCP Cloud Armor Documentation", ("gcp/cloud-armor",)),
    ("GCP Cross-Project Documentation", ("gcp/cross-project",)),
    ("GCP DNS Migration Documentation", ("gcp/migrate-gcp",)),
    ("GCP Secret Manager Documentation", ("gcp/secret-manage",)),
    ("GCP Service Account / IAM Documentation", ("gcp/sa",)),
    ("GCS Bucket Documentation", ("gcp/buckets", "gcp/storage")),
    ("GCP Network/PSC Documentation", ("gcp/network", "gcp/psa-psc")),
    ("GCP/mTLS Documentation", ("gcp/mtls",)),
    ("Logging Documentation", ("gcp/logs",)),
    ("Pub/Sub & Firestore Documentation", ("gcp/pub-sub", "gcp/firestore")),
    ("SQL/BigQuery Documentation", ("gcp/bigquery", "gcp/sql", "database/sql")),
    ("GKE Documentation", ("gcp/gke",)),
    ("Cost & Dashboard Documentation", ("gcp/cost", "gcp/dashboard")),
    ("GCP General Documentation", ("gcp",)),
    ("Gateway/Kong Documentation", ("gateway",)),
    ("Java Documentation", ("develop/java",)),
    ("Python Documentation", ("develop/python",)),
    ("Go/Node/Web Documentation", ("develop/go", "develop/node", "develop/npm", "develop/React",
                                  "develop/groovy", "develop/dev-tools", "develop/vscode",
                                  "develop/waza", "develop/develop-process", "develop/shell-review")),
    ("Nginx Documentation", ("webservice/nginx",)),
    ("Network/Egress/Squid Documentation", ("webservice",)),
    ("Linux Documentation", ("linux",)),
    ("Security Documentation", ("safe",)),
    ("SRE/Monitoring Documentation", ("sre",)),
    ("macOS/iOS Documentation", ("macos",)),
    ("Database/Redis Documentation", ("database",)),
    ("Concept/API Service Documentation", ("concept",)),
    ("AI Documentation", ("ai",)),
    ("OPA Gatekeeper Documentation", ("OPA-Gatekeeper",)),
    ("General Documentation", ()),  # fallback
]

# Metadata labels commonly used in script headers; stripped from descriptions.
LABEL_RE = re.compile(
    r"^(script\s*name|description|desc|author|usage|purpose|version|summary)\s*:\s*",
    re.IGNORECASE,
)
DESC_LABEL_RE = re.compile(r"^(description|desc|summary|purpose)\s*:\s*(.+)$", re.IGNORECASE)
FENCE_RE = re.compile(r"^(```|~~~)")
HEADING_RE = re.compile(r"^#{1,6}\s*")
H1_RE = re.compile(r"^#\s+(.+?)\s*#*$")
HEADING_ANY_RE = re.compile(r"^#{2,6}\s+(.+?)\s*#*$")
FRONTMATTER_TITLE_RE = re.compile(r"^title\s*:\s*(.+)$", re.IGNORECASE)
# Banner / rule lines such as "# ======" or "# -----" carry no information.
SEPARATOR_RE = re.compile(r"^[=\-_*+~#]{3,}$")

# Host names are masked in generated descriptions so that internal names are not
# republished by the index. Well known public domains are kept as-is.
PUBLIC_HOSTS = {
    "cloud.google.com", "docs.cloud.google.com", "kubernetes.io", "github.com", "github.io",
    "spring.io", "googleapis.com", "istio.io", "nginx.org", "redis.io", "apache.org",
    "docker.io", "gcr.io", "pypi.org", "maven.org", "docs.docker.com", "golang.org",
    "example.com", "google.internal",
}
HOST_RE = re.compile(
    r"\b(?:[a-z0-9-]+\.)+(?:com|net|org|io|cn|co|dev|info|biz|us|uk|hk|jp|ai|app|cloud|local|internal)\b",
    re.IGNORECASE,
)
PROJECT_ID_RE = re.compile(r"\b[a-z0-9-]*projectid[a-z0-9-]*\b", re.IGNORECASE)
PROJECT_FLAG_RE = re.compile(r"--project[= ]\S+")
SA_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.iam\.gserviceaccount\.com")
BARE_URL_RE = re.compile(r"^https?://\S+$")
COMMAND_RE = re.compile(r"^(\$|#\s*\$|gcloud|kubectl|curl|helm|kustomize|docker|git|export|echo)\b")

# Tokens that keep a special spelling when a file name is humanized.
TOKEN_OVERRIDES = {"k8s": "K8S", "e2e": "E2E"}

SH_MAX = 100
MD_MAX = 140


# ---------------------------------------------------------------------------
# File collection
# ---------------------------------------------------------------------------

def git_lines(*args: str) -> list[str]:
    out = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True, check=True)
    return [line for line in out.stdout.split("\0") if line]


def collect_files() -> tuple[list[str], list[str]]:
    """Return (shell_scripts, markdown_docs) relative to the repo root."""
    tracked = git_lines("ls-files", "-z", "--", "*.sh", "*.md")
    untracked = git_lines("ls-files", "-z", "--others", "--exclude-standard", "--", "*.sh", "*.md")

    shells: list[str] = []
    docs: list[str] = []
    for path in sorted(set(tracked) | set(untracked)):
        parts = path.split("/")
        if any(part in SKIP_DIRS for part in parts[:-1]):
            continue
        if any(part.startswith(".") for part in parts):
            continue  # hidden directories / files
        if parts[-1] in SKIP_FILES:
            continue
        (shells if path.endswith(".sh") else docs).append(path)
    return shells, docs


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

def classify(path: str, rules: list[tuple[str, tuple[str, ...]]]) -> str:
    best_section = rules[-1][0]
    best_len = -1
    for section, prefixes in rules:
        for prefix in prefixes:
            if path.startswith(prefix) and len(prefix) > best_len:
                best_section, best_len = section, len(prefix)
    return best_section


# ---------------------------------------------------------------------------
# Description extraction
# ---------------------------------------------------------------------------

def clip(text: str, limit: int) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def humanize(path: str) -> str:
    stem = Path(path).stem
    words = []
    for token in re.split(r"[-_]+", stem):
        if not token:
            continue
        words.append(TOKEN_OVERRIDES.get(token.lower(), token[:1].upper() + token[1:].lower()))
    return " ".join(words) or stem


def first_lines(path: str, limit: int = 80) -> list[str]:
    try:
        with open(REPO / path, encoding="utf-8", errors="replace") as handle:
            return [handle.readline() for _ in range(limit)]
    except OSError:
        return []


def describe_shell(path: str) -> str:
    """Header comment of the script: Description > first comment > label > file name."""
    comments: list[str] = []
    for raw in first_lines(path):
        line = raw.strip()
        if not line:
            if comments:
                break  # end of the leading comment block
            continue
        if line.startswith("#!"):
            continue
        if not line.startswith("#"):
            break  # code before any comment: the header block ended
        comments.append(line.lstrip("#").strip())

    # A) an explicit description field
    for text in comments:
        match = DESC_LABEL_RE.match(text)
        if match and match.group(2).strip():
            return clip(redact(match.group(2).strip()), SH_MAX)

    # B) the first plain comment
    for text in comments:
        if not text or SEPARATOR_RE.match(text):
            continue
        if LABEL_RE.match(text):
            continue
        return clip(redact(text), SH_MAX)

    # C) any other labelled field (skip self-referencing file names)
    stem = Path(path).stem.lower()
    for text in comments:
        if not text or SEPARATOR_RE.match(text):
            continue
        match = LABEL_RE.match(text)
        if not match:
            continue
        value = text.split(":", 1)[1].strip()
        if value.lower() in (stem, Path(path).name.lower()):
            continue
        return clip(redact(value), SH_MAX)

    return humanize(path)


def redact(text: str) -> str:
    """Mask internal identifiers that must not be republished by the index."""
    text = PROJECT_FLAG_RE.sub("--project=<project-id>", text)
    text = PROJECT_ID_RE.sub("<project-id>", text)
    text = SA_EMAIL_RE.sub("<sa-email>@<project>.iam.gserviceaccount.com", text)

    def _host(match: re.Match[str]) -> str:
        host = match.group(0).lower()
        if any(host == pub or host.endswith("." + pub) for pub in PUBLIC_HOSTS):
            return match.group(0)
        return "<host>"

    return HOST_RE.sub(_host, text)


def describe_doc(path: str) -> str:
    """Document title: YAML front matter, then the first heading, then the opening line."""
    lines = first_lines(path, 120)

    if lines and lines[0].strip() == "---":  # YAML front matter
        for raw in lines[1:]:
            stripped = raw.strip()
            if stripped == "---":
                break
            match = FRONTMATTER_TITLE_RE.match(stripped)
            if match:
                return clip(redact(match.group(1).strip().strip("\"'")), MD_MAX)

    for pattern in (H1_RE, HEADING_ANY_RE):
        for raw in lines:
            match = pattern.match(raw.strip())
            if match:
                return clip(redact(match.group(1).strip()), MD_MAX)

    in_fence = False
    for raw in lines:
        line = raw.strip()
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if not line:
            continue
        text = HEADING_RE.sub("", line)
        text = text.rstrip("#").strip() if text.endswith("#") else text.strip()
        text = text.lstrip("#").strip()
        if not text or BARE_URL_RE.match(text) or COMMAND_RE.match(text):
            continue  # a bare link or a command line says nothing about the topic
        return clip(redact(text), MD_MAX)
    return humanize(path)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def table(rows: list[tuple[str, str]]) -> list[str]:
    out = ["| File Path | Description |", "| :--- | :--- |"]
    out += [f"| `{path}` | {desc} |" for path, desc in rows]
    return out


def render(shells: list[str], docs: list[str], today: str) -> str:
    lines: list[str] = []
    lines += [
        "# Summary or Background",
        "",
        "- This markdown records my workspace verification information and scripts.",
        "- It is a generated index of every `*.sh` verification script and `*.md` knowledge document"
        " in this repository, grouped by topic.",
        "- Regenerate it with `python3 bin/gen-verify-search.py` — the script adds new files, drops"
        " deleted ones and refreshes `Last Updated`.",
        "- Scope: tracked plus untracked-but-not-ignored files, excluding `skills/` (agent skill"
        " bundles), hidden directories and the index itself.",
        "",
        "# Verify Scripts Search Results",
        f"**Last Updated:** {today}",
        "",
        "## Shell Scripts (`.sh`)",
        "",
    ]

    grouped: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for path in shells:
        grouped[classify(path, SHELL_RULES)].append((path, describe_shell(path)))

    for section, _ in SHELL_RULES:
        rows = grouped.get(section)
        if not rows:
            continue
        lines.append(f"### {section}")
        lines.append("")
        lines += table(sorted(rows))
        lines.append("")

    lines += ["---", "", "## Markdown Documents (`.md`)", ""]

    grouped = defaultdict(list)
    for path in docs:
        grouped[classify(path, DOC_RULES)].append((path, describe_doc(path)))

    for section, _ in DOC_RULES:
        rows = grouped.get(section)
        if not rows:
            continue
        lines.append(f"### {section}")
        lines.append("")
        lines.append("| File Path | Title |")
        lines.append("| :--- | :--- |")
        lines += [f"| `{path}` | {desc} |" for path, desc in sorted(rows)]
        lines.append("")

    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="exit 1 if the index is stale")
    parser.add_argument("--stats", action="store_true", help="print per-section counts only")
    args = parser.parse_args()

    shells, docs = collect_files()
    today = subprocess.run(["date", "+%Y-%m-%d"], capture_output=True, text=True, check=True).stdout.strip()
    content = render(shells, docs, today)

    if args.stats:
        counts_sh = Counter(classify(p, SHELL_RULES) for p in shells)
        counts_md = Counter(classify(p, DOC_RULES) for p in docs)
        print(f"shell scripts: {len(shells)}")
        for section, count in counts_sh.items():
            print(f"  {count:5d}  {section}")
        print(f"markdown docs: {len(docs)}")
        for section, count in counts_md.items():
            print(f"  {count:5d}  {section}")
        return 0

    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
    if current == content:
        print(f"{OUTPUT.name} is up to date ({len(shells)} scripts, {len(docs)} docs)")
        return 0

    if args.check:
        print(f"{OUTPUT.name} is stale — run: python3 bin/{os.path.basename(__file__)}")
        return 1

    OUTPUT.write_text(content, encoding="utf-8")
    print(f"wrote {OUTPUT.name}: {len(shells)} scripts, {len(docs)} docs, {len(content.splitlines())} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
