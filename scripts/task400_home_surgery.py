#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""task400_home_surgery.py -- ZL2HomeViewController.m 四点纠错手术
用户四点反馈（2026-11-04）：
  2. 呈现方式原地化（不是单开一页：账户/版本滚轮驻右栏原卡位，横排条目）
  3. 五瓦片归顶 + MC 头像 1 物理像素超小圆角
  4. 右栏卡片化（透明容器/8pt 卡间隙=栏距屏边/radiusXL=栏圆角）
每个替换断言锚点唯一存在，任何失配即中止不写盘。
"""
import io, sys

PATH = "/home/z/my-project/repo/Natives/ZL2HomeViewController.m"

with io.open(PATH, encoding="utf-8", newline="") as f:
    data = f.read()

def replace_once(old, new, tag):
    global data
    n = data.count(old)
    if n != 1:
        print("FAIL[%s] anchor count=%d" % (tag, n))
        sys.exit(1)
    data = data.replace(old, new, 1)
    print("OK  %s" % tag)

def replace_range(start_marker, end_marker, new, tag):
    """替换 [start_marker, end_marker)（end_marker 保留在文件中）"""
    global data
    i = data.find(start_marker)
    if i < 0:
        print("FAIL[%s] start not found" % tag); sys.exit(1)
    j = data.find(end_marker, i + len(start_marker))
    if j < 0:
        print("FAIL[%s] end not found" % tag); sys.exit(1)
    data = data[:i] + new + data[j:]
    print("OK  %s" % tag)

# ───────────────────────── P1 导入区 ─────────────────────────
replace_once(
'#import "AmeIpodFlowView.h"  // ★Task393：iPod 式竖排封面流（版本选择弹层）\n',
'''#import "AmeIpodFlowView.h"  // ★ Task393：iPod 式竖排封面流（★ Task400 起驻主页右栏原地）
#import "authenticator/ThirdPartyAuthenticator.h" // ★ Task400：账户滚轮选中链（第三方 refreshToken）
#import "NMToast.h"  // ★ Task400：选中链 stale 降级非侵入提示（账户页同款）

// ★ Task400：账户页共享链 C 符号前向声明（验证集合/第三方判别单源共享；
//   零头文件传递依赖，两 TU 同在 smoke 窄链接清单——UIKit_launchMinecraftSurfaceVC 同款判例）
NSMutableSet *ZL2AccountsSharedValidatedSet(void);
BOOL ZL2AccountsSharedIsThirdParty(NSDictionary *accountData);

// ★ Task400：AFNetworking 错误响应体键（仅消费此一个 extern 常量——账户页
//   同款判例；定义由真实构建 libAFNetworking / 预览桩 ZL2PagesStub 提供）
extern NSString * const AFNetworkingOperationFailingURLResponseDataErrorKey;
''', "P1-imports")

# ───────────────────────── P2 常量区 ─────────────────────────
replace_once(
'''// ActionMenu 组件高度
static const CGFloat ZL2HomeAccountCardHeight  = 76;  // 账号卡（48 头像 + 上下 14）
static const CGFloat ZL2HomeVersionCardHeight  = 68;  // 版本选择卡（40 图标 + 上下 14）
static const CGFloat ZL2HomeLaunchButtonHeight = 48;  // 大启动钮（ScalingActionButton 48.dp）
''',
'''// ActionMenu 组件高度
static const CGFloat ZL2HomeLaunchButtonHeight = 48;  // 大启动钮（ScalingActionButton 48.dp）

// ★ Task400：右栏卡片化口径（用户规格第 4 条：右栏各卡（头像/游戏版本/五瓦片/
//   启动插件钮）视为一个个整体——栏容器背景透明透出启动器背景，卡间间隙 =
//   右侧栏距屏幕边缘的距离（Task392 四边 8pt 同值），圆角 = 右侧栏圆角
//   （radiusXL）；第 3 条：五瓦片卡驻顶）
static const CGFloat ZL2HomeCardGap            = 8;   // 卡间间隙 = 栏距屏边 8pt（用户规格）
static const CGFloat ZL2HomeCardPadding        = 8;   // 卡内边距（与卡间隙同律）
static const CGFloat ZL2HomeAccountFlowItemH   = 58;  // 账户滚轮条目高（头像 40 横排，账户页封面流同款）
static const CGFloat ZL2HomeVersionFlowItemH   = 64;  // 版本滚轮条目高（图标 40 + 双行文 =「五个正常的实例版本信息高度」口径）
static const CGFloat ZL2HomeFlowItemGap        = 10;  // 条目间隙（实例卡图标→名称间隙参照，Task393 用户规格沿用）
static const CGFloat ZL2HomeCardFooterHeight   = 32;  // 卡尾动作行钮边长（账户管理/刷新/齿轮）
''', "P2-constants")

# ───────────────────────── P3a 属性：瓦片/滚动区 ─────────────────────────
replace_once(
'''// ★ Task378：五入口快航瓦片（右侧栏顶部：第一行 文件/下载/设置，第二行 联机/AI；
//   下接账号卡/版本选择卡，功能不变）
@property (nonatomic, strong) UIStackView *quickNavWrap;
// ★ Task393：版本选择封面流弹层（版本选择卡点按 = iPod 式竖排选择器，
//   用户规格 bold plan ②「版本选择也是一样，竖排式的」）
@property (nonatomic, strong, nullable) AmeIpodFlowView *ame393_versionFlow;
@property (nonatomic, strong, nullable) UIView *ame393_versionSheetContent;
''',
'''// ★ Task378/Task400：五入口快航瓦片（卡片化后驻右栏顶卡——用户规格第 3 条
//   「五个按钮在顶上」；一行×5 fillEqually，图标 27.5）
@property (nonatomic, strong) UIView *quickNavCard;
@property (nonatomic, strong) UIStackView *quickNavWrap;
// ★ Task400：右栏卡片化——中段滚动区（瓦片/账户滚轮/版本滚轮三卡，总高
//   超出屏高时滚动）+ 启动组卡钉底永可见
@property (nonatomic, strong) UIScrollView *menuScrollView;
@property (nonatomic, strong) UIView *launchCard;
@property (nonatomic, strong) UIStackView *launchStack;
''', "P3a-props-nav")

# ───────────────────────── P3b 属性：账户/版本卡 ─────────────────────────
replace_once(
'''// —— ActionMenu：账号卡 ——
@property (nonatomic, strong) ZL2HomeTapControl *accountCard;
@property (nonatomic, strong) UIView *accountAvatarBg;    // 48 圆底
@property (nonatomic, strong) UIImageView *accountAvatarView;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UILabel *accountTypeLabel;

// —— ActionMenu：版本选择卡 ——
@property (nonatomic, strong) ZL2HomeTapControl *versionCard;
@property (nonatomic, strong) UIView *versionIconBg;
@property (nonatomic, strong) UIImageView *versionIconView;
@property (nonatomic, strong) UILabel *versionNameLabel;
@property (nonatomic, strong) UILabel *versionLoaderLabel;
@property (nonatomic, strong) ZL2HomeTapControl *versionRefreshButton;
@property (nonatomic, strong) ZL2HomeTapControl *versionSettingsButton;
''',
'''// —— ★ Task400：ActionMenu 账户封面流卡（iPod 式原地滚轮，替代原头像+
//    名称单卡——用户规格第 2 条「用相同方式在原地做出一样的横排效果」）——
@property (nonatomic, strong) UIView *accountCard;
@property (nonatomic, strong) AmeIpodFlowView *accountFlow;
@property (nonatomic, strong) ZL2HomeTapControl *accountManageButton;   // 卡尾账户管理小钮
@property (nonatomic, strong) UIActivityIndicatorView *accountSpinner; // 选中链忙态占位
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *ame400_accountList;   // 账户数据源（accounts 目录扫描）

// —— ★ Task400：ActionMenu 版本封面流卡（iPod 式原地滚轮，占五个正常
//    实例版本信息高度——用户规格「实例版本也一样改」）——
@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) AmeIpodFlowView *versionFlow;
@property (nonatomic, strong) ZL2HomeTapControl *versionRefreshButton;  // 卡尾刷新小钮
@property (nonatomic, strong) ZL2HomeTapControl *versionSettingsButton; // 卡尾齿轮小钮
''', "P3b-props-cards")

# ───────────────────────── P4 viewDidLoad：弹层观察者退役 ─────────────────────────
replace_once(
'''    // ★ Task393：版本选择弹层总线入口（预览 harness 与外部唤起同口径——
    //   版本选择卡点按 / 通知直达，双入口同一呈现）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame393_presentVersionPicker)
                                                 name:@"ZL2HomeShowVersionPicker"
                                               object:nil];

''',
'''    // ★ Task400：ZL2HomeShowVersionPicker 总线入口随弹层退役（版本滚轮
    //   原地驻右栏，无呈现/收起时序）

''', "P4-observer")

# ───────────────────────── P5 ame_buildActionMenu 全量重写 ─────────────────────────
NEW_ACTION_MENU = '''/// ActionMenu 竖排（★ Task400 卡片化重构——用户规格第 4 条：「将右边栏的
///   三个卡片（头像、游戏版本、五个按钮、启动和插件的按钮），视为一个个
///   整体，将每个卡片的背景透明（而呈现出启动器背景），每个卡片中间都要
///   留点间隙（右侧栏距离屏幕边缘的距离）和圆角（右侧栏的圆角）」）：
///   栏容器本体背景退役 → 间隙与四周透出启动器背景；四张独立卡
///   （surfaceContainer + radiusXL = 右侧栏圆角同款）之间 8pt 间隙
///   （= Task392 栏距屏幕边缘四边 8pt 同值）：
///     ① 五瓦片卡（驻顶——用户规格第 3 条「五个按钮在顶上」）
///     ② 账户封面流卡（iPod 式原地滚轮 = 原头像+名称卡同位横排条目——
///        用户规格第 2 条「用相同方式在原地做出一样的横排效果」）
///     ③ 版本封面流卡（iPod 式原地滚轮，占五个正常实例版本信息高度）
///     ④ 启动组卡（状态行/大启动钮/插件 chip/停靠提示，钉列底永可见）
///   双滚轮总高（5+5 行）超出屏高时中段滚动区滚动，启动组不受影响；
///   停靠边只决定整列贴左/贴右。
- (void)ame_buildActionMenu {
    _actionMenu = [[UIView alloc] init];
    // ★ Task400：栏容器背景退役（大单卡拆四张独立卡——间隙处透出启动器
    //   背景；surfaceContainer 填充下沉到各卡，Task392 两态可辨口径不变）
    _actionMenu.backgroundColor = [UIColor clearColor];
    _actionMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_actionMenu];

    // —— ④ 启动组卡（钉列底；先建，滚动区底缘锚它）——
    _launchCard = [[UIView alloc] init];
    _launchCard.backgroundColor = [ZL2Theme surfaceContainer];
    _launchCard.layer.cornerRadius = [ZL2Theme radiusXL];   // 右侧栏圆角同款
    _launchCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionMenu addSubview:_launchCard];

    _launchStack = [[UIStackView alloc] init];
    _launchStack.axis = UILayoutConstraintAxisVertical;
    _launchStack.alignment = UIStackViewAlignmentFill;
    _launchStack.spacing = ZL2HomeCardPadding;
    _launchStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchCard addSubview:_launchStack];

    // —— 中段滚动区（瓦片/账户滚轮/版本滚轮三卡；总高超出时滚动）——
    _menuScrollView = [[UIScrollView alloc] init];
    _menuScrollView.backgroundColor = [UIColor clearColor];
    _menuScrollView.showsVerticalScrollIndicator = NO;
    _menuScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionMenu addSubview:_menuScrollView];

    _menuStack = [[UIStackView alloc] init];
    _menuStack.axis = UILayoutConstraintAxisVertical;
    _menuStack.alignment = UIStackViewAlignmentFill;
    _menuStack.spacing = ZL2HomeCardGap;   // ★ Task400：卡间间隙 = 栏距屏边 8pt（用户规格）
    _menuStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_menuScrollView addSubview:_menuStack];

    __weak ZL2HomeViewController *weakSelf = self;

    // —— ① 五瓦片卡（★ Task400 驻顶：用户规格「五个按钮在顶上」——原
    //      Task379「瓦片随账号卡/版本卡之后」口径退役）——
    _quickNavCard = [[UIView alloc] init];
    _quickNavCard.backgroundColor = [ZL2Theme surfaceContainer];
    _quickNavCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _quickNavCard.layer.masksToBounds = YES;
    _quickNavCard.translatesAutoresizingMaskIntoConstraints = NO;
    _quickNavCard.isAccessibilityElement = NO;
    [_menuStack addArrangedSubview:_quickNavCard];
    [self ame378_buildQuickNav];

    // —— ② 账户封面流卡（原地滚轮；条目 = 头像 40 + 名称/类型横排 = 原
    //      头像+名称卡同一呈现语言；吸附落定走原选中链）——
    _accountCard = [[UIView alloc] init];
    _accountCard.backgroundColor = [ZL2Theme surfaceContainer];
    _accountCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _accountCard.layer.masksToBounds = YES;
    _accountCard.translatesAutoresizingMaskIntoConstraints = NO;
    _accountCard.isAccessibilityElement = NO;   // 滚轮（adjustable）+ 卡尾钮各自可达
    _accountCard.accessibilityIdentifier = @"zl2_home_account_card";
    [_menuStack addArrangedSubview:_accountCard];

    _accountFlow = [[AmeIpodFlowView alloc] init];
    _accountFlow.itemHeight = ZL2HomeAccountFlowItemH;
    _accountFlow.interItemGap = ZL2HomeFlowItemGap;
    _accountFlow.accessibilityLabel = localize(@"login.option.select", @"选择账户");
    _accountFlow.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountCard addSubview:_accountFlow];

    // 卡尾动作行：账户管理小钮（原账号卡点击语义收口于此）+ 选中链忙态 spinner
    _accountManageButton = [self ame_iconButtonWithSymbol:@"person.crop.circle.badge.plus"
                                                 fallback:@"person.crop.circle"
                                                     a11y:localize(@"ame369.shell.tab.accounts", @"账户")];
    _accountManageButton.ame_action = ^{
        [weakSelf accountCardTapped];
    };
    [_accountCard addSubview:_accountManageButton];

    _accountSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _accountSpinner.hidesWhenStopped = YES;
    _accountSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountCard addSubview:_accountSpinner];

    // 吸附落定（下标变化）→ 原选中链（Task128 会话校验/第三方 stale 降级/
    // 微软本地 refreshToken——账户页 selectAccountAtIndex 同款全链）
    _accountFlow.onSettle = ^(NSInteger ame400_index) {
        if (ame400_index >= 0) {
            [weakSelf ame400_selectAccountAtIndex:(NSUInteger)ame400_index];
        }
    };

    // —— ③ 版本封面流卡（原地滚轮；条目 = 加载器图标 40 + 实例名/信息行；
    //      高度 = 五个正常实例版本信息行（用户规格「占用的比例算五个正常
    //      的实例版本信息高度」）；吸附落定即选用）——
    _versionCard = [[UIView alloc] init];
    _versionCard.backgroundColor = [ZL2Theme surfaceContainer];
    _versionCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _versionCard.layer.masksToBounds = YES;
    _versionCard.translatesAutoresizingMaskIntoConstraints = NO;
    _versionCard.isAccessibilityElement = NO;
    _versionCard.accessibilityIdentifier = @"zl2_home_version_card";
    [_menuStack addArrangedSubview:_versionCard];

    _versionFlow = [[AmeIpodFlowView alloc] init];
    _versionFlow.itemHeight = ZL2HomeVersionFlowItemH;
    _versionFlow.interItemGap = ZL2HomeFlowItemGap;
    _versionFlow.accessibilityLabel = localize(@"i18n_str_38", nil);   // 选择版本（四表既有键）
    _versionFlow.translatesAutoresizingMaskIntoConstraints = NO;
    [_versionCard addSubview:_versionFlow];

    // 卡尾动作行：刷新（重拉注册表）+ 齿轮（版本管理页直达）——原版本卡
    // 内双小钮语义原样平移
    _versionRefreshButton = [self ame_iconButtonWithSymbol:@"arrow.clockwise"
                                                  fallback:@"sync"
                                                    a11y:localize(@"ame369.home.refresh_instances_a11y", @"刷新实例列表")];
    _versionRefreshButton.ame_action = ^{
        [weakSelf versionRefreshTapped];
    };
    [_versionCard addSubview:_versionRefreshButton];

    _versionSettingsButton = [self ame_iconButtonWithSymbol:@"gearshape"
                                                   fallback:@"gear"
                                                       a11y:localize(@"ame369.home.version_manager_a11y", @"版本管理")];
    _versionSettingsButton.ame_action = ^{
        [weakSelf versionSettingsTapped];
    };
    [_versionCard addSubview:_versionSettingsButton];

    // 吸附落定（下标变化）→ 选用该实例（版本页 ame_selectProfileNamed 同款链；
    // 原地滚轮无收起语义——Task393 弹层 0.35s 驻留收起随弹层一并退役）
    _versionFlow.onSettle = ^(NSInteger ame400_index) {
        if (ame400_index >= 0) {
            [weakSelf ame393_selectProfileAtIndex:(NSUInteger)ame400_index];
        }
    };

    // —— 下载状态行（KVO 百分比态；非下载态隐藏塌缩）——
    _launchStatusLabel = [[UILabel alloc] init];
    _launchStatusLabel.font = [ZL2Theme fontLabelMedium];
    _launchStatusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _launchStatusLabel.textAlignment = NSTextAlignmentCenter;
    _launchStatusLabel.numberOfLines = 1;
    _launchStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchStatusLabel.isAccessibilityElement = YES;
    _launchStatusLabel.hidden = YES;
    [_launchStack addArrangedSubview:_launchStatusLabel];

    // —— 大启动钮（ScalingActionButton 语义：primary 底 / onPrimary 字 /
    // 28 圆角 / 高 48 / 播放图标 + 三态文案；"zl2_home_launch" 为向导锚点）——
    _launchButton = [[UIControl alloc] init];
    _launchButton.accessibilityIdentifier = @"zl2_home_launch";
    _launchButton.layer.cornerRadius = [ZL2Theme radiusXL];   // 28（spec 定稿）
    _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
    _launchButton.isAccessibilityElement = YES;
    [_launchButton addTarget:self
                      action:@selector(launchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [_launchStack addArrangedSubview:_launchButton];

    UIImage *launchPlayImage = ZL2HomeSizedImage(@"play.fill", @"play", 18);
    _launchIconView = [[UIImageView alloc] initWithImage:[launchPlayImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _launchIconView.contentMode = UIViewContentModeScaleAspectFit;
    _launchIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _launchIconView.userInteractionEnabled = NO;

    _launchButtonLabel = [[UILabel alloc] init];
    _launchButtonLabel.font = [ZL2Theme fontLabelLarge];
    _launchButtonLabel.textColor = [ZL2Theme onPrimary];
    _launchButtonLabel.numberOfLines = 1;
    _launchButtonLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _launchButtonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchButtonLabel.userInteractionEnabled = NO;

    // 图标 + 文案水平组（stack 自带 intrinsic 尺寸，组内居中零歧义）
    UIStackView *launchContent = [[UIStackView alloc] initWithArrangedSubviews:@[_launchIconView, _launchButtonLabel]];
    launchContent.axis = UILayoutConstraintAxisHorizontal;
    launchContent.alignment = UIStackViewAlignmentCenter;
    launchContent.spacing = 8;
    launchContent.translatesAutoresizingMaskIntoConstraints = NO;
    launchContent.userInteractionEnabled = NO;
    [_launchButton addSubview:launchContent];

    // —— 插件功能直达 chip（★ Task328：插件效果可见性第三刀；无贡献行时
    //    塌缩隐藏 = 零回归）——
    _pluginChipButton = [[UIControl alloc] init];
    _pluginChipButton.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _pluginChipButton.layer.cornerRadius = [ZL2Theme radiusS];
    _pluginChipButton.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipButton.isAccessibilityElement = YES;
    _pluginChipButton.accessibilityTraits = UIAccessibilityTraitButton;
    _pluginChipButton.accessibilityIdentifier = @"zl2_home_plugin_chip";
    _pluginChipButton.hidden = YES;   // 初始塌缩，viewWillAppear 计数刷新后放行（防首建闪现）
    [_pluginChipButton addTarget:self
                          action:@selector(ame328_pluginChipTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [_launchStack addArrangedSubview:_pluginChipButton];

    UIImage *pluginChipImage = ZL2HomeSizedImage(@"puzzlepiece.extension", @"gearshape", 14);
    _pluginChipIconView = [[UIImageView alloc] initWithImage:[pluginChipImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _pluginChipIconView.contentMode = UIViewContentModeScaleAspectFit;
    _pluginChipIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _pluginChipIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipIconView.userInteractionEnabled = NO;

    _pluginChipLabel = [[UILabel alloc] init];
    _pluginChipLabel.font = [ZL2Theme fontLabelMedium];
    _pluginChipLabel.textColor = [ZL2Theme onSurface];
    _pluginChipLabel.textAlignment = NSTextAlignmentCenter;
    _pluginChipLabel.numberOfLines = 1;
    _pluginChipLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _pluginChipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipLabel.userInteractionEnabled = NO;

    UIStackView *pluginChipContent =
        [[UIStackView alloc] initWithArrangedSubviews:@[_pluginChipIconView, _pluginChipLabel]];
    pluginChipContent.axis = UILayoutConstraintAxisHorizontal;
    pluginChipContent.alignment = UIStackViewAlignmentCenter;
    pluginChipContent.spacing = 6;
    pluginChipContent.translatesAutoresizingMaskIntoConstraints = NO;
    pluginChipContent.userInteractionEnabled = NO;
    [_pluginChipButton addSubview:pluginChipContent];

    [_pluginChipButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [pluginChipContent.centerXAnchor constraintEqualToAnchor:_pluginChipButton.centerXAnchor],
        [pluginChipContent.centerYAnchor constraintEqualToAnchor:_pluginChipButton.centerYAnchor],
        [pluginChipContent.leadingAnchor constraintGreaterThanOrEqualToAnchor:_pluginChipButton.leadingAnchor constant:12],
        [_pluginChipButton.trailingAnchor constraintGreaterThanOrEqualToAnchor:pluginChipContent.trailingAnchor constant:12],
    ]];

    // —— 停靠边提示（ActionMenuDrag 简化语义的可见性说明）——
    _menuHintLabel = [[UILabel alloc] init];
    _menuHintLabel.text = localize(@"ame369.home.menu_dock_hint", @"长按菜单可切换停靠边");
    _menuHintLabel.font = [ZL2Theme fontLabelMedium];
    _menuHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _menuHintLabel.textAlignment = NSTextAlignmentCenter;
    _menuHintLabel.numberOfLines = 1;
    _menuHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchStack addArrangedSubview:_menuHintLabel];

    [NSLayoutConstraint activateConstraints:@[
        // 中段滚动区：贴栏容器三边；底缘锚启动卡顶（- 卡间隙）
        [_menuScrollView.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor],
        [_menuScrollView.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor],
        [_menuScrollView.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor],
        [_menuScrollView.bottomAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:-ZL2HomeCardGap],

        // 启动卡：贴栏容器两侧与底缘（钉底永可见）
        [_launchCard.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor],
        [_launchCard.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor],
        [_launchCard.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor],

        // 滚动内容：三边钉 contentLayoutGuide + 底缘 ≥ 内容底（短内容不滚动），
        // 宽 = 视口宽（fill）
        [_menuStack.topAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.topAnchor],
        [_menuStack.leadingAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.leadingAnchor],
        [_menuStack.trailingAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.trailingAnchor],
        [_menuScrollView.contentLayoutGuide.bottomAnchor constraintGreaterThanOrEqualToAnchor:_menuStack.bottomAnchor],
        [_menuStack.widthAnchor constraintEqualToAnchor:_menuScrollView.frameLayoutGuide.widthAnchor],

        // 启动卡内布局（四边 8pt 同律）
        [_launchStack.topAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:ZL2HomeCardPadding],
        [_launchStack.bottomAnchor constraintEqualToAnchor:_launchCard.bottomAnchor constant:-ZL2HomeCardPadding],
        [_launchStack.leadingAnchor constraintEqualToAnchor:_launchCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_launchStack.trailingAnchor constraintEqualToAnchor:_launchCard.trailingAnchor constant:-ZL2HomeCardPadding],

        // ① 瓦片卡内布局（瓦片行四边 8pt）
        [_quickNavWrap.topAnchor constraintEqualToAnchor:_quickNavCard.topAnchor constant:ZL2HomeCardPadding],
        [_quickNavWrap.bottomAnchor constraintEqualToAnchor:_quickNavCard.bottomAnchor constant:-ZL2HomeCardPadding],
        [_quickNavWrap.leadingAnchor constraintEqualToAnchor:_quickNavCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_quickNavWrap.trailingAnchor constraintEqualToAnchor:_quickNavCard.trailingAnchor constant:-ZL2HomeCardPadding],

        // ② 账户卡内布局：滚轮（高 = 同时五枚口径）+ 卡尾动作行
        [_accountFlow.topAnchor constraintEqualToAnchor:_accountCard.topAnchor constant:ZL2HomeCardPadding],
        [_accountFlow.leadingAnchor constraintEqualToAnchor:_accountCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_accountFlow.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-ZL2HomeCardPadding],
        [_accountFlow.heightAnchor constraintEqualToConstant:_accountFlow.viewportHeight],
        [_accountManageButton.topAnchor constraintEqualToAnchor:_accountFlow.bottomAnchor constant:6],
        [_accountManageButton.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-12],
        [_accountManageButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_accountManageButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_accountManageButton.bottomAnchor constraintEqualToAnchor:_accountCard.bottomAnchor constant:-4],
        [_accountSpinner.centerXAnchor constraintEqualToAnchor:_accountCard.centerXAnchor],
        [_accountSpinner.centerYAnchor constraintEqualToAnchor:_accountManageButton.centerYAnchor],

        // ③ 版本卡内布局：滚轮（高 = 五个正常实例版本信息行）+ 卡尾动作行
        [_versionFlow.topAnchor constraintEqualToAnchor:_versionCard.topAnchor constant:ZL2HomeCardPadding],
        [_versionFlow.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_versionFlow.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-ZL2HomeCardPadding],
        [_versionFlow.heightAnchor constraintEqualToConstant:_versionFlow.viewportHeight],
        [_versionSettingsButton.topAnchor constraintEqualToAnchor:_versionFlow.bottomAnchor constant:6],
        [_versionSettingsButton.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-12],
        [_versionSettingsButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionSettingsButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionSettingsButton.bottomAnchor constraintEqualToAnchor:_versionCard.bottomAnchor constant:-4],
        [_versionRefreshButton.trailingAnchor constraintEqualToAnchor:_versionSettingsButton.leadingAnchor constant:-4],
        [_versionRefreshButton.centerYAnchor constraintEqualToAnchor:_versionSettingsButton.centerYAnchor],
        [_versionRefreshButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionRefreshButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],

        // 大启动钮内布局（图标+文案水平组居中，高 48；不等式四边防溢出）
        [_launchButton.heightAnchor constraintEqualToConstant:ZL2HomeLaunchButtonHeight],
        [launchContent.centerXAnchor constraintEqualToAnchor:_launchButton.centerXAnchor],
        [launchContent.centerYAnchor constraintEqualToAnchor:_launchButton.centerYAnchor],
        [launchContent.leadingAnchor constraintGreaterThanOrEqualToAnchor:_launchButton.leadingAnchor constant:16],
        [launchContent.trailingAnchor constraintLessThanOrEqualToAnchor:_launchButton.trailingAnchor constant:-16],
        [launchContent.topAnchor constraintGreaterThanOrEqualToAnchor:_launchButton.topAnchor constant:4],
        [launchContent.bottomAnchor constraintLessThanOrEqualToAnchor:_launchButton.bottomAnchor constant:-4],
        [_launchIconView.widthAnchor constraintEqualToConstant:18],
        [_launchIconView.heightAnchor constraintEqualToConstant:18],
    ]];
}

#pragma mark - ★ Task378 五入口快航瓦片（★ Task400 驻右栏顶卡：用户规格「五个按钮在顶上」）

/// 快航瓦片区（★ Task392 单行×5：一行 文件/下载/设置/联机/AI，fillEqually
///   均分 + 6pt 等间距；★ Task400 入驻顶卡 quickNavCard——surfaceContainer/
///   radiusXL 卡片语言由卡承担，瓦片本体透明）。对称留白纪律（用户规格
///   「每个按钮与就近右侧栏边界的距离应保持一致」）：行内 fillEqually
///   均分 + 6pt 等间距 + 卡内 8pt 对称内边距 → 每枚瓦片到就近边界距离
///   一致。着色走 ZL2Theme 动态令牌（系统深浅自适应），无写死颜色。
'''

replace_range("/// ActionMenu 竖排：账号卡 → 版本选择卡 → 弹性占位 → 下载状态行 →",
              "- (void)ame378_buildQuickNav {",
              NEW_ACTION_MENU, "P5-action-menu")

# ───────────────────────── P6 瓦片入驻顶卡 ─────────────────────────
replace_once(
'''    _quickNavWrap.accessibilityIdentifier = @"zl2_shell_topbar_rail";
    [_menuStack addArrangedSubview:_quickNavWrap];
}''',
'''    _quickNavWrap.accessibilityIdentifier = @"zl2_shell_topbar_rail";
    // ★ Task400：瓦片行入驻顶卡（卡片化重构——quickNavCard 承担卡片语言，
    //   瓦片本体透明；约束由 ame_buildActionMenu 统一挂）
    [_quickNavCard addSubview:_quickNavWrap];
}''', "P6-quicknav-into-card")

# ───────────────────────── P7 refreshLaunchState 重建序 ─────────────────────────
replace_once(
'''- (void)refreshLaunchState {
    [self ame_refreshAccountCard];
    [self ame_refreshVersionCard];
    [self ame_refreshLaunchButton];
    // 实例网格随三态刷新全量重建（列表小、PLProfiles 为内存注册表，廉价；
    // 壳侧手动调 / viewWillAppear 回来时保证网格与选择卡一致）
    [self ame_rebuildData];
    [self ame_rebuildGrid];
}''',
'''- (void)refreshLaunchState {
    // ★ Task400：数据先行（版本滚轮以 ame_rows 为数据源——原序卡刷新在前/
    //   行模型重建在后，滚轮化后刷新依赖行模型，重建序前移；语义不变：
    //   壳侧手动调 / viewWillAppear 回来时保证网格与滚轮一致）
    [self ame_rebuildData];
    [self ame_rebuildGrid];
    [self ame_refreshAccountCard];
    [self ame_refreshVersionCard];
    [self ame_refreshLaunchButton];
}''', "P7-refresh-order")

# ───────────────────────── P8+P9 账户/版本刷新改滚轮 ─────────────────────────
NEW_REFRESH = '''// —— 账户封面流（★ Task400：原头像+名称卡原地 iPod 化——数据源扫描与
//    账户页 reloadAccounts 同口径（Task180 去重/坏文件过滤）；初始落定 =
//    当前选中账户（accountId 精确比对，同名账户也能正确区分）；无账户 =
//    单条「未登录」占位（登录入口 = 卡尾管理钮 / 无账号点启动续登录链）——
- (void)ame_refreshAccountCard {
    [self ame400_reloadAccountList];

    NSString *ame400_selectedId = nil;
    NSDictionary *ame400_currentData = BaseAuthenticator.current.authData;
    if ([ame400_currentData isKindOfClass:[NSDictionary class]]) {
        ame400_selectedId = ame400_currentData[@"accountId"] ?: ame400_currentData[@"username"];
    }

    NSMutableArray<UIView *> *ame400_items = [NSMutableArray array];
    __block NSUInteger ame400_selectedIdx = 0;   // 枚举块内赋值（Task393 CI 实锤：缺 __block 编译雷）

    if (self.ame400_accountList.count == 0) {
        [ame400_items addObject:[self ame400_signedOutFlowItem]];
    } else {
        [self.ame400_accountList enumerateObjectsUsingBlock:^(NSDictionary *ame400_accountData, NSUInteger idx, BOOL *stop) {
            [ame400_items addObject:[self ame400_accountFlowItemForData:ame400_accountData]];
            NSString *ame400_key = ame400_accountData[@"accountId"] ?: ame400_accountData[@"username"];
            if (ame400_selectedId.length > 0 && [ame400_selectedId isEqualToString:ame400_key]) {
                ame400_selectedIdx = idx;
            }
        }];
    }

    [self.accountFlow configureItems:ame400_items];
    [self.accountFlow setSelectedIndex:(NSInteger)ame400_selectedIdx animated:NO];
}

// —— 版本封面流（★ Task400：原版本选择卡原地 iPod 化——占五个正常实例
//    版本信息高度（用户规格「实例版本也一样改，占用的比例算五个正常的
//    实例版本信息高度」）；初始落定 = 当前选中实例；空注册表 = 单条
//    「选择版本」占位（空态卡引导下载）——
- (void)ame_refreshVersionCard {
    NSMutableArray<UIView *> *ame400_items = [NSMutableArray array];
    __block NSUInteger ame400_selectedIdx = 0;   // 枚举块内赋值（Task393 CI 实锤：缺 __block 编译雷）

    if (self.ame_rows.count == 0) {
        [ame400_items addObject:[self ame400_emptyVersionFlowItem]];
    } else {
        [self.ame_rows enumerateObjectsUsingBlock:^(NSDictionary *ame400_row, NSUInteger idx, BOOL *stop) {
            [ame400_items addObject:[self ame400_versionFlowItemForRow:ame400_row]];
            if ([ame400_row[@"isSelected"] boolValue]) ame400_selectedIdx = idx;
        }];
    }

    [self.versionFlow configureItems:ame400_items];
    [self.versionFlow setSelectedIndex:(NSInteger)ame400_selectedIdx animated:NO];
}

'''

replace_range('// —— 账号卡 ——（显示名取 BaseAuthenticator.current.authData[@"username"]，',
              "// —— 大启动钮三态 ——",
              NEW_REFRESH, "P8P9-refresh-cards")

# ───────────────────────── P10 versionCardTapped 退役 ─────────────────────────
replace_once(
'''- (void)accountCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

// 版本选择卡卡体 = ★ Task393 iPod 式竖排选择器（用户规格「版本选择也是
//   一样，竖排式的」：原直跳版本管理页退役为齿轮钮专属——versionSettingsTapped
//   仍直达管理页，管理/选择双职能自此分家）
- (void)versionCardTapped {
    [self ame393_presentVersionPicker];
}

- (void)versionSettingsTapped {''',
'''// 账户管理入口（★ Task400：原账号卡点击语义收口至账户卡尾管理小钮）
- (void)accountCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

// ★ Task400：versionCardTapped 退役（版本滚轮原地驻卡内，拖拽即选择；
//   管理入口 = 卡尾齿轮钮 versionSettingsTapped 不变）

- (void)versionSettingsTapped {''', "P10-tap-handlers")

# ───────────────────────── P11 Task393 弹层块 → Task400 滚轮块 ─────────────────────────
NEW_WHEELS = '''#pragma mark - ★ Task400 右栏原地封面流（账户/版本双滚轮 + 账户选中链）

// 账户数据源扫描（账户页 reloadAccounts 同口径 1:1：POJAV_HOME/accounts/*.json
// + Task180 双保险——accountId 去重 + 解析失败文件过滤）
- (void)ame400_reloadAccountList {
    if (self.ame400_accountList == nil) {
        self.ame400_accountList = [NSMutableArray array];
    } else {
        [self.ame400_accountList removeAllObjects];
    }

    NSString *ame400_listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *ame400_fm = [NSFileManager defaultManager];
    NSArray *ame400_files = [ame400_fm contentsOfDirectoryAtPath:ame400_listPath error:nil];
    NSMutableSet *ame400_seenIds = [NSMutableSet set];
    for (NSString *ame400_file in ame400_files) {
        NSString *ame400_path = [ame400_listPath stringByAppendingPathComponent:ame400_file];
        BOOL ame400_isDir = NO;
        [ame400_fm fileExistsAtPath:ame400_path isDirectory:(&ame400_isDir)];
        if (!ame400_isDir && [ame400_file hasSuffix:@".json"]) {
            NSDictionary *ame400_data = parseJSONFromFile(ame400_path);
            if (ame400_data == nil || ame400_data[@"NSErrorObject"] != nil) {
                NSLog(@"[ZL2Home] skipping unreadable account file: %@", ame400_file);
                continue;
            }
            NSString *ame400_key = ame400_data[@"accountId"] ?: [ame400_file stringByDeletingPathExtension];
            if ([ame400_seenIds containsObject:ame400_key]) continue;
            [ame400_seenIds addObject:ame400_key];
            [self.ame400_accountList addObject:ame400_data];
        }
    }
}

// 未登录占位条目（原账号卡「未登录」+ 加号占位同款语义；单条不可换选——
// 滚轮 onSettle 只在下标变化时回调，恒居中零误触）
- (UIView *)ame400_signedOutFlowItem {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_avatar = [[UIImageView alloc] init];
    UIImage *ame400_placeholder = ZL2HomeSystemImage(@"plus.circle.fill", @"plus.circle");
    ame400_avatar.image = [ame400_placeholder imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_avatar.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_avatar.contentMode = UIViewContentModeScaleAspectFit;
    ame400_avatar.isUserInteractionEnabled = NO;
    ame400_avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_avatar];

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelLarge];
    ame400_nameLabel.textColor = [ZL2Theme onSurface];
    ame400_nameLabel.text = localize(@"i18n_str_357", nil);   // 未登录（旧账号卡同键）
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    UILabel *ame400_typeLabel = [[UILabel alloc] init];
    ame400_typeLabel.font = [ZL2Theme fontLabelMedium];
    ame400_typeLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_typeLabel.text = @"";
    ame400_typeLabel.numberOfLines = 1;
    ame400_typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_typeLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_typeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [ame400_avatar.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:16],
        [ame400_avatar.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [ame400_avatar.widthAnchor constraintEqualToConstant:40],
        [ame400_avatar.heightAnchor constraintEqualToConstant:40],
        [ame400_nameLabel.leadingAnchor constraintEqualToAnchor:ame400_avatar.trailingAnchor constant:10],
        [ame400_nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-9],
        [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-12],
        [ame400_typeLabel.leadingAnchor constraintEqualToAnchor:ame400_nameLabel.leadingAnchor],
        [ame400_typeLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:9],
        [ame400_typeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-12],
    ]];
    return ame400_item;
}

// 账户条目（★ Task400：横排 = 头像 40 + 名称/类型双行——原右侧栏「头像+
//   名称」卡同一呈现语言（用户规格「用相同方式在原地做出一样的横排效果」）；
//   条目底透明（卡面即背景，选中零装饰）；MC 头像圆角 = 1 物理像素超小
//   圆角（用户规格「圆角大小占用正常头像一个像素」））
- (UIView *)ame400_accountFlowItemForData:(NSDictionary *)accountData {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_avatarView = [[UIImageView alloc] init];
    UIImage *ame400_placeholder = ZL2HomeSystemImage(@"person.crop.circle.fill", @"person.circle.fill");
    ame400_avatarView.image = [ame400_placeholder imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_avatarView.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_avatarView.contentMode = UIViewContentModeScaleAspectFill;
    // ★ Task400：MC 头像 1 物理像素超小圆角（1pt ÷ 屏幕 scale；原圆形口径退役）
    ame400_avatarView.layer.cornerRadius = 1.0 / [UIScreen mainScreen].scale;
    ame400_avatarView.layer.masksToBounds = YES;
    ame400_avatarView.isUserInteractionEnabled = NO;
    ame400_avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_avatarView];

    NSString *ame400_displayName = accountData[@"username"] ?: @"";
    if ([ame400_displayName hasPrefix:@"Demo."]) {
        ame400_displayName = [ame400_displayName substringFromIndex:5];
    }

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelLarge];
    ame400_nameLabel.textColor = [ZL2Theme onSurface];
    ame400_nameLabel.text = ame400_displayName;
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    UILabel *ame400_typeLabel = [[UILabel alloc] init];
    ame400_typeLabel.font = [ZL2Theme fontLabelMedium];
    ame400_typeLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_typeLabel.text = [self ame_typeTextForAccountData:accountData];
    ame400_typeLabel.numberOfLines = 1;
    ame400_typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_typeLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_typeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [ame400_avatarView.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:16],
        [ame400_avatarView.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [ame400_avatarView.widthAnchor constraintEqualToConstant:40],
        [ame400_avatarView.heightAnchor constraintEqualToConstant:40],
        [ame400_nameLabel.leadingAnchor constraintEqualToAnchor:ame400_avatarView.trailingAnchor constant:10],
        [ame400_nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-9],
        [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-12],
        [ame400_typeLabel.leadingAnchor constraintEqualToAnchor:ame400_nameLabel.leadingAnchor],
        [ame400_typeLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:9],
        [ame400_typeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-12],
    ]];

    // 头像异步取（AvatarManager 三层回退链；弱引用条目，回调晚到不吊命已拆条目）
    __weak UIImageView *ame400_weakAvatar = ame400_avatarView;
    [[AvatarManager sharedManager] ame185_fetchAvatarForAuthData:accountData
                                                      completion:^(UIImage *image) {
        if (image && ame400_weakAvatar) {
            ame400_weakAvatar.image = image;   // 默认渲染，1px 超小圆角裁切
            ame400_weakAvatar.tintColor = nil;
        }
    }];
    return ame400_item;
}

// 空注册表占位条目（原版本卡「选择版本」空态同款语义；单条不可换选，
// 齿轮钮/空态卡承接下载引导）
- (UIView *)ame400_emptyVersionFlowItem {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_iconView = [[UIImageView alloc] init];
    UIImage *ame400_fallback = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
    ame400_iconView.image = [ame400_fallback imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_iconView.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_iconView.contentMode = UIViewContentModeScaleAspectFit;
    ame400_iconView.isUserInteractionEnabled = NO;
    ame400_iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_iconView];

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelLarge];
    ame400_nameLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_nameLabel.text = localize(@"ame369.home.select_version", @"选择版本");
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    UILabel *ame400_infoLabel = [[UILabel alloc] init];
    ame400_infoLabel.font = [ZL2Theme fontLabelMedium];
    ame400_infoLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_infoLabel.text = @"";
    ame400_infoLabel.numberOfLines = 1;
    ame400_infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_infoLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_infoLabel];

    [NSLayoutConstraint activateConstraints:@[
        [ame400_iconView.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:14],
        [ame400_iconView.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [ame400_iconView.widthAnchor constraintEqualToConstant:40],
        [ame400_iconView.heightAnchor constraintEqualToConstant:40],
        [ame400_nameLabel.leadingAnchor constraintEqualToAnchor:ame400_iconView.trailingAnchor constant:10],
        [ame400_nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-10],
        [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14],
        [ame400_infoLabel.leadingAnchor constraintEqualToAnchor:ame400_nameLabel.leadingAnchor],
        [ame400_infoLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:10],
        [ame400_infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14],
    ]];
    return ame400_item;
}

// 版本条目（★ Task400：横排 = 加载器图标 40 + 实例名/信息行，条目高 64 =
//   原版本选择卡同族口径（「五个正常的实例版本信息高度」）；条目底透明
//   （卡面即背景）；信息行三态与实例卡 ame_configureWithRow 同一语义）
- (UIView *)ame400_versionFlowItemForRow:(NSDictionary *)row {
    NSString *profileName = row[@"name"];
    NSString *versionId = row[@"versionId"];
    NSString *loader = row[@"loader"];
    NSString *mcVersion = row[@"mcVersion"];
    BOOL valid = [row[@"valid"] boolValue];

    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [ame400_item addSubview:iconView];

    // 实例图标：加载器图标（原版本卡同款）；取不到 → gamecontroller 兜底
    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:iconView
                                      forLoader:loader
                                 traitCollection:self.traitCollection];
    } else {
        UIImage *fallbackIcon = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
        iconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iconView.tintColor = [ZL2Theme onSurfaceVariant];
    }

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.font = [ZL2Theme fontLabelLarge];
    nameLabel.textColor = [ZL2Theme onSurface];
    nameLabel.text = profileName;
    nameLabel.numberOfLines = 1;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:nameLabel];

    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.font = [ZL2Theme fontLabelMedium];
    infoLabel.textColor = [ZL2Theme onSurfaceVariant];
    infoLabel.numberOfLines = 1;
    infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:infoLabel];

    // 信息行：与实例卡同款三态（无效 = error 色引导文案）
    if (!valid) {
        if (versionId.length == 0) {
            infoLabel.text = localize(@"ame351.instance.no_version", nil);
        } else {
            infoLabel.text = localize(@"ame369.common.invalid_version", @"该版本无效");
        }
        infoLabel.textColor = [ZL2Theme error];
    } else {
        if (mcVersion.length > 0 && loader.length > 0) {
            infoLabel.text = [NSString stringWithFormat:@"MC %@ · %@",
                              mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
        } else if (mcVersion.length > 0) {
            infoLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
        } else if (loader.length > 0) {
            infoLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
        } else {
            infoLabel.text = @"";
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:14],
        [iconView.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:40],
        [iconView.heightAnchor constraintEqualToConstant:40],
        [nameLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
        [nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-10],
        [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14],
        [infoLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [infoLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:10],
        [infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14],
    ]];
    return ame400_item;
}

// 选用实例（Task393 原方法保留：写 selected + save + post
// @"SelectedProfileChanged"；本页监听该通知刷新网格与滚轮——原地滚轮的
// 选用提交点 = versionFlow.onSettle）
- (void)ame393_selectProfileAtIndex:(NSUInteger)index {
    if (index >= self.ame_rows.count) return;
    NSString *profileName = self.ame_rows[index][@"name"];
    if (![profileName isKindOfClass:[NSString class]] || profileName.length == 0) return;
    NSString *selected = PLProfiles.current.selectedProfileName;
    if ([profileName isEqualToString:selected]) return;
    PLProfiles.current.selectedProfileName = profileName;
    [PLProfiles.current save];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
}

// —— 账户选中链（★ Task400：账户页 selectAccountAtIndex 同款 1:1——第三方
//    Task128 会话校验/stale 优雅降级、微软/本地 loadSavedName+refreshToken
//    全链；锁滚轮 + spinner 占位；收尾 = 重建滚轮 + 发 @"UpdateAccountInfo"
//    （主页 pendingLaunchAfterLogin 续启动契约不变）——
- (void)ame400_selectAccountAtIndex:(NSUInteger)index {
    if (self.accountFlow.interactionLocked) return;
    if (index >= self.ame400_accountList.count) return;
    NSDictionary *ame400_accountData = self.ame400_accountList[index];

    // 优先用 accountId 加载；若 accountId 缺失（旧格式账户未迁移），回退
    // 到 username 触发迁移（旧链同款）
    NSString *ame400_loadKey = ame400_accountData[@"accountId"];
    if (ame400_loadKey.length == 0) {
        ame400_loadKey = ame400_accountData[@"username"];
    }

    self.accountFlow.interactionLocked = YES;
    [self.accountSpinner startAnimating];

    if (ZL2AccountsSharedIsThirdParty(ame400_accountData)) {
        // 第三方：Task128 zl2 同款 isSessionValidated——本会话已通过服务端
        // 校验直接选中；否则 refresh，成功选中、失败优雅降级（stale token
        // 仍选中 + toast 提示重新登录）
        ThirdPartyAuthenticator *ame400_auth = [ThirdPartyAuthenticator loadSavedName:ame400_loadKey];
        if ([ZL2AccountsSharedValidatedSet() containsObject:ame400_loadKey]) {
            [self ame400_finishAccountSelection];
        } else {
            __weak typeof(self) weakSelf = self;
            [ame400_auth refreshTokenWithCallback:^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [ZL2AccountsSharedValidatedSet() addObject:ame400_loadKey];
                        [weakSelf ame400_handleAuthResult:status success:YES];
                    } else {
                        // Task128 优雅回退：refresh 失败仍选中（current 已由
                        // loadSavedName 设置 + selected_account 持久化）
                        [ZL2AccountsSharedValidatedSet() addObject:ame400_loadKey];
                        setPrefObject(@"internal.selected_account", ame400_loadKey);
                        [weakSelf ame400_finishAccountSelection];
                        [NMToast showMessage:[NSString stringWithFormat:@"%@\\n%@",
                            localize(@"login.3rdparty.stale.title", nil),
                            localize(@"login.3rdparty.stale.message", nil)]
                                      duration:6.0];
                    }
                });
            }];
        }
    } else {
        // 微软/本地：loadSavedName + refreshTokenWithCallback → 共用收尾
        __weak typeof(self) weakSelf = self;
        [[BaseAuthenticator loadSavedName:ame400_loadKey] refreshTokenWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf ame400_handleAuthResult:status success:success];
            });
        }];
    }
}

// 认证收尾（账户页 handleAuthResult 同款：成功 toast/演示弹窗/finish；
// 失败错误弹窗——present 到本页）
- (void)ame400_handleAuthResult:(id)status success:(BOOL)success {
    if (status != nil) {
        if (success) {
            NSString *ame400_message = nil;
            if ([status isKindOfClass:NSError.class]) {
                ame400_message = [(NSError *)status localizedDescription];
            } else if ([status isKindOfClass:NSString.class]) {
                ame400_message = (NSString *)status;
            }
            if (ame400_message.length > 0) {
                [NMToast showMessage:[NSString stringWithFormat:@"%@：%@",
                    localize(@"login.title", @"账户"), ame400_message]
                              duration:6.0];
            }
            if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"]) {
                // 演示模式警告仍需用户知悉（影响后续离线体验预期），保留弹窗
                [self ame400_showDemoDialog];
            }
            [self ame400_finishAccountSelection];
        } else {
            [self ame400_handleAuthFailure:status];
        }
    } else if (success) {
        // 成功登录，无消息
        [self ame400_finishAccountSelection];
    }
}

- (void)ame400_handleAuthFailure:(id)status {
    // 认证失败：恢复交互并展示错误（账户页 handleAuthFailure 同款，含
    // AFNetworking 响应体细节）
    self.accountFlow.interactionLocked = NO;
    [self.accountSpinner stopAnimating];
    if ([status isKindOfClass:[NSError class]]) {
        NSData *ame400_errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        if (ame400_errorData) {
            NSString *ame400_errorStr = [[NSString alloc] initWithData:ame400_errorData
                                                               encoding:NSUTF8StringEncoding];
            NSLog(@"[MSA] Error: %@", ame400_errorStr);
            [self ame400_showErrorDialog:ame400_errorStr];
        } else {
            [self ame400_showErrorDialog:[status localizedDescription]];
        }
    } else if ([status isKindOfClass:NSString.class]) {
        [self ame400_showErrorDialog:status];
    } else {
        [self ame400_showErrorDialog:localize(@"login.error.invalid_response", nil)];
    }
}

- (void)ame400_showDemoDialog {
    UIAlertController *ame400_alert = [UIAlertController
        alertControllerWithTitle:localize(@"login.warn.title.demomode", nil)
                         message:localize(@"login.warn.message.demomode", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [ame400_alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:ame400_alert animated:YES completion:nil];
}

- (void)ame400_showErrorDialog:(NSString *)message {
    UIAlertController *ame400_alert = [UIAlertController
        alertControllerWithTitle:localize(@"Error", nil)
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [ame400_alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:ame400_alert animated:YES completion:nil];
}

// 选中/登录/刷新成功收尾：恢复交互 + 重建滚轮 + 发 @"UpdateAccountInfo"
//（账户页 finishSelection 等价物——setSelectedIndex 程序化滚动不回调
// onSettle，重建零回环）
- (void)ame400_finishAccountSelection {
    self.accountFlow.interactionLocked = NO;
    [self.accountSpinner stopAnimating];
    [self ame_refreshAccountCard];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo"
                                                        object:nil
                                                      userInfo:nil];
}

'''

replace_range("#pragma mark - ★ Task393 版本选择封面流弹层（iPod 式竖排）",
              "#pragma mark - Launch Chain",
              NEW_WHEELS, "P11-wheels")

with io.open(PATH, "w", encoding="utf-8", newline="") as f:
    f.write(data)
print("WRITTEN. total chars:", len(data))
