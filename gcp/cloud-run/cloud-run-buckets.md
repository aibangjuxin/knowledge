# Cloud Run访问Cloud Storage Buckets

Cloud Run服务默认情况下无法直接访问Cloud Storage Buckets,需要为Cloud Run服务关联一个具有相应权限的Service Account.

## 操作步骤

1. 创建一个Service Account
   ```bash
   gcloud iam service-accounts create ${sa_name} --display-name="${sa_name}"
   ```

2. 为Service Account授予访问Bucket的权限
   ```bash
   gsutil iam ch serviceAccount:${sa_name}@${project_id}.iam.gserviceaccount.com:objectAdmin gs://${bucket_name}
   ```

3. 部署Cloud Run服务时,指定Service Account
   ```bash
   gcloud run deploy ${service_name} --image=${image_name} --service-account=${sa_name}@${project_id}.iam.gserviceaccount.com
   ```

## 权限说明

| 角色                          | 权限                                       |
| ----------------------------- | ------------------------------------------ |
| `roles/storage.objectViewer`  | 查看对象和其元数据,不包括ACL               |
| `roles/storage.objectCreator` | 创建对象                                   |
| `roles/storage.objectAdmin`   | 完全控制对象,包括读、写、删除和设置ACL |

## 总结

通过为Cloud Run服务关联具有相应权限的Service Account,可以安全地访问Cloud Storage Buckets.
