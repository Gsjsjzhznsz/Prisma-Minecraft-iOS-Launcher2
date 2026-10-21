//
// AmeFluentPreviewMain.m — Fluent 2 / ZL2 前端预览/冒烟 harness（7.0-UI-7/8/9）
//
// 用途：scripts/ui_fluent_smoke.sh preview 的宿主 App——在 iOS 模拟器里
//   1:1 渲染 ZL2 新壳视觉（M3 NavigationRail；7.0-UI-9-e 起 rail 槽位
//   0=ZL2Home、1-4=四功能页真实 VC（ZL2Download/Versions/Accounts/Settings，
//   各包 UINavigationController 作为根 VC，四页 viewWillAppear 自隐藏
//   系统栏、版本/账户页 reload 由 viewWillAppear 自动触发）、5=组件双栏
//   对比页）+ Fluent 8 件套全陈列，供浅/深两态截图冒烟。
//   启动参数选页：-zl2page <home|download|versions|accounts|settings|
//   components> 预选 rail 项（CI 逐页冷启动截图；缺省 home）。
//
//
// ★ 正式构建不含本文件：Natives/CMakeLists.txt 为显式源列表（唯一的
//   file(GLOB) 仅涉 ModLoaderIcons/*.png），本文件不会被编入 App。
// ★ 服务桩：本 TU 提供 accentColor()/getPrefObject()/localize()/
//   BackgroundManager/BaseAuthenticator/PLProfiles/
//   MinecraftResourceDownloadTask/DownloadTaskManager/PLTaskProgress-
//   ViewController 最小桩实现（仅满足预览链路链接；正式构建用真实现，
//   互不冲突——桩与真实现从不在同一二进制）。7.0-UI-9 四页其余缺失符号
//   在 Preview/ZL2PagesStub.m 桩 TU（目标 VC 空类/管理器/C 函数/extern
//   常量），既有桩缺口方法（PLProfiles.updateCurrent、
//   DownloadTaskManager.tasksWithStates: 等）在本 TU 原桩上补齐。
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
#import "ZL2Theme.h"
#import "ZL2RailView.h"
#import "ZL2HomeViewController.h"
#import "ZL2DownloadViewController.h"
#import "ZL2VersionsViewController.h"
#import "ZL2AccountsViewController.h"
#import "ZL2SettingsViewController.h"

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

#pragma mark - ZL2 预览桩（7.0-UI-8：ZL2HomeViewController 链接期依赖）

// 签名全部取自真实头文件（BaseAuthenticator.h / PLProfiles.h /
// MinecraftResourceDownloadTask.h / DownloadTaskManager.h /
// PLTaskProgressViewController.h / utils.h）；桩 TU 不 import 真头，
// 手写同名类声明 + 实现（与 BackgroundManager 桩同款先例），仅补齐
// ZL2Home.m 直接调用的符号，无 duplicate symbol。

// utils.h 声明：NSString* localize(NSString *key, NSString *comment)
// 预览桩：优先映射启动三态既有键，未命中回退 comment——本仓 localize 约定
// 第二参即中文译文（7.0-UI-9 起），一处覆盖四页全部键，截图不再出现键名
NSString *localize(NSString *key, NSString *comment) {
    NSDictionary *table = @{@"i18n_str_412": @"启动游戏",
                            @"i18n_str_434": @"下载中",
                            @"i18n_str_435": @"登录并启动"};
    NSString *hit = table[key];
    return hit ?: (comment ?: key);
}

// BaseAuthenticator 最小桩：预览恒未登录态（launchReady = 登录并启动文案）。
// 7.0-UI-9-e 补齐账户页消费的缺口方法（setCurrent:/loadSavedName: 类方法 +
// initWithInput:/loginWithCallback:/refreshTokenWithCallback: 实例方法，
// 签名对 authenticator/BaseAuthenticator.h；LocalAuthenticator /
// MicrosoftAuthenticator / ThirdPartyAuthenticator 桩在 ZL2PagesStub.m
// 以本类为超类锚点子类化，超类方法零重复）
@interface BaseAuthenticator : NSObject
+ (id)current;
+ (void)setCurrent:(id)auth;
+ (id)loadSavedName:(NSString *)accountId;
- (id)initWithInput:(NSString *)string;
- (void)loginWithCallback:(void (^)(id status, BOOL success))callback;
- (void)refreshTokenWithCallback:(void (^)(id status, BOOL success))callback;
@end

@implementation BaseAuthenticator
+ (id)current { return nil; }
+ (void)setCurrent:(id)auth {}
+ (id)loadSavedName:(NSString *)accountId { return nil; }
- (id)initWithInput:(NSString *)string { return self; }
- (void)loginWithCallback:(void (^)(id status, BOOL success))callback {}
- (void)refreshTokenWithCallback:(void (^)(id status, BOOL success))callback {}
@end

// PLProfiles 最小桩：无 profile（版本卡显示"未选择实例"）
@interface PLProfiles : NSObject
+ (PLProfiles *)current;
- (NSString *)selectedProfileName;
- (NSMutableDictionary *)profiles;
- (void)save;
@end

@implementation PLProfiles

+ (PLProfiles *)current {
    static PLProfiles *p = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ p = [[PLProfiles alloc] init]; });
    return p;
}

- (NSString *)selectedProfileName { return nil; }
- (NSMutableDictionary *)profiles { return [NSMutableDictionary dictionary]; }
- (void)save {}

// 7.0-UI-9-e：版本页缺口方法补齐（viewWillAppear 先 updateCurrent 重拉
// 注册表；选用链写 selectedProfileName——预览恒空表，写入落空即安全）
+ (void)updateCurrent {}
- (void)setSelectedProfileName:(NSString *)name {}

@end

// MinecraftResourceDownloadTask 最小桩：预览演示态——downloadVersion: 后
// 模拟进度推进（NSProgress completedUnitCount 驱动 KVO → Home 状态 label
// 显示"下载中 xx%"），让截图可验收下载态视觉
@interface MinecraftResourceDownloadTask : NSObject
@property(nonatomic, strong) NSProgress *progress;
@property(nonatomic, copy) void (^handleError)(void);
- (void)downloadVersion:(NSDictionary *)version;
@end

@implementation MinecraftResourceDownloadTask

- (instancetype)init {
    self = [super init];
    if (self) {
        _progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
        _progress.totalUnitCount = 100;
    }
    return self;
}

- (void)downloadVersion:(NSDictionary *)version {
    __weak MinecraftResourceDownloadTask *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong MinecraftResourceDownloadTask *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.progress becomeCurrentWithPendingUnitCount:100];
        strongSelf.progress.completedUnitCount = 8;
        [strongSelf.progress resignCurrent];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong MinecraftResourceDownloadTask *s2 = weakSelf;
            if (!s2) return;
            [s2.progress becomeCurrentWithPendingUnitCount:92];
            s2.progress.completedUnitCount += 55;
            [s2.progress resignCurrent];
        });
    });
}

@end

// DownloadTaskManager 最小桩：预览无真实任务
@interface DownloadTaskItem : NSObject
@property(nonatomic, copy) NSString *taskId;
@property(nonatomic, weak) id rawTask;
// 7.0-UI-9-e：下载页任务胶囊消费的缺口属性（state 恒 0=Pending 且 manager
// 空桩 allTasks 恒空数组，胶囊 hidden 派生不变）
@property(nonatomic, assign) NSInteger state;
@property(nonatomic, assign) double progress;
@end

@implementation DownloadTaskItem
@end

@interface DownloadTaskManager : NSObject
+ (instancetype)sharedManager;
- (NSArray<DownloadTaskItem *> *)allTasks;
- (BOOL)hasActiveTasks;
@end

@implementation DownloadTaskManager

+ (instancetype)sharedManager {
    static DownloadTaskManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ m = [[DownloadTaskManager alloc] init]; });
    return m;
}

- (NSArray<DownloadTaskItem *> *)allTasks { return @[]; }
- (BOOL)hasActiveTasks { return NO; }
// 7.0-UI-9-e：下载页活动任务计数消费（空数组恒 0，胶囊保持隐藏）
- (NSArray<DownloadTaskItem *> *)tasksWithStates:(NSArray<NSNumber *> *)states { return @[]; }

@end

// PLTaskProgressViewController 最小桩：预览不真呈现
@interface PLTaskProgressViewController : UIViewController
+ (void)presentForTaskId:(NSString *)taskId;
@end

@implementation PLTaskProgressViewController
+ (void)presentForTaskId:(NSString *)taskId {
    NSLog(@"[AmeFluentPreview] stub presentForTaskId:%@", taskId);
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

#pragma mark - Fluent 旧栏陈列页（双栏对比：真实旧侧栏 + 8 件套）

// 原 7.0-UI-7 根组装平移至此：左侧真实 LauncherMenuViewController（56pt
// Fluent 栏宿主）+ 右侧组件陈列面板，挂 ZL2 壳 rail 第 6 项"组件"
@interface AmeFluentLegacyPageViewController : UIViewController
@end

@implementation AmeFluentLegacyPageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [AmeTheme bgPrimary];

    UIView *sidebarHost = [[UIView alloc] init];
    sidebarHost.backgroundColor = [AmeTheme bgSecondary];
    sidebarHost.layer.cornerRadius = [AmeTheme radiusXL];
    sidebarHost.layer.cornerCurve = kCACornerCurveContinuous;
    sidebarHost.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    sidebarHost.layer.masksToBounds = YES;
    sidebarHost.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sidebarHost];

    LauncherMenuViewController *menu = [[LauncherMenuViewController alloc] init];
    menu.onMenuItemSelected = ^(NSInteger index, NSString *title) {
        NSLog(@"[AmeFluentPreview] menu index=%ld title=%@", (long)index, title);
    };
    [self addChildViewController:menu];
    [sidebarHost addSubview:menu.view];
    // 7.0-UI-7：子 VC 编程视图默认 translates=YES，autoresizing 恒等约束会与
    // 四边钉冲突被拆（首跑截图侧栏整体缺失根因），必须显式关
    menu.view.translatesAutoresizingMaskIntoConstraints = NO;
    [menu didMoveToParentViewController:self];

    AmeDemoPanelViewController *demo = [[AmeDemoPanelViewController alloc] init];
    [self addChildViewController:demo];
    [self.view addSubview:demo.view];
    demo.view.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [sidebarHost.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [sidebarHost.widthAnchor constraintEqualToConstant:56],
        [sidebarHost.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [sidebarHost.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        [menu.view.leadingAnchor constraintEqualToAnchor:sidebarHost.leadingAnchor],
        [menu.view.trailingAnchor constraintEqualToAnchor:sidebarHost.trailingAnchor],
        [menu.view.topAnchor constraintEqualToAnchor:sidebarHost.topAnchor],
        [menu.view.bottomAnchor constraintEqualToAnchor:sidebarHost.bottomAnchor],
        [demo.view.leadingAnchor constraintEqualToAnchor:sidebarHost.trailingAnchor constant:8],
        [demo.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [demo.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [demo.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];
}

@end

#pragma mark - 启动参数选页（7.0-UI-9-e：CI 逐页冷启动截图）

// scripts/ui_fluent_smoke.sh preview 逐页启动：simctl launch … -zl2page <p>；
// 合法值 home/download/versions/accounts/settings/components（对应 rail 槽位
// 0-5），缺省/非法值回落 home。simctl launch 把 bundle id 之后的参数原样
// 追加到进程 argv，NSProcessInfo.arguments 直接可读
static NSInteger AmePreviewPageIndexFromLaunchArguments(void) {
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSUInteger flagIndex = [args indexOfObject:@"-zl2page"];
    if (flagIndex == NSNotFound || flagIndex + 1 >= args.count) return 0;
    NSString *page = args[flagIndex + 1];
    if ([page isEqualToString:@"download"])   return 1;
    if ([page isEqualToString:@"versions"])   return 2;
    if ([page isEqualToString:@"accounts"])   return 3;
    if ([page isEqualToString:@"settings"])   return 4;
    if ([page isEqualToString:@"components"]) return 5;
    return 0;
}

#pragma mark - ZL2 壳预览控制器（rail 6 项 + 容器切换，1:1 壳视觉）

@interface AmePreviewShellController : UIViewController <ZL2RailViewDelegate>
@property(nonatomic, strong) ZL2RailView *rail;
@property(nonatomic, strong) UIView *container;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *cache;
@property(nonatomic, assign) NSInteger currentIndex;
@end

@implementation AmePreviewShellController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.cache = [NSMutableDictionary dictionary];
    self.currentIndex = -1;

    CGFloat railW = [ZL2RailView widthForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    self.rail = [[ZL2RailView alloc] initWithItems:@[@"主页", @"下载", @"版本", @"账户", @"设置", @"组件"]
                                           symbols:@[@"house.fill",
                                                     @"arrow.down.circle.fill",
                                                     @"folder.fill",
                                                     @"person.fill",
                                                     @"gearshape.fill",
                                                     @"square.grid.2x2.fill"]];
    self.rail.translatesAutoresizingMaskIntoConstraints = NO;
    self.rail.delegate = self;
    [self.view addSubview:self.rail];

    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.container];

    [NSLayoutConstraint activateConstraints:@[
        [self.rail.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.rail.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.rail.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.rail.widthAnchor constraintEqualToConstant:railW],
        [self.container.leadingAnchor constraintEqualToAnchor:self.rail.trailingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 7.0-UI-9-e：-zl2page 启动参数预选 rail 项（CI 逐页截图；缺省 home）
    [self ame_showIndex:AmePreviewPageIndexFromLaunchArguments()];
}

- (void)ame_showIndex:(NSInteger)index {
    if (index == self.currentIndex) return;
    UIViewController *next = self.cache[@(index)];
    if (!next) {
        switch (index) {
            case 0: next = [[ZL2HomeViewController alloc] init]; break;
            // 7.0-UI-9-e：槽位 1-4 换装四功能页真实 VC（与 ZL2ShellViewController
            // 壳侧同构：各包 UINavigationController 作根，根页 viewWillAppear
            // 隐藏系统栏，版本/账户页 reload 由 viewWillAppear 自动触发）；
            // 槽位 1-4 的链接期缺失符号由 Preview/ZL2PagesStub.m 桩 TU 补齐
            case 1: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2DownloadViewController alloc] init]]; break;
            case 2: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2VersionsViewController alloc] init]]; break;
            case 3: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2AccountsViewController alloc] init]]; break;
            case 4: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2SettingsViewController alloc] init]]; break;
            case 5: next = [[AmeFluentLegacyPageViewController alloc] init]; break;
            default: return;
        }
        self.cache[@(index)] = next;
    }

    UIViewController *prev = self.cache[@(self.currentIndex)];
    [self addChildViewController:next];
    next.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.container addSubview:next.view];
    [NSLayoutConstraint activateConstraints:@[
        [next.view.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor],
        [next.view.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor],
        [next.view.topAnchor constraintEqualToAnchor:self.container.topAnchor],
        [next.view.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor],
    ]];
    [next didMoveToParentViewController:self];

    [UIView transitionWithView:self.container
                      duration:0.18
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    } completion:nil];

    self.currentIndex = index;
    self.rail.selectedIndex = index;
}

- (void)railView:(ZL2RailView *)rail didSelectIndex:(NSInteger)index {
    [self ame_showIndex:index];
}

@end

#pragma mark - AppDelegate + main

@interface AmePreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation AmePreviewAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [ZL2Theme surface];

    // 7.0-UI-8：根 = ZL2 壳视觉 1:1（M3 NavigationRail；槽位 0=ZL2Home、
    // 1-4=四功能页真实 VC、5=组件对比页）+ 7.0-UI-9-e 起 -zl2page 选页
    UIViewController *root = [[AmePreviewShellController alloc] init];

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
