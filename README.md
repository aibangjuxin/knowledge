# Knowledge

> Lex's personal knowledge base — cloud architecture, AI, developer tools, and everything in between.

![Knowledge Workspace](https://img.shields.io/badge/Workspace-Knowledge-blue)
![Platform-macOS](https://img.shields.io/badge/Platform-macOS-purple)
![AI-GCP%20focused](https://img.shields.io/badge/Focus-GCP%20%7C%20AI%20%7C%20K8s-green)

---

## 🗂️ Workspace Structure

### Infrastructure & Cloud

| Path | Description |
|------|-------------|
| `gcp/` | GCP architecture: Load Balancing, VPC, IAP, Cloud Armor, multi-tenant |
| `gke/` | GKE platform: cluster setup, workload identity, autoscaling, addons |
| `k8s/` | Kubernetes: networking, storage, RBAC, operators, Helm |
| `dns/` | DNS design: Cloud DNS, private zones, split-horizon, record management |
| `network/` | Network topology: VPC design, firewall rules, peering, HA |
| `ssl/` | TLS/SSL: cert management, mTLS, public CA, private PKI |
| `terrafrom/` | Terraform IaC: module design, state management, CI/CD |

### AI & Development

| Path | Description |
|------|-------------|
| `ai/` | AI tools: prompts, fine-tuning, model serving, local LLM infra |
| `skills/` | Reusable agent skills: workflow automation, MCP, skill authoring |
| `prompt/` | Prompt engineering: templates, techniques, evaluation |
| `api-service/` | API design: REST, gRPC, versioning, auth patterns |
| `node/` | Node.js ecosystem: runtime, packages, best practices |
| `java/` | Java / JVM: Spring Boot, performance tuning, concurrency |

### Apple Ecosystem

| Path | Description |
|------|-------------|
| `macos/` | macOS automation: scripts, Homebrew, system config |
| `ios/` | iOS development: Xcode, Swift, SwiftUI, device management |
| `apple/` | Apple platform: iPad, Shortcuts, Continuity, AirDrop |

### Operations & Security

| Path | Description |
|------|-------------|
| `safe/` | Security research: CVE, pentest notes, threat modeling |
| `sre/` | SRE practices: SLOs, error budgets, incident response |
| `monitor/` | Observability: logging, metrics, tracing, alerting |
| `logs/` | Log analysis: patterns, grep tricks, log diving |

### Reference & Productivity

| Path | Description |
|------|-------------|
| `nginx/` | Nginx: reverse proxy, rate limiting, config snippets |
| `kong/` | Kong API Gateway: plugins, declarative config, auth |
| `docker/` | Docker: Dockerfile best practices, multi-stage builds, registry |
| `shell-script/` | Shell scripts: reusable utilities, automation |
| `shortcut/` | Shortcuts: Apple Shortcuts, CLI workflows |
| `bin/` | Bin utilities: single-file tools, wrappers |

### Languages & Learning

| Path | Description |
|------|-------------|
| `English/` | English learning: vocabulary, phrases, business writing |
| `go/` | Go: concurrency patterns, stdlib, best practices |
| `python/` | Python: scripts, data tools, venv management |
| `linux/` | Linux: systemd, networking, performance tuning |
| `git.sh` / `git-detail-status.sh` | Git utilities: analysis, visualization, workflow |

---

## 💡 Core Philosophy

> **From command-driven to model-driven.**

```
Concept → Resource Model → Dependencies → Command
```

When working with complex systems (GCP, Kubernetes, Linux), the natural tendency is:

```
Find a command → Change parameters → Execute → Error → Repeat
```

The better approach:

```
Understand the resource model → Map dependencies → Then execute.
```

### The Four Layers

1. **Concept** — What is this resource? What problem does it solve?
2. **Resource Model** — What are its required/optional/read-only fields?
3. **Dependencies** — What must exist before this resource can be created?
4. **Command** — Only after understanding 1–3 does the command make sense.

### The Three Self-Checks

Before creating any resource, ask:

1. **Position** — Where does this resource sit in the architecture?
2. **Dependencies** — What other resources does it depend on?
3. **Abstraction** — Which layer of the API does my command target? (REST / Terraform / gcloud / Console)

> Command is not a design tool — it is only an execution tool.

---

## 🚀 Quick Start

```bash
# Navigate to workspace
cd ~/git/knowledge

# Pick a topic
cd gcp && cat README.md
cd k8s/networking
cd ai/prompts

# Run a utility
./bin/git-analysis.sh
./fm.sh
```

---

## 🔧 AI Agent Integration

This workspace includes `AGENTS.md` — designed for AI coding agents
(Claude Code, Codex, Hermes Agent, etc.).

```
knowledge/
├── AGENTS.md          # Agent instructions (this workspace's contract)
├── skills/            # Skill definitions
│   ├── architectrue/  # GCP/GKE architecture partner
│   ├── mac-stats/     # Mac system stats
│   └── ...
└── prompt/            # Prompt templates
```

When an AI agent operates in this workspace, it reads `AGENTS.md` and the
corresponding skill files to understand context, conventions, and constraints.

---

## 📊 Workspace Stats

```bash
find ~/git/knowledge -maxdepth 1 -type d | wc -l   # directories
find ~/git/knowledge -name "*.md" | wc -l           # markdown files
find ~/git/knowledge -name "*.sh" | wc -l           # shell scripts
```

---

## 📝 Contributing

This is a personal knowledge base. Structure conventions:

- One topic → one directory
- `README.md` inside each directory explains the topic
- Scripts in `bin/` are executable utilities
- Skills in `skills/` follow the `SKILL.md` format

---

> **Knowledge compounds. Document what you learn, and it becomes searchable forever.**
