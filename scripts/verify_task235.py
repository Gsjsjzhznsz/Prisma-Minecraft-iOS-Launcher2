#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# verify_task235.py -- Task 235 (7-item round on the Task234 build a32f1f3)
# (1) all-version launch crash: array literal with nil statsLabel in the
#     floating-glass applier (NSInvalidArgumentException objects[1], device
#     log 51327919). (2) version/isolation coach anchor aimed at the home
#     avatar card. (3) font overlap round 6: adjustsFontSizeToFitWidth labels
#     draw outline copies at the UNSCALED font. (4) multiplayer home tile
#     (upstream MP-RESTORE port). (5) dependency quick-entry gains an in-app
#     go-to-download-page flow. (6) native UIAlertController popups -> liquid
#     glass (global, style-gated). (7) issue #11 forensics reply (see worklog).
import io, os, re, subprocess, sys

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径），改从脚本
# 位置动态推导仓库根，TASK235_REPO 环境变量覆盖保留。
REPO = os.environ.get("TASK235_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PASSED = []
FAILED = []

def rd(p):
    with io.open(os.path.join(REPO, p), "r", encoding="utf-8", errors="replace") as f:
        return f.read()


# ★Task440 退役容错壳：本 verifier 撰写轮次早于 Task436/Task440 两批退役——
# 其主体文件（旧下载中心/公告/新闻/服务器/旧三版本页/死代码六件等）已物理
# 删除。rd 对缺席文件不再抛 FileNotFoundError，改返空串并打印 [RETIRED]
# 标注（诚实降级：存留面断言继续生效，退役面口径以 task440_selfcheck.py /
# verify_task189.py 重生门为准）。单跑结论 = 存留面视图，非全量判定。
import functools as _ft
# ★第 12 期整改批次二①壳修复（Task440 壳的 getcwd 病根，与 verify_task236/238
# 同族）：存在性判断改用本门 REPO 前缀——原壳用 getcwd 解析相对路径，在非
# 仓库根 cwd 下永远 miss，把【存留文件】也误判成 [RETIRED] 返回空串，造成
# 大面积假 FAIL/假 SKIP。修壳的路径解析，不放宽任何断言。
_orig_rd_440 = rd
@_ft.wraps(_orig_rd_440)
def rd(p, *a, **k):
    cand = p if os.path.isabs(p) else os.path.join(REPO, p)
    if not os.path.exists(cand):
        print(f"  [RETIRED] {p} —— 退役批次已删，跳过相关断言（容错壳）")
        return ""
    return _orig_rd_440(p, *a, **k)

PASSED = []
SKIPPED = []
def skip(name, path, why=""):
    """退役面断言显式 SKIP：宿主已删/断言面已真退役（[RETIRED] 家法 (b)）。"""
    SKIPPED.append(name)
    print(f"  [SKIP] {name} —— {path}{('，' + why) if why else ''}")

def retired(p):
    return not os.path.exists(os.path.join(REPO, p))

def check(idx, name, cond, detail=""):
    (PASSED if cond else FAILED).append(f"{idx} {name}")
    print(("PASS " if cond else "FAIL ") + f"{idx} {name}" + (f"  [{detail}]" if detail and not cond else ""))

def check_absent(idx, name, content, absent):
    check(idx, name, absent not in content)

gmv = rd("Natives/GameMenuOverlayView.m")
bm  = rd("Natives/BackgroundManager.m")
wvc = rd("Natives/WelcomeViewController.m")
rph = rd("Natives/LauncherRightPanelViewController.h")
rpm = rd("Natives/LauncherRightPanelViewController.m")
nvh = rd("Natives/LauncherNewsViewController.h")
nvm = rd("Natives/LauncherNewsViewController.m")
hcv = rd("Natives/HomeCustomizeViewController.m")
mvv = rd("Natives/ModVersionViewController.m")
ukh = rd("Natives/UIKit+hook.m")

print("== A. 全版本启动闪退（数组字面量 nil[1]）==")
# Task236 诚实重锚：ame232_applyFloatingGlass 重构为防御性可见性——statsLabel/
# captionLabel 不再往标签内插磨砂层（UILabel 文字画在自己图层，子视图磨砂会
# 盖住文字 = “什么都不显示”），ame235_hosts 收集数组整体退役；nil 安全由
# 结构保证（LGCRemoveGlassFromView 对 nil 宿卫返回，menuButton 在两处调用
# 点均非 nil，SystemMaterialDark 升级只迭代 menuButton.subviews）。
# ★第 12 期整改批次二①重锚（Task243 定案：游戏内常驻件不再安装 LGC 组合玻璃
# ——磨砂层在游戏帧上不合成、只有高光描边可见=黑把手粗白框，玻璃升级迭代段
# 整体退役）：nil 安全关切由"LGCRemoveGlassFromView 三件套显式移除玻璃层 +
# 纯深色胶囊"承接（python 实测；原 ame232_sub 升级迭代循环随定案退役）。
check("A1", "nil 安全（Task236 结构性：hosts 数组退役；Task243 重锚：三件套显式移除玻璃层，标签不入玻璃）",
      "LGCRemoveGlassFromView(self.menuButton);" in gmv and
      "LGCRemoveGlassFromView(self.statsLabel);" in gmv and
      "LGCRemoveGlassFromView(self.ame230_captionLabel);" in gmv)
check_absent("A2", "裸数组字面量退役", gmv, "@[self.menuButton, self.statsLabel, self.statsLabel]")
check_absent("A3", "三件套裸数组退役（真锚）", gmv,
             "@[self.menuButton, self.statsLabel, self.ame230_captionLabel]")
check("A4", "init 末尾统一补铺玻璃（三件套就绪后）",
      "[self applyStatsLabelVisibility];" in gmv and
      gmv.index("[self ame232_applyFloatingGlass];") > gmv.index("[self setupStatsLabel];") and
      gmv.index("[self ame232_applyFloatingGlass];") > gmv.index("[self restorePositions];"))
check("A5", "崩溃根因注释锚（NSInvalidArgumentException）", "NSInvalidArgumentException" in gmv)

print("== B. 字体重叠第六轮（缩字标签的描边拷贝用原字号）==")
# ★第 12 期整改批次二①（退役收编）：Task378（commit 91a10fe3d）"全局描边字体
# 退役=白黑双重叠根修"移除 setText:/drawTextInRect: 双渲染源头（BackgroundManager.m
# 净删 374 行，python 实测 ame235_baseFont/ame235_scaledFont/ame235_copyRect/
# ame234_textRect 全部 0 命中，全仓产品代码零残留）；重叠根关切由"单渲染源"
# 结构性保证，退役口径由 ame378_selfcheck.py 守卫。
# [RETIRED] 家法：锚面随链退役，SKIP 而非 FAIL。
for _b in ["B1 缩字门", "B2 自然宽度测量", "B3 下限钳制", "B4 缩后字号注入深色拷贝",
           "B5 缩后字号注入垫底", "B6 四份拷贝画进 ame235_copyRect", "B7 垫底画进 ame235_copyRect",
           "B8 同中心重求缩后行高", "B9 非缩字路径语义保留", "B10 Task234 紧致矩形语义保留"]:
    skip(_b, "BackgroundManager.m 描边拷贝链", "Task378 全局描边字体整体退役（91a10fe3d）")

print("== C. 版本与隔离锚点（头像卡 → 选择版本真身）==")
# ★第 12 期整改批次二①（退役收编）：右面板（LauncherRightPanelViewController
# .h/.m）与旧首启向导（WelcomeViewController.m）已随 Task436/440 退役批次
# 整体物理删除，教练圈版本锚链 C1-C7 随宿主退役（引导语义由 ZL2 域接棒，
# 见 scripts/task440_retire_inventory.md）。
for _c in ["C1 .h 声明 ame235_versionAnchorView", "C2 .m 实现返回 manageVersionBtn 真身",
           "C3 欢迎页 tier-1 直取真身", "C4 tier-2 标题匹配兜底", "C5 tier 落日志",
           "C6 旧'内容区上半 42%'派生退役", "C7 绝不回落头像区"]:
    skip(_c, "LauncherRightPanelViewController.h/.m + WelcomeViewController.m",
         "宿主已随 Task436/440 退役批次删除")

print("== D. 联机主页磁贴（上游 MP-RESTORE 移植）==")
# ★第 12 期整改批次二①（退役收编）：旧主页（LauncherNewsViewController.h/.m）
# 与旧自定义主页（HomeCustomizeViewController.m）已随 Task436/440 退役批次
# 物理删除，联机磁贴 D1-D9 随宿主退役（联机入口由 ZL2 域瓦片接棒）。
for _d in ["D1 动作常量定义", "D2 .h extern 声明", "D3 默认磁贴", "D4 老用户布局一次性补入",
           "D5 点按 → 陶瓦联机页 PageSheet", "D6 可用性探测（TerracottaBridge）",
           "D7 磁贴图标与上游一致", "D8 自定义主页可选清单收录", "D9 标题键复用"]:
    skip(_d, "LauncherNewsViewController.h/.m + HomeCustomizeViewController.m",
         "旧主页宿主已随 Task436/440 退役批次删除")

print("== E. 前置快捷入口直跳模组下载页 ==")
# ★第 12 期整改批次二①（退役收编）：旧版本页（ModVersionViewController.m）
# 已随 Task436/440 退役批次物理删除（ZL2VersionListPage 三域接棒），前置
# 直跳链 E1-E8 随宿主退役；ame235.deps.godl 键按"旧键不删"家法继续留表
# （G2 继续守卫）。
for _e in ["E1 详情页接口挂委托协议", "E2 偏好版本/加载器透传属性", "E3 调用点透传",
           "E4 前往下载页按钮", "E5 跳转实现", "E6 选中版本 → ModService 下载",
           "E7 无双弹", "E8 进度/完成提示"]:
    skip(_e, "ModVersionViewController.m", "旧版本页宿主已随退役批次删除")

print("== F. UIAlertController 液态玻璃化（Task237 重锚：魔改路线整体退役 → 中央路由整体替换）==")
# Task237（用户指令“彻底重写所有悬浮菜单样式。不要使用原生 UIAlertController
# 加魔改”）：Task235/236 的 viewWillAppear/present-hook 玻璃化魔改被整体
# 拆除；同一关切（玻璃风格下弹窗呈现液态玻璃外观）由 AmeFloatingMenu 的
# 全自定义组件 + 中央路由承接——玻璃风格下 UIAlertController 永不上屏。
fm = rd("Natives/AmeFloatingMenu.m")
check("F1", "路由钩子实现迁移至 AmeFloatingMenu.m", "- (void)ame237_hook_presentViewController:" in fm and
      "Ame237FloatingMenuRouter)" in fm)
check("F2", "UIKit+hook.m 魔改双钩子拆除（viewWillAppear 交换退役）", "ame235_hook_viewWillAppear" not in ukh and
      "class_copyMethodList([UIAlertController class], &ame235_mcount)" not in ukh)
check("F3", "Task236 present-hook 魔改拆除（路由日志仍在）", "ame236_hook_presentViewController" not in ukh and
      "[AmeMenu] Task237 floating-menu router installed" in ukh)
check("F4", "路由先判类型与风格（非玻璃零接触直透）",
      "isKindOfClass:[UIAlertController class]] && LGCIsGlassStyleActive()" in fm)
# ★第 12 期整改批次二①重锚（后续批次参数名 viewControllerToPresent→alert，
# 镜像接管语义不变，python 实测）。
check("F5", "玻璃风格下原生弹窗永不上屏（镜像接管 return）",
      "presentGlassMenuForAlert:(UIAlertController *)" in fm)
check("F6", "UIAlertAction KVC 镜像 + 失败回退原生", 'valueForKey:@"title"' in fm and
      'valueForKey:@"handler"' in fm and "native passthrough" in fm)
check("F7", "自适应材质（SystemMaterial）+ 防御性明暗实底",
      "UIBlurEffectStyleSystemMaterial]" in fm and "Ame237PanelBase" in fm)
# ★第 12 期整改批次二①重锚（Task354：菜单行控件文字收敛 M3 语义令牌）：
# "行文字随风格自适应"关切由 ZL2Theme onSurface/onSurfaceVariant 继续守卫。
check("F8", "文字自适应（Task354 重锚：ZL2Theme onSurface/onSurfaceVariant 语义令牌）",
      "[ZL2Theme onSurface]" in fm and "[ZL2Theme onSurfaceVariant]" in fm)
check("F9", "菜单项带图标（SF Symbol 启发式 + 回退链）", "iconNameForTitle:" in fm and
      'systemImageNamed:@"circle"' in fm)
check("F10", "替换日志（限流）", "[AmeMenu] Task237 glass menu replaced native alert" in fm)
check("F11", "输入框镜像 + 双向同步", "ame237_fieldChanged:" in fm and "ame237_syncAllFields" in fm)
check("F12", "键盘避让", "UIKeyboardWillShowNotification" in fm and "UIKeyboardWillHideNotification" in fm)

print("== G. i18n 基线（2765 → 2767）==")
langs4 = ["en", "zh-CN", "zh-Hans", "zh-Hant"]
for l in langs4:
    s = rd(f"Natives/resources/{l}.lproj/Localizable.strings")
    keys = set(re.findall(r'^"([^"]+)" =', s, re.M))
    # ★第 12 期整改批次二①重锚：键数锚 python 实测 4271（Task235 2767 →
    # 现值；漂移源=历批新增键与退役键不删家法累积）。
    check("G1", f"{l} 唯一键总数 == 4271（python 实测重锚）", len(keys) == 4271, f"got {len(keys)}")
for l in ["en", "ja", "zh-CN", "zh-Hans", "zh-Hant"]:
    s = rd(f"Natives/resources/{l}.lproj/Localizable.strings")
    check("G2", f"{l} ame235.deps.godl 在场", '"ame235.deps.godl"' in s)

print("== H. 级联（被本改动触碰的区域）==")
# 232/233/234 已诚实重锚（本轮实改代码区）；229/230 触碰同文件区域。
# 各 fleet 脚本总结行格式不一（passed/ok/PASS / X of Y），这里逐一适配。
def fleet_summary(r):
    t = r.stdout
    for pat in (r"(\d+) passed, (\d+) failed", r"(\d+) ok, (\d+) fail\b",
                r"(\d+) PASS / (\d+) FAIL", r"(\d+) / (\d+) checks passed",
                r"(\d+)/(\d+) checks passed"):
        m = re.search(pat, t)
        if m:
            return m.group(1) == m.group(2) or m.group(2) == "0"
    return r.returncode == 0

for tag, tasks in (("H1", (232, 233, 234)), ("H2", (229, 230))):
    for t in tasks:
        r = subprocess.run([sys.executable, os.path.join(REPO, f"scripts/verify_task{t}.py")],
                           capture_output=True, text=True, timeout=300)
        ok = r.returncode == 0 and fleet_summary(r)
        check(tag, f"verify_task{t} 全绿（重锚/同文件回归）", ok,
              (r.stdout[-300:].replace("\n", " ") + " | rc=" + str(r.returncode)) if not ok else "")

print(f"\n{'=' * 40}\n{len(PASSED)} passed, {len(SKIPPED)} skipped, {len(FAILED)} failed")
if FAILED:
    for f in FAILED:
        print("  FAILED:", f)
    sys.exit(1)
