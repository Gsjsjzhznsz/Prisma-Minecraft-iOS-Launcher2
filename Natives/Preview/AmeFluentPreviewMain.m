//
// AmeFluentPreviewMain.m — ZL2 前端预览/冒烟 harness（7.0-UI-7/8/9/10）
//
// 用途：scripts/ui_fluent_smoke.sh preview 的宿主 App——在 iOS 模拟器里
//   1:1 渲染 ZL2 新壳视觉。7.0-UI-10-c 起壳形态 = 40pt 顶栏镜像（ZL2 真形态
//   本轮实证：40dp 顶栏 + 内容区，无 rail）+ 横屏（模拟器截图恒横置）：
//     顶栏：左簇 chevron.left / house.fill 32×32（onSurfaceVariant template，
//       主页时整簇隐藏）→ 16pt → 页名标题（fontTitleMedium/onSurface；主页 =
//       CFBundleDisplayName 兜底 @"Prisma Launcher"，其余 = 页名）；右簇
//       （右缘 12、间距 8）= 任务胶囊（surfaceContainerHigh/radiusXL/高 28/
//       宽 120：UIProgressView track=outlineVariant bar=primary +
//       doc.plaintext + 任务数 fontLabelMedium——桩态有活动任务才显示，与
//       下载页胶囊同口径，当前空桩恒隐藏）+ 4 枚 RailItem（版本
//       square.grid.2x2.fill / 下载 arrow.down.circle.fill / 账户
//       person.crop.circle.fill / 设置 gearshape.fill，22pt template，当前页
//       primary + 12pt 文字标签，其余 onSurfaceVariant）。顶栏纯视觉无交互，
//       页面切换仅由 -zl2page 启动参数决定。
//     五槽内容：0=ZL2Home（直接嵌）；1-4=四功能页真实 VC（ZL2Download/
//       Versions/Accounts/Settings，各包 UINavigationController 作为根 VC，
//       四页 viewWillAppear 自隐藏系统栏、版本/账户页 reload 由 viewWillAppear
//       自动触发；nav 隐藏后内容直接顶到顶栏下缘不留空隙）。
//   启动参数选页：-zl2page <home|download|versions|accounts|settings>
//   （CI 逐页冷启动截图 × 浅/深两态 = 10 张；缺省 home。"组件" Fluent 陈列页
//   退役：components 槽位与 AmeDemoPanelViewController /
//   AmeFluentLegacyPageViewController 已从本 TU 移除——Fluent 组件源文件
//   保留，仅预览壳不再陈列。）
//   横屏：AppDelegate supportedInterfaceOrientationsForWindow =
//   UIInterfaceOrientationMaskLandscapeButUpsideDown；呈现首选方向挂根 VC
//   （UIKit 只向 root VC 查询 preferredInterfaceOrientationForPresentation，
//   AppDelegate 无此回调）= UIInterfaceOrientationLandscapeRight。仅 harness
//   生效，正式 app 的 AppDelegate 不在本文件，零影响。
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
#import "AmeTheme.h"   // accentColor 桩消费（main TU 唯一残留 AmeTheme 引用）
#import "ZL2Theme.h"
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

#pragma mark - 启动参数选页（7.0-UI-9-e：CI 逐页冷启动截图；7.0-UI-10-c 五页）

// scripts/ui_fluent_smoke.sh preview 逐页启动：simctl launch … -zl2page <p>；
// 合法值 home/download/versions/accounts/settings（对应槽位 0-4；"组件"
// Fluent 陈列页已退役），缺省/非法值回落 home。simctl launch 把 bundle id
// 之后的参数原样追加到进程 argv，NSProcessInfo.arguments 直接可读
static NSInteger AmePreviewPageIndexFromLaunchArguments(void) {
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSUInteger flagIndex = [args indexOfObject:@"-zl2page"];
    if (flagIndex == NSNotFound || flagIndex + 1 >= args.count) return 0;
    NSString *page = args[flagIndex + 1];
    if ([page isEqualToString:@"download"]) return 1;
    if ([page isEqualToString:@"versions"]) return 2;
    if ([page isEqualToString:@"accounts"]) return 3;
    if ([page isEqualToString:@"settings"]) return 4;
    return 0;
}

// 顶栏页名（下标 0-4 与槽位一致；0 = 主页 = CFBundleDisplayName 兜底
// @"Prisma Launcher"——预览 Info.plist 无 CFBundleDisplayName 键必走兜底）
static NSString *AmePreviewPageTitle(NSInteger index) {
    static NSArray<NSString *> *titles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        titles = @[(bundleName ?: @"Prisma Launcher"), @"下载", @"版本", @"账户", @"设置"];
    });
    if (index < 0 || index >= (NSInteger)titles.count) index = 0;
    return titles[index];
}

// 顶栏 RailItem 视觉顺序（版本/下载/账户/设置，按 ZL2 TopBar 右簇规格）到
// 页面槽位的映射：版本→2 / 下载→1 / 账户→3 / 设置→4（home=0 无 RailItem，
// 由左簇 house 镜像承担）
static NSInteger AmePreviewRailSlotForItem(NSUInteger itemIndex) {
    static const NSInteger slots[4] = {2, 1, 3, 4};
    if (itemIndex >= 4) return -1;
    return slots[itemIndex];
}

#pragma mark - ZL2 壳预览控制器（7.0-UI-10-c：40pt 顶栏镜像 + 五槽容器切换）

// 壳真形态镜像（对照并行重写中的 ZL2ShellViewController / ZL2 MainScreen.kt
// TopBar；纯视觉 1:1、零交互——页面切换仅由 -zl2page 启动参数决定）：
//   顶栏高 40（背景自 y=0 延伸过顶部 safeArea；ZL2 TopBar height(40.dp)）：
//     左簇 = [chevron.left][house.fill] 32×32（onSurfaceVariant template；
//       ZL2 backCenter Row：start 12dp 起步），主页时整簇隐藏；
//     标题 = fontTitleMedium/onSurface，跟左簇后 16pt（ZL2 title margin 16dp）；
//     右簇（右缘 12、间距 8，ZL2 endButtons end margin 12dp spacedBy 8dp）=
//       任务胶囊 + 4 枚 RailItem（构建处逐项注明）。
//   内容区 = 顶栏下缘起占满剩余空间（五槽：0=ZL2Home 直接嵌；1-4=四功能页
//   各包 UINavigationController，与壳侧同构；四页 viewWillAppear 自隐藏系统
//   栏，nav 隐藏后内容直接顶到顶栏下缘不留空隙）。
@interface AmePreviewShellController : UIViewController
@property(nonatomic, strong) UIView *barBackground;
@property(nonatomic, strong) UIStackView *leadingCluster;   // [左簇图标组, 标题]
@property(nonatomic, strong) UIStackView *leftCluster;      // chevron + house（主页隐藏→折叠）
@property(nonatomic, strong) UILabel *topBarTitle;
@property(nonatomic, strong) UIView *taskPill;
@property(nonatomic, strong) UIProgressView *pillProgress;
@property(nonatomic, strong) UILabel *pillCount;
@property(nonatomic, strong) NSArray<UIStackView *> *railItems;
@property(nonatomic, strong) UIView *container;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *cache;
@property(nonatomic, assign) NSInteger currentIndex;
@end

@implementation AmePreviewShellController

// 横屏（7.0-UI-10-c）：有效支持方向 = 本值 ∩ AppDelegate
// supportedInterfaceOrientationsForWindow（两侧同给 MaskLandscape，
// 双保险收敛）；呈现首选方向 UIKit 只向 root VC 查询——AppDelegate 无此
// 回调，故挂在根 VC 上（LandscapeRight：设备竖放时 app 强制横置渲染）
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.cache = [NSMutableDictionary dictionary];
    self.currentIndex = -1;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ── 顶栏背景：自 y=0 延伸过顶部 safeArea，下缘 = safeTop + 40 ──
    self.barBackground = [[UIView alloc] init];
    self.barBackground.backgroundColor = [ZL2Theme surface];
    self.barBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.barBackground];

    // ── 左簇（ZL2 backCenter 镜像，纯视觉）：chevron.left + house.fill ──
    self.leftCluster = [[UIStackView alloc] init];
    self.leftCluster.axis = UILayoutConstraintAxisHorizontal;
    self.leftCluster.spacing = 8;
    self.leftCluster.alignment = UIStackViewAlignmentCenter;
    self.leftCluster.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leftCluster addArrangedSubview:[self ame_barIcon:@"chevron.left"]];
    [self.leftCluster addArrangedSubview:[self ame_barIcon:@"house.fill"]];

    // ── 页名标题 ──
    self.topBarTitle = [[UILabel alloc] init];
    self.topBarTitle.font = [ZL2Theme fontTitleMedium];
    self.topBarTitle.textColor = [ZL2Theme onSurface];
    self.topBarTitle.translatesAutoresizingMaskIntoConstraints = NO;

    // 前导簇打包（间距 16 = ZL2 标题 margin）：主页时 leftCluster 整簇隐藏，
    // stack 折叠 → 标题自然滑到簇起点，零约束切换
    self.leadingCluster = [[UIStackView alloc] init];
    self.leadingCluster.axis = UILayoutConstraintAxisHorizontal;
    self.leadingCluster.spacing = 16;
    self.leadingCluster.alignment = UIStackViewAlignmentCenter;
    self.leadingCluster.translatesAutoresizingMaskIntoConstraints = NO;
    [self.leadingCluster addArrangedSubview:self.leftCluster];
    [self.leadingCluster addArrangedSubview:self.topBarTitle];
    [self.view addSubview:self.leadingCluster];

    // ── 右簇：任务胶囊 + 4 枚 RailItem（end margin 12 / spacedBy 8）──
    [self ame_buildTaskPill];

    UIStackView *rightCluster = [[UIStackView alloc] init];
    rightCluster.axis = UILayoutConstraintAxisHorizontal;
    rightCluster.spacing = 8;
    rightCluster.alignment = UIStackViewAlignmentCenter;
    rightCluster.translatesAutoresizingMaskIntoConstraints = NO;
    [rightCluster addArrangedSubview:self.taskPill];
    NSArray<NSString *> *railSymbols = @[@"square.grid.2x2.fill",    // 版本
                                         @"arrow.down.circle.fill",  // 下载
                                         @"person.crop.circle.fill", // 账户
                                         @"gearshape.fill"];         // 设置
    NSArray<NSString *> *railTitles = @[@"版本", @"下载", @"账户", @"设置"];
    NSMutableArray<UIStackView *> *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < railSymbols.count; i++) {
        UIStackView *item = [self ame_railItemWithSymbol:railSymbols[i]
                                                   title:railTitles[i]];
        [items addObject:item];
        [rightCluster addArrangedSubview:item];
    }
    self.railItems = items;
    [self.view addSubview:rightCluster];

    // ── 五槽内容容器：顶栏下缘起占满剩余 ──
    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.container];

    [NSLayoutConstraint activateConstraints:@[
        [self.barBackground.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.barBackground.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.barBackground.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.barBackground.bottomAnchor constraintEqualToAnchor:safe.topAnchor constant:40],
        [self.leadingCluster.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.leadingCluster.centerYAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [rightCluster.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [rightCluster.centerYAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.topAnchor constraintEqualToAnchor:self.barBackground.bottomAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // -zl2page 启动参数预选页面（CI 逐页截图；缺省 home）
    [self ame_showIndex:AmePreviewPageIndexFromLaunchArguments()];
}

// 任务胶囊（ZL2 endButtons 任务条镜像）：surfaceContainerHigh / radiusXL /
// 高 28 / 宽 120，内含 progress（track=outlineVariant bar=primary）+
// doc.plaintext + 任务数（fontLabelMedium）。可见性与下载页胶囊同口径 =
// hasActiveTasks——桩态 manager 无活动任务恒隐藏（主代理集成补活动任务桩后
// 顶栏与下载页两处同步显现）
- (void)ame_buildTaskPill {
    DownloadTaskManager *mgr = [DownloadTaskManager sharedManager];
    BOOL hasTasks = [mgr hasActiveTasks];

    self.taskPill = [[UIView alloc] init];
    self.taskPill.backgroundColor = [ZL2Theme surfaceContainerHigh];
    self.taskPill.layer.cornerRadius = [ZL2Theme radiusXL];
    self.taskPill.layer.masksToBounds = YES;
    self.taskPill.hidden = !hasTasks;
    self.taskPill.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *docImage = [UIImage systemImageNamed:@"doc.plaintext"]
                            ?: [UIImage systemImageNamed:@"doc.text.fill"];
    UIImageView *docIcon =
        [[UIImageView alloc] initWithImage:[docImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    docIcon.tintColor = [ZL2Theme onSurfaceVariant];
    docIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.taskPill addSubview:docIcon];

    self.pillProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.pillProgress.trackTintColor = [ZL2Theme outlineVariant];
    self.pillProgress.progressTintColor = [ZL2Theme primary];
    self.pillProgress.translatesAutoresizingMaskIntoConstraints = NO;
    [self.taskPill addSubview:self.pillProgress];

    self.pillCount = [[UILabel alloc] init];
    self.pillCount.font = [ZL2Theme fontLabelMedium];
    self.pillCount.textColor = [ZL2Theme onSurface];
    self.pillCount.text = [NSString stringWithFormat:@"%lu", (unsigned long)[mgr allTasks].count];
    self.pillCount.translatesAutoresizingMaskIntoConstraints = NO;
    [self.taskPill addSubview:self.pillCount];

    [NSLayoutConstraint activateConstraints:@[
        [self.taskPill.widthAnchor constraintEqualToConstant:120],
        [self.taskPill.heightAnchor constraintEqualToConstant:28],
        [docIcon.leadingAnchor constraintEqualToAnchor:self.taskPill.leadingAnchor constant:10],
        [docIcon.centerYAnchor constraintEqualToAnchor:self.taskPill.centerYAnchor],
        [self.pillProgress.leadingAnchor constraintEqualToAnchor:docIcon.trailingAnchor constant:6],
        [self.pillProgress.trailingAnchor constraintEqualToAnchor:self.pillCount.leadingAnchor constant:-6],
        [self.pillProgress.centerYAnchor constraintEqualToAnchor:self.taskPill.centerYAnchor],
        [self.pillProgress.heightAnchor constraintEqualToConstant:3],
        [self.pillCount.trailingAnchor constraintEqualToAnchor:self.taskPill.trailingAnchor constant:-10],
        [self.pillCount.centerYAnchor constraintEqualToAnchor:self.taskPill.centerYAnchor],
    ]];

    if (hasTasks) {
        double first = [mgr allTasks].firstObject.progress;
        if (first < 0) first = 0;
        if (first > 1) first = 1;
        [self.pillProgress setProgress:(float)first animated:NO];
    }
}

// 左簇图标：32×32 视觉框（ZL2 TopBar IconButton 镜像；纯视觉无交互，非按钮），
// 字形 22pt template onSurfaceVariant
- (UIImageView *)ame_barIcon:(NSString *)symbol {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeCenter;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:32],
        [iconView.heightAnchor constraintEqualToConstant:32],
    ]];
    return iconView;
}

// 顶栏 RailItem（ZL2 TopBarRailItem 镜像，先建未选态；选中态由
// ame_refreshTopBarForIndex: 套用）：图标 22pt template + 12pt 文字标签
// （间距 6 = ZL2 TextRailItem 选中标签 spacer；未选中隐藏 → stack 折叠）
- (UIStackView *)ame_railItemWithSymbol:(NSString *)symbol title:(NSString *)title {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.hidden = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *item = [[UIStackView alloc] init];
    item.axis = UILayoutConstraintAxisHorizontal;
    item.spacing = 6;
    item.alignment = UIStackViewAlignmentCenter;
    item.translatesAutoresizingMaskIntoConstraints = NO;
    [item addArrangedSubview:iconView];
    [item addArrangedSubview:label];
    return item;
}

// 顶栏静态镜像刷新：左簇显隐 + 标题文案 + RailItem 选中态（当前页 primary +
// 12pt 标签，其余 onSurfaceVariant）。选页仅由启动参数解析后触发一次
- (void)ame_refreshTopBarForIndex:(NSInteger)index {
    self.leftCluster.hidden = (index == 0);
    self.topBarTitle.text = AmePreviewPageTitle(index);
    [self.railItems enumerateObjectsUsingBlock:^(UIStackView *item, NSUInteger i, BOOL *stop) {
        BOOL selected = (AmePreviewRailSlotForItem(i) == index);
        UIImageView *icon = item.arrangedSubviews.firstObject;
        UILabel *label = (item.arrangedSubviews.count > 1 ? item.arrangedSubviews[1] : nil);
        icon.tintColor = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
        label.textColor = icon.tintColor;
        label.hidden = !selected;
    }];
}

- (void)ame_showIndex:(NSInteger)index {
    if (index == self.currentIndex) return;
    UIViewController *next = self.cache[@(index)];
    if (!next) {
        switch (index) {
            case 0: next = [[ZL2HomeViewController alloc] init]; break;
            // 槽位 1-4：四功能页真实 VC（与 ZL2ShellViewController 壳侧同构：
            // 各包 UINavigationController 作根，根页 viewWillAppear 隐藏系统栏，
            // 版本/账户页 reload 由 viewWillAppear 自动触发）；链接期缺失符号
            // 由 Preview/ZL2PagesStub.m 桩 TU 补齐
            case 1: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2DownloadViewController alloc] init]]; break;
            case 2: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2VersionsViewController alloc] init]]; break;
            case 3: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2AccountsViewController alloc] init]]; break;
            case 4: next = [[UINavigationController alloc]
                               initWithRootViewController:[[ZL2SettingsViewController alloc] init]]; break;
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
    [self ame_refreshTopBarForIndex:index];
}

@end

#pragma mark - AppDelegate + main

@interface AmePreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation AmePreviewAppDelegate

// 横屏（7.0-UI-10-c）：模拟器截图恒为横屏——supportedInterfaceOrientationsForWindow
// 收敛为双横屏（与根 VC supportedInterfaceOrientations 交集生效）；呈现首选
// 方向由根 VC 的 preferredInterfaceOrientationForPresentation 给出
// （LandscapeRight，设备竖放时 app 强制横置渲染）。仅 harness 生效：正式 app
// 的 AppDelegate 不在本文件，零影响。
- (UIInterfaceOrientationMask)application:(UIApplication *)application
        supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [ZL2Theme surface];

    // 7.0-UI-10-c：根 = ZL2 壳真形态镜像（40pt 顶栏 + 五槽内容区，无 rail；
    // -zl2page 选页 home/download/versions/accounts/settings）
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
