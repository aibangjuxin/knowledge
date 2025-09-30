# Release Dashboard

这是一个动态的API发布管理仪表板，通过JSON数据文件来渲染页面内容。

## 文件结构

```
release-dashboard/
├── index.html          # 主页面文件
├── data.json          # 数据配置文件
└── README.md          # 说明文档
```

## 使用方法

### 1. 基本使用

直接在浏览器中打开 `index.html` 文件，页面会自动加载 `data.json` 中的数据并渲染。

### 2. 更新数据

要更新仪表板内容，只需修改 `data.json` 文件中的相应字段，然后刷新页面即可。

### 3. 数据结构说明

`data.json` 包含以下主要部分：

#### header
- `apiName`: API服务名称
- `version`: 版本号
- `branch`: 发布分支

#### overview
- `commitId`: 提交ID
- `triggeredBy`: 触发者
- `triggerTime`: 触发时间
- `releaseReason`: 发布原因
- `status`: 整体状态（type, icon, text）

#### timeline
- `stages`: 部署阶段数组，每个阶段包含：
  - `id`: 阶段标识
  - `name`: 阶段名称
  - `status`: 状态（completed/active/pending）
  - `statusText`: 状态文本
  - `icon`: 图标名称
  - `timestamp`: 时间戳

#### regions
区域部署状态数组，每个区域包含：
- `name`: 区域名称
- `location`: 具体位置
- `deployed`: 是否已部署
- `status`: 状态信息
- `changeRequest`: 变更请求信息
- `icLink`: IC链接

#### scans
安全和质量扫描结果数组，每个扫描包含：
- `name`: 扫描名称
- `description`: 描述
- `status`: 状态（passed/warning/failed/skipped）
- `metrics`: 指标数据
- `reportLink`: 报告链接

#### executionRecords
执行记录数组，每条记录包含：
- `executor`: 执行者信息
- `action`: 执行动作
- `environment`: 环境
- `region`: 区域
- `timestamp`: 时间戳
- `status`: 状态
- `jobId`: 任务ID
- `jobLink`: 任务链接

#### attachments
附件数组，每个附件包含：
- `name`: 文件名
- `size`: 文件大小
- `uploadedBy`: 上传者
- `uploadedTime`: 上传时间
- `icon`: 图标
- `iconColor`: 图标颜色

#### releaseDetails
发布详情，包含：
- `keyFeatures`: 关键特性数组
- `deploymentSteps`: 部署步骤数组

## 自定义配置

### 状态类型
支持的状态类型：
- `success`: 成功（绿色）
- `warning`: 警告（黄色）
- `danger`: 危险（红色）
- `pending`: 待处理（灰色）
- `progress`: 进行中（蓝色）

### 图标
使用 Lucide 图标库，可以在 [Lucide Icons](https://lucide.dev/icons/) 查看所有可用图标。

### 颜色变量
CSS变量定义了主要颜色：
- `--primary`: 主色调
- `--success`: 成功色
- `--warning`: 警告色
- `--danger`: 危险色
- `--gray-*`: 灰色系列

## 功能特性

1. **响应式设计**: 支持桌面和移动设备
2. **动态加载**: 通过JSON文件动态渲染内容
3. **实时刷新**: 支持数据刷新功能
4. **交互式界面**: 包含折叠面板、文件上传等交互元素
5. **美观的动画**: 渐入动画和过渡效果
6. **状态指示**: 清晰的状态标识和进度条

## 部署建议

### 静态部署
可以直接将整个文件夹部署到任何静态文件服务器（如 Nginx、Apache、GitHub Pages 等）。

### 动态更新
在CI/CD流水线中，可以通过脚本动态生成或更新 `data.json` 文件：

```bash
# 示例：更新API版本
jq '.header.version = "v1.2.4"' data.json > temp.json && mv temp.json data.json

# 示例：更新部署状态
jq '.timeline.stages[2].status = "completed"' data.json > temp.json && mv temp.json data.json
```

### 集成建议
1. 在流水线中生成 `data.json`
2. 将仪表板部署到Web服务器
3. 通过webhook或定时任务更新数据
4. 可以添加API接口来动态更新数据

## 浏览器兼容性

支持现代浏览器：
- Chrome 60+
- Firefox 60+
- Safari 12+
- Edge 79+

## 许可证

此项目基于原有的设计和功能进行改造，保持所有原始特性和样式。