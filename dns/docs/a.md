```bash
#!/bin/bash
team_name="teamname"
project=aibang-111111111-kongapi-dev
ENV=$1
REGION=$2
AUTHN_FQDN=auths.$ENV-sb-rt.aliyun.cloud.$REGION.local
networks=projects/aibang-111111111-kongapi-dev/global/networks/aibang-111111111-kongapi-dev-cinternal-vpc2
if [[ $REGION == hk || $REGION == uk ]];then AUTHN_FQDN=auths.$ENV-sb-rt.aliyun.cloud.$REGION.aibang; fi
# private-dev-gke-cloud-uk-local
# define a scoped project for the DNS zone
# create a DNS zone for the private environment
zone_name="private-$ENV-gke-cloud-$REGION-$team_name-local"
if [[ $REGION == hk || $REGION == uk ]];then zone_name="private-$ENV-gke-cloud-$REGION-$team_name-aibang"; fi
dns_name=cloud.$REGION.local
if [[ $REGION == hk ||  $REGION == uk ]];then dns_name=${AUTHN_FQDN#auths.}; fi


echo "authn_fqdn: $AUTHN_FQDN"
echo "zone_name: $zone_name"
echo "dns_name: $dns_name"
echo "networks: $networks"
description="$zone_name private zone for $team_name gke"
# the next will create a DNS zone for the private environment
echo "gcloud dns --project=$project managed-zones create $zone_name --description="\"${description}\"" --dns-name=$dns_name  --visibility=private"


# the next will create a DNS record for the private environment
echo "gcloud dns --project=$project record-sets create $AUTHN_FQDN --zone=$zone_name --type=A --ttl=30 --rrdatas=10.10.10.10"
```
