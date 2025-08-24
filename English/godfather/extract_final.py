#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import re

def extract_subtitles(input_file, output_file):
    """提取字幕文件中的英文和中文对话，格式为 "英文|中文" """
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"错误: 输入文件 '{input_file}' 不存在")
        return False
    except Exception as e:
        print(f"读取文件时出错: {e}")
        return False
    
    dialogues = []
    
    for line in lines:
        # 只处理包含对话的行
        if 'Dialogue:' in line and '\\rEng' in line:
            # 提取对话内容部分（在最后一个逗号之后的文本部分）
            parts = line.split(',')
            if len(parts) >= 10:
                dialogue_text = ','.join(parts[9:]).strip()
                
                # 移除开头的样式标签
                dialogue_text = re.sub(r'^\{[^}]*\}', '', dialogue_text)
                
                # 查找中英文分隔符 \N{\rEng}
                if '\\N{\\rEng}' in dialogue_text:
                    # 分离中文和英文
                    chinese_part, english_part = dialogue_text.split('\\N{\\rEng}', 1)
                    
                    # 清理中文部分 - 移除所有样式标签和换行符
                    chinese_part = re.sub(r'\{[^}]*\}', '', chinese_part).strip()
                    chinese_part = chinese_part.replace('\\N', ' ')
                    
                    # 清理英文部分 - 移除所有样式标签和换行符
                    english_part = re.sub(r'\{[^}]*\}', '', english_part).strip()
                    english_part = english_part.replace('\\N', ' ')
                    
                    # 只输出非空的对话
                    if chinese_part and english_part:
                        dialogues.append(f"{english_part}|{chinese_part}")
    
    # 写入输出文件
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            for dialogue in dialogues:
                f.write(dialogue + '\n')
        
        print(f"提取完成！结果保存在: {output_file}")
        print(f"共提取了 {len(dialogues)} 行对话")
        return True
        
    except Exception as e:
        print(f"写入文件时出错: {e}")
        return False

def main():
    if len(sys.argv) != 3:
        print("使用方法: python3 extract_final.py <输入字幕文件> <输出文件>")
        print("例如: python3 extract_final.py 1972.ass 1972.txt")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    extract_subtitles(input_file, output_file)

if __name__ == "__main__":
    main()