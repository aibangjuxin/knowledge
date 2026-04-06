#!/opt/homebrew/Caskroom/miniconda/base/bin/python
"""
快速知识库检索工具 - 不使用 AI
"""

import subprocess
import json
import sys
import argparse
from pathlib import Path
from typing import List, Dict
from collections import defaultdict

KNOWLEDGE_BASE = "/Users/lex/git/knowledge"
RG_PATH = "/opt/homebrew/bin/rg"

def search_knowledge(keywords: str, max_results: int = 30) -> List[Dict]:
    """使用 ripgrep 搜索"""
    cmd = [
        RG_PATH,
        "--json",
        "--max-count", "5",  # 每个文件最多5条
        "--ignore-case",
        "--type-add", "md:*.md",
        "--type", "md",
        keywords,
        KNOWLEDGE_BASE
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
                        'line': match_data['lines']['text'].strip()
                    })
            except json.JSONDecodeError:
                continue
        
        return matches[:max_results]
    except Exception as e:
        print(f"搜索错误: {e}", file=sys.stderr)
        return []

def display_results(matches: List[Dict], keywords: str):
    """显示搜索结果"""
    if not matches:
        print("❌ 未找到相关内容")
        return
    
    # 按文件分组
    files_dict = defaultdict(list)
    for match in matches:
        file_path = match['file']
        files_dict[file_path].append(match)
    
    print(f"\n{'='*70}")
    print(f"🔍 搜索: {keywords}")
    print(f"📊 找到 {len(matches)} 条匹配，分布在 {len(files_dict)} 个文件中")
    print(f"{'='*70}\n")
    
    # 显示文件列表
    print("📁 相关文件:\n")
    for idx, (file_path, file_matches) in enumerate(files_dict.items(), 1):
        rel_path = Path(file_path).relative_to(KNOWLEDGE_BASE)
        print(f"{idx:2d}. {rel_path} ({len(file_matches)} 条匹配)")
    
    print(f"\n{'='*70}")
    print("📝 匹配内容预览:\n")
    
    # 显示每个文件的匹配内容
    for file_path, file_matches in list(files_dict.items())[:10]:
        rel_path = Path(file_path).relative_to(KNOWLEDGE_BASE)
        print(f"\n▶ {rel_path}")
        print("-" * 70)
        
        for match in file_matches[:3]:  # 每个文件最多显示3条
            line_preview = match['line'][:120]
            if len(match['line']) > 120:
                line_preview += "..."
            print(f"  行 {match['line_number']:4d}: {line_preview}")
    
    print(f"\n{'='*70}")
    print("💡 建议:")
    
    # 智能建议
    categories = categorize_files(files_dict.keys())
    if categories:
        print("\n  主题分类:")
        for category, count in sorted(categories.items(), key=lambda x: x[1], reverse=True)[:5]:
            print(f"    • {category}: {count} 个文件")
    
    # 推荐文件
    top_files = sorted(files_dict.items(), key=lambda x: len(x[1]), reverse=True)[:3]
    print("\n  推荐深入阅读:")
    for file_path, file_matches in top_files:
        rel_path = Path(file_path).relative_to(KNOWLEDGE_BASE)
        print(f"    • {rel_path} ({len(file_matches)} 条匹配)")
    
    # 相关搜索建议
    related_keywords = suggest_related_keywords(keywords, matches)
    if related_keywords:
        print("\n  相关搜索:")
        for kw in related_keywords[:5]:
            print(f"    • {kw}")
    
    print(f"\n{'='*70}\n")

def categorize_files(file_paths) -> Dict[str, int]:
    """根据文件路径分类"""
    categories = defaultdict(int)
    for file_path in file_paths:
        parts = Path(file_path).relative_to(KNOWLEDGE_BASE).parts
        if parts:
            category = parts[0]
            categories[category] += 1
    return dict(categories)

def suggest_related_keywords(keywords: str, matches: List[Dict]) -> List[str]:
    """基于匹配内容建议相关关键词"""
    # 简单的关键词提取
    common_terms = set()
    keywords_lower = keywords.lower()
    
    for match in matches[:20]:  # 只分析前20条
        line = match['line'].lower()
        # 提取可能的技术术语（简单实现）
        words = line.split()
        for word in words:
            if len(word) > 3 and word not in keywords_lower:
                # 简单过滤
                if any(c.isalnum() for c in word):
                    common_terms.add(word.strip('.,;:()[]{}'))
    
    # 返回一些常见的相关术语
    related = []
    tech_keywords = {
        'nginx': ['proxy_pass', 'upstream', 'location', 'server'],
        'gke': ['ingress', 'service', 'deployment', 'pod'],
        'kong': ['plugin', 'route', 'service', 'upstream'],
        'istio': ['virtualservice', 'gateway', 'destinationrule'],
        'kubernetes': ['deployment', 'service', 'configmap', 'secret'],
    }
    
    for key, suggestions in tech_keywords.items():
        if key in keywords_lower:
            related.extend([s for s in suggestions if s not in keywords_lower])
    
    return related[:5]

def main():
    parser = argparse.ArgumentParser(
        description="快速知识库检索工具",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('keywords', nargs='+', help='搜索关键词')
    parser.add_argument('--max', type=int, default=30, help='最大结果数 (默认: 30)')
    
    args = parser.parse_args()
    keywords = ' '.join(args.keywords)
    
    matches = search_knowledge(keywords, args.max)
    display_results(matches, keywords)

if __name__ == "__main__":
    main()
