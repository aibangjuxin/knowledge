#!/usr/bin/env bash
# GCP Platform Exploration Script
# 探索 GCP 平台中可以获取的各种信息

set -euo pipefail

echo "=== GCP Platform Exploration ==="
echo ""

# 检查 gcloud 是否安装
if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud not found. Please install Google Cloud SDK."
  exit 1
fi

PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$PROJECT" ]]; then
  echo "Error: No active project. Run: gcloud config set project PROJECT_ID"
  exit 1
fi

echo "Current Project: $PROJECT"
echo ""

# 1. Compute Engine
echo "--- Compute Engine ---"
echo "Instances:"
gcloud compute instances list --format="table(name,zone,machineType,status,networkInterfaces[0].networkIP:label=INTERNAL_IP)" 2>/dev/null || echo "  No instances or permission denied"
echo ""

echo "Instance Groups:"
gcloud compute instance-groups list --format="table(name,location,size)" 2>/dev/null || echo "  No instance groups"
echo ""

echo "Disks:"
gcloud compute disks list --format="table(name,zone,sizeGb,type,status)" 2>/dev/null | head -n 10 || echo "  No disks"
echo ""

# 2. GKE
echo "--- Google Kubernetes Engine ---"
echo "Clusters:"
gcloud container clusters list --format="table(name,location,currentMasterVersion,currentNodeCount,status)" 2>/dev/null || echo "  No clusters"
echo ""

# 3. Networking
echo "--- Networking ---"
echo "VPCs:"
gcloud compute networks list --format="table(name,subnet_mode,bgpRoutingMode)" 2>/dev/null || echo "  No VPCs"
echo ""

echo "Subnets (first 10):"
gcloud compute networks subnets list --format="table(name,region,network,ipCidrRange)" 2>/dev/null | head -n 10 || echo "  No subnets"
echo ""

echo "Firewall Rules (first 10):"
gcloud compute firewall-rules list --format="table(name,network,direction,priority,sourceRanges.list():label=SRC_RANGES)" 2>/dev/null | head -n 10 || echo "  No firewall rules"
echo ""

echo "Routes (first 10):"
gcloud compute routes list --format="table(name,network,destRange,nextHopGateway,priority)" 2>/dev/null | head -n 10 || echo "  No routes"
echo ""

echo "VPC Peerings:"
gcloud compute networks peerings list --format="table(name,network,peerNetwork,state)" 2>/dev/null || echo "  No peerings"
echo ""

# 4. Load Balancing
echo "--- Load Balancing ---"
echo "Forwarding Rules:"
gcloud compute forwarding-rules list --format="table(name,region,IPAddress,target)" 2>/dev/null || echo "  No forwarding rules"
echo ""

echo "Backend Services:"
gcloud compute backend-services list --format="table(name,backends[].group.basename():label=BACKENDS,protocol)" 2>/dev/null || echo "  No backend services"
echo ""

echo "Health Checks:"
gcloud compute health-checks list --format="table(name,type,healthyThreshold,unhealthyThreshold)" 2>/dev/null || echo "  No health checks"
echo ""

# 5. Cloud Armor
echo "--- Cloud Armor ---"
echo "Security Policies:"
gcloud compute security-policies list --format="table(name,description,ruleTupleCount)" 2>/dev/null || echo "  No security policies"
echo ""

# 6. Storage
echo "--- Storage ---"
echo "Buckets (first 10):"
gsutil ls 2>/dev/null | head -n 10 || echo "  No buckets or permission denied"
echo ""

# 7. Cloud SQL
echo "--- Cloud SQL ---"
echo "Instances:"
gcloud sql instances list --format="table(name,databaseVersion,region,tier,ipAddresses[0].ipAddress:label=IP,state)" 2>/dev/null || echo "  No SQL instances"
echo ""

# 8. Secret Manager
echo "--- Secret Manager ---"
echo "Secrets (first 10):"
gcloud secrets list --format="table(name,created,replication.automatic:label=AUTO_REPLICATION)" 2>/dev/null | head -n 10 || echo "  No secrets"
echo ""

# 9. IAM
echo "--- IAM ---"
echo "Service Accounts:"
gcloud iam service-accounts list --format="table(email,displayName,disabled)" 2>/dev/null || echo "  No service accounts"
echo ""

# 10. Cloud Run
echo "--- Cloud Run ---"
echo "Services:"
gcloud run services list --format="table(metadata.name,status.url,status.latestReadyRevisionName)" 2>/dev/null || echo "  No Cloud Run services"
echo ""

# 11. Cloud Functions
echo "--- Cloud Functions ---"
echo "Functions (Gen 1):"
gcloud functions list --format="table(name,status,trigger,runtime)" 2>/dev/null || echo "  No functions"
echo ""

# 12. Pub/Sub
echo "--- Pub/Sub ---"
echo "Topics (first 10):"
gcloud pubsub topics list --format="table(name)" 2>/dev/null | head -n 10 || echo "  No topics"
echo ""

echo "Subscriptions (first 10):"
gcloud pubsub subscriptions list --format="table(name,topic.basename():label=TOPIC,ackDeadlineSeconds)" 2>/dev/null | head -n 10 || echo "  No subscriptions"
echo ""

# 13. Cloud DNS
echo "--- Cloud DNS ---"
echo "Managed Zones:"
gcloud dns managed-zones list --format="table(name,dnsName,visibility)" 2>/dev/null || echo "  No DNS zones"
echo ""

# 14. BigQuery
echo "--- BigQuery ---"
echo "Datasets:"
bq ls --format=pretty 2>/dev/null || echo "  No datasets or bq not configured"
echo ""

# 15. APIs
echo "--- Enabled APIs (first 15) ---"
gcloud services list --enabled --format="table(config.name,config.title)" 2>/dev/null | head -n 15 || echo "  Cannot list APIs"
echo ""

# 16. Billing
echo "--- Billing ---"
echo "Billing Accounts:"
gcloud billing accounts list --format="table(name,displayName,open)" 2>/dev/null || echo "  No billing access"
echo ""

# 17. Organization
echo "--- Organization ---"
echo "Projects:"
gcloud projects list --format="table(projectId,name,projectNumber)" 2>/dev/null | head -n 10 || echo "  Cannot list projects"
echo ""

# 18. Monitoring
echo "--- Monitoring ---"
echo "Uptime Checks:"
gcloud monitoring uptime list --format="table(name,displayName,monitoredResource.type)" 2>/dev/null || echo "  No uptime checks"
echo ""

# 19. Logging
echo "--- Logging ---"
echo "Log Sinks:"
gcloud logging sinks list --format="table(name,destination,filter)" 2>/dev/null || echo "  No log sinks"
echo ""

# 20. Certificates
echo "--- SSL Certificates ---"
echo "SSL Certificates:"
gcloud compute ssl-certificates list --format="table(name,type,creationTimestamp,expireTime)" 2>/dev/null || echo "  No SSL certificates"
echo ""

# 21. Quotas (sample)
echo "--- Quotas (Sample) ---"
echo "Compute Engine Quotas (CPUs):"
gcloud compute project-info describe --format="value(quotas.filter(metric:CPUS))" 2>/dev/null || echo "  Cannot retrieve quotas"
echo ""

echo "=== Exploration Complete ==="
