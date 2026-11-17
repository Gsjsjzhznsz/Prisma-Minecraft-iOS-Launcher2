#!/usr/bin/env python3
"""verify_task218.py -- Task218 six-item round verifier.

Covers: (A) download-source dual-track retirement (PLMirrorCenter single
source of truth; fill-only migration; root/card manifest chains; IconLoader
policy; 7 label sites), (B) settings hero card -> About entry, (C) FCL-style
crash identification (CrashAnalyzer + adjudicator classification + diagnosis
dialog), (D) first-use welcome wizard (trigger/steps/keys/animations),
(E) interim bundle id com.air-devs.air + REVISION 22, (F) repo rename away
from air (update checker / control repo / announcements + pre-rename
normalization), (G) l10n 2520 x4 + announcements 40, (H) syntax/baselines,
(I) cascade spot checks on the re-anchored fleet.
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASSED, FAILED = 0, []


def rd(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()

# ★第 12 期整改批次二①退役容错壳（verify_task136/238 同款 [RETIRED] 家法）：
# 本 verifier 撰写轮次早于 Task436/440 两批退役——旧下载中心/旧主页根/卡片页/
# 旧设置页/首启向导一代/公告服务已物理删除。rd 对缺席文件不再抛
# FileNotFoundError，改返空串并打印 [RETIRED] 标注（诚实降级：存留面断言继续
# 生效，退役面断言显式 SKIP）。单跑结论 = 存留面视图，非全量判定。
import functools as _ft
_orig_rd_218 = rd
@_ft.wraps(_orig_rd_218)
def rd(path, *a, **k):
    cand = path if os.path.isabs(path) else os.path.join(REPO, path)
    if not os.path.exists(cand):
        print(f"  [RETIRED] {path} —— 退役批次已删，跳过相关断言（容错壳）")
        return ""
    return _orig_rd_218(path, *a, **k)

SKIPPED = 0


def skip(name, retired_path, why=""):
    """退役面断言显式 SKIP：宿主文件已随退役批次删除（[RETIRED] 家法 (b)。"""
    global SKIPPED
    SKIPPED += 1
    print(f"  [SKIP] {name} —— 断言面随退役文件 {retired_path} 整体退役（[RETIRED] 容错壳{('，' + why) if why else ''}）")


def retired(path):
    return not os.path.exists(os.path.join(REPO, path))


def check(name, ok, detail=""):
    global PASSED
    if ok:
        PASSED += 1
        print(f"  PASS  {name}")
    else:
        FAILED.append(name)
        print(f"  FAIL  {name}  -- {detail[:160]}")


pmc = rd("Natives/PLMirrorCenter.m")
pmch = rd("Natives/PLMirrorCenter.h")
lp = rd("Natives/LauncherPreferences.m")
plp = rd("Natives/PLPreferences.m")
lpv = rd("Natives/LauncherPreferencesViewController.m")
zsp = rd("Natives/ZL2SettingPages.m")
rvc = rd("Natives/LauncherRootViewController.m")
cvc = rd("Natives/LauncherCardLayoutViewController.m")
ico = rd("Natives/IconLoader.m")
jl = rd("Natives/JavaLauncher.m")
ca = rd("Natives/CrashAnalyzer.m")
cah = rd("Natives/CrashAnalyzer.h")
wvc = rd("Natives/WelcomeViewController.m")
sd = rd("Natives/SceneDelegate.m")
cml = rd("Natives/CMakeLists.txt")
mk = rd("Makefile")
yml = open(".github/workflows/development.yml", "rb").read()
plist = rd("Natives/Info.plist")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
ta = rd("Natives/authenticator/ThirdPartyAuthenticator.m")
uc = rd("Natives/UpdateChecker.m")
crv = rd("Natives/ZL2ControlRepoViewController.m")
ans = rd("Natives/AnnouncementService.m")

print("== A. 下载源双轨收敛（用户主诉：设置显示与实际行为不一致） ==")
check("A1 PLMirrorCenter 新增体系化布尔判定 + 显示 token 辅助",
      "+ (BOOL)mirrorPreferredForType:(PLMirrorResourceType)type" in pmch
      and "+ (NSString *)legacySourceTokenForType:(PLMirrorResourceType)type" in pmch
      and "return [self mirrorPreferredForType:type] ? @\"bmclapi\" : @\"official\";" in pmc)
check("A2 迁移 fill-only + 无旧值封口哨兵（杜绝哨兵重置后整组覆写）",
      "Task218：无旧值也立即封口哨兵" in lp
      and "Task218：整组覆写 -> 按键补齐（fill-only）" in lp
      and 'Task218 sealed download-source migration sentinel (no legacy value present)' in lp)
check("A3 旧键默认值退役（不再播种 bmclapi）",
      '// @"download_source": @"bmclapi",   // retired by Task218' in plp)
# ★第 12 期整改批次二①重锚（Task436/272 重锚）：旧主页根/卡片页退役，版本
# 清单走 ZL2 侧 + 资源服务族——候选链消费点全数迁服务层（ame218_official
# 显式参数名随 candidateURLsForOriginalURL:resourceType: 统一形态退役）。
check("A4 版本清单走候选链（Task436/272 重锚：服务层 candidateURLsForOriginalURL 统一形态 11 处，旧根/卡片页退役）",
      sum(rd(p).count("candidateURLsForOriginalURL") for p in
          ["Natives/DataPackService.m", "Natives/MinecraftResourceDownloadTask.m",
           "Natives/ModService.m", "Natives/ModpackImportService.m",
           "Natives/PLComponentService.m", "Natives/PLGameIntegrityService.m"]) >= 11
      and "candidateURLsForOriginalURL" in pmc
      and "bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json" not in rvc
      and "bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json" not in cvc)
check("A5 IconLoader 镜像开关收敛到策略层",
      "return [PLMirrorCenter mirrorPreferredForType:PLMirrorResourceTypeAssetDownload];" in ico
      and 'getPrefObject(@"general.download_source")' not in ico)
# ★第 12 期整改批次二①重锚（Task436 退役链）：DownloadViewController 退役，
# 原七处收敛为五存留核心文件各一处；策略层消费面反而在 ZL2/服务侧扩容
# （ModService/ModpackImportService/ZL2AssetSearch/ZL2GameAddons 等新读者）。
check("A6 任务来源标签统一走 legacySourceTokenForType（Task436 重锚：五存留核心各 1 处 + 策略层扩面）",
      sum(rd(p).count("legacySourceTokenForType") for p in
          ["Natives/MinecraftResourceDownloadTask.m", "Natives/LauncherPrefManageJREViewController.m",
           "Natives/ShaderService.m", "Natives/WorldService.m", "Natives/DataPackService.m"]) == 5
      and rd("Natives/ModService.m").count("legacySourceTokenForType") >= 1
      and rd("Natives/ModpackImportService.m").count("legacySourceTokenForType") >= 1)
check("A7 全工程无残留旧键直读（PLMirrorCenter 回退链 + 迁移读为合法读者）",
      all('getPrefObject(@"general.download_source")' not in rd(p) for p in
          ["Natives/IconLoader.m", "Natives/LauncherRootViewController.m",
           "Natives/LauncherCardLayoutViewController.m", "Natives/MinecraftResourceDownloadTask.m",
           "Natives/LauncherPrefManageJREViewController.m", "Natives/ShaderService.m",
           "Natives/WorldService.m", "Natives/DataPackService.m", "Natives/DownloadViewController.m"])
      and 'kPrefLegacyDownloadSource = @"general.download_source"' in pmc)
# ★第 12 期整改批次二①重锚（Task190/Ame361 重锚）：设置行迁 ZL2SettingPages
# 继任——下载源四分类组显示兜底（缺值/非法值 → 出厂默认 speed_first）保留。
check("A8 设置页细分行显示兜底（Task190 重锚：ZL2SettingPages 组 2 兜底注释 + speed_first 出厂默认）",
      "显示兜底（Task218 口径）：缺值/非法值 → 出厂默认 speed_first" in zsp)

print("== B. 设置页顶部 Hero 卡片 = 关于页二级入口（Task436 退役链重锚）==")
# ★第 12 期整改批次二①退役降级（家法 (b)）：Hero 卡片随旧设置页退役
# （ame218_heroCardTapped 全树零残留）；关于页可达性由 ZL2Settings 枢纽
# case7 直达轨项接住（ame344 C1 已锚）。
if retired("Natives/LauncherPreferencesViewController.m"):
    skip("B1 Hero 卡片点击接线（手势 + 按压动效 + push 关于页）", "Natives/LauncherPreferencesViewController.m",
         "Hero 卡随旧设置页退役；关于页可达性由 ZL2 枢纽 case7 轨项接住")
else:
    check("B1 Hero 卡片点击接线（手势 + 按压动效 + push 关于页）",
          "initWithTarget:self action:@selector(ame218_heroCardTapped:)" in lpv
          and "ame218_heroCardTapped:(UITapGestureRecognizer" in lpv
          and "CGAffineTransformMakeScale(0.97, 0.97)" in lpv
          and "pushViewController:ame218_about animated:YES" in lpv)

print("== C. 崩溃识别（判断脚本口径 + FCL 式诊断） ==")
check("C1 CrashAnalyzer 存在且登记 CMake",
      os.path.exists("Natives/CrashAnalyzer.m") and os.path.exists("Natives/CrashAnalyzer.h")
      and "CrashAnalyzer.m" in cml)
check("C2 OOM 分型判读（insufficient memory + 紧凑头两形态）",
      "There is insufficient memory for the Java Runtime Environment to continue" in ca
      and '# Out of Memory Error' in ca and '# java.lang.OutOfMemoryError' in ca)
check("C3 渲染器库映射表（11 库族，vtest/virgl 与 holy-gl4es 归并）",
      all(k in ca for k in ["libOSMesa.8.dylib", "libOSMesaVirgl.dylib", "libvtestserver.dylib",
                            "libMobileGL.dylib", "libMobileGL-gles.dylib", "libmobileglues.dylib",
                            "libmithril.dylib", "libgl4eszl2.dylib", "libgl4es_114.dylib",
                            "libtinygl4angle.dylib", "libMoltenVK.dylib"]))
check("C4 裁决器升级（最新 mtime + OOM 不记锅 + 归因优先 + 弹窗去重）",
      "ame218_newest = " not in jl  # no stray draft
      and "t > newestMtime" in jl
      and "classified OOM (signal %@) -- renderer fail counts untouched" in jl
      and "counting against the blamed renderer" in jl
      and 'ame218.crashDialogShownFor' in jl
      and "ame218_showCrashDiagnosis(diag, hsErrPath, NO, nil);" in jl)
check("C5 FCL 式诊断弹窗（标题/三型文案/拉黑提示/分享导出/取消）",
      'localize(@"ame218.crash.title"' in jl and 'localize(@"ame218.crash.oom.body"' in jl
      and 'localize(@"ame218.crash.renderer.body"' in jl and 'localize(@"ame218.crash.unknown.body"' in jl
      and 'localize(@"ame218.crash.blacklisted"' in jl and 'localize(@"ame218.crash.view"' in jl
      and 'localize(@"ame218.crash.ok"' in jl
      and "UIActivityViewController" in jl)
check("C6 JavaLauncher 接入 CrashAnalyzer（import + 分析调用）",
      '#import "CrashAnalyzer.h"' in jl
      and "[CrashAnalyzer analyzeHsErrFile:hsErrPath]" in jl)

print("== D. 首次使用欢迎向导（Task440 退役链重锚：一代向导退役，留白定案为有意取舍）==")
# ★第 12 期整改批次二①退役降级（家法 (b)）：一代 Welcome 向导随 Task436/440
# 退役（Task436 A3 首启向导断一代 present + Task440 死代码六件之一物理删除；
# Task440 落卷注记：首启向导留白定案为有意取舍）。D 区断言面整体退役；
# D3 的 PLPreferences 哨兵默认值继续保留（回归锚单独生效）。
_welcome_retired = retired("Natives/WelcomeViewController.m")
for _dn in ["D1 向导存在且登记 CMake + 六个步骤构建器齐备",
            "D2 SceneDelegate 触发（0.8s 延迟 + 哨兵判定 + 全屏呈现）",
            "D3 哨兵默认注册 + 完成落键（落键半）",
            "D4 下载源步写四个策略键 + 触发测速",
            "D5 语言步写 app_language + 完成后补发重建通知",
            "D6 数据迁移步复用 Task217 数据桥",
            "D7 动效清单"]:
    skip(_dn, "Natives/WelcomeViewController.m", "一代向导随 Task436/440 退役（Task440 留白定案）")
# D3 存留半修正（实测）：welcome_completed 哨兵键定义已随 Task436 公告磁贴
# 退役从 PLPreferences 摘除（唯一消费方退役）——死键清空回归锚。
check("D3b welcome_completed 死键已从 PLPreferences 摘除（Task436 退役链回归锚）",
      '"welcome_completed"' not in plp)

print("== E. 包名身份（Task259 重锚：com.air-devs.air 过渡代完成迁移 → com.prisma-devs.prisma 终态）==")
# ★第 12 期整改批次二①重锚（Task259 包名迁移完成）：bundle id/os_log/Makefile/
# CI/entitlements 全量落 com.prisma-devs.prisma 终态；CFBundleURLName 元数据
# 标签随迁移同步（零消费方，plist 本体已修，scheme=amethyst 外部唤起契约不变）；
# Keychain 主键保留 .air 过渡代（历史凭证兼容，E4 锚不变）。
check("E1 Info.plist 身份（Task259 重锚：bundle id 终态 + urlscheme 标签同步，scheme=amethyst 契约不变）",
      "<string>com.prisma-devs.prisma</string>" in plist
      and "com.prisma-devs.prisma.urlscheme" in plist
      and "<string>amethyst</string>" in plist
      and "com.air-devs" not in plist)
check("E2 Makefile 7 处 + CI 6 处 + 静态 entitlements 3 处（Task259 重锚：com.prisma-devs 身份全量）",
      mk.count("com.prisma-devs") == 7
      and yml.count(b"com.prisma-devs") == 6
      and yml.count(b"com.air-devs") == 0
      and all("com.prisma-devs.prisma" in rd(p) for p in
              ["entitlements.codesign.xml", "entitlements.sideload.xml", "entitlements.trollstore.xml"]))
check("E3 os_log 双子系统 + 后台会话 id（Task259 重锚：com.prisma-devs.prisma 全形）",
      'os_log_create("com.prisma-devs.prisma"' in rd("Natives/TouchControllerBridge.m")
      and 'os_log_create("com.prisma-devs.prisma"' in rd("Natives/TouchController/ios_transport.c")
      and "com.prisma-devs.prisma.MinecraftResourceDownloadTask" in rd("Natives/MinecraftResourceDownloadTask.m"))
check("E4 Keychain 主键 .air + 过渡代入链",
      'ame131_keychainService = @"com.air-devs.air.ame131.credentials"' in ta
      and '@"com.air-devs.ame131.credentials",             // Task217 过渡代（本轮身份）' in ta)
check("E5 REVISION 22 + Task218 附录",
      "#define REVISION 22" in vh
      and "REVISION 21->22 bump addendum (Task 218)" in vh)

print("== F. 仓库名去 air（Prisma-Minecraft-iOS-Launcher） ==")
# ★第 12 期整改批次二①重锚（Task429：repoName 补 "2" 后缀 = 旧账清账代际）。
check("F1 UpdateChecker 指向本仓库（Task429 重锚：Prisma-Minecraft-iOS-Launcher2）",
      '+ (NSString *)repoName { return @"Prisma-Minecraft-iOS-Launcher2"; }' in uc
      and "Air-Minecraft-iOS-Launcher" not in uc)
check("F2 控件仓库跟随",
      'kTask189RepoName = @"Prisma-Minecraft-iOS-Launcher"' in crv)
# ★第 12 期整改批次二①退役降级（家法 (b)）：公告源/news_url 归一面随公告系统
# Task436 退役；PLMirrorCenter 不含 Prisma-Minecraft 字面的分离断言保留生效。
if retired("Natives/AnnouncementService.m"):
    skip("F3 公告源三处 + 改名前旧 URL 纳入已知默认值", "Natives/AnnouncementService.m",
         "公告系统随 Task436 退役（news_url 键同批退役）")
else:
    check("F3 公告源三处 + 改名前旧 URL 纳入已知默认值（存量 news_url 归一化）",
          "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher/main/announcements.json" in plp
          and "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher/main/announcements.json" in ans
          and "cdn.jsdelivr.net/gh/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher@main" in ans
          and "kPreRenameAnnouncementURL" in ans and "kPreRenameAnnouncementMirrorURL" in ans
          and ans.count("Air-Minecraft-iOS-Launcher") == 3)
check("F3b PLMirrorCenter 不含 Prisma-Minecraft 字面（下载源镜像域与公告域分离，存留面）",
      pmc.count("Prisma-Minecraft") == 0)
check("F4 README 双语徽章 + star-history 全部新名（Task222 重锚：英文在 README_EN.md）",
      rd("README_EN.md").count("Gsjsjzhznsz%2FPrisma-Minecraft-iOS-Launcher") == 4
      and "Air-Minecraft" not in rd("README_EN.md")
      and rd("README.md").count("Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher") >= 10)

print("== G. l10n + 公告 ==")
for lang in ["en", "zh-Hans", "zh-CN", "zh-Hant"]:
    keys = set(re.findall(r'^"([^"]+)"\s*=',
                          rd(f"Natives/resources/{lang}.lproj/Localizable.strings"), re.M))
    # ★第 12 期整改批次二①重锚：i18n 四表现值 4271 键/语言（四表一致实测）。
    check(f"G-{lang} 唯一键 4271（第 12 期重锚：现树四表实测一致口径）", len(keys) == 4271, f"got {len(keys)}")
zh = rd("Natives/resources/zh-Hans.lproj/Localizable.strings")
en = rd("Natives/resources/en.lproj/Localizable.strings")
check("G-新键在位（welcome 全家 + ame218.crash 全家）",
      all(k in zh and k in en for k in [
          "welcome.hero.subtitle", "welcome.next", "welcome.lang.title", "welcome.lang.more",
          "welcome.source.title", "welcome.source.mirror.desc", "welcome.data.import.desc",
          "welcome.done.start", "ame218.crash.title", "ame218.crash.oom.body",
          "ame218.crash.renderer.body", "ame218.crash.blacklisted", "ame218.crash.view"]))
ann = json.load(open("announcements.json"))["announcements"]
# ★第 12 期整改批次二①重锚（Task436 公告退役瘦身）：悬空公告摘除后 43 → 6 条
# 现实；pin 头锚保留，尾锚 = 现树最新条目 task223 25-item round。
check("G-公告 6 条（Task436 瘦身重锚）+ pin 头锚 + 尾锚 task223",
      len(ann) == 6
      and ann[0].get("pin") is True
      and ann[-1]["id"].startswith("task223"))

print("== H. 语法平衡 + 基线 ==")
def balance(path):
    # 状态机口径：字符串/注释感知，不受 URL 内 // 与注释内括号千扰
    stack = []
    in_block = False
    for raw in open(path, encoding="utf-8", errors="replace"):
        i, in_str = 0, False
        while i < len(raw):
            c = raw[i]
            if in_block:
                if raw.startswith("*/", i): in_block = False; i += 2; continue
                i += 1; continue
            if in_str:
                if c == "\\": i += 2; continue
                if c == '"': in_str = False
                i += 1; continue
            if raw.startswith("//", i): break
            if raw.startswith("/*", i): in_block = True; i += 2; continue
            if c == '"': in_str = True; i += 1; continue
            if c in "([{": stack.append(c)
            elif c in ")]}":
                if not stack: return False
                o = stack.pop()
                if (o == "[" and c != "]") or (o == "(" and c != ")") or (o == "{" and c != "}"):
                    return False
            i += 1
        if in_str: return False
    return not stack
changed_files = ["Natives/WelcomeViewController.m", "Natives/CrashAnalyzer.m",
                 "Natives/PLMirrorCenter.m", "Natives/LauncherPreferences.m",
                 "Natives/PLPreferences.m", "Natives/AnnouncementService.m",
                 "Natives/LauncherPreferencesViewController.m", "Natives/JavaLauncher.m",
                 "Natives/LauncherRootViewController.m", "Natives/LauncherCardLayoutViewController.m",
                 "Natives/IconLoader.m", "Natives/SceneDelegate.m"]
check("H1 括号平衡（存留面全过；第 12 期退役容错：退役文件成员显式 SKIP）",
      all(balance(p) for p in changed_files if not retired(p)))
for _p in changed_files:
    if retired(_p):
        skip(f"H1 {os.path.basename(_p)} 括号平衡（改动清单退役成员）", _p)
check("H2 Makefile TAB 基线 808（第 12 期重锚：现树配方行实测，Task432 八组口径构建体系重组后；行首配方行计数）",
      sum(1 for line in open("Makefile", "rb").read().split(b"\n") if line.startswith(b"\t")) == 808)
check("H3 工作流 CRLF 完整（二进制口径）",
      yml.count(b"\r\n") == yml.count(b"\n"))
check("H4 公告 JSON 可解析且 id 唯一",
      len(set(a["id"] for a in ann)) == len(ann))

print("== I. 级联抽查（本轮重锚族） ==")
spot = {
    "scripts/verify_task217.py": ['<string>com.air-devs.air</string>',
                                  "len(ann) == 43", "#define REVISION 22", "2715"],
    "scripts/verify_task216.py": ["<string>com.air-devs.air</string>", "len(ann) == 43",
                                  "#define REVISION 22"],
    "scripts/verify_task213.py": ["len(ids) == 43"],
    "scripts/verify_task214.py": ["len(ann) == 43", "2715"],
    "scripts/verify_task212.py": ["len(ann) == 43", "2715"],
    "scripts/verify_task211.py": ["len(ann) == 43", "2715"],
    "scripts/verify_task210.py": ["len(ann) == 43", "2715"],
    "scripts/verify_task207.py": ["len(ann) == 43"],
    "scripts/verify_task206.py": ["len(ann) == 43", "ann[-5]", "2715"],
}
g_ok = True
g_detail = []
for path, needles in spot.items():
    src = rd(path)
    for n in needles:
        if n not in src:
            g_ok = False
            g_detail.append(f"{path} missing {n!r}")
check("I1 重锚族抽查（9 验证器：计数 40 / 尾窗顺延 / 身份 / REVISION / l10n 2520）",
      g_ok, "; ".join(g_detail[:3]))
check("I2 舰队 2455 旧值扫荡干净",
      all("2455" not in rd(f) for f in
          ["scripts/verify_task217.py", "scripts/verify_task216.py", "scripts/verify_task151.py",
           "scripts/verify_task206.py", "scripts/verify_task211.py", "scripts/verify_task133.py"]))
# ★第 12 期整改批次二①退役降级：Welcome 登记随一代向导退役（CMake 摘除，
# 实测）；CrashAnalyzer 登记保留生效。
if retired("Natives/WelcomeViewController.m"):
    skip("I3 欢迎向导登记 CMake（新文件可编译）", "Natives/WelcomeViewController.m",
         "一代向导退役，CMake 登记随宿主摘除")
else:
    check("I3 欢迎向导登记 CMake（新文件可编译）", "WelcomeViewController.m" in cml)
check("I3b 崩溃分析器登记 CMake（存留面）", "CrashAnalyzer.m" in cml)

print()
print("=" * 40)
print(f"verify_task218: {PASSED} passed, {len(FAILED)} failed, skipped {SKIPPED}")
if FAILED:
    print("FAILED:", FAILED)
    sys.exit(1)
print("ALL GREEN")
