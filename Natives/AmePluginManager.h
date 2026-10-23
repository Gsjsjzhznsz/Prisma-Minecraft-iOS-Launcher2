#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 管理器（Task 317）
// -------------------------------------------------------------------
// 插件包 = .ameplugin（zip：manifest.json + main.js [+ assets/]）
// 设备布局 = POJAV_HOME/plugins/<pluginId>/{manifest.json, main.js, ...}
// 职责：发现 / manifest 校验 / 安装(解压+替换保授权) / 卸载 / 启停。
// 不负责：JS 执行（Runtime）、权限判定（Permissions）、UI（ZL2Plugin*）。
// ═══════════════════════════════════════════════════════════════════

/// manifest.json 解析产物（只含启动器关心的规范化字段）
@interface AmePluginManifest : NSObject
@property (nonatomic, copy) NSString *pluginId;      // ^[a-z0-9][a-z0-9._-]{2,63}$
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *entry;         // 相对路径，*.js，禁 .. 与绝对路径
@property (nonatomic, copy) NSArray<NSString *> *permissions; // ⊆ 权限注册表
@property (nonatomic, assign) NSInteger minApi;
@end

/// 安装结果
typedef NS_ENUM(NSInteger, AmePluginInstallResult) {
    AmePluginInstallOK            = 0,
    AmePluginInstallErrReadZip    = 1, // 无法读取 zip
    AmePluginInstallErrNoManifest = 2, // 根部无 manifest.json
    AmePluginInstallErrBadJSON    = 3, // manifest 非 JSON 对象
    AmePluginInstallErrBadSchema  = 4, // 字段缺失/非法（含权限 id 未注册）
    AmePluginInstallErrBadEntry   = 5, // entry 文件缺失或路径越界
    AmePluginInstallErrAPITooNew  = 6, // minApi > 启动器插件 API 版本
    AmePluginInstallErrMove       = 7, // 落盘失败
};

@interface AmePluginManager : NSObject

/// 插件 API 版本（manifest.minApi 超过即拒装）
+ (NSInteger)apiVersion;

/// 已安装插件 id 列表（目录扫描，按 id 排序）
+ (NSArray<NSString *> *)installedPluginIds;
/// 读某插件 manifest（目录缺 manifest/解析失败 → nil）
+ (nullable AmePluginManifest *)manifestForPlugin:(NSString *)pluginId;
/// 某插件入口 main.js 绝对路径
+ (nullable NSString *)entryPathForPlugin:(NSString *)pluginId;
/// 插件目录（可能不存在）
+ (NSString *)pluginDir:(NSString *)pluginId;

/// 校验 manifest 字典（安装流与详情页共用）
/// 通过返回解析对象；失败返回 nil 并填充 errCode（AmePluginInstallErr*）
+ (nullable AmePluginManifest *)validateManifestDictionary:(NSDictionary *)dict
                                                   errCode:(AmePluginInstallResult *)errCode;

/// 安装 .ameplugin zip：
///   校验 manifest → 解压 → 目录落位（同 id 覆盖，保留既有授权与启用态）
/// 返回 errCode（OK=0）；成功时 outManifest 带回解析结果
+ (AmePluginInstallResult)installFromZip:(NSString *)zipPath
                            outManifest:(AmePluginManifest **)outManifest;

/// 卸载（删目录 + 清授权/启用态；正在运行的插件由 Runtime 先停）
+ (BOOL)uninstallPlugin:(NSString *)pluginId;

@end

NS_ASSUME_NONNULL_END
