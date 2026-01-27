#!/bin/bash

# 测试图片渲染效果
# 用法: ./test_render.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TEST_DATE="test-$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$SCRIPT_DIR/output/$TEST_DATE"

echo "=========================================="
echo "测试图片渲染"
echo "=========================================="

# 检查依赖
if [ ! -d "node_modules" ]; then
    echo "安装依赖..."
    npm install
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 复制示例内容
cp scripts/example_content.json "$OUTPUT_DIR/content.json"

# 渲染图片
echo "渲染中..."
node scripts/render_images.js "$OUTPUT_DIR/content.json" "$OUTPUT_DIR"

echo ""
echo "=========================================="
echo "完成！"
echo "=========================================="
echo "输出目录: $OUTPUT_DIR"
echo ""

# 打开输出目录
open "$OUTPUT_DIR"
