#!/opt/homebrew/Caskroom/miniconda/base/bin/python
"""
本地知识库智能检索工具
使用 ripgrep 搜索 + Ollama AI 总结
"""

import subprocess
import json
import sys
import argparse
from pathlib import Path
from typing import List, Dict, Tuple
import requests

# 配置
KNOWLEDGE_BASE = "/Users/lex/git/knowledge"
RG_PATH = "/opt/homebrew/bin/rg"
OLLAMA_API = "http://localhost:11434/api/generate"
DEFAULT_MODEL = "qwen3.5:4b"  # 快速且效果好的模型

class KnowledgeSearcher:
    def __init__(self, kb_path: str, model: str = DEFAULT_MODEL):
        self.kb_path = Path(kb_path)
        self.model = model
        
    def search(self, keywords: str, max_results: int = 20) -> List[Dict]:
        """使用 ripgrep 搜索关键词"""
        cmd = [
            RG_PATH,
            "--json",
            "--max-count", str(max_results),
            "--ignore-case",
            "--type-add", "md:*.md",
            "--type", "md",
            keywords,
            str(self.kb_path)
        ]
        
        try:
            result = subprocess.run(cmd, abjture_output=True, text=True, timeout=10)
            matches = []
            
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    if data.get('type') == 'match':
                        match_data = data['data']
                        matches.append({
                            'file': match_data['path']['text'],
                            'line_number': match_data['line_number'],
                            'line': match_data['lines']['text'].strip(),
                            'context': match_data.get('submatches', [])
                        })
                except json.JSONDecodeError:
                    continue
            
            return matches
        except subprocess.TimeoutExpired:
            print("搜索超时", file=sys.stderr)
            return []
        except Exception as e:
            print(f"搜索错误: {e}", file=sys.stderr)
            return []
    
    def format_search_results(self, matches: List[Dict]) -> str:
        """格式化搜索结果为文本"""
        if not matches:
            return "未找到相关内容"
        
        # 按文件分组
        files_dict = {}
        for match in matches:
            file_path = match['file']
            if file_path not in files_dict:
                files_dict[file_path] = []
            files_dict[file_path].append(match)
        
        result = []
        result.append(f"找到 {len(matches)} 条匹配，分布在 {len(files_dict)} 个文件中\n")
        
        for file_path, file_matches in list(files_dict.items())[:10]:  # 限制文件数
            rel_path = Path(file_path).relative_to(self.kb_path)
            result.append(f"\n## 文件: {rel_path}")
            for match in file_matches[:5]:  # 每个文件最多5条
                result.append(f"  行 {match['line_number']}: {match['line'][:150]}")
        
        return '\n'.join(result)
    
    def ask_ollama(self, prompt: str, stream: bool = True) -> str:
        """调用 Ollama API"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": stream,
            "options": {
                "temperature": 0.7,
                "num_predict": 500  # 限制输出长度，加快速度
            }
        }
        
        try:
            response = requests.post(OLLAMA_API, json=payload, stream=stream, timeout=90)
            response.raise_for_status()
            
            if stream:
                full_response = []
                for line in response.iter_lines(decode_unicode=True):
                    if line:
                        try:
                            data = json.loads(line)
                            if 'response' in data:
                                chunk = data['response']
                                print(chunk, end='', flush=True)
                                full_response.append(chunk)
                            if data.get('done', False):
                                break
                        except json.JSONDecodeError:
                            continue
                print()  # 换行
                return ''.join(full_response)
            else:
                return response.json().get('response', '')
                
        except requests.exceptions.Timeout:
            return "\n⚠️  AI 响应超时，请尝试使用更快的模型（如 qwen3.5:0.8b）或使用 --no-ai 选项"
        except requests.exceptions.RequestException as e:
            return f"\n❌ AI 调用失败: {e}"
    
    def generate_concept_summary(self, keywords: str, search_results: str) -> str:
        """生成概念性总结"""
        # 限制搜索结果长度，避免 prompt 过长
        max_result_len = 2000
        if len(search_results) > max_result_len:
            search_results = search_results[:max_result_len] + "\n...(结果已截断)"
        
        prompt = f"""你是知识库助手。用户搜索: "{keywords}"

搜索结果:
{search_results}

请简洁回答:
1. 核心概念 (1-2句)
2. 关键点 (3个要点)
3. 推荐文件 (2-3个)
4. 相关主题

用中文，简洁明了。
"""
        
        print("\n" + "="*60)
        print("🤖 AI 正在分析搜索结果...")
        print("="*60 + "\n")
        
        return self.ask_ollama(prompt, stream=True)

def main():
    parser = argparse.ArgumentParser(
        description="本地知识库智能检索工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s nginx proxy_pass
  %(prog)s "GKE ingress" --max 30
  %(prog)s ollama --model gemma3:4b
  %(prog)s --list-models
        """
    )
    
    parser.add_argument('keywords', nargs='*', help='搜索关键词')
    parser.add_argument('--max', type=int, default=20, help='最大搜索结果数 (默认: 20)')
    parser.add_argument('--model', default=DEFAULT_MODEL, help=f'Ollama 模型 (默认: {DEFAULT_MODEL})')
    parser.add_argument('--no-ai', action='store_true', help='只搜索，不使用 AI 总结')
    parser.add_argument('--list-models', action='store_true', help='列出可用的 Ollama 模型')
    
    args = parser.parse_args()
    
    # 列出模型
    if args.list_models:
        try:
            resp = requests.get("http://localhost:11434/api/tags", timeout=5)
            models = resp.json().get('models', [])
            print("可用的 Ollama 模型:")
            for m in models:
                print(f"  - {m['name']}")
        except Exception as e:
            print(f"无法获取模型列表: {e}")
        return
    
    # 检查关键词
    if not args.keywords:
        parser.print_help()
        return
    
    keywords = ' '.join(args.keywords)
    
    # 搜索
    searcher = KnowledgeSearcher(KNOWLEDGE_BASE, args.model)
    
    print(f"🔍 搜索关键词: {keywords}")
    print(f"📁 知识库路径: {KNOWLEDGE_BASE}")
    print(f"🤖 AI 模型: {args.model}\n")
    
    matches = searcher.search(keywords, args.max)
    
    if not matches:
        print("❌ 未找到相关内容")
        return
    
    # 格式化结果
    formatted_results = searcher.format_search_results(matches)
    print(formatted_results)
    
    # AI 总结
    if not args.no_ai:
        searcher.generate_concept_summary(keywords, formatted_results)
    
    print("\n" + "="*60)
    print(f"✅ 完成！共找到 {len(matches)} 条匹配")
    print("="*60)

if __name__ == "__main__":
    main()
