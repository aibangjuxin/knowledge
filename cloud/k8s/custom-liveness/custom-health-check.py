#!/usr/bin/env python3
"""
自定义健康检查服务
测试Pod是否能访问外部资源
"""
import requests
import time
from flask import Flask, jsonify
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# 配置要测试的外部资源
EXTERNAL_URLS = [
    "https://www.baidu.com",
    "https://www.google.com",
    # 可以添加更多URL
]

# 超时设置
REQUEST_TIMEOUT = 5
PROXY_CONFIG = {
    'http': 'http://squid-proxy:3128',
    'https': 'http://squid-proxy:3128'
}

def test_external_connectivity():
    """测试外部连接"""
    for url in EXTERNAL_URLS:
        try:
            response = requests.get(
                url, 
                timeout=REQUEST_TIMEOUT,
                proxies=PROXY_CONFIG if 'squid-proxy' in locals() else None
            )
            if response.status_code == 200:
                logging.info(f"Successfully connected to {url}")
                return True
        except Exception as e:
            logging.error(f"Failed to connect to {url}: {str(e)}")
            continue
    
    return False

@app.route('/health')
def health_check():
    """健康检查端点"""
    if test_external_connectivity():
        return jsonify({
            "status": "healthy",
            "message": "External connectivity OK",
            "timestamp": time.time()
        }), 200
    else:
        return jsonify({
            "status": "unhealthy", 
            "message": "External connectivity failed",
            "timestamp": time.time()
        }), 503

@app.route('/ready')
def readiness_check():
    """就绪检查端点"""
    return health_check()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)