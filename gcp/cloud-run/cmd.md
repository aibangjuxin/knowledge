```bash
env_list=$(echo "$job_config" | jq -r '
    .spec.template.spec.template.spec.containers[0].env[]? 
    | select(.valueFrom == null) 
    | "\(.name)=\(.value)"
' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
```

```bash
gcloud run jobs describe job-name --region europe-west2 --format="json" | jq -r '.spec.template.spec.template.spec.containers[0].env[]? | select(.valueFrom == null) | "\(.name)=\(.value)"'
```

```bash
gcloud run jobs describe job-name --region europe-west2 --format="json" | jq -r '.spec.template.spec.template.spec.containers[0].env[]? | select(.valueFrom == null) | "\(.name)=\(.value)"' | tr '\n' ',' | sed 's/,$//'
```