# Horizontal Pod Autoscaler (HPA) Detailed Explanation - Revised and Enhanced Version

This article revises the HPA scaling algorithm, focusing on correcting the influence of **tolerance** on actual calculations.

## 1. Core Formula and Logic

HPA's scaling decision is driven by the following formula:

$$
\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil
$$

Where:
- `desiredReplicas`: Calculated target replica count
- `currentReplicas`: Current replica count
- `currentMetricValue`: Current metric value (such as CPU or memory utilization)
- `desiredMetricValue`: Target metric value (such as configured CPU or memory target values)
- `⌈x⌉`: Ceiling function

However, **before applying the formula, tolerance checks must be passed**.

### 1.1 Tolerance Mechanism

The default tolerance is **0.1 (10%)**.

- **Scale-up condition**: `Current / Desired > 1.1` (i.e., metric exceeds target value by more than 10%)
- **Scale-down condition**: `Current / Desired < 0.9` (i.e., metric falls below target value by more than 10%)
- **Silent range**: `0.9 <= Ratio <= 1.1` (at this point HPA **takes no action**)

Only after satisfying the tolerance conditions will HPA use the `ceil` formula to calculate specific replica count changes.

### 1.2 Scaling Delay Mechanism

HPA also has a delay mechanism to prevent frequent scaling:
- **Scale-up delay**: Default is 3 minutes (to avoid over-scaling due to temporary load spikes)
- **Scale-down delay**: Default is 5 minutes (to avoid over-scaling down due to temporary load drops)
---

## 2. HPA Configuration Example

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: aibang-deployment-hpa
spec:
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 750   # Target 750%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80    # Target 80%
```

---

## 3. CPU Scale-up and Scale-down Conditions (Revised Version)

**Target CPU Utilization: 750%**
**Tolerance: 10% (0.1)**

### 3.1. Scale-up Trigger Threshold (General)

Due to 10% tolerance, scaling will only be triggered when CPU utilization exceeds `750% * 1.1 = 825%`.
**Between 750% ~ 825%, although targets are not met, it falls within the tolerance range, so HPA will not scale up.**

### 3.2. Scaling from 1 Replica to 2 Replicas

- **Trigger threshold**: CPU > **825%**
- **Calculation logic** (assuming CPU is 826%):
    1.  **Ratio**: $826 / 750 \approx 1.101$
    2.  **Tolerance check**: $1.101 > 1.1$ (exceeds 10% tolerance, **trigger scale-up**)
    3.  **Desired replicas**:

$$
\text{desiredReplicas} = \left\lceil 1 \times \left( \frac{826}{750} \right) \right\rceil = \left\lceil 1.101 \right\rceil = 2
$$

- **Comparison with incorrect understanding**: If CPU is 760%, although greater than 750%, the deviation is only 1.3%, so HPA will ignore it.

### 3.3. **[Key Point] Scaling from 2 Replicas to 3 Replicas**

- **Trigger threshold**: CPU > **825%**
- **Calculation logic** (assuming CPU is 826%):
    1.  **Ratio**: $1.101$
    2.  **Tolerance check**: Passed
    3.  **Desired replicas**:

$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{826}{750} \right) \right\rceil = \left\lceil 2.202 \right\rceil = 3
$$

- **Conclusion**: It's not just exceeding 750% that triggers scaling; it must exceed 825% to scale from 2 to 3.

### 3.4. Scaling from 3 Replicas to 4 Replicas

- **Trigger threshold**: CPU > **825%**
- **Calculation logic** (assuming CPU is 826%):
    1.  **Desired replicas**:

$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{826}{750} \right) \right\rceil = \left\lceil 3.303 \right\rceil = 4
$$

> **Scale-up Summary**: For Scale Up, due to the characteristics of the `ceil` function (slightly greater than an integer causes rounding up), **tolerance** is usually the key bottleneck. Once the 1.1x threshold is broken, at least 1 replica is typically scaled up.

### 3.5. Scale-down Condition Analysis (Dominant by Ceil Function)

Scale-down must satisfy not only Tolerance (<0.9), but also `ceil(Current * Ratio) < Current`. For small replica counts, the effect of `ceil` is stronger than Tolerance.

#### Scaling from 4 Replicas to 3 Replicas
- **Formula constraint**: $\lceil 4 \times R \rceil \le 3 \implies 4R \le 3 \implies R \le 0.75$
- **Tolerance constraint**: $R < 0.9$
- **Final threshold**: $R \le 0.75$ i.e., CPU $\le 750\% \times 0.75 = \mathbf{562.5\%}$

**Calculation example (CPU 562%)**:
$$
\text{desiredReplicas} = \left\lceil 4 \times \left( \frac{562}{750} \right) \right\rceil = \left\lceil 2.997 \right\rceil = 3
$$

#### Scaling from 3 Replicas to 2 Replicas
- **Formula constraint**: $\lceil 3 \times R \rceil \le 2 \implies 3R \le 2 \implies R \le 0.666$
- **Final threshold**: CPU $\le 750\% \times 0.666 = \mathbf{500\%}$

**Calculation example (CPU 500%)**:
$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{500}{750} \right) \right\rceil = \left\lceil 2 \right\rceil = 2
$$

#### Scaling from 2 Replicas to 1 Replica
- **Formula constraint**: $\lceil 2 \times R \rceil \le 1 \implies 2R \le 1 \implies R \le 0.5$
- **Final threshold**: CPU $\le 750\% \times 0.5 = \mathbf{375\%}$

**Calculation example (CPU 375%)**:
$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{375}{750} \right) \right\rceil = \left\lceil 1 \right\rceil = 1
$$

---

## 4. Memory Scale-up and Scale-down Conditions

**Target Memory Utilization: 80%**
**Tolerance: 10% (0.1)**

**General Scale-up Threshold**: $80\% \times 1.1 = \mathbf{88\%}$

$$
\text{desiredReplicas} = \left\lceil 1 \times \left( \frac{88}{80} \right) \right\rceil = \left\lceil 1.1 \right\rceil = 2
$$

### 4.1. From 1 to 2, From 2 to 3

- **Trigger condition**: Memory > **88%** (81% won't trigger!)
- **Your case (81%/80%)**:
    - Ratio 1.0125. Deviation 1.25% < 10%. **No scale-up**.
- **Verification (utilization 89%)**:
- Ratio $89/80 = 1.1125$. Deviation 11.25% > 10%. **Scale-up**.

$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{89}{80} \right) \right\rceil = \left\lceil 2.225 \right\rceil = 3
$$

### 4.2. From 3 to 4

- **Trigger condition** Memory utilization > **88%**

**Calculation example (Memory 89%)**:
$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{89}{80} \right) \right\rceil = \left\lceil 3.225 \right\rceil = 4
$$


### 4.3. Scale-down Conditions

#### From 4 -> 3
- Constraint: $R \le 0.75$
- Threshold: $80\% \times 0.75 = \mathbf{60\%}$

**Calculation example (Memory 60%)**:
$$
\text{desiredReplicas} = \left\lceil 4 \times \left( \frac{60}{80} \right) \right\rceil = \left\lceil 3 \right\rceil = 3
$$

#### From 3 -> 2
- Constraint: $R \le 0.666$
- Threshold: $80\% \times 0.666 = \mathbf{53.3\%}$

**Calculation example (Memory 53%)**:
$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{53}{80} \right) \right\rceil = \left\lceil 1.9875 \right\rceil = 2
$$

#### From 2 -> 1
- Constraint: $R \le 0.5$
- Threshold: $80\% \times 0.5 = \mathbf{40\%}$

**Calculation example (Memory 40%)**:
$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{40}{80} \right) \right\rceil = \left\lceil 1 \right\rceil = 1
$$

---

## 5. Supplementary Scenario: Target Memory Utilization 90% Detailed Explanation (Complete Coverage 1-4 Replicas)

**Scenario Setting**:
- **Target Memory Utilization**: 90%
- **Tolerance**: 10% (0.1)

### 5.1. Scale-up Conditions (1->2, 2->3, 3->4)

**General Trigger Core**: Due to tolerance existence, the metric must exceed `target value * 1.1`.
$$ \text{Trigger threshold} > 90\% \times 1.1 = \mathbf{99\%} $$

#### 1) Scaling from 1 Replica to 2 Replicas
- **Scenario**: Memory utilization reaches **100%**
- **Calculation logic**:
$$
\text{desiredReplicas} = \left\lceil 1 \times \left( \frac{100}{90} \right) \right\rceil = \left\lceil 1.111 \right\rceil = 2
$$

#### 2) Scaling from 2 Replicas to 3 Replicas
- **Scenario**: Memory utilization reaches **100%**
- **Calculation logic**:
$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{100}{90} \right) \right\rceil = \left\lceil 2.222 \right\rceil = 3
$$

#### 3) Scaling from 3 Replicas to 4 Replicas (Previous example)
- **Scenario**: Memory utilization reaches **100%**
- **Calculation logic**:
$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{100}{90} \right) \right\rceil = \left\lceil 3.333 \right\rceil = 4
$$

### 5.2. Scale-down Conditions (4->3, 3->2, 2->1)

#### 1) Scaling from 4 Replicas to 3 Replicas
- **Constraint**: $R \le 0.75$
- **Threshold**: $90\% \times 0.75 = \mathbf{67.5\%}$

**Calculation example (Memory 67%)**:
$$
\text{desiredReplicas} = \left\lceil 4 \times \left( \frac{67}{90} \right) \right\rceil = \left\lceil 2.977 \right\rceil = 3
$$

#### 2) Scaling from 3 Replicas to 2 Replicas
- **Constraint**: $R \le 0.666$
- **Threshold**: $90\% \times 0.666 = \mathbf{60\%}$

**Calculation example (Memory 60%)**:
$$
\text{desiredReplicas} = \left\lceil 3 \times \left( \frac{60}{90} \right) \right\rceil = \left\lceil 2 \right\rceil = 2
$$

#### 3) Scaling from 2 Replicas to 1 Replica
- **Constraint**: $R \le 0.5$
- **Threshold**: $90\% \times 0.5 = \mathbf{45\%}$

**Calculation example (Memory 45%)**:
$$
\text{desiredReplicas} = \left\lceil 2 \times \left( \frac{45}{90} \right) \right\rceil = \left\lceil 1 \right\rceil = 1
$$

---

## 6. Multi-metric HPA Behavior

When multiple metrics are configured (such as CPU and memory), HPA will select the metric that calculates the largest replica count as the final decision:

$$
\text{finalDesiredReplicas} = \max(\text{calculatedReplicas}_{\text{metric1}}, \text{calculatedReplicas}_{\text{metric2}}, \ldots)
$$

For example, if CPU calculates 3 replicas are needed, and memory calculates 5 replicas are needed, the final result will scale to 5 replicas.

---

## 7. Practical Deployment Considerations

### 7.1 Resource Requests and Limits
Ensure appropriate resource requests and limits are set for Pods, otherwise HPA cannot function properly:

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi
```

### 7.2 Monitoring and Debugging
You can use the following commands to view HPA status:

```bash
kubectl describe hpa <hpa-name>
kubectl get hpa <hpa-name> -o yaml
```

### 7.3 Common Issue Troubleshooting
1. **HPA doesn't respond**: Check if Pods have resource requests set
2. **Frequent scaling**: Adjust tolerance or increase stability window time
3. **Metrics unavailable**: Confirm Metrics Server or other monitoring components are running normally


## 8. Summary Comparison Table

| Replica Change | Key Constraint Factor | Target 750% (CPU) Trigger Value | Target 80% (Memory) Trigger Value | Target 90% (Memory) Trigger Value |
| :--- | :--- | :--- | :--- | :--- |
| **Scale-up (+1)** | **Tolerance (Ratio > 1.1)** | **> 825%** | **> 88%** | **> 99%** |
| **Scale-down (4->3)** | Ceil (Ratio $\le$ 0.75) | $\le$ 562.5% | $\le$ 60% | $\le$ 67.5% |
| **Scale-down (3->2)** | Ceil (Ratio $\le$ 0.66) | $\le$ 500% | $\le$ 53.3% | $\le$ 60% |
| **Scale-down (2->1)** | Ceil (Ratio $\le$ 0.50) | $\le$ 375% | $\le$ 40% | $\le$ 45% |

## 9. Core Correction Points Summary
1.  **Scale-up doesn't trigger immediately after crossing the line**: Must cross the 10% safety line (1.1x target value).
2.  **Scaling down small replica counts is harder**: Scaling from 2 to 1 requires metrics to drop below half of the target (Ratio 0.5), not just below 0.9. This is determined by the mathematical characteristic of the `ceil` rounding up function (for system high availability, scale-down is always very conservative).
3.  **81% memory doesn't scale up**: This is within the tolerance range and is expected behavior.
4.  **Resource utilization target values should be 0-100**: The previous 750% should be 75%.
5.  **Multi-metric scenario**: HPA will select the metric with the largest calculated result as the scaling basis.