Below is a **Docker-focused, copy-paste-ready** explanation showing how to **add annotations (labels)** and **retrieve them via commands**.

> In Docker terminology, there is **no native “annotation” object** like Kubernetes.

> Docker uses **labels** (--label, LABEL) for the same purpose.

---

## **1. Problem Analysis**

- Docker **annotations = labels**
- Labels are **key/value metadata**
- They can be:
    - Added at **build time** (Dockerfile)
    - Added at **run time** (docker run)
- Retrieved via:
    - docker inspect
    - docker ps --format

---

## **2. Add Labels (Annotations)**

### **2.1 Add label in Dockerfile (Build-time)**

```
FROM nginx:alpine

LABEL maintainer="platform-team"
LABEL app="api-gateway"
LABEL version="v1.0.0"
```

Build image:

```
docker build -t my-nginx:1.0 .
```

---

### **2.2 Add label when running container (Run-time)**

```
docker run -d \
  --name my-nginx \
  --label env=prod \
  --label team=platform \
  nginx:alpine
```

---

### **2.3 Add multiple labels (recommended format)**

```
docker run -d \
  --label app=order-service \
  --label owner=gke-platform \
  --label cost-center=cc123 \
  nginx:alpine
```

---

## **3. Get Labels (Annotations)**

### **3.1 Get labels of a container (inspect)**

```
docker inspect my-nginx \
  --format='{{json .Config.Labels}}'
```

Example output:

```
{
  "env": "prod",
  "team": "platform"
}
```

---

### **3.2 Get labels of an image**

```
docker inspect my-nginx:1.0 \
  --format='{{json .Config.Labels}}'
```

---

### **3.3 Get a single label value**

```
docker inspect my-nginx \
  --format='{{ index .Config.Labels "env" }}'
```

Output:

```
prod
```

---

### **3.4 List containers with labels (table output)**

```
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Labels}}"
```

Example:

```
NAMES      IMAGE           LABELS
my-nginx   nginx:alpine    env=prod,team=platform
```

---

## **4. Filter Containers by Label**

```
docker ps --filter "label=env=prod"
```

Filter by key only:

```
docker ps --filter "label=team"
```

---

## **5. Best Practices**

| **Practice**                   | **Reason**                   |
| ------------------------------ | ---------------------------- |
| Use labels instead of env vars | Metadata, not runtime config |
| Namespace labels               | Avoid collisions             |
| Keep labels immutable          | Easier audit & tracking      |

### **Recommended naming style**

```
com.company.team=platform
com.company.env=prod
com.company.app=api-gateway
```

---

## **6. Docker Labels vs Kubernetes Annotations**

| **Platform**   | **Metadata Type**    |
| -------------- | -------------------- |
| Docker         | Labels               |
| Kubernetes     | Labels + Annotations |
| OCI Image Spec | Labels               |

---

## **7. Summary**

```
Docker annotation = Docker label
Add    → --label / LABEL
Read   → docker inspect
Filter → docker ps --filter label=
```

If you want, I can also:

- Map **Docker labels → Kubernetes annotations**
- Show how **Kong / GKE** propagates labels
- Generate **CI-friendly label standards**

Just tell me.
