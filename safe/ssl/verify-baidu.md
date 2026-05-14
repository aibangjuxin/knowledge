./verify-domain-ssl-enhance.sh www.baidu.com
```bash
./verify-domain-ssl-enhance.sh www.baidu.com
==================================================
SSL probe for www.baidu.com:443
CA source:               system default CA store
==================================================

==================================================
[1] Fetching TLS handshake and certificate chain
==================================================
Certificates returned:   3
Chain appears to include multiple certificates.

==================================================
[2] Connection summary
==================================================
Connected:               CONNECTED(00000005)
Protocol:                TLSv1.2
Cipher:                  ECDHE-RSA-AES128-GCM-SHA256
Peer signature:          rsa_pss_rsae_sha256
Server temp key:
Verify result:               Verify return code: 0 (ok)

==================================================
[3] Per-certificate details
==================================================
--- cert_01.pem ---
Subject:                 C=CN, ST=beijing, L=beijing, O=Beijing Baidu Netcom Science Technology Co., Ltd, CN=baidu.com
Issuer:                  C=BE, O=GlobalSign nv-sa, CN=GlobalSign RSA OV SSL CA 2018
Serial:                  5753597B3F311D38E6629529
Not before:              Jul  9 07:01:02 2025 GMT
Not after:               Aug 10 07:01:01 2026 GMT
Basic constraints:       CA:FALSE
SAN:                     DNS:baidu.com, DNS:baifubao.com, DNS:www.baidu.cn, DNS:www.baidu.com.cn, DNS:mct.y.nuomi.com, DNS:apollo.auto, DNS:dwz.cn, DNS:*.baidu.com, DNS:*.baifubao.com, DNS:*.baidustatic.com, DNS:*.bdstatic.com, DNS:*.bdimg.com, DNS:*.hao123.com, DNS:*.nuomi.com, DNS:*.chuanke.com, DNS:*.trustgo.com, DNS:*.bce.baidu.com, DNS:*.eyun.baidu.com, DNS:*.map.baidu.com, DNS:*.mbd.baidu.com, DNS:*.fanyi.baidu.com, DNS:*.baidubce.com, DNS:*.mipcdn.com, DNS:*.news.baidu.com, DNS:*.baidupcs.com, DNS:*.aipage.com, DNS:*.aipage.cn, DNS:*.bcehost.com, DNS:*.safe.baidu.com, DNS:*.im.baidu.com, DNS:*.baiducontent.com, DNS:*.dlnel.com, DNS:*.dlnel.org, DNS:*.dueros.baidu.com, DNS:*.su.baidu.com, DNS:*.91.com, DNS:*.hao123.baidu.com, DNS:*.apollo.auto, DNS:*.xueshu.baidu.com, DNS:*.bj.baidubce.com, DNS:*.gz.baidubce.com, DNS:*.smartapps.cn, DNS:*.bdtjrcv.com, DNS:*.hao222.com, DNS:*.haokan.com, DNS:*.pae.baidu.com, DNS:*.vd.bdstatic.com, DNS:*.cloud.baidu.com, DNS:click.hm.baidu.com, DNS:log.hm.baidu.com, DNS:cm.pos.baidu.com, DNS:wn.pos.baidu.com, DNS:update.pan.baidu.com

--- cert_02.pem ---
Subject:                 C=BE, O=GlobalSign nv-sa, CN=GlobalSign RSA OV SSL CA 2018
Issuer:                  OU=GlobalSign Root CA - R3, O=GlobalSign, CN=GlobalSign
Serial:                  01EE5F221DFC623BD4333A8557
Not before:              Nov 21 00:00:00 2018 GMT
Not after:               Nov 21 00:00:00 2028 GMT
Basic constraints:       CA:TRUE, pathlen:0
SAN:                     not present or not readable

--- cert_03.pem ---
Subject:                 OU=GlobalSign Root CA - R3, O=GlobalSign, CN=GlobalSign
Issuer:                  C=BE, O=GlobalSign nv-sa, OU=Root CA, CN=GlobalSign Root CA
Serial:                  01EE5F169DFF97352B6465D66A
Not before:              Sep 19 00:00:00 2018 GMT
Not after:               Jan 28 12:00:00 2028 GMT
Basic constraints:       CA:TRUE
SAN:                     not present or not readable


==================================================
[4] Hostname verification
==================================================
Leaf cert host match:    PASS

==================================================
[5] Chain verification
==================================================
/tmp/ssl_probe_www.baidu.com_4Du4JR/cert_01.pem: OK

==================================================
[6] Diagnosis guide
==================================================
- CERT_COUNT = 0: check DNS, network path, load balancer listener, firewall, SNI, or TLS termination point.
- CERT_COUNT = 1: server likely returns only the leaf certificate; check fullchain configuration on LB / ingress / nginx / kong.
- Verify return code 20: chain was presented but local CA store cannot anchor it to a trusted issuer.
- Verify return code 21: server likely omitted an intermediate certificate, or the presented chain is incomplete.
- Hostname verification FAIL: certificate SAN/CN does not match the requested domain.
- If custom CA passes but system CA fails: the endpoint is probably signed by an internal CA not present in the current trust store.

==================================================
[7] Temporary artifacts
==================================================
Raw openssl output was abjtured at: /tmp/ssl_probe_www.baidu.com_4Du4JR/s_client.txt
Per-certificate PEM files were created under: /tmp/ssl_probe_www.baidu.com_4Du4JR
Artifacts will be removed automatically when the script exits.
```