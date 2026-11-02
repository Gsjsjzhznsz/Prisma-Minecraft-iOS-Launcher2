//
// ZL2ShellViewController.m — ZL2 壳实现（7.0-UI-10-b 起家；Task378 起默认 bare 壳）
//
// 【历史规格存档】以下 TopBar 结构对应注释为 7.0-UI-10-b~377 顶栏形态的
// 设计文档——★ Task378 起顶栏整体退役（bare 壳），本段仅作溯源存档，
// 不再描述现役结构。
//
// ★ Task378（用户两轮复诉）：①全局文本颜色根修——白黑双重叠（Task227~251
//   描边字体链）整体退役，全部文本回归系统深浅语义色（BackgroundManager）；
//   ②顶栏退役——topbar 骨架改 bare 壳（本文件 ame_buildBareShell），五入口
//   按钮迁移主页右侧栏顶部（ZL2HomeViewController quickNav，2.5x 瓦片，
//   前三后二）；nav（navigationview）骨架与门禁锚点逐字保留。
//
// ZL2 MainScreen.kt 顶栏结构对应（ref/ZalithLauncher2/ZalithLauncher/src/main/
// java/com/movtery/zalithlauncher/ui/screens/main/MainScreen.kt L168-246 实证）：
//   Surface(backgroundColor) { Column { TopBar(fillMaxWidth().height(40.dp))
//   + Box(fillMaxWidth().weight(1f)) { NavigationUI(...) } } }
//   ——无 NavigationRail、无底栏。iOS 对应：topBar（内容 40pt；iPhone 竖放时
//   safeAreaInsets.top 区域由 topBar 容器向上延伸补 surface 底色，内容带钉
//   safeArea 下缘）+ container（余下全部；子页懒建缓存 + 首显 attach +
//   0.18s crossDissolve 机制自 7.0-UI-8/9 平移不变）。
// TopBar 内部（同文件 L248-483 已审计）：
//   · 左簇 backCenter：AnimatedVisibility(!inLauncherScreen) 内 12dp + [←返回]
//     + [🏠主页] → iOS leftCluster（横 Stack spacing 4 + 前导 12 边距，返回/
//     主页各 32×32 图标钮）。iOS 适配语义：仅当前页 != 主页时整簇显示
//     （0.18s alpha/hidden 塌缩动画）；返回钮 = 当前页 nav 可 pop 时
//     popViewControllerAnimated:（子页 push 层的系统返回栏仍按各页
//     viewWillAppear/viewWillDisappear 既有约定工作，顶栏返回是辅助手势），
//     不可 pop 时收起返回钮只留主页钮（ZL2 返回键恒显 + onBackPressed 兜底，
//     iOS 侧以显隐表达同一语义）；主页钮 = showPageAtIndex:0。
//   · 标题 title：titleMedium 左对齐，start = backCenter.end + 16dp，
//     Crossfade → iOS titleLabel（fontTitleMedium，跟左簇 16pt，0.18s 交叉
//     过渡；子页 push 态显示「页名 - 子页名」，对应 MainScreen.kt L358-362
//     的 parent + " - " + child）。主页标题 = CFBundleDisplayName（兜底
//     @"Prisma Launcher"，对应 L345 LAUNCHER_IDENTIFIER 位）。
//   · 右簇 endButtons：end margin 12dp、spacing 8dp → iOS rightCluster
//     （trailing 12 边距、spacing 8）。
//     a) 任务胶囊（AnimatedVisibility：任务运行且未展开时；宽 120dp，
//        LinearProgressIndicator + assignment 图标）→ iOS taskPill
//        （surfaceContainerHigh 底 radiusXL 全圆，高 28 宽 120：UIProgressView
//        track outlineVariant / bar primary，取 DownloadTaskManager 第一个
//        活动任务 progress 负值截 0 + doc.plaintext 图标 template + 活动任务
//        数 fontLabelMedium；仅 hasActiveTasks 时显示——iOS 侧无任务菜单
//        展开态；点击 = PLTaskProgressViewController presentForTaskId: 第一
//        个活动任务）。
//     b) TopBarRailItem（= ui/components/_SimpleRail.kt TextRailItem：图标
//        恒显 + 选中时文字 AnimatedVisibility）→ iOS RailItem（图标 22pt
//        template 恒显 + 选中态文字 fontLabelMedium 宽度 0 ↔ 实宽 0.18s
//        展开/收起，未选宽 0 裁剪；选中 primary / 未选 onSurfaceVariant）。
//        📁文件按钮与联机 RailItem iOS 侧本轮省略（文件管理器/联机页尚未有
//        可嵌页面），待功能域落地后补位。
//   · iOS 侧 RailItem×5（ZL2 顶栏无版本/账户直达；Task318 起新增第 5 项 AI）：
//     文件夹(瞬时) / 多人联机(5) / 下载(1) / 设置(4) / AI 助手(6)，与 ZL2 右侧组同序排列。
//
// 页面 index 映射（.h 契约：0...6，越界忽略）：
//   0 主页 ZL2HomeViewController（不包 nav；顶栏标题 = CFBundleDisplayName）
//   1 下载 ZL2DownloadViewController（UINavigationController 包）
//   2 版本 ZL2VersionsViewController（UINavigationController 包）
//   3 账户 ZL2AccountsViewController（UINavigationController 包）
//   4 设置 ZL2SettingsViewController（UINavigationController 包）
//   5 多人联机 MultiplayerViewController（7.0-UI-14；UINavigationController 包）
//   6 AI 助手 AIViewController（Task318 入口恢复；UINavigationController 包）
//
// 通知契约（消费方，7.0-UI-8 三件原样保留 + 顶栏新增两件）：
//   @"ShowHomePage"                              → 切主页（旧启动链）
//   @"ShowAccountManager"                        → 切账户页（FCL 风格）
//   ZL2ShellNavigateNotification                 → userInfo[@"index"] 切页（0...6
//                                                  越界忽略；Task318 起新增 6=AI 助手）
//   DownloadTaskManagerDidUpdateTaskNotification → 任务胶囊刷新（manager 全部
//     变更均经 postUpdateForTask 派发；防御性回主线程后刷 UI）+ viewWillAppear
//     补刷
//   UINavigationControllerDelegate.didShow → 返回钮显隐与
//     「页名 - 子页名」标题跟随当前 nav 栈深刷新（非当前子 nav 时忽略；
//     DidShow 通知常量在 SDK 非公开——CI 实证 undeclared，改走公开 delegate）
//
// 红线遵守：iOS 14.0+（无 button.configuration/UIMenu 等 iOS15+ API；
//   AnimatedVisibility 以 UIStackView hidden 塌缩 + 宽度约束动画等价实现）；
//   颜色/字体/圆角一律 ZL2Theme 动态令牌（无 traitCollection 分支）；新建
//   视图逐一 translatesAutoresizingMaskIntoConstraints=NO；无 viewWithTag
//   身份查找（点击载荷统一 ame_action block + 构造参数）；dealloc 统一移除
//   全部通知观察者。ZL2RailView.m 本体不删不改（CMake 照旧编译），壳不再
//   使用（旧 .h 断言方法 railWidthForSizeClass: 数值冻结保留）。
//

#import "ZL2ShellViewController.h"
#import "ZL2Theme.h"
#import "ZL2VersionIndex.h"          // 7.0-UI-11：启动链版本索引服务（warmUp）
#import "ZL2HomeViewController.h"
#import "ZL2DownloadViewController.h"
#import "ZL2VersionsViewController.h"
#import "ZL2AccountsViewController.h"
#import "ZL2SettingsViewController.h"
#import "ZL2VersionDetailViewController.h"  // 7.0-UI-13：版本详情容器（主页卡/版本列表设置钮 push 目标）
#import "MultiplayerViewController.h"      // 7.0-UI-14：多人联机页（顶栏联机项，页面 5）
#import "FolderBrowserViewController.h"    // 7.0-UI-14：文件浏览器（顶栏文件夹项 PageSheet）
#import "DownloadTaskManager.h"           // manager 单例 + DownloadTaskItem + 更新通知常量
#import "PLTaskProgressViewController.h"  // 统一进度页（胶囊点开）
#import "AI/AIViewController.h"          // Task318：AI 助手入口恢复（7.0-UI-8 旧壳退役后
#import "AI/AiSessionStore.h"           //   顶栏 RailItem 第 5 项重挂；旧壳 showAIPage 同参）
#import "utils.h"                       // Task318：localize（AI 顶栏项文案四表键，缺头=隐式声明雷）
#import "BackgroundManager.h"            // ★ Task349：壁纸描边字体视图树级豁免（ame230_setViewTreeStrokeExempt）

#include <stdlib.h>

NSString * const ZL2ShellNavigateNotification = @"ZL2ShellNavigate";

#pragma mark - 几何/动画常量（ZL2 TopBar spec 对应）

static const CGFloat ZL2ShellClusterButtonSize = 32.0;  // 返回/主页钮 32×32
static const CGFloat ZL2ShellRailItemIconSize = 22.0;   // 图标 22pt
static const CGFloat ZL2ShellPillWidth = 120.0;         // 任务胶囊宽 120dp
static const CGFloat ZL2ShellPillHeight = 28.0;         // 任务胶囊高
static const CGFloat ZL2ShellAnimateDuration = 0.18;    // 全壳动画时长

// ★ Task347 NavigationView 骨架常量（WinUI 布局溯源：4pt 栅格）
static const CGFloat ZL2ShellPaneWidth = 280.0;         // 窗格宽（WinUI open 320 紧凑化）
static const CGFloat ZL2ShellPaneCompactWidth = 64.0;   // ★ Task376 折叠态图标栏宽（WinUI compact）
static const CGFloat ZL2ShellHeaderHeight = 52.0;       // 大标题内容区头高
static const CGFloat ZL2ShellRegularMinWidth = 640.0;   // ≥ 此宽常驻窗格（窄屏抽屉）

// SF Symbols 取图兜底（ZL2HomeViewController 同款静态 helper）：基名优先，
// 取不到走同族旧名，仍取不到为 nil（调用方以模板渲染前自判）
static UIImage *ZL2ShellSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - 私有点击控件：ame_action block 载荷通道（零 tag / 零 delegate）

@interface ZL2ShellTapControl : UIControl
@property(nonatomic, copy) void (^ame_action)(void);
@end

@implementation ZL2ShellTapControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // ★ Task382：基类统一 translates=NO 根修——本类子类（窗格开关钮/
        //   汉堡/返回/任务胶囊）全部 initWithFrame:CGRectZero 建立后仅靠
        //   显式约束定位，而 translates 默认 YES 会按 0×0 初帧生成 w=0/h=0
        //   遮罩约束，与显式尺寸约束同列为 required → 冲突时引擎静默破弃
        //   尺寸约束（约束冲突告警走系统统一日志不进 App stdout，装机
        //   latestlog 无告警但有 toggle={{0,0},{0,0}} 实锤）→ 折叠开关钮
        //   永久零尺寸不可点 = 用户三轮复诉「折叠侧边栏还是没有」根因。
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self addTarget:self
                 action:@selector(ame_fireAction)
       forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)ame_fireAction {
    if (self.ame_action) self.ame_action();
}

@end

#pragma mark - 顶栏图标钮（返回/主页，32×32 居中 22pt 模板图标）

@interface ZL2ShellIconButton : ZL2ShellTapControl
- (instancetype)initWithSymbol:(NSString *)symbol fallback:(NSString *)fallback;
@end

@implementation ZL2ShellIconButton

- (instancetype)initWithSymbol:(NSString *)symbol fallback:(NSString *)fallback {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        UIImage *image = ZL2ShellSystemImage(symbol, fallback);
        if (image) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *icon = [[UIImageView alloc] initWithImage:image];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        // ZL2 TopBar contentColor = onBackgroundColor → onSurface 令牌
        icon.tintColor = [ZL2Theme onSurface];
        [self addSubview:icon];
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:ZL2ShellRailItemIconSize],
            [icon.heightAnchor constraintEqualToConstant:ZL2ShellRailItemIconSize],

            [self.widthAnchor constraintEqualToConstant:ZL2ShellClusterButtonSize],
            [self.heightAnchor constraintEqualToConstant:ZL2ShellClusterButtonSize],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

@end

// ★ Task378：顶栏 RailItem（TextRailItem 等价）随顶栏整体退役——五入口按钮
//   迁移至主页右侧栏 quickNav 瓦片（见 ZL2HomeViewController）；nav 骨架
//   导航项 = 下方 ZL2ShellNavItem（Task347/376 语义保留）。

#pragma mark - ★ Task347 NavigationView 窗格导航项（WinUI NavigationViewItem 等价）

// Fluent NavigationView 左侧窗格行：选中指示条（3×16 圆角竖条，WinUI
// SelectionIndicator）+ 图标 + 标签整行按钮。几何/着色全经 ZL2Theme 令牌
// （radiusS / fontBodyMedium / primary / surfaceContainerHigh / onSurface*），
// 插件令牌覆盖即整窗格生效——与顶栏形态同一令牌消费纪律。
@interface ZL2ShellNavItem : ZL2ShellTapControl
@property(nonatomic, assign, readonly) NSInteger pageIndex;   // -1 = 瞬时动作
- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbol
                     fallback:(NSString *)fallback
                    pageIndex:(NSInteger)pageIndex;
- (void)ame_setSelected:(BOOL)selected;   // 纯状态应用（动画由壳侧统一包裹）
- (void)ame_setCompact:(BOOL)compact;     // ★ Task376：折叠图标栏态（标签隐藏 + 图标居中）
@end

@interface ZL2ShellNavItem ()
@property(nonatomic, strong) UIView *indicator;    // 3×16 选中指示条
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) NSLayoutConstraint *ame376_iconLeading; // ★ Task376：紧凑态图标居中驱动
@end

@implementation ZL2ShellNavItem

- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbol
                     fallback:(NSString *)fallback
                    pageIndex:(NSInteger)pageIndex {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _pageIndex = pageIndex;

        _indicator = [[UIView alloc] init];
        _indicator.translatesAutoresizingMaskIntoConstraints = NO;
        _indicator.backgroundColor = [ZL2Theme primary];
        _indicator.layer.cornerRadius = 1.5;
        _indicator.layer.masksToBounds = YES;
        _indicator.hidden = YES;
        [self addSubview:_indicator];

        UIImage *image = ZL2ShellSystemImage(symbol, fallback);
        if (image) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _iconView = [[UIImageView alloc] initWithImage:image];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];

        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [ZL2Theme fontBodyMedium];
        _label.text = title;
        _label.numberOfLines = 1;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            // WinUI SelectionIndicator：x=3 起 3pt 宽、16pt 高垂直居中
            [_indicator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3.0],
            [_indicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_indicator.widthAnchor constraintEqualToConstant:3.0],
            [_indicator.heightAnchor constraintEqualToConstant:16.0],
        ]];

        // ★ Task376：图标前导约束持引用 —— 紧凑态（折叠图标栏）居中驱动
        NSMutableArray<NSLayoutConstraint *> *ame376_itemConstraints = [NSMutableArray array];
        _ame376_iconLeading = [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.0];
        [ame376_itemConstraints addObject:_ame376_iconLeading];
        [ame376_itemConstraints addObjectsFromArray:@[
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:20.0],
            [_iconView.heightAnchor constraintEqualToConstant:20.0],

            [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:14.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12.0],
            [_label.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor],

            [self.heightAnchor constraintEqualToConstant:36.0],
        ]];
        [NSLayoutConstraint activateConstraints:ame376_itemConstraints];

        _iconView.tintColor = [ZL2Theme onSurfaceVariant];
        _label.textColor = [ZL2Theme onSurfaceVariant];
        self.layer.cornerRadius = [ZL2Theme radiusS];
        self.layer.masksToBounds = YES;

        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)ame_setSelected:(BOOL)selected {
    // WinUI 11 选中语义：指示条 + 中性抬升行底（M3 映射 = surfaceContainerHigh；
    // 内容着色 onSurface 强调）——区别于 ZL2 顶栏 secondaryContainer 胶囊语义
    self.indicator.hidden = !selected;
    self.backgroundColor = selected ? [ZL2Theme surfaceContainerHigh] : [UIColor clearColor];
    UIColor *tint = selected ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
    self.iconView.tintColor = tint;
    self.label.textColor = tint;
    self.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                        : UIAccessibilityTraitButton;
}

// ★ Task376：折叠图标栏态（WinUI PaneDisplayMode Compact）——标签隐藏、
// 图标在 52pt 行宽内居中（窗格 64 − 栈内边距 12 = 52，(52−20)/2 = 16）。
// 选中指示条保留（紧凑态 WinUI 同样保留 SelectionIndicator）。
- (void)ame_setCompact:(BOOL)compact {
    self.label.hidden = compact;
    self.ame376_iconLeading.constant = compact ? 16.0 : 14.0;
}

@end

#pragma mark - 任务进度胶囊（LinearProgressIndicator + assignment 等价）

@interface ZL2ShellTaskPill : ZL2ShellTapControl
- (void)ame_setProgress:(double)progress count:(NSInteger)count;
@end

@interface ZL2ShellTaskPill ()
@property(nonatomic, strong) UIProgressView *progressView;
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *countLabel;
@end

@implementation ZL2ShellTaskPill

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = [ZL2Theme surfaceContainerHigh];
        // radiusXL（28）> 高/2：CoreAnimation 渲染收敛为全圆胶囊（ZL2Download 同判例）
        self.layer.cornerRadius = [ZL2Theme radiusXL];
        self.hidden = YES;   // 显隐由壳侧 ame_refreshTaskPill 按 hasActiveTasks 派生
        self.alpha = 0.0;

        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.trackTintColor = [ZL2Theme outlineVariant];
        _progressView.progressTintColor = [ZL2Theme primary];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_progressView];

        // assignment 类图标（SF1.0 档：doc.plaintext + fallback doc.text.fill）
        UIImage *image = ZL2ShellSystemImage(@"doc.plaintext", @"doc.text.fill");
        if (image) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _iconView = [[UIImageView alloc] initWithImage:image];
        _iconView.tintColor = [ZL2Theme onSurfaceVariant];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = [ZL2Theme fontLabelMedium];
        _countLabel.textColor = [ZL2Theme onSurface];
        _countLabel.numberOfLines = 1;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:ZL2ShellPillWidth],
            [self.heightAnchor constraintEqualToConstant:ZL2ShellPillHeight],

            [_progressView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_progressView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_progressView.widthAnchor constraintEqualToConstant:56.0],
            [_progressView.heightAnchor constraintEqualToConstant:3.0],

            [_iconView.leadingAnchor constraintEqualToAnchor:_progressView.trailingAnchor constant:8.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:14.0],
            [_iconView.heightAnchor constraintEqualToConstant:14.0],

            [_countLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:4.0],
            [_countLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10.0],
        ]];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)ame_setProgress:(double)progress count:(NSInteger)count {
    [self.progressView setProgress:(float)progress animated:NO];
    self.countLabel.text = [NSString stringWithFormat:@"%ld", (long)count];
    self.accessibilityLabel = [NSString stringWithFormat:localize(@"ame369.shell.dl_tasks_fmt", @"下载任务进行中，共 %ld 个"), (long)count];
}

@end

#pragma mark - 壳本体

@interface ZL2ShellViewController () <UINavigationControllerDelegate>
@property(nonatomic, strong) UIView *topBar;                          // ★ Task378 退役占位（恒 nil；保留声明以兼容 (self.topBar ?: self.contentHeader) 门禁锚点表达式）
@property(nonatomic, strong) ZL2ShellTaskPill *taskPill;              // 任务胶囊（nav 骨架内容区头专属）
@property(nonatomic, strong) UIView *container;                       // 子页挂载区
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@property(nonatomic, assign) NSInteger currentIndex;

// ★ Task347 NavigationView 骨架态（topbar 骨架时全部闲置）
@property(nonatomic, assign) BOOL ame347_navMode;                     // 结构令牌 = navigationview
@property(nonatomic, assign) BOOL ame347_regular;                     // 宽屏常驻窗格 / 窄屏抽屉
@property(nonatomic, assign) BOOL ame347_drawerOpen;                  // 窄屏抽屉展开态
@property(nonatomic, assign) BOOL ame376_paneCollapsed;               // ★ Task376 折叠图标栏态（宽屏）
@property(nonatomic, strong) NSLayoutConstraint *ame376_paneWidth;    // ★ Task376 窗格宽约束（280↔64 驱动）
@property(nonatomic, strong) ZL2ShellIconButton *paneToggleButton;    // ★ Task376 窗格开关钮（折叠/抽屉）
@property(nonatomic, strong) UIView *paneWrap;                        // 左侧导航窗格容器
@property(nonatomic, strong) UILabel *paneTitle;                      // 窗格头（应用名）
@property(nonatomic, strong) UIScrollView *paneScroll;
@property(nonatomic, strong) UIStackView *paneStack;                  // 主导航项列
@property(nonatomic, strong) UIStackView *paneFooterStack;            // 底部固定（设置/文件）
@property(nonatomic, strong) NSArray<ZL2ShellNavItem *> *navItems;    // 全部窗格项（主 + 底）
@property(nonatomic, strong) UIView *contentHeader;                   // 大标题内容区头
@property(nonatomic, strong) ZL2ShellIconButton *hamburgerButton;     // 窄屏抽屉钮
@property(nonatomic, strong) ZL2ShellIconButton *navBackButton;       // 内容区返回钮
@property(nonatomic, strong) UILabel *headerTitle;                    // 大标题
@property(nonatomic, strong) UIView *dimOverlay;                      // 抽屉态遮罩
@property(nonatomic, strong) NSLayoutConstraint *ame347_paneLeading;  // 窗格前导（抽屉开合驱动）
@property(nonatomic, strong) NSLayoutConstraint *ame347_contentLeading; // 内容区前导（宽窄驱动）
@property(nonatomic, strong) NSLayoutConstraint *ame347_headerLeading; // ★ Task349：大标题前导（让位左钮槽位）
@property(nonatomic, assign) BOOL ame347_widthClassApplied;           // ★ Task349：首轮宽窄态必派发哨兵
@property(nonatomic, strong) NSLayoutConstraint *ame350_headerWrapLeading; // ★ Task350：内容区头前导（宽屏 = 窗格宽，头不再横穿窗格）
@property(nonatomic, assign) BOOL ame350_layoutLogged;                // ★ Task350：首帧布局自证哨兵
@property(nonatomic, strong) UIView *ame379_paneHeader;               // ★ Task379：窗格头行容器（固定 32pt，钮/标题不再锚标题 intrinsic 高度）
@property(nonatomic, strong) UIStackView *ame383_headerActions;      // ★ Task383：内容区头右上角动作簇（ZL2 顶栏右侧口径：文件/下载/账户/设置）
@end

@implementation ZL2ShellViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _childCache = [NSMutableDictionary dictionary];
        _currentIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // ★ Task349：壁纸描边字体（Task227/232 全局 setText:/drawTextInRect: 交换）
    //   视图树级豁免。装机 IMG_0522 实锤：hasBackground 设备上 ZL2 全壳满屏
    //   白底黑边幽灵字（含大标题/卡片/胶囊）——根因 = ZL2 壳所有表面均为
    //   ZL2Theme 不透明动态色（dynamicProvider alpha=1.0），壁纸从不在壳内容
    //   后透出，描边可读性处理在 opaque 面上纯损耗。树级豁免（ame230
    //   superview 链上溯 16 层）覆盖壳内全部页面/卡片/单元格；欢迎向导
    //   （Task230）/文件浏览器（Task229）/模态呈现页（独立窗口容器）既有
    //   豁免链不受影响。
    ame230_setViewTreeStrokeExempt(self.view, YES);

    // 7.0-UI-11：版本索引服务预热（远程清单在途拉取，启动链查找免竞态等待）
    [[ZL2VersionIndex sharedIndex] warmUp];

    // ★ Task347：结构令牌决定壳层导航骨架（ame347_shellLayout；插件覆盖 +
    //   Task346 根重建杠杆 = 换蓝图即时整壳重建）。默认 topbar 骨架逐位不变。
    self.ame347_navMode = [[ZL2Theme ame347_shellLayout]
                           isEqualToString:@"navigationview"];
    if (self.ame347_navMode) {
        [self ame_buildNavigationViewShell];
    } else {
        [self ame_buildBareShell];   // ★ Task378：顶栏骨架退役 = 无栏 bare 壳
    }

    // 通知契约：旧启动链（ShowHomePage）+ FCL 账户契约（ShowAccountManager）
    // + ZL2 程序化切页（ZL2ShellNavigate）+ 任务胶囊 / nav 栈深跟随
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showHome)
                                                 name:@"ShowHomePage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showAccount)
                                                 name:@"ShowAccountManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_onNavigate:)
                                                 name:ZL2ShellNavigateNotification
                                               object:nil];
    // 7.0-UI-13：版本详情打开契约（主页版本卡长按 / 版本列表页设置钮经壳统一接线，
    // 页面间零直连——ZL2 壳导航总线同口径）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_openVersionDetail:)
                                                 name:@"ZL2OpenVersionDetail"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_taskManagerDidChange:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    // ★ Task378 r2：目录瓦片接线（主页右侧栏快航 → 文件浏览器 PageSheet）——
    //   原顶栏文件夹项 ame_openFileManagerSheet 的壳统一承接通道，smoke 预览
    //   窄链接面零新增类依赖（主页不直连 FolderBrowserViewController）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_openFileManagerSheet)
                                                 name:@"ZL2ShellOpenFileManager"
                                               object:nil];

    [self showPageAtIndex:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 任务胶囊状态补刷（spec：viewWillAppear 刷新）+ 顶栏态自愈（跨屏返回等）
    [self ame_refreshTaskPill];
    [self ame_refreshTopBarStateAnimated:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ★ Task379：外观 trait 变化 → 插件事件面 appearance.changed（fluent 色板
//   实时跟随系统明暗的桥；窗口 overrideUserInterfaceStyle 偏好切换同样
//   经此传播——root VC trait 随窗口联动）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // ★ Task379 r1：iOS 17 trait 注册 API 世代的老外观差异比较选择器在
    //   Xcode 26.3 / iPhoneOS26.2 SDK 下 "no visible @interface"（CI run
    //   41445634927 + 41445630882 双红实锤）——改 userInterfaceStyle 直比
    //   （iOS 12 稳定面，语义等价：仅明暗变化即发；previous 为 nil 不误发）。
    if (!previousTraitCollection) return;
    UIUserInterfaceStyle ame379_style = self.traitCollection.userInterfaceStyle;
    if (ame379_style == previousTraitCollection.userInterfaceStyle) return;
    BOOL ame379_dark = (ame379_style == UIUserInterfaceStyleDark);
    // ★ Task380：进程级明暗去重——Task346 根重建杠杆在每次令牌落表后整壳
    //   重建，新建壳 VC 首次 trait 解析同样走本回调（style 与自身 previous
    //   不同、但与进程上一次广播值相同），事件面被同值事件灌满 → JS 重应用
    //   令牌 → 再触发重建 → 无限反馈环（装机 latestlog 00:10:37 起 ~10 次/秒
    //   实锤：全界面拆建中完全不可点击）。根修 = 广播前比对进程级上次广播
    //   值，同值不重播；真翻转（系统明暗切换/外观偏好切换）值必不同，不受
    //   影响。与 JS 侧 v2.5.1 去重、ZL2Theme 重建冷却构成三层防回环。
    static BOOL ame380_hasLastDark = NO;
    static BOOL ame380_lastDark = NO;
    if (ame380_hasLastDark && ame379_dark == ame380_lastDark) return;
    ame380_hasLastDark = YES;
    ame380_lastDark = ame379_dark;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AmeAppearanceTraitChanged"
                                                        object:nil
                                                      userInfo:@{@"dark": @(ame379_dark)}];
    NSLog(@"[Ame380] appearance broadcast dark=%d (dedup armed)", ame379_dark);
}

#pragma mark - ★ Task378 bare 壳构建（顶栏退役：容器直铺 + 子页自带导航栏）

// 顶栏（ZL2 TopBar：返回/主页左簇 + 标题 + 任务胶囊 + RailItem×5）整体退役：
//   · 五入口按钮迁移至主页右侧栏顶部（ZL2HomeViewController quickNav 瓦片，
//     22pt 图标 ×2.5 = 55pt，第一行 文件/下载/设置、第二行 联机/AI）；
//   · 任务胶囊随顶栏退役（下载进度由下载页/主页侧栏状态行承担）；
//   · 标题与返回由各子页 UINavigationController 自带导航栏承担（7.0-UI-8
//     既有约定：子页 push 层系统返回栏本就独立工作，顶栏返回仅为辅助手势）；
//   · 主页内部自理 safeArea（ActionMenu/内容区挂 safe 锚）；bare 容器全屏直铺。
- (void)ame_buildBareShell {
    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    self.container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.container];

    [NSLayoutConstraint activateConstraints:@[
        [self.container.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - ★ Task347 NavigationView 骨架（WinUI 布局：左窗格 + 大标题内容区）

// 结构蓝图消费纪律（与 topbar 骨架同源令牌）：
//   窗格 = surfaceContainerLow（Fluent 层级底）+ outlineVariant 发丝分隔；
//   导航项 = ZL2ShellNavItem（WinUI SelectionIndicator 3×16 + 中性抬升行底）；
//   内容区头 = 大标题（fontHeadline，WinUI Page Header）+ 任务胶囊复用；
//   宽屏（≥640pt）常驻窗格，窄屏（iPhone）收成抽屉 + 遮罩。
- (void)ame_buildNavigationViewShell {
    __weak typeof(self) weakSelf = self;

    // ---- 窗格（最外层最后 addSubview，抽屉态盖在内容区上）----
    self.paneWrap = [[UIView alloc] init];
    self.paneWrap.translatesAutoresizingMaskIntoConstraints = NO;
    self.paneWrap.backgroundColor = [ZL2Theme surfaceContainerLow];
    [self.view addSubview:self.paneWrap];

    // ★ Task379：窗格头行容器（固定 32pt 高）——开关钮/标题改锚容器，不再依赖
    //   标题 intrinsic 高度（装机实锤 paneTitle 零高塌缩→钮悬入状态栏带）
    self.ame379_paneHeader = [[UIView alloc] init];
    self.ame379_paneHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.ame379_paneHeader.backgroundColor = [UIColor clearColor];
    [self.paneWrap addSubview:self.ame379_paneHeader];

    // ★ Task376：窗格开关钮（WinUI NavigationView 窗格头语义）——宽屏切换
    //   Expanded(280)↔Compact(64 图标栏)，窄屏切换抽屉；态持久化 NSUserDefaults
    self.paneToggleButton = [[ZL2ShellIconButton alloc] initWithSymbol:@"sidebar.leading" fallback:@"line.3.horizontal"];
    self.paneToggleButton.accessibilityLabel = localize(@"ame369.shell.nav_a11y", @"导航");
    self.paneToggleButton.ame_action = ^{
        if (weakSelf.ame347_regular) {
            weakSelf.ame376_paneCollapsed = !weakSelf.ame376_paneCollapsed;
            [NSUserDefaults.standardUserDefaults setBool:weakSelf.ame376_paneCollapsed
                                                  forKey:@"ame376.paneCollapsed"];
            NSLog(@"[Ame376] pane toggled collapsed=%d", weakSelf.ame376_paneCollapsed);
            [weakSelf ame376_applyPaneGeometry:YES];
        } else {
            [weakSelf ame_setDrawerOpen:!weakSelf.ame347_drawerOpen animated:YES];
        }
    };
    [self.ame379_paneHeader addSubview:self.paneToggleButton];

    self.paneTitle = [[UILabel alloc] init];
    self.paneTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.paneTitle.font = [ZL2Theme fontTitleMedium];
    self.paneTitle.textColor = [ZL2Theme onSurface];
    self.paneTitle.numberOfLines = 1;
    // ★ Task379：标题文案回退链 bundle 显示名优先（processName 在
    //   LiveContainer 宿主下非确定性；display name = 用户认知的应用名）
    NSString *ame379_bundleName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"]
        ?: [NSBundle mainBundle].infoDictionary[@"CFBundleName"]
        ?: NSProcessInfo.processInfo.processName;
    if (ame379_bundleName.length == 0) ame379_bundleName = @"Prisma Launcher";
    self.paneTitle.text = ame379_bundleName;
    [self.ame379_paneHeader addSubview:self.paneTitle];

    self.paneScroll = [[UIScrollView alloc] init];
    self.paneScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.paneScroll.alwaysBounceVertical = NO;
    self.paneScroll.showsVerticalScrollIndicator = NO;
    [self.paneWrap addSubview:self.paneScroll];

    self.paneStack = [[UIStackView alloc] init];
    self.paneStack.axis = UILayoutConstraintAxisVertical;
    self.paneStack.alignment = UIStackViewAlignmentFill;
    self.paneStack.distribution = UIStackViewDistributionFill;
    self.paneStack.spacing = 2.0;
    self.paneStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.paneScroll addSubview:self.paneStack];

    // 主导航项（页面序 = 顶栏 RailItem 契约：0 主页 / 1 下载 / 2 版本 /
    // 3 账户 / 5 联机 / 6 AI；4 设置驻底部，-1 文件 = 瞬时动作）
    NSArray<NSString *> *ame347_titles = @[localize(@"ame369.common.home", @"主页"), localize(@"ame369.shell.tab.downloads", @"下载"), localize(@"ame369.shell.tab.versions", @"版本"), localize(@"ame369.shell.tab.accounts", @"账户"),
                                           localize(@"ame369.common.multiplayer", @"多人联机"), localize(@"ame192.ai.title", nil)];
    NSArray<NSString *> *ame347_symbols = @[@"house.fill",
                                            @"arrow.down.circle.fill",
                                            @"shippingbox.fill",
                                            @"person.crop.circle.fill",
                                            @"person.2.fill",
                                            @"sparkles"];
    NSArray<NSString *> *ame347_fallbacks = @[@"house",
                                              @"arrow.down.circle",
                                              @"shippingbox",
                                              @"person.crop.circle",
                                              @"person.2",
                                              @"sparkles"];
    NSArray<NSNumber *> *ame347_pages = @[@0, @1, @2, @3, @5, @6];
    NSMutableArray<ZL2ShellNavItem *> *ame347_items = [NSMutableArray array];
    [ame347_titles enumerateObjectsUsingBlock:^(NSString *itemTitle, NSUInteger idx, BOOL *stop) {
        ZL2ShellNavItem *item = [[ZL2ShellNavItem alloc]
            initWithTitle:itemTitle
                    symbol:ame347_symbols[idx]
                  fallback:ame347_fallbacks[idx]
                 pageIndex:ame347_pages[idx].integerValue];
        NSInteger ame347_target = ame347_pages[idx].integerValue;
        item.ame_action = ^{
            [weakSelf ame_setDrawerOpen:NO animated:YES];
            [weakSelf showPageAtIndex:ame347_target];
        };
        [self.paneStack addArrangedSubview:item];
        [ame347_items addObject:item];
    }];

    // 底部固定：设置（WinUI 惯例：设置驻窗格底）+ 文件（瞬时）
    // （文案走数组字面——与主导航/顶栏 RailItem 同款判例，task248 写入点闸同构）
    UIView *ame347_sep = [[UIView alloc] init];
    ame347_sep.translatesAutoresizingMaskIntoConstraints = NO;
    ame347_sep.backgroundColor = [ZL2Theme outlineVariant];
    [self.paneWrap addSubview:ame347_sep];

    self.paneFooterStack = [[UIStackView alloc] init];
    self.paneFooterStack.axis = UILayoutConstraintAxisVertical;
    self.paneFooterStack.alignment = UIStackViewAlignmentFill;
    self.paneFooterStack.spacing = 2.0;
    self.paneFooterStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.paneWrap addSubview:self.paneFooterStack];

    NSArray<NSString *> *ame347_footerTitles = @[localize(@"ame369.shell.tab.settings", @"设置"), localize(@"ame369.shell.tab.files", @"文件")];
    NSArray<NSString *> *ame347_footerSymbols = @[@"gearshape.fill", @"folder.fill"];
    NSArray<NSString *> *ame347_footerFallbacks = @[@"gearshape", @"folder"];
    NSArray<NSNumber *> *ame347_footerPages = @[@4, @(-1)];
    [ame347_footerTitles enumerateObjectsUsingBlock:^(NSString *itemTitle, NSUInteger idx, BOOL *stop) {
        ZL2ShellNavItem *item = [[ZL2ShellNavItem alloc]
            initWithTitle:itemTitle
                    symbol:ame347_footerSymbols[idx]
                  fallback:ame347_footerFallbacks[idx]
                 pageIndex:ame347_footerPages[idx].integerValue];
        NSInteger ame347_target = ame347_footerPages[idx].integerValue;
        item.ame_action = ^{
            [weakSelf ame_setDrawerOpen:NO animated:YES];
            if (ame347_target < 0) {
                // 文件 = 瞬时动作（顶栏文件夹项同语义：文件浏览器 PageSheet）
                [weakSelf ame_openFileManagerSheet];
                return;
            }
            [weakSelf showPageAtIndex:ame347_target];
        };
        [self.paneFooterStack addArrangedSubview:item];
        [ame347_items addObject:item];
    }];
    self.navItems = [ame347_items copy];

    // ---- 抽屉遮罩（窄屏展开态，点击收起）----
    self.dimOverlay = [[UIControl alloc] init];
    self.dimOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    self.dimOverlay.alpha = 0.0;
    self.dimOverlay.userInteractionEnabled = NO;
    [self.view addSubview:self.dimOverlay];
    [(UIControl *)self.dimOverlay addTarget:self action:@selector(ame_dimTapped)
                   forControlEvents:UIControlEventTouchUpInside];

    // ---- 内容区头（大标题 + 返回/汉堡 + 任务胶囊）----
    self.contentHeader = [[UIView alloc] init];
    self.contentHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentHeader.backgroundColor = [ZL2Theme surface];
    [self.view addSubview:self.contentHeader];

    self.hamburgerButton = [[ZL2ShellIconButton alloc] initWithSymbol:@"line.3.horizontal" fallback:@"text.justify"];
    self.hamburgerButton.accessibilityLabel = localize(@"ame369.shell.nav_a11y", @"导航");
    self.hamburgerButton.ame_action = ^{
        [weakSelf ame_setDrawerOpen:!weakSelf.ame347_drawerOpen animated:YES];
    };
    [self.contentHeader addSubview:self.hamburgerButton];

    self.navBackButton = [[ZL2ShellIconButton alloc] initWithSymbol:@"chevron.left" fallback:nil];
    self.navBackButton.accessibilityLabel = localize(@"ame369.common.back", @"返回");
    self.navBackButton.ame_action = ^{
        [weakSelf ame_popCurrentIfPossible];
    };
    self.navBackButton.alpha = 0.0;
    self.navBackButton.hidden = YES;
    [self.contentHeader addSubview:self.navBackButton];

    self.headerTitle = [[UILabel alloc] init];
    self.headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitle.font = [ZL2Theme fontHeadline];
    self.headerTitle.textColor = [ZL2Theme onSurface];
    self.headerTitle.numberOfLines = 1;
    self.headerTitle.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentHeader addSubview:self.headerTitle];

    self.taskPill = [[ZL2ShellTaskPill alloc] init];
    self.taskPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.taskPill.ame_action = ^{
        [weakSelf ame_openTaskProgress];
    };
    [self.contentHeader addSubview:self.taskPill];

    // ---- ★ Task383：右上角动作簇（用户复诉「界面不是和 zl2 对齐吗，右上角
    //     的按钮去哪里了」——ZL2 顶栏右侧常驻 文件/联机/下载/设置 图标簇，
    //     Task378 顶栏退役后本壳头区右侧空置；本轮按本壳页面口径回填四钮：
    //     文件=瞬时 Sheet、下载=页 1、账户=页 3、设置=页 4，全宽窄态常驻）
    self.ame383_headerActions = [[UIStackView alloc] init];
    self.ame383_headerActions.axis = UILayoutConstraintAxisHorizontal;
    self.ame383_headerActions.alignment = UIStackViewAlignmentCenter;
    self.ame383_headerActions.spacing = 6.0;
    self.ame383_headerActions.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentHeader addSubview:self.ame383_headerActions];

    NSArray<NSArray *> *ame383_entries = @[
        @[@"folder.fill", @"folder", localize(@"ame369.shell.tab.files", @"文件"), @(-1)],
        @[@"arrow.down.circle.fill", @"arrow.down.circle", localize(@"ame369.shell.tab.downloads", @"下载"), @(1)],
        @[@"person.crop.circle.fill", @"person.crop.circle", localize(@"ame369.shell.tab.accounts", @"账户"), @(3)],
        @[@"gearshape.fill", @"gearshape", localize(@"ame369.shell.tab.settings", @"设置"), @(4)],
    ];
    [ame383_entries enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger idx, BOOL *stop) {
        ZL2ShellIconButton *ame383_btn = [[ZL2ShellIconButton alloc] initWithSymbol:entry[0] fallback:entry[1]];
        ame383_btn.accessibilityLabel = entry[2];
        NSInteger ame383_page = [entry[3] integerValue];
        ame383_btn.ame_action = ^{
            [weakSelf ame_setDrawerOpen:NO animated:YES];
            if (ame383_page < 0) {
                [weakSelf ame_openFileManagerSheet];   // 文件 = 瞬时动作（窗格 footer 同语义）
                return;
            }
            [weakSelf showPageAtIndex:ame383_page];
        };
        [self.ame383_headerActions addArrangedSubview:ame383_btn];
    }];

    // ---- 内容区 ----
    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    self.container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.container];

    // 宽窄态约束一次建全：前导常量由 ame347_applyWidthClass 派发
    self.ame347_paneLeading = [self.paneWrap.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
    self.ame347_contentLeading = [self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
    // ★ Task376：窗格宽持引用（280↔64 折叠驱动）
    self.ame376_paneWidth = [self.paneWrap.widthAnchor constraintEqualToConstant:ZL2ShellPaneWidth];
    [NSLayoutConstraint activateConstraints:@[
        self.ame347_paneLeading,
        [self.paneWrap.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.paneWrap.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.ame376_paneWidth,

        // ★ Task379：头行容器几何（固定 32pt 高 + 安全区上 10pt）——钮位与
        //   滚动区顶从此不依赖标题 intrinsic 高度，零高塌缩类根绝
        [self.ame379_paneHeader.topAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.topAnchor constant:10.0],
        [self.ame379_paneHeader.leadingAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.leadingAnchor constant:8.0],
        [self.ame379_paneHeader.trailingAnchor constraintLessThanOrEqualToAnchor:self.paneWrap.trailingAnchor constant:-12.0],
        [self.ame379_paneHeader.heightAnchor constraintEqualToConstant:32.0],

        [self.paneToggleButton.leadingAnchor constraintEqualToAnchor:self.ame379_paneHeader.leadingAnchor],
        [self.paneToggleButton.centerYAnchor constraintEqualToAnchor:self.ame379_paneHeader.centerYAnchor],
        [self.paneToggleButton.widthAnchor constraintEqualToConstant:32.0],
        [self.paneToggleButton.heightAnchor constraintEqualToConstant:32.0],

        // ★ Task376：标题让位窗格开关钮（379 起锚头行容器）
        [self.paneTitle.leadingAnchor constraintEqualToAnchor:self.paneToggleButton.trailingAnchor constant:6.0],
        [self.paneTitle.centerYAnchor constraintEqualToAnchor:self.ame379_paneHeader.centerYAnchor],
        [self.paneTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.ame379_paneHeader.trailingAnchor],

        [self.paneScroll.topAnchor constraintEqualToAnchor:self.ame379_paneHeader.bottomAnchor constant:8.0],
        // ★ Task350：滚动区底部外部锚定——原实现仅 top/leading/trailing，frame
        //   高度全靠内容推导（self-sizing scroll view）在装机 iPadOS 27 上塌缩，
        //   clipsToBounds 默认 YES → 六项主导航全灭而 footer（外部锚定完整）
        //   正常 = IMG_0524 实锤“窗格在、中间空”。锚到分隔线后滚动区高度
        //   完全由外部约束确定，不再依赖内容推导。
        [self.paneScroll.bottomAnchor constraintEqualToAnchor:ame347_sep.topAnchor constant:-8.0],
        [self.paneScroll.leadingAnchor constraintEqualToAnchor:self.paneWrap.leadingAnchor],
        [self.paneScroll.trailingAnchor constraintEqualToAnchor:self.paneWrap.trailingAnchor],

        [self.paneStack.topAnchor constraintEqualToAnchor:self.paneScroll.topAnchor constant:4.0],
        [self.paneStack.leadingAnchor constraintEqualToAnchor:self.paneScroll.leadingAnchor constant:6.0],
        [self.paneStack.trailingAnchor constraintEqualToAnchor:self.paneScroll.trailingAnchor constant:-6.0],
        [self.paneStack.bottomAnchor constraintEqualToAnchor:self.paneScroll.bottomAnchor constant:-4.0],
        [self.paneStack.widthAnchor constraintEqualToAnchor:self.paneScroll.widthAnchor constant:-12.0],

        [ame347_sep.leadingAnchor constraintEqualToAnchor:self.paneWrap.leadingAnchor constant:12.0],
        [ame347_sep.trailingAnchor constraintEqualToAnchor:self.paneWrap.trailingAnchor constant:-12.0],
        [ame347_sep.heightAnchor constraintEqualToConstant:0.5],
        [ame347_sep.bottomAnchor constraintEqualToAnchor:self.paneFooterStack.topAnchor constant:-4.0],

        [self.paneFooterStack.leadingAnchor constraintEqualToAnchor:self.paneWrap.leadingAnchor constant:6.0],
        [self.paneFooterStack.trailingAnchor constraintEqualToAnchor:self.paneWrap.trailingAnchor constant:-6.0],
        [self.paneFooterStack.bottomAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.bottomAnchor constant:-6.0],

        [self.contentHeader.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        // 与 topBar 同款 safeArea 延伸语义：头底 = safeArea 顶 + 52
        [self.contentHeader.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                                        constant:ZL2ShellHeaderHeight],
        // ★ Task350：头前导可变——宽屏 = 窗格宽（280，与内容区对齐，大标题/
        //   胶囊只在内容区绘制；原实现恒全宽，大标题画在窗格上与 paneTitle
        //   同位重叠 = IMG_0524 “ZalithLauncher” 顶在窗格头上的实锤）；
        //   窄屏 = 0（汉堡/返回驻头左，抽屉语义不变）。
        self.ame350_headerWrapLeading = [self.contentHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        self.ame350_headerWrapLeading,
        [self.contentHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.hamburgerButton.leadingAnchor constraintEqualToAnchor:self.contentHeader.safeAreaLayoutGuide.leadingAnchor constant:8.0],
        [self.hamburgerButton.centerYAnchor constraintEqualToAnchor:self.contentHeader.centerYAnchor],

        [self.navBackButton.leadingAnchor constraintEqualToAnchor:self.contentHeader.safeAreaLayoutGuide.leadingAnchor constant:8.0],
        [self.navBackButton.centerYAnchor constraintEqualToAnchor:self.contentHeader.centerYAnchor],

        // ★ Task349：大标题前导改为可变约束——窄屏汉堡/返回钮（32pt 槽位）
        //   与标题同位重叠，由 ame_refreshNavShellStateAnimated 按可见性派发。
        self.ame347_headerLeading = [self.headerTitle.leadingAnchor constraintEqualToAnchor:self.contentHeader.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        self.ame347_headerLeading,
        [self.headerTitle.centerYAnchor constraintEqualToAnchor:self.contentHeader.centerYAnchor],
        [self.headerTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.taskPill.leadingAnchor constant:-12.0],

        // ★ Task383：动作簇驻头区右侧常驻（宽窄态同权）；任务胶囊改锚簇左
        //   侧（可见时不与簇重叠；隐藏时簇仍贴右缘——旧锚 self 头区右缘会
        //   因胶囊占位把簇挤左 132pt 空档）
        [self.ame383_headerActions.trailingAnchor constraintEqualToAnchor:self.contentHeader.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
        [self.ame383_headerActions.centerYAnchor constraintEqualToAnchor:self.contentHeader.centerYAnchor],

        [self.taskPill.trailingAnchor constraintEqualToAnchor:self.ame383_headerActions.leadingAnchor constant:-12.0],
        [self.taskPill.centerYAnchor constraintEqualToAnchor:self.contentHeader.centerYAnchor],

        [self.container.topAnchor constraintEqualToAnchor:self.contentHeader.bottomAnchor],
        self.ame347_contentLeading,
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.dimOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.dimOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.dimOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.dimOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 宽窄态哨兵：预置 YES（与抽屉闭合判定相反），保证首轮
    // viewDidLayoutSubviews 必派发一次宽窄态（iPhone 闭合 / iPad 常驻），
    // 且首绘前完成——零可见闪帧。
    self.ame347_regular = YES;
    // ★ Task349（历史判例保留）：宽屏几何构建期即为真值 + 首轮无条件派发
    //   双保险（ame347_widthClassApplied 哨兵）。
    // ★ Task376：折叠态持久化回读 + 统一几何派发（宽窄 × 折叠 × 抽屉一次落位）
    self.ame376_paneCollapsed = [NSUserDefaults.standardUserDefaults boolForKey:@"ame376.paneCollapsed"];
    [self ame376_applyPaneGeometry:NO];
    // ★ Task379：头行置顶（滚动区/分隔线/底部栈之后加入层级，头行必须在最上，
    //   折叠开关钮永不被子覆盖）
    [self.paneWrap bringSubviewToFront:self.ame379_paneHeader];
    [self.view setNeedsLayout];
}

// ★ Task376：窗格几何统一派发（折叠态 × 宽窄态 × 抽屉开合一次落位）——
//   compact = 宽屏且折叠：窗格 64、内容区/大标题前导随宽、标题隐藏、
//   导航项转图标栏；宽屏未折叠 = 280 原样；窄屏 = 抽屉语义原样。
- (void)ame376_applyPaneGeometry:(BOOL)animated {
    BOOL ame376_compact = self.ame347_regular && self.ame376_paneCollapsed;
    CGFloat ame376_width = ame376_compact ? ZL2ShellPaneCompactWidth : ZL2ShellPaneWidth;
    self.ame376_paneWidth.constant = ame376_width;
    self.ame347_contentLeading.constant = self.ame347_regular ? ame376_width : 0.0;
    self.ame350_headerWrapLeading.constant = self.ame347_regular ? ame376_width : 0.0;
    self.paneTitle.hidden = ame376_compact;
    [self.navItems enumerateObjectsUsingBlock:^(ZL2ShellNavItem *item, NSUInteger idx, BOOL *stop) {
        [item ame_setCompact:ame376_compact];
    }];
    [self ame347_applyDrawerGeometryAnimated:animated];
}

// 宽窄态派发：宽屏常驻窗格 / 窄屏抽屉（viewDidLayoutSubviews 阈值检测驱动）
- (void)ame347_applyWidthClass:(BOOL)regular {
    self.ame347_regular = regular;
    // ★ Task376：几何统一收敛到 ame376_applyPaneGeometry（折叠态参与派发；
    //   跨阈值收窄时 compact 自动解除 = 窗格回 280 抽屉语义）
    if (!regular && self.ame347_drawerOpen) {
        self.ame347_drawerOpen = NO;   // 跨阈值收敛抽屉（旋转/分屏）
    }
    [self ame376_applyPaneGeometry:NO];
    [self ame_refreshNavShellStateAnimated:NO];
}

// 抽屉几何：常驻（宽屏）恒 open 几何；抽屉（窄屏）按开合态平移窗格 + 遮罩
- (void)ame347_applyDrawerGeometryAnimated:(BOOL)animated {
    BOOL ame347_paneShown = self.ame347_regular || self.ame347_drawerOpen;
    CGFloat ame347_target = ame347_paneShown ? 0.0 : -(ZL2ShellPaneWidth + 12.0);
    self.ame347_paneLeading.constant = ame347_target;
    self.paneWrap.layer.shadowOpacity = (!self.ame347_regular && self.ame347_drawerOpen) ? 0.25f : 0.0f;
    self.paneWrap.layer.shadowRadius = 16.0;
    self.paneWrap.layer.shadowOffset = CGSizeMake(8.0, 0.0);
    self.paneWrap.layer.shadowColor = [UIColor blackColor].CGColor;
    void (^ame347_apply)(void) = ^{
        self.dimOverlay.alpha = (!self.ame347_regular && self.ame347_drawerOpen) ? 1.0 : 0.0;
        self.dimOverlay.userInteractionEnabled = (!self.ame347_regular && self.ame347_drawerOpen);
        [self.view layoutIfNeeded];
    };
    if (animated && self.view.window) {
        [UIView animateWithDuration:ZL2ShellAnimateDuration animations:ame347_apply];
    } else {
        ame347_apply();
    }
}

- (void)ame_setDrawerOpen:(BOOL)open animated:(BOOL)animated {
    if (self.ame347_regular) return;   // 常驻窗格无抽屉语义
    if (self.ame347_drawerOpen == open) return;
    self.ame347_drawerOpen = open;
    [self ame347_applyDrawerGeometryAnimated:animated];
}

- (void)ame_dimTapped {
    [self ame_setDrawerOpen:NO animated:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.ame347_navMode) return;
    BOOL ame347_nowRegular = self.view.bounds.size.width >= ZL2ShellRegularMinWidth;
    // ★ Task349：首轮无条件派发（原"变化才派发"在 iPad 上永不点火——预置
    //   regular=YES 与实际宽类相同，见 ame_buildNavigationViewShell 内注释）。
    if (!self.ame347_widthClassApplied || ame347_nowRegular != self.ame347_regular) {
        self.ame347_widthClassApplied = YES;
        [self ame347_applyWidthClass:ame347_nowRegular];
    }
    // ★ Task350：首帧布局自证——窗格滚动区/主导航列 frame 与行数落日志，
    //   “窗格在、中间空”一类布局塌缩从此装机日志直接可判读（六项应在列时
    //   arranged=6、paneStack 高 ≈ 6×36+5×2=226pt；frame 高异常即约束面问题）。
    if (!self.ame350_layoutLogged) {
        self.ame350_layoutLogged = YES;
        NSLog(@"[Ame350] nav shell first layout -- paneScroll=%@ paneStack=%@ arranged=%lu (nav=%d regular=%d drawerOpen=%d)",
              NSStringFromCGRect(self.paneScroll.frame),
              NSStringFromCGRect(self.paneStack.frame),
              (unsigned long)self.paneStack.arrangedSubviews.count,
              self.ame347_navMode, self.ame347_regular, self.ame347_drawerOpen);
        // ★ Task379：窗格头行自证（开关钮可见性装机判读：钮 frame 应在窗格
        //   顶部可见带内；标题高度塌缩不再影响钮位）
        // ★ Task382：自证补 tglTrans（translates 应为 0）+ Task383 动作簇
        //   frame/钮数——装机日志从此对「钮零尺寸」「右上角簇缺失」两类
        //   回归一击定读，不再靠猜。
        NSLog(@"[Ame379] pane header -- header=%@ toggle=%@ tglTrans=%d title=%@ titleLen=%lu",
              NSStringFromCGRect(self.ame379_paneHeader.frame),
              NSStringFromCGRect(self.paneToggleButton.frame),
              (int)self.paneToggleButton.translatesAutoresizingMaskIntoConstraints,
              NSStringFromCGRect(self.paneTitle.frame),
              (unsigned long)self.paneTitle.text.length);
        NSLog(@"[Ame383] header actions -- stack=%@ btns=%lu",
              NSStringFromCGRect(self.ame383_headerActions.frame),
              (unsigned long)self.ame383_headerActions.arrangedSubviews.count);
    }
}

// 大标题内容区头态刷新（nav 骨架的 ame_refreshTopBarStateAnimated 等价物）：
// 窗格选中跟随 + 大标题 + 返回/汉堡互斥显隐 + 任务胶囊（viewWillAppear 补刷）
- (void)ame_refreshNavShellStateAnimated:(BOOL)animated {
    if (!self.isViewLoaded || self.currentIndex < 0) return;
    NSInteger ame347_index = self.currentIndex;

    UINavigationController *ame347_nav = [self ame_currentNav];
    BOOL ame347_backVisible = (ame347_nav.viewControllers.count > 1);

    [self.headerTitle setText:[self ame_titleForIndex:ame347_index]];

    void (^ame347_apply)(void) = ^{
        [self.navItems enumerateObjectsUsingBlock:^(ZL2ShellNavItem *item, NSUInteger idx, BOOL *stop) {
            [item ame_setSelected:(item.pageIndex >= 0 && item.pageIndex == ame347_index)];
        }];
        BOOL ame347_hamburgerVisible = !self.ame347_regular && !ame347_backVisible;
        // ★ Task349：大标题让位左钮槽位（汉堡/返回 32pt + 前导 8pt + 间距 6pt
        //   = 46pt；两钮互斥同槽）——原实现标题 leading 恒 16pt，窄屏与汉堡
        //   同位重叠（Task347 遗留几何缺陷）。
        self.ame347_headerLeading.constant =
            (ame347_hamburgerVisible || ame347_backVisible) ? 46.0 : 16.0;
        self.hamburgerButton.alpha = ame347_hamburgerVisible ? 1.0 : 0.0;
        self.hamburgerButton.hidden = !ame347_hamburgerVisible;
        self.navBackButton.alpha = ame347_backVisible ? 1.0 : 0.0;
        self.navBackButton.hidden = !ame347_backVisible;
    };
    if (animated && self.contentHeader.window) {
        [UIView animateWithDuration:ZL2ShellAnimateDuration animations:ame347_apply];
    } else {
        ame347_apply();
    }
}

#pragma mark - 通知

- (void)ame_showHome {
    [self showPageAtIndex:0];
}

// 7.0-UI-13：版本详情打开（userInfo[@"profile"] = 实例名；当前活动 nav 上 push）
- (void)ame_openVersionDetail:(NSNotification *)note {
    NSString *profile = [[note userInfo] objectForKey:@"profile"];
    if (![profile isKindOfClass:[NSString class]] || profile.length == 0) return;
    UINavigationController *nav = [self ame_currentNav];
    if (!nav) return;
    ZL2VersionDetailViewController *vc =
        [[ZL2VersionDetailViewController alloc] initWithProfileName:profile];
    [nav pushViewController:vc animated:YES];
}

- (void)ame_showAccount {
    [self showPageAtIndex:3];
}

- (void)ame_onNavigate:(NSNotification *)note {
    NSInteger index = [note.userInfo[@"index"] integerValue];
    [self showPageAtIndex:index];
}

// manager 投递线程不定（addObserver:selector: 同步回调），统一回主线程刷胶囊
- (void)ame_taskManagerDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame_refreshTaskPill];
    });
}

// 仅当前子 nav 的栈变化参与顶栏刷新（跨页导航不误触）
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (navigationController != [self ame_currentNav]) return;
    [self ame_refreshTopBarStateAnimated:animated];
}

#pragma mark - 文件浏览器（顶栏文件夹钮 = ZL2 OpenFileManager 对应）

- (void)ame_openFileManagerSheet {
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *gameDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    UINavigationController *nav = [FolderBrowserViewController wrappedControllerForPath:gameDir];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UIViewController *presenter = self.presentedViewController ?: self;
    [presenter presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 页面切换

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index > 6) return; // Task318：6 = AI 助手（顶栏第 5 项）
    if (index == self.currentIndex) {
        [self ame_refreshTopBarStateAnimated:NO];  // 幂等自愈
        return;
    }

    UIViewController *next = [self ame_childForIndex:index];
    UIViewController *prev = [self ame_currentChild];

    [self ame_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.container
                          duration:ZL2ShellAnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.currentIndex = index;
    [self ame_refreshTopBarStateAnimated:YES];
}

#pragma mark - 顶栏态（左簇显隐 / 返回钮 / RailItem 选中 / 标题）

- (NSString *)ame_titleForIndex:(NSInteger)index {
    if (index == 0) {
        // 主页标题 = ZL2 LAUNCHER_IDENTIFIER（"ZalithLauncher"，真机截图实证）
        return @"ZalithLauncher";
    }
    // 功能页文案（ZL2 顶栏标题映射表，7.0-UI-14 对齐）
    switch (index) {
        case 1: return localize(@"ame369.shell.tab.downloads", @"下载");
        case 2: return localize(@"ame369.shell.tab.versions", @"版本");
        case 3: return localize(@"ame369.shell.tab.accounts", @"账户");
        case 4: return localize(@"ame369.shell.tab.settings", @"设置");
        case 5: return localize(@"ame369.shell.tab.terracotta", @"Terracotta | 陶瓦联机");
        default: return @"";
    }
}


- (void)ame_refreshTopBarStateAnimated:(BOOL)animated {
    // ★ Task347：nav 骨架走等价刷新（窗格选中/大标题/返回汉堡互斥）
    if (self.ame347_navMode) {
        [self ame_refreshNavShellStateAnimated:animated];
        return;
    }
    // ★ Task378：topbar 骨架退役——bare 壳无顶栏态可刷（标题/左簇/RailItem
    //   选中随顶栏整体移除；子页栈深与标题由各子页 UINavigationController
    //   自带导航栏呈现，7.0-UI-8 既有约定不变）
}

- (void)ame_popCurrentIfPossible {
    UINavigationController *nav = [self ame_currentNav];
    if (nav && nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    }
}

#pragma mark - 任务胶囊

- (void)ame_refreshTaskPill {
    if (!self.taskPill) return;   // ★ Task378：bare 壳无顶栏 = 无任务胶囊（nav 骨架专属）
    if (!self.isViewLoaded) return;

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    BOOL active = [manager hasActiveTasks];

    // 活动任务数（Downloading + Pending，ZL2DownloadViewController 同口径）+
    // 首个活动任务 progress（0~1；负值=未知 → 截 0）
    NSInteger count = 0;
    double progress = 0.0;
    if (active) {
        count = (NSInteger)[manager tasksWithStates:@[
            @(DownloadTaskStateDownloading),
            @(DownloadTaskStatePending),
        ]].count;
        for (DownloadTaskItem *item in [manager allTasks]) {
            if (item.state == DownloadTaskStateDownloading ||
                item.state == DownloadTaskStatePending) {
                progress = item.progress;
                break;
            }
        }
        if (progress < 0.0) progress = 0.0;
    }
    [self.taskPill ame_setProgress:progress count:count];

    BOOL visibleNow = !self.taskPill.hidden;
    if (visibleNow == active) return;  // 显隐未变：内容已刷新到位

    void (^apply)(void) = ^{
        self.taskPill.hidden = !active;
        self.taskPill.alpha = active ? 1.0 : 0.0;
        // ★ Task347：动画上下文按骨架择一（topbar / nav 内容区头）
        (self.topBar ?: self.contentHeader).layoutIfNeeded;
    };
    if ((self.topBar ?: self.contentHeader).window) {
        [UIView animateWithDuration:ZL2ShellAnimateDuration animations:apply];
    } else {
        apply();
    }
}

- (void)ame_openTaskProgress {
    // ZL2Home/ZL2Download 同款用法：遍历 allTasks 取第一个活动任务的 taskId
    // → 统一进度页（presentForTaskId: 自带同屏去重/替换）
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSString *taskId = nil;
    for (DownloadTaskItem *item in [manager allTasks]) {
        if (item.state == DownloadTaskStateDownloading ||
            item.state == DownloadTaskStatePending) {
            taskId = item.taskId;
            break;
        }
    }
    if (taskId.length == 0) {
        taskId = [manager allTasks].firstObject.taskId;  // 兜底（hasActiveTasks 恒真时不可达）
    }
    if (taskId.length > 0) {
        [PLTaskProgressViewController presentForTaskId:taskId];
    }
}

#pragma mark - Child 管理（懒建缓存 + 首显 attach，7.0-UI-8/9 机制平移不变）

- (UIViewController *)ame_currentChild {
    if (self.currentIndex < 0) return nil;
    return self.childCache[@(self.currentIndex)];
}

- (UINavigationController *)ame_currentNav {
    if (self.currentIndex <= 0) return nil;  // 主页不包 nav
    UIViewController *child = self.childCache[@(self.currentIndex)];
    if ([child isKindOfClass:[UINavigationController class]]) {
        return (UINavigationController *)child;
    }
    return nil;
}

- (void)ame_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.container addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.container.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

- (UIViewController *)ame_childForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *vc;
    switch (index) {
        case 0: {
            // 主页：ZL2 新写，单页无 push 需求（切页走通知契约），不包 nav
            vc = [[ZL2HomeViewController alloc] init];
            break;
        }
        case 1: {
            ZL2DownloadViewController *download = [[ZL2DownloadViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:download];
            break;
        }
        case 2: {
            ZL2VersionsViewController *versions = [[ZL2VersionsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:versions];
            break;
        }
        case 3: {
            ZL2AccountsViewController *accounts = [[ZL2AccountsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:accounts];
            break;
        }
        case 4: {
            ZL2SettingsViewController *settings = [[ZL2SettingsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:settings];
            break;
        }
        case 5: {
            // 多人联机（ZL2 Multiplayer 入口；legacy FCL 式联机域承接）
            MultiplayerViewController *multiplayer =
                [[MultiplayerViewController alloc] initWithMode:MultiplayerVCModeLauncher];
            vc = [[UINavigationController alloc] initWithRootViewController:multiplayer];
            break;
        }
        case 6: {
            // AI 助手（Task318：7.0-UI-8 旧壳退役后入口恢复；1:1 旧壳 showAIPage
            //   判例 LauncherRootViewController L648-655：lastActiveSession + 包
            //   nav + prefersLargeTitles=NO；未配 Provider 时空态自带「去配置」引导）
            AIViewController *ai = [[AIViewController alloc]
                initWithSession:[[AiSessionStore sharedStore] lastActiveSession]];
            UINavigationController *aiNav =
                [[UINavigationController alloc] initWithRootViewController:ai];
            aiNav.navigationBar.prefersLargeTitles = NO;
            vc = aiNav;
            break;
        }
        default:
            return nil;
    }
    // 顶栏返回钮/标题跟随子 nav 栈深：UINavigationControllerDelegate 公开 API
    //（DidShow 通知常量在 SDK 非公开——CI 实证 undeclared，改走 delegate）
    if ([vc isKindOfClass:[UINavigationController class]]) {
        ((UINavigationController *)vc).delegate = self;
    }
    self.childCache[@(index)] = vc;
    return vc;
}

// .h 契约零改动保留（harness/测试断言）：NavigationRail 已于 7.0-UI-10-b 退役
// 为顶栏，数值冻结为 ZL2RailView 同款（iPhone 88 / iPad 104）
+ (CGFloat)railWidthForSizeClass:(UIUserInterfaceIdiom)idiom {
    return (idiom == UIUserInterfaceIdiomPad) ? 104.0 : 88.0;
}

@end
