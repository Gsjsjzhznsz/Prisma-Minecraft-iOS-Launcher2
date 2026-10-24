#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 权限中心（Task 317）
// -------------------------------------------------------------------
// 权限组定义 + 每插件授权持久化 + 运行时检查单一事实源。
// 强制口径：
//  · 所有桥接 API 在派发前必须过 ame317_pluginHasGrant（桥边界=唯一执法点）
//  · 高危权限（danger=YES）安装时默认拒绝，用户在详情页手动开启
//  · 授权状态实时生效：详情页翻转开关 → 下一帧桥接调用即被拒
//  · state.json 原子写（tmp+rename），损坏自动重建（宁丢授权不崩启动器）
// ═══════════════════════════════════════════════════════════════════

/// 权限组条目
/// 插件根目录（POJAV_HOME/Prisma2/plugins，Task319/320 PCL 风格布局；C 函数，Manager/Runtime 共用）
NSString *ame317_pluginsRootDir(void);

@interface AmePluginPermissionItem : NSObject
/// 权限 id（桥接命名空间对齐，如 @"net" / @"ui.theme"）
@property (nonatomic, copy, readonly) NSString *permissionId;
/// 是否高危（高危=安装默认拒+详情页红标）
@property (nonatomic, assign, readonly) BOOL danger;
/// i18n 键（ame317.perm.<id>.name / ame317.perm.<id>.desc）
@property (nonatomic, copy, readonly) NSString *nameKey;
@property (nonatomic, copy, readonly) NSString *descKey;
- (instancetype)initWithId:(NSString *)pid danger:(BOOL)danger NS_DESIGNATED_INITIALIZER;
@end

@interface AmePluginPermissions : NSObject

/// 全部权限组（顺序=安装确认页展示顺序）
+ (NSArray<AmePluginPermissionItem *> *)allPermissions;
/// 权限 id 是否合法（manifest 校验用）
+ (BOOL)isValidPermissionId:(NSString *)permissionId;
/// 是否高危
+ (BOOL)isDangerous:(NSString *)permissionId;

/// 持久化根：POJAV_HOME/Prisma2/plugins/state.json（grants + enabled）
+ (NSURL *)stateFileURL;

/// 查询某插件对某权限组的授权（默认 NO：未记录=未授权）
+ (BOOL)pluginHasGrant:(NSString *)pluginId permission:(NSString *)permissionId;
/// 写授权（实时生效；调用方负责持久化 flush）
+ (void)setGrant:(BOOL)granted forPlugin:(NSString *)pluginId permission:(NSString *)permissionId;
/// 取某插件全部授权字典（详情页渲染）
+ (NSDictionary<NSString *, NSNumber *> *)grantsForPlugin:(NSString *)pluginId;
/// 按授权表批量落盘（安装流一次性写入；true=全量替换该插件 grants）
+ (void)replaceGrants:(NSDictionary<NSString *, NSNumber *> *)grants
             forPlugin:(NSString *)pluginId;
/// 插件卸载：清 grants + enabled
+ (void)purgePluginState:(NSString *)pluginId;

/// 启用表
+ (BOOL)pluginEnabled:(NSString *)pluginId;
+ (void)setPluginEnabled:(BOOL)enabled pluginId:(NSString *)pluginId;

/// state.json 落盘（所有 set* 调用后由各入口自行 flush；内部亦在批尾 flush）
+ (BOOL)flushState;

@end

NS_ASSUME_NONNULL_END
