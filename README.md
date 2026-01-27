# 小红书运营 (xiaohongshu-ops)

将 AI 交易日志自动转化为小红书内容的工作流。

## 工作流程

```
Prophet 交易日志
       ↓
  daily_publish.sh
       ↓
 Claude 生成文案 (JSON)
       ↓
 Puppeteer 渲染图片 (4:5)
       ↓
   人工审核
       ↓
   发布到小红书
```

## 快速开始

```bash
# 1. 安装依赖
npm install

# 2. 测试渲染效果
./test_render.sh

# 3. 生成今日内容
./daily_publish.sh

# 4. 指定日期
./daily_publish.sh 2026-01-23
```

## 目录结构

```
xiaohongshu-ops/
├── daily_publish.sh      # 主入口脚本
├── test_render.sh        # 测试渲染效果
├── package.json          # Node.js 依赖
├── scripts/
│   ├── render_images.js  # 图片渲染脚本
│   └── example_content.json
├── output/               # 输出目录
│   └── 2026-01-23/
│       ├── source_data.json
│       ├── content.json
│       ├── slide_1.png
│       ├── slide_2.png
│       └── metadata.json
├── prompts/              # Claude 提示词
├── templates/            # HTML 模板
└── CONTENT_RULES.md      # 运营规则
```

## 数据源

从 `Claude_Prophet_Fork` 项目读取：

| 文件 | 内容 | 用途 |
|------|------|------|
| `activity_logs/activity_*.json` | 每日交易活动 | 生成复盘 |
| `decisive_actions/*.json` | 单笔决策记录 | 交易解读 |

## 图片规格

- **尺寸**: 1080 x 1350 (4:5)
- **格式**: PNG
- **风格**: 深色渐变背景，高对比度文字

## 依赖

- Node.js 18+
- Puppeteer (自动安装 Chromium)
- Claude CLI

## 配置

Prophet 项目路径在 `daily_publish.sh` 中配置：

```bash
PROPHET_PATH="/Users/zwan/Documents/GitHub/Claude_Prophet_Fork"
```
