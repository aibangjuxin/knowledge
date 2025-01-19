import re
import requests
from collections import Counter
from urllib.parse import urlparse
from bs4 import BeautifulSoup

def get_domains(url):
    try:
        # 获取页面内容
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        html_content = response.text

        # 使用 BeautifulSoup 解析 HTML
        soup = BeautifulSoup(html_content, "html.parser")

        # 获取所有的链接
        links = set()
        for tag in soup.find_all(["a", "img", "script", "link", "iframe"]):
            attr = tag.get("href") or tag.get("src")
            if attr:
                links.add(attr)

        # 提取域名
        domains = []
        for link in links:
            parsed_url = urlparse(link)
            domain = parsed_url.netloc
            if domain:
                domains.append(domain)

        # 统计域名出现次数
        domain_counts = Counter(domains)

        # 按出现次数降序排序
        sorted_domains = sorted(domain_counts.items(), key=lambda x: x[1], reverse=True)

        return sorted_domains

    except Exception as e:
        print(f"Error: {e}")
        return []

if __name__ == "__main__":
    # 示例页面 URL
    page_url = input("请输入页面 URL: ")
    
    # 获取域名并排序
    result = get_domains(page_url)
    
    # 输出结果
    print(f"页面 {page_url} 涉及到的域名如下：")
    for domain, count in result:
        print(f"{domain}: {count}")
