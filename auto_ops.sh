#!/bin/bash

# 小红书自动运营脚本
# 用法: ./auto_ops.sh [daily|trade|manual]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 加载环境变量
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

MODE=${1:-"manual"}
DATE=$(date +%Y-%m-%d)
LOG_FILE="logs/ops_$DATE.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "小红书运营 - 模式: $MODE"
log "=========================================="

case $MODE in
    daily)
        # 每日复盘模式
        log "生成每日复盘内容..."

        # 读取今天的 Prophet 日志
        ACTIVITY_LOG="$PROPHET_PROJECT_PATH/activity_logs/activity_$DATE.json"

        if [ ! -f "$ACTIVITY_LOG" ]; then
            log "未找到今日交易日志: $ACTIVITY_LOG"
            exit 1
        fi

        PROMPT=$(cat prompts/daily_review.txt)

        claude --print \
            "$PROMPT\n\n今日交易日志:\n$(cat $ACTIVITY_LOG)" \
            | tee "content_archive/daily_$DATE.md"
        ;;

    trade)
        # 交易解读模式
        log "生成交易解读内容..."

        # 获取最新的决策记录
        LATEST_DECISION=$(ls -t "$PROPHET_PROJECT_PATH/decisive_actions/" | head -1)

        if [ -z "$LATEST_DECISION" ]; then
            log "未找到决策记录"
            exit 1
        fi

        PROMPT=$(cat prompts/trade_breakdown.txt)
        DECISION_CONTENT=$(cat "$PROPHET_PROJECT_PATH/decisive_actions/$LATEST_DECISION")

        claude --print \
            "$PROMPT\n\n决策记录:\n$DECISION_CONTENT" \
            | tee "content_archive/trade_$(date +%Y%m%d_%H%M%S).md"
        ;;

    manual)
        # 手动模式 - 进入交互式 Claude
        log "进入手动运营模式..."
        claude
        ;;

    *)
        echo "用法: ./auto_ops.sh [daily|trade|manual]"
        exit 1
        ;;
esac

log "=========================================="
log "运营任务完成"
log "=========================================="
