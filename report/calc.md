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

3. 创建 templates/index.html

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
