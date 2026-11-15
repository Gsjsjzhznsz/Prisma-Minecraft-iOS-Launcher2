#import <Foundation/Foundation.h>
#import "ModpackAPI.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

// NSError userInfo keys for diagnostic information (CurseForge API)
extern NSString *const CurseForgeResponseContentTypeKey;
extern NSString *const CurseForgeResponseSnippetKey;

/// CurseForge API 实现，支持模组、资源包、光影、数据包、整合包等
@interface CurseForgeAPI : ModpackAPI

+ (instancetype)sharedInstance;

/// 7.0-UI-16：最近一次异步搜索响应的 pagination.totalCount（0 = 未知/未搜/
/// 失败）。ZL2 资产搜索页码控制器 "N / M" 总页数来源；读侧在搜索完成回调
/// 后消费，写侧在 ame169_issueSearchRequest 解析块内赋值。
@property (nonatomic, assign) NSUInteger lastSearchTotalCount;

/// 判断 CurseForge API Key 是否已配置（运行时偏好 + 编译时宏 + Info.plist 三层 fallback）
/// 用于 UI 门控判断，与实际请求时的 apiKey getter 保持一致
+ (BOOL)isAPIKeyConfigured;

/// Task162：CurseForge 源可用性（UI 门控用）。key 仅官方直连需要；未配 key 时
/// baseURL 强制落 MCIM 镜像（免 key，实测 200），源对所有人可用。
+ (BOOL)isSourceAvailable;

/// Task316：分类 slug -> CF categoryId（/categories?gameId=432&classId=X 一次
/// 拉取按 classId 缓存；匹配规则 = CF slug 精确 == 输入，或 CF name 小写 ==
/// 输入，或别名表命中；全不中返回 nil）。同步网络调用（首次拉取 /categories），
/// 调用方须在后台线程调用。
/// ★Task428（4.4）起自 .m 私有转公开：ZL2 聚合搜索服务（分类映射/失配感知）
/// 与 ZL2 筛选面板（CF 分类树值域）需要跨 TU 消费。
- (nullable NSNumber *)ame316_categoryIdForSlug:(NSString *)slug classId:(NSInteger)classId;

/// ★Task428（4.4）：CF 官方分类树（/categories?gameId=432&classId=X，与
/// ame316 同缓存池按 classId 缓存）。返回 @{@"slug":…, @"name":…} 字典数组
/// （slug 非字符串项跳过，name 缺失时回退 slug）；空数组 = 拉取失败或该
/// classId 无分类。同步网络调用——调用方须在后台线程调用（ZL2 筛选面板
/// 源=CurseForge 档的分类值域来源）。
- (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_categoryListForClassId:(NSInteger)classId;

/// ★Task428（4.4）：最近一次异步搜索（searchModWithFilters:completion:）的
/// 分类失配回退 slug：请求携带 @"category" 筛选但 ame316 在对应 classId 下
/// 无映射时置位，同时去分类参数继续搜索（已回退全部结果）；nil = 无失配
/// （未带分类筛选 / 映射成功 / 新一次搜索发起时的复位值）。读侧在搜索
/// completion 内消费（lastSearchTotalCount 同款口径），UI 出「该分类在
/// CurseForge 不存在，已回退全部结果」提示——不再静默不筛。
/// ★Task429 N6b：NSLock 收口 + 读后即清（聚合服务消费口改走下方 take
/// 方法，取值后立即置 nil——单例粘态不再跨请求串味）。
@property (nonatomic, copy, nullable) NSString *ame428_lastCategoryFallbackSlug;

/// ★Task429 N6b：失配旗标读后即清（take 语义）——取值后立即置 nil（聚合
/// 服务 completion 消费口；预览桩未实现该成员，消费方守卫跳过）
- (nullable NSString *)ame428_takeLastCategoryFallbackSlug;

/// Task211：占位 API Key 判定（编译期 NULL 字面量字符串化产物家族，如
/// "((void *)0)"）。KeyViewController 的预填净化与保存门使用，与 apiKey getter 的
/// 运行时拒绝共用同一张垃圾表。
+ (BOOL)isPlaceholderAPIKey:(NSString *)key;

// ========== 同步方法（兼容旧代码，注意会阻塞线程） ==========
/// 搜索项目（同步，内部使用 dispatch_group_wait，建议在后台队列调用）
- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters
                     previousPageResult:(nullable NSMutableArray *)previousPageResult;

/// 加载项目详情（同步，会填充 item 的版本信息）
- (void)loadDetailsOfMod:(NSMutableDictionary *)item;

// ========== 异步方法（推荐，不阻塞 UI） ==========
/// 异步搜索（推荐），支持 projectType = @"resourcepack" / @"mod" / @"shader" 等
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;

/// 异步获取某个项目的所有版本
/// ★ Task227（issue #10）：按 modId 取展示名（依赖确认单用）
- (void)ame227_fetchModTitle:(NSString *)modID
                  completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion;

/// ★ Task238（用户："cf源没有显示前置"）：拉取 CF 项目的完整元数据
/// （GET /mods/{id} 的 data：name / summary / logo.thumbnailUrl）——
/// 前置条目富卡片（图标 + 名称 + 介绍）的 CF 侧数据源。
/// 回调字典键：name / summary / icon（均可能缺失，调用方自行兜底）。
- (void)ame238_fetchProjectInfo:(NSString *)modID
                     completion:(void (^)(NSDictionary * _Nullable info, NSError * _Nullable error))completion;

- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;

// ========== 异步详情加载 ==========
/// 异步加载项目详情（不阻塞调用线程）
- (void)loadDetailsOfMod:(NSMutableDictionary *)item
              completion:(void (^)(NSError * _Nullable error))completion;

#pragma mark - Server Packs（CurseForge 服务端整合包）

/// 异步搜索服务器整合包：搜索 classId=4471（modpack）项目，作为服务器整合包展示
/// @param filters 搜索过滤条件（query/limit/offset/mcVersion 等）
/// @param completion 完成回调，返回字典数组（含 apiSource=2, projectType=modpack, serverID 字段）
- (void)searchServersWithFilters:(NSDictionary *)filters
                      completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;

/// 异步获取指定 modpack 项目的服务端整合包文件列表（isServerPack=true 的文件）
/// @param modpackID CurseForge project id
/// @param completion 完成回调，返回 server pack 文件字典数组
- (void)getServerPackFilesForModpack:(NSString *)modpackID
                          completion:(void (^)(NSArray * _Nullable files, NSError * _Nullable error))completion;

// ========== 下载工具方法 ==========
/// 获取文件的直接下载链接（CurseForge 需要二次请求）
- (NSString *)downloadURLForFile:(NSDictionary *)file;

/// 检查文件是否匹配项目类型（如资源包只允许 zip）
- (BOOL)file:(NSDictionary *)file matchesProjectType:(NSString *)projectType;

/// 获取项目类型对应的推荐文件后缀（jar/zip）
- (NSArray<NSString *> *)preferredFileExtensionsForProjectType:(NSString *)projectType;

// ========== 指纹反查 ==========
/// 通过 MurmurHash2 文件指纹反查 CurseForge 项目（单个）
/// @param fingerprint CurseForge MurmurHash2 指纹（对文件过滤空白字节后计算，见 CurseForgeMurmurHash）
- (nullable NSMutableDictionary *)projectForFileHash:(NSNumber *)fingerprint projectType:(NSString *)projectType;

/// 批量指纹反查（用于批量更新检查）
- (NSArray<NSMutableDictionary *> *)fileFingerprints:(NSArray<NSNumber *> *)fingerprints;

// Task 5.10：在线整合包下载已统一走 ModpackImportService 导入流程，
// submitDownloadTasksFromPackage:toPath: 双轨实现已删除。

@end

NS_ASSUME_NONNULL_END