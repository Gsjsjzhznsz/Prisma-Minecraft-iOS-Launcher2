#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 运行时（Task 317）
// -------------------------------------------------------------------
// 每插件一个 JSContext（互不可见，天然隔离）；桥对象 ame 注入后先包
// 一层 JS 门面（友好方法名 + storage 嵌套命名空间），再执行 main.js。
// 线程口径：全部 JS 执行收主队列（桥接 UI 端零跳线，JSC 单线程口径）。
// 事件面（native → JS）：
//   app.launch / app.foreground / app.background
//   profile.changed / profile.listChanged
//   game.starting / game.exited
// ═══════════════════════════════════════════════════════════════════

@interface AmePluginRuntime : NSObject

/// 进程内单例
+ (instancetype)sharedRuntime;

/// 启动期装载：扫描已装插件，enabled=YES 且授权合法者创建上下文并执行
/// main.js，随后向其派发 app.launch。幂等（重复调用无副作用）。
+ (void)bootIfNeeded;

/// 启停单插件（详情页开关用）。enabled：装载执行；disabled：拆除上下文
/// + 还原本插件主题令牌 + 清贡献行/事件表。
+ (void)setPluginEnabled:(NSString *)pluginId enabled:(BOOL)enabled;

/// 插件是否在运行（有活上下文）
+ (BOOL)isRunning:(NSString *)pluginId;

/// 全部插件贡献行（列表页渲染；内部按启用中的插件聚合）
+ (NSArray<NSDictionary *> *)allContributedRows;
/// 转发行点按到所属插件
+ (void)invokeRowTap:(NSString *)rowId;

/// 系统事件入口（native 各接线点调用；内部转发给启用中插件）
+ (void)emitEvent:(NSString *)event payload:(nullable id)payload;

/// 游戏启停接线（SurfaceViewController/JavaGUIViewController 调用）
+ (void)notifyGameStarting;
+ (void)notifyGameExited:(NSInteger)exitCode;

/// 前后台接线（AppDelegate/SceneDelegate 调用）
+ (void)notifyAppEnteringForeground;
+ (void)notifyAppEnteringBackground;

@end

NS_ASSUME_NONNULL_END
