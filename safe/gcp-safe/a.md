gcloud kms keysget-iam-policy projects/aibang-project-id-kms-env/1ocations/g1oba1/keyRings/aibang-1234567-ajx01-env/cryptokeys/env01-uk-core-ajx bindings:

- ﻿﻿members:
- ﻿﻿serviceAccount:ajx-env-uk-kbp-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com
- ﻿serviceAccount:env01-uk-kdp-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com
- ﻿serviceaccount:env01-uk-rt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com
  role: roles/cloudkms.cryptokeyDecrypter members:
- serviceaccount:env01-uk-encrypt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com
  role: roles/cloudkms.cryptokeyEncrypter

# decrypt certificate and key files

function decrypt*cert 0) {
echo "--- decrypt cert file --*" local project_keyring=$project #kms key
local key=${env}-${region}-core-cap
[[ ${region} = hk ]] && local key=$
{env}-${region}-core-ahp
[[${env}!= "prd" && ${region}!=
"prod" ]] && local
project_kms=aibang-project-id-kms-env || local project_kms=aibang-project-id-kms-prod
gcloud kms decrypt --project $ {project_kms} --ciphertext-file=$1 --plaintext-file=$2 --key=$key --keyring=${project_keyring} --location=global
if [[$? == "1" ]]; then
echo "decrypt cert $1 failed" echo "revoke kdp-sa service account and clear temp files"
logout_gcp_sa
clean_up_temp_certs exit 1
else
echo "decrypt cert $1 successfully"
f
}
