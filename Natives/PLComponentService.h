//
//  PLComponentService.h
//  Amethyst (Prisma)
//
//  ★Task429（PDF 第五版 §2.1 + 第六版 §3.2.5）：FCL 式组件自动安装服务。
//
//  FCL 语义对标（LibraryAnalyzer + 组件管理页）：
//   · analyze —— 解析当前实例已装组件 → fabric/forge/neoforge/optifine/clean
//     五类条目（排除游戏本体的重复计数：clean 仅收尾一条，表达"干净本体 =
//     MC x.y.z"，不做本体换版）；条目 = {type, version, source:"scanned"}。
//   · 清单构建（inheritsFrom 链合并与文件枚举）与 PLGameIntegrityService
//     同源共享：版本根解析复用 PLProfiles ame353_versionRootForProfileName:
//     （该服务清单构建 ② 的同一函数）；文件枚举与 inheritsFrom 判定复用
//     Task428 扫描式列表 [ZL2VersionsViewController ame428_scanWithOptions:]
//     （jsonState 三态 + inheritsFromParent 链接即其产物）。链环装配细节
//     与 ame428_resolveContextForProfileName: 的链走法同口径（chain = [子,
//     父, 祖父...]、guard 8、父 JSON 不可读即截断）——两处同源，禁止再分叉
//     出第三套解析（详见 .m 顶部同源声明块）。
//   · availableVersions —— fabric 走 Fabric meta 既有消费点（PLMirrorCenter
//     候选链，Task325 同源端点）；forge/neoforge 走 ModpackUtils
//     installerURLForLoader: 同源清单面（Forge：BMCLAPI /forge/minecraft/<mc>
//     主源 + 官方 maven-metadata 兜底；NeoForge 直接复用 NeoForgeVersionFetcher）；
//     OptiFine 远端清单未接入 → 本服务显式报 NoRemoteSource（UI 灰置"仅展示"），
//     离线导入可用。
//   · install —— 复用既有安装器：Fabric = FabricUtils meta 候选链 +
//     profile json 落盘（ame336 同源）；Forge/NeoForge = installer jar 双面
//     下载 + ForgeDirectInstaller / NeoForgeDirectInstaller 直装
//     （skipRegisterVersion:YES，注册表由本服务收口）。事务性（换装失败不
//     落盘）语义见 .m installComponent 注释块。
//   · 换版二次确认由 UI 层做（ZL2ComponentsPage M3Dialog）。
//
//  红线：纯 Foundation（零 UIKit 依赖）；用户可见文案全部经 localize 的
//  ame429.g.* 键（键清单 scripts/task429_i18n_G.json）；日志前缀 [Component] Task429。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 组件类型常量（条目 type 字段取值；FCL LibraryAnalyzer 五分类）

/// 原版（干净本体；本页仅展示不做本体换版）
extern NSString * const PLComponentTypeClean;
/// Fabric（含 Quilt 谱系归并，见 .m 判定注释）
extern NSString * const PLComponentTypeFabric;
/// Minecraft Forge
extern NSString * const PLComponentTypeForge;
/// NeoForge
extern NSString * const PLComponentTypeNeoForge;
/// OptiFine（远端清单未接入 → 仅展示 + 离线导入）
extern NSString * const PLComponentTypeOptiFine;

/// 条目数据来源标记（本实现只有扫描源；FCL 同名字段口径）
extern NSString * const PLComponentSourceScanned;

/// 错误域与码
extern NSString * const PLComponentServiceErrorDomain;
typedef NS_ENUM(NSInteger, PLComponentServiceError) {
    PLComponentServiceErrorNoRemoteSource = 1,   // 该类型无远端清单面（optifine/clean）
    PLComponentServiceErrorProfileMissing = 2,   // 实例注册表键缺失 / 未装版本
    PLComponentServiceErrorUnsupportedType = 3,  // 该类型不支持本操作（如 fabric 离线 jar）
    PLComponentServiceErrorNetwork = 4,          // 清单/安装器下载失败
    PLComponentServiceErrorParse = 5,            // 安装器/清单载荷解析失败
    PLComponentServiceErrorInstall = 6,          // 安装器执行失败（透传 installer error）
    PLComponentServiceErrorParentMissing = 7,    // OptiFine 补丁父版本缺失（写入前预检）
};

#pragma mark - 组件条目

/// 组件条目（FCL LibraryAnalyzer.analyze 对标；条目 = {type, version, source}）
@interface PLComponentEntry : NSObject

/// 五分类常量之一
@property (nonatomic, copy, readonly) NSString *type;
/// 组件版本（loader 版本号；clean = MC 版本；无法提取时 nil）
@property (nonatomic, copy, readonly, nullable) NSString *version;
/// 承载该组件的版本实体 id（继承链环上的版本目录名；换版 repoint 锚点）
@property (nonatomic, copy, readonly, nullable) NSString *versionId;
/// 继承链根 MC 版本（整链共用；truncated 链按 id 形态推断）
@property (nonatomic, copy, readonly, nullable) NSString *minecraftVersion;
/// 数据来源：恒 @"scanned"（本实现只有扫描源）
@property (nonatomic, copy, readonly) NSString *source;
/// 远端清单面可用性（fabric/forge/neoforge = YES；optifine/clean = NO → UI 灰置"仅展示"）
@property (nonatomic, assign, readonly, getter=isInstallable) BOOL installable;

@end

#pragma mark - 服务 API（全部类方法；后台执行，completion 统一主线程回调）

@interface PLComponentService : NSObject

/// 分析实例已装组件（FCL LibraryAnalyzer.analyze 对标）。
/// profileName 传 nil/空 = 全局当前档（PLProfiles.current.selectedProfileName，
/// 与 PLGameIntegrityService 实例级化同口径）。
/// 返回条目顺序：fabric → forge → neoforge → optifine → clean（在装者）；
/// 无 loader 时仅 clean 一条；实例未装版本/版本 JSON 不可读 → 空数组。
+ (void)analyzeComponentsForProfile:(nullable NSString *)profileName
                         completion:(void (^)(NSArray<PLComponentEntry *> *entries))completion;

/// 远端版本清单（换版选单）。fabric/forge/neoforge 有效；
/// optifine/clean → NoRemoteSource 错误（UI 灰置"仅展示"）。
/// minecraftVersion = 条目的 minecraftVersion（继承链根）。
+ (void)availableVersionsForComponentType:(NSString *)type
                              gameVersion:(NSString *)minecraftVersion
                               completion:(void (^)(NSArray<NSString *> *versions,
                                                    NSError * _Nullable error))completion;

/// 安装/换装（FCL 语义：点条目选 remoteVersion 后由 UI 二次确认再调本接口）。
/// profileName = 要换装的实例注册表键（nil/空 = 当前档）；事务性（失败不落盘）
/// 见 .m 注释块。成功后实例 lastVersionId 已 repoint 至新版本实体并广播
/// @"ReloadProfileList"；旧版本实体保留（Task255 引用计数，版本管理页可清理）。
/// selector 形态：installComponent:type:version:completion:（任务书钦定）。
+ (void)installComponent:(nullable NSString *)profileName
                    type:(NSString *)type
                 version:(NSString *)remoteVersion
              completion:(void (^)(BOOL success,
                                   NSString * _Nullable newVersionId,
                                   NSError * _Nullable error))completion;

/// 离线 jar 导入（FCL 语义：本地安装器直装）。
/// 支持类型：forge（ForgeDirectInstaller 离线路径，DownloadViewController
/// 直装流同款）/ neoforge（NeoForgeDirectInstaller，ModpackImportService
/// 分流同款）/ optifine（补丁流，ZL2GameAddonsViewController ame_installOptiFinePatch
/// 同口径最小实现）；fabric 无离线安装器形态 → UnsupportedType（FCL 同限制）。
/// jarURL 应为 UIDocumentPicker asCopy:YES 产物（服务只读不搬运）。
+ (void)importOfflineJar:(NSURL *)jarURL
       forComponentType:(NSString *)type
              forProfile:(nullable NSString *)profileName
             completion:(void (^)(BOOL success,
                                  NSString * _Nullable newVersionId,
                                  NSError * _Nullable error))completion;

/// 版本实体 id → 组件版本号提取（按 type 口径；页面展示复用）。
/// forge/neoforge："-forge-"/"-neoforge-" 后缀（legacy 复合形态取末段）；
/// fabric："fabric-loader-<v>-<mc>" 中段；optifine："OptiFine_" 后缀；clean：id 原样。
+ (nullable NSString *)componentVersionForVersionId:(nullable NSString *)versionId
                                               type:(NSString *)type;

/// 五分类显示名（clean → 本地化"原版"；其余复用 ModLoaderIconHelper 品牌名）
+ (NSString *)displayNameForComponentType:(NSString *)type;

@end

NS_ASSUME_NONNULL_END
