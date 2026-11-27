# Rex

Rex（Superlogical 的 macOS 终端工作区）相关笔记。

| 文档 | 说明 |
| --- | --- |
| [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md) | 安装 Rex Markdown for Pi：Pi 里点击本地 Markdown 链接 → Rex 右侧分屏渲染预览。含完整安装步骤、路径适配、验证、故障排查与卸载 |
| [Rex-Markdown-tools-migration.md](./Rex-Markdown-tools-migration.md) | 把运行时从 Pi 已废弃的 `~/.pi/tools/` 迁到 `~/.local/share/rex-markdown/`：两个症状的源码级根因、五个关键坑、执行流水与验证清单、回滚方法 |
| [How-to-view-markdown.md](./How-to-view-markdown.md) | 不开 Pi，直接在终端里读 / 预览 Markdown：glow、bat、fzf 实时预览，以及自建 `mdview`（Rex 右侧分屏渲染 + 目录浏览） |
| [mdview.md](./mdview.md) | `mdview` 命令的技术说明：它是我写的胶水脚本，底层调用 Rex CLI + terminal-browser，附逐段执行流程、完整命令、安全模型、排错 |
| [mdview-setup-and-dependencies.md](./mdview-setup-and-dependencies.md) | **换一台 macOS 跑通 `mdview` 要装什么**：必需/可选依赖清单、终端图形协议要求、`rex` CLI 的解析逻辑、完整安装步骤、验证清单与排错表 |
| [Rex-Kitty-Graphics.md](./Rex-Kitty-Graphics.md) | 用 Kitty 图形协议往 Rex 窗格里画图：Rex 支不支持图形协议的验证过程、协议要点、安装步骤、用法（消音词卡 / 任意 PNG）、故障排查 |

## 脚本

| 文件 | 说明 |
| --- | --- |
| [`mdview`](./mdview) | 终端里看 Markdown 的胶水脚本（`~/.local/bin/mdview` 是它的软链） |
| [`mdview-doctor`](./mdview-doctor) | 依赖自检脚本：一条命令核对本机能否跑通 `./mdview-doctor` |
| [`fix-pi-tools.sh`](./fix-pi-tools.sh) | 把 Rex Markdown 运行时从 Pi 已废弃的 `~/.pi/tools/` 迁到 `~/.local/share/rex-markdown/`：幂等，支持 `--dry-run`，详见 [迁移文档](./Rex-Markdown-tools-migration.md) |

## 快速开始

```bash
# 1) 自检：缺什么一目了然
./mdview-doctor

# 2) 用
mdview FILE.md      # Rex 右侧开分屏预览（焦点留在当前 pane）
mdview DIR/         # fzf 浏览目录下所有 .md
mdview -c FILE.md   # 当前 pane 用 glow 排版渲染
mdview -l DIR/      # 只列出 .md 路径
```
