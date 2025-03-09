#!/opt/homebrew/bin/python3
import sys
import csv
import requests
from bs4 import BeautifulSoup

def fetch_data(url):
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as e:
        print(f"请求错误: {e}")
        sys.exit(1)

def parse_data(html):
    soup = BeautifulSoup(html, 'html.parser')
    data = {
        'total_games': '',
        'victories': [],
        'averages': [],
        'game_highs': [],
        'detailed_games': []
    }

    # 解析总场数
    total_games = soup.find('h3', string='Games Played Against Each Other')
    if total_games:
        data['total_games'] = total_games.find_next('p').get_text(strip=True)

    # 解析胜负统计
    tables = soup.find_all('table')
    for table in tables:
        if 'Summary of Victories' in str(table):
            rows = table.find_all('tr')
            data['victories'] = [[td.get_text(strip=True) for td in row.find_all('td')] 
                                for row in rows[1:]]

        elif 'Stats in Games Between Them' in str(table):
            sections = table.find_all('table')
            # 解析场均数据
            avg_rows = sections[0].find_all('tr')[1:]
            data['averages'] = [[td.get_text(strip=True) for td in row.find_all('td')] 
                              for row in avg_rows]
            
            # 解析单场最高
            high_rows = sections[1].find_all('tr')[1:]
            data['game_highs'] = [[td.get_text(strip=True) for td in row.find_all('td')] 
                                for row in high_rows]

    return data

def output_markdown(data):
    md = "## 球员对战数据分析\n\n"
    md += f"**总交手场次**: {data['total_games']}\n\n"
    
    md += "### 胜场统计\n"
    md += "| | 常规赛 | 季后赛 | 附加赛 |\n"
    md += "|---|---|---|---|\n"
    for row in data['victories']:
        md += f"| {'|'.join(row)} |\n"
    
    md += "\n### 场均数据\n"
    md += "| 球员 | 得分 | 篮板 | 助攻 | 抢断 | 盖帽 |\n"
    md += "|---|---|---|---|---|---|\n"
    for row in data['averages']:
        md += f"| {'|'.join(row)} |\n"
    
    md += "\n### 单场最高\n"
    md += "| 球员 | 得分 | 篮板 | 助攻 | 抢断 | 盖帽 |\n"
    md += "|---|---|---|---|---|---|\n"
    for row in data['game_highs']:
        md += f"| {'|'.join(row)} |\n"
    
    return md

def save_to_csv(data, filename):
    with open(filename, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(['类型', '库里数据', '詹姆斯数据'])
        
        # 写入胜场统计
        for row in data['victories']:
            writer.writerow([row[0], row[1], row[2]])
        
        # 写入场均数据
        for row in data['averages']:
            writer.writerow([row[0], '|'.join(row[1:6]), '|'.join(row[6:])])
        
        # 写入单场最高
        for row in data['game_highs']:
            writer.writerow([row[0], '|'.join(row[1:6]), '|'.join(row[6:])])

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使用方法: python a.py <URL>")
        sys.exit(1)
    
    url = sys.argv[1]
    html = fetch_data(url)
    data = parse_data(html)
    
    # 输出Markdown
    print("\nMarkdown格式输出:")
    print(output_markdown(data))
    
    # 保存CSV
    csv_filename = 'comparison_data.csv'
    save_to_csv(data, csv_filename)
    print(f"\nCSV文件已保存为: {csv_filename}")
