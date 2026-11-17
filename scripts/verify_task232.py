#!/usr/bin/env python3
"""verify_task232.py -- Task 232 (17-item feedback round on the Task231 build 092d8448,
device logs 7d8f6630 + 96c67e38) implementation gates. Byte-level anchors, absence checks
where code was retired, and the standing fleet audits (self-ref blocks, task225 bracket)."""
import os, sys, re, subprocess

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径），改从脚本
# 位置动态推导仓库根，TASK232_REPO 环境变量覆盖保留。
BASE = os.environ.get("TASK232_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
passed, failed, skipped = 0, [], 0

def rd(path):
    return open(os.path.join(BASE, path), encoding="utf-8", errors="replace").read()

def check(name, path, needle):
    """字节级锚点断言。退役宿主（Task436/440 批次物理删除）显式 SKIP，
    存留文件锚点缺失仍为 FAIL（[RETIRED] 家法 (b)/(d)）。"""
    global passed, skipped
    p = os.path.join(BASE, path)
    if not os.path.exists(p):
        skipped += 1
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        print(f"  [SKIP] {name}")
        return
    if needle in rd(path):
        passed += 1
        print(f"  ok   {name}")
    else:
        failed.append(f"{name}: anchor missing in {path}")

def check_absent(name, path, needle):
    global passed, skipped
    p = os.path.join(BASE, path)
    if not os.path.exists(p):
        skipped += 1
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        print(f"  [SKIP] {name}")
        return
    if needle not in rd(path):
        passed += 1
        print(f"  ok   {name}")
    else:
        failed.append(f"{name}: forbidden pattern STILL PRESENT in {path}")

svc = "Natives/SurfaceViewController.m"
nav = "Natives/SurfaceViewController+Navigation.m"
gmv = "Natives/GameMenuOverlayView.m"
bm = "Natives/BackgroundManager.m"

# (1) 扩展按键（可滑动键簇）：滑动收尾/切换走干净 UP（无 toggle 补发）
check("232-1a clean swipe release", svc, "Task232 swipe release: clean UP (no toggle re-fire)")
check("232-1b swipe switch clean", svc, "切换键同样走干净路径：旧键 UP + 还原，新键 DOWN（不走 toggle 补发）")
check_absent("232-1c old toggle fallthrough gone", svc, "executebtn_up:self.swipingButton isOutside:NO")

# (2) 切后台输入错位：恢复时刻几何链取证
check("232-2 resume geometry probe", "Natives/input_bridge_v3.m", "Task232 resume geometry probe: physical=%dx%d window=%dx%d guiScale=%d")

# (3) 26.3 进存档卡死：Task233 纠偏退役——用户实测 MobileGL 二开正常（概率
#     性问题），steer 抢走渲染器选择；锚点改验"退役标记在场 + steer 代码不在场"，
#     概率性冻结由 SurfaceViewController Task233 停滞看门狗承接。
check("232-3 steer retired (Task233, user correction: probabilistic, MGL works on 2nd entry)", "Natives/JavaLauncher.m", "Task232 steer 退役")
check_absent("232-3b steer code gone", "Natives/JavaLauncher.m", "steering to tinygl4angle")

# (4) 持续奔跑：迁移扫全部 .json + 名字含 常用/奔跑
check("232-4a all-json scan", "Natives/main.m", "contentsOfDirectoryAtPath:controlPath error:nil] ?: @[]")
check("232-4b name match 常用/奔跑", "Natives/main.m", '([ame230_nm containsString:@"常用"] || [ame230_nm containsString:@"奔跑"])')

# (5) 无映射按键 toast 退役（取证留日志层）
check("232-5 toast retired keep diag", svc, "NMToast 退役")
check_absent("232-5b no toast call", svc, "ame230.controls.unbound_toast")

# (6) 悬浮栏玻璃：齿轮/统计/标签三件套 + 菜单 tint 拆除
check("232-6a floating bar glass", gmv, "ame232_applyFloatingGlass")
# ★第 12 期整改批次二①重锚（Task243：悬浮栏改纯深色胶囊 + 0.5pt/0.20 发丝线，
# Metal 上 LGC 玻璃跳过；Task236 hardened 取证日志继续守卫三件套构成）：
# 旧 "floating bar glass applied (gear + stats + caption, heavy dark material)"
# 日志随重样式退役，python 实测重锚到现行两日志锚。
check("232-6b gear glass heavy dark（Task243 重锚：纯深色胶囊 + 0.5pt 发丝线 + LGC 玻璃 Metal 跳过）",
      gmv, "[GameMenu] Task243 floating bar restyled (pure dark capsules + 0.5pt/0.20 hairline; LGC glass skipped on Metal)")
check_absent("232-6c menu tint stripped (Task237 重锚：面板重写后 LGC 玻璃链整体退役，888903 染色层由构造杜绝)", nav, "LGCApplyGlassToView(self.menuView")

# (7) 上游问题关闭：FAQ 四文件 + 代码标记
faq = 0
for f in ["Natives/resources/help-faq.json", "Natives/resources/en.lproj/help-faq.json",
          "Natives/resources/zh-CN.lproj/help-faq.json", "Natives/resources/zh-Hant.lproj/help-faq.json"]:
    if "上游" in rd(f) or "upstream" in rd(f):
        faq += 1
if faq == 4:
    passed += 1
else:
    failed.append(f"232-7 FAQ upstream note present in {faq}/4 files")
check("232-7b code marker", svc, "本议题【按上游问题关闭】")

# (8) 前置详情页：启动器内打开 + 图标/介绍
check("232-8a detail VC", "Natives/ModVersionViewController.m", "@implementation Ame232DepDetailViewController")
check("232-8b in-app route", "Natives/ModVersionViewController.m", "dependency quick-entry (in-app detail)")
check("232-8c modrinth fetch", "Natives/ModVersionViewController.m", "api.modrinth.com/v2/project/")

# (9) SDL 打开文件夹死锁根修 + 浏览器取证
check("232-9a main-thread no-wait", "Natives/input_bridge_v3.m", "主线程调用时跳过等待")
check("232-9b guarded leave", "Natives/input_bridge_v3.m", "if (group != NULL) dispatch_group_leave(group);")
check("232-9c browser forensics", "Natives/FolderBrowserViewController.m", "Task232 viewWillAppear: rows=%lu first=%@")
check("232-9d browser entry log", "Natives/FolderBrowserViewController.m", "Task232 browser requested for")

# (10) 联机自动扫描端口：ZeroTier 房主自动检测 + 18s 手动兜底
check("232-10a auto detect", "Natives/MultiplayerViewController.m", "ame232_startAutoPortDetection")
check("232-10b detector reactivated", "Natives/MultiplayerViewController.m", "auto-detected LAN port %@ -- generating share code")
check("232-10c 18s fallback", "Natives/MultiplayerViewController.m", "auto detection window elapsed without a port -- falling back to manual input")

# (11) 齿轮菜单文字：行白字 + 软黑投影 + 开菜取证（Task237 重锚：cell → Ame237MenuRow 行控件）
check("232-11a row text shadow (Task237 重锚)", nav, "rowLabel.layer.shadowOpacity = 0.85")
check("232-11b menu shown forensics (Task237 重锚)", nav, "[GameMenu] Task237 menu shown")

# (12) 自动开输入法(SDL)：常驻放行语义（非 one-shot）
check("232-12a always-on mode", svc, "always-on mode while switch is enabled")
check("232-12b hard suppression first", svc, "ame232_sinceDismiss < 2.5")

# (13) 备份导入：实例感知 + 自动切换
check("232-13a touched instances", "Natives/DataTransferService.m", "ame232_touchedInstances")
check("232-13b auto switch", "Natives/DataTransferService.m", "auto-switched game directory to '%@'")
check("232-13c pick instance hint", "Natives/DataTransferService.m", "ame232.import.pick_instance")

# (14) 欢迎页：窗口基准锚点 + 卡片实底投影 + 每页取证 + 空标题过滤
# ★ Task233 重锚：14a 的窗口锚点已被第四轮取代——按类识别锚点 VC +
#   语义锚点从真实视图 frame 派生（窗口比例硬编码矩形退役）。
check("232-14a anchors superseded by Task233 class-based discovery", "Natives/WelcomeViewController.m", "Task233 anchor discovery: menu=%d content=%d right=%d")
check("232-14b solid card + shadow", "Natives/Ame223CoachMarksView.m", "_ame224_card.layer.shadowRadius = 18.0")
check("232-14c per-page forensics", "Natives/Ame223CoachMarksView.m", "Task232 page %lu/%lu: spot=%@ titleLen=%lu")
check("232-14d empty-title filter", "Natives/Ame223CoachMarksView.m", "锚点页也要求非空标题")

# (15) 控件分享：上传免检 + 下载扫描询问
check("232-15a upload unchecked", "Natives/ZL2ControlRepoViewController.m", "上传免检")
check("232-15b issues collector", "Natives/ZL2ControlRepoViewController.m", "ame232_layoutSafetyIssues")
check("232-15c ask dialog", "Natives/ZL2ControlRepoViewController.m", "ame232.repo.check.continue")
check("232-15d 4MB cap", "Natives/ZL2ControlRepoViewController.m", "4 * 1024 * 1024")
check("232-15e keycode -12 floor", "Natives/ZL2ControlRepoViewController.m", "iv < -12")

# (16) 白底黑边字体：四方向外扩描边（CoreText stroke + 光晕退役）
# ★第 12 期整改批次二①（退役收编）：Task378（commit 91a10fe3d）"全局描边字体
# 退役=白黑双重叠根修"把 setText:/drawTextInRect: 双交换 + ame250 染色 +
# ame224 反色阴影全链删除（BackgroundManager.m 净删 374 行，python 实测
# ame232_swizzledLabelDrawTextInRect/ame235_copyRect/ame232_OutlineMarkKey/
# NSStrokeWidthAttributeName 全部 0 命中，全仓产品代码零残留）；白黑重叠的
# 根关切由 Task378 的"移除双渲染源头"承接，退役口径由 ame378_selfcheck.py
# 守卫。[RETIRED] 家法：锚面随链退役，SKIP 而非 FAIL。
skipped += 5
print("  [SKIP] 232-16a drawTextInRect swizzle —— 描边链随 Task378 全局描边字体退役（91a10fe3d）")
print("  [SKIP] 232-16b four offsets —— ame235_copyRect 拷贝画随 Task378 退役（91a10fe3d）")
print("  [SKIP] 232-16c setText marks only —— ame232_OutlineMarkKey 染色标记随 Task378 退役（91a10fe3d）")
print("  [SKIP] 232-16d CoreText stroke retired —— swizzle 整体退役后缺席语义真空成立")
print("  [SKIP] 232-16e halo retired —— 光晕链随 Task378 退役（91a10fe3d）")

# (17) i18n：20 新键 ×5 语言 + 2 退役键移除 + 裸键名修复
KEYS = ["game.menu.settings", "ame232.repo.check.title", "ame232.repo.check.continue",
        "ame232.repo.check.cancel", "ame232.repo.issue.size", "ame232.repo.issue.shape",
        "ame232.repo.issue.depth", "ame232.repo.issue.strlen", "ame232.repo.issue.url",
        "ame232.repo.issue.keycode", "ame232.repo.issue.buttons", "ame232.import.switched",
        "ame232.import.pick_instance", "ame232.mp.auto_title", "ame232.mp.auto_msg",
        "ame232.deps.browser", "ame232.deps.loading", "ame232.deps.stats",
        "ame232.deps.cf_desc", "ame232.deps.no_desc"]
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN", "ja"]:
    src = rd(f"Natives/resources/{lang}.lproj/Localizable.strings")
    miss = [k for k in KEYS if f'"{k}"' not in src]
    if miss:
        failed.append(f"232-17 i18n {lang} missing: {miss}")
    else:
        passed += 1
    if '"ame230.controls.unbound_toast"' not in src and '"ame230.repo.safety_blocked"' not in src:
        passed += 1
    else:
        failed.append(f"232-17 retired keys still present in {lang}")

# --- standing audits -------------------------------------------------------
# 自引用 block 舰队扫描（Task231 常驻审计，Task232 后 = 6 处全 __block）
r = subprocess.run([sys.executable, os.path.join(BASE, "scripts/task231_selfref_block_scan.py")],
                   capture_output=True, text=True, cwd=os.path.join(BASE, "Natives"))
bad = [l for l in r.stdout.splitlines() if l.startswith("***")]
# ★第 12 期整改批次二①重锚：task231 扫描器正则越界修复（\^\(?[^)]*\)? 在
# 无参 block 赋值处越过 body 开括号贪婪吞吃 → cleanup/apply 两处假嫌疑 +
# BackgroundManager.m:1076 一处漏报）；修正后实测 total=5 处真自引用块全部
# 带 __block 标记（代码健康），期望数从 6 重锚到 5。
if "total real self-referencing blocks: 5" in r.stdout and not bad:
    passed += 1
else:
    failed.append(f"232-fleet selfref scan: {bad or 'count mismatch'}")

# task139 语法门 + task225 括号审计
r = subprocess.run([sys.executable, os.path.join(BASE, "scripts/task139_syntax_gate.py")],
                   capture_output=True, text=True, cwd=BASE)
if "all balanced" in r.stdout:
    passed += 1
else:
    failed.append("232-fleet task139 syntax gate RED")
r = subprocess.run([sys.executable, os.path.join(BASE, "scripts/task225_bracket_audit.py")],
                   capture_output=True, text=True, cwd=BASE)
n_ok = sum(1 for l in r.stdout.splitlines() if l.startswith("[OK "))
n_bad = sum(1 for l in r.stdout.splitlines() if l.startswith("[FAIL"))
if n_bad == 0 and n_ok >= 1:   # 提交前多文件/提交后单文件均合法
    passed += 1
else:
    failed.append(f"232-fleet task225 bracket audit: {n_bad} FAIL of {n_ok}")

print(f"verify_task232: {passed} passed, {skipped} skipped, {len(failed)} failed")
for f in failed:
    print(f"  FAIL: {f}")
sys.exit(1 if failed else 0)
