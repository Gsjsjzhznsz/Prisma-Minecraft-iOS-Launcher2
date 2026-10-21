//
// ZL2PagesStub.m — ZL2 四功能页（7.0-UI-9）预览 harness 链接期桩 TU
//
// 服务对象：scripts/ui_fluent_smoke.sh preview 编译的 AmeFluentPreview——
//   7.0-UI-9-e 起 rail 槽位 1-4 换装真实四页（ZL2DownloadViewController /
//   ZL2VersionsViewController / ZL2AccountsViewController /
//   ZL2SettingsViewController），四页自身引用的目标 VC / 管理器类 / C 函数 /
//   extern 常量在本 TU 打桩（正式构建用真实现，桩与真实现从不同一二进制）。
//
// 分账纪律（7.0-UI-8 判例，重复定义 = duplicate symbol 链接失败）：
//   - AmeFluentPreviewMain.m 既有桩（localize / accentColor / getPrefObject /
//     BackgroundManager / BaseAuthenticator / PLProfiles /
//     MinecraftResourceDownloadTask / DownloadTaskManager / DownloadTaskItem /
//     PLTaskProgressViewController）全在 main TU，本 TU 零重复；
//     四页需要的既有桩缺口方法（PLProfiles +updateCurrent /
//     -setSelectedProfileName:、DownloadTaskManager -tasksWithStates:、
//     DownloadTaskItem state/progress、BaseAuthenticator +setCurrent: /
//     +loadSavedName: / -initWithInput: / -loginWithCallback: /
//     -refreshTokenWithCallback:）已直接在 main TU 原桩上补齐，不在本 TU 重定义；
//   - 目标 VC 桩一律不 import 真实类头（避免桩声明与真实声明冲突），手写同名
//     类声明 + 空实现即可：截图流程不点按钮、不 push/present 子页，桩仅满足
//     链接期符号（方法调用是运行时动态绑定，链接期只需要类名与 C 符号）；
//   - C 函数桩 import 真实声明头（LauncherPreferences.h / utils.h）后定义，
//     签名由编译器对表；extern 常量按真实 .m 的字面量值定义一次；
//   - BaseAuthenticator 类本体在 main TU——本 TU 仅以其为超类锚点子类化
//     （LocalAuthenticator / MicrosoftAuthenticator / ThirdPartyAuthenticator，
//     与真实头同构），超类方法零重复实现。
//
// 7.0-UI-10-f 增量：下载页六类接入 ZL2AssetSearchViewController（7.0-UI-10-a，
//   真实 .m 进预览编译）后，其全部外部符号按同一纪律落桩：
//   - 新增类桩 23 个（API 双源 / 四 Item / 两版本模型 / 三版本页 VC / 四
//     Service / 依赖解析三件 / PLTaskStage / PLMirrorCenter /
//     ForgeDirectInstaller / ModpackImportService / IconLoader /
//     InlineMessageView / PLPreferences）——全部手写同名类声明 + 空实现，
//     不 import 真实类头；
//   - 既有桩补缺口 = ObjC category（本轮唯一可改 TU 是本文件，main TU 桩
//     原位零触碰）：DownloadTaskManager 补 registerTaskWithResourceType 七参
//     + setTaskWithId 三变体 + updateTaskWithId 三变体；DownloadTaskItem 补
//     autoPresentDetail；MinecraftResourceDownloadTask 补 maxRetryCount；
//     PLProfiles 补 selectedProfile——category 只增方法/属性，零重复定义；
//   - NS_ENUM / NS_OPTIONS / NS_INLINE（PLTaskStageStatus 五态、
//     DownloadTaskState、PLMirrorResourceType、AssetVersionType、
//     IconLoaderOptions、InlineMessageType、PLTaskStagesModpack()）均为真实
//     头内声明，消费方 TU 编译期内联，无链接符号勿桩；唯 PLTaskStagesModpack()
//     内联体引用 [PLTaskStage stageWithTitle:iconName:] → PLTaskStage 类符号
//     必须由本 TU 提供；
//   - ZL2AssetSearchViewController.m 的 ModrinthAPI.h/CurseForgeAPI.h import
//     已做外科手术（传递链 ModpackAPI.h→ModpackUtils.h→UnzipKit.h 在 harness
//     的 -I（仅 Natives 根）下不可达，与 AFNetworking submodule 判例 365219f
//     同源）：.m 内以本地最小 @interface 替代（签名照抄真实 .h 逐条对表），
//     逻辑零改动；本 TU 的同名类桩与其声明选择器一一对应。
//
// 红线：颜色不落（无新建视图）；translates 全默认（无新建视图）；iOS 14.0+
// API；LF 行尾；本文件不进 Natives/CMakeLists.txt（仅 ui-smoke 特例编译）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>          // category 补属性（autoPresentDetail/maxRetryCount）的关联对象存储
#import "LauncherPreferences.h"   // getSelectedJavaHome / setPrefObject / getPrefBool / setPrefBool 声明
#import "utils.h"                 // parseJSONFromFile 声明

#pragma mark - 下载页六类目标 VC 空桩（ZL2DownloadViewController 懒建嵌入）

@interface DownloadViewController : UIViewController
@end

@implementation DownloadViewController
@end

@interface ModpackImportViewController : UIViewController
@end

@implementation ModpackImportViewController
@end

@interface ModsManagerViewController : UIViewController
@end

@implementation ModsManagerViewController
@end

@interface ResourcePacksManagerViewController : UIViewController
@end

@implementation ResourcePacksManagerViewController
@end

@interface WorldsManagerViewController : UIViewController
@end

@implementation WorldsManagerViewController
@end

@interface ShadersManagerViewController : UIViewController
@end

@implementation ShadersManagerViewController
@end

#pragma mark - 版本页依赖桩（设置按钮 push 目标 + 加载器识别 / MC 版本反解）

// ProfileSettingsViewController：[[alloc] init] + profileName 属性（旧 VC
// editProfile: 同款；真实页自身有完整数据面，桩空壳即可——截图流程不 push）
@interface ProfileSettingsViewController : UIViewController
@property(nonatomic, copy, nullable) NSString *profileName;
@end

@implementation ProfileSettingsViewController
@end

// ModLoaderIconHelper：版本卡加载器识别单一契约（detectLoaderFromVersionId
// 计数 + configureImageView 图标 + displayNameForLoader 标签）。桩全空：
// 空注册表 → 计数 0 + 图标走页面 gamecontroller 兜底容器，空态不受影响
@interface ModLoaderIconHelper : NSObject
+ (nullable NSString *)detectLoaderFromVersionId:(NSString *)versionId;
+ (nullable NSString *)displayNameForLoader:(NSString *)loader;
+ (nullable UIImage *)iconImageForLoader:(NSString *)loader
                         traitCollection:(nullable UITraitCollection *)traitCollection;
+ (void)configureImageView:(UIImageView *)imageView
                 forLoader:(NSString *)loader
           traitCollection:(nullable UITraitCollection *)traitCollection;
@end

@implementation ModLoaderIconHelper

+ (nullable NSString *)detectLoaderFromVersionId:(NSString *)versionId {
    return nil;
}

+ (nullable NSString *)displayNameForLoader:(NSString *)loader {
    return loader;
}

+ (nullable UIImage *)iconImageForLoader:(NSString *)loader
                         traitCollection:(nullable UITraitCollection *)traitCollection {
    return nil;
}

+ (void)configureImageView:(UIImageView *)imageView
                 forLoader:(NSString *)loader
           traitCollection:(nullable UITraitCollection *)traitCollection {
}

@end

// ModpackExportService：+parseVersionId:（lastVersionId 反解 MC 版本）。
// 桩返回 nil → 版本卡标签行走「无 MC 版本」分支（截图为空态，不触达）
@interface ModpackExportService : NSObject
+ (nullable NSDictionary *)parseVersionId:(NSString *)versionId;
@end

@implementation ModpackExportService

+ (nullable NSDictionary *)parseVersionId:(NSString *)versionId {
    return nil;
}

@end

#pragma mark - 账户页依赖桩（authenticator 家族 / 第三方登录页 / 头像 / toast）

// 超类锚点：BaseAuthenticator 类本体在 AmeFluentPreviewMain.m 桩 TU（7.0-UI-8，
// 本轮已补 +setCurrent:/+loadSavedName:/-initWithInput:/-loginWithCallback:/
// -refreshTokenWithCallback:）。本 TU 只声明可见超类供子类化，不重复实现。
@interface BaseAuthenticator : NSObject
@end

@interface LocalAuthenticator : BaseAuthenticator
@end

@implementation LocalAuthenticator
@end

@interface MicrosoftAuthenticator : BaseAuthenticator
+ (void)clearTokenDataOfProfile:(NSString *)profile;
@end

@implementation MicrosoftAuthenticator

+ (void)clearTokenDataOfProfile:(NSString *)profile {
}

@end

@interface ThirdPartyAuthenticator : BaseAuthenticator
@end

@implementation ThirdPartyAuthenticator
@end

// ThirdPartyLoginViewController：[[alloc] init] + mode + onLoginComplete
//（LittleSkin / 自定义第三方登录卡片页；截图流程不进入登录流）
@interface ThirdPartyLoginViewController : UIViewController
@property(nonatomic, assign) NSInteger mode;
@property(nonatomic, copy, nullable) void (^onLoginComplete)(BOOL success, NSString *errorMessage);
@end

@implementation ThirdPartyLoginViewController
@end

// AvatarManager：sharedManager 单例 + ame185 异步取图（三层回退链）。桩恒
// 异步回调 nil 图 → 账户行/视觉卡走 person.crop.circle.fill 占位（空沙盒
// 无账号文件，本桩实际不会被触达，仍按空安全实现）
@interface AvatarManager : NSObject
+ (instancetype)sharedManager;
- (void)ame185_fetchAvatarForAuthData:(NSDictionary *)authData
                           completion:(void (^)(UIImage *image))completion;
@end

@implementation AvatarManager

+ (instancetype)sharedManager {
    static AvatarManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[AvatarManager alloc] init];
    });
    return manager;
}

- (void)ame185_fetchAvatarForAuthData:(NSDictionary *)authData
                           completion:(void (^)(UIImage *image))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil);
    });
}

@end

// NMToast：showMessage: / showMessage:duration:（Task126 应用内通知）。
// 预览不弹 toast（选中链/登录流的提示路径，截图流程不触达）
@interface NMToast : NSObject
+ (void)showMessage:(NSString *)message;
+ (void)showMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

@implementation NMToast

+ (void)showMessage:(NSString *)message {
}

+ (void)showMessage:(NSString *)message duration:(NSTimeInterval)duration {
}

@end

#pragma mark - 设置页十二行目标 VC 空桩（ZL2SettingsViewController push 表）

@interface LauncherPreferencesViewController : UIViewController
@end

@implementation LauncherPreferencesViewController
@end

@interface BackgroundSettingsViewController : UIViewController
@end

@implementation BackgroundSettingsViewController
@end

// BingWallpaperGalleryViewController：+galleryController 类工厂（Task151）。
// 桩返回 nil（行点击仅截图流程不触达；返回类型放宽到 UIViewController 与
// 调用方 `UIViewController *vc = [X galleryController]` 同构）
@interface BingWallpaperGalleryViewController : UIViewController
+ (nullable UIViewController *)galleryController;
@end

@implementation BingWallpaperGalleryViewController

+ (nullable UIViewController *)galleryController {
    return nil;
}

@end

@interface LauncherPrefContCfgViewController : UIViewController
@end

@implementation LauncherPrefContCfgViewController
@end

@interface TouchControllerPreferencesViewController : UIViewController
@end

@implementation TouchControllerPreferencesViewController
@end

@interface LauncherPrefGameDirViewController : UIViewController
@end

@implementation LauncherPrefGameDirViewController
@end

@interface LauncherPrefManageJREViewController : UIViewController
@end

@implementation LauncherPrefManageJREViewController
@end

// JavaGUIViewController：模态专用页（filepath 必填 + hitEnterAfterWindowShown
// 自定义 setter + requiredJavaVersion 只读 getter 解析 MANIFEST）。桩恒 0 →
// 设置页执行 Jar 守卫链走「版本解析失败」提示分支（截图流程不触达）
@interface JavaGUIViewController : UIViewController
@property(nonatomic) NSString *filepath;
@property(nonatomic, readonly) int requiredJavaVersion;
- (void)setHitEnterAfterWindowShown:(BOOL)hitEnter;
@end

@implementation JavaGUIViewController

- (void)setHitEnterAfterWindowShown:(BOOL)hitEnter {
}

@end

@interface DataExportViewController : UIViewController
@end

@implementation DataExportViewController
@end

// CleanupViewController：init + ame255_versionScanner 注入（扫描器由调用方
// 注入避免 Cleanup → VersionManager 头依赖，真实页同款块签名）
@interface CleanupViewController : UITableViewController
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> *(^ame255_versionScanner)(void);
@end

@implementation CleanupViewController
@end

@interface CurseForgeAPIKeyViewController : UIViewController
@end

@implementation CurseForgeAPIKeyViewController
@end

@interface AboutViewController : UIViewController
@end

@implementation AboutViewController
@end

// VersionManagerViewController：仅消费 +ame256_scanVersionsForCleanup 类方法
//（主页磁贴/清理页共用的扫描单一实现）——桩返回 nil，避免链接整个旧 VC
@interface VersionManagerViewController : UIViewController
+ (nullable NSArray<NSDictionary *> *)ame256_scanVersionsForCleanup;
@end

@implementation VersionManagerViewController

+ (nullable NSArray<NSDictionary *> *)ame256_scanVersionsForCleanup {
    return nil;
}

@end

#pragma mark - C 函数桩（签名对真实头，定义各一次）

// LauncherPreferences.h: NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion);
// 预览无 JRE 注册表：恒 nil → 执行 Jar 行 JRE 预检走「未配置」提示分支
NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion) {
    return nil;
}

// LauncherPreferences.h: BOOL getPrefBool(NSString *key);
// 预览无偏好存储：恒 NO（账户页 warnings.local_warn 守卫走默认分支）
BOOL getPrefBool(NSString *key) {
    return NO;
}

// LauncherPreferences.h: void setPrefObject(NSString *key, id value);
// 预览无偏好存储：no-op（选中链 internal.selected_account 写入落空即安全）
void setPrefObject(NSString *key, id value) {
}

// LauncherPreferences.h: void setPrefBool(NSString *key, BOOL value);
void setPrefBool(NSString *key, BOOL value) {
}

// utils.h: NSMutableDictionary* parseJSONFromFile(NSString *path);
// 预览沙盒无账户文件：恒 nil——消费方对 nil / @{@"NSErrorObject":...} 双态
// 都有守卫（Task180 读侧兜底），nil → 空账户列表
NSMutableDictionary* parseJSONFromFile(NSString *path) {
    return nil;
}

#pragma mark - extern 常量桩（定义各一次，字面量值照抄真实 .m）

// DownloadTaskManager.h 声明（DownloadTaskManager.m L7-8 原值）。manager 本体
// 在 main TU 是空桩、永不 post，值仅保真
NSString * const DownloadTaskManagerDidUpdateTaskNotification = @"com.amethyst.DownloadTaskManager.DidUpdateTask";
NSString * const DownloadTaskManagerAggregateStateDidChangeNotification = @"com.amethyst.DownloadTaskManager.AggregateStateDidChange";

// AFNetworking.h 声明（AFURLResponseSerialization.m 原值照抄）。预览无网络层，
// 该键仅出现在登录失败弹窗的 userInfo 取值路径（nil 字典 → nil，空安全）
NSString * const AFNetworkingOperationFailingURLResponseDataErrorKey = @"com.alamofire.error.serialization.response.data.response";

// utils.h 的 customNSLog（utils.h L20 把 NSLog 宏重定向到它，L358 声明）。
// 版本/账户页的日志调用经宏落到此符号；预览环境静音实现（CI 截图不读日志）
void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...) {
    (void)file; (void)lineNumber; (void)functionName; (void)format;
}

#pragma mark - 下载页远程搜索链路桩（7.0-UI-10-f：ZL2AssetSearchViewController 外部符号）

// 7.0-UI-10-a 起下载页五类消费 ZL2AssetSearchViewController（真实 .m 进预览
// 编译），其全部外部符号在本节落桩（分账见文件头）。桩实现口径沿 9-e：异步
// 回调给空数据（nil / 空数组 / NO），消费方全部有 nil/空守卫（逐一核对）；
// 截图流程为空态引导，不触达搜索/下载/安装/依赖链路。

#pragma mark 版本模型（ModVersion.h / ShaderVersion.h；点击→版本页回调与依赖挑选消费）

// 版本页回调携带的数据模型。预览搜索桩恒空结果，实例不会被创建；
// 类桩仍给全消费面属性（readonly 照真实头），满足链接期类符号。
@interface ModVersion : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSArray<NSString *> *gameVersions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *loaders;
@property (nonatomic, copy, readonly, nullable) NSDictionary *primaryFile;
@property (nonatomic, assign) NSInteger apiSource;
@property (nonatomic, copy, nullable) NSDictionary *rawDictionary;
@end

@implementation ModVersion
@end

@interface ShaderVersion : NSObject
@property (nonatomic, copy, readonly, nullable) NSDictionary *primaryFile;
@end

@implementation ShaderVersion
@end

#pragma mark API 双源（installer/modpack/ModrinthAPI.h、CurseForgeAPI.h 签名照抄；
#pragma mark 消费方 .m 在 #import 手术后以本地最小类声明对表，选择器一一对应）

@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)ame227_fetchProjectTitle:(NSString *)projectID
                      completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

@implementation ModrinthAPI

+ (instancetype)sharedInstance {
    static ModrinthAPI *api = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ api = [[ModrinthAPI alloc] init]; });
    return api;
}

// 预览无网络层：异步空结果（results.count >= 30 判定 → hasMore=NO，空态收口）
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], nil); });
}

// 依赖确认单名称 enrichment：回调 nil → 消费方回退 projectId（守卫已核对）
- (void)ame227_fetchProjectTitle:(NSString *)projectID
                      completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
}

// 依赖挑选链：回调 nil → 消费方记 failure 后 nextStep 收口（守卫已核对）
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
}

@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)ame227_fetchModTitle:(NSString *)modID
                  completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

@implementation CurseForgeAPI

+ (instancetype)sharedInstance {
    static CurseForgeAPI *api = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ api = [[CurseForgeAPI alloc] init]; });
    return api;
}

// 恒可用（真实现语义：key 仅官方直连需要，未配 key 落 MCIM 镜像对所有人可用；
// Task162）。恒 YES 使存档 tab 走搜索空态引导而非「源不可用」裸键空态
//（i18n_str_185 不在预览 localize 桩表内，避免截图出现裸键名）
+ (BOOL)isSourceAvailable {
    return YES;
}

- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], nil); });
}

- (void)ame227_fetchModTitle:(NSString *)modID
                  completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
}

- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
}

@end

#pragma mark 在线数据模型四件（ModItem.h / ShaderItem.h / ResourcePackItem.h / WorldItem.h）

// initWithOnlineData: 预览空解析（不触达）；属性覆盖消费面全部读写点
//（结果卡点击→版本页配置 + 下载前 selectedVersionDownloadURL/fileName/fileSHA1 回填）

@interface ModItem : NSObject
@property (nonatomic, copy, nullable) NSString *onlineID;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSNumber *downloads;
@property (nonatomic, strong, nullable) NSNumber *likes;
@property (nonatomic, copy, nullable) NSString *lastUpdated;
@property (nonatomic, strong, nullable) NSArray<NSString *> *categories;
@property (nonatomic, copy, nullable) NSString *selectedVersionDownloadURL;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *modDescription;
@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *fileSHA1;
- (instancetype)initWithOnlineData:(NSDictionary *)data;
@end

@implementation ModItem

- (instancetype)initWithOnlineData:(NSDictionary *)data {
    self = [super init];
    return self;
}

@end

@interface ShaderItem : NSObject
@property (nonatomic, copy, nullable) NSString *onlineID;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *shaderDescription;
@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic, copy, nullable) NSString *selectedVersionDownloadURL;
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *fileSHA1;
- (instancetype)initWithOnlineData:(NSDictionary *)data;
@end

@implementation ShaderItem

- (instancetype)initWithOnlineData:(NSDictionary *)data {
    self = [super init];
    return self;
}

@end

@interface ResourcePackItem : NSObject
@property (nonatomic, copy, nullable) NSString *onlineID;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSNumber *downloads;
@property (nonatomic, strong, nullable) NSNumber *likes;
@property (nonatomic, copy, nullable) NSString *lastUpdated;
@property (nonatomic, strong, nullable) NSArray<NSString *> *categories;
@property (nonatomic, copy, nullable) NSString *selectedVersionDownloadURL;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *resourcePackDescription;
@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *fileSHA1;
- (instancetype)initWithOnlineData:(NSDictionary *)data;
@end

@implementation ResourcePackItem

- (instancetype)initWithOnlineData:(NSDictionary *)data {
    self = [super init];
    return self;
}

@end

@interface WorldItem : NSObject
@property (nonatomic, copy, nullable) NSString *onlineID;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSNumber *downloads;
@property (nonatomic, strong, nullable) NSNumber *likes;
@property (nonatomic, copy, nullable) NSString *lastUpdated;
@property (nonatomic, strong, nullable) NSArray<NSString *> *categories;
@property (nonatomic, copy, nullable) NSString *selectedVersionDownloadURL;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *worldDescription;
@property (nonatomic, copy, nullable) NSString *iconURL;
- (instancetype)initWithOnlineData:(NSDictionary *)data;
@end

@implementation WorldItem

- (instancetype)initWithOnlineData:(NSDictionary *)data {
    self = [super init];
    return self;
}

@end

#pragma mark 版本页 VC 三件（ModVersionViewController.h / ShaderVersionViewController.h /
#pragma mark AssetVersionViewController.h；delegate 属性类型照真实 .h = id<协议>，
#pragma mark 协议本体在真实 .h → 消费方 TU 自含，桩 TU 空声明同名兜底）

// AssetVersionType 枚举照真实 .h（本 TU 本地 typedef，消费方 TU 内联自头，无链接符号）
typedef NS_ENUM(NSInteger, AssetVersionType) {
    AssetVersionTypeResourcePack = 0,
    AssetVersionTypeDataPack = 1,
    AssetVersionTypeWorld = 2,
};

@protocol ModVersionViewControllerDelegate <NSObject>
@end

@interface ModVersionViewController : UIViewController
@property (nonatomic, strong, nullable) ModItem *modItem;
@property (nonatomic, weak, nullable) id<ModVersionViewControllerDelegate> delegate;
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;
@property (nonatomic, copy, nullable) NSString *preferredLoader;
@property (nonatomic, assign) NSInteger apiSource;
@end

@implementation ModVersionViewController
@end

@protocol ShaderVersionViewControllerDelegate <NSObject>
@end

@interface ShaderVersionViewController : UIViewController
@property (nonatomic, strong, nullable) ShaderItem *shaderItem;
@property (nonatomic, weak, nullable) id<ShaderVersionViewControllerDelegate> delegate;
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;
@property (nonatomic, copy, nullable) NSString *preferredLoader;
@property (nonatomic, assign) NSInteger apiSource;
@end

@implementation ShaderVersionViewController
@end

@protocol AssetVersionViewControllerDelegate <NSObject>
@end

@interface AssetVersionViewController : UIViewController
@property (nonatomic, assign) AssetVersionType assetType;
@property (nonatomic, copy, nullable) NSString *projectID;
@property (nonatomic, copy, nullable) NSString *projectDisplayName;
@property (nonatomic, weak, nullable) id<AssetVersionViewControllerDelegate> delegate;
@property (nonatomic, assign) NSInteger apiSource;
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;
@property (nonatomic, copy, nullable) NSString *projectIconURL;
@property (nonatomic, copy, nullable) NSString *projectAuthor;
@property (nonatomic, strong, nullable) NSNumber *projectDownloads;
@property (nonatomic, strong, nullable) NSNumber *projectLikes;
@property (nonatomic, copy, nullable) NSString *projectDescription;
@property (nonatomic, strong, nullable) NSArray<NSString *> *projectCategories;
@property (nonatomic, copy, nullable) NSString *projectLastUpdated;
@end

@implementation AssetVersionViewController
@end

#pragma mark 下载服务四件（ModService.h / ShaderService.h / ResourcePackService.h / WorldService.h）
// 各 download 签名照真实 .h（Mod/Shader 带 expectedSHA1 且 completion 只给
// NSError；ResourcePack/World completion 给 (BOOL success, NSError *)，World
// 无 expectedSHA1）。预览回调成功空数据 → 消费方走成功 toast（InlineMessageView 桩静默）

@interface ModService : NSObject
+ (instancetype)sharedService;
- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
       expectedSHA1:(nullable NSString *)expectedSHA1
           progress:(nullable void (^)(NSProgress *downloadProgress))progress
         completion:(void (^)(NSError * _Nullable error))completion;
@end

@implementation ModService

+ (instancetype)sharedService {
    static ModService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[ModService alloc] init]; });
    return service;
}

- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
       expectedSHA1:(nullable NSString *)expectedSHA1
           progress:(nullable void (^)(NSProgress *downloadProgress))progress
         completion:(void (^)(NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
}

@end

@interface ShaderService : NSObject
+ (instancetype)sharedService;
- (void)downloadShader:(ShaderItem *)shader
             toProfile:(NSString *)profileName
          expectedSHA1:(nullable NSString *)expectedSHA1
              progress:(nullable void (^)(NSProgress *downloadProgress))progress
            completion:(void (^)(NSError * _Nullable error))completion;
@end

@implementation ShaderService

+ (instancetype)sharedService {
    static ShaderService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[ShaderService alloc] init]; });
    return service;
}

- (void)downloadShader:(ShaderItem *)shader
             toProfile:(NSString *)profileName
          expectedSHA1:(nullable NSString *)expectedSHA1
              progress:(nullable void (^)(NSProgress *downloadProgress))progress
            completion:(void (^)(NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
}

@end

@interface ResourcePackService : NSObject
+ (instancetype)sharedService;
- (void)downloadResourcePack:(ResourcePackItem *)item
                   toProfile:(NSString *)profileName
                expectedSHA1:(nullable NSString *)expectedSHA1
                    progress:(nullable void (^)(NSProgress * _Nullable downloadProgress))progress
                  completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;
@end

@implementation ResourcePackService

+ (instancetype)sharedService {
    static ResourcePackService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[ResourcePackService alloc] init]; });
    return service;
}

- (void)downloadResourcePack:(ResourcePackItem *)item
                   toProfile:(NSString *)profileName
                expectedSHA1:(nullable NSString *)expectedSHA1
                    progress:(nullable void (^)(NSProgress * _Nullable downloadProgress))progress
                  completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
}

@end

@interface WorldService : NSObject
+ (instancetype)sharedService;
- (void)downloadWorld:(WorldItem *)item
            toProfile:(NSString *)profileName
             progress:(nullable void (^)(NSProgress * _Nullable downloadProgress))progress
           completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;
@end

@implementation WorldService

+ (instancetype)sharedService {
    static WorldService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[WorldService alloc] init]; });
    return service;
}

- (void)downloadWorld:(WorldItem *)item
            toProfile:(NSString *)profileName
             progress:(nullable void (^)(NSProgress * _Nullable downloadProgress))progress
           completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
}

@end

#pragma mark 依赖解析三件（ModDependencyResolver.h；Task227 下载前置链）
// resolve 回调 plan 必不为 nil（真实头注释契约）→ 空数组依赖 = 零前置直下，
// 消费方跳过确认单（planned 空态路径，与无依赖 mod 同款收口）

// Item 先于 Plan：Plan 的属性泛型 NSArray<ModDependencyItem *> 引用其类型名
//（真实头同为 Item 前置的声明序）
@interface ModDependencyItem : NSObject
@property (nonatomic, assign) NSInteger apiSource;
@property (nonatomic, copy, nullable) NSString *projectId;
@property (nonatomic, copy, nullable) NSString *displayName;
@end

@implementation ModDependencyItem
@end

@interface ModDependencyPlan : NSObject
@property (nonatomic, copy, nullable) NSArray<ModDependencyItem *> *required;
@property (nonatomic, copy, nullable) NSArray<ModDependencyItem *> *optional;
@property (nonatomic, copy, nullable) NSArray<NSString *> *truncated;
@end

@implementation ModDependencyPlan
@end

@interface ModDependencyResolver : NSObject
+ (instancetype)sharedResolver;
- (void)resolveDependenciesFromVersionDetail:(nullable NSDictionary *)versionDetail
                                   apiSource:(NSInteger)apiSource
                        installedProjectIds:(nullable NSSet<NSString *> *)installedProjectIds
                                      loader:(nullable NSString *)loader
                                 gameVersion:(nullable NSString *)gameVersion
                                  completion:(void (^)(ModDependencyPlan *plan, NSError * _Nullable error))completion;
@end

@implementation ModDependencyResolver

+ (instancetype)sharedResolver {
    static ModDependencyResolver *resolver = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ resolver = [[ModDependencyResolver alloc] init]; });
    return resolver;
}

- (void)resolveDependenciesFromVersionDetail:(nullable NSDictionary *)versionDetail
                                   apiSource:(NSInteger)apiSource
                        installedProjectIds:(nullable NSSet<NSString *> *)installedProjectIds
                                      loader:(nullable NSString *)loader
                                 gameVersion:(nullable NSString *)gameVersion
                                  completion:(void (^)(ModDependencyPlan *plan, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        ModDependencyPlan *plan = [[ModDependencyPlan alloc] init];
        plan.required = @[];
        plan.optional = @[];
        plan.truncated = @[];
        completion(plan, nil);
    });
}

@end

#pragma mark 任务阶段模型（PLTaskStage.h 类本体；PLTaskStages.h 的 NS_INLINE
#pragma mark PLTaskStagesModpack() 在消费方 TU 内联展开 → 需要 OBJC_CLASS_$_PLTaskStage）
// PLTaskStageStatus 五态为真实头 NS_ENUM（消费方 TU 编译期内联，无链接符号勿桩）；
// 本 TU 属性以 NSInteger 承载（同 ABI），阶段数据仅统一进度页渲染（本 harness 为
// presentForTaskId 空桩，不触达）

@interface PLTaskStage : NSObject
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *iconName;
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic, assign) double progress;
+ (instancetype)stageWithTitle:(NSString *)title iconName:(NSString *)iconName;
- (instancetype)initWithTitle:(NSString *)title iconName:(NSString *)iconName;
@end

@implementation PLTaskStage

+ (instancetype)stageWithTitle:(NSString *)title iconName:(NSString *)iconName {
    return [[PLTaskStage alloc] initWithTitle:title iconName:iconName];
}

- (instancetype)initWithTitle:(NSString *)title iconName:(NSString *)iconName {
    self = [super init];
    if (self) {
        _title = [title copy];
        _iconName = [iconName copy];
        _status = 0;    // PLTaskStageStatusPending
        _progress = -1; // 不确定进度（UI 流动动画约定）
    }
    return self;
}

@end

#pragma mark 镜像中心（PLMirrorCenter.h；Task218 下载来源展示 token）

// PLMirrorResourceType 枚举（含 PLMirrorResourceTypeAssetDownload）为真实头
// NS_ENUM → 消费方 TU 内联，无链接符号；桩参数以 NSInteger 承载（同 ABI）
@interface PLMirrorCenter : NSObject
+ (NSString *)legacySourceTokenForType:(NSInteger)type;
@end

@implementation PLMirrorCenter

// 真实现返回 official / bmclapi 旧式 token（仅展示字段）；manager 桩不读值
+ (NSString *)legacySourceTokenForType:(NSInteger)type {
    return @"official";
}

@end

#pragma mark Forge 直装器（installer/ForgeDirectInstaller.h；整合包原版预装门）

@interface ForgeDirectInstaller : NSObject
+ (BOOL)ensureParentVersionExists:(NSString *)minecraftVersion error:(NSError **)error;
@end

@implementation ForgeDirectInstaller

// 恒 NO → 原版预装走 completion(NO) 失败收口（消费方守卫已核对）。有意不返
// YES：YES 会继续进入 MinecraftResourceDownloadTask 下载 + 30min 轮询等待，
// 而该任务的演示桩 progress 永不 finished → 后台线程空转 30 分钟（预览环境
// 防呆优先；该链路截图不触达，仅链路符号必须齐）
+ (BOOL)ensureParentVersionExists:(NSString *)minecraftVersion error:(NSError **)error {
    return NO;
}

@end

#pragma mark 整合包导入服务（ModpackImportService.h；.mrpack/.zip 解析与导入）

@interface ModpackImportService : NSObject
- (nullable NSDictionary *)parseModpackAtURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)importModpack:(NSDictionary *)modpackInfo
             progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                error:(NSError **)error;
@end

@implementation ModpackImportService

// 预览无真实包：解析 nil → 消费方 setTaskWithId:completedWithError: 收口（桩
// manager no-op）+ InlineMessageView 提示（本桩静默）
- (nullable NSDictionary *)parseModpackAtURL:(NSURL *)fileURL error:(NSError **)error {
    return nil;
}

- (BOOL)importModpack:(NSDictionary *)modpackInfo
             progress:(void (^_Nullable)(double progress, NSString *stageMessage))progress
                error:(NSError **)error {
    return NO;
}

@end

#pragma mark 图标加载器（IconLoader.h；本仓自有异步图组件，无 SDWebImage 依赖）

@interface IconLoader : NSObject
+ (void)loadIconForImageView:(nullable UIImageView *)imageView
                         URL:(nullable NSString *)url
                 placeholder:(nullable UIImage *)placeholder
                    fallback:(nullable UIImage *)fallback
                  targetSize:(CGSize)targetSize
                     options:(NSUInteger)options
                  completion:(nullable void (^)(UIImage * _Nullable image))completion;
+ (void)prefetchIconWithURL:(NSString *)url targetSize:(CGSize)targetSize;
@end

@implementation IconLoader

// 恒命中"占位"分支：同步铺 placeholder ?: fallback（真实加载器对 nil URL 的
// 同款行为）→ 结果卡占位 SF 符号视觉成立；completion 异步 nil → 消费方守卫
//（!image return）不动 AspectFill 形态
+ (void)loadIconForImageView:(nullable UIImageView *)imageView
                         URL:(nullable NSString *)url
                 placeholder:(nullable UIImage *)placeholder
                    fallback:(nullable UIImage *)fallback
                  targetSize:(CGSize)targetSize
                     options:(NSUInteger)options
                  completion:(nullable void (^)(UIImage * _Nullable image))completion {
    if (imageView) imageView.image = placeholder ?: fallback;
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
}

+ (void)prefetchIconWithURL:(NSString *)url targetSize:(CGSize)targetSize {
}

@end

// IconLoaderOptions 为真实头 NS_OPTIONS（消费方 TU 内联，无链接符号勿桩）

#pragma mark 内联消息视图（InlineMessageView.h；旧页 showError/showSuccess 同款）

// InlineMessageType 为真实头 NS_ENUM（消费方 TU 内联，无链接符号勿桩）；本 TU
// 仅类方法签名需要类型名 → 本地 typedef（值与真实头一致）
typedef NS_ENUM(NSInteger, InlineMessageType) {
    InlineMessageTypeLoading = 0,
    InlineMessageTypeError,
    InlineMessageTypeSuccess,
    InlineMessageTypeInfo,
};

@interface InlineMessageView : UIView
+ (instancetype)showInViewController:(UIViewController *)viewController
                               title:(NSString *)title
                             message:(nullable NSString *)message
                                type:(InlineMessageType)type;
@end

@implementation InlineMessageView

// 预览不弹内联消息（返回 nil 即安全：消费方忽略返回值，仅驱动提示链路）
+ (instancetype)showInViewController:(UIViewController *)viewController
                               title:(NSString *)title
                             message:(nullable NSString *)message
                                type:(InlineMessageType)type {
    return nil;
}

@end

#pragma mark 偏好（PLPreferences.h；下载源口径）

@interface PLPreferences : NSObject
+ (NSString *)currentDownloadSourceForType:(NSString *)type;
@end

@implementation PLPreferences

// 非 "curseforge" 一律判 Modrinth（消费方 isEqualToString 守卫已核对）；
// 返回值仅影响搜索 API 选择，双源桩行为一致
+ (NSString *)currentDownloadSourceForType:(NSString *)type {
    return @"modrinth";
}

@end

#pragma mark - 既有桩缺口补齐（ObjC category：只增方法/属性，零重复定义）
// 本轮唯一可改 TU 是本文件 → main TU（AmeFluentPreviewMain.m）既有桩原位零
// 触碰，缺口以 category 在本 TU 补齐（9-e「补方法/补属性」纪律的等价形态）。
// 类本体符号仍由 main TU 提供：本节先给最小类声明（仅 category 编译所需），
// 不实现任何既有桩方法。

// ── DownloadTaskItem：补 autoPresentDetail（整合包注册后置 YES，manager 在
//    首次状态更新时自动弹进度页——本 harness manager 桩 no-op，属性仅落盘）。
//    category 无法自动合成 → 关联对象存储
@interface DownloadTaskItem : NSObject
@property (nonatomic, copy) NSString *taskId;
@end

@interface DownloadTaskItem (PreviewAssetSearchStubs)
@property (nonatomic, assign) BOOL autoPresentDetail;
@end

@implementation DownloadTaskItem (PreviewAssetSearchStubs)

- (BOOL)autoPresentDetail {
    return [objc_getAssociatedObject(self, @selector(autoPresentDetail)) boolValue];
}

- (void)setAutoPresentDetail:(BOOL)autoPresentDetail {
    objc_setAssociatedObject(self, @selector(autoPresentDetail), @(autoPresentDetail),
                             OBJC_ASSOCIATION_RETAIN);
}

@end

// ── DownloadTaskManager：补七参注册 + setTask 三变体 + updateTask 三变体
//   （ZL2AssetSearch 整合包 6 阶段任务上报面；与 7.0-UI-10-a 汇报的签名清单
//   逐条对 DownloadTaskManager.h 核对）。返回的 item 携带非 nil taskId（消费方
//   后续 updateTaskWithId:/setTaskWithId: 全走桩 no-op，状态恒 Pending → 顶栏
//   胶囊与下载页胶囊可见性派生不变）
@interface DownloadTaskManager : NSObject
@end

@interface DownloadTaskManager (PreviewAssetSearchStubs)
- (DownloadTaskItem *)registerTaskWithResourceType:(NSString *)resourceType
                                      resourceName:(NSString *)resourceName
                                       displayName:(NSString *)displayName
                                    downloadSource:(NSString *)downloadSource
                                           rawTask:(nullable id)rawTask
                                    supportsResume:(BOOL)supportsResume
                                           iconURL:(nullable NSString *)iconURL;
- (void)setTaskWithId:(NSString *)taskId stages:(NSArray<PLTaskStage *> *)stages;
- (void)setTaskWithId:(NSString *)taskId completedWithError:(nullable NSError *)error;
- (void)setTaskWithId:(NSString *)taskId state:(NSInteger)state;
- (void)updateTaskWithId:(NSString *)taskId
            stageAtIndex:(NSUInteger)index
                  status:(NSInteger)status;
- (void)updateTaskWithId:(NSString *)taskId
            stageAtIndex:(NSUInteger)index
                progress:(double)progress
                 message:(nullable NSString *)message;
- (void)updateTaskWithId:(NSString *)taskId
       currentStageIndex:(NSInteger)currentStageIndex;
@end

@implementation DownloadTaskManager (PreviewAssetSearchStubs)

- (DownloadTaskItem *)registerTaskWithResourceType:(NSString *)resourceType
                                      resourceName:(NSString *)resourceName
                                       displayName:(NSString *)displayName
                                    downloadSource:(NSString *)downloadSource
                                           rawTask:(nullable id)rawTask
                                    supportsResume:(BOOL)supportsResume
                                           iconURL:(nullable NSString *)iconURL {
    DownloadTaskItem *item = [[DownloadTaskItem alloc] init];
    item.taskId = [[NSUUID UUID] UUIDString];
    return item;
}

- (void)setTaskWithId:(NSString *)taskId stages:(NSArray<PLTaskStage *> *)stages {
}

- (void)setTaskWithId:(NSString *)taskId completedWithError:(nullable NSError *)error {
}

- (void)setTaskWithId:(NSString *)taskId state:(NSInteger)state {
}

- (void)updateTaskWithId:(NSString *)taskId
            stageAtIndex:(NSUInteger)index
                  status:(NSInteger)status {
}

- (void)updateTaskWithId:(NSString *)taskId
            stageAtIndex:(NSUInteger)index
                progress:(double)progress
                 message:(nullable NSString *)message {
}

- (void)updateTaskWithId:(NSString *)taskId
       currentStageIndex:(NSInteger)currentStageIndex {
}

@end

// ── MinecraftResourceDownloadTask：补 maxRetryCount（原版预装重试上限，
//    消费方 task.maxRetryCount = 3）。category 无法自动合成 → 关联对象存储
@interface MinecraftResourceDownloadTask : NSObject
@end

@interface MinecraftResourceDownloadTask (PreviewAssetSearchStubs)
@property (nonatomic, assign) NSInteger maxRetryCount;
@end

@implementation MinecraftResourceDownloadTask (PreviewAssetSearchStubs)

- (NSInteger)maxRetryCount {
    return [objc_getAssociatedObject(self, @selector(maxRetryCount)) integerValue];
}

- (void)setMaxRetryCount:(NSInteger)maxRetryCount {
    objc_setAssociatedObject(self, @selector(maxRetryCount), @(maxRetryCount),
                             OBJC_ASSOCIATION_RETAIN);
}

@end

// ── PLProfiles：补 selectedProfile（ZL2AssetSearch 从选中 profile 反解
//    lastVersionId 推导 preferredGameVersion/preferredLoader；main TU 桩已有
//    selectedProfileName，勿重复）。恒 nil → lastVersionId nil → preferred*
//    nil（消费方 isKindOfClass/length 守卫已核对，版本页保持「全部」默认行为）
@interface PLProfiles : NSObject
@end

@interface PLProfiles (PreviewAssetSearchStubs)
- (nullable NSMutableDictionary<NSString *, NSString *> *)selectedProfile;
@end

@implementation PLProfiles (PreviewAssetSearchStubs)

- (nullable NSMutableDictionary<NSString *, NSString *> *)selectedProfile {
    return nil;
}

@end

#pragma mark - extern 常量桩（7.0-UI-10-f 新增）

// DownloadTaskItem.h 声明（DownloadTaskItem.m L9 原值照抄）。整合包注册任务
// 时消费；manager 桩不读值，仅保真。已 grep 本 TU 与 main TU 确认无重复定义
NSString * const DownloadTaskResourceTypeModpack = @"modpack";
