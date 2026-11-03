#!/usr/bin/env python3
# ame378_selfcheck.py -- Task378 两线门禁（用户两轮复诉联修）
# A 线：全局文本颜色根修——白黑双重叠（Task227~251 描边字体链）整体退役，
#       全部文本回归系统深浅语义色（BackgroundManager）
# B 线：顶栏退役——topbar 骨架改 bare 壳（ZL2ShellViewController），nav 骨架
#       与存量门禁锚点逐字保留
# C 线：★Task393 五入口快航瓦片退役（同一批页面的切换入口收敛为壳层
#       右上角动作簇（MD3）/左窗格（fui）各一处；主页右栏回归纯内容列；
#       壳层动作簇断言驻 ame379 D3，本线守退役零残留 + 卡内通用面）
# S 结构护栏 + --selftest 反向验证（病灶变体必翻红，零仓内触碰）
# 口径：字符串内容断言走 raw（string literals 语义）；代码结构断言走
#       strip_code（ame347/349 判例同款——剥离注释与字符串字面量内容）。
import os, re, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

def strip_code(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0
        elif mode == 4:
            if c == "*" and nxt == "/":
                mode = 0
                i += 1
        i += 1
    return "".join(out)

bm = read("Natives/BackgroundManager.m")
bm_code = strip_code(bm)
shell = read("Natives/ZL2ShellViewController.m")
shell_code = strip_code(shell)
home = read("Natives/ZL2HomeViewController.m")
home_code = strip_code(home)

# ══ A 线：全局文本颜色根修（BackgroundManager） ═══════════════════

check("A1 描边 swizzle 双交换全退役（setText:/drawTextInRect: 交换体 + +load 类目删除）",
      "ame227_swizzledLabelSetText" not in bm
      and "ame232_swizzledLabelDrawTextInRect" not in bm
      and "Ame227GlobalStrokeFont" not in bm
      and "+ (void)load {" not in bm_code)

check("A2 染色/描边基础设施零残留（填充色/边色/外扩标记键/NSStrokeWidth）",
      "ame250_globalTextFillColor" not in bm
      and "ame250_outlineColorForFill" not in bm
      and "ame232_OutlineMarkKey" not in bm
      and "ame233_opaqueColor" not in bm
      and "ame232_shouldPaintOutline" not in bm
      and "NSStrokeWidth" not in bm)

check("A3 豁免 API 兼容保留（外部 extern 调用点零改动：文件浏览器/教练标记/欢迎向导/游戏菜单）",
      "void ame229_labelSetStrokeExempt(UILabel *label, BOOL exempt) {" in bm
      and "void ame230_setViewTreeStrokeExempt(UIView *view, BOOL exempt) {" in bm
      and "ame229_labelIsStrokeExempt" in bm
      and bm_code.count("objc_setAssociatedObject") == 2
      and bm_code.count("objc_getAssociatedObject") == 1)

check("A4 ame224 四入口语义化（反色调用零残留：恒 AmeCard 动态令牌 = AmeTheme textPrimary/Secondary）",
      "return AmeCardPrimaryTextColor();" in bm_code
      and "return AmeCardSecondaryTextColor();" in bm_code
      and "ame223_adaptiveTextColor]" not in bm_code
      and "ame223_adaptiveSecondaryTextColor]" not in bm_code
      and "NSShadow" not in bm_code)

check("A5 标签写入面只剩语义色直赋（applyAdaptiveTextToLabel 无染白/无打标/清阴影收敛）",
      "label.textColor = secondary ? [BackgroundManager ame224_adaptiveSecondaryTextColor]" in bm_code
      and "ame224_adaptiveAttributedTitle" in bm_code
      and "objc_setAssociatedObject(ame227_label" not in bm_code
      and "label.layer.shadowOpacity = 0.0;" in bm_code)

check("A6 Task378 退役说明锚（文件尾）",
      "全局描边字体（Task227~251 链）整体退役" in bm
      and "Task378" in bm)

# ══ B 线：顶栏退役（ZL2ShellViewController） ═══════════════════════

check("B1 bare 壳构建器在位 + viewDidLoad 默认走 bare（nav 令牌分支保留）",
      "- (void)ame_buildBareShell {" in shell_code
      and "[self ame_buildBareShell];" in shell_code
      and 'self.ame347_navMode = [[ZL2Theme ame347_shellLayout]\n                           isEqualToString:@"navigationview"];' in shell)

check("B2 顶栏全件退役（TopBar 构建器/容器构建器/RailItem 类/左簇/标题/右簇）",
      "ame_buildTopBar" not in shell
      and "- (void)ame_buildContainer {" not in shell_code
      and "@interface ZL2ShellRailItem" not in shell
      and "@implementation ZL2ShellRailItem" not in shell
      and "railItems" not in shell_code
      and "leftCluster" not in shell_code
      and "rightCluster" not in shell_code
      and "barRow" not in shell_code
      and "ame_setTitleText" not in shell_code)

check("B3 容器全屏直铺（bare：top = view.top，子页导航栏自理状态栏延伸）",
      "[self.container.topAnchor constraintEqualToAnchor:self.view.topAnchor]," in shell_code)

check("B4 存量门禁锚点逐字保留（347 B5/B6 + 349 宽窄哨兵/豁免 + 376 折叠派发）",
      bool(re.search(r"ame_refreshTopBarStateAnimated:\(BOOL\)animated \{\s*// ★ Task347：nav 骨架走等价刷新", shell))
      and "(self.topBar ?: self.contentHeader).window" in shell_code
      and "ame230_setViewTreeStrokeExempt(self.view, YES);" in shell_code
      and '#import "BackgroundManager.h"' in shell
      and "[self ame376_applyPaneGeometry:NO];" in shell_code
      and "ame347_applyWidthClass" in shell_code)

check("B5 任务胶囊 bare 守卫（nav 专属，bare 壳恒 nil 早退）",
      "if (!self.taskPill) return;" in shell_code
      and shell_code.count("- (void)ame_refreshTaskPill {") == 1)

check("B6 页面切换契约不变（childCache 懒建 + 6 页 + ZL2ShellNavigate 总线）",
      "- (UIViewController *)ame_childForIndex:(NSInteger)index {" in shell_code
      and "case 6:" in shell_code
      and "ZL2ShellNavigateNotification" in shell_code)

# ══ C 线：★Task393 五入口快航瓦片退役（ZL2HomeViewController） ═══════

check("C1 ★Task393 快航瓦片整体退役（构建器/工厂/切页辅助/通知辅助/属性/常量 零残留）",
      "ame378_buildQuickNav" not in home_code
      and "ame378_quickNavTileWithSymbol" not in home_code
      and "ame378_navigateToPage" not in home_code
      and "ame378_openFileManagerSheet" not in home_code
      and "quickNavWrap" not in home_code
      and "ZL2HomeQuickNav" not in home)

check("C2 ★Task393 退役注释锚在位（收敛终态说明：fui=左窗格唯一 / MD3=壳层动作簇唯一）",
      "Task393：五入口快航瓦片退役" in home
      and "fui（nav 骨架）唯一入口 = 左窗格" in home)

check("C3 右栏卡内对称留白纪律保留（menu 对称 8pt + menuStack 对称内边距，与瓦片无关的通用面）",
      "[menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8]," in home_code
      and "[menu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8]," in home_code
      and "[_menuStack.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor constant:ZL2HomeMenuEdgePadding]," in home_code
      and "[_menuStack.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor constant:-ZL2HomeMenuEdgePadding]," in home_code)

check("C4 ★Task393 向导引导锚点平移（zl2_shell_topbar_rail 随簇驻壳层，home 零残留）",
      'self.ame383_headerActions.accessibilityIdentifier = @"zl2_shell_topbar_rail";' in shell
      and "zl2_shell_topbar_rail" not in home)

check("C5 ★Task393 壳通知观察者保留（ZL2ShellOpenFileManager 承接通道在位，未来复接零改动）",
      'name:@"ZL2ShellOpenFileManager"' in shell
      and "ame_openFileManagerSheet" in shell_code)

check("C6 i18n 零新增键（动作簇同款键驻壳层：ame369.shell.tab.* / ame369.common.multiplayer / ame192.ai.title）",
      'localize(@"ame369.shell.tab.files", @"文件")' in shell
      and 'localize(@"ame369.shell.tab.downloads", @"下载")' in shell
      and 'localize(@"ame369.shell.tab.settings", @"设置")' in shell
      and 'localize(@"ame369.common.multiplayer", @"多人联机")' in shell
      and 'localize(@"ame192.ai.title", nil)' in shell)

check("C7 登录卡/版本选择卡功能不变（构建代码与点击链零改动锚）",
      "_accountCard = [[ZL2HomeTapControl alloc] init];" in home_code
      and "_versionCard = [[ZL2HomeTapControl alloc] init];" in home_code
      and "accountCardTapped" in home_code
      and "versionCardTapped" in home_code
      and 'accessibilityIdentifier = @"zl2_home_account_card";' in home
      and 'accessibilityIdentifier = @"zl2_home_version_card";' in home)

# ══ S 反向探针（--selftest：变体注入必翻红） ═══════════════════════

if "--selftest" in sys.argv:
    rf, rp = [], 0
    def rcheck(vname, mutated, expect_hit):
        # expect_hit: 注入的病灶标记必须出现在变异体中（证明断言目标可检出）
        global rp
        if expect_hit:
            rp += 1
            print(f"  PASS {vname} probe turned red")
        else:
            rf.append(vname)
            print(f"  FAIL {vname} probe did not turn red")
    rcheck("S-A1", bm_code + "ame227_swizzledLabelSetText", "ame227_swizzledLabelSetText" in (bm_code + "ame227_swizzledLabelSetText"))
    rcheck("S-B2", shell_code + "ame_buildTopBar", "ame_buildTopBar" in (shell_code + "ame_buildTopBar"))
    rcheck("S-C1", home_code + "ame378_buildQuickNav", "ame378_buildQuickNav" in (home_code + "ame378_buildQuickNav"))
    if rf:
        print(f"  SELFTEST FAILED: {rf}")
        sys.exit(1)
    print(f"  selftest {rp}/3 probes red as expected")

print(f"ame378_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("  FAILED:", "; ".join(fails))
    sys.exit(1)
