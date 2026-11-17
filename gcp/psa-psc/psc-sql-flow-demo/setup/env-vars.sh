#!/bin/bash

# 环境变量配置文件
# 使用方法: source setup/env-vars.sh

# 通用配置
export REGION=asia-east2
export ZONE=asia-east2-a

# Producer 项目配置 (Cloud SQL)
export PRODUCER_PROJECT_ID=your-producer-project
export PRODUCER_VPC=producer-vpc
export SQL_INSTANCE_NAME=my-sql-instance
export SQL_DATABASE_VERSION=MYSQL_8_0
export SQL_TIER=db-n1-standard-2
export SQL_ROOT_PASSWORD=SecurePassword123!
export SQL_DATABASE_NAME=appdb
export SQL_USER=appuser
export SQL_USER_PASSWORD=AppUserPassword123!

# Consumer 项目配置 (GKE)
export CONSUMER_PROJECT_ID=your-consumer-project
export CONSUMER_VPC=consumer-vpc
export CONSUMER_SUBNET=gke-subnet
export GKE_CLUSTER_NAME=psc-demo-cluster
export GKE_NODE_POOL=default-pool

# PSC 配置
export PSC_ENDPOINT_NAME=sql-psc-endpoint
export STATIC_IP_NAME=sql-psc-ip

# Kubernetes 配置
export NAMESPACE=psc-demo
export APP_NAME=db-app
export SERVICE_ACCOUNT_NAME=db-app-sa
export WORKLOAD_IDENTITY_SA=db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com

# 数据库配置
export DB_PORT=3306
export DB_CONNECTION_POOL_SIZE=10
export DB_MAX_IDLE_CONNECTIONS=5

echo "环境变量已设置完成！"
echo "Producer Project: ${PRODUCER_PROJECT_ID}"
echo "Consumer Project: ${CONSUMER_PROJECT_ID}"
echo "Region: ${REGION}"
echo "GKE Cluster: ${GKE_CLUSTER_NAME}"