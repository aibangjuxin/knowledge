import os
import urllib.request
import urllib.error
import urllib.parse
import ssl

class AuthenticationClient:
    """
    一个演示用的客户端，展示如何根据不同的环境配置适配 Reverse Proxy 和 Forward Proxy。
    (使用标准库 urllib，无需 pip install requests)
    """

    def __init__(self, use_forward_proxy=False):
        """
        初始化客户端。
        """
        # Mode A 配置 (Reverse Proxy, Legacy)
        self.legacy_base_url = "https://dev-microsoft.gcp.cloud.env.aibang/login/"
        
        # Mode B 配置 (Forward Proxy, Target Truth)
        self.real_base_url = "https://login.microsoftonline.com/"
        self.forward_proxy_url = "http://microsoft.intra.aibang.local:3128"

        # 决策逻辑
        env_http_proxy = os.environ.get("HTTP_PROXY") or os.environ.get("HTTPS_PROXY")
        
        if use_forward_proxy or env_http_proxy:
            print("[Init] Mode B Detected: 使用正向代理 (Forward Proxy) 模式")
            self.mode = "FORWARD"
            self.base_url = self.real_base_url
            
            # 配置 urllib 的 ProxyHandler
            if not env_http_proxy:
                 self.proxy_handler = urllib.request.ProxyHandler({
                     "http": self.forward_proxy_url,
                     "https": self.forward_proxy_url
                 })
                 print(f"[Init] 手动配置代理: {self.forward_proxy_url}")
            else:
                # urllib 默认会自动读取环境变量，不需要额外操作，但为了演示显式加上
                self.proxy_handler = urllib.request.ProxyHandler() 
                print(f"[Init] 检测到环境代理变量: {env_http_proxy}")
        else:
            print("[Init] Mode A Detected: 使用反向代理 (Reverse Proxy) 模式")
            self.mode = "REVERSE"
            self.base_url = self.legacy_base_url
            self.proxy_handler = None

    def get_token(self, tenant_id):
        endpoint = f"{tenant_id}/oauth2/v2.0/token"
        full_url = urllib.parse.urljoin(self.base_url, endpoint)
        
        print(f"\n[Request] 正在发起请求...")
        print(f"  - Mode: {self.mode}")
        print(f"  - URL : {full_url}")
        
        # 构建 Opener
        handlers = []
        if self.proxy_handler:
            handlers.append(self.proxy_handler)
            print(f"  - Proxy: Enable")
        else:
            print(f"  - Proxy: None (Direct/Transparent)")
            
        # 忽略 SSL 验证 (仅为了本地模拟演示，生产严禁这样做!)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        handlers.append(urllib.request.HTTPSHandler(context=ctx))

        opener = urllib.request.build_opener(*handlers)
        
        try:
            # 发起请求
            # timeout 是 socket 级别的
            with opener.open(full_url, timeout=3) as response:
                print(f"[Response] Status: {response.getcode()}")
                return response.getcode()
            
        except urllib.error.URLError as e:
            print(f"[Error] 连接失败 (预期内，因为这是本地模拟): {e}")
            return None
        except Exception as e:
            print(f"[Error] 其他错误: {e}")
            return None

def main():
    tenant_id = "test-tenant-id-123"

    print("="*60)
    print("场景 1: 模拟旧环境 (无代理变量，走 Nginx 反向代理)")
    print("="*60)
    # 清理环境变量
    os.environ.pop("HTTP_PROXY", None)
    os.environ.pop("HTTPS_PROXY", None)
    
    client_a = AuthenticationClient(use_forward_proxy=False)
    client_a.get_token(tenant_id)
    
    print("\n" + "="*60)
    print("场景 2: 模拟新环境 (注入 HTTP_PROXY，走 Squid 正向代理)")
    print("="*60)
    # 模拟 Kubernetes 注入环境变量
    os.environ["HTTPS_PROXY"] = "http://microsoft.intra.aibang.local:3128"
    
    client_b = AuthenticationClient(use_forward_proxy=True)
    client_b.get_token(tenant_id)

    print("\n" + "="*60)
    print("场景 3: 代码自适应 (仅依靠环境变量)")
    print("="*60)
    # 保持环境变量存在
    client_c = AuthenticationClient()
    client_c.get_token(tenant_id)

if __name__ == "__main__":
    main()
