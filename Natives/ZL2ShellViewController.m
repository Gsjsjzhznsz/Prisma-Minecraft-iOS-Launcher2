//
// ZL2ShellViewController.m — ZL2 真形态顶栏壳实现（7.0-UI-10-b）
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
//   · iOS 侧 RailItem×4（ZL2 顶栏无版本/账户直达，iOS 保留五页全量导航）：
//     版本(2) / 下载(1) / 账户(3) / 设置(4)，与 ZL2 右侧组同序排列。
//
// 五页 index 映射（.h 契约零改动）：
//   0 主页 ZL2HomeViewController（不包 nav；顶栏标题 = CFBundleDisplayName）
//   1 下载 ZL2DownloadViewController（UINavigationController 包）
//   2 版本 ZL2VersionsViewController（UINavigationController 包）
//   3 账户 ZL2AccountsViewController（UINavigationController 包）
//   4 设置 ZL2SettingsViewController（UINavigationController 包）
//
// 通知契约（消费方，7.0-UI-8 三件原样保留 + 顶栏新增两件）：
//   @"ShowHomePage"                              → 切主页（旧启动链）
//   @"ShowAccountManager"                        → 切账户页（FCL 风格）
//   ZL2ShellNavigateNotification                 → userInfo[@"index"] 切页（0...4
//                                                  越界忽略）
//   DownloadTaskManagerDidUpdateTaskNotification → 任务胶囊刷新（manager 全部
//     变更均经 postUpdateForTask 派发；防御性回主线程后刷 UI）+ viewWillAppear
//     补刷
//   UINavigationControllerDidShowViewControllerNotification → 返回钮显隐与
//     「页名 - 子页名」标题跟随当前 nav 栈深刷新（object 非当前子 nav 时忽略）
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
#import "ZL2HomeViewController.h"
#import "ZL2DownloadViewController.h"
#import "ZL2VersionsViewController.h"
#import "ZL2AccountsViewController.h"
#import "ZL2SettingsViewController.h"
#import "DownloadTaskManager.h"           // manager 单例 + DownloadTaskItem + 更新通知常量
#import "PLTaskProgressViewController.h"  // 统一进度页（胶囊点开）

NSString * const ZL2ShellNavigateNotification = @"ZL2ShellNavigate";

#pragma mark - 几何/动画常量（ZL2 TopBar spec 对应）

static const CGFloat ZL2ShellBarContentHeight = 40.0;   // TopBar 40.dp
static const CGFloat ZL2ShellBarEdgeInset = 12.0;       // 左右 12dp 边距
static const CGFloat ZL2ShellClusterButtonSize = 32.0;  // 返回/主页钮 32×32
static const CGFloat ZL2ShellRailItemHeight = 40.0;     // RailItem 高（顶栏全高）
static const CGFloat ZL2ShellRailItemIconSize = 22.0;   // 图标 22pt
static const CGFloat ZL2ShellRailItemPadH = 10.0;       // RailItem 横向内边距
static const CGFloat ZL2ShellRailItemTextGap = 6.0;     // TopBarRailItem Spacer(6.dp)
static const CGFloat ZL2ShellPillWidth = 120.0;         // 任务胶囊宽 120dp
static const CGFloat ZL2ShellPillHeight = 28.0;         // 任务胶囊高
static const CGFloat ZL2ShellAnimateDuration = 0.18;    // 全壳动画时长

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

#pragma mark - 顶栏 RailItem（TextRailItem 等价：图标恒显 + 选中文字宽度展开）

@interface ZL2ShellRailItem : ZL2ShellTapControl
@property(nonatomic, assign, readonly) NSInteger pageIndex;
- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbol
                     fallback:(NSString *)fallback
                    pageIndex:(NSInteger)pageIndex;
// 纯状态应用（着色 + 宽度/透明度目标值）；动画由壳侧统一包裹
- (void)ame_setSelected:(BOOL)selected;
@end

@interface ZL2ShellRailItem ()
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) NSLayoutConstraint *labelWidthConstraint;  // 文字宽 0 ↔ 实宽
@property(nonatomic, strong) NSLayoutConstraint *itemWidthConstraint;   // 整枚宽 42 ↔ 48+文字
@property(nonatomic, assign) CGFloat textWidth;                         // 选中态文字实宽
@property(nonatomic, assign) CGFloat collapsedWidth;                    // 未选整枚宽
@property(nonatomic, assign) CGFloat expandedWidth;                     // 选中整枚宽
@end

@implementation ZL2ShellRailItem

- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbol
                     fallback:(NSString *)fallback
                    pageIndex:(NSInteger)pageIndex {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _pageIndex = pageIndex;

        UIImage *image = ZL2ShellSystemImage(symbol, fallback);
        if (image) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _iconView = [[UIImageView alloc] initWithImage:image];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];

        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [ZL2Theme fontLabelMedium];
        _label.text = title;
        _label.numberOfLines = 1;
        _label.clipsToBounds = YES;  // 未选宽 0 时文字裁剪（AnimatedVisibility 等价裁剪面）
        _label.userInteractionEnabled = NO;
        _label.alpha = 0.0;
        [self addSubview:_label];

        // 几何：单一定宽来源 = itemWidthConstraint；label 只从 icon 尾随 +6
        // 定位并按宽度约束展开/收起（无 trailing 链，任何宽度组合零冲突）
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:ZL2ShellRailItemPadH],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:ZL2ShellRailItemIconSize],
            [_iconView.heightAnchor constraintEqualToConstant:ZL2ShellRailItemIconSize],

            [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:ZL2ShellRailItemTextGap],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor],

            [self.heightAnchor constraintEqualToConstant:ZL2ShellRailItemHeight],
        ]];

        _textWidth = ceil([_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
        _collapsedWidth = ZL2ShellRailItemPadH + ZL2ShellRailItemIconSize + ZL2ShellRailItemPadH;
        _expandedWidth = ZL2ShellRailItemPadH + ZL2ShellRailItemIconSize
                       + ZL2ShellRailItemTextGap + _textWidth + ZL2ShellRailItemPadH;

        _labelWidthConstraint = [_label.widthAnchor constraintEqualToConstant:0.0];
        _labelWidthConstraint.active = YES;
        _itemWidthConstraint = [self.widthAnchor constraintEqualToConstant:_collapsedWidth];
        _itemWidthConstraint.active = YES;

        _iconView.tintColor = [ZL2Theme onSurfaceVariant];
        _label.textColor = [ZL2Theme onSurfaceVariant];

        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)ame_setSelected:(BOOL)selected {
    UIColor *tint = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    self.labelWidthConstraint.constant = selected ? self.textWidth : 0.0;
    self.itemWidthConstraint.constant = selected ? self.expandedWidth : self.collapsedWidth;
    self.label.alpha = selected ? 1.0 : 0.0;
    self.iconView.tintColor = tint;
    self.label.textColor = tint;
    self.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                        : UIAccessibilityTraitButton;
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
    self.accessibilityLabel = [NSString stringWithFormat:@"下载任务进行中，共 %ld 个", (long)count];
}

@end

#pragma mark - 壳本体

@interface ZL2ShellViewController ()
@property(nonatomic, strong) UIView *topBar;                          // safeArea 顶延伸 + 40pt 内容带
@property(nonatomic, strong) UIStackView *barRow;                     // [左簇 | 标题 | 右簇]
@property(nonatomic, strong) UIStackView *leftCluster;                // [返回 | 主页]
@property(nonatomic, strong) ZL2ShellIconButton *backButton;
@property(nonatomic, strong) ZL2ShellIconButton *homeButton;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIStackView *rightCluster;               // [胶囊 | RailItem×4]
@property(nonatomic, strong) ZL2ShellTaskPill *taskPill;
@property(nonatomic, strong) NSArray<ZL2ShellRailItem *> *railItems;  // ZL2 右侧组序：版本/下载/账户/设置
@property(nonatomic, strong) UIView *container;                       // 子页挂载区
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@property(nonatomic, assign) NSInteger currentIndex;
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

    [self ame_buildTopBar];
    [self ame_buildContainer];

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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_taskManagerDidChange:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_navDidShow:)
                                                 name:UINavigationControllerDidShowViewControllerNotification
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

#pragma mark - 顶栏构建（ZL2 TopBar 等价）

- (void)ame_buildTopBar {
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    // 顶栏与内容同底色（ZL2 MainScreen 单一 Surface backgroundColor）
    self.topBar.backgroundColor = [ZL2Theme surface];
    [self.view addSubview:self.topBar];

    self.barRow = [[UIStackView alloc] init];
    self.barRow.axis = UILayoutConstraintAxisHorizontal;
    self.barRow.alignment = UIStackViewAlignmentCenter;
    self.barRow.distribution = UIStackViewDistributionFill;
    self.barRow.spacing = 16.0;  // 标题 start = 左簇 end + 16dp
    // 右簇 end margin 12dp（前导边距由左簇自带，塌缩时标题回到 16pt 位）
    self.barRow.layoutMargins = UIEdgeInsetsMake(0.0, 0.0, 0.0, ZL2ShellBarEdgeInset);
    self.barRow.isLayoutMarginsRelativeArrangement = YES;
    self.barRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.barRow];

    // 左簇：AnimatedVisibility(!inLauncherScreen) + 12dp 前导（ZL2 Spacer(12.dp)）
    self.leftCluster = [[UIStackView alloc] init];
    self.leftCluster.axis = UILayoutConstraintAxisHorizontal;
    self.leftCluster.alignment = UIStackViewAlignmentCenter;
    self.leftCluster.spacing = 4.0;  // 返回/主页间距 4
    self.leftCluster.layoutMargins = UIEdgeInsetsMake(0.0, ZL2ShellBarEdgeInset, 0.0, 0.0);
    self.leftCluster.isLayoutMarginsRelativeArrangement = YES;
    self.leftCluster.translatesAutoresizingMaskIntoConstraints = NO;
    self.leftCluster.hidden = YES;   // 主页初始态（showPageAtIndex:0 统一同步）
    self.leftCluster.alpha = 0.0;

    self.backButton = [[ZL2ShellIconButton alloc] initWithSymbol:@"chevron.left" fallback:nil];
    self.backButton.accessibilityLabel = @"返回";
    __weak typeof(self) weakSelf = self;
    self.backButton.ame_action = ^{
        [weakSelf ame_popCurrentIfPossible];
    };
    [self.leftCluster addArrangedSubview:self.backButton];

    self.homeButton = [[ZL2ShellIconButton alloc] initWithSymbol:@"house.fill" fallback:nil];
    self.homeButton.accessibilityLabel = @"主页";
    self.homeButton.ame_action = ^{
        [weakSelf showPageAtIndex:0];
    };
    [self.leftCluster addArrangedSubview:self.homeButton];

    [self.barRow addArrangedSubview:self.leftCluster];

    // 标题：titleMedium 左对齐；Fill 分布下唯一低 hug 项 → 拉伸占中段，
    // 右簇恒钉右缘（ZL2 ConstraintLayout 同构）
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [ZL2Theme fontTitleMedium];
    self.titleLabel.textColor = [ZL2Theme onSurface];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.titleLabel setContentHuggingPriority:(UILayoutPriority)249.0
                                       forAxis:UILayoutConstraintAxisHorizontal];
    [self.titleLabel setContentCompressionResistancePriority:(UILayoutPriority)749.0
                                                     forAxis:UILayoutConstraintAxisHorizontal];
    [self.barRow addArrangedSubview:self.titleLabel];

    // 右簇：trailing 12dp（barRow margin）+ 间距 8dp
    self.rightCluster = [[UIStackView alloc] init];
    self.rightCluster.axis = UILayoutConstraintAxisHorizontal;
    self.rightCluster.alignment = UIStackViewAlignmentCenter;
    self.rightCluster.spacing = 8.0;
    self.rightCluster.translatesAutoresizingMaskIntoConstraints = NO;
    [self.barRow addArrangedSubview:self.rightCluster];

    // a) 任务胶囊（AnimatedVisibility：任务运行且未展开时——iOS 无任务菜单
    //    展开态，仅按 hasActiveTasks 显隐）
    self.taskPill = [[ZL2ShellTaskPill alloc] init];
    self.taskPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.taskPill.ame_action = ^{
        [weakSelf ame_openTaskProgress];
    };
    [self.rightCluster addArrangedSubview:self.taskPill];

    // b) RailItem×4（版本/下载/账户/设置，ZL2 右侧组序；📁文件与联机 RailItem
    //    待文件管理器/联机功能域落地后补位）
    NSArray<NSString *> *titles = @[@"版本", @"下载", @"账户", @"设置"];
    NSArray<NSString *> *symbols = @[@"square.grid.2x2.fill",
                                     @"arrow.down.circle.fill",
                                     @"person.crop.circle.fill",
                                     @"gearshape.fill"];
    NSArray<NSString *> *fallbacks = @[@"square.grid.2x2", @"arrow.down", @"", @"gear"];
    NSArray<NSNumber *> *pageIndexNumbers = @[@2, @1, @3, @4];
    NSMutableArray<ZL2ShellRailItem *> *items = [NSMutableArray array];
    [titles enumerateObjectsUsingBlock:^(NSString *itemTitle, NSUInteger idx, BOOL *stop) {
        NSString *fallback = fallbacks[idx];
        ZL2ShellRailItem *item = [[ZL2ShellRailItem alloc]
                                     initWithTitle:itemTitle
                                             symbol:symbols[idx]
                                           fallback:(fallback.length > 0 ? fallback : nil)
                                         pageIndex:pageIndexNumbers[idx].integerValue];
        NSInteger target = pageIndexNumbers[idx].integerValue;
        item.ame_action = ^{
            [weakSelf showPageAtIndex:target];
        };
        [self.rightCluster addArrangedSubview:item];
        [items addObject:item];
    }];
    self.railItems = [items copy];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        // safeArea 顶部延伸：顶栏底 = safeArea 顶 + 40（iPhone 竖放补状态栏区
        // 域底色；iPad/横屏 safeTop=0 即 40pt 平顶）
        [self.topBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                                constant:ZL2ShellBarContentHeight],

        [self.barRow.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [self.barRow.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
        [self.barRow.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.barRow.heightAnchor constraintEqualToConstant:ZL2ShellBarContentHeight],
    ]];
}

- (void)ame_buildContainer {
    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    self.container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.container];

    [NSLayoutConstraint activateConstraints:@[
        [self.container.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - 通知

- (void)ame_showHome {
    [self showPageAtIndex:0];
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
- (void)ame_navDidShow:(NSNotification *)note {
    if (note.object != [self ame_currentNav]) return;
    [self ame_refreshTopBarStateAnimated:YES];
}

#pragma mark - 页面切换

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index > 4) return;
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
        // 主页标题 = CFBundleDisplayName（兜底 @"Prisma Launcher"，对应 ZL2
        // LAUNCHER_IDENTIFIER 位）
        NSString *name = (NSString *)[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        return name.length > 0 ? name : @"Prisma Launcher";
    }
    // 功能页文案 = ZL2RailView 同款中文（主页/下载/版本/账户/设置）
    switch (index) {
        case 1: return @"下载";
        case 2: return @"版本";
        case 3: return @"账户";
        case 4: return @"设置";
        default: return @"";
    }
}

- (void)ame_setTitleText:(NSString *)title {
    NSString *next = title ?: @"";
    if ([self.titleLabel.text isEqualToString:next]) return;
    if (self.titleLabel.window) {
        // Crossfade 等价（MainScreen.kt title 位）
        [UIView transitionWithView:self.titleLabel
                          duration:ZL2ShellAnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ self.titleLabel.text = next; }
                        completion:nil];
    } else {
        self.titleLabel.text = next;
    }
}

- (void)ame_refreshTopBarStateAnimated:(BOOL)animated {
    if (!self.isViewLoaded || self.currentIndex < 0) return;
    NSInteger index = self.currentIndex;

    UINavigationController *nav = [self ame_currentNav];
    BOOL clusterVisible = (index != 0);                  // 左簇仅非主页显示
    BOOL backVisible = (nav.viewControllers.count > 1);  // 可 pop 才有返回钮

    NSString *title = [self ame_titleForIndex:index];
    if (nav.viewControllers.count > 1) {
        // 子页 push 态「页名 - 子页名」（MainScreen.kt L358-362 同构）
        NSString *childTitle = nav.topViewController.title;
        if (childTitle.length > 0) {
            title = [NSString stringWithFormat:@"%@ - %@", title, childTitle];
        }
    }
    [self ame_setTitleText:title];

    // AnimatedVisibility 等价：hidden 塌缩（UIStackView）+ alpha + 宽度约束，
    // 单一动画上下文统一 0.18s
    void (^apply)(void) = ^{
        [self.railItems enumerateObjectsUsingBlock:^(ZL2ShellRailItem *item, NSUInteger idx, BOOL *stop) {
            [item ame_setSelected:(item.pageIndex == index)];
        }];
        self.leftCluster.alpha = clusterVisible ? 1.0 : 0.0;
        self.leftCluster.hidden = !clusterVisible;
        self.backButton.alpha = backVisible ? 1.0 : 0.0;
        self.backButton.hidden = !backVisible;
        [self.topBar layoutIfNeeded];
    };
    if (animated && self.topBar.window) {
        [UIView animateWithDuration:ZL2ShellAnimateDuration animations:apply];
    } else {
        apply();
    }
}

- (void)ame_popCurrentIfPossible {
    UINavigationController *nav = [self ame_currentNav];
    if (nav && nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    }
}

#pragma mark - 任务胶囊

- (void)ame_refreshTaskPill {
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
        [self.topBar layoutIfNeeded];
    };
    if (self.topBar.window) {
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
        default:
            return nil;
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
