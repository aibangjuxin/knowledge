- [Horizontal Pod Autoscaler (HPA) Explained - Corrected and Enhanced Version](#horizontal-pod-autoscaler-hpa-explained---corrected-and-enhanced-version)
  - [1. Core Formula](#1-core-formula)
  - [2. Important Note: About Tolerance](#2-important-note-about-tolerance)
  - [3. HPA Configuration Example](#3-hpa-configuration-example)
  - [4. CPU Scale-Out and Scale-In Trigger Condition Analysis](#4-cpu-scale-out-and-scale-in-trigger-condition-analysis)
    - [4.1. Scale from 1 to 2 Replicas](#41-scale-from-1-to-2-replicas)
    - [4.2. Scale from 2 to 3 Replicas](#42-scale-from-2-to-3-replicas)
    - [4.3. Scale from 3 to 4 Replicas](#43-scale-from-3-to-4-replicas)
    - [4.4. Scale from 4 to 3 Replicas](#44-scale-from-4-to-3-replicas)
    - [4.5. Scale from 3 to 2 Replicas](#45-scale-from-3-to-2-replicas)
    - [4.7. Scale from 2 to 1 Replica](#47-scale-from-2-to-1-replica)
  - [5. Memory Scale-Out and Scale-In Trigger Condition Analysis](#5-memory-scale-out-and-scale-in-trigger-condition-analysis)
    - [5.1. Scale from 1 to 2 Replicas](#51-scale-from-1-to-2-replicas)
    - [5.2. Scale from 2 to 3 Replicas](#52-scale-from-2-to-3-replicas)
    - [5.3. Scale from 3 to 4 Replicas](#53-scale-from-3-to-4-replicas)
    - [5.4. Scale from 4 to 3 Replicas](#54-scale-from-4-to-3-replicas)
    - [5.5. Scale from 3 to 2 Replicas](#55-scale-from-3-to-2-replicas)
    - [5.7. Scale from 2 to 1 Replica](#57-scale-from-2-to-1-replica)
  - [6. Multi-Metric HPA Behavior](#6-multi-metric-hpa-behavior)
  - [7. Other Key Factors Affecting HPA Behavior](#7-other-key-factors-affecting-hpa-behavior)
  - [8. Supplementary Example: Target Utilization at 90%](#8-supplementary-example-target-utilization-at-90)
    - [8.1. Scale from 3 to 4 Replicas](#81-scale-from-3-to-4-replicas)
    - [8.2. Scale from 4 to 3 Replicas](#82-scale-from-4-to-3-replicas)
    - [8.3. Notes](#83-notes)
  - [9. Key Takeaways](#9-key-takeaways)

# Horizontal Pod Autoscaler (HPA) Explained - Corrected and Enhanced Version

## 1. Core Formula

The core algorithm formula for HPA is:

$$
\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil
$$

Where $\lceil \rceil$ represents the ceiling function (round up). This formula is the foundation for understanding HPA behavior.

## 2. Important Note: About Tolerance

A common misconception is that HPA has a built-in "10% buffer zone," meaning it only triggers scaling when metrics exceed the target by 10%. This understanding is not entirely accurate.

- **HPA continuously calculates**: As long as the current metric value is not exactly equal to the target value, the HPA controller will **continuously** calculate based on the above formula.
- **Execution Tolerance**: To prevent excessive scaling due to minor metric fluctuations (i.e., "flapping"), HPA introduces a configurable **execution tolerance** (default 10%).

**Working Mechanism**: After calculating `desiredReplicas`, HPA checks the ratio between the current metric and the target value. If the ratio is very close to `1.0` (within the tolerance range), the controller may **skip this scaling operation**.

**Formula**:
$$
\left| 1.0 - \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right| \le \text{tolerance}
$$
Only when metric fluctuations exceed this tolerance range will HPA actually execute scale-out or scale-in actions. This ensures system stability and avoids unnecessary resource adjustments.

## 3. HPA Configuration Example

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: aibang-deployment-hpa
  namespace: aibang
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: aibang-deployment
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 750
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## 4. CPU Scale-Out and Scale-In Trigger Condition Analysis

**Target CPU Utilization: 750%**

### 4.1. Scale from 1 to 2 Replicas

- **Trigger Condition**: CPU utilization > 750%
- **Verification**: When CPU utilization is 751%:
  $$
  \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{751}{750} \right) \right\rceil = \left\lceil 1.001 \right\rceil = 2
  $$
- **Conclusion**: Any CPU utilization exceeding 750% will trigger scaling from 1 to 2 replicas.

### 4.2. Scale from 2 to 3 Replicas

- **Trigger Condition**: CPU utilization > 750%
- **Verification**: When CPU utilization is 751%:
  $$
  \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{751}{750} \right) \right\rceil = \left\lceil 2.003 \right\rceil = 3
  $$
- **Conclusion**: Any CPU utilization exceeding 750% will trigger scaling from 2 to 3 replicas.

### 4.3. Scale from 3 to 4 Replicas

- **Trigger Condition**: CPU utilization ≥ 1000%
- **Derivation**:
  $
  \left\lceil 3 \times \left( \frac{x}{750} \right) \right\rceil \ge 4 \implies 3 \times \left( \frac{x}{750} \right) \ge 4 \implies x \ge 1000
  $
- **Verification**:
  - When CPU utilization is 1000%: `ceil(3 * (1000/750)) = ceil(4) = 4`
  - When CPU utilization is 999%: `ceil(3 * (999/750)) = ceil(3.996) = 4`
- **Conclusion**: When CPU utilization ≥ 1000%, it will scale from 3 to 4 replicas.

### 4.4. Scale from 4 to 3 Replicas

- **Trigger Condition**: CPU utilization ≤ 562.5%
- **Derivation**:
  $
  \left\lceil 4 \times \left( \frac{x}{750} \right) \right\rceil \le 3 \implies 4 \times \left( \frac{x}{750} \right) \le 3 \implies x \le 562.5
  $
- **Verification**:
  - When CPU utilization is 562.5%: `ceil(4 * (562.5/750)) = ceil(3) = 3`
  - When CPU utilization is 563%: `ceil(4 * (563/750)) = ceil(3.003) = 4`
- **Conclusion**: When CPU utilization ≤ 562.5%, it will scale from 4 to 3 replicas.

### 4.5. Scale from 3 to 2 Replicas

- **Trigger Condition**: CPU utilization ≤ 500%
- **Derivation**:
  $$
  \left\lceil 3 \times \left( \frac{x}{750} \right) \right\rceil \le 2 \implies 3 \times \left( \frac{x}{750} \right) \le 2 \implies x \le 500
  $$
- **Verification**:
  - When CPU utilization is 500%: `ceil(3 * (500/750)) = ceil(2) = 2`
  - When CPU utilization is 501%: `ceil(3 * (501/750)) = ceil(2.004) = 3`
- **Conclusion**: When CPU utilization ≤ 500%, it will scale from 3 to 2 replicas.

### 4.7. Scale from 2 to 1 Replica

- **Trigger Condition**: CPU utilization ≤ 375%
- **Derivation**:
  $$
  \left\lceil 2 \times \left( \frac{x}{750} \right) \right\rceil \le 1 \implies 2 \times \left( \frac{x}{750} \right) \le 1 \implies x \le 375
  $$
- **Conclusion**: When CPU utilization ≤ 375%, it will scale from 2 to 1 replica.

## 5. Memory Scale-Out and Scale-In Trigger Condition Analysis

**Target Memory Utilization: 80%**

### 5.1. Scale from 1 to 2 Replicas

- **Trigger Condition**: Memory utilization > 80%
- **Verification**: When memory utilization is 81%:
  $$
  \text{desiredReplicas} = \left\lceil 1 \times \left( \frac{81}{80} \right) \right\rceil = \left\lceil 1.0125 \right\rceil = 2
  $$
- **Conclusion**: Any memory utilization exceeding 80% will trigger scaling from 1 to 2 replicas.

### 5.2. Scale from 2 to 3 Replicas

- **Trigger Condition**: Memory utilization > 80%
- **Verification**: When memory utilization is 81%:
  $$
  \text{desiredReplicas} = \left\lceil 2 \times \left( \frac{81}{80} \right) \right\rceil = \left\lceil 2.025 \right\rceil = 3
  $$
- **Conclusion**: Any memory utilization exceeding 80% will trigger scaling from 2 to 3 replicas.

### 5.3. Scale from 3 to 4 Replicas

- **Trigger Condition**: Memory utilization ≥ 107%
- **Derivation**:
  $
  \left\lceil 3 \times \left( \frac{x}{80} \right) \right\rceil \ge 4 \implies 3 \times \left( \frac{x}{80} \right) \ge 4 \implies x \ge 106.67
  $
- **Verification**:
  - When memory utilization is 107%: `ceil(3 * (107/80)) = ceil(4.0125) = 5`
  - When memory utilization is 106.67%: `ceil(3 * (106.67/80)) = ceil(4.00) = 4`
- **Conclusion**: When memory utilization ≥ 107%, it will scale from 3 to 4 replicas.

### 5.4. Scale from 4 to 3 Replicas

- **Trigger Condition**: Memory utilization ≤ 60%
- **Derivation**:
  $
  \left\lceil 4 \times \left( \frac{x}{80} \right) \right\rceil \le 3 \implies 4 \times \left( \frac{x}{80} \right) \le 3 \implies x \le 60
  $
- **Verification**:
  - When memory utilization is 60%: `ceil(4 * (60/80)) = ceil(3) = 3`
  - When memory utilization is 61%: `ceil(4 * (61/80)) = ceil(3.05) = 4`
- **Conclusion**: When memory utilization ≤ 60%, it will scale from 4 to 3 replicas.

### 5.5. Scale from 3 to 2 Replicas

- **Trigger Condition**: Memory utilization ≤ 53%
- **Derivation**:
  $$
  \left\lceil 3 \times \left( \frac{x}{80} \right) \right\rceil \le 2 \implies 3 \times \left( \frac{x}{80} \right) \le 2 \implies x \le 53.33
  $$
- **Conclusion**: When memory utilization ≤ 53%, it will scale from 3 to 2 replicas.

### 5.7. Scale from 2 to 1 Replica

- **Trigger Condition**: Memory utilization ≤ 40%
- **Derivation**:
  $$
  \left\lceil 2 \times \left( \frac{x}{80} \right) \right\rceil \le 1 \implies 2 \times \left( \frac{x}{80} \right) \le 1 \implies x \le 40
  $$
- **Conclusion**: When memory utilization ≤ 40%, it will scale from 2 to 1 replica.

## 6. Multi-Metric HPA Behavior

When HPA is configured with multiple metrics, its decision logic is very clear:

1.  **Calculate Separately**: HPA independently calculates the desired number of replicas for each metric.
2.  **Select Maximum Value**: The final scaling decision will be based on the **maximum value** among all calculation results.

**Example**:
- Desired replicas calculated from CPU usage: `1`
- Desired replicas calculated from memory usage: `2`
- Final HPA decision for replicas: `max(1, 2) = 2`

This mechanism ensures that the system can handle resource pressure in any dimension, preventing service instability caused by any single metric exceeding its threshold.

## 7. Other Key Factors Affecting HPA Behavior

In addition to the core algorithm, the following factors have significant impact on HPA behavior in production environments:

1.  **Stabilization Window / Cooldown**:
    - HPA allows configuring independent cooldown times for scale-out and scale-in to prevent frequent scaling due to short-term load fluctuations.
    - **Scale-Down Cooldown (`scaleDown`)**: Before deciding to scale in, HPA reviews a period of time (default 5 minutes) and selects the **peak value** during that period to calculate desired replicas. This prevents immediate scale-in due to temporary traffic drops, avoiding being caught off guard during the next traffic spike.
    - **Scale-Up Cooldown (`scaleUp`)**: The cooldown time for scale-out is typically shorter (default 3 minutes) to ensure quick response to load increases.

2.  **Pod Readiness**:
    - When calculating average utilization, HPA **only considers Pods in `Ready` state**. Metrics from Pods that are starting up or have not passed readiness probes are not included. This prevents unnecessary scale-out triggered by CPU or memory spikes during application startup.

3.  **Missing Metrics**:
    - If metrics for some Pods cannot be obtained from the Metrics Server, HPA ignores these Pods when calculating averages. In extreme cases, if all Pod metrics are missing, HPA will not perform any scaling operations to ensure safety.

## 8. Supplementary Example: Target Utilization at 90%

To better understand HPA's scaling mechanism, here's a complete example with a target utilization of 90%.

**Target Utilization: 90%**

### 8.1. Scale from 3 to 4 Replicas

- **Trigger Condition**: Utilization ≥ 120%
- **Derivation**:
  $
  \left\lceil 3 \times \left( \frac{x}{90} \right) \right\rceil \ge 4 \implies 3 \times \left( \frac{x}{90} \right) \ge 4 \implies x \ge 120
  $
- **Verification**:
  - When utilization is 120%: `ceil(3 * (120/90)) = ceil(4) = 4`
  - When utilization is 119%: `ceil(3 * (119/90)) = ceil(3.967) = 4`
- **Conclusion**: When utilization ≥ 120%, it will scale from 3 to 4 replicas.

### 8.2. Scale from 4 to 3 Replicas

- **Trigger Condition**: Utilization ≤ 67.5%
- **Derivation**:
  $
  \left\lceil 4 \times \left( \frac{x}{90} \right) \right\rceil \le 3 \implies 4 \times \left( \frac{x}{90} \right) \le 3 \implies x \le 67.5
  $
- **Verification**:
  - When utilization is 67.5%: `ceil(4 * (67.5/90)) = ceil(3) = 3`
  - When utilization is 68%: `ceil(4 * (68/90)) = ceil(3.022) = 4`
- **Conclusion**: When utilization ≤ 67.5%, it will scale from 4 to 3 replicas.

### 8.3. Notes

- HPA controller repeatedly calculates based on its **sync-period (default 15 seconds)**
- It's recommended to use `kubectl describe hpa` to view real-time calculation details
- If cluster load fluctuates rapidly, consider increasing `stabilizationWindow` to reduce flapping

## 9. Key Takeaways

1.  **No Built-in Buffer**: HPA directly calculates based on the comparison between current and target values, but has **execution tolerance** to avoid flapping.
2.  **Round Up**: Calculation results are always rounded up to ensure sufficient resources.
3.  **Multi-Metric Maximum**: Ensures the system can handle pressure in any dimension.
4.  **Cooldown Time**: Prevents excessive scaling through stabilization windows.
5.  **Pod Readiness**: Only counts healthy Pods for more accurate decisions.
6.  **Boundary Limits**: Calculation results are always constrained by `minReplicas` and `maxReplicas`.
