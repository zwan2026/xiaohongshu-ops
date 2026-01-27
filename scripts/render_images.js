#!/usr/bin/env node

/**
 * 将内容渲染为小红书图片 (4:5 = 1080x1350)
 * 用法: node render_images.js <content.json> <output_dir>
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const WIDTH = 1080;
const HEIGHT = 1350;

// 图片模板 HTML
function generateSlideHTML(slide, index, total, date) {
    const isFirst = index === 0;
    const isLast = index === total - 1;

    return `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            width: ${WIDTH}px;
            height: ${HEIGHT}px;
            font-family: "PingFang SC", "SF Pro Display", -apple-system, sans-serif;
            background: linear-gradient(160deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            color: #ffffff;
            display: flex;
            flex-direction: column;
            padding: 60px;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
        }

        .date {
            font-size: 28px;
            color: rgba(255,255,255,0.6);
            font-weight: 300;
        }

        .page-num {
            font-size: 24px;
            color: rgba(255,255,255,0.4);
            font-weight: 300;
        }

        .main {
            flex: 1;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }

        .heading {
            font-size: 52px;
            font-weight: 700;
            margin-bottom: 50px;
            line-height: 1.3;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }

        .content {
            font-size: 38px;
            line-height: 1.8;
            color: rgba(255,255,255,0.9);
            font-weight: 400;
        }

        .highlight {
            color: #00ff88;
            font-weight: 600;
        }

        .negative {
            color: #ff6b6b;
            font-weight: 600;
        }

        .footer {
            margin-top: auto;
            padding-top: 40px;
            border-top: 1px solid rgba(255,255,255,0.1);
        }

        .disclaimer {
            font-size: 22px;
            color: rgba(255,255,255,0.4);
            text-align: center;
        }

        .brand {
            font-size: 20px;
            color: rgba(255,255,255,0.3);
            text-align: center;
            margin-top: 15px;
        }

        /* 特殊样式: 首页 */
        .first-slide .heading {
            font-size: 64px;
        }

        /* 特殊样式: 末页 */
        .last-slide .content {
            font-style: italic;
            color: rgba(255,255,255,0.8);
        }
    </style>
</head>
<body class="${isFirst ? 'first-slide' : ''} ${isLast ? 'last-slide' : ''}">
    <div class="header">
        <span class="date">${date}</span>
        <span class="page-num">${index + 1} / ${total}</span>
    </div>

    <div class="main">
        <h1 class="heading">${slide.heading}</h1>
        <div class="content">${formatContent(slide.content)}</div>
    </div>

    <div class="footer">
        <div class="disclaimer">个人交易记录，不构成投资建议</div>
        <div class="brand">AI Trading Journal</div>
    </div>
</body>
</html>
`;
}

// 格式化内容，添加高亮
function formatContent(content) {
    return content
        // 高亮正收益
        .replace(/\+[\d.]+%/g, '<span class="highlight">$&</span>')
        // 高亮负收益
        .replace(/-[\d.]+%/g, '<span class="negative">$&</span>')
        // 高亮股票代码
        .replace(/\b(SPY|QQQ|NVDA|TSLA|AMD|AAPL|AMZN|GOOGL|META|MSFT)\b/g, '<span class="highlight">$&</span>');
}

async function main() {
    const args = process.argv.slice(2);

    if (args.length < 2) {
        console.error('用法: node render_images.js <content.json> <output_dir>');
        process.exit(1);
    }

    const [contentFile, outputDir] = args;

    // 读取内容
    const content = JSON.parse(fs.readFileSync(contentFile, 'utf-8'));
    const { title, slides, tags, caption } = content;

    // 从文件路径提取日期
    const dateMatch = outputDir.match(/(\d{4}-\d{2}-\d{2})/);
    const date = dateMatch ? dateMatch[1] : new Date().toISOString().split('T')[0];

    console.log(`渲染 ${slides.length} 张图片...`);

    // 启动浏览器 - 使用系统 Chrome
    const browser = await puppeteer.launch({
        headless: 'new',
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu'
        ],
        timeout: 60000
    });

    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT });

    // 渲染每张图片
    for (let i = 0; i < slides.length; i++) {
        const slide = slides[i];
        const html = generateSlideHTML(slide, i, slides.length, date);

        await page.setContent(html, { waitUntil: 'domcontentloaded', timeout: 10000 });

        const outputPath = path.join(outputDir, `slide_${i + 1}.png`);
        await page.screenshot({ path: outputPath, type: 'png' });

        console.log(`  [${i + 1}/${slides.length}] ${outputPath}`);
    }

    await browser.close();

    // 保存元数据
    const metadata = {
        title,
        tags,
        caption,
        slides_count: slides.length,
        generated_at: new Date().toISOString(),
        images: slides.map((_, i) => `slide_${i + 1}.png`)
    };

    fs.writeFileSync(
        path.join(outputDir, 'metadata.json'),
        JSON.stringify(metadata, null, 2)
    );

    console.log(`\n完成！生成了 ${slides.length} 张图片`);
    console.log(`标题: ${title}`);
    console.log(`标签: ${tags.join(' ')}`);
}

main().catch(err => {
    console.error('渲染失败:', err);
    process.exit(1);
});
