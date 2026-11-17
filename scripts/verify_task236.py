#!/usr/bin/env python3
# verify_task236: Task236 六项修复的代码锚点验证
#   (1) 字体重叠第七轮：VersionCardCell 垂直超定根修（行高 64→72）+ 描边交换多行缩字镜像
#   (2) 游戏内悬浮栏（齿轮/统计/菜单标签）防御性可见性
#   (3) 游戏内菜单面板防御性底色 + 原生风格底色恢复
#   (4) 前置条目模组列表化（图标+介绍内联）+ 点击直跳下载页 + 自委托下载
#   (5) 弹窗液态玻璃 v2（present-hook 必定安装 + 自适应配方 + 防御性半透明底）
#   (6) i18n +ame236.deps.hint x5
import os, re, subprocess, sys

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径），改从脚本
# 位置动态推导仓库根，TASK236_REPO 环境变量覆盖保留。
BASE = os.environ.get("TASK236_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def rd(p):
    with open(os.path.join(BASE, p), encoding="utf-8") as f:
        return f.read()


# ★Task440 退役容错壳：本 verifier 撰写轮次早于 Task436/Task440 两批退役——
# 其主体文件（旧下载中心/公告/新闻/服务器/旧三版本页/死代码六件等）已物理
# 删除。rd 对缺席文件不再抛 FileNotFoundError，改返空串并打印 [RETIRED]
# 标注（诚实降级：存留面断言继续生效，退役面口径以 task440_selfcheck.py /
# verify_task189.py 重生门为准）。单跑结论 = 存留面视图，非全量判定。
import functools as _ft
# ★第 12 期整改批次二①壳修复（Task440 壳的 getcwd 病根，与 verify_task235/238
# 同族）：存在性判断改用本门 BASE 前缀——原壳用 getcwd 解析相对路径，在非
# 仓库根 cwd 下把存留文件误判成 [RETIRED] 返回空串，存留面断言全部假红。
# 修壳的路径解析，不放宽任何断言。
_orig_rd_440 = rd
@_ft.wraps(_orig_rd_440)
def rd(p, *a, **k):
    cand = p if os.path.isabs(p) else os.path.join(BASE, p)
    if not os.path.exists(cand):
        print(f"  [RETIRED] {p} —— 退役批次已删，跳过相关断言（容错壳）")
        return ""
    return _orig_rd_440(p, *a, **k)

def retired(p):
    return not os.path.exists(os.path.join(BASE, p))

n_ok = n_fail = n_skip = 0
def check(cid, desc, ok):
    global n_ok, n_fail
    if ok:
        n_ok += 1
        print(f"  ok   {cid} {desc}")
    else:
        n_fail += 1
        print(f"  FAIL {cid} {desc}")

def skip(cid, desc, path, why=""):
    """退役面断言显式 SKIP：宿主已删/断言面已真退役（[RETIRED] 家法 (b)）。"""
    global n_skip
    n_skip += 1
    print(f"  [SKIP] {cid} {desc} —— {path}{('，' + why) if why else ''}")

def check_absent(cid, desc, text, bad):
    check(cid, desc + " [absent]", bad not in text)

dlv = rd("Natives/DownloadViewController.m")
vcc = rd("Natives/VersionCardCell.m")
bgm = rd("Natives/BackgroundManager.m")
gmv = rd("Natives/GameMenuOverlayView.m")
svn = rd("Natives/SurfaceViewController+Navigation.m")
mvv = rd("Natives/ModVersionViewController.m")
ukh = rd("Natives/UIKit+hook.m")

print("== A. 字体重叠第七轮（垂直超定根修 + 多行缩字镜像）==")
# ★第 12 期整改批次二①（退役收编）：A1-A3/A7 的宿主旧下载中心
# （DownloadViewController.m）已随 Task436/440 退役批次物理删除——行高锚面
# 随宿主退役（版本列表行由 ZL2VersionListPage 接棒）。
if retired("Natives/DownloadViewController.m"):
    print("  [RETIRED] Natives/DownloadViewController.m —— 退役批次已删，跳过相关断言（容错壳）")
    for _a in ["A1 版本列表行高 72（初始 itemSize）", "A2 行高 72（动态宽度路径）",
               "A3 根因注释（垂直内容链超定 ~6.3pt）", "A7 旧 64 行高退役"]:
        skip("A1-A3/A7", "Natives/DownloadViewController.m", "旧下载中心宿主已随退役批次删除") if _a.endswith("A7 旧 64 行高退役") else skip(_a, "Natives/DownloadViewController.m", "旧下载中心宿主已随退役批次删除")
else:
    check("A1", "版本列表行高 64→72（初始 itemSize）", "CGSizeMake(360, 72)" in dlv)
    check("A2", "版本列表行高 64→72（动态宽度路径）", "CGSizeMake(availableWidth, 72)" in dlv)
    check("A3", "根因注释（垂直内容链超定 ~6.3pt）", "超定 ~6.3pt" in dlv)
    check("A7", "旧 64 行高退役", "CGSizeMake(availableWidth, 64)" not in dlv and "CGSizeMake(360, 64)" not in dlv)
check("A4", "顶行上距 14→13", "self.cardContainer.topAnchor constant:13" in vcc)
check("A5", "日期间距 3→2", "self.topRowStack.bottomAnchor constant:2" in vcc)
check("A6", "日期底距 12→10", "self.cardContainer.bottomAnchor constant:-10" in vcc)
# ★第 12 期整改批次二①（退役收编）：A8-A13 锚面（ame232/ame233/ame235/ame236
# 字体镜像链）随 Task378（91a10fe3d）全局描边字体退役整体删除（BackgroundManager.m
# 净删 374 行，python 实测全链 0 命中，全仓产品代码零残留）；重叠根关切由
# "单渲染源"结构性保证，退役口径由 ame378_selfcheck.py 守卫。
for _a in ["A8 多行缩字镜像", "A9 二分搜索 12 次迭代", "A10 多行拷贝词换行",
           "A11 多行注释", "A12 单行缩字镜像逐字节保留", "A13 测量块无自引用"]:
    skip(_a, "BackgroundManager.m 字体镜像链", "Task378 全局描边字体整体退役（91a10fe3d）")

print("== B. 悬浮栏防御性可见性（齿轮消失/什么都不显示）==")
check("B1", "齿轮玻璃后重铺半透明深色底（alpha 0.55）",
      "blue:0.1 alpha:0.55];" in gmv)
check("B2", "玻璃圆角跟随当前形态（docked 13 / 浮态 22）",
      "self.menuButton.layer.cornerRadius > 0.5" in gmv)
check("B3", "标签不再入磨砂层（文字被盖 = 什么都不显示）",
      "LGCApplyGlassToView(self.statsLabel" not in gmv and
      "LGCApplyGlassToView(self.ame230_captionLabel" not in gmv)
# ★第 12 期整改批次二①重锚（Task243：悬浮栏改纯深色胶囊，发丝描边
# 0.75pt/0.32 → 0.5pt/0.20 减淡细边；实底胶囊语义不变，python 实测）。
check("B4", "标签改实底胶囊 + 发丝描边（Task243 重锚：0.5pt/0.20 减淡细边）",
      "self.statsLabel.layer.borderWidth = 0.5;" in gmv and
      "self.ame230_captionLabel.layer.borderWidth = 0.5;" in gmv and
      "colorWithWhite:1.0 alpha:0.20].CGColor" in gmv)
check("B5", "把手/悬浮形态切换后玻璃重铺（动画完成回调）",
      "completion:^(BOOL finished) {\n            // ★ Task236：形态切换后玻璃层圆角/尺寸跟随新几何（把手 13 / 球 22）\n            [self ame232_applyFloatingGlass];" in gmv)
check("B6", "非动画路径同样重铺", "ame227_apply();\n        // ★ Task236：同上，非动画路径立即重铺（恢复把手态时圆角已变）。" in gmv)
check("B7", "取证日志（帧/圆角/子视图构成）", "[GameMenu] Task236 floating bar hardened" in gmv)
check("B8", "非玻璃风格还原（清描边）",
      "self.statsLabel.layer.borderWidth = 0;" in gmv and
      "self.ame230_captionLabel.layer.borderWidth = 0;" in gmv)
# ★第 12 期整改批次二①重锚（Task243 定案：游戏内常驻件不再安装 LGC 组合
# 玻璃——磨砂层在游戏帧上不合成、只余高光描边=黑把手粗白框；Task230 的
# "heavy dark 材质"关切由纯深色胶囊 0.55 实底承接，python 实测）。
check("B9", "重质深色材质保留（Task230 锚；Task243 重锚：纯深色胶囊 0.55 实底，LGC 玻璃 Metal 跳过）",
      "LGCRemoveGlassFromView(self.menuButton);" in gmv and
      "self.menuButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.55];" in gmv)
check("B10", "方法头根因注释（磨砂层覆盖标签文字）", "盖在标签自己的文字上" in gmv)

print("== C. 菜单面板防御性底色（Task237 重锚：面板彻底重写为自控分层自定义 UIView）==")
# Task237（用户：“游戏内菜单打开还是就液态玻璃的覆盖层，根本没有任何文字”）：
# UITableView + 塞玻璃层方案整体退役，同一关切（面板可见 + 文字恒在）由
# 自控分层构造性保证。
# ★第 12 期整改批次二①重锚（Task243 快照磨砂 + Task244 tint 层 + Task277
# 动态取色底接管面板分层；"防御性深色实底、永不被 LGC 清空"关切由
# menuView.backgroundColor 深色底 + ame244_tint 防御层继续守卫，python 实测）。
check("C1", "防御性深色实底（Task239/243/244 重锚：menuView 深色底 + ame244_tint 防御层，永不被 LGC 清空）",
      "self.menuView.backgroundColor = [UIColor colorWithWhite:0.0" in svn and
      "ame244_tint" in svn and "LGCApplyGlassToView(self.menuView" not in svn)
check("C2", "面板重写日志（玻璃/原生两分支）", "[GameMenu] Task237 glass panel applied" in svn and
      "[GameMenu] Task237 native panel applied" in svn)
check("C3", "原生风格旧版 FCL 外观恢复（纯文本行）", "showsIcon = NO" in svn and
      "legacy FCL look" in svn)
# ★第 12 期整改批次二①重锚（Task243：磨砂插入点改为快照层之上
# aboveSubview:ame243_snap，分层受控语义不变）。
check("C4", "分层构造（磨砂贴快照层 + 行区恒在其上 + 开菜取证）",
      "insertSubview:ame237_blur aboveSubview:ame243_snap]" in svn and
      "[GameMenu] Task237 menu shown" in svn)

print("== D. 前置条目模组列表化 + 直跳 ==")
# ★第 12 期整改批次二①（退役收编）：旧版本页（ModVersionViewController.m）
# 已随 Task436/440 退役批次物理删除（ZL2VersionListPage 三域接棒），
# 前置富条目链 D1-D11 随宿主退役。
if retired("Natives/ModVersionViewController.m"):
    print("  [RETIRED] Natives/ModVersionViewController.m —— 退役批次已删，跳过相关断言（容错壳）")
    for _d in ["D1 富条目渲染 + 日志", "D2 数据抓取", "D3 行构造", "D4 整行点按直跳",
               "D5 自委托实现", "D6 类扩展声明委托协议", "D7 ⓘ 保留详情页入口",
               "D8 偏好版本/加载器透传", "D9 直跳日志", "D10 头部提示", "D11 旧纯文字按钮形态退役"]:
        skip(_d, "Natives/ModVersionViewController.m", "旧版本页宿主已随退役批次删除")
else:
    check("D1", "富条目渲染 + 日志", "[ModVersionVC] Task238 dependency section pinned above version list:" in mvv)
if not retired("Natives/ModVersionViewController.m"):
    check("D2", "数据抓取（图标 + 介绍一步到位）", "ame236_buildDependencyFooterWithItems:" in mvv)
    check("D3", "行构造（44pt 图标 + 标题 + 介绍 + ⓘ）", "ame236_dependencyRow:(NSDictionary *)row" in mvv and
          'constraintEqualToConstant:44' in mvv and 'systemImageNamed:@"info.circle"' in mvv)
    check("D4", "整行点按直跳（自委托）", "ame236_openDependencyDownload:(UIButton *)sender" in mvv and
          "ame236_vc.delegate = self;" in mvv)
    check("D5", "自委托实现（下载到当前实例）",
          "- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version {" in mvv and
          "[[ModService sharedService] downloadMod:ame236_dl" in mvv)
    check("D6", "类扩展声明委托协议", "<UITableViewDataSource, UITableViewDelegate, ModVersionViewControllerDelegate>" in mvv)
    check("D7", "ⓘ 保留详情页入口（关联对象复用）",
          'objc_setAssociatedObject(ame236_info, "ame230.dep.pid"' in mvv)
    check("D8", "偏好版本/加载器透传", "ame236_vc.preferredGameVersion = self.preferredGameVersion;" in mvv)
    check("D9", "直跳日志", "[ModVersionVC] Task236 dependency row direct-jump" in mvv)
    check("D10", "头部提示（ame236.deps.hint）", 'localize(@"ame236.deps.hint", nil)' in mvv)
    check_absent("D11", "旧纯文字按钮形态退役", mvv, '"▸  %@ (%@)"')

print("== E. 弹窗液态玻璃 v2（Task237 重锚：present-hook 魔改拆除 → 中央路由整体替换）==")
fm2 = rd("Natives/AmeFloatingMenu.m")
check("E1", "Task237 路由安装（基类自有选择器，接替 Task236 hook）",
      "[AmeMenu] Task237 floating-menu router installed" in ukh)
check("E2", "路由先判后透传（原生直通零魔改）",
      "[self ame237_hook_presentViewController:viewControllerToPresent animated:flag completion:completion];" in fm2)
check("E3", "只对 UIAlertController + 玻璃风格激活",
      "isKindOfClass:[UIAlertController class]] && LGCIsGlassStyleActive()" in fm2)
check("E4", "魔改双钩子整体退役（无延时补玻璃残留）", "ame235_" not in ukh and "ame236_" not in ukh and
      "0.45 * NSEC_PER_SEC" not in ukh)
check("E5", "自适应材质（SystemMaterial）",
      "UIBlurEffectStyleSystemMaterial]" in fm2)
# ★第 12 期整改批次二①重锚（7.0-UI-3e + Task354：局部动态色助手
# Ame237PanelBase 退役——面板底改语义令牌 ZL2Theme surfaceContainerHigh，
# 自带动态深浅适配，注释自标退役墓碑；"防御性明暗实底"关切由令牌底色承接，
# python 实测）。
check("E6", "防御性明暗实底（7.0-UI-3e/Task354 重锚：ZL2Theme surfaceContainerHigh 动态令牌底）",
      "self.panel.backgroundColor = [ZL2Theme surfaceContainerHigh];" in fm2)
# ★第 12 期整改批次二①重锚（Task354：菜单行文字收敛 M3 语义令牌）。
check("E7", "文字自适应（Task354 重锚：ZL2Theme onSurface/onSurfaceVariant）",
      "[ZL2Theme onSurface]" in fm2)
check("E8", "替换日志（限流）", "[AmeMenu] Task237 glass menu replaced native alert" in fm2)
check("E9", "行控件公开共用（头文件 Ame237MenuRow）", "Ame237MenuRow" in rd("Natives/AmeFloatingMenu.h"))

print("== F. i18n（+ame236.deps.hint x5，基线 2766→2767）==")
langs4 = ["en", "zh-CN", "zh-Hans", "zh-Hant"]
for l in langs4 + ["ja"]:
    s = rd(f"Natives/resources/{l}.lproj/Localizable.strings")
    check(f"F-{l}", "ame236.deps.hint 已定义", '"ame236.deps.hint"' in s)
for l in langs4:
    s = rd(f"Natives/resources/{l}.lproj/Localizable.strings")
    keys = set(re.findall(r'^"([^"]+)" =', s, re.M))
    # ★第 12 期整改批次二①重锚：键数锚 python 实测 4271（Task236 2767 → 现值）。
    check(f"F-cnt-{l}", "唯一键数 4271（python 实测重锚）", len(keys) == 4271)

print("== G. 级联（同文件/同链回归）==")
casc = ["verify_task229.py", "verify_task230.py", "verify_task232.py", "verify_task233.py",
        "verify_task234.py", "verify_task235.py"]
for v in casc:
    r = subprocess.run([sys.executable, os.path.join(BASE, "scripts", v)],
                       capture_output=True, text=True, timeout=300)
    tail = (r.stdout + r.stderr).strip().splitlines()
    verdict = tail[-1] if tail else "(no output)"
    check(f"G-{v}", f"exit={r.returncode} ({verdict[:60]})", r.returncode == 0)

print("========================================")
print(f"verify_task236: {n_ok} passed, {n_skip} skipped, {n_fail} failed")
sys.exit(1 if n_fail else 0)
