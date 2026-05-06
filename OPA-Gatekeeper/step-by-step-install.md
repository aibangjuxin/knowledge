# GKE Policy Controller Installation Guide

## Overview

This document provides a detailed, step-by-step guide for installing GKE Policy Controller on a GKE cluster. The installation joins the cluster to a Fleet and enables Policy Controller for policy enforcement.

**Environment:**
- Project ID: `aibang-12345678-ajbx-dev`
- Cluster Name: `dev-lon-cluster-xxxxxx`
- Cluster Location: `europe-west2`
- Fleet Membership Name: `aibang-master`
- Policy Controller Version: `1.23.1`

---

## Prerequisites

### Required APIs

The following Google Cloud APIs must be enabled:

| API | Purpose |
|-----|---------|
| `anthospolicycontroller.googleapis.com` | Policy Controller API |
| `gkehub.googleapis.com` | GKE Hub / Fleet API |
| `anthosconfigmanagement.googleapis.com` | Anthos Config Management API |

### IAM Permissions

Ensure the current user has the following roles:
- `roles/gkehub.admin` or equivalent
- `roles/iam.serviceAccountUser`

### CLI Tools

- `gcloud` - Google Cloud CLI
- `kubectl` - Kubernetes CLI

---

## Step 1: Environment Verification

### 1.1 List Current GKE Clusters

**Command:**
```bash
gcloud container clusters list
```

**Output:**
```
NAME                     LOCATION      MASTER_VERSION  MASTER_IP       MACHINE_TYPE  NODE_VERSION  NUM_NODES  STATUS
dev-lon-cluster-xxxxxx   europe-west2  1.35.1-gke.1396002  35.189.124.66  e2-medium    1.35.1-gke.1396002  3  RUNNING
```

**Description:** Verifies the target cluster exists and is in RUNNING state.

### 1.2 Get Current kubectl Context

**Command:**
```bash
kubectl config current-context
```

**Output:**
```
gke_aibang-12345678-ajbx-dev_europe-west2_dev-lon-cluster-xxxxxx
```

**Description:** Confirms kubectl is configured to access the target cluster.

### 1.3 List Current Namespaces

**Command:**
```bash
kubectl get namespaces
```

**Output:**
```
NAME                          STATUS   AGE
default                       Active   35h
gke-managed-cim               Active   35h
gke-managed-networking-dra-driver  Active  35h
gke-managed-system            Active   35h
gke-managed-volumepopulator   Active   35h
gmp-public                    Active   35h
gmp-system                    Active   35h
kube-node-lease               Active   35h
kube-public                   Active   35h
kube-system                   Active   35h
```

**Description:** Shows existing namespaces. Note: No `gatekeeper-system` namespace exists, which is good (no conflicting open-source Gatekeeper installation).

### 1.4 Check for Existing Gatekeeper Installation

**Command:**
```bash
kubectl get ns | grep -E "gatekeeper|gatekeeper-system" || echo "No Gatekeeper namespace found - OK"
```

**Output:**
```
No Gatekeeper namespace found - OK
```

**Description:** Verifies no open-source Gatekeeper is installed (would conflict with Policy Controller).

---

## Step 2: Enable Required APIs

### 2.1 Enable APIs

**Command:**
```bash
gcloud services enable anthospolicycontroller.googleapis.com gkehub.googleapis.com anthosconfigmanagement.googleapis.com
```

**Output:**
```
Operation "operations/acat.p2-487126826743-4e57ed2d-baa1-4778-9b6d-cae94e149ead" finished successfully.
```

**Description:** Enables the three required APIs for Policy Controller and Fleet management.

---

## Step 3: Register Cluster to Fleet

### 3.1 Check Existing Fleet Memberships

**Command:**
```bash
gcloud container hub memberships list
```

**Output:**
```
Listed 0 items.
```

**Description:** Confirms no existing Fleet memberships exist.

### 3.2 Register Cluster to Fleet

**Command:**
```bash
gcloud container hub memberships register aibang-master --gke-cluster=europe-west2/dev-lon-cluster-xxxxxx --enable-workload-identity
```

**Output:**
```
Waiting for membership to be created... .................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................done.
Finished registering to the Fleet.
```

**Parameters:**
- `--gke-cluster`: Format is `LOCATION/CLUSTER_NAME`
- `--enable-workload-identity`: Enables Workload Identity for secure service account binding

**Description:** Registers the cluster to the Fleet with the membership name `aibang-master`. This is a prerequisite for enabling Policy Controller.

---

## Step 4: Enable Policy Controller

### 4.1 Enable Policy Controller on Fleet Membership

**Command:**
```bash
gcloud container fleet policycontroller enable --memberships=aibang-master
```

**Output:**
```
Waiting for Feature Policy Controller to be created... ......................done.
Waiting for MembershipFeature projects/aibang-12345678-ajbx-dev/locations/europe-west2/memberships/aibang-master/features/policycontroller to be updated... .............done.
```

**Description:** Enables Policy Controller on the Fleet membership. This installs the Gatekeeper-based Policy Controller in the cluster.

---

## Step 5: Verify Policy Controller Installation

### 5.1 Check Policy Controller Status

**Command:**
```bash
gcloud container fleet policycontroller describe --memberships=aibang-master
```

**Output:**
```yaml
createTime: '2026-04-29T01:12:21.892334353Z'
membershipSpecs:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    policycontroller:
      policyControllerHubConfig:
        auditIntervalSeconds: '60'
        deploymentConfigs:
          admission:
            podAffinity: ANTI_AFFINITY
        installSpec: INSTALL_SPEC_ENABLED
        monitoring:
          backends:
          - PROMETHEUS
          - CLOUD_MONITORING
        policyContent:
          bundles:
            policy-essentials-v2022: {}
          templateLibrary:
            installation: ALL
        version: 1.23.1
membershipStates:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    policycontroller:
      componentStates:
        admission:
          details: 1.23.1
          state: ACTIVE
        audit:
          details: 1.23.1
          state: ACTIVE
        mutation:
          details: 'deployment not installed: resource is missing'
          state: NOT_INSTALLED
      policyContentState:
        bundleStates:
          asm-policy-v0.0.1:
            state: NOT_INSTALLED
          cis-gke-v1.5.0:
            state: NOT_INSTALLED
          cis-k8s-v1.5.1:
            state: NOT_INSTALLED
          cost-reliability-v2023:
            state: NOT_INSTALLED
          nist-sp-800-190:
            state: NOT_INSTALLED
          nist-sp-800-53-r5:
            state: NOT_INSTALLED
          nsa-cisa-k8s-v1.2:
            state: NOT_INSTALLED
          pci-dss-v3.2.1:
            state: NOT_INSTALLED
          pci-dss-v3.2.1-extended:
            state: NOT_INSTALLED
          pci-dss-v4.0:
            state: NOT_INSTALLED
          policy-essentials-v2022:
            details: object state is unknown
          psp-v2022:
            state: NOT_INSTALLED
          pss-baseline-v2022:
            state: NOT_INSTALLED
          pss-restricted-v2022:
            state: NOT_INSTALLED
          referentialSyncConfigState:
            state: NOT_INSTALLED
          templateLibraryState:
            state: ACTIVE
      state: updateTime: '2026-04-29T01:12:46.002120689Z'
name: projects/aibang-12345678-ajbx-dev/locations/global/features/policycontroller
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-04-29T01:12:24.945193581Z'
```

**Description:** Shows Policy Controller configuration and state. Key observations:
- `installSpec: INSTALL_SPEC_ENABLED` - Policy Controller is enabled
- `version: 1.23.1` - Using version 1.23.1
- `admission.state: ACTIVE` - Admission controller is active
- `audit.state: ACTIVE` - Audit functionality is active
- `mutation.state: NOT_INSTALLED` - Mutation webhook not installed (optional feature)
- `templateLibraryState: ACTIVE` - Template library is active
- `policy-essentials-v2022` bundle is being used

### 5.2 Check Gatekeeper Deployments

**Command:**
```bash
kubectl get deployments -n gatekeeper-system
```

**Output:**
```
NAME                         READY  UP-TO-DATE  AVAILABLE  AGE
gatekeeper-audit             1/1    1           1          58s
gatekeeper-controller-manager  1/1   1           1          60s
```

**Description:** Confirms the two Gatekeeper deployments are running (audit and controller manager).

### 5.3 Check Gatekeeper Pods

**Command:**
```bash
kubectl get pods -n gatekeeper-system
```

**Output:**
```
NAME                                          READY  STATUS   RESTARTS  AGE
gatekeeper-audit-57b4b9bbf9-n69g7             1/1    Running  0         2m56s
gatekeeper-controller-manager-79ff65dddb-rm2q6  1/1    Running  0         2m58s
```

**Description:** Both Gatekeeper pods are in Running state with 1/1 Ready.

### 5.4 Check Installed Constraint Templates

**Command:**
```bash
kubectl get constrainttemplates
```

**Output:**
```
NAME                                                    AGE
allowedserviceportname                                  57s
asmauthzpolicydisallowedprefix                          61s
asmauthzpolicyenforcesourceprincipals                   56s
asmauthzpolicynormalization                             60s
asmauthzpolicysafepattern                               64s
asmingressgatewaylabel                                  66s
asmpeerauthnstrictmtls                                  48s
asmrequestauthnprohibitedoutputheaders                  51s
asmsidecarinjection                                     45s
destinationruletlsenabled                               61s
disallowedauthzprefix                                   59s
gcpstoragelocationconstraintv1                          55s
k8sallowedrepos                                         56s
k8savoiduseofsystemmastersgroup                         43s
k8sblockallingress                                      50s
k8sblockcreationwithdefaultserviceaccount               46s
k8sblockendpointeditdefaultrole                         46s
k8sblockloadbalancer                                    65s
k8sblocknodeport                                        44s
k8sblockobjectsoftype                                   53s
k8sblockprocessnamespacesharing                         45s
k8sblockwildcardingress                                 65s
k8scontainerephemeralstoragelimit                       65s
k8scontainerlimits                                      60s
k8scontainerratios                                      44s
k8scontainerrequests                                    52s
k8scronjoballowedrepos                                  43s
k8sdisallowanonymous                                    50s
k8sdisallowedrepos                                      45s
k8sdisallowedrolebindingsubjects                        42s
k8sdisallowedtags                                       48s
k8sdisallowinteractivetty                               58s
k8senforcecloudarmorbackendconfig                       55s
k8sexternalips                                          46s
k8shttpsonly                                            50s
k8simagedigests                                         49s
k8slocalstoragerequiresafetoevict                       62s
k8smemoryrequestequalslimit                             51s
k8snoenvvarsecrets                                      53s
k8snoexternalservices                                   67s
k8spodresourcesbestpractices                            54s
k8spodsrequiresecuritycontext                           56s
k8sprohibitrolewildcardaccess                           58s
k8spspallowedusers                                      59s
k8spspallowprivilegeescalationcontainer                 65s
k8spspapparmor                                          60s
k8spspautomountserviceaccounttokenpod                    54s
k8spspcapabilities                                      54s
k8spspflexvolumes                                       49s
k8spspforbiddensysctls                                  65s
k8spspfsgroup                                           64s
k8spsphostfilesystem                                    55s
k8spsphostnamespace                                     44s
k8spsphostnetworkingports                               43s
k8spspprivilegedcontainer                               49s
k8spspprocmount                                         66s
k8spspreadonlyrootfilesystem                            64s
k8spspseccomp                                           61s
k8spspselinuxv2                                         50s
k8spspvolumetypes                                       59s
k8spspwindowshostprocess                                51s
k8spssrunasnonroot                                      59s
k8sreplicalimits                                        57s
k8srequirecosnodeimage                                  52s
k8srequiredannotations                                  44s
k8srequiredlabels                                       52s
k8srequiredprobes                                       48s
k8srequiredresources                                    47s
k8srequirevalidrangesfornetworks                        61s
k8srestrictadmissioncontroller                           56s
k8srestrictautomountserviceaccounttokens                 51s
k8srestrictlabels                                       57s
k8srestrictnamespaces                                   57s
k8srestrictnfsurls                                      58s
k8srestrictrbacsubjects                                 53s
k8srestrictrolebindings                                 64s
k8srestrictrolerules                                    63s
noupdateserviceaccount                                  47s
policystrictonly                                        47s
restrictnetworkexclusions                               62s
sourcenotallauthz                                       47s
verifydeprecatedapi                                     60s
```

**Description:** 70+ constraint templates are installed, including security policies (PSP), required labels, container limits, etc.

### 5.5 Check Specific Constraint Template Status

**Command:**
```bash
kubectl get constrainttemplate k8srequiredlabels -o jsonpath='{.status}'
```

**Output:**
```json
{"byPod":[{"id":"gatekeeper-audit-57b4b9bbf9-n69g7","observedGeneration":1,"operations":["audit","status"],"templateUID":"5644579c-bbd2-4ddb-a46d-7d3c15bef069"},{"id":"gatekeeper-controller-manager-79ff65dddb-rm2q6","observedGeneration":1,"operations":["webhook"],"templateUID":"5644579c-bbd2-4ddb-a46d-7d3c15bef069"}],"created":true}
```

**Description:** Confirms the constraint template is created and operational.

### 5.6 Check Active Constraints and Violations

**Command:**
```bash
kubectl get constraint --all-namespaces
```

**Output:**
```
NAME                                                                              ENFORCEMENT-ACTION  TOTAL-VIOLATIONS
k8snoenvvarsecrets.constraints.gatekeeper.sh/policy-essentials-v2022-no-secrets-as-env-vars  dryrun  0
k8spodsrequiresecuritycontext.constraints.gatekeeper.sh/policy-essentials-v2022-pods-require-security-context  dryrun  3
k8sprohibitrolewildcardaccess.constraints.gatekeeper.sh/policy-essentials-v2022-prohibit-role-wildcard-access  dryrun  2
k8spspallowedusers.constraints.gatekeeper.sh/policy-essentials-v2022-psp-pods-must-run-as-nonroot  dryrun  3
k8spspallowprivilegeescalationcontainer.constraints.gatekeeper.sh/policy-essentials-v2022-psp-allow-privilege-escalation  dryrun  3
k8spspcapabilities.constraints.gatekeeper.sh/policy-essentials-v2022-psp-capabilities  dryrun  3
k8spsphostnamespace.constraints.gatekeeper.sh/policy-essentials-v2022-psp-host-namespace  dryrun  0
```

**Description:** Shows active constraints from the `policy-essentials-v2022` bundle. All are in `dryrun` mode (will log violations but not block). Violations detected for missing security contexts, which is expected for basic deployments.

---

## Step 6: Create Test Resources

### 6.1 Create Demo Namespace

**Command:**
```bash
kubectl create namespace policy-controller-demo
```

**Output:**
```
namespace/policy-controller-demo created
```

**Description:** Creates a namespace for testing Policy Controller functionality.

### 6.2 Apply Demo Application YAML

**Command:**
```bash
kubectl apply -f demo-yaml/demo-app.yaml
```

**Output:**
```
configmap/nginx-config created
service/nginx-service created
deployment.apps/nginx-deployment created
```

**Description:** Deploys a simple nginx application with ConfigMap, Service, and Deployment.

### 6.3 Verify Demo Application

**Command:**
```bash
kubectl get configmap,service,deployment -n policy-controller-demo
```

**Output:**
```
NAME                              DATA  AGE
configmap/kube-root-ca.crt        1     2m52s
configmap/nginx-config            1     40s
NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP  PORT(S)  AGE
service/nginx-service ClusterIP  100.68.20.206   <none>       80/TCP   39s
NAME                             READY  UP-TO-DATE  AVAILABLE  AGE
deployment.apps/nginx-deployment 2/2    2           2          39s
```

**Description:** Confirms all demo resources are created and the deployment is healthy.

---

## Demo Application YAML

The demo application YAML file is saved at: `demo-yaml/demo-app.yaml`

**Contents:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
data:
  nginx.conf: |
    server {
      listen 80;
      server_name localhost;
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
    owner: platform-team
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
        environment: demo
        owner: platform-team
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "500m"
            memory: "128Mi"
          requests:
            cpu: "100m"
            memory: "64Mi"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## Available Policy Bundles

The following bundles are available for installation:

| Bundle | Description | Status |
|--------|-------------|--------|
| `policy-essentials-v2022` | Core security policies (installed) | Active |
| `pss-baseline-v2022` | Pod Security Standards Baseline | Available |
| `pss-restricted-v2022` | Pod Security Standards Restricted | Available |
| `cis-k8s-v1.5.1` | CIS Kubernetes Benchmark 1.5.1 | Available |
| `cis-k8s-v1.7` | CIS Kubernetes Benchmark 1.7 | Available |
| `nist-sp-800-190` | NIST SP 800-190 | Available |
| `pci-dss-v3.2.1` | PCI DSS 3.2.1 | Available |
| `pci-dss-v4.0` | PCI DSS 4.0 | Available |
| `cost-reliability-v2023` | Cost and Reliability Best Practices | Available |
| `asm-policy-v0.0.1` | ASM Policy | Available |

---

## Troubleshooting

### Check Controller Logs

```bash
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=100
```

### Check Events

```bash
kubectl get events -n gatekeeper-system --sort-by='.lastTimestamp'
```

### Check Webhook Configuration

```bash
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration
```

### View Constraint Violations

```bash
kubectl get constraint --all-namespaces -o yaml > constraint-violations.yaml
```

---

## Cleanup

### Remove Demo Resources

```bash
kubectl delete -f demo-yaml/demo-app.yaml
kubectl delete namespace policy-controller-demo
```

### Uninstall Policy Controller

```bash
gcloud container fleet policycontroller disable --memberships=aibang-master
```

### Remove Fleet Membership

```bash
gcloud container hub memberships delete aibang-master
```

---

## References

- [GKE Policy Controller Overview](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/overview)
- [Using Policy Bundles](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/concepts/policy-controller-bundles)
- [Creating Constraints](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/creating-policy-controller-constraints)
- [Troubleshooting](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/troubleshoot-policy-controller)