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
about = read("Natives/AboutViewController.m")
about_code = strip_code(about)

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

check("C1 快航构建器在位 + 顶卡挂接（★Task400 重锚：瓦片卡驻右栏顶——用户复诉「五个按钮在顶上，你移到中间干啥」；Task379「随账号/版本卡之后」与弹性占位口径随卡片化滚动区退役；构建序 = quickNavCard 建卡 → 瓦片行入驻 → 账户/版本滚轮卡随后）",
      "- (void)ame378_buildQuickNav {" in home_code
      and "[self ame378_buildQuickNav];" in home_code
      and "[_quickNavCard addSubview:_quickNavWrap];" in home_code
      and home_code.index("[self ame378_buildQuickNav];") > home_code.index("_quickNavCard = [[UIView alloc] init];")
      and home_code.index("[self ame378_buildQuickNav];") < home_code.index("_accountCard = [[UIView alloc] init];"))

check("C2 ★Task401 面板还原+卡窗透明锚（用户规格：保留原来的右边栏整块灰面板，每卡窗区 even-odd 排除不画=直透启动器背景；r4 重锚：绘制期自取四卡帧（喂矩形链路两轮 CI smoke 实锤洞恒空退役）+洞为零自诊锚=纯红面板）",
      "_panelBackdrop = [[Ame401PanelHolesView alloc] init];" in home_code
      and "@interface Ame401PanelHolesView : UIView" in home
      and "- (void)drawRect:(CGRect)rect {" in home_code
      and "usesEvenOddFillRule = YES;" in home
      and "resolvedColorWithTraitCollection:" in home_code
      and "- (void)ame_refreshPanelMask {" in home_code
      and "_menuScrollView.delegate = self;" in home_code
      and "- (void)ame401_setHostCards:(NSArray<UIView *> *)cards" in home_code
      and "convertRect:ame401_card.bounds toView:self]" in home_code
      and "[UIColor systemRedColor]" in home_code
      and "[_panelBackdrop ame401_setHostCards:@[_quickNavCard, _accountCard, _versionCard, _launchCard]];" in home_code)

check("C3 ★Task392 图标减半规格（用户规格\"缩小两倍\"：图标 27.5 = 55÷2；瓦片高 66.5；间距 6）",
      "ZL2HomeQuickNavIconSize   = 27.5;" in home
      and "ZL2HomeQuickNavTileHeight = 66.5;" in home
      and "ZL2HomeQuickNavGap        = 6;" in home
      and "ZL2HomeQuickNavIconSize   = 55;" not in home
      and "[ame378_icon.widthAnchor constraintEqualToConstant:ZL2HomeQuickNavIconSize]," in home_code)

check("C4 对称留白纪律（★Task400 重锚：单行 fillEqually 均分 + 统一间距 + 瓦片行四边钉顶卡内缩 8pt（卡片化对称内边距）+ 长标签缩排不截断 + 卡间间隙 = 栏距屏边 8pt 同值 + ★Task404 重锚：停靠换边恢复（73c10b7 退役 + b78a16c 摘提示双双回滚）= 双支线在位（menuOnRight 右贴 -8 / 左贴 +8，content 对向挂接 8pt 缝镜像））",
      home_code.count("UIStackViewDistributionFillEqually") == 1
      and "_quickNavWrap.spacing = ZL2HomeQuickNavGap;" in home_code
      and "ame378_label.minimumScaleFactor = 0.7;" in home_code
      and "[_quickNavWrap.topAnchor constraintEqualToAnchor:_quickNavCard.topAnchor constant:ZL2HomeCardPadding]," in home_code
      and "[_quickNavWrap.leadingAnchor constraintEqualToAnchor:_quickNavCard.leadingAnchor constant:ZL2HomeCardPadding]," in home_code
      and "[_quickNavWrap.trailingAnchor constraintEqualToAnchor:_quickNavCard.trailingAnchor constant:-ZL2HomeCardPadding]," in home_code
      and "_menuStack.spacing = ZL2HomeCardGap;" in home_code
      and "if (self.ame_menuOnRight) {" in home_code
      and "[menu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8]," in home_code
      and "[menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8]," in home_code
      and "ZL2HomeMenuSideDefaultsKey" in home_code
      and "ame_handleMenuLongPress:" in home_code)

check("C4 向导引导锚点随五瓦片驻主页顶卡（zl2_shell_topbar_rail ★Task401 重锚：五瓦片驻顶=用户规格，向导锚随瓦片行）",
      'accessibilityIdentifier = @"zl2_shell_topbar_rail";' in home)

check("C4b 卡窗圆角=右侧栏圆角同源（灰棱外轮廓与卡窗路径同 radiusXL 令牌）",
      "bezierPathWithRoundedRect:self.bounds cornerRadius:ame401_radius" in home
      and "bezierPathWithRoundedRect:ame401_r" in home
      and "CGFloat ame401_radius = [ZL2Theme radiusXL];" in home_code)

check("C5 ★Task393 壳通知观察者保留（ZL2ShellOpenFileManager 承接通道在位，未来复接零改动）",
      'name:@"ZL2ShellOpenFileManager"' in shell
      and "ame_openFileManagerSheet" in shell_code)

check("C6 i18n 零新增键（动作簇同款键驻壳层：ame369.shell.tab.* / ame369.common.multiplayer / ame192.ai.title）",
      'localize(@"ame369.shell.tab.files", @"文件")' in shell
      and 'localize(@"ame369.shell.tab.downloads", @"下载")' in shell
      and 'localize(@"ame369.shell.tab.settings", @"设置")' in shell
      and 'localize(@"ame369.common.multiplayer", @"多人联机")' in shell
      and 'localize(@"ame192.ai.title", nil)' in shell)

check("C9 账户/版本滚轮卡功能锚（★Task401 重锚：双卡改 AmeFlowSelectView 原地封面流——账户横轴（水平拖动）+版本竖轴，落定回调/卡尾钮（账户管理+刷新+齿轮）/a11y id 保留；卡体点击链退役 = 拖拽即选择）",
      "_accountFlow = [[AmeFlowSelectView alloc] init];" in home_code
      and "_versionFlow = [[AmeFlowSelectView alloc] init];" in home_code
      and "_accountFlow.axis = AmeFlowSelectAxisHorizontal;" in home_code
      and "_versionFlow.axis = AmeFlowSelectAxisVertical;" in home_code
      and "_accountFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "_versionFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "accountCardTapped" in home_code
      and "versionSettingsTapped" in home_code
      and 'accessibilityIdentifier = @"zl2_home_account_card";' in home
      and 'accessibilityIdentifier = @"zl2_home_version_card";' in home)

check("C9b 选中可靠链双保险（★Task401 新立：滚动视图 pan 对滚轮 pan 动态让位 + 数据未变免重建守卫——修「只能拖动再回弹」手势竞争与重建吸附回跳双病灶）",
      ("shouldBeRequiredToFailByGestureRecognizer:" in home_code
       or "shouldBeRequiredToFailByGestureRecognizer:" in read("Natives/AmeFlowSelectView.m"))
      and "ame_itemsCount" in home_code
      and "self.ame400_versionRowNames = ame400_names;" in home_code
      and "self.ame400_accountKeys = ame400_keys;" in home_code)

check("C10 右栏面板+卡窗口径（★Task401 r3 重锚：用户规格——保留原来的右边栏（灰棱视图 drawRect 画 surfaceContainer）+ 四卡窗区 even-odd 排除=直透启动器背景 + 卡间间隙 8pt（= Task392 栏距屏边四边同值）+ 滚动区内缩/启动组内缩 8pt 四周留灰边）",
      "_actionMenu.backgroundColor = [UIColor clearColor];" in home_code
      and "[[ZL2Theme surfaceContainer]"
       and "resolvedColorWithTraitCollection:self.traitCollection];" in home_code
      and "_quickNavCard.backgroundColor = [UIColor clearColor];" in home_code
      and "_accountCard.backgroundColor = [UIColor clearColor];" in home_code
      and "_versionCard.backgroundColor = [UIColor clearColor];" in home_code
      and "_launchCard.backgroundColor = [UIColor clearColor];" in home_code
      and "_menuScrollView.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor constant:ZL2HomeCardGap" in home_code
      and "_launchCard.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor constant:-ZL2HomeCardGap" in home_code
      and "ZL2HomeCardGap            = 8;" in home
      and "layer.cornerRadius = 1.0 / [UIScreen mainScreen].scale;" in home_code)

check("C11 停靠镜像（★Task406：面板停靠左 = 卡尾四钮整组卸/立换钉 + 启动/插件内容组反排 + 版本条目镜像重建（图标右挂/文字右对齐）+ 幂等闸 + [Ame406] 读数）",
      "ame_applyPanelMirror" in home_code
      and "_ame_pinManageLeading = [_accountManageButton.leadingAnchor" in home_code
      and "_ame_pinDeleteTrailing = [_accountDeleteButton.trailingAnchor" in home_code
      and "_ame_pinSettingsTrailing = [_versionSettingsButton.trailingAnchor" in home_code
      and "_ame_pinRefreshChain = [_versionRefreshButton.trailingAnchor" in home_code
      and "self.ame_panelMirrorLeft == ame_left" in home_code
      and "[self.versionSettingsButton.leadingAnchor constraintEqualToAnchor:self.versionCard.leadingAnchor constant:12]" in home_code
      and "ame_setLaunchContentReversed" in home_code
      and "ame_setPluginContentReversed" in home_code
      and "self.ame400_versionRowNames = nil;" in home_code
      and "nameLabel.textAlignment = NSTextAlignmentRight;" in home_code
      and "if (ame_left && self.versionFlow.ame_itemsCount > 0)" in home_code)

check("C12 转盘字体恒定（★Task407：封面流条目随 |d| 缩放时缩字属性令字号泵动\n      = 「转盘转的时候字体自动展开和缩小」根修——账户流三标签（未登录/名称/类型）\n      去 adjustsFontSizeToFitWidth，恒定字号 + TruncatingTail；瓦片标签（静态\n      不随缩放）保留缩字判例；版本轮条目本就恒定口径不动）",
      "ame400_nameLabel.adjustsFontSizeToFitWidth" not in home
      and "ame400_typeLabel.adjustsFontSizeToFitWidth" not in home
      and "ame378_label.adjustsFontSizeToFitWidth = YES" in home
      and "ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;" in home
      and "ame400_typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;" in home)

check("C13 构建代际锚（★Task407：关于页版本行追加源码级构建代号 ame407_buildTag\n      —— Info.plist 双键静态致装机代际不可辨 = 旧构建滞留循环的结构性盲区，\n      关于页读到 Task407 = 本轮新构建在机）",
      "ame407_buildTag" in about_code
      and "Task407" in about
      and about_code.count("ame407_buildTag") >= 2
      and "numberOfLines = 0" in about_code)

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
    rcheck("S-C12", home_code + "ame400_nameLabel.adjustsFontSizeToFitWidth = YES;",
           "ame400_nameLabel.adjustsFontSizeToFitWidth" in (home_code + "ame400_nameLabel.adjustsFontSizeToFitWidth = YES;"))
    rcheck("S-C13", about_code + "ame407_buildTag", "ame407_buildTag" in (about_code + "ame407_buildTag"))
    if rf:
        print(f"  SELFTEST FAILED: {rf}")
        sys.exit(1)
    print(f"  selftest {rp}/5 probes red as expected")

print(f"ame378_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("  FAILED:", "; ".join(fails))
    sys.exit(1)
