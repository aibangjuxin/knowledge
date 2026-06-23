# envs/dev/project-a/main.tf
# 完整 dev env 例子:bootstrap + network + gke + cert + glb + nginx/squid + monitoring + secret
# 8 个 module 引用,无 resource {} 块

module "project_bootstrap" {
  source     = "../../../modules/project-bootstrap"
  project_id = local.project_id
  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "certificatemanager.googleapis.com",
    "secretmanager.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
  ]
  labels = local.common_labels
}

module "network" {
  source     = "../../../modules/network"
  project_id = module.project_bootstrap.project_id
  region     = local.region
  vpc_name   = "${local.env}-${local.project_id_short}-vpc"

  subnets = {
    gke = {
      cidr    = "10.10.0.0/20"
      purpose = "GKE"
    }
    proxy = {
      cidr    = "10.10.16.0/24"
      purpose = "REGIONAL_MANAGED_PROXY"
    }
    backend = {
      cidr    = "10.10.32.0/20"
      purpose = "GCE"
    }
  }
}

module "gke" {
  source                   = "../../../modules/gke"
  project_id               = module.project_bootstrap.project_id
  cluster_name             = var.cluster_name
  region                   = local.region
  network                  = module.network.vpc_self_link
  subnetwork               = module.network.subnets["gke"].self_link
  node_count               = var.node_count
  release_channel          = "REGULAR"
  enable_workload_identity = true
  labels                   = local.common_labels
}

module "cert_manager" {
  source     = "../../../modules/cert-manager"
  project_id = module.project_bootstrap.project_id
  domains    = [var.domain_name]
}

module "glb_public" {
  source      = "../../../modules/glb-public"
  project_id  = module.project_bootstrap.project_id
  region      = local.region
  domains     = [var.domain_name]
  backend_service_backends = [
    { name = module.nginx.backend_service_name }
  ]
  cert_manager_certificate = module.cert_manager.certificate_id
}

module "nginx" {
  source      = "../../../modules/nginx-squid"
  component   = "nginx"
  project_id  = module.project_bootstrap.project_id
  gke_cluster = module.gke.cluster_id
  namespace   = "nginx"
  upstream    = "http://squid.squid.svc.cluster.local:3128"
}

module "squid" {
  source      = "../../../modules/nginx-squid"
  component   = "squid"
  project_id  = module.project_bootstrap.project_id
  gke_cluster = module.gke.cluster_id
  namespace   = "squid"
  upstream    = "http://internal-api.default.svc.cluster.local:8080"
}

module "monitoring" {
  source     = "../../../modules/monitoring"
  project_id = module.project_bootstrap.project_id
  alerts = {
    high-cpu = {
      resource_type = "k8s_container"
      threshold     = 0.85
      duration      = "300s"
    }
    high-error-rate = {
      resource_type = "https_lb_rule"
      threshold     = 0.05
      duration      = "120s"
    }
  }
  notification_channels = ["projects/${local.project_id}/notificationChannels/dev-team"]
}
