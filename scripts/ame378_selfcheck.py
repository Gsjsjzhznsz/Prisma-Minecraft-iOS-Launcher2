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

check("B3 容器顶锚（bare：★Task414 起 top = bareHeaderView.bottom——顶带入列，\n      子页导航栏自理状态栏延伸语义随容器整体下移同源保留）",
      "[self.container.topAnchor constraintEqualToAnchor:self.view.topAnchor]," in shell_code
      or "[self.container.topAnchor constraintEqualToAnchor:self.bareHeaderView.bottomAnchor]" in shell_code)

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

check("C9 账户/版本滚轮卡功能锚（★Task401 重锚 Task408 重锚：a11y id 随 3dc220d 更名\n      zl2.sidebar.accounts/instances——双卡 AmeFlowSelectView 原地封面流不变，\n      落定回调/卡尾钮（添加/删除账户文本钮+刷新+齿轮）在位；卡体点击链退役 = 拖拽即选择）",
      "_accountFlow = [[AmeFlowSelectView alloc] init];" in home_code
      and "_versionFlow = [[AmeFlowSelectView alloc] init];" in home_code
      and "_accountFlow.axis = AmeFlowSelectAxisHorizontal;" in home_code
      and "_versionFlow.axis = AmeFlowSelectAxisVertical;" in home_code
      and "_accountFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "_versionFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "accountCardTapped" in home_code
      and "versionSettingsTapped" in home_code
      and 'accessibilityIdentifier = @"zl2.sidebar.accounts";' in home
      and 'accessibilityIdentifier = @"zl2.sidebar.instances";' in home)

check("C9b 选中可靠链双保险（★Task401 新立：滚动视图 pan 对滚轮 pan 动态让位 + 数据未变免重建守卫——修「只能拖动再回弹」手势竞争与重建吸附回跳双病灶）",
      ("shouldBeRequiredToFailByGestureRecognizer:" in home_code
       or "shouldBeRequiredToFailByGestureRecognizer:" in read("Natives/AmeFlowSelectView.m"))
      and "ame_itemsCount" in home_code
      and "self.ame400_versionRowNames = ame400_names;" in home_code
      and "self.ame400_accountKeys = ame400_keys;" in home_code)

check("C10 右栏面板+卡窗口径（★Task408 立 ★Task415 重锚：四卡实底化保留；滚动区底缘\n      改锚启动卡顶 + 启动卡钉底三钉 = Task400「钉底永可见」自约束面落实（第 24 轮\n      「部分区域都卡在下面」根修），启动卡出栈；卡间间隙 8pt 同值不变）",
      "_actionMenu.backgroundColor = [UIColor clearColor];" in home_code
      and "_panelBackdrop.hidden = YES;" in home_code
      and "_quickNavCard.backgroundColor = [ZL2Theme surfaceContainer];" in home
      and "_accountCard.backgroundColor = [ZL2Theme surfaceContainer];" in home
      and "_versionCard.backgroundColor = [ZL2Theme surfaceContainer];" in home
      and "_launchCard.backgroundColor = [ZL2Theme surfaceContainer];" in home
      and "_menuScrollView.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor constant:ZL2HomeCardGap" in home_code
      and "_menuScrollView.bottomAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:-ZL2HomeCardGap" in home_code
      and "_launchCard.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor constant:-ZL2HomeCardGap" in home_code
      and "addArrangedSubview:_launchCard]" not in home_code
      and "ZL2HomeCardGap            = 8;" in home
      and "layer.cornerRadius = 1.0 / [UIScreen mainScreen].scale;" in home_code)

check("C11 停靠镜像（★Task406 ★Task409 重锚：面板停靠左 = 卡尾五钉（四钮原钉+\n      管理↔删除相邻链）整组卸/立换钉 + 启动/插件内容组反排 + 版本条目镜像\n      重建对称化（两侧翻转均强制重建，单向 ame_left 条件退役）+ 幂等闸 + [Ame406] 读数）",
      "ame_applyPanelMirror" in home_code
      and "_ame_pinManageLeading = [_accountManageButton.leadingAnchor" in home_code
      and "_ame_pinDeleteTrailing = [_accountDeleteButton.trailingAnchor" in home_code
      and "_ame_pinSettingsTrailing = [_versionSettingsButton.trailingAnchor" in home_code
      and "_ame_pinRefreshChain = [_versionRefreshButton.trailingAnchor" in home_code
      and "_ame_pinFooterChain = [_accountManageButton.trailingAnchor" in home_code
      and "self.ame_panelMirrorLeft == ame_left" in home_code
      and "[self.versionSettingsButton.leadingAnchor constraintEqualToAnchor:self.versionCard.leadingAnchor constant:12]" in home_code
      and "ame_setLaunchContentReversed" in home_code
      and "ame_setPluginContentReversed" in home_code
      and "self.ame400_versionRowNames = nil;" in home_code
      and "nameLabel.textAlignment = NSTextAlignmentRight;" in home_code
      and "if (self.versionFlow.ame_itemsCount > 0) {" in home_code
      and "if (ame_left && self.versionFlow.ame_itemsCount" not in home_code)

check("C12 转盘字体恒定（★Task407：封面流条目随 |d| 缩放时缩字属性令字号泵动\n      = 「转盘转的时候字体自动展开和缩小」根修——账户流三标签（未登录/名称/类型）\n      去 adjustsFontSizeToFitWidth，恒定字号 + TruncatingTail；瓦片标签（静态\n      不随缩放）保留缩字判例；版本轮条目本就恒定口径不动）",
      "ame400_nameLabel.adjustsFontSizeToFitWidth" not in home
      and "ame400_typeLabel.adjustsFontSizeToFitWidth" not in home
      and "ame378_label.adjustsFontSizeToFitWidth = YES" in home
      and "ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;" in home
      and "ame400_typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;" in home)

check("C13 构建代际锚（★Task407 立 408/409/410/411/412 推进 Task414 推进：关于页版本行追加源码级构建代号\n      ame415_buildTag —— Info.plist 双键静态致装机代际不可辨 = 旧构建滞留循环的\n      结构性盲区，关于页读到 Task414 = 本轮新构建在机）",
      "ame415_buildTag" in about_code
      and "Task413" in about
      and about_code.count("ame415_buildTag") >= 2
      and "numberOfLines = 0" in about_code)

check("C14 换边恢复+瓦片二度退役+排序退役（★Task408 立 ★Task410 重锚 ★Task411 终局——\n      ①面板长按换边手势+实现体+持久化恢复回装（镜像随 applySide→applyPanelMirror\n      链自动生效）；②五瓦片二度退役：★Task411 第 19 轮用户钦定「一开始的无文字\n      右上角小型的切换按钮」= 壳层 ame411_switcherCluster 悬浮图标胶囊（屏幕\n      右上 safeArea 常驻）接棒 bare 全场景唯一切换区，五瓦片（有文字大瓦片）\n      无条件 hidden=「固定形态」收敛（408 判例回归，条件化断言退役）；③排序长按\n      挂接退役（restoreSidebarCardOrder 保留），提示语回原键）",
      "ame_handleMenuLongPress" in home_code
      and "[self.actionMenu addGestureRecognizer:menuLongPress]" in home_code
      and "menuLongPress.minimumPressDuration = 0.5" in home_code
      and "stringForKey:ZL2HomeMenuSideDefaultsKey" in home_code
      and "menu side toggled right=%d" in home
      and "_quickNavCard.hidden = YES;" in home_code
      and "_quickNavCard.hidden = [[ZL2Theme ame347_shellLayout]" not in home_code   # ★Task411 条件化断言退役
      and "action:@selector(handleSidebarReorder:)" not in home_code
      and "restoreSidebarCardOrder" in home_code
      and "ame369.home.menu_dock_hint" in home)

flow = read("Natives/AmeFlowSelectView.m")
flow_code = strip_code(flow)
flow_h = read("Natives/AmeFlowSelectView.h")
vpages = read("Natives/ZL2VersionPages.m")   # ★Task412 模组行对齐锚读面
vpages_code = strip_code(vpages)

check("C15 转盘恒定尺寸+无缝循环+镜像钉修复（★Task409 第 17 轮复诉四项之三——\n      ①封面流缩放判例 scale = 1−0.15×|d| 整体退役（左侧图标缩小+字体被边\n      边挤压成省略号双根因），条目尺寸恒定 + 窗缘渐隐带；②槽位复制工厂\n      （小集合接缝推窗：逻辑数≤2×窗半宽时复制，宿主 ame_copyFactory 现建\n      副本，下标全链映射回逻辑数）；③镜像面超定修复：管理↔删除相邻链原钉\n      化随镜像面卸/立 + 版本条目镜像重建对称化（去 ame_left 单向条件））",
      "AmeFlowSelectCenterScale" not in flow
      and "AmeFlowSelectScalePerStep" not in flow
      and "ame_scale" not in flow_code
      and "AmeFlowSelectEdgeFadeBand" in flow_code
      and "ame_windowHalfRange" in flow_code
      and "ame_requiredCopiesForLogicalCount" in flow_code
      and "[self ame_itemsCount]" in flow_code   # ame_itemsCount = 逻辑数（宿主免重建守卫不破；方括号形式 = task393 B 族审计自洽）
      and home_code.count("ame_copyFactory") >= 2   # 双流工厂在位
      and "_ame_pinFooterChain = " in home_code
      and "if (self.ame_pinFooterChain) [ame_pins addObject:self.ame_pinFooterChain]" in home_code
      and "if (ame_left && self.versionFlow.ame_itemsCount" not in home_code   # 单向重建条件退役
      and "if (self.versionFlow.ame_itemsCount > 0) {" in home_code)

check("C16 转盘弧度恢复（★Task410 第 18 轮复诉「转盘的弧度怎么不见了」——409a 恒定\n      尺寸退役缩放后布局纯直线 = 转盘观感丧失；弧度改由位置承接：双轴条目\n      中心叠加抛物线位置弧（AmeFlowSelectArcSagH/V 常量在位且双轴各自应用\n      一次），条目尺寸全程恒定（= 视口减两端弧余量，静态常量不随 |d|），\n      407a 字号恒定与 409a 尺寸恒定双口径零回归——缩放类根因零复沾）",
      "AmeFlowSelectArcSagH" in flow
      and "AmeFlowSelectArcSagV" in flow
      and flow_code.count("ame_sag + ame_sag * ame_arc * ame_arc") == 2   # 双轴各自应用
      and "CGFloat ame_yOff" in flow_code
      and "CGFloat ame_xOff" in flow_code
      and "AmeFlowSelectCenterScale" not in flow   # 缩放类根因零复沾（C15 同口径复核）
      and "AmeFlowSelectScalePerStep" not in flow)

check("C17 右上角无文字切换簇回归+rail 图标回档恒定（★Task411 立 ★Task412 重锚——①bare 骨架\n      ame411_switcherCluster 悬浮图标胶囊：六入口（主页/下载/联机/AI/设置/文件）\n      钉 safeArea 右上全页面常驻 + 选中态随 currentIndex 刷新（ame411_refreshSwitcherSelection），\n      fui 骨架不建防双导航重复；②壳 rail 图标回档 24pt 恒定单一常量（第 20 轮\n      复诉②「图标放的更大了」= 410b 38pt 二轮放大被实测否决，「一开始」展开态\n      口径回归，仍为折叠/展开单一常量零联动）+ 高度独立 required 常量（宽高两条\n      同值常量零耦合）+ 四轴抗压抗抱死）",
      "ame411_switcherCluster" in shell_code
      and "ame411_refreshSwitcherSelection" in shell_code
      and shell_code.count("constraintEqualToConstant:24.0") >= 2   # 图标宽+高两条独立 required
      and "self.ame402_iconSize.constant = 24.0;" in shell_code    # 回档 24 恒定
      and "constraintEqualToConstant:38.0" not in shell_code       # 38 二轮放大口径零残留
      and "compact ? 38.0 : 24.0" not in shell_code
      and "compact ? 7.0 : 14.0" not in shell_code                 # 居中路径二态亦退役（恒 14）
      and "ZL2ShellSystemImageSized(symbol, fallback, 24.0)" in shell_code
      and "setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal" in shell_code
      and "ZL2ShellRailItemIconSize = 24.0" in shell)

check("C18 转盘镜像+模组行对齐（★Task412 立 ★Task413 重锚——①AmeFlowSelectView\n      ame_mirrored：竖轴弧向外移方向翻转 + 横轴排布向翻转 + 横轴点按反解同构\n      翻转；★Task413 手势恒指随判例：拖动/惯性向翻转整体退役（镜像只翻几何，\n      手势零翻转 = 左右手握持侧拖动恒跟手），宿主 ame_applyPanelMirror 双流\n      挂接（右停靠 = 镜像）；②模组行卡 trailing LessThanOrEqualTo → 等式钉卡缘\n      + spacer 拥抱 248 独家吸收 = 全列开关/删除右缘垂直对齐）",
      "ame_mirrored" in flow_code
      and "setAme_mirrored:" in flow_code
      and flow_code.count("_ame_mirrored") >= 5   # setter×2 + 横轴排布 + 竖轴外移 + 点按反解（拖/甩翻转已退役）
      and "ame_signed = _ame_mirrored" not in flow_code   # ★Task413 拖向翻转退役零残留
      and "ame_flick = _ame_mirrored" not in flow_code    # ★Task413 甩向翻转退役零残留
      and "self.ame_offset - (ame_pt.x" in flow_code       # 横轴镜像点按反解在位
      and "self.accountFlow.ame_mirrored" in home_code
      and "self.versionFlow.ame_mirrored" in home_code
      and "row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor" in vpages
      and "constraintLessThanOrEqualToAnchor:card.trailingAnchor" not in vpages_code
      and "setContentHuggingPriority:248 forAxis:UILayoutConstraintAxisHorizontal" in vpages_code)

shell_h = read("Natives/ZL2ShellViewController.h")
accounts_code = strip_code(read("Natives/ZL2AccountsViewController.m"))
skinview = read("Natives/ZL2SkinPreviewView.m")
skinview_code = strip_code(skinview)
skinview_raw = skinview   # 字符串字面量断言走 raw（strip_code 剥字面量内容）
auth3p_code = strip_code(read("Natives/authenticator/ThirdPartyAuthenticator.m"))
auth3p_raw = read("Natives/authenticator/ThirdPartyAuthenticator.m")
modupd_code = strip_code(read("Natives/ModUpdateService.m"))
modsvc_code = strip_code(read("Natives/ModService.m"))
modsvc_raw = read("Natives/ModService.m")   # 字符串字面量断言走 raw（strip_code 剥字面量内容）

# C19 断言子句化（逐条可读；失败时打印首个未命中子句名）
ame378_c19 = [
    ("hdr64", "ZL2ShellHeaderHeight = 64.0" in shell),
    ("cy32", "safeAreaLayoutGuide.topAnchor constant:32.0]" in shell_code),
    ("cap12", "safeAreaLayoutGuide.topAnchor constant:12.0]" in shell_code),
    ("grid28", "ZL2HomeGridInsetTop     = 28" in home),
    ("glyph-lock", "_ame413_appliedGlyphPt" in shell_code),
    ("glyph-skip", "ame413_appliedGlyphPt != 24.0" in shell_code),
    ("source-sig", "NSNumber *source))completion" in modupd_code),   # .m 签名（.h 同增 _Nullable 形态）
    ("v13-push", "ameV13_pushVersionListWithProjectId" in vpages_code),
    ("v13-pidmap", "ameV13_projectIdByPath" in vpages_code),
    ("mvc-import", "ModVersionViewController.h" in vpages),
    ("svc-contact", 'contact[@"homepage"]' in modsvc_raw),
    ("svc-mcmod", 'entryName:@"mcmod.info"' in modsvc_raw),
    ("acct-inline", "ZL2SkinPreviewView" in accounts_code),
    ("btn-retired", "skinPreviewButton" not in accounts_code),
    ("y-flip", ") - 16.0;" in skinview_code),          # ★Task416 重锚：模型 y=16 居中（旧 y_l=−(y_m−16) 翻转同语义）
    ("top-face", "AME416_OFF[ame413_i][1] * ame416_h / 2.0" in skinview_code),   # 顶面轴向偏移
    ("slim-arms", "ZL2SkinViewRArmSlimFaces" in skinview_code),      # slim 模型表在位
    ("yggdrasil", "sessionserver/session/minecraft/profile" in skinview_raw),   # 真皮链（字面量 raw）
    ("full-skin-path", "ame413_fullSkinPathForAccountId" in auth3p_code),
    ("full-skin-disk", "skinfull-" in auth3p_raw),   # 全皮落盘（字面量 raw）
]
ame378_c19_fail = [n for n, ok in ame378_c19 if not ok]
if ame378_c19_fail and os.environ.get("AME378_DEBUG"):
    print("  C19 failing clauses:", ", ".join(ame378_c19_fail))
check("C19 安全区二轮+模组链接内跳+皮肤预览内嵌真皮链（★Task413 第 22 轮复诉五项——\n      ①安全区二轮：壳头带 64 / 内容行 centerY 32 / 胶囊顶距 12 / 主页网格顶距 28\n      （iPhone 刘海由 safeAreaLayoutGuide 锚点天然涵盖）；②fui 图标字形重生幂等锁\n      （ame413_appliedGlyphPt 同值跳过 = 调节不再带动图标重渲染）；③模组链接内跳：\n      fetchProjectInfoForMod completion 增补 source + ameV13_projectIdByPath 路由 +\n      ModVersionViewController 推入 + jar 链接三源提取（ModService homepage）；\n      ④皮肤预览内嵌：ZL2SkinPreviewView 账户卡右栏 + Y 轴翻转（y_l = −(y_m−16)）\n      + 左右面换位 + slim 模型 + yggdrasil 真皮链 + skinfull-<accountId>.png 全皮落盘）",
      all(ok for _, ok in ame378_c19))

# ── C20 断言子句化（★Task414 第 23 轮复诉六项——逐条可读） ──
preview_code = strip_code(read("Natives/Preview/AmeFluentPreviewMain.m"))
smoke_raw = read("scripts/ui_fluent_smoke.sh")

ame378_c20 = [
    # ④ MD3 bare 顶带（安全区口径对齐 fui）
    ("bare-band", "bareHeaderView" in shell_code),
    ("bare-band-pin", "bareHeaderView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor" in shell_code),
    ("bare-title", "bareTitleLabel" in shell_code),
    ("bare-title-cy", "bareTitleLabel.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32.0" in shell_code),
    ("bare-container", "[self.container.topAnchor constraintEqualToAnchor:self.bareHeaderView.bottomAnchor]" in shell_code),
    ("bare-title-refresh", "[self ame_titleForIndex:self.currentIndex]" in shell_code),
    # ⑥ fui rail 选中态对比度（Highest 抬升）
    ("rail-highest", "selected ? [ZL2Theme surfaceContainerHighest] : [UIColor clearColor]" in shell_code),
    # ① 真 3D 四件套（深度序/光影/透视/跑步）★Task416 重锚 CPU 投影引擎
    ("depth-sort", "zPosition" in skinview_code),
    ("face-record", "ZL2SkinViewFace" in skinview_code),
    ("light-shade", "shade.opacity" in skinview_code),
    ("walk-swing", "AME416_WALK_AMP * sin(_ame414_walkPhase)" in skinview_code),
    ("persp-cpu", "AME416_CAMERA_D" in skinview_code),
    ("pivot-swing", "ame416_dy * ame416_ct - ame416_dz * ame416_st" in skinview_code),
    # ② 皮肤站控件组 + ③ 衣柜/设为头像/下载
    ("studio-controls", "ame414_iconButtonWithSymbol" in skinview_code),
    ("wardrobe-disk", "skinwardrobe" in skinview_raw),
    ("avatar-set", "saveAvatarForAccount" in skinview_code),
    ("skin-share", "UIActivityViewController" in skinview_code),
    # ⑤ 账户页两栏右移（工作室卡 + 880 阈值切幅）
    ("studio-card", "ame414_buildStudioCard" in accounts_code),
    ("studio-relayout", "ame414_relayoutStudioForWidth" in accounts_code),
    ("studio-threshold", "width >= 880.0" in accounts_code),
    # ⑤ 主页右栏自适应（滚轮 112 + 版本视口收敛）
    ("wheel-112", "ZL2HomeAccountWheelH      = 112" in home),
    ("version-adaptive", "ame414_relayoutVersionHeight" in home_code),
    ("version-height-pin", "_ame414_versionHeight" in home_code),
    # 预览 harness 双骨架镜像 + 冒烟 nav 轨（「你不会运用预览吗」）
    ("preview-nav-shell", "ame414_buildNavPane" in preview_code),
    ("preview-capsule", "ame414_buildCapsule" in preview_code),
    ("preview-fluent-tokens", "ame317_setPluginThemeTokens" in preview_code),
    ("smoke-nav-track", "-zl2shell nav -zl2theme fluent-dark" in smoke_raw),
]
ame378_c20_fail = [n for n, ok in ame378_c20 if not ok]
if ame378_c20_fail and os.environ.get("AME378_DEBUG"):
    print("  C20 failing clauses:", ", ".join(ame378_c20_fail))
check("C20 MD3顶带+真3D皮肤工作室+右栏自适应+fui rail对比度+预览镜像（★Task414 第 23 轮复诉六项——\n      ④bare 顶带 64/大标题/容器下起/标题随页刷新（安全区口径对齐 fui）；⑥rail 选中底色\n      surfaceContainerHighest；①深度排序 zPosition/逐面光影罩/透视 480/跑步摆动（枢轴\n      RotX）；②③皮肤站控件/衣柜 skinwardrobe/设为头像/下载分享；⑤账户页工作室卡\n      880 阈值切幅 + 主页滚轮 112/版本视口自适应；预览 harness bare/nav 双骨架 + fluent-dark\n      渲染轨 + 冒烟 nav 截图轨）",
      all(ok for _, ok in ame378_c20))

# ── C21 断言子句化（★Task415 第 24 轮复诉三项——逐条可读） ──
preview_raw = read("Natives/Preview/AmeFluentPreviewMain.m")   # 字面量断言走 raw
stub_raw = read("Natives/Preview/ZL2PagesStub.m")

ame378_c21 = [
    # ① 3D 几何核心 ★Task416 skinview3d 移植重锚（CPU 逐面投影 + 画家序 +
    #    背面剔除 + 居中模型空间；旧 CATransform3D 拼接链整体退役）
    ("cpu-project", "AME416_CAMERA_D / (AME416_CAMERA_D - ame416_vz)" in skinview_code),
    ("cat-old-gone", "CATransform3DMakeTranslation((ame413_x + ame413_offX)" not in skinview_code),
    ("model-center", ") - 16.0;" in skinview_code),
    ("yaw-then-pitch", "Ame416RotY(_ame413_yaw, &ame416_vx, &ame416_vz);" in skinview_code),
    ("exact-z", "ame414_f.layer.zPosition = ame416_zsum / 4.0" in skinview_code),
    ("backface-cull", "ame416_nz <= 0.0" in skinview_code),
    ("affine-face", "CATransform3DMakeAffineTransform" in skinview_code),
    ("nan-guard", "isfinite(_ame413_yaw)" in skinview_code),
    ("diag-log", "[ZL2SkinPreview] Task417" in skinview_raw),   # ★Task417 推进（面数 72 诊断）
    # ⑥ ★Task417 3D 第二层（skinview3d outerLayer 移植：帽/衣/袖/裤 +1.0 全维膨胀，
    #    同枢轴同摆动；legacy 左区镜像；alpha 镂空经 CALayer 内容合成）
    ("overlay-uv", "ZL2SkinViewHatFaces[6]" in skinview_code),
    ("overlay-inflate", "ame416_p[3] + 1.0, ame416_p[4] + 1.0, ame416_p[5] + 1.0" in skinview_code),
    ("overlay-legacy", "ame417_lPantF = ame413_legacy ? ZL2SkinViewRPantFaces : ZL2SkinViewLPantFaces" in skinview_code),
    # ⑦ ★Task417 真壳本体入预览（镜像不可信教训的结构性终点：真机 10pt vs
    #    CI 镜像 20pt 两倍差 = 镜像自绘图标从未经过真字形管线）
    ("real-shell-host", "ame417_buildRealShell" in preview_code),
    ("real-navitem", "ZL2ShellNavItem" in preview_code),
    ("probe-page", "ame417_buildProbePage" in preview_code),
    ("flu-token-path", "ame347_setPluginThemeStructure" in preview_code),
    ("realistic-skin", "AmePreviewWriteRealisticSkin" in preview_code),
    ("smoke-real", "-zl2shell real" in smoke_raw),
    ("smoke-ipad", "iPad 仿真腿" in smoke_raw),
    ("stub-shell-symbols", all(s in stub_raw for s in (
        "MultiplayerViewController", "FolderBrowserViewController",
        "AIViewController", "AiSessionStore", "ZL2VersionIndex"))),
    # ⑧ ★Task417-r5 过约束根修（紧凑行 52 = 14+24+14+12 = 64 > 52：隐藏标签链
    #    压图标到 12×12 → 字形 10pt = 真机四轮「图标被压缩」总根源）
    ("label-chain-999", "_ame417_labelLead.priority = 999" in shell_code
        and "_ame417_labelTrail.priority = 999" in shell_code),
    # ④ ★Task416 转盘镜像定谳：极性回归（右停靠=原生/左停靠=镜像）+ 镜像
    #    几何下拖动/甩向符号同步翻转（恒指随的镜像侧实现）
    ("flow-mirror-sign", "ame416_sign = (ame_horizontal && _ame_mirrored)" in flow_code),
    ("flow-flick-sign", "ame416_fsign" in flow_code),
    ("home-mirror-polarity", "BOOL ame_flowMirror = ame_left;" in home_code),
    # ⑤ ★Task416 harness 镜像自伤修复：内容随窗格内缩 + 展开态镜像轨
    ("harness-pane-lead", "ame416_paneLead" in preview_code),
    ("harness-pane-expanded", "ame416_paneExpanded" in preview_code),
    ("smoke-expanded", "-zl2pane expanded" in smoke_raw),
    # ② 主页右栏：启动卡钉出滚动区（Task400「钉底永可见」自约束面真正成立）
    ("launch-out-stack", "addArrangedSubview:_launchCard]" not in home_code),
    ("launch-pin", "_launchCard.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor" in home_code),
    ("scroll-anchor-launch", "_menuScrollView.bottomAnchor constraintEqualToAnchor:_launchCard.topAnchor" in home_code),
    ("floor3-soft", "ame414_floor3" in home_code),
    # ② 工作室卡幅面自适应（「依旧压缩」：高 = 视口 − 48，clamp[460,640]）
    ("studio-fill-height", "_studioCard.heightAnchor constraintEqualToAnchor:frameLG.heightAnchor" in accounts_code),
    ("studio-cap", "constraintLessThanOrEqualToConstant:640.0" in accounts_code),
    # ③ 预览闭环补盲（CI 首渲 3D 预览 = 用户点名「测试图」的结构性保障）
    ("harness-selected", "internal.selected_account" in preview_raw),
    ("harness-skin", "AmePreviewWriteTestSkin" in preview_code),
    ("harness-current", "ame415_loadAccount" in preview_code),
    ("stub-skinfull", "skinfull-%@.png" in stub_raw),
]
ame378_c21_fail = [n for n, ok in ame378_c21 if not ok]
if ame378_c21_fail and os.environ.get("AME378_DEBUG"):
    print("  C21 failing clauses:", ", ".join(ame378_c21_fail))
check("C21 真3D装配序根修+启动卡钉底回归根修+预览闭环补盲（★Task415 第 24 轮复诉——\n      ①面变换 R·T（纸片+90°塌线同根）+ 摆动枢轴换序 T(−P)R(T+P) + 模型旋转入面\n      （真透视+精确 zPosition）+ NaN 卫兵 + 装配诊断日志；②主页启动卡钉出滚动区\n      三钉 + 版本视口三行软下限 + 工作室卡高度自适应 clamp[460,640]；③harness\n      选中账户 + 测试皮肤双落点 + skinfull 桩真路径 = CI 首渲 3D 预览）",
      all(ok for _, ok in ame378_c21))

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
    rcheck("S-C13", about_code.replace("ame415_buildTag", "ame413_buildTag"),
           "ame415_buildTag" not in about_code.replace("ame415_buildTag", "ame413_buildTag"))   # ★Task413 有效化：代标回退变体 → C13 必翻红
    rcheck("S-C14", home_code + "action:@selector(handleSidebarReorder:)",
           "action:@selector(handleSidebarReorder:)" in (home_code + "action:@selector(handleSidebarReorder:)"))
    # ★Task410 S-C16：弧度常量抹除变体 → C16 必翻红
    rcheck("S-C16", flow_code.replace("AmeFlowSelectArcSagH", "AmeFlowSelectArcGone"),
           "AmeFlowSelectArcSagH" not in flow_code.replace("AmeFlowSelectArcSagH", "AmeFlowSelectArcGone"))
    # ★Task412 S-C17：图标二档常量回潮变体 → C17 必翻红（回档口径破坏检出）
    rcheck("S-C17", shell_code.replace("self.ame402_iconSize.constant = 24.0;",
                                       "self.ame402_iconSize.constant = 38.0;"),
           "self.ame402_iconSize.constant = 38.0;" in shell_code.replace("self.ame402_iconSize.constant = 24.0;",
                                                                         "self.ame402_iconSize.constant = 38.0;"))
    # ★Task413 S-C18：拖向翻转回潮变体 → C18 必翻红（手势恒指随判例破坏检出）
    rcheck("S-C18", flow_code + "CGFloat ame_signed = _ame_mirrored ? -1.0 : 1.0;",
           "ame_signed = _ame_mirrored" in (flow_code + "CGFloat ame_signed = _ame_mirrored ? -1.0 : 1.0;"))
    # ★Task413 S-C19：Y 轴翻转抹除变体 → C19 必翻红（IMG_0596 倒置根修破坏检出）
    rcheck("S-C20", skinview_code.replace("ame414_f.layer.zPosition", "/*depth-erased*/"),
           "ame414_f.layer.zPosition" not in skinview_code.replace("ame414_f.layer.zPosition", "/*depth-erased*/"))   # ★Task414 S-C20：深度排序抹除变体 → C20 必翻红
    rcheck("S-C19", skinview_code.replace(") - 16.0;", ") + 16.0;"),
           ") + 16.0;" in skinview_code.replace(") - 16.0;", ") + 16.0;"))   # ★Task416 S-C19：模型 y=16 居中翻转回潮变体 → C19 必翻红
    # ★Task417 S-C22：第二层装配抹除变体 → C21 overlay-inflate 必翻红
    rcheck("S-C22a", skinview_code.replace("ame416_p[3] + 1.0, ame416_p[4] + 1.0, ame416_p[5] + 1.0",
                                           "ame416_p[3], ame416_p[4], ame416_p[5]"),
           "ame416_p[3] + 1.0" not in skinview_code.replace("ame416_p[3] + 1.0, ame416_p[4] + 1.0, ame416_p[5] + 1.0",
                                                            "ame416_p[3], ame416_p[4], ame416_p[5]"))
    # ★Task417 S-C22：真壳预览抹除变体 → C21 real-shell-host 必翻红
    rcheck("S-C22b", preview_code.replace("ame417_buildRealShell", "ame417_goneShell"),
           "ame417_buildRealShell" not in preview_code.replace("ame417_buildRealShell", "ame417_goneShell"))
    # ★Task417 S-C22c：标签链回潮 required 变体 → C21 label-chain-999 必翻红
    rcheck("S-C22c", shell_code.replace("_ame417_labelLead.priority = 999;", "_ame417_labelLead.priority = 1000;"),
           "_ame417_labelLead.priority = 999" not in shell_code.replace("_ame417_labelLead.priority = 999;", "_ame417_labelLead.priority = 1000;"))
    # ★Task415 S-C21 → ★Task416 重锚：CPU 投影旁路回潮变体（sublayerTransform
    #    m34 复活 = 透视双源）→ C21 必翻红
    rcheck("S-C21", skinview_code.replace("_ame413_stageView.layer.sublayerTransform = CATransform3DIdentity;",
                                          "_ame413_stageView.layer.sublayerTransform.m34 = -1.0 / 480.0;"),
           "sublayerTransform.m34" in skinview_code.replace(
               "_ame413_stageView.layer.sublayerTransform = CATransform3DIdentity;",
               "_ame413_stageView.layer.sublayerTransform.m34 = -1.0 / 480.0;"))
    if rf:
        print(f"  SELFTEST FAILED: {rf}")
        sys.exit(1)
    print(f"  selftest {rp}/12 probes red as expected")

print(f"ame378_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("  FAILED:", "; ".join(fails))
    sys.exit(1)
