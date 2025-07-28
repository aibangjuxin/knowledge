<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>团队时区时钟</title>
    <link rel="icon" href="https://vectorcraftr.com/library/blink/Young%20woman%20with%20headphones.svg" type="image/svg+xml" />
    <style>
      * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
      }
      
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%);
        background-size: 400% 400%;
        animation: gradientShift 15s ease infinite;
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 20px;
        position: relative;
        overflow-x: hidden;
      }
      
      @keyframes gradientShift {
        0% { background-position: 0% 50%; }
        50% { background-position: 100% 50%; }
        100% { background-position: 0% 50%; }
      }
      
      .background-pattern {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        opacity: 0.1;
        background-image: 
          radial-gradient(circle at 25% 25%, white 2px, transparent 2px),
          radial-gradient(circle at 75% 75%, white 2px, transparent 2px);
        background-size: 50px 50px;
        z-index: -1;
      }
      
      .header {
        text-align: center;
        margin-bottom: 40px;
        color: white;
        position: relative;
      }
      
      .header h1 {
        font-size: 3rem;
        margin-bottom: 15px;
        text-shadow: 2px 2px 8px rgba(0, 0, 0, 0.3);
        font-weight: 700;
        letter-spacing: -1px;
      }
      
      .header p {
        font-size: 1.2rem;
        opacity: 0.9;
        font-weight: 300;
      }
      
      .header::after {
        content: '';
        position: absolute;
        bottom: -10px;
        left: 50%;
        transform: translateX(-50%);
        width: 60px;
        height: 3px;
        background: linear-gradient(90deg, transparent, white, transparent);
        border-radius: 2px;
      }
      
      .clock-container {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 25px;
        max-width: 1400px;
        width: 100%;
        margin-bottom: 40px;
      }
      
      .clock-card {
        background: rgba(255, 255, 255, 0.95);
        border-radius: 20px;
        padding: 30px;
        box-shadow: 
          0 10px 40px rgba(0, 0, 0, 0.1),
          0 2px 8px rgba(0, 0, 0, 0.05);
        backdrop-filter: blur(20px);
        border: 1px solid rgba(255, 255, 255, 0.3);
        transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        position: relative;
        overflow: hidden;
      }
      
      .clock-card::before {
        content: '';
        position: absolute;
        top: 0;
        left: -100%;
        width: 100%;
        height: 100%;
        background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.4), transparent);
        transition: left 0.6s;
      }
      
      .clock-card:hover {
        transform: translateY(-8px) scale(1.02);
        box-shadow: 
          0 20px 60px rgba(0, 0, 0, 0.15),
          0 5px 20px rgba(0, 0, 0, 0.1);
      }
      
      .clock-card:hover::before {
        left: 100%;
      }
      
      .card-header {
        display: flex;
        align-items: center;
        margin-bottom: 20px;
        position: relative;
        z-index: 1;
      }
      
      .country-flag {
        font-size: 2.5rem;
        margin-right: 15px;
        filter: drop-shadow(2px 2px 4px rgba(0, 0, 0, 0.1));
      }
      
      .country-info {
        flex: 1;
      }
      
      .country-name {
        font-size: 1.5rem;
        font-weight: 700;
        color: #2c3e50;
        margin-bottom: 5px;
        letter-spacing: -0.5px;
      }
      
      .timezone-info {
        font-size: 0.9rem;
        color: #7f8c8d;
        font-weight: 500;
        background: rgba(127, 140, 141, 0.1);
        padding: 4px 8px;
        border-radius: 8px;
        display: inline-block;
      }
      
      .time-section {
        text-align: center;
        margin: 25px 0;
        position: relative;
        z-index: 1;
      }
      
      .time-display {
        font-size: 2.8rem;
        font-weight: 800;
        color: #2c3e50;
        margin-bottom: 8px;
        font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
        letter-spacing: -1px;
        text-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
      }
      
      .date-display {
        font-size: 1.1rem;
        color: #5a6c7d;
        margin-bottom: 15px;
        font-weight: 500;
      }
      
      .status-section {
        display: flex;
        justify-content: space-between;
        align-items: center;
        position: relative;
        z-index: 1;
      }
      
      .status-indicator {
        padding: 8px 16px;
        border-radius: 25px;
        font-size: 0.85rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
        transition: all 0.3s ease;
      }
      
      .working-hours {
        background: linear-gradient(135deg, #27ae60, #2ecc71);
        color: white;
      }
      
      .off-hours {
        background: linear-gradient(135deg, #e74c3c, #c0392b);
        color: white;
      }
      
      .current-timezone {
        background: linear-gradient(135deg, #f39c12, #e67e22);
        color: white;
        animation: pulse 2s infinite;
      }
      
      @keyframes pulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.05); }
      }
      
      .time-diff {
        font-size: 0.8rem;
        color: #95a5a6;
        font-weight: 500;
        background: rgba(149, 165, 166, 0.1);
        padding: 4px 8px;
        border-radius: 12px;
      }
      
      .stats-bar {
        background: rgba(255, 255, 255, 0.9);
        backdrop-filter: blur(10px);
        border-radius: 15px;
        padding: 20px;
        margin-bottom: 30px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
        display: flex;
        justify-content: space-around;
        flex-wrap: wrap;
        gap: 20px;
        max-width: 1400px;
        width: 100%;
      }
      
      .stat-item {
        text-align: center;
        flex: 1;
        min-width: 120px;
      }
      
      .stat-number {
        font-size: 2rem;
        font-weight: 800;
        color: #2c3e50;
        display: block;
      }
      
      .stat-label {
        font-size: 0.9rem;
        color: #7f8c8d;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }
      
      .footer {
        text-align: center;
        color: rgba(255, 255, 255, 0.9);
        font-size: 1rem;
        font-weight: 300;
      }
      
      .controls {
        position: fixed;
        bottom: 30px;
        right: 30px;
        display: flex;
        flex-direction: column;
        gap: 15px;
        z-index: 1000;
      }
      
      .control-btn {
        background: rgba(255, 255, 255, 0.95);
        border: none;
        border-radius: 50%;
        width: 60px;
        height: 60px;
        cursor: pointer;
        font-size: 1.4rem;
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.3);
      }
      
      .control-btn:hover {
        transform: scale(1.1) translateY(-2px);
        background: white;
        box-shadow: 0 8px 25px rgba(0, 0, 0, 0.2);
      }
      
      .control-btn:active {
        transform: scale(0.95);
      }
      
      @media (max-width: 768px) {
        .header h1 {
          font-size: 2.2rem;
        }
        
        .clock-container {
          grid-template-columns: 1fr;
          gap: 20px;
        }
        
        .time-display {
          font-size: 2.2rem;
        }
        
        .clock-card {
          padding: 25px;
        }
        
        .stats-bar {
          padding: 15px;
        }
        
        .controls {
          bottom: 20px;
          right: 20px;
        }
        
        .control-btn {
          width: 50px;
          height: 50px;
          font-size: 1.2rem;
        }
      }
      
      .theme-toggle {
        position: fixed;
        top: 30px;
        right: 30px;
        background: rgba(255, 255, 255, 0.2);
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 25px;
        padding: 8px 16px;
        color: white;
        cursor: pointer;
        font-size: 0.9rem;
        font-weight: 500;
        backdrop-filter: blur(10px);
        transition: all 0.3s ease;
      }
      
      .theme-toggle:hover {
        background: rgba(255, 255, 255, 0.3);
        transform: translateY(-2px);
      }
    </style>
  </head>
  <body>
    <div class="background-pattern"></div>
    
    <button class="theme-toggle" onclick="toggleTheme()" title="切换主题">
      🌙 深色模式
    </button>
    
    <div class="header">
      <h1>🌍 团队时区时钟</h1>
      <p>实时显示全球团队所在地区时间</p>
    </div>

    <div class="stats-bar" id="statsBar">
      <!-- 统计信息由 JS 动态生成 -->
    </div>

    <div class="clock-container" id="clockContainer">
      <!-- 时钟卡片由 JS 动态生成 -->
    </div>

    <div class="footer">
      <p>⏰ 页面每秒自动更新 | 实时同步全球时间</p>
    </div>

    <div class="controls">
      <button class="control-btn" onclick="toggleFullscreen()" title="全屏模式">
        📺
      </button>
      <button class="control-btn" onclick="updateAllClocks()" title="手动刷新">
        🔄
      </button>
    </div>

    <script>
      const timezones = [
        {
          name: "中国",
          flag: "🇨🇳",
          timezone: "Asia/Shanghai",
          workingHours: [9, 18],
        },
        {
          name: "印度",
          flag: "🇮🇳",
          timezone: "Asia/Kolkata",
          workingHours: [9, 18],
        },
        {
          name: "英国",
          flag: "🇬🇧",
          timezone: "Europe/London",
          workingHours: [9, 17],
        },
        {
          name: "UTC",
          flag: "🌐",
          timezone: "UTC",
          workingHours: [9, 18],
        },
        {
          name: "美国西海岸",
          flag: "🇺🇸",
          timezone: "America/Los_Angeles",
          workingHours: [9, 18],
        },
        {
          name: "当前位置",
          flag: "📍",
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          workingHours: [9, 18],
          isCurrent: true,
        },
      ];

      function getWorkingStatus(hour, workingHours, isCurrent = false) {
        if (isCurrent) return "current-timezone";
        return hour >= workingHours[0] && hour < workingHours[1]
          ? "working-hours"
          : "off-hours";
      }

      function getStatusText(hour, workingHours, isCurrent = false) {
        if (isCurrent) return "当前时区";
        return hour >= workingHours[0] && hour < workingHours[1]
          ? "工作时间"
          : "非工作时间";
      }

      function formatTime(date) {
        return date.toLocaleTimeString("zh-CN", {
          hour12: false,
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
        });
      }

      function formatDate(date) {
        return date.toLocaleDateString("zh-CN", {
          year: "numeric",
          month: "long",
          day: "numeric",
          weekday: "long",
        });
      }

      function createClockCard(timezone) {
        const now = new Date();
        const localTime = new Date(
          now.toLocaleString("en-US", { timeZone: timezone.timezone }),
        );
        const hour = localTime.getHours();
        
        // 计算与当前时区的时差
        const currentTime = new Date();
        const timeDiff = Math.round((localTime.getTime() - currentTime.getTime()) / (1000 * 60 * 60));
        const timeDiffText = timeDiff === 0 ? '本地时间' : 
          timeDiff > 0 ? `+${timeDiff}小时` : `${timeDiff}小时`;

        const statusClass = getWorkingStatus(
          hour,
          timezone.workingHours,
          timezone.isCurrent,
        );
        const statusText = getStatusText(
          hour,
          timezone.workingHours,
          timezone.isCurrent,
        );

        return `
        <div class="clock-card">
          <div class="card-header">
            <div class="country-flag">${timezone.flag}</div>
            <div class="country-info">
              <div class="country-name">${timezone.name}</div>
              <div class="timezone-info">${timezone.timezone}</div>
            </div>
          </div>
          
          <div class="time-section">
            <div class="time-display" data-timezone="${timezone.timezone}">
              ${formatTime(localTime)}
            </div>
            <div class="date-display" data-timezone="${timezone.timezone}">
              ${formatDate(localTime)}
            </div>
          </div>
          
          <div class="status-section">
            <div class="status-indicator ${statusClass}">
              ${statusText}
            </div>
            <div class="time-diff">
              ${timeDiffText}
            </div>
          </div>
        </div>
      `;
      }
      
      function createStatsBar() {
        const now = new Date();
        let workingCount = 0;
        let offCount = 0;
        
        timezones.forEach(timezone => {
          if (timezone.isCurrent) return;
          const localTime = new Date(
            now.toLocaleString("en-US", { timeZone: timezone.timezone })
          );
          const hour = localTime.getHours();
          
          if (hour >= timezone.workingHours[0] && hour < timezone.workingHours[1]) {
            workingCount++;
          } else {
            offCount++;
          }
        });
        
        return `
          <div class="stat-item">
            <span class="stat-number">${timezones.length}</span>
            <span class="stat-label">时区总数</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${workingCount}</span>
            <span class="stat-label">工作时间</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${offCount}</span>
            <span class="stat-label">非工作时间</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${formatTime(now)}</span>
            <span class="stat-label">本地时间</span>
          </div>
        `;
      }

      function updateAllClocks() {
        const container = document.getElementById("clockContainer");
        const statsContainer = document.getElementById("statsBar");
        
        container.innerHTML = timezones.map(createClockCard).join("");
        statsContainer.innerHTML = createStatsBar();
      }

      function updateTimes() {
        timezones.forEach((timezone) => {
          const now = new Date();
          const localTime = new Date(
            now.toLocaleString("en-US", { timeZone: timezone.timezone }),
          );
          const hour = localTime.getHours();

          const timeElements = document.querySelectorAll(
            `[data-timezone="${timezone.timezone}"]`,
          );
          timeElements.forEach((element) => {
            if (element.classList.contains("time-display")) {
              element.textContent = formatTime(localTime);
            } else if (element.classList.contains("date-display")) {
              element.textContent = formatDate(localTime);
            }
          });

          const card = timeElements[0]?.closest(".clock-card");
          if (card) {
            const statusElement = card.querySelector(".status-indicator");
            const statusClass = getWorkingStatus(
              hour,
              timezone.workingHours,
              timezone.isCurrent,
            );
            const statusText = getStatusText(
              hour,
              timezone.workingHours,
              timezone.isCurrent,
            );

            statusElement.className = `status-indicator ${statusClass}`;
            statusElement.textContent = statusText;
          }
        });
        
        // 更新统计信息
        const statsContainer = document.getElementById("statsBar");
        statsContainer.innerHTML = createStatsBar();
      }
      
      function toggleFullscreen() {
        if (!document.fullscreenElement) {
          document.documentElement.requestFullscreen().catch(err => {
            console.log(`Error attempting to enable fullscreen: ${err.message}`);
          });
        } else {
          document.exitFullscreen();
        }
      }
      
      function toggleTheme() {
        const body = document.body;
        const themeBtn = document.querySelector('.theme-toggle');
        
        if (body.style.filter === 'invert(1) hue-rotate(180deg)') {
          body.style.filter = '';
          themeBtn.textContent = '🌙 深色模式';
        } else {
          body.style.filter = 'invert(1) hue-rotate(180deg)';
          themeBtn.textContent = '☀️ 浅色模式';
        }
      }
      
      // 添加键盘快捷键
      document.addEventListener('keydown', function(e) {
        if (e.key === 'f' || e.key === 'F') {
          toggleFullscreen();
        } else if (e.key === 't' || e.key === 'T') {
          toggleTheme();
        } else if (e.key === 'r' || e.key === 'R') {
          updateAllClocks();
        }
      });

      updateAllClocks();
      setInterval(updateTimes, 1000);
      setInterval(updateAllClocks, 60000);
    </script>
  </body>
</html>
