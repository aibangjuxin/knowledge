To monitor the network policy hit log for pods in Google Kubernetes Engine (GKE), you can follow these steps:
1. Enable network policy logging by creating a new ConfigMap with the following settings:

apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-system/network-policy-logging
  namespace: kube-system
data:
  loglevel: "5"

Apply the ConfigMap to your cluster using the command:

kubectl apply -f <path_to_config_map.yaml>


Verify that network policy logging is enabled by running the command

gcloud container clusters describe <cluster_name> --zone=<zone>

and checking that the networkPolicyConfig field has the enabled attribute set to true.
4. View the network policy hit logs by querying the Stackdriver Logging API using the command:

gcloud logging read "resource.type=k8s_container AND resource.labels.cluster_name=<cluster_name> AND resource.labels.namespace_name=<namespace_name> AND resource.labels.pod_name=<pod_name> AND jsonPayload.event.reason=NetworkPolicyMatch" --limit=<limit_value>

You can monitor GKE pod network policy hit logs by enabling audit logging in your GKE cluster and configuring it to log the network policy decisions. This can be done using the Stackdriver Logging feature in Google Cloud Platform.
Once enabled, you can filter the logs based on the "k8s.io/pod-network-policy" log category to see the network policy hit logs for your GKE pods. Additionally, you can create metrics and alerts based on these logs using Stackdriver Monitoring to proactively identify and respond to network policy violations.
