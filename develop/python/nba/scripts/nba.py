#!/opt/homebrew/bin/python3
import sys
import requests
from bs4 import BeautifulSoup
import re
from datetime import datetime

def scrape_player_matchup(url):
    # 获取网页内容
    response = requests.get(url)
    if response.status_code != 200:
        print(f"错误: 无法访问页面，状态码: {response.status_code}")
        return None
    
    soup = BeautifulSoup(response.text, 'html.parser')
    
    # 获取标题（哪两位球员的对决）
    title = soup.find('h1').text.strip()
    
    # 获取球员的对决总体统计
    summary_div = soup.find('div', class_='center')
    summary_text = summary_div.get_text(strip=True) if summary_div else ""
    # 提取对决次数
    num_games_match = re.search(r'Games:\s*(\d+)', summary_text)
    num_games = num_games_match.group(1) if num_games_match else "N/A"
    
    # 提取球员名字
    players = re.findall(r'([A-Za-z\s]+\w+):', summary_text)
    player1 = players[0] if len(players) > 0 else "Player 1"
    player2 = players[1] if len(players) > 1 else "Player 2"
    
    # 获取详细对决表格
    tables = soup.find_all('table', class_='center')
    
    # 存储每场比赛的数据
    games_data = []
    
    if tables and len(tables) >= 2:
        # 第二个表格通常包含详细比赛记录
        games_table = tables[1]
        rows = games_table.find_all('tr')
        
        # 跳过表头，处理每一行
        for row in rows[1:]:
            cols = row.find_all('td')
            if len(cols) >= 10:
                date_str = cols[0].text.strip()
                try:
                    # 转换日期格式
                    date_obj = datetime.strptime(date_str, '%b %d, %Y')
                    date = date_obj.strftime('%Y-%m-%d')
                except:
                    date = date_str
                
                # 提取比赛信息
                game_info = {
                    'date': date,
                    'player1_team': cols[1].text.strip(),
                    'player2_team': cols[2].text.strip(),
                    'result': cols[3].text.strip(),
                    'player1_stats': cols[4].text.strip(),
                    'player2_stats': cols[5].text.strip()
                }
                games_data.append(game_info)
    
    # 生成Markdown表格
    markdown = f"# {title}\n\n"
    markdown += f"总计比赛次数: {num_games}\n\n"
    
    # 创建表格头部
    markdown += f"| 日期 | {player1}队伍 | {player2}队伍 | 比赛结果 | {player1}数据 | {player2}数据 |\n"
    markdown += "| --- | --- | --- | --- | --- | --- |\n"
    
    # 添加每一行数据
    for game in games_data:
        markdown += f"| {game['date']} | {game['player1_team']} | {game['player2_team']} | {game['result']} | {game['player1_stats']} | {game['player2_stats']} |\n"
    
    return markdown

def main():
    if len(sys.argv) != 2:
        print("用法: python a.py <url>")
        print("例如: python a.py https://www.landofbasketball.com/games_between/lebron_james_vs_nikola_jokic.htm")
        return
    
    url = sys.argv[1]
    markdown = scrape_player_matchup(url)
    
    if markdown:
        print(markdown)
        
        # 将结果保存到文件
        output_file = "player_matchup.md"
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(markdown)
        print(f"\n结果已保存到 {output_file}")

if __name__ == "__main__":
    main()
