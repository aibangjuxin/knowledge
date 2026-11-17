- first principles /ˈprɪns.ɪplz/
- make it more flexible and focused on CVE information extraction.
- Now I will summary how fix  violation
	- 1.  apt update ==> latest 
		- using --only-upgrade [only update violation Running library ]
		- eg: `apt install --only-upgrade libpam0g libpam-modules libpam-modules-bin libpam-runtime`
	- 2. make sure using right repo within apt sources.list 
	- 3. using dkpg -l |grep Verify the New latest version about of my keyword.
	- 4. Check cyberflows report and find the Solution
		- need using purge command delete some lib or packages
		- eg: `apt-get purge -y iir1.2-glib-2.0`
	- 5. filter the cve report at office 
		- https://ubuntu.com/security/CVE-2025-8941
	- 6. find the internal repo package Version 




# fix Flow
```mermaid
graph TD
    A[检测到 CVE-2025-8941] --> B{官方是否发布补丁?}
    B -->|否| C[状态: fix deferred]
    C --> D[执行缓解措施: PAM加固 + SSH限制]
    D --> E[启用 unattended-upgrades]
    E --> F[持续监控 Ubuntu 安全通告]
    B -->|是| G[执行 apt upgrade 修复漏洞]
```

- fix 
```mermaid
graph TD
    A[开始修复] --> B{检查组件类型}
    B -->|PAM 组件| C[更新软件源]
    B -->|Netty 组件| D[检查依赖关系]
    
    C --> E{官方有补丁?}
    E -->|是| F[apt install --only-upgrade]
    E -->|否| G{是否紧急?}
    
    G -->|是| H[尝试 proposed 源]
    G -->|否| I[等待官方补丁]
    
    D --> J{是独立包?}
    J -->|是| K[直接升级 Netty]
    J -->|否| L[升级依赖应用]
    
    F --> M[验证修复]
    H --> M
    K --> M
    L --> M
    
    M --> N{漏洞是否消除?}
    N -->|是| O[完成]
    N -->|否| P[查看 CVE 详情]
    
    P --> Q[应用临时缓解措施]
    Q --> I
    I --> R[定期检查更新]
    R --> O
```