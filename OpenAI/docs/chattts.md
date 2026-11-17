使用ChatTTS实现文本转语音功能，需要进行以下步骤：

## 1. 准备环境
- **安装Python和Git**：确保你的Mac上安装了Python（建议3.9或更高版本）和Git[6]。
- **安装Miniconda**：前往Conda官网下载并安装Miniconda[3]。

## 2. 克隆仓库
- **克隆ChatTTS-WebUI仓库**：
  ```bash
  git clone https://github.com/yuhaolove/ChatTTS-WebUI.git
  ```
- **进入仓库目录**：
  ```bash
  cd ChatTTS-WebUI
  ```
- **克隆ChatTTS仓库**：
  ```bash
  git clone https://github.com/2noise/ChatTTS.git
  ```

## 3. 创建虚拟环境
- **创建并激活虚拟环境**：
  ```bash
  conda create -n chattts_webui python=3.12.3
  conda activate chattts_webui
  ```
- process
```bash
conda create -n chattts_webui python=3.12.3
Channels:
 - defaults
Platform: osx-arm64
Collecting package metadata (repodata.json): done
Solving environment: done

## Package Plan ##

  environment location: /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui

  added / updated specs:
    - python=3.12.3


The following packages will be downloaded:

    package                    |            build
    ---------------------------|-----------------
    pip-25.0                   |  py312hca03da5_0         2.8 MB
    python-3.12.3              |       h99e199e_1        14.0 MB
    setuptools-75.8.0          |  py312hca03da5_0         2.2 MB
    tzdata-2025a               |       h04d1e81_0         117 KB
    wheel-0.45.1               |  py312hca03da5_0         148 KB
    xz-5.6.4                   |       h80987f9_1         289 KB
    ------------------------------------------------------------
                                           Total:        19.6 MB

The following NEW packages will be INSTALLED:

  bzip2              pkgs/main/osx-arm64::bzip2-1.0.8-h80987f9_6 
  ca-certificates    pkgs/main/osx-arm64::ca-certificates-2024.12.31-hca03da5_0 
  expat              pkgs/main/osx-arm64::expat-2.6.4-h313beb8_0 
  libcxx             pkgs/main/osx-arm64::libcxx-14.0.6-h848a8c0_0 
  libffi             pkgs/main/osx-arm64::libffi-3.4.4-hca03da5_1 
  ncurses            pkgs/main/osx-arm64::ncurses-6.4-h313beb8_0 
  openssl            pkgs/main/osx-arm64::openssl-3.0.15-h80987f9_0 
  pip                pkgs/main/osx-arm64::pip-25.0-py312hca03da5_0 
  python             pkgs/main/osx-arm64::python-3.12.3-h99e199e_1 
  readline           pkgs/main/osx-arm64::readline-8.2-h1a28f6b_0 
  setuptools         pkgs/main/osx-arm64::setuptools-75.8.0-py312hca03da5_0 
  sqlite             pkgs/main/osx-arm64::sqlite-3.45.3-h80987f9_0 
  tk                 pkgs/main/osx-arm64::tk-8.6.14-h6ba3021_0 
  tzdata             pkgs/main/noarch::tzdata-2025a-h04d1e81_0 
  wheel              pkgs/main/osx-arm64::wheel-0.45.1-py312hca03da5_0 
  xz                 pkgs/main/osx-arm64::xz-5.6.4-h80987f9_1 
  zlib               pkgs/main/osx-arm64::zlib-1.2.13-h18a0788_1 


Proceed ([y]/n)? y


Downloading and Extracting Packages:
                                                                                                                                                                                           
Preparing transaction: done                                                                                                                                                                
Verifying transaction: done                                                                                                                                                                
Executing transaction: done                                                                                                                                                                
#                                                                                                                                                                                          
# To activate this environment, use                                                                                                                                                        
#
#     $ conda activate chattts_webui
#
# To deactivate an active environment, use
#
#     $ conda deactivate

conda activate chattts_webui 当我执行这个报错

CondaError: Run 'conda init' before 'conda activate'


conda init
no change     /opt/homebrew/Caskroom/miniconda/base/condabin/conda
no change     /opt/homebrew/Caskroom/miniconda/base/bin/conda
no change     /opt/homebrew/Caskroom/miniconda/base/bin/conda-env
no change     /opt/homebrew/Caskroom/miniconda/base/bin/activate
no change     /opt/homebrew/Caskroom/miniconda/base/bin/deactivate
no change     /opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh
no change     /opt/homebrew/Caskroom/miniconda/base/etc/fish/conf.d/conda.fish
no change     /opt/homebrew/Caskroom/miniconda/base/shell/condabin/Conda.psm1
no change     /opt/homebrew/Caskroom/miniconda/base/shell/condabin/conda-hook.ps1
no change     /opt/homebrew/Caskroom/miniconda/base/lib/python3.12/site-packages/xontrib/conda.xsh
no change     /opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.csh
modified      /Users/lex/.bash_profile

==> For changes to take effect, close and re-open your current shell. <==



这个错误出现是因为 conda 还没有正确初始化到你的 shell 环境中。虽然你已经运行了 `conda init`，但是看到输出提示：

```bash
modified      /Users/lex/.bash_profile
==> For changes to take effect, close and re-open your current shell. <==
```

要解决这个问题，你需要：

1. 关闭当前的终端窗口
2. 重新打开一个新的终端窗口
或者，你也可以在当前终端中执行以下命令来立即生效：

```bash
source ~/.bash_profile
source ~/.bash_profile
cd
cd git/ChatTTS-WebUI/
pwd
/Users/lex/git/ChatTTS-WebUI
conda activate chattts_webui

```

这样就可以让 conda 的初始化设置生效，之后就可以正常使用 `conda activate chattts_webui` 命令了。

如果你使用的是其他 shell（比如 zsh），可能需要修改对应的配置文件：

```bash
# 如果使用 zsh
source ~/.zshrc
```

这个错误是很常见的，主要是因为 conda 需要在 shell 环境中设置一些必要的环境变量和路径，而这些设置需要通过重新加载配置文件或重启终端才能生效。
```



## 4. 安装依赖
- **安装ChatTTS依赖**：
  ```bash
  cd ChatTTS
  pip install -r requirements.txt 报错

    which pip3
    /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/pip3 
    fix command
    /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/pip3  install -r requirements.txt
  cd ..
  ```
- **安装WebUI依赖**：
  ```bash
  #pip install -r requirements.txt
  Using next command 
  /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/pip3 install -r requirements.txt
  ```

## 5. 下载模型文件
- **自动下载模型文件**：通常会在运行时自动下载。如果网络不佳，可以手动下载并放置在`models`目录中[3]。
启动失败 需要下载模型
```bash
Load models from snapshot.
Traceback (most recent call last):
  File "/Users/lex/git/ChatTTS-WebUI/webui/main.py", line 39, in <module>
    chat.load_models()
    ^^^^^^^^^^^^^^^^
AttributeError: 'Chat' object has no attribute 'load_models'. Did you mean: 'download_models'?
```
- pwd
/Users/lex/git/ChatTTS-WebUI/ChatTTS/ChatTTS/model
- pwd
/Users/lex/git/ChatTTS-WebUI/ChatTTS/ChatTTS/model
- git lfs install
Updated Git hooks.
Git LFS initialized.
- git clone https://www.modelscope.cn/ai-modelscope/chattts.git 
Cloning into 'chattts'...
remote: Enumerating objects: 72, done.
remote: Counting objects: 100% (72/72), done.
remote: Compressing objects: 100% (69/69), done.
remote: Total 72 (delta 15), reused 0 (delta 0), pack-reused 0
Receiving objects: 100% (72/72), 115.68 KiB | 1.43 MiB/s, done.
Resolving deltas: 100% (15/15), done.
Filtering content: 100% (12/12), 2.20 GiB | 15.33 MiB/s, done.
- will clone do directory chattts
```bash
pwd
/Users/lex/git/ChatTTS-WebUI/ChatTTS/ChatTTS/model/chattts
tree
.
├── README.md
├── asset
│   ├── DVAE.pt
│   ├── DVAE.safetensors
│   ├── DVAE_full.pt
│   ├── Decoder.pt
│   ├── Decoder.safetensors
│   ├── Embed.safetensors
│   ├── GPT.pt
│   ├── Vocos.pt
│   ├── Vocos.safetensors
│   ├── gpt
│   │   ├── config.json
│   │   └── model.safetensors
│   ├── spk_stat.pt
│   ├── tokenizer
│   │   ├── special_tokens_map.json
│   │   ├── tokenizer.json
│   │   └── tokenizer_config.json
│   └── tokenizer.pt
├── config
│   ├── decoder.yaml
│   ├── dvae.yaml
│   ├── gpt.yaml
│   ├── path.yaml
│   └── vocos.yaml
└── configuration.json

5 directories, 23 files
du -sh *
4.0K	README.md
2.2G	asset
 20K	config
4.0K	configuration.json
```

## 6. 启动WebUI
- **启动WebUI**：
  ```bash
  python webui/main.py

    pwd
    /Users/lex/git/ChatTTS-WebUI

    which python3
    /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/python3

    /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/python3 webui/main.py

    /opt/homebrew/Caskroom/miniconda/base/envs/chattts_webui/bin/python3 webui/main.py
    Load models from snapshot.
    Traceback (most recent call last):
    File "/Users/lex/git/ChatTTS-WebUI/webui/main.py", line 39, in <module>
        chat.load_models()
        ^^^^^^^^^^^^^^^^
    AttributeError: 'Chat' object has no attribute 'load_models'. Did you mean: 'download_models'?
    ```
- copy models 

```bash
pwd
/Users/lex/git/ChatTTS-WebUI
mkdir models
cp -r /Users/lex/git/ChatTTS-WebUI/ChatTTS/ChatTTS/model/chattts/* ./models/
```

---
- main.py
```python
cat main.py 
import gradio as gr
import numpy as np
import soundfile as sf

import sys
import os
import random
import datetime

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../ChatTTS')))

import ChatTTS
chat = ChatTTS.Chat()

# load models from local path or snapshot

required_files = [
    'models/asset/Decoder.pt',
    'models/asset/DVAE.pt',
    'models/asset/GPT.pt',
    'models/asset/spk_stat.pt',
    'models/asset/tokenizer.pt',
    'models/asset/Vocos.pt',
    'models/config/decoder.yaml',
    'models/config/dvae.yaml',
    'models/config/gpt.yaml',
    'models/config/path.yaml',
    'models/config/vocos.yaml'
]

# 检查所有文件是否存在
all_files_exist = all(os.path.exists(file_path) for file_path in required_files)

if all_files_exist:
    print('Load models from local path.')
    chat.load_models(source='local', local_path='models')
else:
    print('Load models from snapshot.')
    chat.load_models()

def text_to_speech(text):

    wavs = chat.infer([text], use_decoder=True)
    audio_data = np.array(wavs[0])
    if audio_data.ndim == 1:
        audio_data = np.expand_dims(audio_data, axis=0)
    if not os.path.exists('outputs'):
        os.makedirs('outputs')
    output_file = f'outputs/{datetime.datetime.now().strftime("%Y%m%d%H%M%S")} - {random.randint(1000, 9999)}.wav'
    sf.write(output_file, audio_data.T, 24000)
    return output_file

# examples
examples = [
    ["你先去做，哪怕做成屎一样，在慢慢改[laugh]，不要整天犹犹豫豫[uv_break]，一个粗糙的开始，就是最好的开始，什么也别管，先去做，然后你就会发现，用不了多久，你几十万就没了[laugh]"],
    ["生活就像一盒巧克力，你永远不知道你会得到什么。"],
    ["每一天都是新的开始，每一个梦想都值得被追寻。"]
]

# create a block
block = gr.Blocks(css="footer.svelte-mpyp5e {display: none !important;}", title='文本转语音').queue()

with block:
    with gr.Row():
        gr.Markdown("## ChatTTS-WebUI     【浩哥聊AI】")
    
    with gr.Row():
        gr.Markdown(
            """
            ### 说明
            - 输入一段文本，点击“生成”按钮。
            - 程序会生成对应的语音文件并显示在右侧。
            - 你可以下载生成的音频文件。
            - 也可以选择一些示例文本进行测试。
            - 作者：浩哥聊AI
            - 欢迎关注我的抖音号：浩哥聊AI。或者加我微信聊一些商业项目：yuhao1029
            """
        )
    
    
    with gr.Row():
        with gr.Column():
            input_text = gr.Textbox(label='输入文本', lines=2, placeholder='请输入文本...')
            example = gr.Examples(
                label="示例文本",
                inputs=input_text,
                examples=examples,
                examples_per_page=3,
            )
        
        with gr.Column():
            output_audio = gr.Audio(label='生成的音频', type='filepath', show_download_button=True)
        
    with gr.Column():
        run_button = gr.Button(value="生成")
    
    

    run_button.click(fn=text_to_speech, inputs=input_text, outputs=output_audio)

# launch
block.launch(server_name='127.0.0.1', server_port=9527, share=True)
```
  访问 `http://127.0.0.1:9527` 即可使用ChatTTS进行文本转语音。

## 7. 使用ChatTTS
- **输入文本**：在WebUI界面输入你希望合成的文本。
- **生成语音**：点击“合成”按钮生成语音。
- **播放或下载**：可以在线试听或下载生成的语音文件。

注意：确保你的Mac具有足够的显存（至少4G）以顺利运行ChatTTS[3]。

Citations:
[1] https://www.cnblogs.com/wangpg/p/18232094
[2] https://cloud.baidu.com/article/3367979
[3] https://github.com/yuhaolove/ChatTTS-WebUI/blob/main/README_CN.md
[4] https://www.youtube.com/watch?v=199fyU7NfUQ
[5] https://blog.csdn.net/weixin_44259499/article/details/139640987
[6] https://www.freedidi.com/12613.html
[7] https://www.youtube.com/watch?v=D_QtZAbZ4JY
[8] https://blog.csdn.net/engchina/article/details/139817529


# Condas是什么 macOS下如何安装
conda install anaconda::conda
Retrieving notices: done
Channels:
 - defaults
 - anaconda
 - conda-forge
Platform: osx-arm64
Collecting package metadata (repodata.json): done
Solving environment: done

## Package Plan ##

  environment location: /opt/homebrew/Caskroom/miniconda/base

  added / updated specs:
    - anaconda::conda


The following packages will be downloaded:

    package                    |            build
    ---------------------------|-----------------
    ca-certificates-2024.12.31 |       hca03da5_0         129 KB
    certifi-2025.1.31          |  py312hca03da5_0         164 KB
    conda-24.11.3              |  py312hca03da5_0         1.2 MB  anaconda
    ------------------------------------------------------------
                                           Total:         1.4 MB

The following packages will be UPDATED:

  ca-certificates    conda-forge::ca-certificates-2024.12.~ --> pkgs/main::ca-certificates-2024.12.31-hca03da5_0 
  certifi            conda-forge/noarch::certifi-2024.12.1~ --> pkgs/main/osx-arm64::certifi-2025.1.31-py312hca03da5_0 
  conda              conda-forge::conda-24.11.2-py312h81bd~ --> anaconda::conda-24.11.3-py312hca03da5_0 


Proceed ([y]/n)? y


Downloading and Extracting Packages:
                                                                                                                                                                                           
Preparing transaction: done                                                                                                                                                                
Verifying transaction: done                                                                                                                                                                
Executing transaction: done