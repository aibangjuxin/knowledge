

我需要跨2个GCP Project Shared VPC里面抓日志
比如说我们称之为
UK Shared VPC IP Range 10.72.0.0/10
CN Shared VPC IP Range 10.92.0.0/10
比如A工程是UK的里面有Instance主机一般有2块网卡。一个是private的网络，一个是Shared VPC UK的网络。 
我现在要跟踪一个IP来自哪里?或者其资源类型是什么?这个IP地址是10.72.22.3 我看到这个IP发起了一些请求.
到另一个工程的IP比如10.72.22.3
UK VPC 下某个 A工程对应的是shared vpc UK 
CN VPC下某个 B 工程这个下面一个VM的Share VPC CN 这个网络下一个Instance IP 是10.92.22.3
我如何获取完整的日志情况. 另外我也关心一些VPC之间互联的基础概念.如果可以可以帮我画出一个使用interconnects链接2个VPC的Flow图? 
因为每个Shared VPC本身又是多个GCP project 共用的。 比如我们
所有使用UK shared vpc 这边的叫做UK ==> 下面有很多GCP Project 
所有使用CN shared vpc 这班的叫做CN ==> 下面也有很多GCP project
```
UK Region (Host Project)
├── Shared VPC UK (10.72.0.0/10)
│   ├── Project A (Service Project)
│   │   └── VM Instance (10.72.22.3) OR it's a src_gateway
│   ├── Project B (Service Project)
│   └── Project C (Service Project)
└── Interconnect Attachment

CN Region (Host Project)
├── Shared VPC CN (10.92.0.0/10)
│   ├── Project X (Service Project)
│   │   └── VM Instance (10.92.22.3)
│   ├── Project Y (Service Project)
│   └── Project Z (Service Project)
└── Interconnect Attachment
```

我应该是去Shared VPC所在的Project 去捕获日志。 
能否给我一些思路 或者快速实现，我的目的是快速定位到比如A工程里面的这个IP 10.72.22.3 对应的Instance主机。
在后来的探索当中，我期待的IP地址应该不是1个VM的日志,我发现了其实有这样一个概念 就是说在不同的vpc之间访问的时候 有下面这样一个日志，所以说我拿到了一些其他概念interconnects attachments describe
```json
"src_gateway"(
"type": "'INTERCONNECT_ATTACHMENT"?
"project_id": "aibang-1231231-vpchost-eu-prod",
"vpc": {
"pc_name": "aibang-1231231-vpchost-eu-prod-cinternal-vpc1",
"project_id": "aibang-1231231-vpchost-eu-prod"
｝
"location": "europe-west2",
"interconnect_project_number": "538341205868",
"name": "aibang-1231231-vpchost-eu-prod-vpc1-eq1d6-z2-3b",
"interconnect_name": "aibang-1231231-vpc-europe-prod-eqld6-z2-3"
"dest_vpc": E
"project_id": "aibang-1231231-vpchost-eu-prod",
"subnetwork_region": "europe-west2",
"vpc_name":: "aibang-1231231-vpchost-eu-prod-cinternal-vpc1",
"subnetwork_name": "cinternal-vpc1-europe-west2"
"connection": {
"protocol": 6,
"dest_ip": "10.100.17.167",
"doct nont"
2129
"src ip":
"10.72.22.3",
src_port": 59304
```

gcloud compute interconnects attachments describe
因为这个IP其实不是一个VM
该字段标识的是 GCP Cloud Interconnect 物理/逻辑
Interconnect 资源 （Dedicated 或 Partner Interconnect） 本身的名字，不是 VLAN attachment，也不是 Cloud Router。它代表
GCP 与本地数据中心之间的某条专线（或一组链路）实体，承载下面多个 VLAN attachments（例如日志里的 src_gateway.name：
就是其中一个 attachment
基于此我想了解一些关于GCP VPC之间的的概念或者关系
在 Google Cloud 中：Interconnect Attachment (VLAN Attachment) Router (Cloud Router)

￼
