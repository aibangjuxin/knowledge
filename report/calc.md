```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GKE 成本计算器</title>
    <style>
        :root {
            --primary: #1a73e8;
            --primary-dark: #0d47a1;
            --secondary: #34a853;
            --light-bg: #f8f9fa;
            --border: #dadce0;
            --text: #202124;
            --text-secondary: #5f6368;
            --error: #ea4335;
            --shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
        }
        
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background-color: var(--light-bg);
            padding: 20px;
        }
        
        .container {
            max-width: 600px;
            margin: 0 auto;
            background-color: white;
            border-radius: 8px;
            box-shadow: var(--shadow);
            padding: 30px;
        }
        
        .header {
            margin-bottom: 30px;
            text-align: center;
        }
        
        .header h1 {
            color: var(--primary);
            font-size: 28px;
            margin-bottom: 10px;
        }
        
        .header p {
            color: var(--text-secondary);
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            margin-bottom: 6px;
            font-weight: 500;
            color: var(--text);
        }
        
        .input-group {
            display: flex;
            align-items: center;
        }
        
        input {
            width: 100%;
            padding: 12px 15px;
            border: 1px solid var(--border);
            border-radius: 4px;
            font-size: 16px;
            transition: border 0.2s;
        }
        
        input:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 2px rgba(26, 115, 232, 0.2);
        }
        
        .suffix {
            margin-left: 10px;
            color: var(--text-secondary);
            font-weight: 500;
            min-width: 40px;
        }
        
        .buttons {
            display: flex;
            justify-content: center;
            margin-top: 30px;
        }
        
        button {
            background-color: var(--primary);
            color: white;
            border: none;
            padding: 12px 25px;
            font-size: 16px;
            font-weight: 500;
            border-radius: 4px;
            cursor: pointer;
            transition: background-color 0.2s, transform 0.1s;
        }
        
        button:hover {
            background-color: var(--primary-dark);
        }
        
        button:active {
            transform: translateY(1px);
        }
        
        .reset-btn {
            background-color: transparent;
            color: var(--primary);
            margin-left: 15px;
        }
        
        .reset-btn:hover {
            background-color: rgba(26, 115, 232, 0.1);
        }
        
        .result {
            margin-top: 30px;
            text-align: center;
            padding: 20px;
            border-radius: 4px;
            background-color: var(--light-bg);
            display: none;
        }
        
        .result.show {
            display: block;
            animation: fadeIn 0.4s;
        }
        
        .result-value {
            font-size: 36px;
            font-weight: 600;
            color: var(--secondary);
            margin: 10px 0;
        }
        
        .result-details {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin-top: 20px;
            text-align: left;
        }
        
        .detail-item {
            padding: 10px;
            background-color: white;
            border-radius: 4px;
            border-left: 3px solid var(--primary);
        }
        
        .detail-label {
            font-size: 14px;
            color: var(--text-secondary);
        }
        
        .detail-value {
            font-weight: 500;
        }
        
        .error-message {
            color: var(--error);
            font-size: 14px;
            margin-top: 6px;
            display: none;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        @media (max-width: 600px) {
            .container {
                padding: 20px;
            }
            
            .result-details {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>GKE 成本计算器</h1>
            <p>计算您的 Google Kubernetes Engine 估计成本</p>
        </div>
        
        <div class="form-group">
            <label for="cpu">CPU 数量 (vCPU)</label>
            <div class="input-group">
                <input type="number" id="cpu" min="0" step="1" placeholder="输入CPU数量">
                <span class="suffix">vCPU</span>
            </div>
            <div class="error-message" id="cpu-error">请输入有效的CPU数量</div>
        </div>
        
        <div class="form-group">
            <label for="memory">内存大小</label>
            <div class="input-group">
                <input type="number" id="memory" min="0" step="0.5" placeholder="输入内存大小">
                <span class="suffix">GB</span>
            </div>
            <div class="error-message" id="memory-error">请输入有效的内存大小</div>
        </div>
        
        <div class="form-group">
            <label for="maxReplicas">最大副本数</label>
            <div class="input-group">
                <input type="number" id="maxReplicas" min="1" step="1" value="4" placeholder="输入最大副本数">
                <span class="suffix">个</span>
            </div>
            <div class="error-message" id="replicas-error">请输入至少1个副本</div>
        </div>
        
        <div class="buttons">
            <button id="calculate-btn" onclick="calculateCost()">计算成本</button>
            <button class="reset-btn" onclick="resetForm()">重置</button>
        </div>
        
        <div class="result" id="result-container">
            <h2>估计每月成本</h2>
            <div class="result-value" id="result">$0.00</div>
            
            <div class="result-details">
                <div class="detail-item">
                    <div class="detail-label">基础成本</div>
                    <div class="detail-value" id="base-cost">$180.00</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">资源成本</div>
                    <div class="detail-value" id="resource-cost">$0.00</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">CPU 成本</div>
                    <div class="detail-value" id="cpu-cost">$0.00</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">内存成本</div>
                    <div class="detail-value" id="memory-cost">$0.00</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        function validateInput(id, errorId, errorMessage) {
            const input = document.getElementById(id);
            const errorElement = document.getElementById(errorId);
            const value = parseFloat(input.value);
            
            if (isNaN(value) || value < 0 || input.value === '') {
                errorElement.textContent = errorMessage;
                errorElement.style.display = 'block';
                input.style.borderColor = 'var(--error)';
                return false;
            } else {
                errorElement.style.display = 'none';
                input.style.borderColor = 'var(--border)';
                return true;
            }
        }
        
        function calculateCost() {
            const cpuValid = validateInput('cpu', 'cpu-error', '请输入有效的CPU数量');
            const memoryValid = validateInput('memory', 'memory-error', '请输入有效的内存大小');
            const replicasValid = validateInput('maxReplicas', 'replicas-error', '请输入至少1个副本');
            
            if (!cpuValid || !memoryValid || !replicasValid) {
                return;
            }
            
            let cpu = parseFloat(document.getElementById("cpu").value) || 0;
            let memory = parseFloat(document.getElementById("memory").value) || 0;
            let maxReplicas = parseInt(document.getElementById("maxReplicas").value) || 4;
            
            let base_cost = 180;
            let cpu_cost = 19 * cpu * maxReplicas / 2;
            let memory_cost = 19 * memory * maxReplicas / 2;
            let resource_cost = cpu_cost + memory_cost;
            let total_cost = base_cost + resource_cost;
            
            document.getElementById("result").innerText = "$" + total_cost.toFixed(2);
            document.getElementById("base-cost").innerText = "$" + base_cost.toFixed(2);
            document.getElementById("resource-cost").innerText = "$" + resource_cost.toFixed(2);
            document.getElementById("cpu-cost").innerText = "$" + cpu_cost.toFixed(2);
            document.getElementById("memory-cost").innerText = "$" + memory_cost.toFixed(2);
            
            document.getElementById("result-container").classList.add("show");
        }
        
        function resetForm() {
            document.getElementById("cpu").value = "";
            document.getElementById("memory").value = "";
            document.getElementById("maxReplicas").value = "4";
            
            document.getElementById("cpu-error").style.display = 'none';
            document.getElementById("memory-error").style.display = 'none';
            document.getElementById("replicas-error").style.display = 'none';
            
            document.getElementById("cpu").style.borderColor = 'var(--border)';
            document.getElementById("memory").style.borderColor = 'var(--border)';
            document.getElementById("maxReplicas").style.borderColor = 'var(--border)';
            
            document.getElementById("result-container").classList.remove("show");
        }
    </script>
</body>
</html>
``` 
 是的，你可以很容易地使用GitHub Pages来发布这个静态页面。这是一种免费且简单的方法来托管你的GKE成本计算器。以下是具体步骤：

### 使用GitHub Pages发布静态页面

1. **创建GitHub账户**（如果你还没有）

2. **创建新仓库**
   - 登录GitHub并点击右上角的"+"图标
   - 选择"New repository"
   - 为仓库命名，例如"gke-cost-calculator"
   - 保持仓库为"Public"（GitHub Pages需要公开仓库，除非你使用GitHub Pro）
   - 点击"Create repository"

3. **上传HTML文件**
   - 在新创建的仓库中，点击"Add file" > "Upload files"
   - 将我们之前创建的HTML文件拖拽到上传区域
   - 重命名为"index.html"（这很重要，因为GitHub Pages会将其作为默认页面）
   - 点击"Commit changes"

4. **启用GitHub Pages**
   - 在仓库页面，点击"Settings"
   - 向下滚动到"GitHub Pages"部分
   - 在"Source"下拉菜单中，选择"main"分支
   - 点击"Save"
   - GitHub会显示你的页面URL，通常是 `https://你的用户名.github.io/gke-cost-calculator/`

5. **访问你的页面**
   - 几分钟后，你的GKE成本计算器将在提供的URL上可用
   - 你可以将此URL嵌入到Google Dashboard中

### 进一步改进（可选）

1. **添加自定义域名**
   - 在仓库设置的GitHub Pages部分，你可以配置自定义域名
   - 这样你的计算器URL可以是 `https://calculator.yourdomain.com`

2. **使用分支管理更新**
   - 创建开发分支进行更改
   - 测试后再合并到main分支发布

3. **添加README文件**
   - 解释计算器的用途和使用方法
   - 提供有关计算公式的信息

4. **使用版本控制**
   - 利用GitHub的版本控制功能跟踪对计算器的更改

GitHub Pages是一个非常适合托管这类简单静态工具的平台，它提供了免费、可靠的托管，并且与GitHub的版本控制功能无缝集成，便于你管理和更新计算器。​​​​​​​​​​​​​​​​



如果要快速搭建一个简单的页面，类似 Google 产品的计费页面，可以考虑以下方案：

方案 1：Streamlit（Python 快速构建 Web 应用）

如果你的公式是 Python 可计算的，Streamlit 是一个非常适合的工具。它可以用极少的代码快速构建交互式 Web 页面，不需要复杂的前端开发。

实现步骤
	1.	安装 Streamlit：

pip install streamlit


	2.	编写 app.py：

import streamlit as st

# 页面标题
st.title("GKE 计费计算器")

# 输入参数
cpu = st.number_input("CPU 数量 (vCPU)", min_value=0.1, step=0.1)
memory = st.number_input("内存大小 (GB)", min_value=0.5, step=0.5)
storage = st.number_input("存储大小 (GB)", min_value=1, step=1)

# 计算公式（示例）
price_per_cpu = 0.031  # 假设 vCPU 每小时单价
price_per_mem = 0.004  # 假设每 GB 内存单价
price_per_storage = 0.0002  # 假设每 GB 存储单价

cost = (cpu * price_per_cpu) + (memory * price_per_mem) + (storage * price_per_storage)

# 显示结果
if st.button("计算"):
    st.success(f"预计每小时成本: ${cost:.4f}")


	3.	运行：

streamlit run app.py


	4.	访问 http://localhost:8501，就能看到页面。

⸻

方案 2：Flask + HTML（轻量 Python API）

如果你更倾向于用 Python API，然后用简单的 HTML 页面来渲染，也可以用 Flask 快速实现。

1. 安装 Flask

pip install flask

2. 创建 app.py
```python
from flask import Flask, request, jsonify, render_template

app = Flask(__name__)

# 计费计算逻辑
def calculate_cost(cpu, memory, storage):
    price_per_cpu = 0.031
    price_per_mem = 0.004
    price_per_storage = 0.0002
    return (cpu * price_per_cpu) + (memory * price_per_mem) + (storage * price_per_storage)

# 首页
@app.route("/")
def index():
    return render_template("index.html")

# 计算接口
@app.route("/calculate", methods=["POST"])
def calculate():
    data = request.json
    cost = calculate_cost(data["cpu"], data["memory"], data["storage"])
    return jsonify({"cost": round(cost, 4)})

if __name__ == "__main__":
    app.run(debug=True)
```
3. 创建 templates/index.html
```html
<!DOCTYPE html>
<html>
<head>
    <title>GKE 计费计算器</title>
    <script>
        async function calculateCost() {
            let cpu = parseFloat(document.getElementById("cpu").value);
            let memory = parseFloat(document.getElementById("memory").value);
            let storage = parseFloat(document.getElementById("storage").value);
            
            let response = await fetch("/calculate", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ cpu, memory, storage })
            });

            let data = await response.json();
            document.getElementById("result").innerText = "预计每小时成本: $" + data.cost.toFixed(4);
        }
    </script>
</head>
<body>
    <h2>GKE 计费计算器</h2>
    <label>CPU 数量 (vCPU):</label> <input id="cpu" type="number" step="0.1"><br>
    <label>内存大小 (GB):</label> <input id="memory" type="number" step="0.5"><br>
    <label>存储大小 (GB):</label> <input id="storage" type="number" step="1"><br>
    <button onclick="calculateCost()">计算</button>
    <p id="result"></p>
</body>
</html>
```
4. 运行

python app.py

然后访问 http://127.0.0.1:5000，输入参数后点击 “计算” 按钮即可。

⸻

选择哪种方案？

方案	适用场景	依赖	实现复杂度
Streamlit	适合快速构建交互页面，无需前端开发	仅 streamlit	非常简单
Flask + HTML	适合 API + 前端分离的架构，可定制 UI	flask	需要写 HTML 和 JS

如果是内部工具，Streamlit 更快。如果希望页面自定义，Flask + HTML 更灵活。

你觉得哪种方案更合适？


如果想结合 Google 的产品，或者纯 HTML + JS 实现，可以有以下几种方式：

方案 1：Cloud Run + Cloud Functions（结合 Google Cloud）

如果你的计算公式是后端逻辑，可以部署在 Google Cloud 上，然后前端用 HTML + JS 调用 API。

1. 创建 Cloud Function

使用 Cloud Functions 提供一个 HTTP 端点，计算成本并返回 JSON。

Python 代码（main.py）

from flask import Flask, request, jsonify

app = Flask(__name__)

# 计算逻辑
def calculate_cost(cpu, memory, storage):
    price_per_cpu = 0.031
    price_per_mem = 0.004
    price_per_storage = 0.0002
    return (cpu * price_per_cpu) + (memory * price_per_mem) + (storage * price_per_storage)

@app.route("/", methods=["POST"])
def calculate():
    data = request.json
    cost = calculate_cost(data["cpu"], data["memory"], data["storage"])
    return jsonify({"cost": round(cost, 4)})

def main(request):
    return calculate()

if __name__ == "__main__":
    app.run()

部署到 Cloud Functions

gcloud functions deploy gke-cost-calculator --runtime python311 --trigger-http --allow-unauthenticated

这样，你会得到一个 Google Cloud Functions 的 URL，比如：

https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/gke-cost-calculator

2. 纯 HTML + JS 前端

你的 HTML 直接调用这个 API 计算：
```html
<!DOCTYPE html>
<html>
<head>
    <title>GKE 计费计算器</title>
    <script>
        async function calculateCost() {
            let cpu = parseFloat(document.getElementById("cpu").value);
            let memory = parseFloat(document.getElementById("memory").value);
            let storage = parseFloat(document.getElementById("storage").value);

            let response = await fetch("https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/gke-cost-calculator", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ cpu, memory, storage })
            });

            let data = await response.json();
            document.getElementById("result").innerText = "预计每小时成本: $" + data.cost.toFixed(4);
        }
    </script>
</head>
<body>
    <h2>GKE 计费计算器</h2>
    <label>CPU 数量 (vCPU):</label> <input id="cpu" type="number" step="0.1"><br>
    <label>内存大小 (GB):</label> <input id="memory" type="number" step="0.5"><br>
    <label>存储大小 (GB):</label> <input id="storage" type="number" step="1"><br>
    <button onclick="calculateCost()">计算</button>
    <p id="result"></p>
</body>
</html>
```
最终效果
	•	这个 HTML 页面可以直接在 Cloud Storage 作为静态网站 托管。
	•	用户输入 CPU、内存、存储大小，前端调用 Google Cloud Functions 计算费用并返回结果。
	•	不需要搭建服务器，直接依赖 Google Cloud，容易扩展。

⸻

方案 2：纯 HTML + JS（无后端，直接浏览器计算）

如果你的计算公式很简单，可以直接用 纯 HTML + JavaScript 计算，不依赖任何后端。

1. 直接 HTML + JS 代码

<!DOCTYPE html>
<html>
<head>
    <title>GKE 计费计算器</title>
    <script>
        function calculateCost() {
            let cpu = parseFloat(document.getElementById("cpu").value) || 0;
            let memory = parseFloat(document.getElementById("memory").value) || 0;
            let storage = parseFloat(document.getElementById("storage").value) || 0;

            let price_per_cpu = 0.031;
            let price_per_mem = 0.004;
            let price_per_storage = 0.0002;

            let cost = (cpu * price_per_cpu) + (memory * price_per_mem) + (storage * price_per_storage);
            document.getElementById("result").innerText = "预计每小时成本: $" + cost.toFixed(4);
        }
    </script>
</head>
<body>
    <h2>GKE 计费计算器</h2>
    <label>CPU 数量 (vCPU):</label> <input id="cpu" type="number" step="0.1"><br>
    <label>内存大小 (GB):</label> <input id="memory" type="number" step="0.5"><br>
    <label>存储大小 (GB):</label> <input id="storage" type="number" step="1"><br>
    <button onclick="calculateCost()">计算</button>
    <p id="result"></p>
</body>
</html>

2. 部署方式

你可以：
	1.	本地使用：直接双击 HTML 文件，浏览器打开即可。
	2.	托管到 Cloud Storage：

gsutil mb gs://your-bucket-name
gsutil cp index.html gs://your-bucket-name
gsutil acl ch -u AllUsers:R gs://your-bucket-name/index.html
gcloud storage buckets update gs://your-bucket-name --website-main-page index.html

这样 https://storage.googleapis.com/your-bucket-name/index.html 直接访问即可。

⸻

方案 3：使用 Google Sheets 作为计算引擎

如果你的计算规则可能会动态调整，可以直接使用 Google Sheets + Apps Script 作为计算后端：
	1.	创建 Google Sheets，并定义 A1 B1 C1 作为输入，D1 计算公式：

=A1 * 0.031 + B1 * 0.004 + C1 * 0.0002


	2.	在 Google Apps Script 创建 API：

function doGet(e) {
    var sheet = SpreadsheetApp.openById("YOUR_SHEET_ID").getActiveSheet();
    sheet.getRange("A1").setValue(e.parameter.cpu);
    sheet.getRange("B1").setValue(e.parameter.memory);
    sheet.getRange("C1").setValue(e.parameter.storage);
    var cost = sheet.getRange("D1").getValue();
    return ContentService.createTextOutput(JSON.stringify({cost: cost})).setMimeType(ContentService.MimeType.JSON);
}


	3.	部署成 Web API，并用 JavaScript 调用：

let url = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec?cpu=2&memory=4&storage=100";
fetch(url).then(response => response.json()).then(data => console.log(data.cost));



这样，你的计算规则可以随时修改，不用改代码。

⸻

最终选择

方案	适用场景	依赖	部署方式
Cloud Run + Cloud Functions	适合计算较复杂，前后端分离	需要 GCP	部署到 Google Cloud
纯 HTML + JS	适合简单计算	无依赖	直接打开 HTML
Google Sheets + Apps Script	适合经常改计算规则	Google Sheets	作为 Web API

	•	想快速上线？→ 方案 2（纯 HTML + JS）
	•	想结合 Google Cloud？→ 方案 1（Cloud Functions）
	•	想让非技术人员修改公式？→ 方案 3（Google Sheets）

你更倾向哪个方案？
