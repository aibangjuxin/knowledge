# envs/dev/project-a/backend.tf
terraform {
  backend "gcs" {
    bucket = "tfstate-dev-project-a-uscentral1"
    prefix = "envs/dev/project-a"
  }
}
