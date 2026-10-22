#!/usr/bin/env python3
# verify_task264 — 7.0-UI-16 门禁：ZL2 下载域资产搜索页真机截图对齐重排
# （进门即搜 / 右栏筛选面板 / 页码控制器 / ZL2 卡片形态 / 双源 total 透传）
# 进程内计算只输出 PASS/FAIL 摘要（仓库判例：显示层吞字，结论不散拼）。
import re, subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

PAGE = "Natives/ZL2AssetSearchViewController.m"
CF_M = "Natives/installer/modpack/CurseForgeAPI.m"
CF_H = "Natives/installer/modpack/CurseForgeAPI.h"
MR_M = "Natives/installer/modpack/ModrinthAPI.m"
MR_H = "Natives/installer/modpack/ModrinthAPI.h"
STUB = "Natives/Preview/ZL2PagesStub.m"

page = read(PAGE)
cf_m = read(CF_M); cf_h = read(CF_H)
mr_m = read(MR_M); mr_h = read(MR_H)
stub = read(STUB)

results = []
def check(name, ok):
    results.append((name, bool(ok)))

# ── A. 进门即搜（"模组什么都不显示"主修：ZL2 语义初始拉第 1 页浏览态） ──
check("A1 进门即搜触发（viewDidLoad 非 favorites 即搜空词）",
      "进门即搜" in page and re.search(r"ame_triggerSearchWithQuery:@\"\"\]", page) is not None)
check("A2 引导空态退役（ame_guideText 方法删除）", "ame_guideText" not in page)
check("A3 空态仅剩暂无X/暂无收藏", "dl.asset.favorites.empty" in page and "i18n_str_180" in page)

# ── B. 右栏筛选面板（ZL2 SearchAssetsScreen 右栏真机对齐；文案走 54 表新键） ──
for key in ["dl.asset.filter.name", "dl.asset.filter.version", "dl.asset.import",
            "dl.asset.filter.platform", "i18n_str_161"]:
    check("B 面板字段 %s" % key, key in page)
check("B1 版本弹层（M3 底部弹层 + 内筛 + 不限版本）",
      "ZL2VersionSheetHandler" in page and "ZL2VersionIndex.sharedIndex" in page
      and "不限版本" in page and "latest-" in page)
check("B2 平台切换持久化（setDownloadSource forType）",
      "setDownloadSource:" in page and "platformOverride != 0" in page)
check("B3 存档平台锁定 CurseForge（userInteractionEnabled=NO）",
      re.search(r"ZL2AssetSearchTypeWorld\s*\)\s*\{\s*_platformControl.userInteractionEnabled = NO", page) is not None)
check("B4 面板宽态显隐收敛（≥560 收敛 + 收藏页恒隐）",
      "ame_setFilterPanelVisible" in page and "560.0" in page and "favoritesMode" in page)
check("B5 导入整合包 1:1 旧页导入流（push ModpackImportViewController）",
      "ModpackImportViewController" in page and "ame_importTapped" in page
      and "[[ModpackImportViewController alloc] init]" in page)

# ── C. 页码控制器（ZL2 PageController 整页替换） ──
check("C1 页码状态与翻页动作", all(k in page for k in
      ["_currentPage = 1", "ame_updatePaginationUI", "ame_nextPageTapped", "ame_prevPageTapped"]))
check("C2 总页数两种口径（N / M 与 dl.asset.page）",
      "%ld / %ld" in page and "dl.asset.page" in page)
check("C3 整页替换语义（成功路径 removeAllObjects，无滚动追加）",
      "页码语义：整页替换" in page and "hasMore = ((NSInteger)results.count >= ZL2AssetSearchPageSize)" in page)
check("C4 旧滚动续载退役（willDisplay 无 loadListWithReset:NO）",
      "ame_loadListWithReset:NO" not in page)

# ── D. 游戏版本筛选管线（两 API 均消费 mcVersion） ──
check("D1 页面下发 mcVersion", 'filters[@"mcVersion"]' in page)
check("D2 Modrinth facets versions:X（异步路径既有）",
      '[\"versions:%@\"]' in mr_m or '[\\"versions:%@\\"]' in mr_m or "versions:%@" in mr_m)
check("D3 CurseForge gameVersion 参数（既有）", "gameVersion=%@" in cf_m)

# ── E. 双源 total 透传（"N / M" 数据源） ──
check("E1 CurseForgeAPI.h/.m lastSearchTotalCount",
      "lastSearchTotalCount" in cf_h and "self.lastSearchTotalCount = total;" in cf_m
      and "@property (nonatomic, assign, readwrite)" not in cf_m)
check("E2 CF 解析块写 total", "self.lastSearchTotalCount = total;" in cf_m)
check("E3 ModrinthAPI.h/.m lastSearchTotalCount",
      "lastSearchTotalCount" in mr_h and "total_hits" in mr_m)
check("E4 页面消费按 isKindOfClass 分流",
      page.count("lastSearchTotalCount") >= 3 and "isKindOfClass:[CurseForgeAPI class]]" in page)

# ── F. 卡片形态（ZL2 _Search.Result 真机对齐） ──
check("F1 72dp 卡图", "CGSizeMake(72, 72)" in page and "widthAnchor constraintEqualToConstant:72" in page)
check("F2 作者同排（| 作者: X）", '| 作者: %@"' in page)
check("F3 中文量级（万/亿）", "%.1f万" in page and "%.1f亿" in page and "%.1fK" not in page)
check("F4 平台品牌徽标双色", "ZL2AssetSourceBadgeColor" in page and '@"CurseForge"' in page and '@"Modrinth"' in page)
check("F5 描述/标签行（2 行描述 + categories 空格连接）",
      "numberOfLines = 2" in page and 'tags appendString:@" "' in page)
check("F6 行高 128", "rowHeight = 128" in page)
check("F7 CF author 透传（authors 数组首名）", '"author": ame316_author' in cf_m)

# ── G. 旧件退役反锚 ──
forbidden = ["chipsScroll", "chipControls", "sortToggleControl", "searchCapsule",
             "ame_sortChipTapped", "ame_applyChipAppearance", "chipsExpanded",
             "UITextFieldDelegate", "rowHeight = 100", "chipsHeightConstraint", "chipsStack"]
check("G1 旧 chips/搜索胶囊全清", not any(x in page for x in forbidden))
check("G2 卡面下载钮退役（onDownload 字边界清零）",
      re.search(r"\bonDownload\b", page) is None)

# ── H. 括号平衡（注释/字符串感知） ──
def strip(code):
    out=[]; i=0; n=len(code)
    while i < n:
        c = code[i]
        if c == "/" and i+1 < n and code[i+1] == "/":
            j = code.find("\n", i); i = n if j < 0 else j
        elif c == "/" and i+1 < n and code[i+1] == "*":
            j = code.find("*/", i+2); i = n if j < 0 else j+2
        elif c == "@" and i+1 < n and code[i+1] == '"':
            i += 2
            while i < n:
                if code[i] == "\\": i += 2; continue
                if code[i] == '"': i += 1; break
                i += 1
        elif c == '"':
            i += 1
            while i < n:
                if code[i] == "\\": i += 2; continue
                if code[i] == '"': i += 1; break
                i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

def balanced(code):
    d = 0
    for ch in strip(code):
        if ch == "[": d += 1
        elif ch == "]":
            d -= 1
            if d < 0: return False
    return d == 0

for f, c in [("页面", page), ("CF", cf_m), ("CF.h", cf_h), ("MR", mr_m), ("MR.h", mr_h), ("桩", stub)]:
    check("H 括号平衡 %s" % f, balanced(c))

# ── I. 预览桩（进门即搜下桩出 3 条演示项 + total） ──
check("I1 桩演示项（Sodium/JEI）", "Sodium" in stub and "Just Enough Items (JEI)" in stub)
check("I2 桩 total（359/4210）", "359" in stub and "4210" in stub)
check("I3 桩属性齐备", stub.count("lastSearchTotalCount") >= 4)

# ── J. 级联 verify_task263 ──
try:
    r = subprocess.run([sys.executable, "scripts/verify_task263.py"],
                       capture_output=True, text=True, timeout=120)
    check("J1 verify_task263 ALL GREEN", "ALL GREEN" in r.stdout)
except Exception:
    check("J1 verify_task263 ALL GREEN", False)

passed = sum(1 for _, ok in results if ok)
for name, ok in results:
    print(("  PASS  " if ok else "  FAIL  ") + name)
print("=" * 44)
print("verify_task264: %d passed, %d failed" % (passed, len(results) - passed))
print("ALL GREEN" if passed == len(results) else "FAILED")
sys.exit(0 if passed == len(results) else 1)
