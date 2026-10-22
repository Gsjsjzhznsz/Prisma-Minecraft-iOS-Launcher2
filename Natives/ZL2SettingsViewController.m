//
// ZL2SettingsViewController.m — ZL2 设置「左轨八屏 + 右内容」枢纽（7.0-UI-13-S）
//
// 对标：ZalithLauncher2 ui/screens/content/SettingsScreen.kt——左轨 8 项分
// 3 组（组间分隔线）+ 右侧内容区（子页切换非 push）。8 个子页 VC 全部
// 落在 ZL2SettingPages（ZL2SettingPage 基类 + 八个子类），行卡组件落在
// ZL2SettingCards（SettingsCard 连体拼接组）。
//
// 左轨规格（spec）：
//   · 宽 200pt（iPad）/ 160pt（iPhone 横屏）；
//   · 8 项：渲染器(Renderer)/游戏(Game)/控制(Control)/手柄(Gamepad)/
//     启动器(Launcher)｜分隔线｜Java 管理/控制管理｜分隔线｜关于；
//   · 轨项 = 32pt 图标胶囊（选中 primaryContainer 底 + onPrimaryContainer
//     图标）+ 12pt 标签——ZL2RailView.m 同款视觉（绘制模式平移）；
//   · 分组分隔线 = 0.4 alpha onSurface 细线，宽 60%。
// 右侧内容区：子 VC 切换（addChildViewController + 四边钉入 + 0.18s
//   crossDissolve）——ZL2ShellViewController.m 的页面切换手法平移
//   （ame_attachChildIfNeeded / showPageAtIndex 同构）。
//
// 壳契约不变：本页仍由 ZL2Shell 包 UINavigationController 后做 page 4
//（ZL2ShellViewController ame_childForIndex case 4，零改动）；根页
// viewWillAppear 隐藏系统栏 / viewWillDisappear 恢复（7.0-UI-9-d 原样
// 保留——push 旧子页时系统栏显示，返回本页再隐藏）。
//
// 通知面：无监听（子页各自管理写键后的刷新通知；枢纽纯容器，dealloc
// 无需清理）。
//
// 红线遵守：iOS 14.0+；SF 符号全带旧名 fallback；颜色/字体/圆角一律
// ZL2Theme 动态令牌（无 traitCollection 分支）；全部新建视图
// translatesAutoresizingMaskIntoConstraints = NO；轨项身份 = 数组
// 下标（UIControl.tag 仅作下标载荷，不经 viewWithTag: 查找）；轨文案
// 硬编码中文与 ZL2HomeViewController 同判例（7.0-UI-8 待办③）。
//

#import "ZL2SettingsViewController.h"
#import "ZL2Theme.h"
#import "ZL2SettingPages.h"

#pragma mark - 常量

// 左轨宽（spec：iPad 200 / iPhone 横屏 160）；轨项高与图标胶囊沿用
// ZL2RailView 规格（56 项高 / 32 胶囊 / 24 图标 / 12 标签）
static const CGFloat ame_hubRailWidthPad = 200.0;
static const CGFloat ame_hubRailWidthPhone = 160.0;
static const CGFloat ame_hubRailItemHeight = 56.0;
static const CGFloat ame_hubAnimateDuration = 0.18;

// SF 符号取图兜底（ZL2Home/ZL2Rail 同款判例：符号名异常时降级旧名而非空白）
static UIImage *ame_hubSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - 轨项（ZL2RailItem 视觉平移：胶囊 + 标签，选中态换色）

@interface ZL2SettingsRailItem : UIControl
- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbolName
                     fallback:(nullable NSString *)fallbackName;
- (void)ame_setSelected:(BOOL)selected;
@end

@interface ZL2SettingsRailItem ()
@property (nonatomic, strong) UIView *iconBg;      // 32×32 图标胶囊
@property (nonatomic, strong) UIImageView *icon;   // 24×24 模板
@property (nonatomic, strong) UILabel *label;      // 12pt（fontLabelMedium 档）
@property (nonatomic, strong) NSLayoutConstraint *itemWidth;
@end

@implementation ZL2SettingsRailItem

- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbolName
                     fallback:(NSString *)fallbackName {
    self = [super initWithFrame:CGRectZero];
    if (!self) return self;

    _iconBg = [[UIView alloc] init];
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBg.layer.cornerRadius = 16.0;   // 32/2 = M3 full pill
    _iconBg.userInteractionEnabled = NO;
    [self addSubview:_iconBg];

    UIImage *image = ame_hubSystemImage(symbolName, fallbackName);
    _icon = [[UIImageView alloc] initWithImage:
        [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _icon.tintColor = [ZL2Theme onSurfaceVariant];
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _icon.userInteractionEnabled = NO;
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    [_iconBg addSubview:_icon];

    _label = [[UILabel alloc] init];
    _label.text = title;
    _label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    [NSLayoutConstraint activateConstraints:@[
        [_iconBg.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconBg.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
        [_iconBg.widthAnchor constraintEqualToConstant:32.0],
        [_iconBg.heightAnchor constraintEqualToConstant:32.0],

        [_icon.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:24.0],
        [_icon.heightAnchor constraintEqualToConstant:24.0],

        [_label.topAnchor constraintEqualToAnchor:_iconBg.bottomAnchor constant:2.0],
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2.0],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2.0],
        [_label.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-2.0],
    ]];
    [self.heightAnchor constraintEqualToConstant:ame_hubRailItemHeight].active = YES;
    _itemWidth = [self.widthAnchor constraintEqualToConstant:ame_hubRailWidthPhone - 12.0];
    _itemWidth.active = YES;
    return self;
}

// ZL2RailItem ame_setSelected 同款两态换色（dynamicProvider 已随深浅，
// 此处仅按选中态重涂）
- (void)ame_setSelected:(BOOL)selected {
    UIColor *bg = selected ? [ZL2Theme primaryContainer] : [UIColor clearColor];
    UIColor *iconTint = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    UIColor *labelTint = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    self.iconBg.backgroundColor = bg;
    self.icon.tintColor = iconTint;
    self.label.textColor = labelTint;
    self.accessibilityTraits = selected
        ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
        : UIAccessibilityTraitButton;
}

@end

#pragma mark - 枢纽本体

@interface ZL2SettingsViewController ()
// 左轨
@property (nonatomic, strong) UIScrollView *railScrollView;
@property (nonatomic, strong) UIStackView *railStack;
@property (nonatomic, strong) NSMutableArray<ZL2SettingsRailItem *> *railItems;
@property (nonatomic, strong) NSMutableArray<UIView *> *railSeparators;
@property (nonatomic, strong) NSLayoutConstraint *railWidthConstraint;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *separatorWidthConstraints;
// 右内容区
@property (nonatomic, strong) UIView *contentContainer;
// 子页状态
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@end

@implementation ZL2SettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    self.childCache = [NSMutableDictionary dictionary];
    self.railItems = [NSMutableArray array];
    self.railSeparators = [NSMutableArray array];
    self.separatorWidthConstraints = [NSMutableArray array];
    self.currentIndex = -1;

    [self buildViews];
    [self ame_showPageAtIndex:0];   // 首屏：渲染器（无过渡，首显直挂）
}

// 根页导航栏约定：本页隐藏系统栏；push 子页 / present 全屏页时由
// viewWillDisappear 恢复，返回本页时 viewWillAppear 再隐藏（系统栏在
// push 时显示，子页标题/返回手势依赖它）
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

// 通知/KVO 均未注册，无需 dealloc 清理

// 旋转：左轨宽度随 idiom 口径刷新（iPad 200 / iPhone 160），分隔线宽随轨宽
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self ame_applyRailMetrics];
    } completion:nil];
}

#pragma mark - Layout

- (void)buildViews {
    // —— 左轨（竖向可滚：小屏 iPhone 横放时 8 项 + 分隔线 ≈ 460pt 可能超视口）——
    _railScrollView = [[UIScrollView alloc] init];
    _railScrollView.backgroundColor = [ZL2Theme surface];
    _railScrollView.alwaysBounceVertical = YES;
    _railScrollView.showsVerticalScrollIndicator = NO;
    _railScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_railScrollView];

    // 右缘 1pt 分隔线（outlineVariant——与主壳 NavigationRail 同语言）
    UIView *railEdge = [[UIView alloc] init];
    railEdge.backgroundColor = [ZL2Theme outlineVariant];
    railEdge.userInteractionEnabled = NO;
    railEdge.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:railEdge];

    _railStack = [[UIStackView alloc] init];
    _railStack.axis = UILayoutConstraintAxisVertical;
    _railStack.alignment = UIStackViewAlignmentCenter;
    _railStack.spacing = 0.0;
    _railStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_railScrollView addSubview:_railStack];

    // 7.0-UI-13-r2：宽度约束先建后入数组（赋值提出数组字面量）
    _railWidthConstraint =
        [_railScrollView.widthAnchor constraintEqualToConstant:[self ame_railWidth]];
    [NSLayoutConstraint activateConstraints:@[
        [_railScrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_railScrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_railScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        // 7.0-UI-13-r2：裸 ivar 入数组不需括号（[ivar] = 空消息表达式语法错）
        _railWidthConstraint,

        [railEdge.trailingAnchor constraintEqualToAnchor:_railScrollView.trailingAnchor],
        [railEdge.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [railEdge.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [railEdge.leadingAnchor constraintEqualToAnchor:_railScrollView.trailingAnchor],
        [railEdge.widthAnchor constraintEqualToConstant:1.0],

        [_railStack.topAnchor constraintEqualToAnchor:_railScrollView.contentLayoutGuide.topAnchor constant:8.0],
        [_railStack.bottomAnchor constraintEqualToAnchor:_railScrollView.contentLayoutGuide.bottomAnchor constant:8.0],
        [_railStack.centerXAnchor constraintEqualToAnchor:_railScrollView.contentLayoutGuide.centerXAnchor],
        [_railStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_railScrollView.contentLayoutGuide.leadingAnchor constant:4.0],
        [_railStack.trailingAnchor constraintLessThanOrEqualToAnchor:_railScrollView.contentLayoutGuide.trailingAnchor constant:-4.0],
    ]];

    // —— 轨项装配（8 项 + 2 条组分隔线；组间 custom spacing 6 呼吸）——
    //   0 渲染器 / 1 游戏 / 2 控制 / 3 手柄 / 4 启动器 ｜ 5 Java 管理 /
    //   6 控制管理 ｜ 7 关于
    NSArray<NSArray<NSString *> *> *defs = @[
        @[@"渲染器",   @"cpu",                       @"gearshape"],
        @[@"游戏",     @"gamecontroller",            @""],
        @[@"控制",     @"hand.tap",                  @"hand.point.up.left"],
        @[@"手柄",     @"gamecontroller.fill",       @"gamecontroller"],
        @[@"启动器",   @"gearshape.fill",            @"gear"],
        @[@"Java 管理", @"wrench.and.screwdriver",   @"wrench"],
        @[@"控制管理", @"square.on.square",          @"square.split.2x1"],
        @[@"关于",     @"info.circle",               @""],
    ];
    for (NSUInteger i = 0; i < defs.count; i++) {
        ZL2SettingsRailItem *item = [[ZL2SettingsRailItem alloc]
            initWithTitle:defs[i][0] symbol:defs[i][1] fallback:defs[i][2]];
        item.tag = (NSInteger)i;   // 下标载荷（不经 viewWithTag: 查找身份）
        [item addTarget:self
                 action:@selector(ame_railItemTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [_railStack addArrangedSubview:item];
        [_railItems addObject:item];

        // 组分隔线：4→5（启动器｜Java管理/控制管理）与 6→7（控制管理｜关于）；
        // 分隔线两侧 custom spacing 6 呼吸（组间距语义）
        if (i == 4 || i == 6) {
            [_railStack setCustomSpacing:6.0 afterView:item];
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor =
                [[ZL2Theme onSurface] colorWithAlphaComponent:0.4];
            separator.userInteractionEnabled = NO;
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            [_railStack addArrangedSubview:separator];
            [_railStack setCustomSpacing:6.0 afterView:separator];
            [_railSeparators addObject:separator];
            NSLayoutConstraint *sepWidth =
                [separator.widthAnchor constraintEqualToConstant:0.0];
            sepWidth.active = YES;
            [self.separatorWidthConstraints addObject:sepWidth];
        }
    }
    [self ame_applyRailMetrics];

    // —— 右内容区 ——
    _contentContainer = [[UIView alloc] init];
    _contentContainer.backgroundColor = [ZL2Theme surface];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_contentContainer];
    [NSLayoutConstraint activateConstraints:@[
        [_contentContainer.leadingAnchor constraintEqualToAnchor:railEdge.trailingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

// 轨宽度量刷新：轨宽、轨项宽（轨宽-12，ZL2RailView 同款内缩）、分隔线宽（60%）
- (void)ame_applyRailMetrics {
    CGFloat railWidth = [self ame_railWidth];
    self.railWidthConstraint.constant = railWidth;
    for (ZL2SettingsRailItem *item in self.railItems) {
        item.itemWidth.constant = railWidth - 12.0;
    }
    for (NSUInteger i = 0; i < self.railSeparators.count && i < self.separatorWidthConstraints.count; i++) {
        self.separatorWidthConstraints[i].constant = railWidth * 0.6;   // spec：宽 60%
    }
}

- (CGFloat)ame_railWidth {
    return ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        ? ame_hubRailWidthPad : ame_hubRailWidthPhone;
}

#pragma mark - 子页管理（懒建缓存 + 首显 attach + 0.18s crossDissolve，
//               ZL2ShellViewController 手法平移）

- (UIViewController *)ame_currentPage {
    if (self.currentIndex < 0) return nil;
    return self.childCache[@(self.currentIndex)];
}

- (UIViewController *)ame_pageForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *page;
    switch (index) {
        case 0: page = [[ZL2RendererSettingsPage alloc] init];        break;
        case 1: page = [[ZL2GameSettingsPage alloc] init];            break;
        case 2: page = [[ZL2ControlSettingsPage alloc] init];         break;
        case 3: page = [[ZL2GamepadSettingsPage alloc] init];         break;
        case 4: page = [[ZL2LauncherSettingsPage alloc] init];        break;
        case 5: page = [[ZL2JavaManagerSettingsPage alloc] init];     break;
        case 6: page = [[ZL2ControlManagerSettingsPage alloc] init];  break;
        case 7: page = [[ZL2AboutSettingsPage alloc] init];           break;
        default: return nil;
    }
    // 页首大标题（ZL2SettingPage.viewDidLoad 消费）
    page.title = [self ame_titleForIndex:index];
    self.childCache[@(index)] = page;
    return page;
}

- (NSString *)ame_titleForIndex:(NSInteger)index {
    switch (index) {
        case 0: return @"渲染器";
        case 1: return @"游戏";
        case 2: return @"控制";
        case 3: return @"手柄";
        case 4: return @"启动器";
        case 5: return @"Java 管理";
        case 6: return @"控制管理";
        case 7: return @"关于";
        default: return @"";
    }
}

// 四边钉入（ZL2Shell ame_attachChildIfNeeded 同构）
- (void)ame_attachPageIfNeeded:(UIViewController *)page {
    if (page.parentViewController == self) return;
    [self addChildViewController:page];
    page.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:page.view];
    [NSLayoutConstraint activateConstraints:@[
        [page.view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [page.view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [page.view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [page.view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
    [page didMoveToParentViewController:self];
}

// 子页切换：attach + 显隐 + 0.18s crossDissolve（同壳 showPageAtIndex）
- (void)ame_showPageAtIndex:(NSInteger)index {
    if (index < 0 || index > 7) return;
    if (index == self.currentIndex) return;

    UIViewController *next = [self ame_pageForIndex:index];
    UIViewController *prev = [self ame_currentPage];
    if (!next) return;

    [self ame_attachPageIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.contentContainer
                          duration:ame_hubAnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.currentIndex = index;
    [self ame_refreshRailSelection];

    // 切轨即刷新：子页重读偏好/文件状态（Java 运行时、控制布局等可在外部变化）
    if ([next respondsToSelector:@selector(ame_refreshState)]) {
        [(ZL2SettingPage *)next ame_refreshState];
    }
}

- (void)ame_refreshRailSelection {
    [self.railItems enumerateObjectsUsingBlock:^(ZL2SettingsRailItem *item, NSUInteger idx, BOOL *stop) {
        [item ame_setSelected:((NSInteger)idx == self.currentIndex)];
    }];
}

- (void)ame_railItemTapped:(ZL2SettingsRailItem *)sender {
    [self ame_showPageAtIndex:(NSInteger)sender.tag];
}

@end
