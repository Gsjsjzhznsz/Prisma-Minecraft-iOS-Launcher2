//
// AmeFluentPreviewMain.m — ZL2 前端预览/冒烟 harness（7.0-UI-7/8/9/10）
//
// 用途：scripts/ui_fluent_smoke.sh preview 的宿主 App——在 iOS 模拟器里
//   1:1 渲染 ZL2 新壳视觉。7.0-UI-10-c 起壳形态 = 40pt 顶栏镜像（ZL2 真形态
//   本轮实证：40dp 顶栏 + 内容区，无 rail）+ 横屏（模拟器截图恒横置）：
//     顶栏：左簇 chevron.left / house.fill 32×32（onSurfaceVariant template，
//       主页时整簇隐藏）→ 16pt → 页名标题（fontTitleMedium/onSurface；主页 =
//       CFBundleDisplayName 兜底 @"Prisma Ⅱ"，其余 = 页名）；右簇
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
//   UIInterfaceOrientationMaskLandscape；呈现首选方向挂根 VC
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
// ★Task415b 升级：NSUserDefaults 后备（原先恒 nil = 预览链永远「未登录」，
//   皮肤 3D 预览从未被 CI 渲染过 = 第 23 轮「依旧纸片」假阴性根因之一）。
//   未设键仍返 nil = 旧消费方（菜单选中色等）零回归。
id getPrefObject(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
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

// BaseAuthenticator 桩（★Task415b 最小真语义）：旧桩 +current 恒 nil = 预览
//   恒「未登录」→ 皮肤 3D 预览/视觉卡/头像链在 CI 从未渲染（第 23 轮「依旧
//   纸片」两轮绿灯假阴性的结构性根源之一）。本版：current 惰性读
//   selected_account 偏好 → POJAV_HOME/accounts/<id>.json → authData 挂真
//   数据的本地 authenticator（setCurrent:/loadSavedName: 静态存储保持选中链
//   可写）。签名对 authenticator/BaseAuthenticator.h；LocalAuthenticator /
//   MicrosoftAuthenticator / ThirdPartyAuthenticator 桩在 ZL2PagesStub.m
//   以本类为超类锚点子类化，超类方法零重复。
extern NSMutableDictionary* parseJSONFromFile(NSString *path);   // utils.h 真解析（ZL2PagesStub TU）

@interface BaseAuthenticator : NSObject
@property (nonatomic, strong) NSMutableDictionary *authData;   // ★Task415b（真头同型）
+ (id)current;
+ (void)setCurrent:(id)auth;
+ (id)loadSavedName:(NSString *)accountId;
- (id)initWithInput:(NSString *)string;
- (void)loginWithCallback:(void (^)(id status, BOOL success))callback;
- (void)refreshTokenWithCallback:(void (^)(id status, BOOL success))callback;
@end

static id ame415_current = nil;

@implementation BaseAuthenticator
+ (id)ame415_loadAccount:(NSString *)accountId {
    if (![accountId isKindOfClass:[NSString class]] || accountId.length == 0) return nil;
    NSString *ame415_path = [NSString stringWithFormat:@"%s/accounts/%@.json",
                             getenv("POJAV_HOME"), accountId];
    NSMutableDictionary *ame415_data = parseJSONFromFile(ame415_path);
    if (!ame415_data || ame415_data[@"NSErrorObject"] != nil) return nil;
    BaseAuthenticator *ame415_auth = [[self alloc] init];
    ame415_auth.authData = ame415_data;
    return ame415_auth;
}
+ (id)current {
    if (ame415_current == nil) {
        NSString *ame415_saved = getPrefObject(@"internal.selected_account");
        if ([ame415_saved isKindOfClass:[NSString class]]) {
            ame415_current = [self ame415_loadAccount:ame415_saved];
        }
    }
    return ame415_current;
}
+ (void)setCurrent:(id)auth { ame415_current = auth; }
+ (id)loadSavedName:(NSString *)accountId {
    id ame415_auth = [self ame415_loadAccount:accountId];
    if (ame415_auth) ame415_current = ame415_auth;
    return ame415_auth;
}
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

// ★ Task393：假实例注册表（封面流/主页网格/版本页截图实数据；4 实例 =
//   封面流同时可见五枚的 4/5 覆盖 + 远近衰减可判读；写 save 落空即安全）
- (NSString *)selectedProfileName {
    static NSString *ame393_selected = @"生存存档";
    return ame393_selected;
}
- (NSMutableDictionary *)profiles {
    static NSMutableDictionary *ame393_profiles = nil;
    static dispatch_once_t ame393_once;
    dispatch_once(&ame393_once, ^{
        ame393_profiles = [@{
            @"1.21 Fabric":  @{@"lastVersionId": @"fabric-loader-0.16.9-1.21"},
            @"1.20.4 Forge": @{@"lastVersionId": @"forge-1.20.4"},
            @"生存存档":      @{@"lastVersionId": @"1.21.4"},
            @"纯净原版":      @{@"lastVersionId": @"1.8.9"},   // 实体不建 = 无效态判读样本
        } mutableCopy];
    });
    return ame393_profiles;
}
- (void)save {}

// 7.0-UI-9-e：版本页缺口方法补齐（viewWillAppear 先 updateCurrent 重拉
// 注册表；选用链写 selectedProfileName——预览恒空表，写入落空即安全）
+ (void)updateCurrent {}
- (void)setSelectedProfileName:(NSString *)name {}

// 7.0-UI-12：游戏下载页安装流建 profile（预览落空即安全，无写盘）
- (void)saveProfile:(NSDictionary *)profile withName:(NSString *)name {}

@end

// MinecraftResourceDownloadTask 最小桩：预览演示态——downloadVersion: 后
// 模拟进度推进（NSProgress completedUnitCount 驱动 KVO → Home 状态 label
// 显示"下载中 xx%"），让截图可验收下载态视觉
@interface MinecraftResourceDownloadTask : NSObject
@property(nonatomic, strong) NSProgress *progress;
@property(nonatomic, copy) void (^handleError)(void);
// Task323：启动续链读 task.metadata（真实头声明域）；预览桩回 nil →
// KVO 100% 走无 metadata 收尾分支（task=nil+ReloadProfileList，安全空转）
@property(nonatomic, copy) NSDictionary *metadata;
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
            // 7.0-UI-12：演示进度收尾到 finished（游戏页安装流轮询
            // progress.finished 判定，永不 finished → 后台空转 30 分钟，
            // ForgeDirectInstaller 恒 NO 同款预览防呆判例）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong MinecraftResourceDownloadTask *s3 = weakSelf;
                if (!s3) return;
                [s3.progress becomeCurrentWithPendingUnitCount:37];
                s3.progress.completedUnitCount += 37;
                [s3.progress resignCurrent];
            });
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

#pragma mark - Task323 启动续链预览桩（ZL2Home KVO 100% 续链链接期依赖）

// 签名取自真实头（LauncherPreferences.h / ios_uikit_bridge.h / PLJITGate.h）；
// 桩 TU 不 import 真头，手写同名声明 + 空实现（ZL2 预览桩同款先例）。

// LauncherPreferences.h: void setPrefString(NSString *key, NSString *value);
void setPrefString(NSString *key, NSString *value) {
    NSLog(@"[AmeFluentPreview] stub setPrefString:%@", key);
}

// LauncherPreferences.h: void setPrefInt(NSString *key, NSInteger value);
void setPrefInt(NSString *key, NSInteger value) {
    NSLog(@"[AmeFluentPreview] stub setPrefInt:%@", key);
}

// ios_uikit_bridge.h: void UIKit_launchMinecraftSurfaceVC(UIWindow*, NSDictionary*);
void UIKit_launchMinecraftSurfaceVC(UIWindow *window, NSDictionary *metadata) {
    NSLog(@"[AmeFluentPreview] stub UIKit_launchMinecraftSurfaceVC (metadata=%@)", metadata);
}

// PLJITGate.h 最小桩：预览不真进门禁（metadata=nil 路径也不会到达）
@interface PLJITGate : NSObject
+ (void)invokeAfterJITEnabledWithHandler:(void (^)(void))handler
                                  hostVC:(UIViewController *)hostVC
                               onAbandon:(void (^)(void))onAbandon
                                 onStage:(void (^)(NSString *stageText))onStage;
@end

@implementation PLJITGate
+ (void)invokeAfterJITEnabledWithHandler:(void (^)(void))handler
                                  hostVC:(UIViewController *)hostVC
                               onAbandon:(void (^)(void))onAbandon
                                 onStage:(void (^)(NSString *))onStage {
    NSLog(@"[AmeFluentPreview] stub PLJITGate invokeAfterJITEnabled (no-op)");
}
@end

#pragma mark - 启动参数选页（7.0-UI-9-e：CI 逐页冷启动截图；7.0-UI-10-c 五页）

// scripts/ui_fluent_smoke.sh preview 逐页启动：simctl launch … -zl2page <p>；
// 合法值 home/download/versions/accounts/settings（对应槽位 0-4；"组件"
// Fluent 陈列页已退役），缺省/非法值回落 home。simctl launch 把 bundle id
// 之后的参数原样追加到进程 argv，NSProcessInfo.arguments 直接可读
// ★ Task400：versionpicker 特例页退役（版本滚轮原地驻主页右栏，主页截图
//   即含双滚轮；总线/@"ZL2HomeShowVersionPicker" 延迟弹层链一并拆除）
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

/// ★ Task393：预览沙盒（假账户 + 假版本实体；POJAV_HOME 指向 app 容器内
/// 临时目录——账户页封面流与版本判定链（ame_isVersionIdValid 的
/// POJAV_HOME/versions 探测）由此读到实数据；parseJSONFromFile 桩
/// 同轮升级为真解析）
// ★Task415b 测试皮肤（64×64 程序化生成，零仓库二进制）：六部位六面调试
//   色直填 UV 区块（与 ZL2SkinViewFace 表同源）——渲染后预览图自证面向/
//   装配正确性（前面红/后面蓝/右面绿/左面黄/上面紫/下面青），头白点眼。
//   双落点：预览缓存 ①（Caches/skins/<id>.png）+ skinfull ②
//   （Documents/avatars/skinfull-<id>.png）——两段缓存回退链全被真数据覆盖。
//   ★Task415-r3：表体从嵌套 NSArray<NSArray*> 字面量改 C 结构体表——run
//   42825176854 实锤嵌套字面量 @[[@(8),...]] 在 CI clang 下 expected
//   identifier + comma-operator 误报三连（字面量解析歧义），C 表零歧义。
typedef struct { CGFloat x, y, w, h, r, g, b; } Ame415UVRect;

static void AmePreviewWriteTestSkin(NSString *path) {
    static const Ame415UVRect ame415_uv[] = {
        // 头 8³：前/后/右/左/上/下
        {8, 8, 8, 8, 1.00, 0.10, 0.10}, {24, 8, 8, 8, 0.15, 0.15, 0.95},
        {0, 8, 8, 8, 0.10, 0.85, 0.10}, {16, 8, 8, 8, 0.95, 0.90, 0.15},
        {8, 0, 8, 8, 0.90, 0.15, 0.90}, {16, 0, 8, 8, 0.10, 0.90, 0.90},
        // 身 8×12×4（绿系分面：前后右侧左上下亮度渐变，黑背景可辨）
        {20, 20, 8, 12, 0.20, 0.75, 0.30}, {32, 20, 8, 12, 0.15, 0.60, 0.25},
        {16, 20, 4, 12, 0.35, 0.70, 0.40}, {28, 20, 4, 12, 0.10, 0.50, 0.20},
        {20, 16, 8, 4, 0.50, 0.85, 0.55}, {28, 16, 8, 4, 0.25, 0.65, 0.35},
        // 右臂（蓝）
        {44, 20, 4, 12, 0.25, 0.45, 1.0}, {52, 20, 4, 12, 0.25, 0.45, 1.0},
        {40, 20, 4, 12, 0.25, 0.45, 1.0}, {48, 20, 4, 12, 0.25, 0.45, 1.0},
        {44, 16, 4, 4, 0.25, 0.45, 1.0}, {48, 16, 4, 4, 0.25, 0.45, 1.0},
        // 左臂（青）
        {36, 52, 4, 12, 0.20, 0.80, 0.80}, {44, 52, 4, 12, 0.20, 0.80, 0.80},
        {32, 52, 4, 12, 0.20, 0.80, 0.80}, {40, 52, 4, 12, 0.20, 0.80, 0.80},
        {36, 48, 4, 4, 0.20, 0.80, 0.80}, {40, 48, 4, 4, 0.20, 0.80, 0.80},
        // 右腿（棕）
        {4, 20, 4, 12, 0.55, 0.36, 0.20}, {12, 20, 4, 12, 0.55, 0.36, 0.20},
        {0, 20, 4, 12, 0.55, 0.36, 0.20}, {8, 20, 4, 12, 0.55, 0.36, 0.20},
        {4, 16, 4, 4, 0.55, 0.36, 0.20}, {8, 16, 4, 4, 0.55, 0.36, 0.20},
        // 左腿（橙）
        {20, 52, 4, 12, 1.0, 0.60, 0.10}, {28, 52, 4, 12, 1.0, 0.60, 0.10},
        {16, 52, 4, 12, 1.0, 0.60, 0.10}, {24, 52, 4, 12, 1.0, 0.60, 0.10},
        {20, 48, 4, 4, 1.0, 0.60, 0.10}, {24, 48, 4, 4, 1.0, 0.60, 0.10},
    };
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(64, 64), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.13 alpha:1.0].CGColor);
        CGContextFillRect(ctx, CGRectMake(0, 0, 64, 64));
        for (NSUInteger ame415_i = 0; ame415_i < sizeof(ame415_uv) / sizeof(ame415_uv[0]); ame415_i++) {
            const Ame415UVRect *ame415_r = &ame415_uv[ame415_i];
            CGContextSetRGBFillColor(ctx, ame415_r->r, ame415_r->g, ame415_r->b, 1.0);
            CGContextFillRect(ctx, CGRectMake(ame415_r->x, ame415_r->y, ame415_r->w, ame415_r->h));
        }
        // 头前脸白点眼（自证面向：两枚 1×1 点 (10,12)(13,12)）
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextFillRect(ctx, CGRectMake(10, 12, 1, 1));
        CGContextFillRect(ctx, CGRectMake(13, 12, 1, 1));
    }
    UIImage *ame415_skin = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (ame415_skin) {
        NSData *ame415_png = UIImagePNGRepresentation(ame415_skin);
        if (ame415_png.length > 0) [ame415_png writeToFile:path atomically:YES];
    }
}

static void AmePreviewPrepareSandbox(void) {
    NSString *home = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                          NSUserDomainMask, YES).firstObject
                      stringByAppendingPathComponent:@"preview-home"];
    [[NSFileManager defaultManager] createDirectoryAtPath:home
                              withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("POJAV_HOME", home.fileSystemRepresentation, 1);

    // 假账户 ×4（本地×2 / Microsoft / 第三方——类型文案判读面全覆盖）
    NSString *accounts = [home stringByAppendingPathComponent:@"accounts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:accounts
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *ame393_accounts = @{
        @"alex.json":     @{@"accountId": @"alex", @"username": @"Alex", @"accountType": @"local"},
        @"steve.json":    @{@"accountId": @"steve", @"username": @"Steve", @"accountType": @"local"},
        @"notchy.json":   @{@"accountId": @"notchy", @"username": @"Notchy", @"xboxGamertag": @"Notchy"},
        @"herobrine.json":@{@"accountId": @"herobrine", @"username": @"Demo.Herobrine", @"clientToken": @"preview"},
    };
    [ame393_accounts enumerateKeysAndObjectsUsingBlock:^(NSString *file, NSDictionary *data, BOOL *stop) {
        NSString *path = [accounts stringByAppendingPathComponent:file];
        NSData *json = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
        [json writeToFile:path atomically:YES];
    }];

    // ★Task415b 选中账户（internal.selected_account → steve）：BaseAuthenticator
    //   .current 由此加载 steve.json → 账户页视觉卡出真账号 + 皮肤 3D 预览
    //   首次在 CI 渲染（旧版恒「未登录」= 预览假阴性根因）
    [[NSUserDefaults standardUserDefaults] setObject:@"steve" forKey:@"internal.selected_account"];
    // 测试皮肤双落点（缓存①/skinfull②）——预览链两段缓存全真数据覆盖
    NSString *ame415_caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                                  NSUserDomainMask, YES) firstObject];
    NSString *ame415_skinsDir = [ame415_caches stringByAppendingPathComponent:@"skins"];
    [[NSFileManager defaultManager] createDirectoryAtPath:ame415_skinsDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    AmePreviewWriteTestSkin([ame415_skinsDir stringByAppendingPathComponent:@"steve.png"]);
    NSString *ame415_avatars = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                   NSUserDomainMask, YES) firstObject];
    ame415_avatars = [ame415_avatars stringByAppendingPathComponent:@"avatars"];
    [[NSFileManager defaultManager] createDirectoryAtPath:ame415_avatars
                              withIntermediateDirectories:YES attributes:nil error:nil];
    AmePreviewWriteTestSkin([ame415_avatars stringByAppendingPathComponent:@"skinfull-steve.png"]);

    // 假版本实体 ×3（纯净原版 1.8.9 不建 = 无效态判读样本）
    NSArray *ame393_vids = @[@"fabric-loader-0.16.9-1.21", @"forge-1.20.4", @"1.21.4"];
    for (NSString *vid in ame393_vids) {
        NSString *dir = [[home stringByAppendingPathComponent:@"versions"]
                         stringByAppendingPathComponent:vid];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *json = [NSString stringWithFormat:@"{\"id\": \"%@\"}", vid];
        [json writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", vid]]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// 顶栏页名（下标 0-4 与槽位一致；0 = 主页 = CFBundleDisplayName 兜底
//   ★ Task400：兜底字面与真机 CFBundleDisplayName 对齐“Prisma Ⅱ”——
//   原 "Prisma Launcher" 与真机名分叉，截图会被误读为改名）
static NSString *AmePreviewPageTitle(NSInteger index) {
    static NSArray<NSString *> *titles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        titles = @[(bundleName ?: @"Prisma Ⅱ"), @"下载", @"版本", @"账户", @"设置"];
    });
    if (index < 0 || index >= (NSInteger)titles.count) index = 0;
    return titles[index];
}

// 顶栏 RailItem 视觉顺序（版本/下载/账户/设置，按 ZL2 TopBar 右簇规格）到
// 页面槽位的映射：版本→2 / 下载→1 / 账户→3 / 设置→4（home=0 无 RailItem，
// 由左簇 house 镜像承担）
@interface AmePreviewShellController : UIViewController
@property(nonatomic, strong) UIView *barBackground;          // 顶带背景（bare） / 内容区头带（nav）
@property(nonatomic, strong) UILabel *headerTitle;          // 大标题（双骨架同源）
@property(nonatomic, strong) UIView *capsuleCluster;        // bare 右上六钮胶囊（ame411 镜像）
@property(nonatomic, strong) NSArray<UIView *> *capsuleButtons;
@property(nonatomic, strong) UIView *paneWrap;              // nav 左窗格（64 折叠态）
@property(nonatomic, strong) NSArray<UIView *> *paneItems;  // nav 主导航项（含选中抬升）
@property(nonatomic, strong) UIView *container;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *cache;
@property(nonatomic, assign) NSInteger currentIndex;
@property(nonatomic, assign) BOOL ame414_navShell;
@property(nonatomic, assign) BOOL ame416_paneExpanded;   // ★Task416：-zl2pane expanded 展开态镜像（折叠/展开两态同帡对比 = 图标恒定图证）
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

    // -zl2shell nav → fui NavigationView 镜像（缺省 bare）
    NSArray<NSString *> *ame414_args = [NSProcessInfo processInfo].arguments;
    NSUInteger ame414_shellIdx = [ame414_args indexOfObject:@"-zl2shell"];
    self.ame414_navShell = (ame414_shellIdx != NSNotFound && ame414_shellIdx + 1 < ame414_args.count
                            && [ame414_args[ame414_shellIdx + 1] isEqualToString:@"nav"]);
    // ★Task416：-zl2pane expanded → 窗格展开态镜像（280 宽 + 文字标签，
    //   图标仍 24pt 恒定 = 折叠不调图标的同帧图证；缺省折叠态 64）
    NSUInteger ame416_paneIdx = [ame414_args indexOfObject:@"-zl2pane"];
    self.ame416_paneExpanded = (ame416_paneIdx != NSNotFound && ame416_paneIdx + 1 < ame416_args.count
                                && [ame416_args[ame416_paneIdx + 1] isEqualToString:@"expanded"]);
    // -zl2theme fluent-dark → fui 暗板令牌渲染轨（fui 插件 PALETTES[1] 同值）
    NSUInteger ame414_themeIdx = [ame414_args indexOfObject:@"-zl2theme"];
    if (ame414_themeIdx != NSNotFound && ame414_themeIdx + 1 < ame414_args.count
        && [ame414_args[ame414_themeIdx + 1] isEqualToString:@"fluent-dark"]) {
        [ZL2Theme ame317_setPluginThemeTokens:@"preview-fluent"
                                       tokens:@{
            @"primary": @"4CC2FF", @"onPrimary": @"00344E",
            @"primaryContainer": @"004578", @"onPrimaryContainer": @"B4D6F7",
            @"secondary": @"6FA8CC", @"onSecondary": @"062033",
            @"secondaryContainer": @"1A3A54", @"onSecondaryContainer": @"C7E0F4",
            @"tertiary": @"C1A7E8", @"onTertiary": @"221046",
            @"tertiaryContainer": @"5D2E8C", @"onTertiaryContainer": @"EAD9FF",
            @"surface": @"1A1A1A", @"onSurface": @"F5F5F5",
            @"onSurfaceVariant": @"D4D4D4", @"surfaceVariant": @"262626",
            @"surfaceContainerLowest": @"111111", @"surfaceContainerLow": @"1D1D1D",
            @"surfaceContainer": @"222222", @"surfaceContainerHigh": @"282828",
            @"surfaceContainerHighest": @"2F2F2F", @"surfaceBright": @"3B3B3B",
            @"outline": @"6B6B6B", @"outlineVariant": @"3D3D3D",
            @"error": @"FF99A4", @"errorContainer": @"6E1122",
            @"success": @"6CCB5F", @"warning": @"F7B26A",
        }];
        self.view.backgroundColor = [ZL2Theme surface];
    }

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ── 顶带背景：自 y=0 延伸过顶部 safeArea，下缘 = safeTop + 64（★Task414）──
    self.barBackground = [[UIView alloc] init];
    self.barBackground.backgroundColor = [ZL2Theme surface];
    self.barBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.barBackground];

    // ── 大标题（fontHeadline，ame_titleForIndex 同源：主页 = Prisma Ⅱ）──
    self.headerTitle = [[UILabel alloc] init];
    self.headerTitle.font = [ZL2Theme fontHeadline];
    self.headerTitle.textColor = [ZL2Theme onSurface];
    self.headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerTitle];

    if (self.ame414_navShell) {
        [self ame414_buildNavPane];
    } else {
        [self ame414_buildCapsule];
    }

    // ── 五槽内容容器：顶带下缘起占满剩余 ──
    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.container];

    NSMutableArray<NSLayoutConstraint *> *ame414_pins = [NSMutableArray array];
    CGFloat ame416_paneLead = self.ame414_navShell ? 64.0 : 0.0;   // ★Task416：内容随窗格内缩（旧镜像漏内缩 = 内容滑入窗格底下）
    [ame414_pins addObject:[self.barBackground.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ame416_paneLead]];
    [ame414_pins addObject:[self.barBackground.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]];
    [ame414_pins addObject:[self.barBackground.topAnchor constraintEqualToAnchor:self.view.topAnchor]];
    [ame414_pins addObject:[self.barBackground.bottomAnchor constraintEqualToAnchor:safe.topAnchor constant:64]];
    [ame414_pins addObject:[self.headerTitle.leadingAnchor constraintEqualToAnchor:self.barBackground.leadingAnchor constant:16]];
    [ame414_pins addObject:[self.headerTitle.centerYAnchor constraintEqualToAnchor:safe.topAnchor constant:32]];
    [ame414_pins addObject:[self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ame416_paneLead]];
    [ame414_pins addObject:[self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]];
    [ame414_pins addObject:[self.container.topAnchor constraintEqualToAnchor:self.barBackground.bottomAnchor]];
    [ame414_pins addObject:[self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]];
    [NSLayoutConstraint activateConstraints:ame414_pins];

    // -zl2page 启动参数预选页面（CI 逐页截图；缺省 home）
    [self ame_showIndex:AmePreviewPageIndexFromLaunchArguments()];
}

// ── bare 右上六钮胶囊（ame411_switcherCluster 镜像：safe+12 入带，无文字）──
- (void)ame414_buildCapsule {
    self.capsuleCluster = [[UIView alloc] init];
    self.capsuleCluster.backgroundColor = [ZL2Theme surfaceContainer];
    self.capsuleCluster.layer.cornerRadius = 26.0;
    self.capsuleCluster.layer.masksToBounds = NO;
    self.capsuleCluster.layer.shadowColor = [UIColor blackColor].CGColor;
    self.capsuleCluster.layer.shadowOpacity = 0.28;
    self.capsuleCluster.layer.shadowRadius = 8.0;
    self.capsuleCluster.layer.shadowOffset = CGSizeMake(0, 2);
    self.capsuleCluster.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.capsuleCluster];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 2.0;
    [self.capsuleCluster addSubview:stack];

    NSArray<NSString *> *symbols = @[@"house.fill", @"arrow.down.circle.fill",
                                     @"person.2.fill", @"sparkles", @"gearshape.fill", @"folder.fill"];
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (NSString *symbol in symbols) {
        UIView *btn = [[UIView alloc] init];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.layer.cornerRadius = 12.0;
        UIImage *img = [UIImage systemImageNamed:symbol];
        if (img) {
            img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIImageView *iv = [[UIImageView alloc] initWithImage:img];
            iv.tintColor = [ZL2Theme onSurfaceVariant];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            iv.userInteractionEnabled = NO;
            [btn addSubview:iv];
            [NSLayoutConstraint activateConstraints:@[
                [iv.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
                [iv.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
                [iv.widthAnchor constraintEqualToConstant:24.0],
                [iv.heightAnchor constraintEqualToConstant:24.0],
            ]];
        }
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:40.0],
            [btn.heightAnchor constraintEqualToConstant:40.0],
        ]];
        [stack addArrangedSubview:btn];
        [buttons addObject:btn];
    }
    self.capsuleButtons = buttons;
    [NSLayoutConstraint activateConstraints:@[
        [self.capsuleCluster.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [self.capsuleCluster.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8.0],
        [stack.topAnchor constraintEqualToAnchor:self.capsuleCluster.topAnchor constant:6.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.capsuleCluster.bottomAnchor constant:-6.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.capsuleCluster.leadingAnchor constant:6.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.capsuleCluster.trailingAnchor constant:-6.0],
        // 标题尾缘让位胶囊（ame_buildBareShell 同源）
        [self.headerTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.capsuleCluster.leadingAnchor constant:-12.0],
    ]];
    [self.view bringSubviewToFront:self.capsuleCluster];
}

// ── nav 左窗格（fui NavigationView 镜像：折叠 64 / 展开 280 双态；★Task416
//   图标 24pt 两态恒定 + leading 恒 14 = 折叠不调图标大小的同帧图证）──
- (void)ame414_buildNavPane {
    BOOL ame416_expanded = self.ame416_paneExpanded;
    CGFloat ame416_paneW = ame416_expanded ? 280.0 : 64.0;
    self.paneWrap = [[UIView alloc] init];
    self.paneWrap.backgroundColor = [ZL2Theme surfaceContainerLow];
    self.paneWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.paneWrap];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24];
    UIView *toggle = [[UIView alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.paneWrap addSubview:toggle];
    UIImage *tglImg = [UIImage systemImageNamed:@"sidebar.leading" withConfiguration:config];
    if (tglImg) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[tglImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        iv.tintColor = [ZL2Theme onSurface];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.userInteractionEnabled = NO;
        [toggle addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.centerXAnchor constraintEqualToAnchor:toggle.centerXAnchor],
            [iv.centerYAnchor constraintEqualToAnchor:toggle.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:24.0],
            [iv.heightAnchor constraintEqualToConstant:24.0],
        ]];
    }

    // 五主导航（ame389 镜像：图标 24pt 两态恒定 / 行 44 / 选中 Highest 抬升；
    // 展开态补文字标签 = 真壳 ZL2ShellNavItem 同构）
    NSArray<NSNumber *> *pages = @[@0, @1, @2, @4, @6];   // ★Task414 显式泛型 = id 点语法判例（run 42487051782 族）规避
    NSArray<NSString *> *symbols = @[@"house.fill", @"arrow.down.circle.fill",
                                     @"shippingbox.fill", @"gearshape.fill", @"sparkles"];
    NSArray<NSString *> *titles = @[localize(@"ame369.common.home", @"主页"), localize(@"ame369.shell.tab.downloads", @"下载"),
                                    localize(@"ame369.shell.tab.versions", @"版本"), localize(@"ame192.ai.title", @"AI 助手"),
                                    localize(@"ame369.shell.tab.settings", @"设置")];   // ★Task416 全键复用既有 ame369 四表键（零新键）
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    UIView *ame414_prev = nil;
    for (NSUInteger i = 0; i < symbols.count; i++) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.layer.cornerRadius = 8.0;
        row.backgroundColor = [UIColor clearColor];
        // ★Task416 图标：leading 恒 14 + 24×24 两态不变（与真壳 ame402 同口径）
        UIImage *img = [UIImage systemImageNamed:symbols[i] withConfiguration:config];
        UIImageView *ame416_rowIcon = nil;
        if (img) {
            ame416_rowIcon = [[UIImageView alloc] initWithImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            ame416_rowIcon.tag = 100;   // 预览 harness 内部查找（非交互纯视觉；正式壳零 tag 红线不适用于 harness 镜像）
            ame416_rowIcon.tintColor = [ZL2Theme onSurfaceVariant];   // ★Task416：显式着色（默认蓝在暗板失真，真壳 nav 项同口径）
            ame416_rowIcon.contentMode = UIViewContentModeScaleAspectFit;
            ame416_rowIcon.translatesAutoresizingMaskIntoConstraints = NO;
            ame416_rowIcon.userInteractionEnabled = NO;
            [row addSubview:ame416_rowIcon];
            [NSLayoutConstraint activateConstraints:@[
                [ame416_rowIcon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
                [ame416_rowIcon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [ame416_rowIcon.widthAnchor constraintEqualToConstant:24.0],
                [ame416_rowIcon.heightAnchor constraintEqualToConstant:24.0],
            ]];
        }
        if (ame416_expanded) {
            UILabel *lb = [[UILabel alloc] init];
            lb.text = titles[i];
            lb.font = [ZL2Theme fontBodyMedium];
            lb.textColor = [ZL2Theme onSurface];
            lb.translatesAutoresizingMaskIntoConstraints = NO;
            lb.userInteractionEnabled = NO;
            [row addSubview:lb];
            [NSLayoutConstraint activateConstraints:@[
                [lb.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:52.0],
                [lb.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [lb.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-12.0],
            ]];
        }
        [self.paneWrap addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.widthAnchor constraintEqualToAnchor:self.paneWrap.widthAnchor constant:-12.0],
            [row.heightAnchor constraintEqualToConstant:44.0],
            [row.centerXAnchor constraintEqualToAnchor:self.paneWrap.centerXAnchor],
        ]];
        if (ame414_prev) {
            [NSLayoutConstraint activateConstraints:@[
                [row.topAnchor constraintEqualToAnchor:ame414_prev.bottomAnchor constant:2.0],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [row.topAnchor constraintEqualToAnchor:toggle.bottomAnchor constant:10.0],
            ]];
        }
        ame414_prev = row;
        ame414_prevBottomConstant = 0.0;
        row.tag = pages[i].integerValue;   // 页映射预选态刷新用（harness 内部）
        [items addObject:row];
    }

    // 底部固定（设置/文件，同壳 paneFooterStack 口径；展开态 leading 14 对齐行图标）
    UIImage *gearImg = [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:config];
    UIImage *folderImg = [UIImage systemImageNamed:@"folder.fill" withConfiguration:config];
    UIImageView *footerA = [[UIImageView alloc] initWithImage:[gearImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    UIImageView *footerB = [[UIImageView alloc] initWithImage:[folderImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    for (UIImageView *fv in @[footerA, footerB]) {
        fv.tintColor = [ZL2Theme onSurfaceVariant];
        fv.contentMode = UIViewContentModeScaleAspectFit;
        fv.translatesAutoresizingMaskIntoConstraints = NO;
        fv.userInteractionEnabled = NO;
        [self.paneWrap addSubview:fv];
        [NSLayoutConstraint activateConstraints:@[
            ame416_expanded
                ? (NSLayoutConstraint *)[fv.leadingAnchor constraintEqualToAnchor:self.paneWrap.leadingAnchor constant:14.0]
                : (NSLayoutConstraint *)[fv.centerXAnchor constraintEqualToAnchor:self.paneWrap.centerXAnchor],
            [fv.widthAnchor constraintEqualToConstant:24.0],
            [fv.heightAnchor constraintEqualToConstant:24.0],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.paneWrap.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.paneWrap.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.paneWrap.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.paneWrap.widthAnchor constraintEqualToConstant:ame416_paneW],
        [toggle.topAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.topAnchor constant:10.0],
        [toggle.leadingAnchor constraintEqualToAnchor:self.paneWrap.leadingAnchor constant:16.0],
        [toggle.widthAnchor constraintEqualToConstant:32.0],
        [toggle.heightAnchor constraintEqualToConstant:32.0],
        [footerA.bottomAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.bottomAnchor constant:-40.0],
        [footerB.bottomAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
    ]];
    [self.view bringSubviewToFront:self.paneWrap];
    self.paneItems = items;
}

// 壳态刷新（★Task414 双骨架同源：大标题 + 胶囊/窗格选中态）
- (void)ame414_refreshShellForIndex:(NSInteger)index {
    self.headerTitle.text = AmePreviewPageTitle(index);
    // bare 胶囊选中（pages = 0,1,5,6,4,-1）
    NSArray<NSNumber *> *capsulePages = @[@0, @1, @5, @6, @4, @(-1)];   // 显式泛型 = id 点语法判例规避
    [self.capsuleButtons enumerateObjectsUsingBlock:^(UIView *btn, NSUInteger i, BOOL *stop) {
        BOOL selected = (capsulePages[i].integerValue == index);
        btn.backgroundColor = selected ? [ZL2Theme surfaceContainerHigh] : [UIColor clearColor];
        UIImageView *iv = btn.subviews.firstObject;
        if ([iv isKindOfClass:[UIImageView class]]) {
            iv.tintColor = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
        }
    }];
    // nav 窗格选中（surfaceContainerHighest 抬升 = ★Task414 对比度根修镜像）
    [self.paneItems enumerateObjectsUsingBlock:^(UIView *row, NSUInteger i, BOOL *stop) {
        BOOL selected = (row.tag == index);
        row.backgroundColor = selected ? [ZL2Theme surfaceContainerHighest] : [UIColor clearColor];
        UIImageView *iv = [row viewWithTag:100];
        if ([iv isKindOfClass:[UIImageView class]]) {
            iv.tintColor = selected ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
        }
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
    [self ame414_refreshShellForIndex:index];
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
    // ★ Task393：预览沙盒（假账户/假版本实体 + POJAV_HOME）先行于任何页面
    AmePreviewPrepareSandbox();

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [ZL2Theme surface];

    // ★Task414：根 = ZL2 壳真形态镜像（bare 顶带/nav 双骨架 + 五槽内容区；
    // -zl2page 选页 home/download/versions/accounts/settings）
    UIViewController *root = [[AmePreviewShellController alloc] init];

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    // ★ Task400：versionpicker 延迟总线弹层块随弹层退役（版本滚轮随主页
    //   右栏直接呈现，无呈现时序）
    return YES;
}

// iOS 16+ 场景化几何更新：preferredInterfaceOrientationForPresentation 在新
// runtime（CI 26.2 实证）对经典生命周期 app 被弱化——启动仍竖屏。官方正解是
// 显式请求几何更新（supportedInterfaceOrientations 双侧横屏收敛仍保留，为
// iOS 14/15 老路径与本请求的合法性背书）。@available 门护，仅 harness 生效。
- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = self.window.windowScene;
        if (!scene && application.connectedScenes.count > 0) {
            scene = (UIWindowScene *)application.connectedScenes.anyObject;
        }
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc]
                    initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:nil];
            [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AmePreviewAppDelegate class]));
    }
}
