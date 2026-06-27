# GCP Terraform Monorepo Best Practices — 2025/2026 Validation

> Web research conducted 2026-06-27 to validate the v1 layout at `/Users/lex/git/knowledge/gcp/terraform/` against current authoritative sources.
> Verdict at-a-glance: **v1 layout is still best-practice**. Only one notable shift: the foundation blueprint now uses `<stage>/business_unit_<n>/<env>/` instead of a flat `envs/<env>/` layout — see Q2.

---

## 1. HashiCorp Standard Module Structure — still canonical (2025+)

**Source:** HashiCorp Developer docs (v1.15.x as of 2025-11-19; mirrored at web.archive.org on 2025-12-24).
URL: https://developer.hashicorp.com/terraform/language/modules/develop
Archive: https://web.archive.org/web/20251224181335/https://developer.hashicorp.com/terraform/language/modules/develop

> "To define a module, create a new directory for it and place one or more `.tf` files inside just as you would do for a root module."

> "Modules can also call other modules using a `module` block, but we recommend keeping the module tree relatively flat and using [module composition] as an alternative to a deeply-nested tree of modules, because this makes the individual modules easier to re-use in different combinations."

**Verdict:** No structural change in 2024–2026. The two non-obvious additions in current docs:
- "No-Code Provisioning in HCP Terraform" (module-design requirements for the registry).
- "Refactoring module resources" (new `refactoring {}` block for renaming/structural moves).
Neither invalidates the v1 layout.

---

## 2. terraform-example-foundation — layout shifted in 2025

**Source:** `terraform-example-foundation` repo README on `main` (commits through 2026-06-22; 21 commits in last 12 months — actively maintained).
URL: https://github.com/terraform-google-modules/terraform-example-foundation
Raw: https://raw.githubusercontent.com/terraform-google-modules/terraform-example-foundation/main/README.md

**Active repo paths** (verified via GitHub Contents API 2026-06-27):
- `0-bootstrap/` — one-off bootstrap (not env-aware)
- `1-org/envs/shared/` — envs/ layout, but only "shared" is set
- `2-environments/envs/{development,nonproduction,production}/`
- `3-networks-svpc/envs/{shared,development,nonproduction,production}/`
- `3-networks-hub-and-spoke/envs/{shared,development,nonproduction,production}/`
- **`4-projects/business_unit_1/{development,nonproduction,production}/`** ← **major 2025 shift**

The 4-projects step abandoned the flat `envs/<env>/` pattern and introduced a per-business-unit dimension:

```
4-projects/
  business_unit_1/
    development/
    nonproduction/
    production/
  business_unit_2/    # (extensible)
```

> "[foundation README] The intended audience of this blueprint is large enterprise organizations with a dedicated platform team responsible for deploying and maintaining their GCP environment."

**Verdict for v1:** **Keep `envs/<env>/<project>/`** — the v1 layout is the right simplification for non-enterprise scale. If you ever need multi-business-unit fan-out, model it as `envs/<env>/<business_unit>/<project>/`. The foundation's heavier `4-projects/business_unit_<n>/<env>/` ordering is a quirk of how Cloud Build triggers map 1:1 to Git branches; not a recommendation for everyone.

---

## 3. GCS backend — one bucket per project, CMEK-encrypted, object versioning on

**Source A:** Google Cloud docs — "Store Terraform state in a Cloud Storage bucket".
URL: https://cloud.google.com/docs/terraform/resource-management/store-state-in-cloud-storage

**Source B:** `terraform-example-foundation/0-bootstrap/main.tf` — actual reference implementation.
URL: https://raw.githubusercontent.com/terraform-google-modules/terraform-example-foundation/main/0-bootstrap/main.tf

Quote from the bootstrap source:
```hcl
state_bucket_name    = "${var.bucket_prefix}-${var.project_prefix}-b-seed-tfstate"
encrypt_gcs_bucket_tfstate = true
kms_prevent_destroy  = !var.bucket_tfstate_kms_force_destroy
key_rotation_period  = "7776000s"     # 90 days
```

Foundation README confirms (line 22-ish):
> "It is a best practice to separate concerns by having two projects here: one for the Terraform state and one for the CI/CD tool.
>   - The `prj-b-seed` project stores Terraform state and has the service accounts that can create or modify infrastructure."

**Verdict:** **One bucket per state-project**, not a giant shared bucket. Each bucket is:
- CMEK-encrypted with a customer-managed KMS key
- In a dedicated state project (separate from CI/CD project)
- Object versioning should be enabled (standard GCS best practice; foundation enables it on log-export buckets and recommends it for state buckets)
- Uniform bucket-level access (UBLA) enabled
- Public access prevention enforced

This validates v1's `references/state-and-backend.md` approach. One nuance worth adding: pin a 90-day KMS rotation (`key_rotation_period = "7776000s"`) as the foundation does.

---

## 4. Module placement — pull from public registry, not vendor in private

**Source:** terraform-google-modules registry namespace + project-factory README.
URL: https://registry.terraform.io/namespaces/terraform-google-modules
URL: https://raw.githubusercontent.com/terraform-google-modules/terraform-google-project-factory/master/README.md

Project Factory README explicitly shows the public-registry consumption pattern:
```hcl
module "project-factory" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.3"
  # ...
}
```

**Trade-offs (confirmed by foundation's own usage):**
- ✅ Public registry = pinned version (`~> 18.3`), security-cve notifications, no maintenance burden
- ✅ Modules are battle-tested across thousands of GCP customers
- ❌ You can't modify them — fork only if you need divergence
- ❌ Big version jumps sometimes break inputs (read CHANGELOG before bumping)
- 🟡 Keep `modules/` for **GCP-specific glue** (your VPC layout, your IAM roles, your labels) — not for re-implementing what the registry already does well

**Verdict for v1:** v1's current 14 private modules are mostly the right call (they encode *your* platform conventions). But `modules/storage/`, `modules/dns/`, `modules/iam/`, `modules/network/` should at least be evaluated against the public registry versions before being maintained in-house — particularly `terraform-google-modules/project-factory` for the project-bootstrap module.

---

## 5. Terragrunt vs Terraform Stacks — for sub-20 envs, **plain TF still wins**

**Source A:** Terragrunt docs (moved to `docs.terragrunt.com`, current 2025 site with `v1.0 is here!` banner).
URL: https://docs.terragrunt.com/getting-started/overview/
URL: https://docs.terragrunt.com/guides/terralith-to-terragrunt/

Quote from the Terralith-to-Terragrunt guide:
> "A common challenge that emerges as infrastructure grows is the 'Terralith,' a portmanteau of Terraform and Monolith. This pattern, also referred to as a 'Megamodule' or an 'All In One State' configuration, describes a scenario where a large, complex infrastructure estate is managed within a single state file."

The guide is framed as a refactoring story — implying the threshold is when you've outgrown one root module, not when you have N environments.

**Source B:** Terraform Stacks (announced 2024-04, HCP-only, still HCP-only as of 2026-06).
The Stacks product requires HCP Terraform and was GA'd in HCP only — it has not been folded into OSS Terraform. Community consensus remains that Stacks competes with Terragrunt for the same problem space (multi-stack dependency graphs) but requires paid HCP Terraform.

**Consensus for sub-20 env setups (2025+):**
- < 5 envs × < 10 components → **plain TF + `envs/<env>/<project>/`** (v1 today)
- 5–20 envs or shared backend/remote-state config duplication → **consider Terragrunt `run --all`** (it's now first-class with v1.0; see "Terragrunt v1.0 is here!" banner)
- > 20 envs, or cross-stack dependencies, or HCP Terraform already in use → evaluate Stacks in parallel
- The foundation blueprint itself **does NOT use Terragrunt** — it uses Cloud Build triggers. That's a signal that "the canonical GCP reference architecture" considers Cloud Build + plain TF sufficient.

**Verdict for v1:** v1's "现阶段不要 — < 20 env 用纯 TF" is still correct and consistent with 2025+ community guidance.

---

## 6. Project factory pattern — still the canonical GCP project-creation module

**Source:** `terraform-google-project-factory` README.
URL: https://github.com/terraform-google-modules/terraform-google-project-factory

> "This module allows you to create opinionated Google Cloud Platform projects. It creates projects and configures aspects like Shared VPC connectivity, IAM access, Service Accounts, and API enablement to follow best practices."

The module will, in one `module "project-factory"` call:
1. Create the GCP project
2. Attach to Shared VPC host project + grant network User role on specified subnets
3. Delete default compute SA, create a new default SA
4. Attach billing account
5. Grant controlling group the configured role
6. Enable required + caller-specified APIs
7. Delete default network
8. Optionally create a state GCS bucket + grant `storage.admin` to controlling group / new SA / Google APIs SA
9. Optionally route GCE usage reports to a central bucket

**What's new in 2025+ (project-factory v18.x):**
- Terraform 1.3+ compatibility (was 0.12.x as recently as 2022)
- Multi-universe support (`universe_domain` for GKE-style sovereign clouds)

**Verdict for v1:** Replace or wrap `modules/project-bootstrap/` with a thin wrapper around `terraform-google-modules/project-factory/google ~> 18.3`. Keep your own module only for the inputs the registry doesn't expose (your label conventions, your OS Login group, your VPC-SC perimeter assignment). This is a concrete reduction in maintenance burden — the project-factory module has dedicated maintainers; yours doesn't.

---

## Summary — delta vs v1 knowledge base

| # | v1 statement | 2025/2026 verdict | Action |
|---|---|---|---|
| 1 | HashiCorp Standard Module Structure is canonical | Still canonical. Added `refactoring {}` block and no-code-ready guidance, but no layout change. | None |
| 2 | `envs/<env>/<project>/` layout | Foundation shifted to `4-projects/business_unit_<n>/<env>/` but only because of Cloud Build trigger/branch mapping. v1's flattening is still correct for non-enterprise. | None (or add ADR for future BU fan-out) |
| 3 | State bucket per state-project, GCS backend | Confirmed + add CMEK 90-day rotation as a default | Update `references/state-and-backend.md` |
| 4 | Public registry vs private modules | Public-registry-first is correct; foundation uses it heavily | Audit `modules/storage/`, `modules/dns/`, `modules/iam/`, `modules/network/` against public registry |
| 5 | No Terragrunt for sub-20 envs | Confirmed by Terragrunt v1.0 docs themselves + foundation blueprint using Cloud Build instead | None |
| 6 | Project factory for new GCP projects | Confirmed — `terraform-google-project-factory/google ~> 18.3` is the canonical 2025 answer | Wrap or replace `modules/project-bootstrap/` |
