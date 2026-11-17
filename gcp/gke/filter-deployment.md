filter-deployment 
# reference
https://github.com/aibangjuxin/groovy/issues/35

要获取 kubectl get deployment 命令输出中 containers 下 env 中 apiName 的值，你可以使用 kubectl 命令结合 jq 工具来提取。假设 kubectl get deployment 命令输出的 JSON 部分为 deployment.json，可以使用以下命令：
`kubectl get deployment <deployment_name> -o=json | jq '.spec.template.spec.containers[0].env[] | select(.name=="apiName") | .value'`
其中 <deployment_name> 是你要查询的部署名称。这个命令会输出 apiName 的值。

# filter images 
- running images
- `kubectl get pods -A -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n' | sort | uniq `
- filter ns deployment images
  - https://alm-aibang.os.aaaaa.aibang/sp-api-platform/aib-infra-gcp/blob/APICLOUD-8951/7.gke-scripts/02.gke-ns-scripts/no-sms-deploy-images-replaces-byns.sh
  - `kubectl -n aib-core get deploy -o json| jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)'`
  - `kubectl -n aib-core get deploy -o json|jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | select(has("spec") and (.spec.template.spec.initContainers | length > 0)) | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)'`
  - `kubectl -n aib-core get deploy -o json| jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)'`
  - all namespace containers
    - `kubectl get deploy -A -o json| jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)'`
    - `kubectl get deploy -A -o json|jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | select(has("spec") and (.spec.template.spec.initContainers | length > 0)) | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)'`

# filte namespace containers Or inintcontainer
- `kubectl -n aib-core get deploy -o json|jq -r '.items[]| .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)'`
- `kubectl -n kuaiyong get deploy -o json|jq -r '.items[]| select(has("spec") and (.spec.template.spec.initContainers | length > 0)) | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)'`


# filter cronjob
- `kubectl -n $ns get cronjob -o json|jq -r '.items[] | "\(.metadata.name) \(.spec.jobTemplate.spec.template.spec.containers[].name) \(.spec.jobTemplate.spec.template.spec.containers[].image)"'`
- `kubectl -n aib-core get cronjob -o json|jq -r '.items[] | "\(.metadata.name) \(.spec.jobTemplate.spec.template.spec.containers[].name) \(.spec.jobTemplate.spec.template.spec.containers[].image)"'`
# GKE API List filter image = gcr, category by sms/non-sms
https://alm-jira.os.aaaaa.aibang/jira/browse/APICLOUD-9118
https://alm-aibang.os.aaaaa.aibang/sp-api-platform/aib-infra-gcp/blob/APICLOUD-8951/7.gke-scripts/02.gke-ns-scripts/no-sms-deploy-images-replaces-byns.sh
https://alm-aibang.os.aaaaa.aibang/sp-api-platform/aib-infra-gcp/blob/APICLOUD-8951/7.gke-scripts/02.gke-ns-scripts/no-sms-deploy-images-replaces-byproject.sh

- enhance 
- Reference no-sms-deploy-images-replaces-byns.sh loop for my byproject
  - byproject get ns 
  - using no-sms-deploy-images-replaces-byns.sh function to set images 



[Linux ~]$ kubectl get pod -A --show-labels|grep -E "sms=disabled|sms=enabled"|wc -l
306
[Linux ~]$ kubectl get pod -A --show-labels|grep "sms=disabled"|wc -l
95
[Linux ~]$ kubectl get pod -A --show-labels|grep "sms=enabled"|wc -l
211


[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath="{.items[*].metadata.name}"|tr " " "\n"|grep deployment|wc -l
301


- all of deployment
[Linux ~]$ kubectl get deployment -A --no-headers|wc -l
325
- no sms
[Linux ~]$ kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.sms==null) | "\(.metadata.namespace) \(.metadata.name)"'|wc -l
26
- sms enabled
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l
209
- sms disabled 
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="disabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l
90


[Linux ~]$ kubectl get deployment -A --no-headers|grep -Ev "^kube-system|aib-core"|awk '{print$1,$2}' |wc -l
310

  template:
    metadata:
      annotations:
        clusters-autoscaler.kubernetes.io/safe-to-evict: "true"
      creationTimestamp: null
      labels:
        app: woup-wcl-bblsmp-pa-woup-servicenow-1-1-16
        category: springboot
        kdp: aib-int-kdp
        nexthop: ksp-srs-asp-rdcsp
        sms: enabled
        team: asp-rdcsp
        timestamp: "1700451805942"
        type: pa

# sms 

## sms==null

kubectl get deployments -n aib-core -o json | jq -r '.items[] | select(.spec.template.metadata.labels.sms==null) | "\(.metadata.namespace) \(.metadata.name)"'
## sms disabled
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.name}:{@.spec.template.metadata.labels.sms}{"\n"}{end}' |awk -F":" '$2~/disabled/'|wc -l
90

## sms enabled
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l
195 

kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' \
| grep -Ev "^kube-|aib-core|aib-saasp" \
| awk '$1 !~ /-kdp$/ {print $0}'
上面也是195个



[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}'|wc -l
195
[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="disabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}'|wc -l
79
[Linux filter]$ expr 195 + 79
274

kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'


[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'| grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}'|wc -l
276


- 1. filter all 276
[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'| grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' > a
- 2. filter enabled 195
[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' > b
- 3. filter disabled 79
[Linux filter]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="disabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' > c
- 4. filter 276 - 195 - 79
```
[Linux filter]$ cat b c > d
[Linux filter]$ cat d|awk '{print$2}' > e    174 
$ grep -f e a|wc -l
274
[Linux filter]$ grep -vf e a
kuaiyong wsopenai-analysis-service
kuaiyong wsopenai-suggestion-service
```


- merege 
  - kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {@.spec.template.metadata.labels.sms=="enabled"} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'
  - kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l


kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'

kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'

sms diabled
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="disabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l
asp-rdcsp woup-wcl-bblsmp-pa-instabase-1-1-5-deployment
aib-common-ext abj-kuaiyong-aib-pa-healthcheck-2-0-0-deployment


- sms blank 这个比较少基本都是我们自己的 API 
kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.sms==null) | "\(.metadata.namespace) \(.metadata.name)"'

# team 

- filter teams  
- `kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team=="txkj-aib") | "\(.metadata.namespace) \(.metadata.name)"'`
```bash
$ `kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team=="txkj-aib") | "\(.metadata.namespace) \(.metadata.name)"'`
aib-common-ext woup-txkj-aib-pa-healthcheck-1-0-0-deployment
aib-common-ext woup-txkj-aib-pa-healthcheck-2-0-0-deployment
aib-common woup-txkj-aib-pa-healthcheck-1-0-0-deployment
aib-common woup-txkj-aib-pa-healthcheck-2-0-0-deployment
```

+ dev-hk team =null 96 条都没有 再排除 kube-|aib-core|aib-saasp
+ `kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -v "^kube-"`
+ `kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'|wc -l`
83


## process
+  kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' > no-teams-apis.txt
检查`.spec.template.metadata.labels.team`是否为`null`的功能可能无法直接通过JSONPath实现，因为JSONPath不支持检查`null`值
+  kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' > all-apis.txt 275个
+  kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' > all-apis.txt
+  注意下面这个过滤 后来增加了一个仅仅过滤sms=enabled的也就是需要Pipeline去处理的逻辑
  ```bash 
  kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' \
  kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' \
| while read -r line; do 
    namespace=$(echo $line | awk '{print $1}')
    team=$(echo $line | awk '{print $3}')
    gwType=$(kubectl get namespace $namespace -o=jsonpath='{.metadata.labels.gwType}')
    
    # Check if team or gwType is empty, and provide a default value if needed
    team=${team:-<defaultTeam>}
    gwType=${gwType:-<defaultGwType>}
    
    echo "$line $gwType"
done
  ```
+  grep -f no-teams-apis.txt all-apis.txt |wc -l 这个就是没有teams的
83
+ grep -vf no-teams-apis.txt all-apis.txt 这个就是有teams的
grep -vf no-teams-apis.txt all-apis.txt|wc -l
192
- 下面计算结果说明过滤综合比较匹配的。就是说有team和没有team的基本就完整了
```bash
[Linux filter]$ grep -vf no-teams-apis.txt all-apis.txt|wc -l
192
[Linux filter]$ wc -l all-apis.txt
275 all-apis.txt
[Linux filter]$ expr 192 + 83
275
```
- 根据上面的结果我的no-teams-apis都能在all里面找到，我就要补充这一部分的teams的数据，这个参考我的Loopapi.sh
- dp-get-aibteams.sh
- [Linux filter]$ cp ../firestore/dev-hk-running-api.json ./
- cat ../firestore/ns-dp-name-dev-hk-include-version.txt 这个需要改造才能去grep 
- cat ../firestore/ns-dp-name-dev-hk-include-version.txt|sed 's/\./:/'  # 将第一个.替换为 ：号 

- format.sh
```bash
true > ./ns-dp-name-no-teams-api.txt
while read -r ns dpname;do
    splitdpname=${dpname%-deployment*}
    version=$(echo $splitdpname|awk -F"-" '{print$(NF-2)"."$(NF-1)"."$(NF)}')
    #mergeddpname="$splitdpname""deployment"
    bucketname=${splitdpname%-*-*-*}
    echo "$bucketname.$version" >> ./ns-dp-name-no-teams-api.txt
done < no-teams-apis.txt
```
- generate a file ns-dp-name-no-teams-api.txt
- cat ns-dp-name-no-teams-api.txt |grep '.*[0-9]$' > ns-dp-name-no-teams-api-include-version.txt 
- [Linux filter]$ cp ../firestore/apis.json ./
- cat ns-dp-name-no-teams-api-include-version.txt |while read line;do grep "^$line" ./apis.json ;done > ns-dp-name-no-teams-api.json
- `$ cat ns-dp-name-no-teams-api.json |wc -l  72` 仅仅找到了72个
    ```bash
    while read line;do
        grep "^$line" ./apis.json
    done < ./ns-dp-name-${environment}-include-version.txt
    ```
- awk -F"=" '{print$2}' ns-dp-name-no-teams-api.json
-  awk -F"=" '{print$2}' ns-dp-name-no-teams-api.json > stand-ns-dp-name-no-teams-api.json
-   cat stand-ns-dp-name-no-teams-api.json |jq -r '[.name,.version,.aibTeam]|@csv '|sed 's/"//g' > api-version-teams.txt
    -   格式化这个结果
    -   awk -F, '{ gsub(/\./, "-", $2); print $1"-"$2","$3 }' api-version-teams.txt > api-version-teams-format.txt
- cut -d ',' -f 1 api-version-teams-format.txt|grep -F -f - no-teams-apis.txt 这个是去看匹配的结果的
  - 下面有脚本p.sh去生成我要的 no-teams-apis-addteam.txt
  - 以,为分割符 取第一个字段，然后拿个关键字去no-teams-apis.txt文件查看匹配的行 
  - ./p.sh > no-teams-apis-addteam.txt
```bash
#!/bin/bash

# 创建一个关联数组
declare -A map
while IFS=',' read -r key value
do
    map["$key"]="$value"
done < api-version-teams-format.txt

# 处理no-teams-apis.txt文件
while read -r line
do
    for key in "${!map[@]}"
    do
        if [[ $line == *"$key"* ]]; then
            echo "$line ${map[$key]}"
        fi
    done
done < no-teams-apis.txt
```
- compare 还有11个没有的
  - [Linux filter]$ wc -l no-teams-apis.txt
    83 no-teams-apis.txt
  - [Linux filter]$ wc -l no-teams-apis-addteam.txt
    72 no-teams-apis-addteam.txt


grep -f no-teams-apis.txt no-teams-apis-addteam.txt|wc -l 可以找到72个 
72

no-teams-apis-addteam.txt 这个文件也只有72个  拿这个文件的第二个字段no-teams-apis.txt
cat no-teams-apis-addteam.txt|awk '{print$2}' > dep
下面就是没有拿到Teams的 刚好是11个 
$ grep -vf dep no-teams-apis.txt
aib-common-ext woup-txkj-aib-pa-amw-scanner-1-0-2-deployment
aib-common dcs-pa-form-translator-1-0-4-deployment
aib-common dcs-pa-form-translator-1-0-5-deployment
aib-common dcs-pa-gdms-service-1-0-0-deployment
dbbhk-api woup-dbbhk-onboarding-ea-quantum-1-0-22-deployment
dbbhk-obf abj-dbbhk-onboarding-pa-customer-auth-ua-1-1-6-deployment
kuaiyong-ext abj-kuaiyong-aib-pa-healthcheck-1-0-0-deployment
kuaiyong-ext woup-kuaiyong-aib-ea-amw-scanner-1-0-1-deployment
kuaiyong abj-kuaiyong-aib-pa-healthcheck-1-0-0-deployment
kuaiyong wsopenai-analysis-service
kuaiyong wsopenai-suggestion-service



## summary 
- part 1
  - grep -vf no-teams-apis.txt all-apis.txt 这个是192个也就是有teams的
  - cat all-apis.txt |awk 'NF ==3' 这个是192个也就是有teams的
- part 2
  - cat no-teams-apis-addteam.txt  72条
  - 上面11个没有的

cat all-apis.txt |awk 'NF ==3' > all-apis-filter.txt

- no-teams-apis-addteam.txt 

cat no-teams-apis-addteam.txt all-apis-filter.txt|wc -l
264

 cat no-teams-apis-addteam.txt all-apis-filter.txt |sort -k3
 这个是我按照Teams排出来的结果。现在的问题是这个是all的我没有排除sms=disable的
 如果我要排除sms=disable的我处理我最初开始的逻辑就可以了
+  kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' > all-apis.txt 275个
+  kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' > all-apis.txt






```bash
$ cat add-result.txt|awk 'NF !=3'
aib-common-ext glcm-whaleh-dlt-aib-pa-sb-0-1-0-deployment
aib-common-ext ums-gateway-pa-external-response-1-0-0-deployment
obai abj-aibangnet-is-au-ob-pa-account-1-0-11-deployment
```


+ 所以仅仅根据Teams去过滤所有的deployment应该不合理？
```bash
[Linux ~]$  kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'
asp-rdcsp woup-wcl-bblsmp-pa-health-monitor-0-0-2-deployment
kuaiyong wsopenai-analysis-service
kuaiyong wsopenai-suggestion-service
```   
- 查询team==aib的
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.team=="aib")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'
- 查询所有有值的 大概190条 
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.team)]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.team)]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'|wc -l
191


public class UpdateDeploymentRequest {
    private String name;
    private String version;
    private String team;
    private String operator;
    private String gwType;
    private String operation;
}


- 查询所有的 包含Namespace 298
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.name}:{@.spec.template.metadata.labels.team} {@.metadata.namespace}{"\n"}{end}'==> deployment:teams namespace

kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.name}:{@.spec.template.metadata.labels.team} {@.metadata.namespace}{"\n"}{end}'|wc -l
298
- filter namespace api and teams 
  -  `kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'`
     -  except kube-
     -  `kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -v "^kube-"`
     -  `kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"`
     -  `kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'` 275个
     -  过滤第三个字段不为空的
     -  `kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ && $3 !="" {print$0}'`
- bash
- filter one namespace
- `kubectl get deployments -n aib-common -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'` 
- filter all namespace
- `kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'`
```
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ && $3 !="" {print$0}'|wc -l
191
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ && $3 =="" {print$0}'|wc -l
84 也就是这里有84个API需要去补充对应的Teams
[Linux ~]$ kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}'|wc -l
275
要想办法给其补充进去　但是这样Pod会重新创建

[Linux ~]$ kubectl get deployments woup-wcl-bblsmp-pa-health-monitor-0-0-2-deployment -n asp-rdcsp -o yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "2"
  creationTimestamp: "2022-11-29T17:27:27Z"
  generation: 12
  labels:
    app: woup-wcl-bblsmp-pa-health-monitor-0-0-2
    type: pa
  name: woup-wcl-bblsmp-pa-health-monitor-0-0-2-deployment
  namespace: asp-rdcsp
  resourceVersion: "481968054"
  uid: 4ca5fe32-92c0-4504-9756-44ecbe2e72de
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: woup-wcl-bblsmp-pa-health-monitor-0-0-2
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations:
        clusters-autoscaler.kubernetes.io/safe-to-evict: "true"
      creationTimestamp: null
      labels:
        app: woup-wcl-bblsmp-pa-health-monitor-0-0-2
        nexthop: ksp-srs-asp-rdcsp
        sms: enabled
        timestamp: "1669777665576"
        type: pa
    spec:
```

 namespace api teams
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name}:{@.spec.template.metadata.labels.team} {"\n"}{end}'
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'

hsil-ddoc-ext woup-hsi-ddoc-ea-index-stream-1-0-3-deployment:hsil-ddoc
hsil-ddoc-ext woup-hsi-ddoc-ea-index-stream-1-0-4-deployment:hsil-ddoc
hsil-ext-kdp hsil-ext-kdp-dev-kong:
hsil-hiip-int woup-hsil-hiip-ea-content-1-0-3-deployment:hsil-hiip
hsil-hiip-int woup-hsil-hiip-ea-content-1-0-4-deployment:hsil-hiip
hsil-hiip-int woup-hsil-hiip-ea-contract-1-0-4-deployment:hsil-hiip
hsil-hiip-int woup-hsil-hiip-ea-contract-1-0-5-deployment:hsil-hiip
hsil-hiip-int woup-hsil-hiip-ea-customer-1-0-5-deployment:hsil-hiip
hsil-hiip-int woup-hsil-hiip-ea-customer-1-0-6-deployment:hsil-hiip


## query no team这个key的
kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'
 kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -Ev "^kuaiyong|^kube-"


$ kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.spec.template.metadata.labels.team==null) | "\(.metadata.namespace) \(.metadata.name)"'|grep -Ev "^kuaiyong|^kube-"|wc -l
92







了解，如果你需要按照原有格式增加 `gwType` 字段，你可以使用以下命令：

```bash
#kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' 
#kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team}{" "}{@.metadata.namespace}{"\n"}{end}' \
# kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}'|grep -Ev "^kube-|aib-core|aib-saasp"|awk '$1 !~ /-kdp$/ {print$0}' \
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' \
| while read -r line; do 
    namespace=$(echo $line | awk '{print $1}')
    team=$(echo $line | awk '{print $3}')
    gwType=$(kubectl get namespace $namespace -o=jsonpath='{.metadata.labels.gwType}')
    
    # Check if team or gwType is empty, and provide a default value if needed
    team=${team:-<defaultTeam>}
    gwType=${gwType:-<defaultGwType>}
    
    echo "$line $gwType"
done


这个会输出gwtype 如果没有拿到team的话 ，那么对应的行就是3个字段 且三个字段中没有internal或者external
因为是每个都循环稍微有些慢 by Lex L XU
12:10 PM
Lex L XU
因为是每个都循环稍微有些慢
has context menu


kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.sms=="enabled")]}{@.metadata.namespace} {@.metadata.name} {@.spec.template.metadata.labels.team} {"\n"}{end}' | grep -Ev "^kube-|aib-core|aib-saasp" | awk '$1 !~ /-kdp$/ {print $0}' \
| while read -r line; do 
    namespace=$(echo $line | awk '{print $1}')
    team=$(echo $line | awk '{print $3}')
    gwType=$(kubectl get namespace $namespace -o=jsonpath='{.metadata.labels.gwType}')
    
    # Check if team or gwType is empty, and provide a default value if needed
    team=${team:-<defaultTeam>}
    gwType=${gwType:-<defaultGwType>}
    
    echo "$line $gwType"
done




