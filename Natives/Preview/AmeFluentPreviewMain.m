//
// AmeFluentPreviewMain.m — Fluent 2 前端预览/冒烟 harness（7.0-UI-7）
//
// 用途：scripts/ui_fluent_smoke.sh preview 的宿主 App——在 iOS 模拟器里
//   1:1 渲染侧栏 Navigation Rail 重搭成果（真实 LauncherMenuViewController
//   原样嵌入）+ 组件库 8 件套全陈列，供浅/深两态截图冒烟。
//
// ★ 正式构建不含本文件：Natives/CMakeLists.txt 为显式源列表（唯一的
//   file(GLOB) 仅涉 ModLoaderIcons/*.png），本文件不会被编入 App。
// ★ 服务桩：本 TU 提供 accentColor()/getPrefObject()/BackgroundManager
//   最小桩实现（仅满足预览链路链接；正式构建用真实现，互不冲突——
//   桩与真实现从不在同一二进制）。
//

#import <UIKit/UIKit.h>
#import "AmeTheme.h"
#import "FluentButton.h"
#import "FluentCard.h"
#import "FluentListCell.h"
#import "FluentTextField.h"
#import "FluentToast.h"
#import "FluentSegmentedControl.h"
#import "FluentProgress.h"
#import "FluentBanner.h"
#import "LauncherMenuViewController.h"

#pragma mark - 服务桩（预览链路专用）

// LauncherPreferences.h 声明：UIColor *accentColor(void);
UIColor *accentColor(void) {
    return [AmeTheme brandPrimary];
}

// LauncherPreferences.h 声明：id getPrefObject(NSString *key);
// 预览环境无偏好存储：返回 nil → 菜单未选中色走 [AmeTheme textSecondary] 默认档
id getPrefObject(NSString *key) {
    return nil;
}

// BackgroundManager 最小桩：LauncherMenuViewController 仅消费
// sharedManager + makeViewControllerTransparent:（预览无壁纸管线，透传清底）
@interface BackgroundManager : NSObject
+ (instancetype)sharedManager;
- (void)makeViewControllerTransparent:(UIViewController *)viewController;
@end

@implementation BackgroundManager

+ (instancetype)sharedManager {
    static BackgroundManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[BackgroundManager alloc] init];
    });
    return manager;
}

- (void)makeViewControllerTransparent:(UIViewController *)viewController {
    viewController.view.backgroundColor = [UIColor clearColor];
}

@end

#pragma mark - 组件陈列面板（右侧）

@interface AmeDemoPanelViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, strong) FluentProgress *progressBar;
@property(nonatomic, strong) UIButton *appearanceToggle;
@end

@implementation AmeDemoPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [AmeTheme bgPrimary];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];

    // ── 标题区 ──
    UILabel *title = [[UILabel alloc] init];
    title.text = @"AmeTheme × Fluent 组件预览";
    title.font = [AmeTheme fontTitle];
    title.textColor = [AmeTheme textPrimary];
    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"fluent2_kit 规格 ObjC 重建 · 令牌真源 AmeTheme · 浅/深动态适配";
    sub.font = [AmeTheme fontBody2];
    sub.textColor = [AmeTheme textSecondary];
    sub.numberOfLines = 0;
    [stack addArrangedSubview:title];
    [stack addArrangedSubview:sub];

    // ── 1. FluentButton 四变体（Regular 40）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentButton 四变体"]];
    UIStackView *btnRow = [self rowStack];
    [btnRow addArrangedSubview:[FluentButton buttonWithStyle:FluentButtonStyleAccent title:@"启动" target:nil action:NULL]];
    [btnRow addArrangedSubview:[FluentButton buttonWithStyle:FluentButtonStyleOutline title:@"选择版本" target:nil action:NULL]];
    [btnRow addArrangedSubview:[FluentButton buttonWithStyle:FluentButtonStyleSubtle title:@"官方文档" target:nil action:NULL]];
    [btnRow addArrangedSubview:[FluentButton buttonWithStyle:FluentButtonStyleDefault title:@"清理缓存" target:nil action:NULL]];
    [stack addArrangedSubview:btnRow];

    // ── 2. Compact 32 + IconButton 图标档（侧栏同款组件）──
    [stack addArrangedSubview:[self sectionHeader:@"Compact 32 + IconButton（侧栏同款）"]];
    UIStackView *compactRow = [self rowStack];
    [compactRow addArrangedSubview:[FluentButton compactButtonWithStyle:FluentButtonStyleAccent title:@"下载" target:nil action:NULL]];
    [compactRow addArrangedSubview:[FluentButton compactButtonWithStyle:FluentButtonStyleOutline title:@"导入" target:nil action:NULL]];
    [compactRow addArrangedSubview:[FluentButton iconButtonWithStyle:FluentButtonStyleSubtle size:40
                                                               image:[UIImage systemImageNamed:@"gearshape.fill"]
                                                              target:nil action:NULL]];
    [compactRow addArrangedSubview:[FluentButton iconButtonWithStyle:FluentButtonStyleOutline size:40
                                                               image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                                              target:nil action:NULL]];
    [compactRow addArrangedSubview:[FluentButton iconButtonWithStyle:FluentButtonStyleDefault size:40
                                                               image:[UIImage systemImageNamed:@"trash"]
                                                              target:nil action:NULL]];
    [stack addArrangedSubview:compactRow];

    // ── 3. FluentSegmentedControl（滑块分段）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentSegmentedControl"]];
    FluentSegmentedControl *seg = [[FluentSegmentedControl alloc] initWithItems:@[@"主界面", @"下载", @"联机", @"设置"]];
    [seg setSelectedIndex:1 animated:NO];
    seg.onChange = ^(NSUInteger index) {
        [FluentToast showWithTitle:[NSString stringWithFormat:@"已切换到段 %lu", (unsigned long)index]
                            detail:nil
                          variant:FluentToastVariantNeutral];
    };
    [stack addArrangedSubview:seg];

    // ── 4. FluentProgress（Bar + Ring）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentProgress"]];
    UIStackView *progressRow = [self rowStack];
    self.progressBar = [[FluentProgress alloc] initWithStyle:FluentProgressStyleBar];
    [self.progressBar.widthAnchor constraintEqualToConstant:180].active = YES;
    [self.progressBar setProgress:0.35 animated:NO];
    FluentProgress *ring = [[FluentProgress alloc] initWithStyle:FluentProgressStyleRing];
    ring.running = YES;
    [progressRow addArrangedSubview:self.progressBar];
    [progressRow addArrangedSubview:ring];
    [stack addArrangedSubview:progressRow];

    // ── 5. FluentBanner（warning 信息条，可直接关闭）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentBanner"]];
    FluentBanner *banner = [[FluentBanner alloc] initWithTitle:@"Java 17 运行时可用"
                                                        message:@"建议为 1.20.5+ 版本启用新运行时"
                                                       severity:FluentBannerSeverityWarning];
    banner.closeHandler = ^{
        [FluentToast showWithTitle:@"信息条已关闭" detail:nil variant:FluentToastVariantNeutral];
    };
    [stack addArrangedSubview:banner];

    // ── 6. FluentCard + FluentTextField ──
    [stack addArrangedSubview:[self sectionHeader:@"FluentCard + FluentTextField"]];
    FluentCard *card = [[FluentCard alloc] init];
    UIStackView *cardStack = [[UIStackView alloc] init];
    cardStack.axis = UILayoutConstraintAxisVertical;
    cardStack.spacing = 10;
    cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:cardStack];
    [NSLayoutConstraint activateConstraints:@[
        [cardStack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [cardStack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor],
        [cardStack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [cardStack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor]
    ]];
    UILabel *cardTitle = [[UILabel alloc] init];
    cardTitle.text = @"玩家档案";
    cardTitle.font = [AmeTheme fontSubtitle];
    cardTitle.textColor = [AmeTheme textPrimary];
    FluentTextField *nameField = [[FluentTextField alloc] initWithFieldLabel:@"玩家名"
                                                                 placeholder:@"输入离线玩家名"
                                                                  isRequired:YES];
    [cardStack addArrangedSubview:cardTitle];
    [cardStack addArrangedSubview:nameField];
    [stack addArrangedSubview:card];

    // ── 7. FluentListCell（one-line ×2 + multi-line ×1）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentListCell"]];
    UITableView *list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    list.translatesAutoresizingMaskIntoConstraints = NO;
    list.backgroundColor = [UIColor clearColor];
    list.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0);
    list.scrollEnabled = NO;
    list.delegate = self;
    list.dataSource = self;
    [list registerClass:[FluentListCell class] forCellReuseIdentifier:@"one"];
    [list registerClass:[FluentListCell class] forCellReuseIdentifier:@"multi"];
    [list.heightAnchor constraintEqualToConstant:156].active = YES;
    [stack addArrangedSubview:list];

    // ── 8. FluentToast 触发器（四变体）──
    [stack addArrangedSubview:[self sectionHeader:@"FluentToast"]];
    UIStackView *toastRow = [self rowStack];
    [toastRow addArrangedSubview:[self toastButton:@"常规" variant:FluentToastVariantNeutral]];
    [toastRow addArrangedSubview:[self toastButton:@"成功" variant:FluentToastVariantSuccess]];
    [toastRow addArrangedSubview:[self toastButton:@"警告" variant:FluentToastVariantWarning]];
    [toastRow addArrangedSubview:[self toastButton:@"危险" variant:FluentToastVariantDanger]];
    [stack addArrangedSubview:toastRow];

    // ── 9. 深浅切换 + 进度动画演示 ──
    UIStackView *demoRow = [self rowStack];
    self.appearanceToggle = [FluentButton buttonWithStyle:FluentButtonStyleAccent
                                                    title:@"切换深浅模式"
                                                   target:self
                                                   action:@selector(toggleAppearance)];
    UIButton *animateBar = [FluentButton buttonWithStyle:FluentButtonStyleOutline
                                                   title:@"随机进度"
                                                  target:self
                                                  action:@selector(randomizeProgress)];
    [demoRow addArrangedSubview:self.appearanceToggle];
    [demoRow addArrangedSubview:animateBar];
    [stack addArrangedSubview:demoRow];
}

#pragma mark - demo actions

- (void)toggleAppearance {
    UIWindow *window = self.view.window;
    if (!window) return;
    BOOL toDark = (window.overrideUserInterfaceStyle != UIUserInterfaceStyleDark);
    window.overrideUserInterfaceStyle = toDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}

- (void)randomizeProgress {
    [self.progressBar setProgress:((arc4random_uniform(90) + 5) / 100.0) animated:YES];
}

- (UIButton *)toastButton:(NSString *)title variant:(FluentToastVariant)variant {
    // 变体参数由 fireToast: 按 title 重解析（按钮只带标题；variant 形参保留
    // API 对称性并抑制"四变体枚举被遗忘"的维护盲区）
    return [FluentButton compactButtonWithStyle:FluentButtonStyleDefault
                                          title:title
                                         target:self
                                         action:@selector(fireToast:)];
}

- (void)fireToast:(UIButton *)sender {
    NSString *title = [sender titleForState:UIControlStateNormal];
    FluentToastVariant variant = FluentToastVariantNeutral;
    if ([title isEqualToString:@"成功"]) variant = FluentToastVariantSuccess;
    else if ([title isEqualToString:@"警告"]) variant = FluentToastVariantWarning;
    else if ([title isEqualToString:@"危险"]) variant = FluentToastVariantDanger;
    [FluentToast showWithTitle:[NSString stringWithFormat:@"%@通知", title]
                        detail:@"FluentToast 底部浮出 · 同屏单例"
                      variant:variant];
}

#pragma mark - helpers

- (UILabel *)sectionHeader:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [AmeTheme fontCaption];
    label.textColor = [AmeTheme textTertiary];
    return label;
}

- (UIStackView *)rowStack {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

#pragma mark - UITableView (FluentListCell)

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.row == 2) ? 64.0 : 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL multi = (indexPath.row == 2);
    NSString *identifier = multi ? @"multi" : @"one";
    FluentListCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = multi ? [FluentListCell multiLineCellWithReuseIdentifier:identifier]
                     : [FluentListCell oneLineCellWithReuseIdentifier:identifier];
    }
    NSArray<NSString *> *icons = @[@"house.fill", @"arrow.down.circle.fill", @"gearshape.fill"];
    cell.leadingIcon.image = [UIImage systemImageNamed:icons[indexPath.row]];
    if (multi) {
        cell.titleLabel.text = @"当前版本 1.0.0";
        cell.subtitleLabel.text = @"Fluent 2 · iOS 14+ 纯 ObjC";
    } else {
        cell.titleLabel.text = (indexPath.row == 0) ? @"主界面" : @"下载中心";
    }
    return cell;
}

@end

#pragma mark - AppDelegate + main

@interface AmePreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation AmePreviewAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [AmeTheme bgPrimary];

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [AmeTheme bgPrimary];

    // ── 左：侧栏宿主（模拟 RootVC 布局：surface 底 + radiusXL + 单侧圆角）──
    UIView *sidebarHost = [[UIView alloc] init];
    sidebarHost.backgroundColor = [AmeTheme bgSecondary];
    sidebarHost.layer.cornerRadius = [AmeTheme radiusXL];
    sidebarHost.layer.cornerCurve = kCACornerCurveContinuous;
    sidebarHost.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    sidebarHost.layer.masksToBounds = YES;
    sidebarHost.translatesAutoresizingMaskIntoConstraints = NO;
    [root.view addSubview:sidebarHost];

    // ── 真实侧栏原样嵌入（重搭成果的直接视觉验证）──
    LauncherMenuViewController *menu = [[LauncherMenuViewController alloc] init];
    menu.onMenuItemSelected = ^(NSInteger index, NSString *title) {
        NSLog(@"[AmeFluentPreview] menu index=%ld title=%@", (long)index, title);
    };
    [root addChildViewController:menu];
    [sidebarHost addSubview:menu.view];
    [menu didMoveToParentViewController:root];

    // ── 右：组件陈列面板 ──
    AmeDemoPanelViewController *demo = [[AmeDemoPanelViewController alloc] init];
    [root addChildViewController:demo];
    [root.view addSubview:demo.view];

    [NSLayoutConstraint activateConstraints:@[
        [sidebarHost.leadingAnchor constraintEqualToAnchor:root.view.leadingAnchor constant:8],
        [sidebarHost.widthAnchor constraintEqualToConstant:56],
        [sidebarHost.topAnchor constraintEqualToAnchor:root.view.topAnchor constant:8],
        [sidebarHost.bottomAnchor constraintEqualToAnchor:root.view.bottomAnchor constant:-8],
        [menu.view.leadingAnchor constraintEqualToAnchor:sidebarHost.leadingAnchor],
        [menu.view.trailingAnchor constraintEqualToAnchor:sidebarHost.trailingAnchor],
        [menu.view.topAnchor constraintEqualToAnchor:sidebarHost.topAnchor],
        [menu.view.bottomAnchor constraintEqualToAnchor:sidebarHost.bottomAnchor],
        [demo.view.leadingAnchor constraintEqualToAnchor:sidebarHost.trailingAnchor constant:8],
        [demo.view.trailingAnchor constraintEqualToAnchor:root.view.trailingAnchor constant:-8],
        [demo.view.topAnchor constraintEqualToAnchor:root.view.topAnchor constant:8],
        [demo.view.bottomAnchor constraintEqualToAnchor:root.view.bottomAnchor constant:-8]
    ]];

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AmePreviewAppDelegate class]));
    }
}
