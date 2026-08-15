# -*- coding: utf-8 -*-
"""每周复盘：统计近 7 天选题方向配比、耗时、产出成功率，输出 markdown 到 state/weekly"""
import json
import os
import sys
import datetime

if len(sys.argv) > 1 and sys.argv[1] == "--days":
    DAYS = int(sys.argv[2])
else:
    DAYS = 7

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(TOOLS, "state")
PROGRESS = os.path.join(STATE, "progress")
DAILY = os.path.join(STATE, "daily_news")

DIRECTIONS = [
    ("中国突破", ["中国", "国产", "全球首", "世界首", "反超", "突破", "芯片", "光刻机", "中芯", "华为", "大模型", "航天",
                  "卫星", "火箭", "发射", "空间站", "深空", "量子", "新能源", "电池", "光伏", "高铁", "航母", "六代机",
                  "机器人", "首架", "首艘", "交付"]),
    ("文化输出", ["文化", "游戏", "电影", "电视剧", "短剧", "短视频", "网文", "戏曲", "京剧", "武术", "国粹", "出海",
                  "风靡", "全球票房", "登陆", "爆款", "电竞", "中文"]),
    ("南方向华", ["东盟", "东南亚", "越南", "印尼", "马来", "泰国", "菲律宾", "新加坡", "非洲", "中东", "沙特", "阿联酋",
                  "伊朗", "埃及", "拉美", "巴西", "墨西哥", "阿根廷", "智利", "秘鲁", "哈萨克", "乌兹别克", "白俄罗斯",
                  "塞尔维亚", "匈牙利", "金砖", "一带一路", "中欧班列", "贸易额", "订单", "签署", "关税减免", "零关税"]),
    ("中国护盾", ["撤侨", "护侨", "护航", "领事馆", "领事", "救援", "撤离", "保护", "侨民", "公民安全"]),
    ("他山败笔", ["反噬", "打脸", "搬起石头", "自食其果", "得不偿失", "内讧", "分裂", "朝令夕改", "政策失败", "倒行逆施",
                  "众叛亲离", "外交孤立", "经济恶化"]),
    ("对手狼狈", ["美国", "美", "日本", "印度", "英国", "澳大利亚", "加拿大", "韩国", "北约", "欧盟", "欧洲",
                  "美联储", "白宫", "国会", "拜登", "特朗普", "马斯克", "波音", "苹果", "谷歌", "英伟达",
                  "危机", "崩溃", "破产", "裁员", "暴跌", "丑闻", "受贿", "贪腐", "性侵", "遇难", "坠机", "泄漏",
                  "火灾", "骚乱", "罢工", "通胀", "衰退", "违约", "封锁", "冲突"]),
]

def classify(title):
    score = {}
    for name, kws in DIRECTIONS:
        score[name] = sum(1 for k in kws if k in title)
    if max(score.values()) == 0:
        return "其他"
    # 中国突破优先于对手狼狈（同命中时）
    best = max(score, key=lambda k: (score[k], 0 if k == "中国突破" else 1))
    return best

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def main():
    today = datetime.date.today()
    days = [(today - datetime.timedelta(days=i)).isoformat() for i in range(DAYS)]
    days.reverse()

    rows = []
    total_docs = 0
    total_elapsed = 0
    elapsed_n = 0
    dir_count = {}
    for d in days:
        pfile = os.path.join(PROGRESS, d + ".json")
        dfile = os.path.join(DAILY, d + ".json")
        prog = load_json(pfile) or {}
        daily = load_json(dfile) or {}
        items = daily.get("items", []) if daily else []
        status = prog.get("status", "无记录")
        elapsed = prog.get("elapsed_min")
        titles = [it.get("title", "") for it in items] if items else []
        if len(items) >= 10:
            total_docs += 10
        if elapsed:
            total_elapsed += elapsed
            elapsed_n += 1
        for t in titles:
            dc = classify(t)
            dir_count[dc] = dir_count.get(dc, 0) + 1
        rows.append({"date": d, "status": status, "elapsed": elapsed, "titles": titles, "items": len(items)})

    out = []
    out.append("# 每周复盘报告（%s ~ %s）" % (days[0], days[-1]))
    out.append("")
    out.append("## 总览")
    out.append("")
    out.append("- 覆盖天数：%d 天" % len(days))
    out.append("- 产文总数：%d 篇（目标 %d 篇，完成率 %.0f%%）" % (total_docs, 10 * len(days), total_docs / (10 * len(days)) * 100))
    if elapsed_n:
        out.append("- 平均耗时：%.1f 分钟（基于 %d 天）" % (total_elapsed / elapsed_n, elapsed_n))
        out.append("- 总耗时：%.0f 分钟" % total_elapsed)
    out.append("")
    out.append("## 选题方向配比")
    out.append("")
    for name in [x[0] for x in DIRECTIONS] + ["其他"]:
        n = dir_count.get(name, 0)
        if n:
            out.append("- %s：%d 篇（%.0f%%）" % (name, n, n / max(total_docs, 1) * 100))
    out.append("")
    out.append("## 逐日明细")
    out.append("")
    out.append("| 日期 | 状态 | 耗时(分) | 产出 | 标题 |")
    out.append("| --- | --- | --- | --- | --- |")
    for r in rows:
        t = r["titles"][0] if r["titles"] else "-"
        out.append("| %s | %s | %s | %d/10 | %s" % (r["date"], r["status"], r["elapsed"] if r["elapsed"] is not None else "-", r["items"], t))
        for extra in r["titles"][1:]:
            out.append("| | | | | %s" % extra)
    out.append("")

    weekly_dir = os.path.join(STATE, "weekly")
    os.makedirs(weekly_dir, exist_ok=True)
    outfile = os.path.join(weekly_dir, "weekly_%s.md" % today.isoformat())
    with open(outfile, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("\n".join(out))
    print("\n[saved] %s" % outfile)

if __name__ == "__main__":
    main()
