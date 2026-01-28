#!/bin/bash

# 小红书每日发布脚本
# 用法: ./daily_publish.sh [YYYY-MM-DD]
# 不传日期则默认今天

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 配置
PROPHET_PATH="/Users/zwan/Documents/GitHub/Claude_Prophet_Fork"
OUTPUT_DIR="$SCRIPT_DIR/output"
DATE=${1:-$(date +%Y-%m-%d)}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

log "========================================"
log "小红书每日发布 - 日期: $DATE"
log "========================================"

# 1. 计算这是第几天（Day X）并获取前一天的收盘账户总值
# 统计 output 目录下已有的 YYYY-MM-DD 格式文件夹数量
EXISTING_DAYS=$(ls -d "$OUTPUT_DIR"/????-??-?? 2>/dev/null | wc -l | tr -d ' ')
# 如果当前日期的文件夹已存在，不重复计数
if [ -d "$OUTPUT_DIR/$DATE" ]; then
    DAY_NUMBER=$EXISTING_DAYS
else
    DAY_NUMBER=$((EXISTING_DAYS + 1))
fi
log "交易日记 Day $DAY_NUMBER"

# 获取前一天的收盘账户总值（用于计算当日百分比收益）
PREVIOUS_PORTFOLIO_VALUE=100000  # 默认初始资金
if [ $DAY_NUMBER -gt 1 ]; then
    # 找到最近一个已生成的 day 的 metadata
    PREV_DAY_DIR=$(ls -d "$OUTPUT_DIR"/????-??-?? 2>/dev/null | sort | grep -v "$DATE" | tail -1)
    if [ -n "$PREV_DAY_DIR" ] && [ -f "$PREV_DAY_DIR/source_data.json" ]; then
        # 从前一天的数据中提取收盘 portfolio_value
        PREV_VALUE=$(python3 -c "
import json
with open('$PREV_DAY_DIR/source_data.json', 'r') as f:
    data = json.load(f)

# 从 activity_log 的最后一条 DECISION 记录中获取 portfolio_value
activities = data.get('activity_log', {}).get('activities', [])
for a in reversed(activities):
    if 'portfolio_value' in a.get('details', {}):
        print(int(a['details']['portfolio_value']))
        break
else:
    # 从 decisive_actions 中找
    for d in reversed(data.get('decisive_actions', [])):
        if 'portfolio_value' in d.get('market_data', {}):
            print(int(d['market_data']['portfolio_value']))
            break
" 2>/dev/null)
        if [ -n "$PREV_VALUE" ]; then
            PREVIOUS_PORTFOLIO_VALUE=$PREV_VALUE
            log "前一交易日收盘账户总值: \$$PREVIOUS_PORTFOLIO_VALUE"
        fi
    fi
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR/$DATE"

# 2. 检查数据源
DECISIONS_DIR="$PROPHET_PATH/decisive_actions"
ACTIVITY_LOGS_DIR="$PROPHET_PATH/activity_logs"

# 查找包含目标日期数据的 activity_log
# (activity_log 按会话存储，一个文件可能包含多天的数据)
ACTIVITY_LOG=""
for log_file in "$ACTIVITY_LOGS_DIR"/activity_*.json; do
    if [ -f "$log_file" ]; then
        # 检查文件中是否有目标日期的 activities
        if grep -q "\"timestamp\": \"$DATE" "$log_file" 2>/dev/null; then
            ACTIVITY_LOG="$log_file"
            break
        fi
    fi
done

# 收集当日的 decisive_actions (按日期前缀匹配 YYYY-MM-DD)
TODAYS_DECISIONS=$(ls "$DECISIONS_DIR" 2>/dev/null | grep "^$DATE" || true)

# 必须有 activity_log 或 decisive_actions 其中之一
if [ -z "$ACTIVITY_LOG" ] && [ -z "$TODAYS_DECISIONS" ]; then
    error "未找到 $DATE 的交易数据（无 activity_log 且无 decisive_actions）"
fi

log "数据源检查完成"
[ -n "$ACTIVITY_LOG" ] && log "  - Activity log: $(basename $ACTIVITY_LOG)"
[ -z "$ACTIVITY_LOG" ] && warn "  - Activity log: 未找到"
[ -n "$TODAYS_DECISIONS" ] && log "  - Decisive actions: $(echo "$TODAYS_DECISIONS" | wc -l | tr -d ' ') 个"

# 3. 准备数据文件
DATA_FILE="$OUTPUT_DIR/$DATE/source_data.json"

echo "{" > "$DATA_FILE"
echo '  "date": "'$DATE'",' >> "$DATA_FILE"
echo '  "day_number": '$DAY_NUMBER',' >> "$DATA_FILE"
echo '  "previous_portfolio_value": '$PREVIOUS_PORTFOLIO_VALUE',' >> "$DATA_FILE"

# 添加 activity_log（按日期过滤 activities）
if [ -n "$ACTIVITY_LOG" ] && [ -f "$ACTIVITY_LOG" ]; then
    echo '  "activity_log": ' >> "$DATA_FILE"
    # 过滤只保留目标日期的 activities
    python3 -c "
import json
import sys

with open('$ACTIVITY_LOG', 'r') as f:
    data = json.load(f)

# 过滤 activities，只保留目标日期
target_date = '$DATE'
filtered_activities = [
    a for a in data.get('activities', [])
    if a.get('timestamp', '').startswith(target_date)
]

# 更新数据
data['activities'] = filtered_activities
data['_filtered_for_date'] = target_date
data['_original_activity_count'] = len(data.get('activities', []))

json.dump(data, sys.stdout, ensure_ascii=False)
" >> "$DATA_FILE"
    echo ',' >> "$DATA_FILE"
else
    echo '  "activity_log": null,' >> "$DATA_FILE"
fi

# 添加 decisive_actions
echo '  "decisive_actions": [' >> "$DATA_FILE"
FIRST=true
for decision in $TODAYS_DECISIONS; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo ',' >> "$DATA_FILE"
    fi
    cat "$DECISIONS_DIR/$decision" >> "$DATA_FILE"
done
echo ']' >> "$DATA_FILE"
echo '}' >> "$DATA_FILE"

log "数据文件已生成: $DATA_FILE"

# 4. 调用 Claude 生成内容
log "正在生成内容..."

CONTENT_FILE="$OUTPUT_DIR/$DATE/content.json"
PROMPT_FILE="$OUTPUT_DIR/$DATE/prompt.txt"

# 生成提示词文件
cat > "$PROMPT_FILE" << 'PROMPT_END'
你是小红书内容创作者，专注于美股期权交易分享。

请根据提供的交易数据，生成一篇小红书帖子内容。

输出要求（必须是有效JSON，不要包含任何其他文字）:
{
  "title": "标题（20字以内，吸引眼球但不夸张）",
  "slides": [
    {
      "heading": "小标题",
      "content": "该页内容（50-100字，简洁有力）"
    }
  ],
  "tags": ["标签1", "标签2", "标签3"],
  "caption": "发布时的正文（2-3句话，50字左右，只写核心数据：今日盈亏、关键操作、账户总值。不要长篇大论）"
}

## 必须严格遵守的 5 张图结构：

**Slide 1 - 今日战绩**
- 标题格式：「Day X | 今日战绩」（X 从下面的 day_number 字段获取）
- 总结今天的整体表现
- 包含：总盈亏（金额+百分比）、账户总值、执行了几笔交易
- 背景：这是一个 $100,000 起始资金的模拟盘
- **重要**：当日盈亏百分比 = (今日收盘总值 - previous_portfolio_value) / previous_portfolio_value
  - Day 1 的 previous_portfolio_value 是 100000（初始资金）
  - Day 2+ 的 previous_portfolio_value 是前一天的收盘账户总值
  - 这样读者可以通过翻看前一天的帖子来验证计算

**Slide 2 - 操作时间线**
- 列出每笔操作的具体时间（美东时间）
- 格式示例：
  "10:45 买入 SPY $689C x3
   12:56 止盈 TSLA +38%
   14:30 止损 SPY -15%"
- 从 timestamp 字段提取时间，转换为 HH:MM 格式

**Slide 3 - 买入逻辑**
- 为什么做这笔交易？
- 从 reasoning 字段提取分析依据
- 包含：消息面（如 Trump tariff、GDP data）或技术面（如 delta、支撑位）

**Slide 4 - 卖出/止损逻辑**
- 为什么平仓？是止盈还是止损？
- 触发了什么规则？（如 -15% 止损线、+25% 止盈目标）

**Slide 5 - 今日感悟**
- 这次交易学到了什么
- 哪里做得好，哪里可以改进
- **避免套话**：不要每次都说"纪律执行到位"、"严格遵守规则"之类的话
- 换不同角度，比如：
  - 市场认知（"今天学到了关于波动率的一课"）
  - 心态管理（"盈利时保持冷静比亏损时更难"）
  - 具体技巧（"ATM 期权的 delta 衰减比预期快"）
  - 自我反思（"入场时机还是太急了"）
  - 市场观察（"财报季的期权定价确实不一样"）

## 其他规则：
1. slides 必须是 5 个，不多不少
2. 语气：专业但亲和，像朋友分享
3. 可以透露具体金额（这是10万美元的模拟盘，无需隐藏）
4. 时间用美东时间（ET），只显示 HH:MM
5. 股票代码保持大写（SPY, NVDA, TSLA）
6. **避免重复套话**：
   - 禁止每篇都说"纪律执行到位"、"严守纪律"、"规则就是规则"
   - 禁止空泛的正能量总结（"继续加油"、"明天会更好"）
   - 每篇的感悟要有具体的、不同的角度

只输出JSON，不要markdown代码块，不要其他解释文字。

交易数据:
PROMPT_END

cat "$DATA_FILE" >> "$PROMPT_FILE"

# 调用 Claude（使用 --print 输出到文件）
claude --print -p "$(cat "$PROMPT_FILE")" > "$CONTENT_FILE"

# 验证JSON
if ! python3 -c "import json; json.load(open('$CONTENT_FILE'))" 2>/dev/null; then
    warn "Claude 输出不是有效JSON，尝试提取..."
    # 尝试提取JSON部分
    python3 -c "
import re
import json
with open('$CONTENT_FILE', 'r') as f:
    content = f.read()
# 找到JSON部分
match = re.search(r'\{[\s\S]*\}', content)
if match:
    data = json.loads(match.group())
    with open('$CONTENT_FILE', 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print('JSON extracted successfully')
else:
    raise Exception('No valid JSON found')
"
fi

log "内容已生成: $CONTENT_FILE"

# 5. 渲染图片
log "正在渲染图片..."

node "$SCRIPT_DIR/scripts/render_images.js" "$CONTENT_FILE" "$OUTPUT_DIR/$DATE"

log "========================================"
log "完成！输出目录: $OUTPUT_DIR/$DATE"
log "========================================"

# 列出生成的文件
ls -la "$OUTPUT_DIR/$DATE/"

echo ""
log "下一步："
log "  1. 查看生成的图片: open $OUTPUT_DIR/$DATE"
log "  2. 确认后发布: ./publish.sh $DATE"
