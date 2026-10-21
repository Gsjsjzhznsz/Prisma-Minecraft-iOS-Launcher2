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
// 红线：颜色不落（无新建视图）；translates 全默认（无新建视图）；iOS 14.0+
// API；LF 行尾；本文件不进 Natives/CMakeLists.txt（仅 ui-smoke 特例编译）。
//

#import <UIKit/UIKit.h>
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
