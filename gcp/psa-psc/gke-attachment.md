https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net

Create ServiceAttachment.

The following manifest describes a ServiceAttachment that exposes the service that you created to service consumers. Save the manifest as my-psc.yaml:


apiVersion: networking.gke.io/v1
kind: ServiceAttachment
metadata:
 name: SERVICE_ATTACHMENT_NAME
 namespace: default
spec:
 connectionPreference: ACCEPT_AUTOMATIC
 natSubnets:
 - SUBNET_NAME
 proxyProtocol: false
 reconcileConnections: false  # set to true to enable connection reconciliation
 resourceRef:
   kind: Service
   name: SERVICE_NAME