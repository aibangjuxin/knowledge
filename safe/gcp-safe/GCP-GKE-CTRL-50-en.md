| **GCP-GKE-CTRL-50** | IDAM-3 - Access Rules and Role Management | RBAC policies must not use wildcards. | CAEP team | Yes | Yes | Enforced through static checks in CI/CD pipelines and Gatekeeper policies. |

### **Verification Method: How to Check for Wildcards in RBAC Policies**

To ensure that RBAC policies do not use wildcards (`*`), which is an important security practice to prevent over-permissioning, you can use `kubectl` commands combined with the `jq` tool to audit the `rules` field in `ClusterRole` and `Role` definitions.

**Prerequisites:**
*   `kubectl` is installed and configured to connect to your GKE cluster.
*   The `jq` tool is installed for parsing JSON output.

**Step 1: Check for Wildcards in ClusterRoles**

Run the following command to find `ClusterRole`s that use wildcards in the `apiGroups`, `resources`, or `verbs` fields.

```bash
kubectl get clusterroles -o json | \
jq '.items[] | select(.rules[] | select( (.apiGroups[]? | select(. == "*")) or (.resources[]? | select(. == "*")) or (.verbs[]? | select(. == "*")) )) | .metadata.name'
```

*   **Command Explanation**:
    *   `kubectl get clusterroles -o json`: Retrieves the definitions of all `ClusterRole`s in JSON format.
    *   `jq '.items[] | ...'`: Iterates through each `ClusterRole`.
    *   `select(.rules[] | select( ... ))`: Filters for `ClusterRole`s that contain wildcards in any of their `rules`.
    *   `(.apiGroups[]? | select(. == "*"))`: Checks if the `apiGroups` array contains a `*`. The `?` makes the field optional.
    *   `(.resources[]? | select(. == "*"))`: Checks if the `resources` array contains a `*`.
    *   `(.verbs[]? | select(. == "*"))`: Checks if the `verbs` array contains a `*`.
    *   `.metadata.name`: Outputs the name of the found `ClusterRole`.

**Expected Compliant Output:**

If your RBAC policies are compliant, this command should return an **empty result**. Any outputted `ClusterRole` name indicates non-compliant use of wildcards.

**Step 2: Check for Wildcards in Roles**

Run the following command to find `Role`s in any namespace that use wildcards in the `apiGroups`, `resources`, or `verbs` fields.

```bash
kubectl get roles --all-namespaces -o json | \
jq '.items[] | select(.rules[] | select( (.apiGroups[]? | select(. == "*")) or (.resources[]? | select(. == "*")) or (.verbs[]? | select(. == "*")) )) | .metadata.namespace + "/" + .metadata.name'
```

*   **Command Explanation**:
    *   `kubectl get roles --all-namespaces -o json`: Retrieves the definitions of all `Role`s in all namespaces in JSON format.
    *   The rest of the `jq` explanation is similar to the `ClusterRole` command, but it will also output the namespace of the `Role`.

**Expected Compliant Output:**

If your RBAC policies are compliant, this command should also return an **empty result**. Any outputted `Role` name and namespace indicates non-compliant use of wildcards.

---

By executing the two commands above and confirming that they return an empty result, you can provide evidence that your GKE cluster's RBAC policies do not use wildcards, thus satisfying the compliance requirements of `GCP-GKE-CTRL-50`.
