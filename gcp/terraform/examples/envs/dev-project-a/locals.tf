# envs/dev/project-a/locals.tf
locals {
  project_id       = "aibang-dev-project-a"
  project_id_short = "project-a"
  region           = "us-central1"
  env              = "dev"

  common_labels = {
    env        = local.env
    project    = local.project_id_short
    managed_by = "terraform"
    repo       = "terraform-gcp-platform"
    cost_center = "engineering"
  }
}
