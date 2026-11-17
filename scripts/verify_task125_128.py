#!/usr/bin/env python3
"""verify_task125_128.py -- Tasks 125-128（5.1.0 第三轮用户反馈）验证器。

任务对照：
  A. Task125  启动时自动检测更新（NMToast 非侵入提示 + 偏好开关）
  B. Task126  正版登录系统弹窗根治（showDialog window 回收 + toast 化）
  C. Task127  子级面板新拟物基底（NMPanel 单一执法点）
  D. Task128  第三方登录修复（zl2 参照：jar 随包 / 优雅回退 / accountType）
  E. 语法门 + 级联
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASS, FAIL = 0, 0

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

def rd(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()

# ★第 12 期整改批次二①退役容错壳（verify_task136/238 同款 [RETIRED] 家法）：
# 本 verifier 撰写轮次早于 Task436/440 两批退役——旧下载中心/旧账户列表/
# 旧导航壳/旧设置页（LauncherRoot/AccountList/LauncherNavigation/
# LauncherPreferencesViewController）已物理删除。rd 对缺席文件不再抛
# FileNotFoundError，改返空串并打印 [RETIRED] 标注（诚实降级：存留面断言
# 继续生效，退役面断言显式 SKIP）。单跑结论 = 存留面视图，非全量判定。
import functools as _ft
_orig_rd_125 = rd
@_ft.wraps(_orig_rd_125)
def rd(path, *a, **k):
    cand = path if os.path.isabs(path) else os.path.join(REPO, path)
    if not os.path.exists(cand):
        print(f"  [RETIRED] {path} —— 退役批次已删，跳过相关断言（容错壳）")
        return ""
    return _orig_rd_125(path, *a, **k)

SKIP = 0

def skip(name, retired_path, why=""):
    """退役面断言显式 SKIP：宿主文件已随退役批次删除（[RETIRED] 家法 (b)。"""
    global SKIP
    SKIP += 1
    print(f"  [SKIP] {name} —— 断言面随退役文件 {retired_path} 整体退役（[RETIRED] 容错壳{('，' + why) if why else ''}）")

def retired(path):
    return not os.path.exists(os.path.join(REPO, path))

root = rd("Natives/LauncherRootViewController.m")
uc = rd("Natives/UpdateChecker.m")
about_vc = rd("Natives/AboutViewController.m")
lpvc = rd("Natives/LauncherPreferencesViewController.m")
plp = rd("Natives/PLPreferences.m")
bridge = rd("Natives/ios_uikit_bridge.m")
acc = rd("Natives/AccountListViewController.m")
nav = rd("Natives/LauncherNavigationController.m")
# Task138 重锚：Task137 将 NMToast 迁出 NeomorphKit 至 Natives/ 根
toast = rd("Natives/NMToast.m")
# Task138 重锚：Task137 将 NMPanel 原生化重写为 UIViewController+AMEPanel
panel = rd("Natives/UIViewController+AMEPanel.m")
tp = rd("Natives/authenticator/ThirdPartyAuthenticator.m")
ba = rd("Natives/authenticator/BaseAuthenticator.m")
ms = rd("Natives/authenticator/MicrosoftAuthenticator.m")
lo = rd("Natives/authenticator/LocalAuthenticator.m")
cml = rd("Natives/CMakeLists.txt")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("== A. Task125 启动自动检测更新（Task436 退役链重锚：执行链随旧主页根退役，开关行+手动检查保留）==")
check("A1 NMToast 组件存在（Task137 迁至 Natives/ 根）",
      os.path.exists(os.path.join(REPO, "Natives/NMToast.m")) and
      os.path.exists(os.path.join(REPO, "Natives/NMToast.h")))
check("A2 NMToast 无新建 window（挂 mainWindow，Task126 教训）",
      "UIWindow.mainWindow" in toast and "windowLevel = 1000" not in toast)
# ★第 12 期整改批次二①退役降级（家法 (b)）：启动自动检测执行链（一次性守卫/
# 1.5s 延迟/toast 呈现/静默口径）宿主为旧主页根 LauncherRootViewController.m，
# 已随 Task436/440 退役物理删除，ame125_autoUpdateCheckOnce 全树零残留
# （实测）；开关行（A6）与手动检查（ame217_checkForUpdate）保留生效。
_retire_root = retired("Natives/LauncherRootViewController.m")
if _retire_root:
    skip("A3 自动检测一次性守卫 + 偏好开关（general.auto_update_check）", "Natives/LauncherRootViewController.m",
         "启动检测执行链随旧主页根退役；开关行/手动检查由 A6/AboutVC 保留锚定")
    skip("A4 非侵入呈现（toast + 查看动作，无 AlertDialog）", "Natives/LauncherRootViewController.m",
         "同上")
    skip("A5 冷启动延迟 1.5s（避开启动期 UI 竞争）", "Natives/LauncherRootViewController.m",
         "同上")
    skip("A8 静默口径（无更新/出错不打扰：hasUpdate 才提示）", "Natives/LauncherRootViewController.m",
         "同上")
else:
    check("A3 自动检测一次性守卫 + 偏好开关（general.auto_update_check）",
          "ame125_autoUpdateCheckOnce" in root and
          'general.auto_update_check' in root)
    check("A4 非侵入呈现（toast + 查看动作，无 AlertDialog）",
          "NMToast showMessage:msg" in root and "openReleasePage" in root)
    check("A5 冷启动延迟 1.5s（避开启动期 UI 竞争）",
          "1.5 * NSEC_PER_SEC" in root)
    check("A8 静默口径（无更新/出错不打扰：hasUpdate 才提示）",
          "if (!info.hasUpdate) return;" in root)
# Task217 重锚：设置行随"更新两项迁往关于页"移入 AboutViewController
#（开关 + 落键 general.auto_update_check）；默认值仍在 PLPreferences。
check("A6 关于页开关 + 默认值（默认开）（Task217 重锚：行迁关于页）",
      'self.autoUpdateSwitch.on = [getPrefObject(@"general.auto_update_check") boolValue]' in about_vc and
      'setPrefObject(@"general.auto_update_check"' in about_vc and
      '"auto_update_check": @YES' in plp)
check("A7 l10n 四语言齐备（toast 文案 + 设置 title/detail）",
      all(f'"preference.title.auto_update_check"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          and '"auto_update.toast.view"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          for l in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))

print("== B. Task126 正版登录弹窗根治（Task190 重锚：账户 UI 迁 ZL2Accounts 继任形态）==")
check("B1 showDialog OK 后回收 window（隐藏 + 归还 key window）",
      "w.hidden = YES;" in bridge and "makeKeyAndVisible" in bridge and
      "previousKeyWindow" in bridge)
# ★第 12 期整改批次二①重锚：旧账户列表 AccountListViewController.m 已随退役
# 批次删除，账户选择/登录链迁 ZL2AccountsViewController.m（Task190 用户定稿）
# ——成功/状态提示走 NMToast、错误分支保留弹窗语义 1:1 继任。
zacc = rd("Natives/ZL2AccountsViewController.m")
check("B2 登录成功/状态提示走 NMToast（Task190 重锚：ZL2Accounts handleAuthResult + 优雅回退 toast 继任）",
      "NMToast showMessage:" in zacc)
check("B3 错误分支保留弹窗（Task190 重锚：ZL2Accounts showErrorDialog 1:1 旧失败分支继任）",
      "认证失败：恢复交互并展示错误" in zacc and "showErrorDialog:" in zacc)

print("== C. Task127 子面板基底（Task138 重锚：Task137 新拟态退役后的原生化继任形态） ==")
# Task137 按用户指令删除全部新拟态代码，NMPanel 重写为 AMEPanel；
# Task127 的四条语义保证（幂等/透明跳过/深度限界/单一执法点）在继任者
# 中原样保留，断言改钉继任符号。
check("C1 UIViewController+AMEPanel 存在（幂等语义保留）",
      "ame_applySubpanelBaseStyle" in panel and
      "幂等：每个 VC 实例只应用一次" in panel)
check("C2 透明定制面板跳过（背景照片功能不破坏，语义保留）",
      "clearColor" in panel)
check("C3 表格深度限界遍历（不深入 cell，语义保留）",
      "depth > 3" in panel)
# ★第 12 期整改批次二①退役降级（家法 (b)）：旧导航壳 LauncherNavigationController.m
# 已退役——AMEPanel 的 push 钩子执法点随之消失（断言面退役）；组件本体与三条
# 语义保证（幂等/透明跳过/深度限界）保留，由 C1-C3/C5 继续锚定。
if retired("Natives/LauncherNavigationController.m"):
    skip("C4 单一执法点（push + 根面板，语义保留）", "Natives/LauncherNavigationController.m",
         "push 钩子执法点随旧导航壳退役；AMEPanel 组件语义保留（C1-C3）且仍登记 CMake（C5）")
else:
    check("C4 单一执法点（push + 根面板，语义保留）",
          "pushViewController:(UIViewController *)viewController" in nav and
          "ame_applySubpanelBaseStyle" in nav)
check("C5 CMakeLists 收录继任组件（Natives/NMToast.m + AMEPanel）",
      "NMToast.m" in cml and "UIViewController+AMEPanel.m" in cml)

print("== D. Task128 第三方登录修复（zl2 参照）==")
check("D1 authlib-injector jar 随包（Task132 升级 1.2.8：349681B，sha256 9c7f4343...）",
      os.path.getsize(os.path.join(REPO, "Natives/resources/authlib-injector-1.2.8.jar")) == 349681)
check("D2 bundled 路径解析（NSBundle pathForResource）",
      "bundledAuthlibInjectorPath" in tp and "pathForResource" in tp)
check("D3 ensure 优先包内复制（零网络依赖），在线下载降为回退",
      "Task128: authlib-injector installed from bundled copy" in tp and
      tp.find("bundled copy failed") > tp.find("bundledAuthlibInjectorPath"))
check("D4 启动时 agent 兜底（POJAV_HOME 副本缺失 -> 包内 jar）",
      "using bundled authlib-injector at launch" in tp)
check("D5 accountType 显式标记（thirdparty/microsoft/local 三处写入）",
      '"accountType"] = @"thirdparty"' in tp and
      '"accountType"] = @"microsoft"' in ms and
      '"accountType"] = @"local"' in lo)
check("D6 BaseAuthenticator 判别器 accountType 优先（嗅探回退）",
      "ame128_type" in ba and
      ba.find('isEqualToString:@"thirdparty"') < ba.find('longValue] == 0'))
check("D7 选择回退：refresh 失败仍选中（Task190 重锚：ZL2Accounts 继任形态，Task128 优雅回退语义保留）",
      "Task 128（zl2 同款优雅回退）" in zacc and
      'setPrefObject(@"internal.selected_account", loadKey)' in zacc)
check("D8 会话级已验证标志（Task190 重锚：ZL2Accounts sessionValidated/markSessionValidated 继任）",
      "sessionValidated" in zacc and "markSessionValidated" in zacc)
check("D9 过期提示 toast 文案四语言",
      all('"login.3rdparty.stale.message"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          for l in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
check("D10 version.h addendum 记录 Tasks 125-128",
      all(f"Task {n}" in vh for n in [119, 120, 121, 124, 125, 126, 127, 128]))

print("== E. 语法门 + 级联 ==")
def balance(src):
    state = depth = i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if state == 0:
            if c == '"': state = 1
            elif c == '/' and i + 1 < n and src[i+1] == '/': state = 3
            elif c == '/' and i + 1 < n and src[i+1] == '*': state = 4
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
        elif state == 1:
            if c == '\\': i += 1
            elif c == '"': state = 0
        elif state == 3:
            if c == '\n': state = 0
        elif state == 4:
            if c == '*' and i + 1 < n and src[i+1] == '/': state = 0; i += 1
        i += 1
    return depth
TOUCHED = ["Natives/NMToast.m", "Natives/UIViewController+AMEPanel.m",
           "Natives/LauncherRootViewController.m", "Natives/LauncherNavigationController.m",
           "Natives/ios_uikit_bridge.m", "Natives/AccountListViewController.m",
           "Natives/authenticator/ThirdPartyAuthenticator.m", "Natives/authenticator/BaseAuthenticator.m",
           "Natives/authenticator/MicrosoftAuthenticator.m", "Natives/authenticator/LocalAuthenticator.m",
           "Natives/LauncherPreferencesViewController.m", "Natives/PLPreferences.m"]
for p in TOUCHED:
    if retired(p):
        skip(f"E1 {os.path.basename(p)} 大括号平衡", p)
        continue
    check(f"E1 {os.path.basename(p)} 大括号平衡", balance(rd(p)) == 0)
for p in TOUCHED:
    if retired(p):
        skip(f"E2 {os.path.basename(p)} 裸括号 delta 与 HEAD 一致", p, "宿主已退役，HEAD 对拍基线不复存在")
        continue
    cur = rd(p)
    head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{p}"],
                          capture_output=True, text=True).stdout
    ok = all(cur.count(a) - cur.count(b) == head.count(a) - head.count(b)
             for a, b in [("{", "}"), ("(", ")"), ("[", "]")])
    check(f"E2 {os.path.basename(p)} 裸括号 delta 与 HEAD 一致", ok)
# mgl_fsr GL 守卫全覆盖（774fa7871 CI 失败教训：GL_TEXTURE_2D 裸用）
fsr = rd("Natives/ctxbridges/mgl_fsr.mm")
used = set(re.findall(r'\bGL_[A-Z0-9_]+\b', re.sub(r'/\*.*?\*/', '', re.sub(r'//[^\n]*', '', fsr))))
guarded = set(re.findall(r'#ifndef\s+(GL_[A-Z0-9_]+)', fsr))
check("E3 mgl_fsr.mm 代码用 GL 枚举全部有 #ifndef 守卫（CI 教训）",
      not (used - guarded), f"unguarded={sorted(used - guarded)}")
r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/verify_task119_124.py")],
                   capture_output=True, text=True)
check("E4 级联 verify_task119_124 ALL PASS", r.returncode == 0,
      r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr[:200])

print(f"\n==== RESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}, skipped {SKIP}) ====")
sys.exit(0 if FAIL == 0 else 1)
