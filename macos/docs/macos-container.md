container system start

➜  ~ container system start
Launching container-apiserver...
Testing access to container-apiserver...
Verifying machine API server is running..


➜  ~ mkdir -p ~/ha_config
➜  ~ pwd


➜  ~ container run -d \
  --name homeassistant \
  -v /Users/lex/ha_config:/config \
  -e TZ=Asia/Shanghai \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable



  # 创建配置目录
mkdir -p ~/ha_config

# 启动 Home Assistant（去掉 --network=host）
container run -d \
  --name homeassistant \
  -v /Users/lex/ha_config:/config \
  -e TZ=Asia/Shanghai \
  ghcr.io/home-assistant/home-assistant:stable
homeassistant 
# 看启动日志
container logs -f homeassistant
➜  ~ container logs -f homeassistant
s6-rc: info: service s6rc-oneshot-runner: starting
s6-rc: info: service s6rc-oneshot-runner successfully started
s6-rc: info: service fix-attrs: starting
s6-rc: info: service fix-attrs successfully started
s6-rc: info: service legacy-cont-init: starting
s6-rc: info: service legacy-cont-init successfully started
s6-rc: info: service legacy-services: starting
services-up: info: copying legacy longrun home-assistant (no readiness notification)
s6-rc: info: service legacy-services successfully started
2026-06-18 12:18:21.464 WARNING (ImportExecutor_0) [py.warnings] /usr/local/lib/python3.14/site-packages/rich/segment.py:547: SyntaxWarning: 'return' in a 'finally' block
  return


# 确认容器跑起来了
container ls
➜  ~ container ls
ID             IMAGE                                         OS     ARCH   STATE    IP               CPUS  MEMORY   STARTED
homeassistant  ghcr.io/home-assistant/home-assistant:stable  linux  arm64  running  192.168.64.2/24  4     1024 MB  2026-06-18T04:18:18Z


# 看端口映射（OrbStack 通常会直接暴露）
container ls --format "{{.Names}} {{.Ports}}"


http://192.168.64.2:8123/onboarding.html
