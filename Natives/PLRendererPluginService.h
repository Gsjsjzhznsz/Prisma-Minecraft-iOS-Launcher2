#pragma once
#import <Foundation/Foundation.h>
#import "AmePluginManager.h"   // AmePluginInstallResult 错误族复用（管理端弹窗同表）

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// PLRendererPluginService（★Task429 / PDF v5 §11.4 + v6 §3.2.1 维护者钦定）
// -------------------------------------------------------------------
// MobileGlues 渲染器插件（renderer plugin）单一事实源。
//
// 插件包三要素（§11.4）：
//   manifest.json —— 三字段：rendererName（渲染器名）/ driverType（驱动
//                    类型）/ abi（ABI 架构数组），另带 id/version/dylib；
//   dylib         —— 渲染器本体（可缺省：随包内置绑定走 bundle
//                    Frameworks 回退，白名单两处来源，其余一律拒收）；
//   driver.json   —— 驱动配置（可选；driverType=mobileglues 时键型与
//                    MG config.json 同构，启动链覆盖层消费）。
//
// 设备布局 = Prisma2/plugins/renderer/<pluginId>/{manifest.json, ...}
//   （renderer 子目录在 AmePluginManager.installedPluginIds 扫描下天然
//   不可见——根目录无 manifest.json，JS 插件域零串扰）。
//
// 管理端复用 JS 插件流程（§11.4：安装/启停/删除共用，仅包格式校验不同）：
//   启停 = AmePluginPermissions state.json enabled 表（与 JS 插件详情页
//   开关同一注册表）；删除 = purgePluginState 同款。
//
// 落地顺序（第六版钦定）：先做「内置渲染器插件包」单条链路
//   （清单注册→扫描→启动注入→UI 呈现渲染器档位），跑通后再泛化。
//
// 消费契约：JavaLauncher / LauncherPreferences 一律 NSClassFromString
//   软链调用本类（ame428 PLGameIntegrityService 判例同款）——本 TU 未进
//   构建时类查找为 nil，消费面整体跳过：零链接依赖、零崩溃。
// ═══════════════════════════════════════════════════════════════════

/// 渲染器插件条目（扫描产物，只读）
/// 管理端软链影子协议（ZL2PluginListViewController 同名文件内声明）：协议
/// 对象经 runtime 按名唯一化——条目类采纳同名协议后，插件页的
/// conformsToProtocol 影子闸才能判真（若不采纳，页面对本条目的守卫恒假
/// = 渲染器插件组永远隐藏——第六版 N2 判例"恒假守卫"的同型事故，此处以
/// 真实现根修：采纳同名协议，成员集与页面影子协议逐位同源）。
@protocol Ame429RendererEntryShadow <NSObject>
@property (nonatomic, readonly) NSString *pluginId;
@property (nonatomic, readonly) NSString *rendererName;
@property (nonatomic, readonly) NSString *driverType;
@property (nonatomic, readonly) NSArray<NSString *> *abi;
@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly) BOOL enabled;
@end

@interface PLRendererPluginEntry : NSObject <Ame429RendererEntryShadow>
/// 目录名 + 渲染器选择键（写入 video.renderer / profile.renderer 的值）
@property (nonatomic, copy, readonly) NSString *pluginId;
/// manifest 三字段①：渲染器名（设置页/管理页显示的档位名）
@property (nonatomic, copy, readonly) NSString *rendererName;
/// manifest 三字段②：驱动类型（mobileglues / …；开放字符串，消费侧按
/// 前缀判白名单行为，未知类型仅登记不注入驱动专属环境变量）
@property (nonatomic, copy, readonly) NSString *driverType;
/// manifest 三字段③：ABI 架构（["arm64"]；扫描面过滤非本机架构）
@property (nonatomic, copy, readonly) NSArray<NSString *> *abi;
@property (nonatomic, copy, readonly) NSString *version;
/// 包内 dylib 文件名（manifest "dylib"；可空 = 纯驱动配置件，不上架渲染器列表）
@property (nonatomic, copy, readonly, nullable) NSString *dylibFile;
/// 绝对路径（Prisma2/plugins/renderer/<id>）
@property (nonatomic, copy, readonly) NSString *packageDir;
/// 白名单校验后的 dylib 绝对路径：①插件 renderer 目录内 ②bundle
/// Frameworks 回退（随包内置绑定）。两处之外一律不收编（§11.4 dlopen
/// 路径白名单）。nil = 无可用 dylib（不上架渲染器列表）。
@property (nonatomic, copy, readonly, nullable) NSString *resolvedDylibPath;
/// driver.json 绝对路径（可空）
@property (nonatomic, copy, readonly, nullable) NSString *driverConfigPath;
/// driver.json 解析结果（可空）
@property (nonatomic, copy, readonly, nullable) NSDictionary *driverConfig;
/// state.json enabled 表（与 JS 插件启停同源）
@property (nonatomic, assign, readonly) BOOL enabled;
@end

@interface PLRendererPluginService : NSObject

+ (instancetype)sharedService;

/// 渲染器插件根 = Prisma2/plugins/renderer
+ (NSString *)rendererPluginsRootDir;

/// 扫描注册面（启动链 / 渲染器列表 / 管理页共用；内置包先引导安装，幂等。
/// 结果进程内缓存，安装/启停/删除即失效重扫）
+ (NSArray<PLRendererPluginEntry *> *)availableRenderers;

/// 渲染器列表动态扩展（LauncherPreferences.availableRendererCandidates
/// 表尾追加项；@{key/name/file} 三键与 rendererCandidates 表同构——
/// 仅收编 已启用 + dylib 白名单校验通过 + ABI 命中 本机 的插件档）
+ (NSArray<NSDictionary *> *)rendererChoiceOverrides;

/// 选择键判定 / 取项（JavaLauncher 启动链消费点；key = pluginId。
/// entryForRendererKey 对 停用/ABI 不匹配 的插件仍返回条目（enabled 字段
/// 如实承载），由消费方决定回退——扫描面不隐匿管理信息）
+ (BOOL)isRendererPluginId:(NSString *)key;
+ (nullable PLRendererPluginEntry *)entryForRendererKey:(NSString *)key;

/// 启停（state.json enabled 表；启用=渲染器列表出现档位，停用=隐去，
/// 不触碰用户当前选中值——选中了停用插件的会话由启动链回退 auto）
+ (BOOL)isRendererPluginEnabled:(NSString *)pluginId;
+ (void)setRendererPluginEnabled:(BOOL)enabled pluginId:(NSString *)pluginId;

/// 安装（zip：根部或单层子目录 manifest.json → 三字段/dylib 校验 →
/// renderer 子目录落位 → 登记清单 → 首装默认启用）
/// 返回 AmePluginInstallResult（JS 插件错误族 + 复用；管理端弹窗同表）
+ (AmePluginInstallResult)installRendererPluginFromZip:(NSString *)zipPath
                                                 outId:(NSString *_Nullable *_Nullable)outId;

/// 卸载（删目录 + purge state.json；运行中会话不受影响，下次启动生效）
+ (BOOL)uninstallRendererPlugin:(NSString *)pluginId;

@end

NS_ASSUME_NONNULL_END
