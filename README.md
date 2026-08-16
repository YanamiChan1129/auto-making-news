# 每日国际新闻写作流水线

基于 opencode Agent 的自动化国际新闻评论写作系统：每天自动搜索不重复的国际新闻，撰写观察者网风格的评论文章，配真实新闻图片，生成 docx 文档并保存。配有实时进度仪表盘、Windows 通知、失败自动补跑、每日备份与每周复盘。

## 功能特性

- **每日自动运行**：Windows 任务计划程序，每天 05:30 自动执行，运行开始时自动弹出仪表盘
- **每天 10 篇**：六大选题方向（对手狼狈/中国突破/中国护盾/他山败笔/南方向华/文化输出）每方向至少 1 条，余量在【对手狼狈】【中国突破】中追加；自动补足模式可保留已产出的部分、补齐到 10 篇
- **智能查重**：15 天滚动窗口去重，避免重复选题
- **真实配图**：每篇自动搜索并下载 3 张真实新闻图片（AI 生成图、站点 og:image 一律弃用；单篇找图 12 分钟上限）
- **统一风格**：标题公式 + 副标题栏 + 7 段正文（1500-1900 字）+ 3 图注 + 署名，docx 结构固定 17 段
- **逐篇落盘**：每篇完成（含自检 PASS）才进入下一篇，进度实时上报，仪表盘可见每篇状态
- **产出自检**：生成后自动校验 docx 结构完整性（verify_docx.py），不达标自动重写
- **超时看门狗**：任务卡死 180 分钟自动终止并通知
- **失败自动补跑**：产出不足时延迟 5 分钟自动重跑一次（不覆盖已有成果）
- **实时仪表盘**：`tools/dashboard/` 本地 HTTP 服务（127.0.0.1:8123），5 秒自动刷新——10 篇进度条、逐篇状态、耗时/ETA、日志按阶段着色滚动、近 7 天耗时趋势图、已完成文章点击直达、日期回看（保留 7 天）
- **Windows 通知**：运行中/完成/失败/自动补跑 Toast 提醒（AUMID 注册，球泡通知兜底）；可选接入 Bark/ServerChan 手机推送
- **每日备份**：05:45 将 article + state 镜像到 `_backup/`
- **每周复盘**：周一 08:00 自动生成周报（方向配比、耗时、完成率）

## 目录结构

```
├── article/            # 文章产出（按日期分文件夹，默认不提交到仓库）
├── tools/              # 流水线工程文件
│   ├── .opencode/      # opencode 配置（agent/、command/、skills/）
│   ├── prompts/        # 提示词（找新闻、写文章）
│   ├── scripts/        # Python 脚本（构建/校验/配图/周报等）
│   ├── dashboard/      # 进度仪表盘（serve.ps1 + index.html + 图标）
│   ├── state/          # 查重档案与进度（本地数据，默认不提交）
│   └── schedule/       # 定时任务脚本（run_daily / toast / backup / weekly / admin_fix）
├── requirements.txt    # Python 依赖
├── LICENSE             # GPL-3.0
└── README.md
```

## 环境要求

- **Windows 10/11**（定时任务基于 Windows 任务计划程序）
- **Python 3.10+** 及依赖：`pip install -r requirements.txt`
- **[opencode](https://opencode.ai)** 命令行工具，并配置好可用的模型

## 快速开始

### 1. 手动执行一次

```bash
cd tools
opencode run --agent news-writer --auto "Start today's news writing task"
```

产出 10 篇 docx 到 `article\YYYY-MM-DD\`。

### 2. 配置每日定时任务

先确认 `opencode` 在 PATH 中（或用环境变量 `OPENCODE_CMD` 指定完整路径），然后创建计划任务：

```powershell
$action = New-ScheduledTaskAction -Execute "<仓库绝对路径>\tools\schedule\run_daily.bat"
$t1 = New-ScheduledTaskTrigger -Daily -At 05:30
$t2 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 180) `
  -MultipleInstances IgnoreNew `
  -StartWhenAvailable `
  -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName "NewsWriterDaily" `
  -Action $action -Trigger $t1,$t2 -Settings $settings -User $env:USERNAME -Force
```

本机已配置的计划任务（也可用 `tools/schedule/admin_fix.cmd` 提权执行隐藏窗口/防火墙等管理员操作）：

| 任务 | 时间 | 用途 |
|---|---|---|
| NewsWriterDaily | 每天 05:30 | 主任务（run_daily.ps1） |
| NewsWriterRerun | 手动触发 | 手动补跑（桌面「手动补跑新闻」） |
| NewsWriterBackup | 每天 05:45 | 备份 article + state 到 `_backup/` |
| NewsWriterWeekly | 每周一 08:00 | 周报生成 |

### 3. 仪表盘

浏览器打开 http://127.0.0.1:8123/（桌面「看新闻进度」）。服务由 run_daily.ps1 自动拉起，也可手动运行 `tools/dashboard/serve.ps1`。

### 4. 工作流程说明

1. **找新闻**：搜索昨天和今天的国际新闻，筛 20-30 条候选（`prompts/find_news.md`）
2. **查重**：与 `state/recent_topics.json`（15 天窗口）比对，剔除已写主题，凑满 10 条
3. **写作**：按 `prompts/write_article.md` 撰写（标题公式 + 副标题栏 + 7 段 1500-1900 字 + 图注 + 署名）
4. **配图**：每篇下载 3 张真实新闻图片并校验（单篇 12 分钟上限）
5. **生成 docx**：`build_docx.py` 构建文档，`verify_docx.py` 自检，逐篇落盘并上报进度
6. **更新档案**：写入 `state/written_topics.json` 供下次查重，素材存档到 `state/daily_news/`
7. **通知**：完成/失败/超时通过 `tools/schedule/toast.ps1` 发 Toast

## 配置说明

| 配置 | 位置 | 说明 |
|---|---|---|
| 模型 | `tools/.opencode/agent/news-writer.md` | `model:` 字段，可按需更换 |
| 每日篇数与配比 | `tools/.opencode/skills/daily-news-writing/SKILL.md` | 默认 10 篇，六大方向配比 |
| 查重窗口 | `tools/scripts/refresh_window.py` | `WINDOW_DAYS`，默认 15 天 |
| 图片校验阈值 | `tools/scripts/fetch_image.py` | `MIN_SIZE`，默认 10KB |
| 超时上限 | `tools/schedule/run_daily.ps1` | `TIMEOUT_MIN`，默认 180 分钟 |
| 手机推送 | `tools/state/push_config.json` | 按 `push_config.example.json` 模板填 Bark/ServerChan key |
| opencode 路径 | 环境变量 `OPENCODE_CMD` | 未设置时依赖 PATH |

## 注意事项

- **编码**：`.ps1` 脚本必须保持 UTF-8 with BOM，否则 Windows PowerShell 5.1 会按 GBK 误读导致解析错乱（本项目已统一处理）
- **图片版权**：图片来自互联网公开新闻源，仅为个人自动化写作流程演示，请在使用中自行评估版权风险
- **文章内容**：文章由 AI 生成，观点不代表本项目立场
- **本地数据**：`state/`、`article/`、`_backup/` 默认被 `.gitignore` 排除，不会提交到仓库

## License

本项目采用 [GPL-3.0](./LICENSE)。