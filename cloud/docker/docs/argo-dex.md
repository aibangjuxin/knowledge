➜  ~ docker pull --platform linux/amd64 dexidp/dex:latest
latest: Pulling from dexidp/dex
23a5c88706e6: Pull complete
9ae8349519e9: Pull complete
90df3e2cf03c: Pull complete
60256958346d: Pull complete
351bf9cfb227: Pull complete
b39b2a0f5840: Pull complete
c1525c6e50c3: Pull complete
2258e1d7495d: Pull complete
8e2f6e30fd4c: Pull complete
635a5e5951fb: Pull complete
56eae75e56ee: Pull complete
Digest: sha256:b66073d3e3dd95539c943445e3fbfab78d64d6b6d91be0f497c5989d69f059d1
Status: Downloaded newer image for dexidp/dex:latest
docker.io/dexidp/dex:latest
➜  ~ docker save --platform linux/amd64 -o dex-linux-amd64.tar dexidp/dex:latest
➜  ~ du -sh dex-linux-amd64.tar
 50M    dex-linux-amd64.tar