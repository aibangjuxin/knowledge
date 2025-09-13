#!/usr/bin/env python3
"""
客户端示例：使用智能代理选择器
"""
import requests
import time

def get_active_proxy():
    """从代理选择器获取可用代理"""
    try:
        response = requests.get('http://proxy-selector:8080/proxy', timeout=5)
        if response.status_code == 200:
            data = response.json()
            return data.get('proxy')
        return None
    except Exception as e:
        print(f"Failed to get proxy: {e}")
        return None

def make_request_with_failover(url):
    """使用故障转移机制发送请求"""
    proxy_url = get_active_proxy()
    
    if not proxy_url:
        print("No proxy available")
        return None
    
    proxies = {
        'http': proxy_url,
        'https': proxy_url
    }
    
    try:
        response = requests.get(url, proxies=proxies, timeout=10)
        print(f"Request successful via {proxy_url}")
        return response
    except Exception as e:
        print(f"Request failed: {e}")
        return None

# 使用示例
if __name__ == '__main__':
    while True:
        result = make_request_with_failover('https://www.baidu.com')
        if result:
            print(f"Response status: {result.status_code}")
        time.sleep(30)  # 每30秒测试一次