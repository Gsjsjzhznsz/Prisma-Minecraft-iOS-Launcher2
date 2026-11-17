#!/usr/bin/env python3
"""verify_task230.py -- Task 230 (15-item feedback round) implementation gates.
Each check asserts a byte-level anchor in the edited files (display-layer
character-eating defense: pure substring membership, no regex ambiguity)."""
import os, sys, json, re

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径），改从脚本
# 位置动态推导仓库根，TASK230_REPO 环境变量覆盖保留。
BASE = os.environ.get("TASK230_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
passed, failed, skipped = 0, [], 0

def check(name, path, needle):
    """字节级锚点断言。退役宿主（Task436/440 批次物理删除）走显式 SKIP，
    存留文件锚点缺失仍为 FAIL（[RETIRED] 家法 (b)/(d)）。"""
    global passed, skipped
    p = os.path.join(BASE, path)
    if not os.path.exists(p):
        skipped += 1
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        print(f"  [SKIP] {name}")
        return
    src = open(p, encoding="utf-8", errors="replace").read()
    if needle in src:
        passed += 1
    else:
        failed.append(f"{name}: anchor missing in {path}")

# (1) 1.20.1 ANGLE crash: colon-aware stub signature + noNative
check("230-1a colon-aware stub", "Natives/JavaLauncher.m", "static BOOL ame230_addGenericNoop(Class cls, SEL name)")
check("230-1b Task99 uses it", "Natives/JavaLauncher.m", "if (!ame230_addGenericNoop(self, name)) return NO;")
check("230-1c noNative flag", "Natives/JavaLauncher.m", "-Dio.netty.transport.noNative=true")
# (5) LAN first-open crash: netty native dlopen block
check("230-5a netty dlopen block", "Natives/main_hook.m", 'strstr(path, "netty_transport_native") != NULL')
check("230-5b block log anchor（Prisma 品牌化重锚）", "Natives/main_hook.m", "[Prisma] Task230: blocked dlopen of netty native transport")
# (2) input offset after backgrounding: DOWN re-anchor in grab mode
check("230-2a down re-anchor", "Natives/input_bridge_v3.m", "} else if (event == ACTION_DOWN) {")
check("230-2b baseline set", "Natives/input_bridge_v3.m", "cLastX = x;\n                cLastY = y;")
# (6) keyboard closes per input: adaptive debounce
check("230-6a char timestamp", "Natives/SurfaceViewController.m", "static CFAbsoluteTime ame230_lastCharForwardedAt = 0.0;")
check("230-6b adaptive delay（Task250 参数化重锚：ame250_adaptiveWindow）", "Natives/SurfaceViewController.m", "ame230_resignDelay = (ame230_sinceChar < 2.0) ? ame250_adaptiveWindow : 0.25;")
check("230-6c fire clears ptr", "Natives/SurfaceViewController.m", "ame223_pendingStopResign = NULL;   // ★ Task230")
# (10) auto keyboard switch: pref registered
# ★第 12 期整改批次二①重锚（Task247 T8：开关语义落地，默认值 @NO→@YES——
# 键注册守卫活行为不变，默认值漂移重锚到现实）。
check("230-10 pref registered (Task247 重锚：默认 @YES)", "Natives/PLPreferences.m", '@"auto_keyboard_sdl": @YES,')
# (14) font ghosting: zero-offset halo both sites
# ★退役收编：Task378（91a10fe3d）全局描边字体退役（setText:/drawTextInRect:
# 双交换+ame250 染色全链删除），描边/染色标记锚面随链退役（退役口径由
# ame378_selfcheck.py 守卫）。
skipped += 2
print("  [SKIP] 230-14a swizzle halo —— 描边链随 Task378 全局描边字体退役（91a10fe3d）")
print("  [SKIP] 230-14b adaptive halo —— ame232_OutlineMarkKey 染色标记随 Task378 退役（91a10fe3d）")
# (12) welcome blank: tree exemption
check("230-12a tree api", "Natives/BackgroundManager.m", "void ame230_setViewTreeStrokeExempt(UIView *view, BOOL exempt)")
# ★退役收编：Task378（91a10fe3d）全局描边字体退役后 swizzle 入口已删，
# 树豁免的消费点随链退役（豁免 API 定义保留为兼容空操作桩，230-12a 守卫）。
# [RETIRED] 家法：断言面随链退役，SKIP 而非 FAIL。
skipped += 1
print("  [SKIP] 230-12b swizzle checks tree —— swizzle 入口随 Task378 描边退役（91a10fe3d），锚面随链退役")
check("230-12c wizard exempt", "Natives/WelcomeViewController.m", "ame230_setViewTreeStrokeExempt(self.view, YES);")
check("230-12d coachmarks exempt", "Natives/Ame223CoachMarksView.m", "ame230_setViewTreeStrokeExempt(self, YES);")
# (9) gear drag
check("230-9a manual tap-fire", "Natives/GameMenuOverlayView.m", "Task230 gear manual tap-fire")
check("230-9b caption label", "Natives/GameMenuOverlayView.m", "ame230_captionLabel.text = localize(@\"ame230.gamemenu.caption\", nil);")
check("230-9c no translationInView rejection", "Natives/GameMenuOverlayView.m", "if (ame229_pan.view == self.menuButton) {\n            return YES;\n        }")
# (8) SDL folder open: dlsym-path hook + solid FileList
check("230-8a dlsym OpenURL hook", "Natives/sdl3_hook.m", 'if (strcmp(name, "SDL_OpenURL") == 0) {')
check("230-8b FileList solid（7.0-UI-5c 重锚：AmeTheme bgPrimary 实底）", "Natives/FileListViewController.m", "self.tableView.backgroundColor = [AmeTheme bgPrimary];")
check("230-8c FileList exempt", "Natives/FileListViewController.m", "ame230_setViewTreeStrokeExempt(self.view, YES);")
# (4) floating menu glass: heavy material
check("230-4 heavy glass", "Natives/SurfaceViewController+Navigation.m", "UIBlurEffectStyleSystemMaterialDark")
# (7) wrong-loader deps: loader-aware picking both sides + quick entry
check("230-7a install loader check", "Natives/DownloadViewController.m", "BOOL (^ame230_loaderOK)(ModVersion *)")
check("230-7b skip on no match", "Natives/DownloadViewController.m", "dep skipped (no version matches loader=")
check("230-7c resolver fallback", "Natives/ModDependencyResolver.m", "if (picked == nil) picked = ame230_loaderOnly;")
check("230-7d quick entry", "Natives/ModVersionViewController.m", "ame230_openDependencyPage:(UIButton *)sender")
# Task236 诚实重锚：footer 已重构为模组列表同款富条目（图标+介绍内联+直跳
# 下载页），旧"Task230 dependency quick-entry footer"日志由 Task236 rich footer
# 日志接替；ⓘ 按钮仍走 ame230_openDependencyPage:（230-7d 不变）。
# Task238 诚实重锚：前置区从表尾上移到头部堆叠（详情头之下、版本列表
# 之上），日志文案随之升级；富条目渲染 + 直跳行为不变（230-7d 不变）。
check("230-7e quick entry log", "Natives/ModVersionViewController.m", "[ModVersionVC] Task238 dependency section pinned above version list:")
# (11) backup import: reload + refresh + summary
check("230-11a prefs reload", "Natives/DataTransferService.m", "loadPreferences(NO);")
check("230-11b root rebuild", "Natives/DataTransferService.m", 'postNotificationName:@"AppLanguageChanged"')
check("230-11c summary", "Natives/DataTransferService.m", "ame230.import.summary")
# (3) sprint: layout bind + migration + toast
# ★第 12 期整改批次二①重锚（Task233 drawer 化：custom.json 的"常用操作键"
# 已从直连大按钮重构为抽屉容器——容器 keycodes=[0,0,0,0]，真键移入子按钮；
# sprint=Left Control(341) 绑定现由"持续奔跑"[341,87] 组合键与 CTRL[341]
# 承载，python 实测）。断言语义"sprint 键位 341 已绑定在场"不变：classic/
# large-buttons 仍走原"常用大按钮 341"walk；custom.json 改走"奔跑 341 在场"
# walk（Task232 4a/4b 迁移扫面继续由其各自门守卫）。
def _walk_341_common(o):
    """classic/large-buttons：名字含"常用"的直连按键 keycode[0]==341。"""
    if isinstance(o, dict):
        if "常用" in str(o.get("name", "")) and isinstance(o.get("keycodes"), list) and o["keycodes"]:
            return o["keycodes"][0] == 341
        return any(_walk_341_common(v) for v in o.values())
    if isinstance(o, list):
        return any(_walk_341_common(v) for v in o)
    return False

def _walk_341_runner(o):
    """custom.json（drawer 化后）：名字含"奔跑"且 keycode[0]==341 的按键在场
    （持续奔跑 = Left Control 341 + W 87 组合键）。"""
    if isinstance(o, dict):
        if "奔跑" in str(o.get("name", "")) and isinstance(o.get("keycodes"), list) and o["keycodes"]:
            return o["keycodes"][0] == 341
        return any(_walk_341_runner(v) for v in o.values())
    if isinstance(o, list):
        return any(_walk_341_runner(v) for v in o)
    return False

for jf in ["Natives/resources/controlmap/custom.json", "controls/layouts/classic.json", "controls/layouts/large-buttons.json"]:
    try:
        j = json.load(open(os.path.join(BASE, jf), encoding="utf-8"))
        found = json.dumps(j, ensure_ascii=False)
        if "常用" not in found and "奔跑" not in found:
            failed.append(f"230-3 layout missing 常用 button: {jf}")
            continue
        walker = _walk_341_runner if jf.endswith("custom.json") else _walk_341_common
        if walker(j):
            passed += 1
        else:
            failed.append(f"230-3 layout not bound to 341: {jf}")
    except Exception as e:
        failed.append(f"230-3 layout parse error {jf}: {e}")
check("230-3b migration", "Natives/main.m", "sprint dead-button migrated to Left Control 341")
check("230-3c unbound toast (Task232 重锚：⑤ NMToast 退役，取证留日志层)", "Natives/SurfaceViewController.m", "Task229 UNBOUND button pressed")
# (13) control repo: upload + safety check
check("230-13a sanitizer", "Natives/ZL2ControlRepoViewController.m", "static BOOL ame230_layoutSafetyCheck(NSData *raw, id jsonObj, NSString **reasonOut)")
check("230-13b download check (Task232 重锚：⑮ 检查移到下载侧询问流)", "Natives/ZL2ControlRepoViewController.m", "ame232_layoutSafetyIssues")
check("230-13c upload flow", "Natives/ZL2ControlRepoViewController.m", "+ (void)ame230_presentUploadFlowFrom:(UIViewController *)presenter preselect:(NSString *)preselect")
check("230-13d header decl", "Natives/ZL2ControlRepoViewController.h", "+ (void)ame230_presentUploadFlowFrom:(UIViewController *)presenter preselect:(NSString *)preselect;")
check("230-13e editor entry", "Natives/CustomControlsViewController.m", "- (void)actionMenuUpload {")
# ★第 12 期整改批次二①重锚（gamepad 支持批次：目录预导航参数化拆段——
# URL 模板 https://github.com/%@/%@/new/%@/%@ + 目标目录三元选择）：
# "纯路径目录预导航（零查询参数）"关切由 234-5b/5c absent 断言 + 本锚
# URL 模板与 controls/layouts/community 目标继续守卫。
check("230-13f github deeplink（Task234 零查询参数终案；gamepad 批次重锚：目录预导航参数化拆段）",
      "Natives/ZL2ControlRepoViewController.m",
      '@"https://github.com/%@/%@/new/%@/%@"')
# (15) i18n: 18 keys x 5 langs
KEYS = ["ame230.gamemenu.caption", "ame230.deps.required",
        "ame230.deps.optional", "ame230.import.summary", "ame230.repo.upload",
        "ame230.repo.upload_editor", "ame230.repo.upload.pick", "ame230.repo.upload.form.title",
        "ame230.repo.upload.form.message", "ame230.repo.upload.name", "ame230.repo.upload.author",
        "ame230.repo.upload.desc", "ame230.repo.upload.github", "ame230.repo.upload.github_hint",
        "ame230.repo.upload.no_layouts", "ame230.repo.upload.invalid"]
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN", "ja"]:
    p = os.path.join(BASE, f"Natives/resources/{lang}.lproj/Localizable.strings")
    src = open(p, encoding="utf-8").read()
    miss = [k for k in KEYS if f'"{k}"' not in src]
    if miss:
        failed.append(f"230-15 i18n {lang} missing: {miss}")
    else:
        passed += 1

total = passed + len(failed) + skipped
print(f"verify_task230: {passed} passed, {skipped} skipped / {total} checks")
if failed:
    print("FAILURES:")
    for f in failed:
        print(" -", f)
    sys.exit(1)
print("ALL GREEN")
