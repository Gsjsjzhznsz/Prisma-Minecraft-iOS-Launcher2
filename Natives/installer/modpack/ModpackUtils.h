#import <Foundation/Foundation.h>
#import "UnzipKit.h"

@interface ModpackUtils : NSObject

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError **)error;
+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency;

/// 根据 loader 类型构造 installer.jar 下载 URL（Forge/NeoForge）
/// 提取自 ModpackImportService，供 ModrinthAPI/CurseForgeAPI 整合包安装复用
+ (nullable NSString *)installerURLForLoader:(NSString *)loader
                               loaderVersion:(NSString *)loaderVersion
                            minecraftVersion:(NSString *)minecraftVersion;

/// 根据 MC 版本推断所需 Java 主版本号
+ (NSInteger)javaMajorVersionForMC:(NSString *)mcVersion;

/// 写入显式失败的占位 version JSON（mainClass 指向不存在的类，启动时显式报错）
/// 避免 Forge/NeoForge 直装失败后误装作 vanilla MC 让用户以为 mods 生效
+ (void)writePlaceholderVersionJSONForVersionId:(NSString *)versionId
                               minecraftVersion:(NSString *)minecraftVersion
                                         loader:(NSString *)loader
                                 loaderVersion:(NSString *)loaderVersion
                                          error:(NSError *)error;

#pragma mark - ★Task428：Modrinth SHA1 反查（工作项二 2.3，FCL ModrinthModpackExportTask 口径）

/// 导出 .mrpack 时按本地 mod 文件 SHA-1 反查 Modrinth 直链。
/// 输入：mod 文件描述数组（每项需含非空 @"sha1"（40 位 hex），形态参考
/// ModpackExportService 收集的 modFiles；无 sha1 的条目直接视为未命中）。
/// 请求：GET https://api.modrinth.com/v2/version_file/{sha1}?algorithm=sha1
///（官方端点，传输级失败时以 MCIM 镜像端点各补一次；HTTP 404 = 确定未命中，
/// 不换端点重试）。命中取版本 files[] 中 primary 条目的 url（无 primary 标记
/// 时取首条 url），未命中/任何失败静默降级为「不补链接」，绝不抛错阻断导出。
/// 返回：sha1 → 直链 url 映射（仅命中项）。
+ (NSDictionary<NSString *, NSString *> *)ame428_modrinthDownloadURLsForFiles:(NSArray<NSDictionary *> *)files
                                                                   concurrency:(NSInteger)concurrency;

/// ★Task439 E4 清偿：带取消旗标的反查变体——isCancelledBlock 在每个探测槽入口
/// 与双端点切换处轮询，取消即查即退（弱网下秒级生效）；传 nil 等价旧无参入口。
/// 取消语义：已发出的单次探测不被打断（网络层无超时中断通道），但取消后的
/// 剩余槽位不再发起任何新请求，dispatch_group 立即收口。
+ (NSDictionary<NSString *, NSString *> *)ame439_modrinthDownloadURLsForFiles:(NSArray<NSDictionary *> *)files
                                                                  concurrency:(NSInteger)concurrency
                                                              isCancelledBlock:(BOOL (^)(void))isCancelled;

@end
