#import <Foundation/Foundation.h>

@interface FabricUtils : NSObject

/// 官方端点表（Fabric / Quilt 的 meta 与 profile json 模板）
+ (NSDictionary *)endpoints;

/// 按当前镜像策略返回 Fabric/Quilt meta 端点的候选 URL 数组
/// （endpoint 取值 game / loader；候选顺序由 download.modLoaderSource 策略决定，
///   Fabric meta → BMCLAPI /fabric-meta，Quilt meta → BMCLAPI /quilt-meta）
+ (NSArray<NSURL *> *)candidateURLsForVendor:(NSString *)vendor endpoint:(NSString *)endpoint;

/// 按当前镜像策略返回 profile json 端点格式化后的候选 URL 数组
/// （Fabric/Quilt loader 的 version JSON 下载地址，maven 体系 → BMCLAPI /maven）
+ (NSArray<NSURL *> *)candidateURLsForVendor:(NSString *)vendor
                             minecraftVersion:(NSString *)minecraftVersion
                               loaderVersion:(NSString *)loaderVersion;

/// ★ Task336：Fabric-like 三厂直装执行器（新 UI Addons 页内联安装，
/// 不再跳旧 UI FabricInstallViewController 表单——「点击安装跳到旧界面」
/// 用户点题退役）。语义与 legacy 安装器 actionDone 一致：profile json 候选
/// 轮询拉取 → versions/<id>/<id>.json 落盘 + localVersionList 注册 →
/// saveProfile（Task322 混居 gameDir=versions/<id>，旧表单 /game 分居层
/// 不再延续）→ 可选三厂 API（Modrinth fabric-api / legacy-fabric-api / qsl，
/// loader 标签 fabric / legacy-fabric / quilt）下载入实例 mods/。
/// completion 主线程回调（success, profileId, error）。
+ (void)ame336_installFabricLikeVendor:(NSString *)vendor
                           gameVersion:(NSString *)gameVersion
                         loaderVersion:(NSString *)loaderVersion
                            installAPI:(BOOL)installAPI
                            completion:(void (^)(BOOL success, NSString *profileId, NSError *error))completion;

@end
