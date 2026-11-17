`gcloud storage buckets describe pre-env-region-gkeconfigs --project=aibang-projectid-wwww-dev --format=json`
kms-project == abjx-id-kms-dev region == europe-west2 project == aibang-projectid-wwww-dev buckets = gs://pre-env-region-gkeconfigs gs://pre-env-region-gkeconfigs2 

以下是该`gcloud`命令的输出内容（JSON格式）：
- `gcloud storage buckets describe pre-env-region-gkeconfigs --project=aibang-projectid-wwww-dev --format=json`
```json
{
  "autoclass": {
    "enabled": true,
    "terminalStorageClass": "ARCHIVE",
    "terminalStorageClassUpdateTime": "2025-05-08T20:11:22.705000+00:00",
    "toggleTime": "2025-05-08T20:11:22.705000+00:00"
  },
  "autoclass_enabled_time": "2025-05-08T20:11:22+0000",
  "creation_time": "2021-05-14T01:35:39+0000",
  "default_kms_key": "projects/abjx-id-kms-dev/locations/europe-west2/keyRings/cloudStorage/cryptoKeys/cloudStorage",
  "default_storage_class": "STANDARD",
  "generation": 1620956136569003542,
  "labels": {
    "enforcer_autoclass": "enabled"
  },
  "location": "EUROPE-WEST2",
  "location_type": "region",
  "metageneration": 790,
  "name": "pre-env-region-gkeconfigs",
  "public_access_prevention": "inherited",
  "satisfies_pzs": true,
  "soft_delete_policy": {
    "effectiveTime": "2024-03-01T08:00:00+00:00",
    "retentionDurationSeconds": "604800"
  },
  "storage_url": "gs://pre-env-region-gkeconfigs/",
  "uniform_bucket_level_access": true,
  "update_time": "2025-05-08T20:11:22+0000"
}
```

