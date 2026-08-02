# 每日国际新闻写作流水线

基于 opencode Agent 的自动化国际新闻评论写作系统：每天自动搜索不重复的国际新闻，撰写观察者网风格的评论文章，配真实新闻图片，生成 docx 文档并保存。

## 功能特性

- **每日自动运行**：通过 Windows 任务计划程序，每天 05:30 自动执行
- **智能查重**：15 天滚动窗口去重，避免重复选题
- **真实配图**：自动搜索并下载 3 张真实新闻图片（校验 HTTP 状态、图片类型、大小）
- **统一风格**：标题公式 + 副标题栏 + 6 段正文 + 图注 + 署名，产出结构与人工写作一致
- **产出自检**：生成后自动校验 docx 结构完整性，不达标自动重写
- **超时看门狗**：任务卡死自动终止，防止无人值守时无限挂起
- **失败重试**：定时任务配置了超时限制、重启重试、错过补跑

## 目录结构

```
├── article/            # 文章产出（按日期分文件夹，默认不提交到仓库）
├── tools/              # 流水线工程文件
│   ├── .opencode/      # opencode Agent 定义（agent/ 和 command/）
│   ├── prompts/        # 提示词（找新闻、写文章）
│   ├── scripts/        # Python 脚本
│   ├── state/          # 查重档案（本地数据，默认不提交）
│   └── schedule/       # 定时任务脚本（run_daily.ps1 / run_daily.bat）
├── requirements.txt    # Python 依赖
├── LICENSE             # GPL-3.0
└── README.md
```

## 环境要求

- **Windows 10/11**（定时任务基于 Windows 任务计划程序）
- **Python 3.10+** 及依赖：

  ```bash
  pip install -r requirements.txt
  ```

- **[opencode](https://opencode.ai)** 命令行工具，并配置好可用的模型（示例配置使用 `opencode/deepseek-v4-flash-free`）

## 快速开始

### 1. 手动执行一次

```bash
cd tools
opencode run --agent news-writer --auto "Start today's news writing task"
```

产出 5 篇 docx 到 `article\YYYY-MM-DD\`。

### 2. 配置每日定时任务

先确认 `opencode` 在 PATH 中（或用环境变量 `OPENCODE_CMD` 指定完整路径），然后创建计划任务：

```powershell
$action = New-ScheduledTaskAction -Execute "<仓库绝对路径>\tools\schedule\run_daily.bat"
$t1 = New-ScheduledTaskTrigger -Daily -At 05:30
$t2 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 90) `
  -MultipleInstances IgnoreNew `
  -StartWhenAvailable `
  -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName "NewsWriterDaily" `
  -Action $action -Trigger $t1,$t2 -Settings $settings -User $env:USERNAME -Force
```

### 3. 工作流程说明

1. **找新闻**：搜索昨天和今天的国际新闻，筛 10-15 条候选（`prompts/find_news.md`）
2. **查重**：与 `state/recent_topics.json`（15 天窗口）比对，剔除已写主题，凑满 5 条
3. **写作**：按 `prompts/write_article.md` 撰写（标题公式 + 副标题栏 + 6 段 + 图注）
4. **配图**：下载 3 张真实新闻图片并校验
5. **生成 docx**：`build_docx.py` 构建文档，`verify_docx.py` 自检
6. **更新档案**：写入 `state/written_topics.json` 供下次查重

## 配置说明

| 配置 | 位置 | 说明 |
|---|---|---|
| 模型 | `tools/.opencode/agent/news-writer.md` | `model:` 字段，可按需更换 |
| 每日篇数 | `tools/.opencode/agent/news-writer.md` | 默认 5 篇 |
| 查重窗口 | `tools/scripts/refresh_window.py` | `WINDOW_DAYS`，默认 15 天 |
| 图片校验阈值 | `tools/scripts/fetch_image.py` | `MIN_SIZE`，默认 10KB |
| opencode 路径 | 环境变量 `OPENCODE_CMD` | 未设置时依赖 PATH |

## 注意事项

- **图片版权**：图片来自互联网公开新闻源，仅为个人自动化写作流程演示，请在使用中自行评估版权风险
- **文章内容**：文章由 AI 生成，观点不代表本项目立场
- **编码**：`.ps1` 脚本需保持 UTF-8 with BOM，否则 Windows PowerShell 5.1 会乱码导致逻辑异常
- **本地数据**：`state/` 和 `article/` 默认被 `.gitignore` 排除，不会提交到仓库

## License

本项目采用 [GPL-3.0](./LICENSE)。
