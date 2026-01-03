在 Python 中，有几种方法可以查看详细的执行过程：

1. 使用 Python 的内置调试器 pdb：
```bash
python3 -m pdb /Users/lex/git/knowledge/nba/compare.py <URL>
```
在 pdb 中常用命令：
- `n`: 下一步
- `s`: 步入函数
- `c`: 继续执行
- `p 变量名`: 打印变量值
- `l`: 显示当前位置代码
- `q`: 退出调试器

2. 添加详细的日志输出，修改代码如下：

```python:/Users/lex/git/knowledge/nba/compare.py
import logging

# ... 其他导入保持不变 ...

# 在文件开头添加日志配置
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def scrape_url(url):
    logging.debug(f"开始抓取 URL: {url}")
    try:
        # ... 现有代码 ...
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        logging.debug(f"使用 headers: {headers}")
        
        response = requests.get(url, headers=headers)
        logging.debug(f"请求状态码: {response.status_code}")
        
        # ... 其余代码保持不变 ...
```

3. 使用 Python 的性能分析器：
```bash
python3 -m cProfile -s cumtime /Users/lex/git/knowledge/nba/compare.py <URL>
```

4. 如果使用 VS Code，可以直接在代码中设置断点，然后使用调试模式运行。

推荐使用第 2 种方法（添加日志），因为它：
- 不会中断程序执行
- 可以看到详细的执行流程
- 便于问题排查
- 可以保存日志供后续分析