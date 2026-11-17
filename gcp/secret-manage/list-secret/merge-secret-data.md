```json
# jq script to merge secret info and IAM policy
.[0] as $info | 
.[1] as $iam | 
{
    secretName: ($info.name | split("/") | .[-1]),
    fullName: $info.name,
    createTime: $info.createTime,
    bindings: [
        $iam.bindings[]? | {
            role: .role,
            members: [
                .members[] | {
                    type: (
                        if startswith("group:") then "Group"
                        elif startswith("serviceAccount:") then "ServiceAccount"
                        elif startswith("user:") then "User"
                        elif startswith("domain:") then "Domain"
                        else "Other"
                        end
                    ),
                    id: (
                        if startswith("group:") then .[6:]
                        elif startswith("serviceAccount:") then .[15:]
                        elif startswith("user:") then .[5:]
                        elif startswith("domain:") then .[7:]
                        else .
                        end
                    ),
                    fullMember: .
                }
            ]
        }
    ],
    summary: {
        groups: ([$iam.bindings[]?.members[]? | select(startswith("group:"))] | length),
        serviceAccounts: ([$iam.bindings[]?.members[]? | select(startswith("serviceAccount:"))] | length),
        users: ([$iam.bindings[]?.members[]? | select(startswith("user:"))] | length),
        others: ([$iam.bindings[]?.members[]? | select(startswith("domain:") or (startswith("group:") or startswith("serviceAccount:") or startswith("user:")) | not)] | length)
    }
}
```