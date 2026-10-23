#pragma once
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// AmePluginBridge（Task 317）
// -------------------------------------------------------------------
// 注入每个插件 JSContext 的 `ame` 对象。桥边界=权限唯一执法点：
//   每个 API 派发前先查 AmePluginPermissions，拒绝即抛 JS 异常。
// JS 调用形态（JSC 自动 ObjC↔JS 桥）：
//   ame.log("…") / ame.toast("…")
//   ame.on("game.starting", fn) / ame.off("game.starting")
//   ame.dialog({title, body, confirm, cancel}, function(ok){…})
//   ame.addLauncherRow({id, title, subtitle}, onTap)
//   ame.setThemeToken({primary:"#RRGGBB"})
//   ame.getPref("video.renderer") / ame.setPref("k", v)
//   ame.getRenderer() / ame.setRenderer({renderer:"mg", backend:"gles"})
//   ame.storage.get(k) / .set(k,v) / .remove(k) / .keys()
//   ame.fetch(url, {method, headers}, function(err, resp){…})
//   ame.getProfiles()
// ═══════════════════════════════════════════════════════════════════

@interface AmePluginBridge : NSObject

/// 所属插件 id（权限查询键）
@property (nonatomic, copy, readonly) NSString *pluginId;
/// manifest 声明的权限（用于快速短路：未声明直接拒，连查询都不必）
@property (nonatomic, copy, readonly) NSArray<NSString *> *declaredPermissions;

- (instancetype)initWithPluginId:(NSString *)pluginId
            declaredPermissions:(NSArray<NSString *> *)permissions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 事件回调注册表运行时互访（Runtime 派发用）
/// 返回该事件的全部 JS 回调（主线程调用后即失效持引用者负责）
- (NSArray<JSValue *> *)handlersForEvent:(NSString *)event;
/// 注册插件贡献行（Runtime/列表页互访；返回行 id，重复 id 覆盖）
- (NSArray<NSDictionary *> *)contributedRows;
- (void)invokeRowTap:(NSString *)rowId;
/// 插件停用/卸载：清事件表/贡献行（主题令牌还原由 Runtime 统一调）
- (void)teardown;

@end

NS_ASSUME_NONNULL_END
