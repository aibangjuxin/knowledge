# .tflint.hcl - tflint 静态检查配置
# https://github.com/terraform-linters/tflint

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.25.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
  # 在 modules/<name>/versions.tf 设置 required_version
}

# GCP-specific rules
rule "google_project_label_name" {
  enabled = true
  format  = "^[a-z][-a-z0-9_.a-z0-9]{0,62}$"
}
