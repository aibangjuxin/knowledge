https://github.com/0x4m4/hexstrike-ai



```bash
# 1. Clone the repository
git clone https://github.com/0x4m4/hexstrike-ai.git
cd hexstrike-ai

# 2. Create virtual environment (recommended)
python3 -m venv hexstrike-env
source hexstrike-env/bin/activate  # Linux/Mac
# hexstrike-env\Scripts\activate   # Windows

# 3. Install Python dependencies
pip3 install -r requirements.txt

# 4. Install Browser Agent dependencies
pip3 install selenium beautifulsoup4 mitmproxy
# Download ChromeDriver (or use webdriver-manager for automatic management)
pip3 install webdriver-manager
```