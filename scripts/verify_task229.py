#!/usr/bin/env python3
"""verify_task229 -- Task 229 (11-item feedback round on the Task228 build,
e24a60a9 log set) anchor verification.

Item map:
  1  ANGLE non-SDL crash + bg input offset   -> A (AppKitStub ext) + B (resume hook)
  2  sprint dead + right shift relapsed      -> B (mod replay) + C (toggleSprint + keybind sync)
  3  liquid glass floating bar no effect     -> D (menu composite glass)
  4  dependency sheet + footer dead          -> E (apiSource + sniff)
  5  folder browser blank / SDL dead         -> F (solid sheet + CTC-on-SDL3)
  6  keyboard cannot close                   -> G (hard suppression window)
  7  gear un-openable + FCL auto-IME switch  -> H (pan threshold + switch)
  8  backup import no effect                 -> I (pickerMode + logging)
  9  welcome tour blank                      -> J3 (coach label exemption)
  10 stroke font black lines                 -> J1 (stroke rework)
  11 i18n completeness                       -> K (12 keys x 5 langs + audits)
"""
import re, subprocess, sys, os

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径：任何门不得
# 依赖仓库外绝对路径），改从脚本位置动态推导仓库根，TASK229_REPO 环境变量覆盖保留。
os.chdir(os.environ.get("TASK229_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PASS = 0; FAIL = 0; SKIPPED = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print(f"[PASS] {name}")
    else: FAIL += 1; print(f"[FAIL] {name} {detail}")

def skip(name, path, why=""):
    """退役面断言显式 SKIP：宿主已删/断言面已真退役（[RETIRED] 家法 (b)）。"""
    global SKIPPED
    SKIPPED += 1
    print(f"[SKIP] {name} —— {path}{('，' + why) if why else ''}")

def retired(p):
    return not os.path.exists(p)

def rd(p): return open(p, encoding='utf-8', errors='replace').read()

# ---------- A: AppKitStub extension (JavaLauncher.m) ----------
jl = rd('Natives/JavaLauncher.m')
check("A1 NSImage stub class registered", 'objc_allocateClassPair(objc_getClass("NSObject"), "NSImage", 0)' in jl)
check("A2 NSData legacy b64 selector added", 'initWithBase64Encoding:' in jl and 'class_addMethod(nsDataCls' in jl)
check("A3 install hooked at JLI_Launch site", jl.count('ame229_installIconPathStubs();') == 1)
check("A4 NSImage stub initWithData IMP", 'ame229_image_initWithData' in jl)
check("A5 install anchor log", 'Task229: NSImage stub + NSData legacy-b64 selector installed' in jl)
# the stub install must be idempotent + guarded
check("A6 real-macOS guard", 'real NSImage present, icon stubs not needed' in jl)
# structural: functions must live OUTSIDE ame99 (the brace we restored)
i99 = jl.find('static void ame99_installAppKitMenuStubs(void)')
i99end = jl.find('ame229_image_initWithData')
seg = jl[i99:i99end]
# the ame99 body must contain its own closing brace before the Task229 comment
import re as _re
closing = _re.search(r'numberOfItems=0\)"\);\n}', seg)
check("A7 ame99 closed before Task229 functions", closing is not None)

# ---------- B: resume reassert (input_bridge + SceneDelegate) ----------
ib = rd('Natives/input_bridge_v3.m')
sd = rd('Natives/SceneDelegate.m')
check("B1 resume reassert defined", 'void ame229_inputResumeReassert(void)' in ib)
check("B2 cursor baseline reset", 'cLastX = cursorX;' in ib and 'cLastY = cursorY;' in ib)
check("B3 toggle-held mod replay map", 'ame229_modMap' in ib and '{AME66_KMOD_RSHIFT, 229}' in ib)
check("B4 ACTION_MOVE baseline refresh (Task232 重锚：Task230 DOWN 重锚后 MOVE+DOWN 双写点)", ib.count('cLastX = x;') == 2)
check("B5 SceneDelegate hook", 'ame229_inputResumeReassert();' in sd)
check("B6 CTC register-on-SDL3 helper", 'static void ame229_registerCTCOnce(void)' in ib)
check("B7 GetCreatedJavaVMs recovery", 'JNI_GetCreatedJavaVMs' in ib)
check("B8 called from Amethyst_SetSDLWindow", 'ame229_registerCTCOnce();' in ib)
check("B9 SDL3-path anchor log", 'Task229 CTCDesktopPeer natives registered via Amethyst_SetSDLWindow' in ib)

# ---------- C: sprint toggle + keybind sync (LauncherPreferencesViewController.m) ----------
print("-- C. sprint toggle + keybind sync（设置页宿主） --")
if retired('Natives/LauncherPreferencesViewController.m'):
    print("  [RETIRED] Natives/LauncherPreferencesViewController.m —— 退役批次已删，跳过相关断言（容错壳）")
    for _c in ["C1 all-instance options scanner", "C2 toggleSprint writer", "C3 keybind sync method",
               "C4 sprint settings entry", "C5 keybind sync settings entry", "C6 toggleSprint log typo fixed"]:
        skip(_c, "Natives/LauncherPreferencesViewController.m", "旧设置页宿主已随退役批次删除（设置域由 ZL2 接棒）")
else:
    lp = rd('Natives/LauncherPreferencesViewController.m')
    check("C1 all-instance options scanner", 'ame229_allInstanceOptionsPaths' in lp)
    check("C2 toggleSprint writer", 'ame229_writeToggleSprint:toOptions:' in lp or 'ame229_writeToggleSprint' in lp)
    check("C3 keybind sync method", 'ame229_syncKeybindsAcrossInstances' in lp)
    check("C4 sprint settings entry", '"mc_toggle_sprint"' in lp)
    check("C5 keybind sync settings entry", '"keybind_sync"' in lp)
    check("C6 toggleSprint log typo fixed", 'toggleSprint written' in lp and 'toggleSpring written' not in lp)

# ---------- D: floating menu glass (SurfaceViewController+Navigation.m) ----------
# Task237 重锚：游戏内菜单面板已彻底重写为自定义 UIView（旧 UITableView +
# LGCApplyGlassToView 塞玻璃层的路线被用户明令退役）。本区锚点改为验证
# 同一关切在 Task237 现实下的形态：风格应用函数存在、磨砂层分层受控、
# 内容恒在磨砂之上、风格切换广播接力不变。
nav = rd('Natives/SurfaceViewController+Navigation.m')
check("D1 style apply helper (Task237 renamed)", 'ame237_applyMenuStyle' in nav and 'ame229_reapplyMenuGlass' not in nav)
check("D2 LGC glass-in-table retired (Task237)", 'LGCApplyGlassToView(self.menuView' not in nav and
      'LGCRemoveGlassFromView(self.menuView' not in nav)
# ★第 12 期整改批次二①重锚（Task243：面板引入 ame243_snap 游戏快照层）：
# 磨砂层插入点从 atIndex:0 重锚为 aboveSubview:ame243_snap（"磨砂受控分层、
# 内容恒在磨砂之上"的关切不变；python 实测）。
check("D3 layered blur above snapshot + rows above (Task237/243 重锚)", 'insertSubview:ame237_blur aboveSubview:ame243_snap]' in nav and
      'bringSubviewToFront:ame237_scroll' in nav)
check("D4 style-gated", 'LGCIsGlassStyleActive()' in nav)
check("D5 style-change observer", 'ame229_handleBackgroundUIEffectChanged' in nav and 'BackgroundUIEffectChanged' in nav)
check("D6 import present", 'LiquidGlassCompat.h' in nav)

# ---------- E: dependency resolver (ModVersion.m + ModDependencyResolver.m) ----------
mv = rd('Natives/ModVersion.m')
res = rd('Natives/ModDependencyResolver.m')
check("E1 Modrinth apiSource set", '_apiSource = 1;   // Modrinth' in mv)
check("E2 apiSource only in Modrinth branch + CF branch keeps 2", mv.count('_apiSource = 2;') == 1)
check("E3 shape sniffing fallback", 'ame229_mrShape' in res and 'ame229_cfShape' in res)
check("E4 sniff only when not declared Modrinth", 'if (apiSource != 1) {' in res)

# ---------- F: folder browser + label exemption ----------
fb = rd('Natives/FolderBrowserViewController.m')
import re as _re
_fb_code = _re.sub(r'//[^\n]*', '', _re.sub(r'/\*.*?\*/', '', fb, flags=_re.S))
check("F1 solid sheet (no code-level transparency call)", _fb_code.count('makeViewControllerTransparent') == 0)
# ★第 12 期整改批次二①重锚（7.0-UI-5c：Fluent 设计令牌=颜色单一事实源）：
# 页面底色从 systemBackgroundColor 重锚为 AmeTheme bgPrimary 令牌（语义自适应不变）。
check("F2 systemBackground view (7.0-UI-5c 重锚：AmeTheme bgPrimary 令牌)", '[AmeTheme bgPrimary];' in fb)
check("F3 empty state on tableHeaderView", 'tableHeaderView = ame229_hv' in fb)
check("F4 cell labels exempt from stroke", fb.count('ame229_labelSetStrokeExempt') == 5)

# ---------- G: keyboard latch hard suppression (SurfaceViewController.m) ----------
svc = rd('Natives/SurfaceViewController.m')
check("G1 hard suppression window", 'Task229 hard suppression' in svc)
check("G2 2.5s window constant (Task232 重锚：硬抑制块变量随 ⑫ 重排更名)", 'ame232_sinceDismiss < 2.5' in svc)
check("G3 recent-touch clear retired", 'recent touch"' not in svc)
# ★第 12 期整改批次二①重锚（Task247：auto_keyboard_sdl 开关语义落地后
# chat-opener 放行日志改写为宽限语义）："聊天开键在硬抑制窗外仍被尊重"的
# 关切由 Task247 宽限日志承接（python 实测重锚）。
check("G4 chat-opener still honored (post-window；Task247 重锚：宽限放行日志)",
      "Task247 keyboard shown via chat-opener grace" in svc
      and "ame161_lastSentKeyWasChatOpener(3.0)" in svc)

# ---------- H: gear pan threshold + auto-IME switch ----------
gm = rd('Natives/GameMenuOverlayView.m')
check("H1 pan shouldBegin gate", 'gestureRecognizerShouldBegin' in gm)
check("H2 gear pan threshold (Task232 重锚：Task230 重写为 pan 恒开始 + Ended 手动补 tap)", 'Task230 gear manual tap-fire' in gm)
check("H3 tap-chain logging", 'Task229 gear tap #' in gm)
check("H4 pan delegate set", 'pan.delegate = self;' in gm)
check("H5 auto-keyboard gate (first Start only)", 'ame229_autoKbShownThisSession' in svc)
check("H6 pref key", 'control.auto_keyboard_sdl' in svc)
if retired('Natives/LauncherPreferencesViewController.m'):
    print("  [RETIRED] Natives/LauncherPreferencesViewController.m —— 退役批次已删，跳过相关断言（容错壳）")
    skip("H7 settings switch", "Natives/LauncherPreferencesViewController.m", "旧设置页宿主已随退役批次删除")
else:
    check("H7 settings switch", '"auto_keyboard_sdl"' in lp)
check("H8 session reset in viewDidLoad", 'ame229_autoKbShownThisSession = NO;' in svc)
check("H9 unbound-button diagnostic", 'Task229 UNBOUND button pressed' in svc)

# ---------- I: import picker mode (DataTransferService.m) ----------
dts = rd('Natives/DataTransferService.m')
check("I1 picker mode enum", 'Ame229PickerModeImportZip' in dts and 'Ame229PickerModeExportDestination' in dts)
check("I2 mode consumed on dispatch", 'self.ame229_pickerMode = Ame229PickerModeNone;' in dts)
check("I3 import presented log", 'Task229: import picker presented' in dts)
check("I4 didPick log", 'Task229: didPickDocumentsAtURLs' in dts)
check("I5 cancelled log", 'Task229: picker cancelled' in dts)
check("I6 import branch routes to performImport", 'ame229_mode == Ame229PickerModeImportZip' in dts)
check("I7 export sites set mode", dts.count('Ame229PickerModeExportDestination') == 4)

# ---------- J: font stroke rework (BackgroundManager.m + coach marks) ----------
bm = rd('Natives/BackgroundManager.m')
cm = rd('Natives/Ame223CoachMarksView.m')
# ★第 12 期整改批次二①（退役收编）：Task378（commit 91a10fe3d）"全局描边字体
# 退役=白黑双重叠根修"把 setText:/drawTextInRect: 双交换+ame250 染色全链删除
# （BackgroundManager.m 净删 374 行，python 实测描边/光晕 needle 0 命中）；
# J1-J3/J5 锚面随链退役（退役口径由 ame378_selfcheck.py 守卫）。J4 豁免 API
# 按 Task378 家法保留为兼容空操作桩（定义在位），J6 调用点继续守卫。
skip("J1 stroke width（四方向 0.6pt 外扩描边）", "BackgroundManager.m 描边渲染链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("J2 semi-transparent stroke color", "BackgroundManager.m 描边渲染链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("J3 shadow", "BackgroundManager.m 光晕链", "Task378 全局描边字体整体退役（91a10fe3d）")
check("J4 exemption API（Task378 后保留为兼容空操作桩，定义在位）",
      'ame229_labelSetStrokeExempt' in bm and 'ame229_labelIsStrokeExempt' in bm)
skip("J5 swizzle honors exemption", "BackgroundManager.m swizzle 入口",
     "swizzle 随 Task378 退役，豁免消费点随链退役")
check("J6 coach title exempt", cm.count('ame229_labelSetStrokeExempt') == 3)

# ---------- K: i18n ----------
KEYS = ['preference.title.auto_keyboard_sdl', 'preference.title.mc_toggle_sprint',
        'preference.title.keybind_sync', 'ame229.sprint.title', 'ame229.sprint.on.desc',
        'ame229.sprint.off.desc', 'ame229.sprint.turn_on', 'ame229.sprint.turn_off',
        'ame229.sprint.result', 'ame229.keybind.sync.one_instance',
        'ame229.keybind.sync.no_bindings', 'ame229.keybind.sync.done']
for lang in ['en', 'zh-Hans', 'zh-Hant', 'zh-CN', 'ja']:
    p = f'Natives/resources/{lang}.lproj/Localizable.strings'
    c = rd(p)
    missing = [k for k in KEYS if f'"{k}" =' not in c]
    check(f"K {lang}: all 12 Task229 keys present", not missing, f"missing {missing}")

# used-subset audit: every localize(@"..." key in touched UI files exists in en+zh-Hans
used = set()
# ★退役收编：LauncherPreferencesViewController.m 已随退役批次删除——不参与
# used 取证面（存留三文件守卫继续生效）。
for f in ['Natives/LauncherPreferencesViewController.m', 'Natives/FolderBrowserViewController.m',
          'Natives/SurfaceViewController.m', 'Natives/SurfaceViewController+Navigation.m']:
    if retired(f):
        print(f"  [RETIRED] {f} —— 退役批次已删，跳过相关断言（容错壳）")
        continue
    for m in re.finditer(r'localize\(@"([A-Za-z0-9_.\-]+)"', rd(f)):
        used.add(m.group(1))
en = rd('Natives/resources/en.lproj/Localizable.strings')
zh = rd('Natives/resources/zh-Hans.lproj/Localizable.strings')
miss_en = [k for k in sorted(used) if f'"{k}" =' not in en]
miss_zh = [k for k in sorted(used) if f'"{k}" =' not in zh]
check("K used-subset audit (en)", not miss_en, f"missing {miss_en[:6]}")
check("K used-subset audit (zh-Hans)", not miss_zh, f"missing {miss_zh[:6]}")

# ---------- syntax gates ----------
r = subprocess.run([sys.executable, 'scripts/task139_syntax_gate.py'], capture_output=True, text=True)
check("L task139 syntax gate", r.returncode == 0, r.stdout[-200:] if r.returncode else "")
r = subprocess.run([sys.executable, 'scripts/task225_bracket_audit.py'], capture_output=True, text=True)
check("L bracket audit (touched files)", 'FAIL' not in r.stdout, r.stdout[-300:] if 'FAIL' in r.stdout else "")

print(f"\n===== verify_task229: {PASS} PASS / {SKIPPED} SKIP / {FAIL} FAIL =====")
sys.exit(1 if FAIL else 0)
