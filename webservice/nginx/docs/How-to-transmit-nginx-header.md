
  

> 在流量路径中，**A(7层 Nginx)** → **B(4层 Nginx Stream 模式)** → **C(GKE Gateway)**，但由于 B 是 L4 层，导致 C（GKE Gateway）只能看到 B 的 IP（如 192.168.0.35），无法获得真正的 **客户端源 IP（来自 A 或用户）**，从而 **无法使用 Cloud Armor 做基于源 IP 的访问控制**。