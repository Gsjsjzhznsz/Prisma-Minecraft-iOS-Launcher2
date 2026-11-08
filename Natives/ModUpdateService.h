#import <Foundation/Foundation.h>
#import "ModItem.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

/// 单个 Mod 的更新检查结果
@interface ModUpdateResult : NSObject
/// 本地 Mod 文件路径
@property (nonatomic, copy) NSString *localFilePath;
/// 当前版本（反查命中的版本）
@property (nonatomic, strong, nullable) ModVersion *currentVersion;
/// 更新候选版本列表（按 datePublished 降序，最新在前）
@property (nonatomic, copy) NSArray<ModVersion *> *candidateVersions;
/// 所有版本列表（用于降级选择，按 datePublished 降序）
@property (nonatomic, copy) NSArray<ModVersion *> *allVersions;
/// 项目 ID（用于拉取版本列表）
@property (nonatomic, copy, nullable) NSString *projectID;
/// API 来源（1=Modrinth, 2=CurseForge）
@property (nonatomic, strong, nullable) NSNumber *apiSource;
/// 项目类型（mod/shader/resourcepack/datapack）
@property (nonatomic, copy) NSString *projectType;
/// 是否有可用更新
- (BOOL)hasUpdate;
@end

@interface ModUpdateService : NSObject

+ (instancetype)sharedService;

/// 检查单个 Mod 的更新
/// @param mod 本地 Mod item（需有 filePath 和 fileSHA1）
/// @param gameVersion 当前游戏版本（如 "1.20.1"）
/// @param loader 当前加载器（如 "fabric"/"forge"/"neoforge"/"quilt"，可为 nil）
/// @param projectType 项目类型（mod/shader/resourcepack/datapack）
/// @param completion 结果回调（主线程，result 为 nil 表示检查失败或无匹配）
- (void)checkUpdateForMod:(ModItem *)mod
              gameVersion:(NSString *)gameVersion
                   loader:(nullable NSString *)loader
              projectType:(NSString *)projectType
               completion:(void (^)(ModUpdateResult *_Nullable result))completion;

/// 批量检查更新（并发限流 3）
/// @param mods 本地 Mod 数组
/// @param gameVersion 当前游戏版本
/// @param loader 当前加载器
/// @param projectType 项目类型
/// @param progress 进度回调（已完成数/总数）
/// @param completion 全部完成回调（results 数组，每个元素对应一个 mod 的检查结果，无更新的不在数组中）
/// ★Task412 模组在线信息查询（第 20 轮复诉⑤「以前1代和zl2的模组信息在线
/// 查询替代这些文件名和图标还有模组信息的设计怎么没了」）：复用更新检查的
/// 双源哈希反查（Modrinth SHA1 / CurseForge MurmurHash2 指纹抢答）命中项目
/// 后，再拉项目详情（Modrinth ame412_fetchProjectDetails / CurseForge
/// ame238_fetchProjectInfo，输出 name/summary/icon 同构字典），主线程回调
/// title/summary/iconURL/projectID；任一环节失败回调空串（页面按缺席降级，
/// 诚实边界：零假数据）。
/// @param mod 本地 Mod item（需有 filePath；fileSHA1 缺席时仅走 CF 指纹源）
/// @param projectType 项目类型（mod/shader/resourcepack/datapack）
/// ★Task413：completion 增补 source（1=Modrinth, 2=CurseForge）——第 22 轮
/// 复诉「模组在线查询回归的模组链接请在启动器完成，直接跳转对应的模组
/// 列表」：页面凭 source 路由 apiSource 推入内建版本列表页（拿 CF 数字
/// ID 请求 Modrinth 拉不到版本的 Task247 判例同源）。
- (void)fetchProjectInfoForMod:(ModItem *)mod
                    projectType:(NSString *)projectType
                     completion:(void (^)(NSString * _Nullable title,
                                          NSString * _Nullable summary,
                                          NSString * _Nullable iconURL,
                                          NSString * _Nullable projectID,
                                          NSNumber * _Nullable source))completion;

- (void)checkUpdatesForMods:(NSArray<ModItem *> *)mods
               gameVersion:(NSString *)gameVersion
                    loader:(nullable NSString *)loader
               projectType:(NSString *)projectType
                  progress:(void (^)(NSInteger completed, NSInteger total))progress
                completion:(void (^)(NSArray<ModUpdateResult *> *results))completion;

@end

NS_ASSUME_NONNULL_END
