能不能帮我写一个Python脚本,比如我输入类似的页面 
https://www.landofbasketball.com/games_between/lebron_james_vs_nikola_jokic.htm
其就是我关心这个人的对比结果?
然后帮我按照一定的格式输出一个对应的对比数据
比如我要的数据格式如下最好是Markdown格式的table
Date	Game Type	LeBron’s Team	Score (LeBron - Jokic)	LeBron’s Stats (Pts/Reb/Ass) Jokic’s Team	Jokic’s Stats (Pts/Reb/Ass)	Winner

eg:
python app.py https://www.landofbasketball.com/games_between/lebron_james_vs_nikola_jokic.htm


```python
import sys
import requests
from bs4 import BeautifulSoup
import pandas as pd
from tabulate import tabulate

def get_player_stats(url):
    # 发送HTTP请求获取页面内容
    response = requests.get(url)
    soup = BeautifulSoup(response.content, 'html.parser')
    
    # 找到包含比赛数据的表格
    table = soup.find('table', {'class': 'tblGames'})
    if not table:
        print("未找到比赛数据表格")
        return
    
    games_data = []
    # 遍历每一行数据
    for row in table.find_all('tr')[1:]:  # 跳过表头
        cols = row.find_all('td')
        if len(cols) >= 7:
            date = cols[0].text.strip()
            game_type = cols[1].text.strip()
            
            # 解析球队和比分
            teams_score = cols[2].text.strip()
            teams = teams_score.split('@') if '@' in teams_score else teams_score.split('vs')
            lebron_team = teams[0].strip()
            jokic_team = teams[1].strip()
            
            # 获取比分
            score = cols[3].text.strip()
            
            # 获取球员数据
            lebron_stats = cols[4].text.strip()
            jokic_stats = cols[5].text.strip()
            
            # 获取获胜方
            winner = cols[6].text.strip()
            
            games_data.append([
                date,
                game_type,
                lebron_team,
                score,
                lebron_stats,
                jokic_team,
                jokic_stats,
                winner
            ])
    
    # 创建DataFrame并转换为Markdown表格
    df = pd.DataFrame(games_data, columns=[
        'Date', 'Game Type', "LeBron's Team", 'Score (LeBron - Jokic)',
        "LeBron's Stats (Pts/Reb/Ass)", "Jokic's Team",
        "Jokic's Stats (Pts/Reb/Ass)", 'Winner'
    ])
    
    # 输出Markdown格式的表格
    print(tabulate(df, headers='keys', tablefmt='pipe', showindex=False))

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使用方法: python nba_compare.py <url>")
        sys.exit(1)
    
    url = sys.argv[1]
    get_player_stats(url)
```