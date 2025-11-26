
POC - Use distroless image as base image for docker
我们需要进行一个多阶段构建 (multistage builds)的可行性分析.下面是需要考虑一些方面
Definition of Done - Do a poc to using distroless image and pilot with one or two real API to identify the gap.
Action Requirement/Task
Breakdown/Project Plan
Issue/Feature analysis
Development Task
Testing Task
Deployment Task
Documentation
Demo & Training

[https://yeasy.gitbook.io/docker_practice/image/multistage-builds](https://yeasy.gitbook.io/docker_practice/image/multistage-builds)

这个是我们旧的Dockerfile模版
- Dockerfile
````Dockerfile
FROM FROM nexus3.companydomain:18080/zuljava-jre-Ubuntu-17:latest
# set env
ENV DEBIAN_FRONTEND=noninteractive
ENV API_NAME
ENV API_VERSION
ENV API_NAME=${API_NAME}
ENV API_VERSION=${API_VERSION}
USER root
# apt update
RUN --mount-type=secret,id=auth,target=/etc/apt/auth.conf \
    apt-get update && \
    apt-get install -y --no-install-recommends curl wget gnupg2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY ${API_NAME}-${API_VERSION}.jar /opt/apps/
COPY ["wrapper.sh","abc.sh","/opt/"]
RUN chmod +x /opt/wrapper.sh /opt/abc.sh
# Create api admin
RUN groupadd -g 3000 apigroup
RUN useradd -u 3000 -g 3000 -ms /bin/bash apiadmin
RUN chown -R apiadmin:apigroup /opt/
RUN chmod u+s /usr/bin/rm
# start api
WORKDIR /opt
USER apiadmin
CMD ./wrapper.sh ${API_NAME} ${API_VERSION}
# docker build
# docker build -t apiname:latest --build-arg API_NAME=apiname --build-arg API_VERSION=2.0.0 .
````
- `wrapper.sh`
```bash
#!/bin/bash
function start_api() {
  java -jar /opt/apps/$API_NAME-$API_VERSION.jar
}
start_api
```