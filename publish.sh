#!/bin/bash

# 发布小红书内容
# 用法: ./publish.sh <YYYY-MM-DD> [--dry-run]
# 依赖: xiaohongshu-mcp (通过 Claude CLI 调用)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

DATE=${1:-}
DRY_RUN=false

if [ -z "$DATE" ]; then
    echo "用法: ./publish.sh <YYYY-MM-DD> [--dry-run]"
    echo ""
    echo "可发布的日期:"
    for dir in output/????-??-??/; do
        if [ -f "${dir}metadata.json" ]; then
            date=$(basename "$dir")
            title=$(python3 -c "import json; print(json.load(open('${dir}metadata.json')).get('title',''))" 2>/dev/null)
            echo "  $date  $title"
        fi
    done
    exit 0
fi

[ "$2" = "--dry-run" ] && DRY_RUN=true

OUTPUT_DIR="$SCRIPT_DIR/output/$DATE"

# 检查文件是否就绪
[ ! -d "$OUTPUT_DIR" ] && error "目录不存在: $OUTPUT_DIR"
[ ! -f "$OUTPUT_DIR/content.json" ] && error "缺少 content.json"
[ ! -f "$OUTPUT_DIR/metadata.json" ] && error "缺少 metadata.json"

log "========================================"
log "发布小红书内容 - 日期: $DATE"
log "========================================"

# 读取内容
TITLE=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/content.json'))['title'])")
CAPTION=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/content.json'))['caption'])")
TAGS=$(python3 -c "import json; print(' '.join(json.load(open('$OUTPUT_DIR/content.json'))['tags']))")
IMAGES=$(python3 -c "
import json, os
meta = json.load(open('$OUTPUT_DIR/metadata.json'))
paths = [os.path.abspath(os.path.join('$OUTPUT_DIR', img)) for img in meta['images']]
print('\n'.join(paths))
")

# 组装正文（tags 通过 MCP 的 tags 参数单独传，不拼进正文）
DESCRIPTION="${CAPTION}

个人交易记录，不构成投资建议"

log ""
log "标题: $TITLE"
log "正文:"
echo -e "${CYAN}${DESCRIPTION}${NC}"
log ""
log "图片:"
echo "$IMAGES" | while read img; do
    echo "  $(basename "$img")"
done
log ""

# Dry run 模式
if [ "$DRY_RUN" = true ]; then
    warn "Dry run 模式，不会实际发布"
    log "========================================"
    log "预览完成"
    log "========================================"
    exit 0
fi

# 确认发布
echo ""
echo -e "${YELLOW}确认发布? (y/n)${NC}"
read -r CONFIRM
if [ "$CONFIRM" != "y" ]; then
    log "已取消"
    exit 0
fi

# 通过 Claude CLI 调用 xiaohongshu-mcp 发布
log "正在发布..."

# 直接通过 MCP streamable HTTP 协议调用 publish_content
MCP_URL="http://localhost:18060/mcp"

PUBLISH_EXIT=0
PUB_OUTPUT_DIR="$OUTPUT_DIR" PUB_TITLE="$TITLE" PUB_CONTENT="$DESCRIPTION" \
python3 -u << 'PYEOF' 2>&1 | tee "$OUTPUT_DIR/publish_log.txt" || PUBLISH_EXIT=$?
import json, os
from urllib.request import Request, urlopen

output_dir = os.environ["PUB_OUTPUT_DIR"]
title = os.environ["PUB_TITLE"]
content = os.environ["PUB_CONTENT"]
mcp_url = "http://localhost:18060/mcp"

# 读取 tags
with open(f"{output_dir}/content.json") as f:
    tags = json.load(f)["tags"]

# 读取 images
with open(f"{output_dir}/metadata.json") as f:
    meta = json.load(f)
images = [os.path.abspath(os.path.join(output_dir, img)) for img in meta["images"]]

def mcp_post(url, data, headers=None):
    hdrs = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"
    }
    if headers:
        hdrs.update(headers)
    req = Request(url, data=json.dumps(data).encode(), headers=hdrs, method="POST")
    resp = urlopen(req, timeout=300)
    return resp

# Step 1: initialize
resp = mcp_post(mcp_url, {
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "publish-script", "version": "1.0"}
    }
})
session_id = resp.headers.get("mcp-session-id", "")
extra_headers = {}
if session_id:
    extra_headers["mcp-session-id"] = session_id
print(f"MCP session: {session_id[:16]}...")

# Step 2: initialized notification
mcp_post(mcp_url, {
    "jsonrpc": "2.0", "method": "notifications/initialized"
}, extra_headers)

# Step 3: call publish_content
print(f"正在发布: {title}")
print(f"图片数量: {len(images)}")
print(f"标签: {tags}")

resp = mcp_post(mcp_url, {
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": {
        "name": "publish_content",
        "arguments": {
            "title": title,
            "content": content,
            "images": images,
            "tags": tags
        }
    }
}, extra_headers)

result = json.loads(resp.read())
if "error" in result:
    print(f"ERROR: {result['error']}", file=sys.stderr)
    sys.exit(1)

tool_result = result.get("result", {})
print(json.dumps(tool_result, ensure_ascii=False, indent=2))

if tool_result.get("isError"):
    print("发布失败", file=sys.stderr)
    sys.exit(1)

print("发布成功")
PYEOF

PUBLISH_EXIT=${PIPESTATUS[0]}

if [ $PUBLISH_EXIT -eq 0 ]; then
    # 记录发布状态
    python3 -c "
import json
with open('$OUTPUT_DIR/metadata.json', 'r') as f:
    meta = json.load(f)
meta['published'] = True
meta['published_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$OUTPUT_DIR/metadata.json', 'w') as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)
"
    log "========================================"
    log "发布完成！"
    log "========================================"
else
    error "发布失败，查看日志: $OUTPUT_DIR/publish_log.txt"
fi
