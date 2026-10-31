#import "AmePluginBridge.h"
#import "AmePluginPermissions.h"
#import "AmePluginManager.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"       // localize + 渲染器宏（RENDERER_NAME_*）
#import "ZL2M3Kit.h"    // MD3 对话框
#import "ZL2Theme.h"    // 主题令牌覆盖钩子
#import "ZL2ShellViewController.h"   // Task327：页面导航通知契约（ZL2ShellNavigate）
#import "StikDebugViewController.h"  // ★ Task365：JIT 状态四态/内置轨可用性/开启共享入口
// ★ Task366：API 全量扩容导入面（模组/光影/下载历史/崩溃分析/AI/运行时互访）
#import "ModService.h"              // ame264 有效 mods 目录解析（实例隔离感知）
#import "ShaderService.h"           // shaderpacks 目录
#import "DownloadHistoryStore.h"    // 下载历史
#import "CrashAnalyzer.h"           // hs_err JVM 崩溃日志分析
#import "AI/AiSettings.h"           // AI 供应商选中态
#import "AI/AiProviderStore.h"      // 供应商存储（selectedProvider）
#import "AI/AiAPIClient.h"          // 一次性问答通道
#import "AI/AiProvider.h"
#import "AI/AiMessage.h"
#import "AmePluginRuntime.h"        // 末次游戏退出记录 / 主题覆盖读取
#import <UserNotifications/UserNotifications.h>  // 本地通知（notify 权限）

#import <UIKit/UIKit.h>
#import <objc/runtime.h>   // Task364：pan 累计位移关联对象
#include <math.h>          // Task364：isfinite 防呆
#import <mach/mach.h>      // Task366：phys_footprint（进程内存用量）

// ═══════════════════════════════════════════════════════════════════
// AmePluginBridge 实现（Task 317）
// 口径注释：
//  · 权限执法点：ame317_requirePerm 先查 manifest 声明（未声明=连查询都
//    不做），再查用户授权；拒绝即向 JS 抛本地化异常 + return
//  · 所有 JS 可见方法仅允许主线程调用（Runtime 保证事件/回调主线程派发）
//  · fetch 走 NSURLSession 异步，回调切主线程后进 JS；30s 超时
//  · storage 沙盒 = 插件目录内 storage.json（键值 JSON，4MB 上限防失控）
//  · 主题令牌覆盖经 ZL2Theme 的插件覆盖表（smoke 目标零新增依赖）
//  · ★ Task364 视图操纵：句柄注册表 = NSMapTable 强键弱值（视图释放即
//    查空判 stale）；首改留痕原几何（frame/alpha/hidden）供 reset 还原；
//    手势回调经 Ame364GestureSink 载体（非 JSExport 类，不进 JSC 面）；
//    teardown 统一摘手势 + 还原几何，插件卸载零残留
// ═══════════════════════════════════════════════════════════════════

static const NSUInteger ame317_storageMaxBytes = 4 * 1024 * 1024;

// ★ Task364：手势回调载体（普通 NSObject，非 JSExport——JSC 不见此类；
//   UIGestureRecognizer target/action 需要常驻对象，JSValue 回调随载体
//   持有，插件卸载经 teardown 连根摘除）。
@interface Ame364GestureSink : NSObject
@property (nonatomic, assign) NSUInteger handle;
@property (nonatomic, copy) NSString *event;
@property (nonatomic, strong) JSValue *cb;
@property (nonatomic, weak) AmePluginBridge *bridge;
@property (nonatomic, weak) UIGestureRecognizer *gesture;   // ★ 精确摘除：只摘自己挂的
- (void)ame364_fired:(UIGestureRecognizer *)gr;
@end

// ★ Task364：sink 实现在主实现之前，跨类调用需前置声明（ARC 下未声明
//   selector = no known instance method 编译错；Task261 判例同族）
@interface AmePluginBridge (Ame364Internal)
- (void)ame364_gestureFired:(UIGestureRecognizer *)gr sink:(Ame364GestureSink *)sink;
@end

// ★ Task365：私有方法跨类消费前向声明（Task261 判例同族防线——ARC 下未声明
//   selector = no known instance method 编译错）。主页启动按钮动作 launchButtonTapped
//   与壳层子页访问器 ame_childForIndex: 均只活在各自 .m，桥面仅经类别声明消费。
//   ★ r1/r2（CI run 41167538237/41168291941 两轮编译实锤）：类别定义要求
//   完整 @interface —— 未导入时 cannot find interface declaration；@class
//   前置仍报 cannot define category for undefined class + receiver type
//   forward declaration。正解 = 导入 ZL2HomeViewController.h（纯 UIKit
//   import 无环；launchButtonTapped 仍为其 .m 私有，类别声明照旧）。
#import "ZL2HomeViewController.h"
@interface ZL2ShellViewController (Ame365Bridge)
- (UIViewController *)ame_childForIndex:(NSInteger)index;
@end
@interface ZL2HomeViewController (Ame365Bridge)
- (void)launchButtonTapped;
@end

@implementation Ame364GestureSink
- (void)ame364_fired:(UIGestureRecognizer *)gr {
    [self.bridge ame364_gestureFired:gr sink:self];
}
@end

@interface AmePluginBridge ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<JSValue *> *> *eventTable;
@property (nonatomic, strong) NSMutableDictionary<NSString *, JSValue *> *rowTable; // rowId → handler
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *rowSpecTable;
// ★ Task364：视图操纵注册表（强键弱值——视图释放后 lookup 即 nil=stale 句柄）
@property (nonatomic, strong) NSMapTable<NSNumber *, UIView *> *viewTable;
@property (nonatomic, assign) NSUInteger viewHandleSeed;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *viewOriginals; // handle → @{frame,alpha,hidden} 首改留痕
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<Ame364GestureSink *> *> *viewSinks; // handle → 手势载体表
// ★ Task366：本插件弹出的 UIAlertController 登记（dialogDismissAll 只关自己的）
@property (nonatomic, strong) NSHashTable<UIAlertController *> *presentedDialogs;
// ★ Task366：样式首改留痕（textColor/font/边框——viewsReset 与卸载还原）
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *viewStyleOriginals;
@end

@implementation AmePluginBridge

- (instancetype)initWithPluginId:(NSString *)pluginId
            declaredPermissions:(NSArray<NSString *> *)permissions {
    self = [super init];
    if (self) {
        _pluginId = [pluginId copy];
        _declaredPermissions = [permissions copy] ?: @[];
        _eventTable = [NSMutableDictionary dictionary];
        _rowTable = [NSMutableDictionary dictionary];
        _rowSpecTable = [NSMutableDictionary dictionary];
        // ★ Task364：句柄表 = 强 NSNumber 键 + 弱 UIView 值（视图释放即判 stale）
        _viewTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
                                          valueOptions:NSMapTableWeakMemory];
        _viewOriginals = [NSMutableDictionary dictionary];
        _viewSinks = [NSMutableDictionary dictionary];
        _presentedDialogs = [NSHashTable weakObjectsHashTable];
        _viewStyleOriginals = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 权限执法

/// 权限门：未声明 或 未授权 → 抛 JS 异常返回 NO（fail-closed）
- (BOOL)ame317_requirePerm:(NSString *)perm {
    // ★ Task333：完全接管放行（ame.super 已授权即全权限通过）——用户点题
    //   "最高级别权限，一打开全部东西都可以改"。刻意置于声明检查之前：
    //   接管语义 = 逐项声明+逐项授权两道闸全部越过。日志落一行审计痕
    //   （限频不必要：接管下每闸一行便于事后审计插件行为面）。
    if ([AmePluginPermissions pluginHasGrant:self.pluginId permission:@"ame.super"]) {
        NSLog(@"[AmePlugin:%@] ame.super takeover grant: perm '%@' allowed (bypass declaration+grant gates)", self.pluginId, perm);
        return YES;
    }
    if ([self.declaredPermissions containsObject:perm] &&
        [AmePluginPermissions pluginHasGrant:self.pluginId permission:perm]) {
        return YES;
    }
    NSString *msg = [NSString stringWithFormat:
        localize(@"ame317.bridge.denied", nil), self.pluginId, perm];
    JSContext *ctx = [JSContext currentContext];
    if (ctx) {
        ctx.exception = [JSValue valueWithObject:msg inContext:ctx];
    }
    NSLog(@"[AmePlugin:%@] 权限拒绝: %@", self.pluginId, perm);
    return NO;
}

#pragma mark - 日志 / 提示

- (void)log:(NSString *)msg {
    NSLog(@"[AmePlugin:%@] %@", self.pluginId, msg ?: @"");
}

- (void)toast:(NSString *)text {
    if (![self ame317_requirePerm:@"ui.dialog"]) return;
    if (text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self ame317_keyWindow];
        UILabel *toast = [[UILabel alloc] init];
        toast.text = [NSString stringWithFormat:@"[%@] %@", self.pluginId, text];
        toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        toast.textColor = [ZL2Theme onSurface];
        toast.backgroundColor = [ZL2Theme surfaceContainerHigh];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.numberOfLines = 0;
        toast.layer.cornerRadius = 12;
        toast.layer.masksToBounds = YES;
        CGFloat pad = 16.0;
        CGSize fit = [toast sizeThatFits:CGSizeMake(window.bounds.size.width - 96, CGFLOAT_MAX)];
        toast.frame = CGRectMake((window.bounds.size.width - MIN(fit.width + pad * 2, window.bounds.size.width - 64)) / 2,
                                 window.bounds.size.height - 140 - MIN(fit.height, 120) / 2,
                                 MIN(fit.width + pad * 2, window.bounds.size.width - 64),
                                 MIN(fit.height + pad, 120));
        toast.alpha = 0;
        [window addSubview:toast];
        [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{ toast.alpha = 0; }
                             completion:^(BOOL _) { [toast removeFromSuperview]; }];
        });
    });
}

- (void)dialog:(NSDictionary *)spec callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ui.dialog"]) return;
    NSString *title = [self ame317_string:spec[@"title"]] ?: self.pluginId;
    NSString *body = [self ame317_string:spec[@"body"]] ?: @"";
    NSString *confirm = [self ame317_string:spec[@"confirm"]];
    NSString *cancel = [self ame317_string:spec[@"cancel"]];
    BOOL destructive = [spec[@"destructive"] boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak typeof(self) wself = self;
        [ZL2M3Dialog showTitle:title
                           body:body
                   confirmTitle:confirm ?: localize(@"ame317.common.ok", nil)
                    destructive:destructive
                     onConfirm:^{
            [wself ame317_callCallback:cb arguments:@[@YES]];
        }
                      onCancel:^{
            [wself ame317_callCallback:cb arguments:@[@NO]];
        }];
    });
}

#pragma mark - 事件

- (void)on:(NSString *)event handler:(JSValue *)cb {
    if (![self ame317_requirePerm:@"events"]) return;
    if (event.length == 0 || !cb.isObject) return;
    NSMutableArray<JSValue *> *list = self.eventTable[event];
    if (!list) {
        list = [NSMutableArray array];
        self.eventTable[event] = list;
    }
    if (![list containsObject:cb]) [list addObject:cb];
}

- (void)off:(NSString *)event {
    if (![self ame317_requirePerm:@"events"]) return;
    if (event.length == 0) { [self.eventTable removeAllObjects]; return; }
    [self.eventTable removeObjectForKey:event];
}

- (NSArray<JSValue *> *)handlersForEvent:(NSString *)event {
    NSArray<JSValue *> *list = self.eventTable[event];
    return [list copy] ?: @[];
}

#pragma mark - 启动器设置页贡献行（ui.rows）

- (void)addLauncherRow:(NSDictionary *)spec handler:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ui.rows"]) return;
    NSString *rowId = [self ame317_string:spec[@"id"]];
    if (rowId.length == 0 || !cb.isObject) return;
    rowId = [NSString stringWithFormat:@"%@.%@", self.pluginId, rowId];
    self.rowTable[rowId] = cb;
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    s[@"id"] = rowId;
    s[@"title"] = [self ame317_string:spec[@"title"]] ?: rowId;
    NSString *sub = [self ame317_string:spec[@"subtitle"]];
    if (sub) s[@"subtitle"] = sub;
    s[@"pluginName"] = self.pluginId;
    self.rowSpecTable[rowId] = s;
}

- (NSArray<NSDictionary *> *)contributedRows {
    return [self.rowSpecTable allValues] ?: @[];
}

- (void)invokeRowTap:(NSString *)rowId {
    JSValue *cb = self.rowTable[rowId];
    if (cb) [self ame317_callCallback:cb arguments:@[rowId]];
}

#pragma mark - 主题令牌覆盖（ui.theme，高危）

- (BOOL)setThemeToken:(NSDictionary *)tokens {
    if (![self ame317_requirePerm:@"ui.theme"]) return NO;
    if (![tokens isKindOfClass:[NSDictionary class]]) return NO;
    // 归一为纯字符串字典（白名单校验在 ZL2Theme 侧做）
    NSMutableDictionary<NSString *, NSString *> *norm = [NSMutableDictionary dictionary];
    for (NSString *k in tokens) {
        id v = tokens[k];
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) {
            norm[k] = v;
        }
    }
    BOOL ok = [ZL2Theme ame317_setPluginThemeTokens:self.pluginId tokens:norm];
    if (ok) {
        // 持久化 __theme 供下次 boot 重放（Runtime 装载期读取；此处已过
        // ui.theme 权限门，直接落插件私有 storage.json，不走 storage 权限门）。
        // 读改写合并进既有 storage（与 storageSet 共用同一文件，禁整表覆盖）
        NSMutableDictionary *storage = [self ame317_loadStorage];
        storage[@"__theme"] = norm ?: @{};
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&err];
        if (data && data.length <= ame317_storageMaxBytes) {
            [data writeToURL:[self ame317_storageURL] atomically:YES];
        }
    }
    return ok;
}

// ★ Task341：形状/字体令牌覆盖（ui.theme，高危；setThemeToken 同构执法链）
//   半径键值 = JS number（JSC 桥自动转 NSNumber）；字体键值 = JS object
//   {size, weight}（自动转 NSDictionary）。类型/白名单校验在 ZL2Theme 侧。
- (BOOL)setThemeShape:(NSDictionary *)tokens {
    if (![self ame317_requirePerm:@"ui.theme"]) return NO;
    if (![tokens isKindOfClass:[NSDictionary class]]) return NO;
    BOOL ok = [ZL2Theme ame341_setPluginThemeShape:self.pluginId tokens:tokens];
    if (ok) {
        // 持久化 __shape 供下次 boot 重放（Runtime 装载期读取；与 __theme
        // 同一 storage 文件读改写合并，禁整表覆盖——与 setThemeToken 同口径）
        NSMutableDictionary *storage = [self ame317_loadStorage];
        storage[@"__shape"] = tokens ?: @{};
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&err];
        if (data && data.length <= ame317_storageMaxBytes) {
            [data writeToURL:[self ame317_storageURL] atomically:YES];
        }
    }
    return ok;
}

// ★ Task343：布局令牌覆盖（ui.theme，高危；setThemeShape 同构执法链）
//   数值键值 = JS number（JSC 桥自动转 NSNumber）。类型/白名单/钳制在
//   ZL2Theme 侧。
- (BOOL)setThemeLayout:(NSDictionary *)tokens {
    if (![self ame317_requirePerm:@"ui.theme"]) return NO;
    if (![tokens isKindOfClass:[NSDictionary class]]) return NO;
    BOOL ok = [ZL2Theme ame343_setPluginThemeLayout:self.pluginId tokens:tokens];
    if (ok) {
        // 持久化 __layout 供下次 boot 重放（与 __theme/__shape 同一 storage
        // 文件读改写合并，禁整表覆盖——同族口径）
        NSMutableDictionary *storage = [self ame317_loadStorage];
        storage[@"__layout"] = tokens ?: @{};
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&err];
        if (data && data.length <= ame317_storageMaxBytes) {
            [data writeToURL:[self ame317_storageURL] atomically:YES];
        }
    }
    return ok;
}

// ★ Task347：结构令牌覆盖（ui.theme，高危；setThemeLayout 同构执法链）
//   字符串键值 = JS string（JSC 桥自动转 NSString）。白名单/值域校验在
//   ZL2Theme 侧（shellLayout ∈ topbar|navigationview）。
- (BOOL)setThemeStructure:(NSDictionary *)tokens {
    if (![self ame317_requirePerm:@"ui.theme"]) return NO;
    if (![tokens isKindOfClass:[NSDictionary class]]) return NO;
    BOOL ok = [ZL2Theme ame347_setPluginThemeStructure:self.pluginId tokens:tokens];
    if (ok) {
        // 持久化 __structure 供下次 boot 重放（与 __theme/__shape/__layout
        // 同一 storage 文件读改写合并，禁整表覆盖——同族口径）
        NSMutableDictionary *storage = [self ame317_loadStorage];
        storage[@"__structure"] = tokens ?: @{};
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&err];
        if (data && data.length <= ame317_storageMaxBytes) {
            [data writeToURL:[self ame317_storageURL] atomically:YES];
        }
    }
    return ok;
}

#pragma mark - 启动器设置读写（settings.read / settings.write）

- (id)getPref:(NSString *)key {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    if (![self ame317_validPrefKey:key]) return nil;
    return getPrefObject(key);
}

- (BOOL)setPref:(NSString *)key value:(id)value {
    if (![self ame317_requirePerm:@"settings.write"]) return NO;
    if (![self ame317_validPrefKey:key]) return NO;
    // 插件系统自身状态键禁写（防插件篡改彼此的授权/启用态）
    if ([key hasPrefix:@"plugin."]) return NO;
    value = [self ame317_unwrapJs:value];
    if ([value isKindOfClass:[NSString class]]) {
        setPrefString(key, value);
        return YES;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *n = (NSNumber *)value;
        if (strcmp([n objCType], @encode(BOOL)) == 0 || strcmp([n objCType], @encode(char)) == 0) {
            setPrefBool(key, n.boolValue);
        } else if (strcmp([n objCType], @encode(float)) == 0 || strcmp([n objCType], @encode(double)) == 0) {
            setPrefFloat(key, (float)n.doubleValue);
        } else {
            setPrefInt(key, n.integerValue);
        }
        return YES;
    }
    return NO;
}

/// 键规范：分段 [a-z0-9_]，点分层，长度 ≤128（防止脏键污染偏好 plist）
- (BOOL)ame317_validPrefKey:(NSString *)key {
    if (key.length == 0 || key.length > 128) return NO;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    for (NSUInteger i = 0; i < key.length; i++) {
        if (![ok characterIsMember:[key characterAtIndex:i]]) return NO;
    }
    return YES;
}

#pragma mark - 渲染器（renderer.read / renderer.write，写=高危）

- (NSDictionary *)getRenderer {
    if (![self ame317_requirePerm:@"renderer.read"]) return nil;
    NSString *profileRenderer =
        [PLProfiles resolveKeyForCurrentProfile:@"renderer"] ?: @"auto";
    NSString *backend = nil;
    id be = getPrefObject(@"mobileglues.renderer_backend");
    if ([be isKindOfClass:[NSString class]]) backend = be;
    return @{
        @"renderer": profileRenderer,
        @"backend": backend ?: [NSNull null],
        @"effective": ame_effective_renderer() ?: @"auto",
        @"available": getRendererKeys(NO) ?: @[],
    };
}

- (BOOL)setRenderer:(NSDictionary *)cfg {
    if (![self ame317_requirePerm:@"renderer.write"]) return NO;
    if (![cfg isKindOfClass:[NSDictionary class]]) return NO;

    // 渲染器层：写当前实例 profile 键（与实例设置页同层；白名单=
    // getRendererKeys(NO) 可用候选，防止写入不存在 dylib 的值致黑屏）
    NSString *renderer = [self ame317_string:cfg[@"renderer"]];
    if (renderer) {
        if (![getRendererKeys(NO) containsObject:renderer]) {
            [self ame317_rejectValue:renderer];
            return NO;
        }
        NSString *selected = [PLProfiles current].selectedProfileName;
        if (selected.length == 0) return NO;
        // Task275 F6 锁内批量变更（禁裸写活字典——写方必须同锁）
        [[PLProfiles current] applyChanges:^(NSMutableDictionary<NSString *, id> *profiles) {
            NSMutableDictionary *profile = profiles[selected];
            if (![profile isKindOfClass:[NSMutableDictionary class]]) {
                profile = [NSMutableDictionary dictionary];
                profiles[selected] = profile;
            }
            profile[@"renderer"] = renderer;
        }];
    }

    // 后端层：mg 家族三键白名单（utils.h 宏，编译期定死）
    NSString *backend = [self ame317_string:cfg[@"backend"]];
    if (backend) {
        NSArray *family = @[
            @RENDERER_NAME_MOBILEGL,
            @RENDERER_NAME_MOBILEGL_GLES,
            @RENDERER_NAME_MITHRIL,
        ];
        if (![family containsObject:backend]) {
            [self ame317_rejectValue:backend];
            return NO;
        }
        setPrefString(@"mobileglues.renderer_backend", backend);
    }
    return (renderer != nil) || (backend != nil);
}

- (void)ame317_rejectValue:(NSString *)value {
    NSString *msg = [NSString stringWithFormat:
        localize(@"ame317.bridge.invalid_value", nil), value ?: @""];
    JSContext *ctx = [JSContext currentContext];
    if (ctx) ctx.exception = [JSValue valueWithObject:msg inContext:ctx];
}

#pragma mark - 实例档案（profile.read）

- (NSArray *)getProfiles {
    if (![self ame317_requirePerm:@"profile.read"]) return nil;
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *profiles = [PLProfiles current].profiles;
    for (NSString *name in profiles) {
        id p = profiles[name];
        if (![p isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"name"] = name;
        id last = p[@"lastVersionId"];
        if ([last isKindOfClass:[NSString class]]) item[@"version"] = last;
        id dir = p[@"gameDir"];
        if ([dir isKindOfClass:[NSString class]]) item[@"gameDir"] = dir;
        [out addObject:item];
    }
    return out;
}

#pragma mark - 私有存储（storage）

- (NSURL *)ame317_storageURL {
    return [NSURL fileURLWithPath:
        [[AmePluginManager pluginDir:self.pluginId]
         stringByAppendingPathComponent:@"storage.json"]];
}

- (NSMutableDictionary *)ame317_loadStorage {
    NSData *data = [NSData dataWithContentsOfURL:[self ame317_storageURL]];
    if (!data || data.length > ame317_storageMaxBytes) {
        return [NSMutableDictionary dictionary];
    }
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![json isKindOfClass:[NSDictionary class]]) {
        return [NSMutableDictionary dictionary];
    }
    return [json mutableCopy];
}

- (BOOL)ame317_saveStorage:(NSDictionary *)storage {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&err];
    if (err || !data || data.length > ame317_storageMaxBytes) return NO;
    return [data writeToURL:[self ame317_storageURL] atomically:YES];
}

- (id)storageGet:(NSString *)key {
    if (![self ame317_requirePerm:@"storage"]) return nil;
    if (key.length == 0) return nil;
    return [self ame317_loadStorage][key];
}

- (BOOL)storageSet:(NSString *)key value:(id)value {
    if (![self ame317_requirePerm:@"storage"]) return NO;
    if (key.length == 0 || key.length > 256) return NO;
    value = [self ame317_unwrapJs:value];
    // JSON 可序列化兜底（防循环引用直接拒）
    if (value != nil &&
        ![NSJSONSerialization isValidJSONObject:@{@"v": value}]) {
        return NO;
    }
    NSMutableDictionary *storage = [self ame317_loadStorage];
    storage[key] = value;
    return [self ame317_saveStorage:storage];
}

- (BOOL)storageRemove:(NSString *)key {
    if (![self ame317_requirePerm:@"storage"]) return NO;
    if (key.length == 0) return NO;
    NSMutableDictionary *storage = [self ame317_loadStorage];
    if (!storage[key]) return YES;
    [storage removeObjectForKey:key];
    return [self ame317_saveStorage:storage];
}

- (NSArray *)storageKeys {
    if (![self ame317_requirePerm:@"storage"]) return nil;
    return [[self ame317_loadStorage] allKeys] ?: @[];
}

#pragma mark - 网络（net，高危）

- (void)fetch:(NSString *)urlString options:(NSDictionary *)opts callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"net"]) return;
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url.scheme || !url.host) {
        [self ame317_callCallback:cb arguments:@[localize(@"ame317.bridge.bad_url", nil), [NSNull null]]];
        return;
    }
    NSString *method = [self ame317_string:opts[@"method"]] ?: @"GET";
    if (![@[@"GET", @"POST", @"PUT", @"DELETE", @"HEAD"] containsObject:method.uppercaseString]) {
        method = @"GET";
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method.uppercaseString;
    req.timeoutInterval = 30;
    id headers = opts[@"headers"];
    if ([headers isKindOfClass:[NSDictionary class]]) {
        for (NSString *hk in headers) {
            id hv = headers[hk];
            if ([hv isKindOfClass:[NSString class]] && hk.length) {
                [req setValue:hv forHTTPHeaderField:hk];
            }
        }
    }
    id body = opts[@"body"];
    if ([body isKindOfClass:[NSString class]]) {
        req.HTTPBody = [(NSString *)body dataUsingEncoding:NSUTF8StringEncoding];
    }
    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            if (err) {
                [sself ame317_callCallback:cb
                                 arguments:@[err.localizedDescription ?: @"error", [NSNull null]]];
                return;
            }
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            NSString *text = data ? [[NSString alloc] initWithData:data
                                                          encoding:NSUTF8StringEncoding] : @"";
            if (!text && data.length) text = @"";
            [sself ame317_callCallback:cb
                             arguments:@[[NSNull null],
                                         @{@"status": @(http.statusCode),
                                           @"body": text ?: @""}]];
        });
    }] resume];
}

#pragma mark - 页面导航（ui.nav，Task327）

- (void)openPage:(NSString *)pageId {
    if (![self ame317_requirePerm:@"ui.nav"]) return;
    // 页面序 = ZL2ShellViewController ame_childForIndex 0...6（越界/未知拒绝）
    NSDictionary<NSString *, NSNumber *> *ame327_pageMap = @{
        @"home": @0, @"download": @1, @"versions": @2, @"accounts": @3,
        @"settings": @4, @"multiplayer": @5, @"ai": @6,
    };
    NSNumber *ame327_idx = ame327_pageMap[pageId ?: @""];
    if (!ame327_idx) {
        [self ame317_rejectValue:pageId ?: @""];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:ZL2ShellNavigateNotification
                          object:nil
                        userInfo:@{@"index": ame327_idx}];
    });
}

#pragma mark - 实例档案写（profile.write，高危，Task327）

/// 档案名规范：[a-zA-Z0-9._-]{1,64}（防脏名/分隔符注入 PLProfiles 注册表）
- (BOOL)ame327_validProfileName:(NSString *)name {
    if (name.length == 0 || name.length > 64) return NO;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    for (NSUInteger i = 0; i < name.length; i++) {
        if (![ok characterIsMember:[name characterAtIndex:i]]) return NO;
    }
    return YES;
}

- (BOOL)createProfile:(NSDictionary *)spec {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    if (![spec isKindOfClass:[NSDictionary class]]) return NO;
    NSString *name = [self ame317_string:spec[@"name"]];
    if (![self ame327_validProfileName:name]) {
        [self ame317_rejectValue:name ?: @""];
        return NO;
    }
    NSDictionary *profiles = [PLProfiles current].profiles;
    if (profiles[name] != nil) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile exists: %@", name]];
        return NO;
    }
    NSString *version = [self ame317_string:spec[@"version"]] ?: @"";
    NSString *gameDir = [self ame317_string:spec[@"gameDir"]];
    if (gameDir == nil) {
        const char *ame327_home = getenv("POJAV_HOME");
        gameDir = ame327_home
            ? [[NSString stringWithUTF8String:ame327_home]
               stringByAppendingPathComponent:
               [NSString stringWithFormat:@"instances/%@", name]]
            : @"";
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    if (version.length) entry[@"lastVersionId"] = version;
    if (gameDir.length) entry[@"gameDir"] = gameDir;
    [[PLProfiles current] applyChanges:^(NSMutableDictionary<NSString *, id> *ame327_all) {
        ame327_all[name] = [entry copy];
    }];
    // 游戏目录落位（骨架 six-dir 留给 ame325/ame327 自愈链补齐，此处仅建根）
    if (gameDir.length && ![NSFileManager.defaultManager fileExistsAtPath:gameDir]) {
        [NSFileManager.defaultManager createDirectoryAtPath:gameDir
                               withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    return YES;
}

- (BOOL)deleteProfile:(NSString *)name {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    if (![self ame327_validProfileName:name]) {
        [self ame317_rejectValue:name ?: @""];
        return NO;
    }
    // 守卫：默认档案与当前选中档案不删（防自毁；先切档再删）
    if ([name isEqualToString:@"(Default)"] ||
        [name isEqualToString:[PLProfiles current].selectedProfileName]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile in use: %@", name]];
        return NO;
    }
    if ([PLProfiles current].profiles[name] == nil) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", name]];
        return NO;
    }
    [[PLProfiles current] applyChanges:^(NSMutableDictionary<NSString *, id> *ame327_all) {
        [ame327_all removeObjectForKey:name];
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    return YES;
}

#pragma mark - 游戏目录文件沙盒（files.game，高危，Task327）

static const NSUInteger ame327_fileReadMax = 2 * 1024 * 1024;
static const NSUInteger ame327_fileWriteMax = 4 * 1024 * 1024;

/// 路径守卫：仅当前实例 POJAV_GAME_DIR 内相对路径（禁 ..//绝对路径/
/// symlink 逃逸）；返回已拼好的绝对路径（不要求存在）
- (NSString *)ame327_gamePathFor:(NSString *)relPath {
    const char *ame327_env = getenv("POJAV_GAME_DIR");
    if (!ame327_env || !*ame327_env) return nil;
    if (relPath.length == 0 || relPath.length > 512) return nil;
    if ([relPath hasPrefix:@"/"]) return nil;
    for (NSString *ame327_seg in [relPath pathComponents]) {
        if ([ame327_seg isEqualToString:@".."] || ame327_seg.length == 0) return nil;
    }
    NSString *ame327_base = [NSString stringWithUTF8String:ame327_env];
    NSString *ame327_full = [ame327_base stringByAppendingPathComponent:relPath];
    NSString *ame327_resolved = [ame327_full stringByResolvingSymlinksInPath];
    NSString *ame327_resolvedBase = [ame327_base stringByResolvingSymlinksInPath];
    if (![ame327_resolved hasPrefix:ame327_resolvedBase]) return nil;   // symlink 逃逸
    return ame327_full;
}

- (NSArray<NSDictionary *> *)listGameFiles:(NSString *)relPath {
    if (![self ame317_requirePerm:@"files.game"]) return nil;
    NSString *ame327_dir = [self ame327_gamePathFor:relPath ?: @""];
    if (!ame327_dir) return nil;
    NSFileManager *ame327_fm = [NSFileManager defaultManager];
    BOOL ame327_isDir = NO;
    if (![ame327_fm fileExistsAtPath:ame327_dir isDirectory:&ame327_isDir] || !ame327_isDir) return nil;
    NSArray<NSString *> *ame327_names = [ame327_fm contentsOfDirectoryAtPath:ame327_dir error:nil];
    NSMutableArray<NSDictionary *> *ame327_out = [NSMutableArray array];
    for (NSString *ame327_nm in [ame327_names sortedArrayUsingSelector:@selector(compare:)]) {
        if ([ame327_nm hasPrefix:@"."]) continue;
        NSString *ame327_p = [ame327_dir stringByAppendingPathComponent:ame327_nm];
        BOOL ame327_d = NO;
        [ame327_fm fileExistsAtPath:ame327_p isDirectory:&ame327_d];
        NSUInteger ame327_sz = 0;
        if (!ame327_d) {
            NSDictionary *ame327_at = [ame327_fm attributesOfItemAtPath:ame327_p error:nil];
            ame327_sz = [ame327_at fileSize];
        }
        [ame327_out addObject:@{
            @"name": ame327_nm,
            @"isDir": @(ame327_d),
            @"size": @(ame327_sz),
        }];
    }
    return ame327_out;
}

- (NSString *)readGameFile:(NSString *)relPath {
    if (![self ame317_requirePerm:@"files.game"]) return nil;
    NSString *ame327_p = [self ame327_gamePathFor:relPath ?: @""];
    if (!ame327_p) return nil;
    NSDictionary *ame327_at = [NSFileManager.defaultManager attributesOfItemAtPath:ame327_p error:nil];
    if ([ame327_at fileSize] > ame327_fileReadMax) return nil;   // 超限拒读
    return [NSString stringWithContentsOfFile:ame327_p
                                     encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)writeGameFile:(NSString *)relPath
              content:(NSString *)content
               append:(BOOL)append {
    if (![self ame317_requirePerm:@"files.game"]) return NO;
    NSString *ame327_p = [self ame327_gamePathFor:relPath ?: @""];
    if (!ame327_p || content.length > ame327_fileWriteMax) return NO;
    NSFileManager *ame327_fm = [NSFileManager defaultManager];
    NSString *ame327_dir = ame327_p.stringByDeletingLastPathComponent;
    if (![ame327_fm fileExistsAtPath:ame327_dir]) {
        [ame327_fm createDirectoryAtPath:ame327_dir
             withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSData *ame327_data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (!ame327_data) return NO;
    if (append && [ame327_fm fileExistsAtPath:ame327_p]) {
        NSMutableData *ame327_mut = [NSMutableData dataWithContentsOfFile:ame327_p] ?: [NSMutableData data];
        [ame327_mut appendData:ame327_data];
        if (ame327_mut.length > ame327_fileWriteMax) return NO;
        return [ame327_mut writeToFile:ame327_p atomically:YES];
    }
    return [ame327_data writeToFile:ame327_p atomically:YES];
}

- (BOOL)removeGameFile:(NSString *)relPath {
    if (![self ame317_requirePerm:@"files.game"]) return NO;
    NSString *ame327_p = [self ame327_gamePathFor:relPath ?: @""];
    if (!ame327_p) return NO;
    NSFileManager *ame327_fm = [NSFileManager defaultManager];
    BOOL ame327_isDir = NO;
    if (![ame327_fm fileExistsAtPath:ame327_p isDirectory:&ame327_isDir]) return NO;
    if (ame327_isDir) {
        // 仅空目录可删（防一键清空用户存档/模组树）
        NSArray *ame327_children = [ame327_fm contentsOfDirectoryAtPath:ame327_p error:nil];
        if (ame327_children.count > 0) return NO;
    }
    return [ame327_fm removeItemAtPath:ame327_p error:nil];
}

#pragma mark - 视图操纵（ui.views，高危，Task364）

static const NSUInteger ame364_findLimitDefault = 24;
static const NSUInteger ame364_findLimitMax = 64;
static const NSUInteger ame364_maxHandles = 256;
static const CGFloat ame364_coordClamp = 100000.0;

/// 禁改名单：游戏渲染面子树（含 SDL/Metal 表面与滚动包裹层）。查询跳过、
/// 改写/挂手势拒绝——插件碰渲染面 = 游戏黑屏/输入断链，结构性不可触碰。
static BOOL ame364_isProtectedClass(NSString *cls) {
    return [cls isEqualToString:@"SurfaceView"]
        || [cls isEqualToString:@"GameSurfaceView"]
        || [cls isEqualToString:@"ScrollableSurfaceView"];
}

/// 元素可读文本（UILabel/UIButton/UITextField/UITextView best-effort）
static NSString *ame364_bestText(UIView *v) {
    if ([v isKindOfClass:[UILabel class]]) return ((UILabel *)v).text;
    if ([v isKindOfClass:[UIButton class]]) return [((UIButton *)v) titleForState:UIControlStateNormal];
    if ([v isKindOfClass:[UITextField class]]) return ((UITextField *)v).text;
    if ([v isKindOfClass:[UITextView class]]) return ((UITextView *)v).text;
    return nil;
}

/// 视图可读名（匿名容器降级为短类名，NSArray 数组类名等长前缀去掉）
static NSString *ame364_clsName(UIView *v) {
    return NSStringFromClass(v.class) ?: @"UIView";
}

/// 遍历窗列表（只取公开 UIWindow 类 = 排除键盘/特效等私有系统窗）
- (NSArray<UIWindow *> *)ame364_windows {
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in scene.windows) {
            if ([NSStringFromClass(w.class) isEqualToString:@"UIWindow"]) [out addObject:w];
        }
    }
    if (out.count == 0) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if ([NSStringFromClass(w.class) isEqualToString:@"UIWindow"]) [out addObject:w];
        }
    }
    return out;
}

/// 深度优先收集（pre-order；过滤感知：节点过筛才计入，遍历不截断→limit 是
/// 匹配数上限不是扫描数上限；禁改名单子树整枝跳过；隐藏视图照收集带标记，
/// 供"找回来显示"类修复场景；窗内根视图自身不入表——只收子视图）
- (void)ame364_walk:(UIView *)v windowIndex:(NSUInteger)wi
              out:(NSMutableArray<NSMutableDictionary *> *)out
           filter:(NSDictionary *)f
            limit:(NSUInteger)limit depth:(NSUInteger)depth {
    if (out.count >= limit || depth > 40) return;
    NSString *cls = ame364_clsName(v);
    if (ame364_isProtectedClass(cls)) return;   // 禁改子树整枝剪掉
    NSString *fCls = [self ame317_string:f[@"cls"]];
    NSString *fText = [self ame317_string:f[@"text"]];
    NSString *fIdent = [self ame317_string:f[@"ident"]];
    id fTag = f[@"tag"];
    for (UIView *child in v.subviews) {
        if (out.count >= limit) return;
        NSString *ccls = ame364_clsName(child);
        if (ame364_isProtectedClass(ccls)) continue;
        NSString *text = ame364_bestText(child) ?: @"";
        // 过滤（cls/text 大小写不敏感子串；ident/tag 精确；无筛键 = 全量浏览）
        if (fCls.length && [ccls rangeOfString:fCls options:NSCaseInsensitiveSearch].location == NSNotFound) {
            [self ame364_walk:child windowIndex:wi out:out filter:f limit:limit depth:depth + 1];
            continue;
        }
        if (fText.length && [text rangeOfString:fText options:NSCaseInsensitiveSearch].location == NSNotFound) {
            [self ame364_walk:child windowIndex:wi out:out filter:f limit:limit depth:depth + 1];
            continue;
        }
        if (fIdent != nil && ![child.accessibilityIdentifier ?: @"" isEqualToString:fIdent]) {
            [self ame364_walk:child windowIndex:wi out:out filter:f limit:limit depth:depth + 1];
            continue;
        }
        if (fTag != nil && [fTag isKindOfClass:[NSNumber class]]
            && (double)child.tag != [fTag doubleValue]) {
            [self ame364_walk:child windowIndex:wi out:out filter:f limit:limit depth:depth + 1];
            continue;
        }
        NSUInteger h = [self ame364_registerView:child];
        NSMutableDictionary *node = [NSMutableDictionary dictionary];
        node[@"handle"] = @(h);
        node[@"cls"] = ccls;
        node[@"text"] = text;
        node[@"ident"] = child.accessibilityIdentifier ?: @"";
        node[@"tag"] = @(child.tag);
        node[@"frame"] = @{@"x": @(child.frame.origin.x), @"y": @(child.frame.origin.y),
                           @"w": @(child.frame.size.width), @"h": @(child.frame.size.height)};
        node[@"alpha"] = @(child.alpha);
        node[@"hidden"] = @(child.hidden);
        // ★ r1：UIView 无 enabled 属性（CI 编译实锤）——enabled 归 UIControl，
        //   非 UIControl 容器恒报可点（与 UIKit 语义一致）
        node[@"enabled"] = @([child isKindOfClass:[UIControl class]]
                                 ? ((UIControl *)child).enabled : YES);
        node[@"win"] = @(wi);
        [out addObject:node];
        [self ame364_walk:child windowIndex:wi out:out filter:f limit:limit depth:depth + 1];
    }
}

/// 句柄登记（同视图复用既有句柄；容量上限防失控）
- (NSUInteger)ame364_registerView:(UIView *)v {
    // ★ r1：NSMapTable 快速枚举是键值混合 id 流（CI 编译实锤：
    //   unsignedIntegerValue not found on __strong id）——用 keyEnumerator
    //   只取键，反向比对弱值指针
    for (NSNumber *k in [self.viewTable keyEnumerator]) {
        if ([self.viewTable objectForKey:k] == v) return k.unsignedIntegerValue;
    }
    NSUInteger h = ++self.viewHandleSeed;
    [self.viewTable setObject:v forKey:@(h)];
    return h;
}

/// 句柄取视图（nil = stale：视图已释放或从未登记）
- (UIView *)ame364_viewForHandle:(double)handle {
    if (!(handle >= 1) || handle != floor(handle) || handle > (double)ame364_maxHandles * 4096) return nil;
    return [self.viewTable objectForKey:@((NSUInteger)handle)];
}

- (NSArray *)viewsFind:(NSDictionary *)filter {
    if (![self ame317_requirePerm:@"ui.views"]) return nil;
    if (filter && ![filter isKindOfClass:[NSDictionary class]]) filter = nil;
    filter = [self ame317_unwrapJs:filter] ?: @{};
    NSUInteger limit = ame364_findLimitDefault;
    id fLimit = filter[@"limit"];
    // ★ r2：id 类型不支持属性点语法（CI 编译实锤：property not found on
    //   __strong id）——判型后显式转 NSNumber 再取值
    if ([fLimit isKindOfClass:[NSNumber class]]) {
        NSUInteger ame364_req = [(NSNumber *)fLimit unsignedIntegerValue];
        if (ame364_req > 0) limit = MIN(ame364_req, ame364_findLimitMax);
    }
    NSMutableArray<NSMutableDictionary *> *out = [NSMutableArray array];
    NSArray<UIWindow *> *windows = [self ame364_windows];
    for (NSUInteger wi = 0; wi < windows.count && out.count < limit; wi++) {
        [self ame364_walk:windows[wi] windowIndex:wi out:out filter:filter limit:limit depth:0];
    }
    return [out copy];
}

/// #RRGGBB / #RRGGBBAA → UIColor（主题令牌同款值域）
static UIColor *ame364_colorFromString(NSString *s) {
    if (s.length != 7 && s.length != 9) return nil;
    if (![s hasPrefix:@"#"]) return nil;
    unsigned long long v = 0;
    for (NSUInteger i = 1; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        unsigned long long d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else return nil;
        v = v * 16 + d;
    }
    if (s.length == 7) {
        return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                               green:((v >> 8) & 0xFF) / 255.0
                                blue:(v & 0xFF) / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:((v >> 24) & 0xFF) / 255.0
                           green:((v >> 16) & 0xFF) / 255.0
                            blue:((v >> 8) & 0xFF) / 255.0
                           alpha:(v & 0xFF) / 255.0];
}

- (BOOL)viewsApply:(double)handle props:(NSDictionary *)props {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"stale handle: %g", handle]];
        return NO;
    }
    if (ame364_isProtectedClass(ame364_clsName(v))) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"protected view: %@", ame364_clsName(v)]];
        return NO;
    }
    props = [self ame317_unwrapJs:props] ?: @{};
    if (![props isKindOfClass:[NSDictionary class]] || props.count == 0) return NO;
    NSNumber *n;
    // 首改留痕（reset 还原基准；只记一次 = 首次改动前状态）
    NSNumber *hk = @((NSUInteger)handle);
    if (!self.viewOriginals[hk]) {
        self.viewOriginals[hk] = @{
            @"frame": [NSValue valueWithCGRect:v.frame],
            @"alpha": @(v.alpha),
            @"hidden": @(v.hidden),
        };
    }
    if ((n = [self ame364_num:props[@"x"]]))  { CGRect f = v.frame; f.origin.x = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"y"]]))  { CGRect f = v.frame; f.origin.y = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"w"]]))  { CGRect f = v.frame; f.size.width = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"h"]]))  { CGRect f = v.frame; f.size.height = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"alpha"]])) { v.alpha = MAX(0.0, MIN(1.0, n.doubleValue)); }
    if (props[@"hidden"] != nil) v.hidden = [props[@"hidden"] boolValue];
    // ★ r1：enabled 写面收窄到 UIControl（UIView 无此属性，CI 编译实锤）
    if (props[@"enabled"] != nil && [v isKindOfClass:[UIControl class]]) {
        ((UIControl *)v).enabled = [props[@"enabled"] boolValue];
    }
    if ((n = [self ame364_num:props[@"cornerRadius"]])) {
        v.layer.cornerRadius = MAX(0, MIN(200, n.doubleValue));
        v.layer.masksToBounds = v.layer.cornerRadius > 0 ? YES : v.layer.masksToBounds;
    }
    NSString *text = [self ame317_string:props[@"text"]];
    if (text) {
        if ([v isKindOfClass:[UILabel class]]) ((UILabel *)v).text = text;
        else if ([v isKindOfClass:[UIButton class]]) {
            [((UIButton *)v) setTitle:text forState:UIControlStateNormal];
            [((UIButton *)v) setTitle:text forState:UIControlStateHighlighted];
        }
        else if ([v isKindOfClass:[UITextField class]]) ((UITextField *)v).text = text;
        else if ([v isKindOfClass:[UITextView class]]) ((UITextView *)v).text = text;
    }
    NSString *bg = [self ame317_string:props[@"bg"]];
    if (bg) {
        UIColor *c = ame364_colorFromString(bg);
        if (c) v.backgroundColor = c;
    }
    return YES;
}

/// 有限数字防呆（NaN/Inf/非数值一律 nil）
- (NSNumber *)ame364_num:(id)raw {
    if (![raw isKindOfClass:[NSNumber class]]) return nil;
    double d = [raw doubleValue];
    if (!isfinite(d)) return nil;
    return raw;
}

- (BOOL)viewsOn:(double)handle event:(NSString *)event handler:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"stale handle: %g", handle]];
        return NO;
    }
    if (ame364_isProtectedClass(ame364_clsName(v))) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"protected view: %@", ame364_clsName(v)]];
        return NO;
    }
    if (event.length == 0 || !cb.isObject) return NO;
    if (![@[@"tap", @"pan", @"longpress", @"swipe"] containsObject:event]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"unknown gesture: %@", event]];
        return NO;
    }
    NSNumber *hk = @((NSUInteger)handle);
    NSMutableArray<Ame364GestureSink *> *sinks = self.viewSinks[hk];
    if (!sinks) { sinks = [NSMutableArray array]; self.viewSinks[hk] = sinks; }
    // 同 (handle,event) 复用：换回调不叠手势（重复 on 不产生双触发）
    for (Ame364GestureSink *old in sinks) {
        if ([old.event isEqualToString:event]) {
            old.cb = cb;
            return YES;
        }
    }
    Ame364GestureSink *sink = [[Ame364GestureSink alloc] init];
    sink.handle = (NSUInteger)handle;
    sink.event = event;
    sink.cb = cb;
    sink.bridge = self;
    UIGestureRecognizer *gr = nil;
    if ([event isEqualToString:@"pan"]) {
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc]
            initWithTarget:sink action:@selector(ame364_fired:)];
        p.cancelsTouchesInView = YES;   // 拖拽型手势接管触摸（按钮拖动不触发其点击）
        gr = p;
    } else if ([event isEqualToString:@"tap"]) {
        gr = [[UITapGestureRecognizer alloc] initWithTarget:sink action:@selector(ame364_fired:)];
    } else if ([event isEqualToString:@"longpress"]) {
        gr = [[UILongPressGestureRecognizer alloc] initWithTarget:sink action:@selector(ame364_fired:)];
    } else {
        gr = [[UISwipeGestureRecognizer alloc] initWithTarget:sink action:@selector(ame364_fired:)];
    }
    sink.gesture = gr;
    [v addGestureRecognizer:gr];
    [sinks addObject:sink];
    return YES;
}

/// 手势事件进 JS（增量 dx/dy + 累计 tx/ty + 当前 frame + 窗口坐标 x/y）
- (void)ame364_gestureFired:(UIGestureRecognizer *)gr sink:(Ame364GestureSink *)sink {
    UIView *v = gr.view;
    if (!v) return;
    NSMutableDictionary *ev = [NSMutableDictionary dictionary];
    ev[@"type"] = sink.event;
    CGPoint loc = [gr locationInView:v.window];
    ev[@"x"] = @(loc.x);
    ev[@"y"] = @(loc.y);
    ev[@"frame"] = @{@"x": @(v.frame.origin.x), @"y": @(v.frame.origin.y),
                     @"w": @(v.frame.size.width), @"h": @(v.frame.size.height)};
    NSString *state = @"changed";
    if (gr.state == UIGestureRecognizerStateBegan) state = @"began";
    else if (gr.state == UIGestureRecognizerStateChanged) state = @"changed";
    else if (gr.state == UIGestureRecognizerStateEnded) state = @"ended";
    else if (gr.state == UIGestureRecognizerStateCancelled
             || gr.state == UIGestureRecognizerStateFailed) state = @"cancelled";
    ev[@"state"] = state;
    if ([gr isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gr;
        // ★ 窗口坐标系测增量：视图自身随拖动位移，view 坐标系会漂移；
        //   window 恒定 = dx/dy 就是手指真实位移，拖拽插件零漂移
        CGPoint delta = [pan translationInView:v.window];
        // 增量口径：上报后清零，dx/dy = 距上次事件位移（began=0 起点）
        ev[@"dx"] = @(delta.x);
        ev[@"dy"] = @(delta.y);
        // 累计口径：js 侧一般用 start.frame + tx/ty（提示词标准写法），
        // 这里再给一份自手势起的累计值（OBJC 侧自己累加，began 时清累计器）
        CGPoint acc = CGPointMake(0, 0);
        NSValue *av = objc_getAssociatedObject(gr, @selector(ame364_fired:));
        if (av) acc = av.CGPointValue;
        if ([state isEqualToString:@"began"]) acc = CGPointMake(0, 0);
        acc = CGPointMake(acc.x + delta.x, acc.y + delta.y);
        objc_setAssociatedObject(gr, @selector(ame364_fired:), [NSValue valueWithCGPoint:acc],
                                 OBJC_ASSOCIATION_RETAIN);
        ev[@"tx"] = @(acc.x);
        ev[@"ty"] = @(acc.y);
        [pan setTranslation:CGPointZero inView:v.window];
    }
    if ([gr isKindOfClass:[UISwipeGestureRecognizer class]]) {
        UISwipeGestureRecognizerDirection d = ((UISwipeGestureRecognizer *)gr).direction;
        ev[@"direction"] = d == UISwipeGestureRecognizerDirectionUp ? @"up"
                         : d == UISwipeGestureRecognizerDirectionDown ? @"down"
                         : d == UISwipeGestureRecognizerDirectionLeft ? @"left" : @"right";
    }
    [self ame317_callCallback:sink.cb arguments:@[ev]];
}

- (BOOL)viewsReset:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    NSNumber *hk = @((NSUInteger)handle);
    if (v) {
        if (ame364_isProtectedClass(ame364_clsName(v))) return NO;
        // 只摘本插件挂的手势（sink.gesture 精确指认，不碰他人/系统手势）
        for (Ame364GestureSink *s in self.viewSinks[hk] ?: @[]) {
            if (s.gesture) [v removeGestureRecognizer:s.gesture];
        }
        // 还原首改前几何
        NSDictionary *orig = self.viewOriginals[hk];
        if (orig) {
            v.frame = [orig[@"frame"] CGRectValue];
            v.alpha = [orig[@"alpha"] doubleValue];
            v.hidden = [orig[@"hidden"] boolValue];
            [self.viewOriginals removeObjectForKey:hk];
        }
        // ★ Task366：还原样式首改（textColor/font/边框）
        NSDictionary *style = self.viewStyleOriginals[hk];
        if (style) {
            UIColor *tc = style[@"textColor"];
            if (tc) [self ame366_setTextColor:tc on:v];
            UIFont *font = style[@"font"];
            if (font) [self ame366_setFont:font on:v];
            v.layer.borderWidth = [style[@"borderWidth"] doubleValue];
            UIColor *bc = style[@"borderColor"];
            v.layer.borderColor = bc ? bc.CGColor : nil;
            [self.viewStyleOriginals removeObjectForKey:hk];
        }
    }
    [self.viewSinks removeObjectForKey:hk];
    return v != nil;
}

/// 插件卸载：摘全部手势 + 还原全部几何 + 清注册表（teardown 调用）
- (void)ame364_teardownViews {
    for (NSNumber *hk in [self.viewSinks allKeys]) {
        UIView *v = [self.viewTable objectForKey:hk];
        if (!v) continue;
        for (Ame364GestureSink *s in self.viewSinks[hk] ?: @[]) {
            if (s.gesture) [v removeGestureRecognizer:s.gesture];
        }
    }
    for (NSNumber *hk in [self.viewOriginals allKeys]) {
        UIView *v = [self.viewTable objectForKey:hk];
        NSDictionary *orig = self.viewOriginals[hk];
        if (v && orig) {
            v.frame = [orig[@"frame"] CGRectValue];
            v.alpha = [orig[@"alpha"] doubleValue];
            v.hidden = [orig[@"hidden"] boolValue];
        }
    }
    [self.viewSinks removeAllObjects];
    [self.viewOriginals removeAllObjects];
    [self.viewStyleOriginals removeAllObjects];
    [self.viewTable removeAllObjects];
    self.viewHandleSeed = 0;
}

#pragma mark - 自修复三件套（jit.read / jit.write / game.launch / logs.read，Task365）

/// JIT 状态（jit.read，安全）：enabled=进程内 isJITEnabled 实测；setupState=
/// 内置轨四态（enabled/ready/waitingConfiguration/unavailable）；
/// builtinTrackAvailable=Task294 内置轨可用性（iOS 17.4+ 配对文件在位）；
/// scheme=debug.jit_enabler 偏好（auto/builtin/stikjit/trollstore/...）。
- (NSDictionary *)getJITState {
    if (![self ame317_requirePerm:@"jit.read"]) return nil;
    NSString *ame365_stateName = nil;
    switch ([StikDebugViewController ame291_setupState]) {
        case Ame291JITSetupStateEnabled:                 ame365_stateName = @"enabled"; break;
        case Ame291JITSetupStateReady:                   ame365_stateName = @"ready"; break;
        case Ame291JITSetupStateWaitingConfiguration:    ame365_stateName = @"waitingConfiguration"; break;
        case Ame291JITSetupStateUnavailable:
        default:                                          ame365_stateName = @"unavailable"; break;
    }
    id ame365_scheme = getPrefObject(@"debug.jit_enabler");
    return @{
        @"enabled": @(isJITEnabled(NO)),
        @"setupState": ame365_stateName,
        @"builtinTrackAvailable": @([StikDebugViewController ame294_builtinTrackAvailable]),
        @"scheme": [ame365_scheme isKindOfClass:[NSString class]] ? ame365_scheme : @"auto",
    };
}

/// 触发内置 JIT 开启（jit.write，高危）：Task294 共享入口（JIT 管理页/
/// RightPanel/JavaLauncher 三处同源），completion 必达；回调体回主线程后进 JS
/// （ame317_callCallback 主线程契约）。unavailable/unready 时 message 为可展示
/// 文案，插件侧应引导用户去 设置 → 调试 配置配对文件/方案。
- (void)enableJIT:(JSValue *)cb {
    if (![self ame317_requirePerm:@"jit.write"]) return;
    if (!cb.isObject) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak typeof(self) wself = self;
        [StikDebugViewController ame294_enableBuiltinJITWithCompletion:^(BOOL success, NSString *message) {
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            [sself ame317_callCallback:cb arguments:@[@{ @"success": @(success),
                                                         @"message": message ?: @"" }]];
        }];
    });
}

/// 触发游戏启动（game.launch，高危）：主页启动按钮同款全链（版本校验→
/// 下载/verify→JIT 门禁→换根 SurfaceViewController→launchJVM）；profile
/// 可选切换当前选中实例（与设置页同源 setSelectedProfileName，
/// SelectedProfileChanged 广播 → 插件 profile.changed 事件照常）；游戏
/// 运行中/界面未就绪拒绝。回调 {ok,message} = 接受/拒绝语义（启动结果
/// 由 game.starting / game.exited 事件覆盖，launchJVM 阻塞至退出不回调）。
- (void)launchGameWithProfile:(NSDictionary *)opts callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"game.launch"]) return;
    if (!cb.isObject) return;
    NSDictionary *spec = [self ame317_unwrapJs:opts] ?: @{};
    void (^ame365_respond)(BOOL, NSString *) = ^(BOOL ok, NSString *msg) {
        [self ame317_callCallback:cb arguments:@[@{ @"ok": @(ok), @"message": msg ?: @"" }]];
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *profile = [self ame317_string:spec[@"profile"]];
        if (profile.length > 0) {
            if ([PLProfiles current].profiles[profile] == nil) {
                [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", profile]];
                ame365_respond(NO, [NSString stringWithFormat:@"实例档案不存在：%@", profile]);
                return;
            }
            [[PLProfiles current] setSelectedProfileName:profile];
        }
        UIWindow *window = [self ame317_keyWindow];
        UIViewController *root = window.rootViewController;
        if ([NSStringFromClass(root.class) isEqualToString:@"SurfaceViewController"]) {
            ame365_respond(NO, @"游戏正在运行，无法重复启动；请先退出游戏。");
            return;
        }
        if (![root isKindOfClass:[ZL2ShellViewController class]]) {
            ame365_respond(NO, @"启动器界面未就绪（欢迎/引导流程中），请稍后再试。");
            return;
        }
        UIViewController *home = [(ZL2ShellViewController *)root ame_childForIndex:0];
        if (!home || ![NSStringFromClass(home.class) isEqualToString:@"ZL2HomeViewController"]) {
            ame365_respond(NO, @"主页未就绪，无法启动游戏。");
            return;
        }
        [(ZL2HomeViewController *)home launchButtonTapped];
        ame365_respond(YES, @"已进入启动流程（版本校验 → JIT 门禁 → 启动）。启动/退出会以 game.starting / game.exited 事件广播。");
    });
}

/// 日志尾部读取（logs.read，安全）：which ∈ launcher（POJAV_HOME/latestlog.txt，
/// 含游戏 stdout 重定向，诊断首选）/ launcherOld / game（实例 logs/latest.log）/
/// crash（实例 crash-reports 最新 .txt）。行数上限 1000（默认 200）、单行截断
/// 2000 字、总量封顶 48KB 保尾。
- (NSString *)readLog:(NSString *)which limit:(double)maxLines {
    if (![self ame317_requirePerm:@"logs.read"]) return nil;
    NSString *key = which.length ? which : @"launcher";
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    NSString *path = nil;
    if ([key isEqualToString:@"launcher"]) {
        path = home.length ? [home stringByAppendingPathComponent:@"latestlog.txt"] : nil;
    } else if ([key isEqualToString:@"launcherOld"]) {
        path = home.length ? [home stringByAppendingPathComponent:@"latestlog.old.txt"] : nil;
    } else if ([key isEqualToString:@"game"]) {
        const char *gd = getenv("POJAV_GAME_DIR");
        path = (gd && *gd) ? [[NSString stringWithUTF8String:gd] stringByAppendingPathComponent:@"logs/latest.log"] : nil;
    } else if ([key isEqualToString:@"crash"]) {
        path = [self ame365_latestCrashReportPath];
    } else {
        [self ame317_rejectValue:[NSString stringWithFormat:@"unknown log: %@", key]];
        return nil;
    }
    if (path.length == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0) return nil;
    if (data.length > 4 * 1024 * 1024) {
        data = [data subdataWithRange:NSMakeRange(data.length - 4 * 1024 * 1024, 4 * 1024 * 1024)];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) return nil;
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        [lines addObject:line.length > 2000 ? [line substringToIndex:2000] : line];
    }
    NSUInteger n = 200;
    if (maxLines >= 1) n = (NSUInteger)MIN((double)maxLines, 1000.0);
    NSUInteger start = lines.count > n ? lines.count - n : 0;
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = start; i < lines.count; i++) {
        [out appendString:lines[i]];
        [out appendString:@"\n"];
        if (out.length > 48 * 1024) {
            // 总量封顶：丢头部保尾部（诊断价值集中在尾段）
            NSRange cut = [out rangeOfString:@"\n" options:0];
            if (cut.location != NSNotFound && cut.location < out.length - 1) {
                [out deleteCharactersInRange:NSMakeRange(0, cut.location + 1)];
            }
        }
    }
    return out;
}

/// 最新崩溃报告路径（实例 crash-reports / logs/crash-reports 取 mtime 最新）
- (NSString *)ame365_latestCrashReportPath {
    const char *gd = getenv("POJAV_GAME_DIR");
    if (!gd || !*gd) return nil;
    NSString *root = [NSString stringWithUTF8String:gd];
    NSArray *candidates = @[
        [root stringByAppendingPathComponent:@"logs/crash-reports"],
        [root stringByAppendingPathComponent:@"crash-reports"],
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *best = nil;
    NSDate *bestDate = nil;
    for (NSString *dir in candidates) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if (![name hasSuffix:@".txt"]) continue;
            NSString *p = [dir stringByAppendingPathComponent:name];
            NSDate *d = [fm attributesOfItemAtPath:p error:nil][NSFileModificationDate];
            if (!bestDate || [d compare:bestDate] == NSOrderedDescending) { bestDate = d; best = p; }
        }
    }
    return best;
}

#pragma mark - Task366 app 元信息（settings.read，安全）

- (nullable NSDictionary *)getAppInfo {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    NSDictionary *info = [NSBundle mainBundle].infoDictionary ?: @{};
    return @{
        @"name": info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"Prisma",
        @"version": info[@"CFBundleShortVersionString"] ?: @"",
        @"build": info[(NSString *)kCFBundleVersionKey] ?: @"",
        @"bundleId": info[@"CFBundleIdentifier"] ?: @"",
        @"iosVersion": [UIDevice currentDevice].systemVersion ?: @"",
        @"device": [UIDevice currentDevice].model ?: @"",
        @"darkMode": @([self ame366_isDarkMode]),
    };
}

- (nullable NSDictionary *)getAppPaths {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    const char *home = getenv("POJAV_HOME");
    const char *game = getenv("POJAV_GAME_DIR");
    return @{
        @"home": (home && *home) ? @(home) : @"",
        @"gameDir": (game && *game) ? @(game) : @"",
        @"pluginsDir": ame317_pluginsRootDir() ?: @"",
        @"documents": [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] ?: @"",
    };
}

- (nullable NSDictionary *)getAppMemory {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) != KERN_SUCCESS) {
        return nil;
    }
    return @{
        @"usedBytes": @((double)vmInfo.phys_footprint),
        @"uptimeSeconds": @([[NSProcessInfo processInfo] systemUptime]),
    };
}

- (double)getAppUptime {
    if (![self ame317_requirePerm:@"settings.read"]) return -1;
    return [[NSProcessInfo processInfo] systemUptime];
}

- (nullable NSDictionary *)getScreenInfo {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    UIWindow *w = [self ame317_keyWindow];
    UIScreen *screen = w.screen ?: [UIScreen mainScreen];
    return @{
        @"width": @(screen.bounds.size.width),
        @"height": @(screen.bounds.size.height),
        @"scale": @(screen.scale),
        @"safeAreaTop": @(w.safeAreaInsets.top),
        @"safeAreaBottom": @(w.safeAreaInsets.bottom),
    };
}

- (BOOL)ame366_isDarkMode {
    return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
}

#pragma mark - Task366 视图操纵扩展（ui.views†）

- (nullable NSDictionary *)viewsDescribe:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return nil;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return nil;
    NSMutableDictionary *node = [NSMutableDictionary dictionary];
    node[@"handle"] = @(handle);
    node[@"cls"] = ame364_clsName(v);
    node[@"text"] = ame364_bestText(v) ?: @"";
    node[@"ident"] = v.accessibilityIdentifier ?: @"";
    node[@"tag"] = @(v.tag);
    node[@"frame"] = @{@"x": @(v.frame.origin.x), @"y": @(v.frame.origin.y),
                       @"w": @(v.frame.size.width), @"h": @(v.frame.size.height)};
    node[@"alpha"] = @(v.alpha);
    node[@"hidden"] = @(v.hidden);
    node[@"enabled"] = @([v isKindOfClass:[UIControl class]] ? ((UIControl *)v).enabled : YES);
    node[@"userInteractionEnabled"] = @(v.userInteractionEnabled);
    node[@"cornerRadius"] = @(v.layer.cornerRadius);
    node[@"childrenCount"] = @((NSUInteger)v.subviews.count);
    node[@"gestureCount"] = @((NSUInteger)v.gestureRecognizers.count);
    NSString *bgHex = [self ame366_hexFromColor:v.backgroundColor];
    if (bgHex) node[@"bg"] = bgHex;
    return node;
}

- (nullable NSArray *)viewsChildren:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return nil;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *child in v.subviews) {
        if (out.count >= ame364_findLimitMax) break;
        if (ame364_isProtectedClass(ame364_clsName(child))) continue;
        NSUInteger h = [self ame364_registerView:child];
        [out addObject:@{@"handle": @(h), @"cls": ame364_clsName(child),
                         @"text": ame364_bestText(child) ?: @"",
                         @"frame": @{@"x": @(child.frame.origin.x), @"y": @(child.frame.origin.y),
                                     @"w": @(child.frame.size.width), @"h": @(child.frame.size.height)}}];
    }
    return out;
}

- (nullable NSDictionary *)viewsParent:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return nil;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v) return nil;
    UIView *p = v.superview;
    if (!p || ame364_isProtectedClass(ame364_clsName(p))) return nil;
    NSUInteger h = [self ame364_registerView:p];
    return @{@"handle": @(h), @"cls": ame364_clsName(p),
             @"text": ame364_bestText(p) ?: @""};
}

- (BOOL)viewsTap:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return NO;
    if (![v isKindOfClass:[UIControl class]] || !((UIControl *)v).enabled) return NO;
    [((UIControl *)v) sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

- (BOOL)viewsScroll:(double)handle props:(NSDictionary *)props {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return NO;
    if (![v isKindOfClass:[UIScrollView class]]) return NO;
    props = [self ame317_unwrapJs:props] ?: @{};
    CGPoint offset = ((UIScrollView *)v).contentOffset;
    NSNumber *n;
    if ((n = [self ame364_num:props[@"x"]])) offset.x = n.doubleValue;
    if ((n = [self ame364_num:props[@"y"]])) offset.y = n.doubleValue;
    BOOL animated = props[@"animated"] == nil ? YES : [props[@"animated"] boolValue];
    [((UIScrollView *)v) setContentOffset:offset animated:animated];
    return YES;
}

- (BOOL)viewsAnimate:(double)handle props:(NSDictionary *)props {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return NO;
    props = [self ame317_unwrapJs:props] ?: @{};
    NSNumber *n;
    CGRect target = v.frame;
    BOOL any = NO;
    if ((n = [self ame364_num:props[@"x"]])) { target.origin.x = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); any = YES; }
    if ((n = [self ame364_num:props[@"y"]])) { target.origin.y = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); any = YES; }
    if ((n = [self ame364_num:props[@"w"]])) { target.size.width = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); any = YES; }
    if ((n = [self ame364_num:props[@"h"]])) { target.size.height = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); any = YES; }
    CGFloat alpha = v.alpha;
    if ((n = [self ame364_num:props[@"alpha"]])) { alpha = MAX(0.0, MIN(1.0, n.doubleValue)); any = YES; }
    if (!any) return NO;
    double duration = 0.25;
    if ((n = [self ame364_num:props[@"duration"]])) duration = MAX(0.0, MIN(2.0, n.doubleValue));
    NSNumber *hk = @((NSUInteger)handle);
    if (!self.viewOriginals[hk]) {
        self.viewOriginals[hk] = @{
            @"frame": [NSValue valueWithCGRect:v.frame],
            @"alpha": @(v.alpha),
            @"hidden": @(v.hidden),
        };
    }
    [UIView animateWithDuration:duration animations:^{
        v.frame = target;
        v.alpha = alpha;
    }];
    return YES;
}

- (BOOL)viewsApplyStyle:(double)handle props:(NSDictionary *)props {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return NO;
    props = [self ame317_unwrapJs:props] ?: @{};
    if (![props isKindOfClass:[NSDictionary class]] || props.count == 0) return NO;
    NSNumber *hk = @((NSUInteger)handle);
    if (!self.viewStyleOriginals[hk]) {
        // 样式首改留痕（reset/卸载还原基准）
        NSMutableDictionary *orig = [NSMutableDictionary dictionary];
        UIColor *curText = [self ame366_textColorOf:v];
        if (curText) orig[@"textColor"] = curText;
        UIFont *curFont = [self ame366_fontOf:v];
        if (curFont) orig[@"font"] = curFont;
        orig[@"borderWidth"] = @(v.layer.borderWidth);
        if (v.layer.borderColor) orig[@"borderColor"] = [UIColor colorWithCGColor:v.layer.borderColor];
        self.viewStyleOriginals[hk] = orig;
    }
    BOOL any = NO;
    NSString *textColor = [self ame317_string:props[@"textColor"]];
    if (textColor) {
        UIColor *c = ame364_colorFromString(textColor);
        if (c) { [self ame366_setTextColor:c on:v]; any = YES; }
    }
    NSNumber *n;
    if ((n = [self ame364_num:props[@"fontSize"]]) || props[@"bold"] != nil) {
        BOOL bold = [props[@"bold"] boolValue];
        CGFloat size = n ? n.doubleValue : [self ame366_fontOf:v].pointSize;
        if (size <= 0) size = 14;
        UIFont *f = [UIFont systemFontOfSize:size weight:bold ? UIFontWeightSemibold : UIFontWeightRegular];
        [self ame366_setFont:f on:v];
        any = YES;
    }
    if ((n = [self ame364_num:props[@"borderWidth"]])) {
        v.layer.borderWidth = MAX(0, MIN(20, n.doubleValue));
        any = YES;
    }
    NSString *borderColor = [self ame317_string:props[@"borderColor"]];
    if (borderColor) {
        UIColor *c = ame364_colorFromString(borderColor);
        if (c) { v.layer.borderColor = c.CGColor; any = YES; }
    }
    return any;
}

- (nullable NSDictionary *)viewsReadStyle:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return nil;
    UIView *v = [self ame364_viewForHandle:handle];
    if (!v || ame364_isProtectedClass(ame364_clsName(v))) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    UIColor *tc = [self ame366_textColorOf:v];
    NSString *tcHex = [self ame366_hexFromColor:tc];
    if (tcHex) out[@"textColor"] = tcHex;
    UIFont *f = [self ame366_fontOf:v];
    if (f) {
        out[@"fontSize"] = @(f.pointSize);
        out[@"bold"] = @(([[f fontDescriptor] symbolicTraits] & UIFontDescriptorTraitBold) != 0);
    }
    out[@"borderWidth"] = @(v.layer.borderWidth);
    NSString *bcHex = v.layer.borderColor
        ? [self ame366_hexFromColor:[UIColor colorWithCGColor:v.layer.borderColor]] : nil;
    if (bcHex) out[@"borderColor"] = bcHex;
    out[@"alpha"] = @(v.alpha);
    out[@"hidden"] = @(v.hidden);
    return out;
}

- (BOOL)viewsBatch:(NSArray *)ops {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    ops = [self ame317_unwrapJs:ops];
    if (![ops isKindOfClass:[NSArray class]] || ops.count == 0 || ops.count > 64) return NO;
    BOOL all = YES;
    for (id raw in ops) {
        if (![raw isKindOfClass:[NSDictionary class]]) { all = NO; continue; }
        NSDictionary *op = (NSDictionary *)raw;
        id hRaw = op[@"handle"];
        if (![hRaw isKindOfClass:[NSNumber class]]) { all = NO; continue; }
        UIView *v = [self ame364_viewForHandle:((NSNumber *)hRaw).doubleValue];
        if (!v || ame364_isProtectedClass(ame364_clsName(v))) { all = NO; continue; }
        id props = op[@"props"];
        if (![props isKindOfClass:[NSDictionary class]]) { all = NO; continue; }
        if (![self ame366_applyProps:v props:props]) all = NO;
    }
    return all;
}

- (BOOL)viewsRelease:(double)handle {
    if (![self ame317_requirePerm:@"ui.views"]) return NO;
    NSNumber *hk = @((NSUInteger)handle);
    UIView *v = [self.viewTable objectForKey:hk];
    if (!v) return NO;
    // 语义：仅解除句柄寻址（手势与已落改动保留，teardown 兜底摘除）
    [self.viewTable removeObjectForKey:hk];
    return YES;
}

/// apply 核心复用（viewsApply / viewsBatch 双入口；调用方已过权限+stale+禁改检查）
- (BOOL)ame366_applyProps:(UIView *)v props:(NSDictionary *)props {
    if (![props isKindOfClass:[NSDictionary class]] || props.count == 0) return NO;
    NSNumber *hk = @((NSUInteger)[self ame364_registerView:v]);
    if (!self.viewOriginals[hk]) {
        self.viewOriginals[hk] = @{
            @"frame": [NSValue valueWithCGRect:v.frame],
            @"alpha": @(v.alpha),
            @"hidden": @(v.hidden),
        };
    }
    NSNumber *n;
    if ((n = [self ame364_num:props[@"x"]]))  { CGRect f = v.frame; f.origin.x = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"y"]]))  { CGRect f = v.frame; f.origin.y = MAX(-ame364_coordClamp, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"w"]]))  { CGRect f = v.frame; f.size.width = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"h"]]))  { CGRect f = v.frame; f.size.height = MAX(0, MIN(ame364_coordClamp, n.doubleValue)); v.frame = f; }
    if ((n = [self ame364_num:props[@"alpha"]])) { v.alpha = MAX(0.0, MIN(1.0, n.doubleValue)); }
    if (props[@"hidden"] != nil) v.hidden = [props[@"hidden"] boolValue];
    if (props[@"enabled"] != nil && [v isKindOfClass:[UIControl class]]) {
        ((UIControl *)v).enabled = [props[@"enabled"] boolValue];
    }
    if ((n = [self ame364_num:props[@"cornerRadius"]])) {
        v.layer.cornerRadius = MAX(0, MIN(200, n.doubleValue));
        v.layer.masksToBounds = v.layer.cornerRadius > 0 ? YES : v.layer.masksToBounds;
    }
    NSString *text = [self ame317_string:props[@"text"]];
    if (text) {
        if ([v isKindOfClass:[UILabel class]]) ((UILabel *)v).text = text;
        else if ([v isKindOfClass:[UIButton class]]) {
            [((UIButton *)v) setTitle:text forState:UIControlStateNormal];
            [((UIButton *)v) setTitle:text forState:UIControlStateHighlighted];
        }
        else if ([v isKindOfClass:[UITextField class]]) ((UITextField *)v).text = text;
        else if ([v isKindOfClass:[UITextView class]]) ((UITextView *)v).text = text;
    }
    NSString *bg = [self ame317_string:props[@"bg"]];
    if (bg) {
        UIColor *c = ame364_colorFromString(bg);
        if (c) v.backgroundColor = c;
    }
    return YES;
}

/// 文本色读/写（UILabel/UIButton/UITextField/UITextView；其余返回 nil）
- (nullable UIColor *)ame366_textColorOf:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) return ((UILabel *)v).textColor;
    if ([v isKindOfClass:[UIButton class]]) return [((UIButton *)v) titleColorForState:UIControlStateNormal];
    if ([v isKindOfClass:[UITextField class]]) return ((UITextField *)v).textColor;
    if ([v isKindOfClass:[UITextView class]]) return ((UITextView *)v).textColor;
    return nil;
}

- (void)ame366_setTextColor:(UIColor *)c on:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) ((UILabel *)v).textColor = c;
    else if ([v isKindOfClass:[UIButton class]]) [((UIButton *)v) setTitleColor:c forState:UIControlStateNormal];
    else if ([v isKindOfClass:[UITextField class]]) ((UITextField *)v).textColor = c;
    else if ([v isKindOfClass:[UITextView class]]) ((UITextView *)v).textColor = c;
}

- (nullable UIFont *)ame366_fontOf:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) return ((UILabel *)v).font;
    if ([v isKindOfClass:[UIButton class]]) return ((UIButton *)v).titleLabel.font;
    if ([v isKindOfClass:[UITextField class]]) return ((UITextField *)v).font;
    if ([v isKindOfClass:[UITextView class]]) return ((UITextView *)v).font;
    return nil;
}

- (void)ame366_setFont:(UIFont *)f on:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) ((UILabel *)v).font = f;
    else if ([v isKindOfClass:[UIButton class]]) ((UIButton *)v).titleLabel.font = f;
    else if ([v isKindOfClass:[UITextField class]]) ((UITextField *)v).font = f;
    else if ([v isKindOfClass:[UITextView class]]) ((UITextView *)v).font = f;
}

/// UIColor → #RRGGBB(AA)（读样式用；nil 返回 nil）
- (nullable NSString *)ame366_hexFromColor:(UIColor *)c {
    if (!c) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return nil;
    if (a >= 0.999) {
        return [NSString stringWithFormat:@"#%02X%02X%02X",
                (unsigned int)roundf(r * 255), (unsigned int)roundf(g * 255), (unsigned int)roundf(b * 255)];
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (unsigned int)roundf(r * 255), (unsigned int)roundf(g * 255),
            (unsigned int)roundf(b * 255), (unsigned int)roundf(a * 255)];
}

#pragma mark - Task366 弹窗扩展（ui.dialog）

- (void)dialogPrompt:(NSDictionary *)spec callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ui.dialog"]) return;
    spec = [self ame317_unwrapJs:spec] ?: @{};
    NSString *title = [self ame317_string:spec[@"title"]] ?: self.pluginId;
    NSString *body = [self ame317_string:spec[@"body"]] ?: @"";
    NSString *placeholder = [self ame317_string:spec[@"placeholder"]] ?: @"";
    NSString *defaultValue = [self ame317_string:spec[@"value"]] ?: @"";
    NSString *confirm = [self ame317_string:spec[@"confirm"]] ?: localize(@"ame317.common.ok", nil);
    NSString *cancel = [self ame317_string:spec[@"cancel"]] ?: localize(@"ame317.common.cancel", nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:body.length ? body : nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = placeholder;
            textField.text = defaultValue;
        }];
        __weak typeof(self) wself = self;
        __weak UIAlertController *walert = alert;
        [walert addAction:[UIAlertAction actionWithTitle:confirm style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            __strong typeof(wself) sself = wself;
            NSString *text = walert.textFields.firstObject.text ?: @"";
            [sself ame317_callCallback:cb arguments:@[text, @YES]];
        }]];
        [walert addAction:[UIAlertAction actionWithTitle:cancel style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
            __strong typeof(wself) sself = wself;
            [sself ame317_callCallback:cb arguments:@[[NSNull null], @NO]];
        }]];
        [self ame366_presentDialog:alert];
    });
}

- (void)dialogSheet:(NSDictionary *)spec callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ui.dialog"]) return;
    spec = [self ame317_unwrapJs:spec] ?: @{};
    NSString *title = [self ame317_string:spec[@"title"]] ?: self.pluginId;
    NSString *body = [self ame317_string:spec[@"body"]] ?: @"";
    NSArray *items = [self ame317_unwrapJs:spec[@"items"]];
    if (![items isKindOfClass:[NSArray class]] || items.count == 0 || items.count > 12) {
        [self ame317_rejectValue:@"sheet.items 须为 1-12 个字符串"];
        return;
    }
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (id it in items) {
        if (![it isKindOfClass:[NSString class]]) {
            [self ame317_rejectValue:@"sheet.items 元素须为字符串"];
            return;
        }
        [texts addObject:it];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak typeof(self) wself = self;
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                       message:body.length ? body : nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        __weak UIAlertController *wsheet = sheet;
        [texts enumerateObjectsUsingBlock:^(NSString *label, NSUInteger idx, BOOL *_) {
            [wsheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                __strong typeof(wself) sself = wself;
                [sself ame317_callCallback:cb arguments:@[@(idx)]];
            }]];
        }];
        [wsheet addAction:[UIAlertAction actionWithTitle:localize(@"ame317.common.cancel", nil)
                                                  style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
            __strong typeof(wself) sself = wself;
            [sself ame317_callCallback:cb arguments:@[@(-1)]];
        }]];
        [self ame366_presentDialog:sheet];
    });
}

- (BOOL)dialogDismissAll {
    if (![self ame317_requirePerm:@"ui.dialog"]) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIAlertController *vc in [self.presentedDialogs copy]) {
            if (vc && [vc isKindOfClass:[UIAlertController class]]) {
                [vc dismissViewControllerAnimated:NO completion:nil];
            }
        }
        [self.presentedDialogs removeAllObjects];
    });
    return YES;
}

/// 弹窗呈现（含 iPad popover 锚点防呆；登记到 presentedDialogs）
- (void)ame366_presentDialog:(UIAlertController *)alert {
    UIWindow *window = [self ame317_keyWindow];
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (!root) return;
    alert.popoverPresentationController.sourceView = root.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(root.view.bounds.size.width / 2,
                                                                root.view.bounds.size.height / 2, 1, 1);
    alert.popoverPresentationController.permittedArrowDirections = 0;
    [root presentViewController:alert animated:YES completion:nil];
    [self.presentedDialogs addObject:alert];
}

#pragma mark - Task366 通知 / 触感 / 剪贴板 / 分享 / 外链（notify；clipboard.read†）

- (void)notifyWithTitle:(NSString *)title body:(NSString *)body {
    if (![self ame317_requirePerm:@"notify"]) return;
    if (title.length == 0 && body.length == 0) return;
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString stringWithFormat:@"%@ · %@", self.pluginId, title ?: @""];
    content.body = body ?: @"";
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:
        [NSString stringWithFormat:@"ame366-%@-%f", self.pluginId, [NSDate date].timeIntervalSince1970]
        content:content trigger:nil];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError *_) {
        if (!granted) {
            NSLog(@"[AmePlugin:%@] 通知未授权（系统设置），通知丢弃", self.pluginId);
            return;
        }
        [center addNotificationRequest:req withCompletionHandler:nil];
    }];
}

- (BOOL)hapticWithKind:(NSString *)kind {
    if (![self ame317_requirePerm:@"notify"]) return NO;
    if ([kind isEqualToString:@"light"]) {
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight].impactOccurred;
    } else if ([kind isEqualToString:@"medium"]) {
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium].impactOccurred;
    } else if ([kind isEqualToString:@"heavy"]) {
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy].impactOccurred;
    } else if ([kind isEqualToString:@"success"] || [kind isEqualToString:@"warning"] || [kind isEqualToString:@"error"]) {
        UINotificationFeedbackType t = [kind isEqualToString:@"success"] ? UINotificationFeedbackTypeSuccess
            : [kind isEqualToString:@"warning"] ? UINotificationFeedbackTypeWarning : UINotificationFeedbackTypeError;
        UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
        [gen notificationOccurred:t];
    } else {
        return NO;
    }
    return YES;
}

- (BOOL)clipboardSetText:(NSString *)text {
    if (![self ame317_requirePerm:@"notify"]) return NO;
    if (text.length == 0) return NO;
    [UIPasteboard generalPasteboard].string = text;
    return YES;
}

- (nullable NSString *)clipboardGetText {
    if (![self ame317_requirePerm:@"clipboard.read"]) return nil;
    return [UIPasteboard generalPasteboard].string;
}

- (void)shareText:(NSString *)text title:(NSString *)title {
    if (![self ame317_requirePerm:@"notify"]) return;
    if (text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *vc = [[UIActivityViewController alloc]
            initWithActivityItems:@[text] applicationActivities:nil];
        [self ame366_presentDialogLike:vc];
    });
}

- (BOOL)openExternalURL:(NSString *)urlString {
    if (![self ame317_requirePerm:@"notify"]) return NO;
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url || (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString])) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
    return YES;
}

/// 非弹窗 VC 呈现（分享面板；iPad popover 防呆复用）
- (void)ame366_presentDialogLike:(UIViewController *)vc {
    UIWindow *window = [self ame317_keyWindow];
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (!root) return;
    vc.popoverPresentationController.sourceView = root.view;
    vc.popoverPresentationController.sourceRect = CGRectMake(root.view.bounds.size.width / 2,
                                                             root.view.bounds.size.height / 2, 1, 1);
    vc.popoverPresentationController.permittedArrowDirections = 0;
    [root presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Task366 主题读取（ui.theme†）

- (nullable NSDictionary *)getThemeTokens {
    if (![self ame317_requirePerm:@"ui.theme"]) return nil;
    return [AmePluginRuntime ame366_themeOverrides:@"tokens" forPlugin:self.pluginId];
}

- (nullable NSDictionary *)getThemeShapes {
    if (![self ame317_requirePerm:@"ui.theme"]) return nil;
    return [AmePluginRuntime ame366_themeOverrides:@"shapes" forPlugin:self.pluginId];
}

- (nullable NSDictionary *)getThemeLayouts {
    if (![self ame317_requirePerm:@"ui.theme"]) return nil;
    return [AmePluginRuntime ame366_themeOverrides:@"layouts" forPlugin:self.pluginId];
}

- (nullable NSDictionary *)getThemeStructures {
    if (![self ame317_requirePerm:@"ui.theme"]) return nil;
    return [AmePluginRuntime ame366_themeOverrides:@"structures" forPlugin:self.pluginId];
}

#pragma mark - Task366 设置扩展（settings.read / settings.write†）

- (nullable NSArray *)listPrefKeys:(NSString *)prefix {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    NSArray *all = ame366_registeredPrefKeys() ?: @[];
    if (prefix.length == 0) return all;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in all) {
        if ([k hasPrefix:prefix]) [out addObject:k];
    }
    return out;
}

- (nullable NSDictionary *)getPrefs:(NSArray *)keys {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    keys = [self ame317_unwrapJs:keys];
    if (![keys isKindOfClass:[NSArray class]] || keys.count == 0 || keys.count > 128) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id raw in keys) {
        if (![raw isKindOfClass:[NSString class]]) continue;
        if (![self ame317_validPrefKey:raw]) continue;
        id v = getPrefObject(raw);
        out[raw] = v ?: [NSNull null];
    }
    return out;
}

- (BOOL)setPrefs:(NSDictionary *)dict {
    if (![self ame317_requirePerm:@"settings.write"]) return NO;
    dict = [self ame317_unwrapJs:dict];
    if (![dict isKindOfClass:[NSDictionary class]] || dict.count == 0 || dict.count > 128) return NO;
    BOOL all = YES;
    for (NSString *k in dict) {
        if (![self ame317_validPrefKey:k] || [k hasPrefix:@"plugin."]) { all = NO; continue; }
        if (![self ame366_setPrefValue:dict[k] forKey:k]) all = NO;
    }
    return all;
}

/// setPref 值类型分派核心（setPref/setPrefs 复用；调用方已过权限与键校验）
- (BOOL)ame366_setPrefValue:(id)value forKey:(NSString *)key {
    if (value == nil || value == [NSNull null]) return NO;
    if ([value isKindOfClass:[NSString class]]) {
        setPrefString(key, value);
        return YES;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *n = (NSNumber *)value;
        if (strcmp([n objCType], @encode(BOOL)) == 0 || strcmp([n objCType], @encode(char)) == 0) {
            setPrefBool(key, n.boolValue);
        } else if (strcmp([n objCType], @encode(float)) == 0 || strcmp([n objCType], @encode(double)) == 0) {
            setPrefFloat(key, (float)n.doubleValue);
        } else {
            setPrefInt(key, n.integerValue);
        }
        return YES;
    }
    return NO;
}

- (BOOL)removePref:(NSString *)key {
    if (![self ame317_requirePerm:@"settings.write"]) return NO;
    if (![self ame317_validPrefKey:key] || [key hasPrefix:@"plugin."]) return NO;
    // setValue:nil forKeyPath 语义 = 从注册字典移除键并落盘（未注册键恒 NO）
    if (!ame366_registeredPrefKeys() || ![ame366_registeredPrefKeys() containsObject:key]) return NO;
    setPrefObject(key, nil);
    return YES;
}

- (nullable NSDictionary *)prefDescribe:(NSString *)key {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    if (![self ame317_validPrefKey:key]) return nil;
    id v = getPrefObject(key);
    BOOL registered = [ame366_registeredPrefKeys() containsObject:key];
    NSString *type = @"null";
    if ([v isKindOfClass:[NSString class]]) type = @"string";
    else if ([v isKindOfClass:[NSNumber class]]) {
        NSNumber *n = (NSNumber *)v;
        if (strcmp([n objCType], @encode(BOOL)) == 0) type = @"bool";
        else if (strcmp([n objCType], @encode(float)) == 0 || strcmp([n objCType], @encode(double)) == 0) type = @"float";
        else type = @"int";
    }
    return @{@"value": v ?: [NSNull null], @"type": type, @"registered": @(registered)};
}

#pragma mark - Task366 实例档案扩展（profile.read / profile.write†）

- (nullable NSDictionary *)getCurrentProfile {
    if (![self ame317_requirePerm:@"profile.read"]) return nil;
    NSString *name = [PLProfiles current].selectedProfileName ?: @"";
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"name"] = name;
    NSDictionary *entry = [PLProfiles current].profiles[name];
    if ([entry isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in entry) [out setObject:entry[k] forKey:k];
    }
    return out;
}

- (BOOL)setCurrentProfile:(NSString *)name {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    if (![self ame327_validProfileName:name]) {
        [self ame317_rejectValue:name ?: @""];
        return NO;
    }
    if ([PLProfiles current].profiles[name] == nil) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", name]];
        return NO;
    }
    [[PLProfiles current] setSelectedProfileName:name];
    return YES;
}

- (nullable NSDictionary *)describeProfile:(NSString *)name {
    if (![self ame317_requirePerm:@"profile.read"]) return nil;
    if (![self ame327_validProfileName:name]) return nil;
    NSDictionary *entry = [PLProfiles current].profiles[name];
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:entry];
    out[@"name"] = name;
    out[@"selected"] = @([name isEqualToString:[PLProfiles current].selectedProfileName ?: @""]);
    return out;
}

- (BOOL)renameProfile:(NSString *)oldName to:(NSString *)newName {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    if (![self ame327_validProfileName:oldName] || ![self ame327_validProfileName:newName]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"rename %@ -> %@", oldName ?: @"", newName ?: @""]];
        return NO;
    }
    if ([oldName isEqualToString:@"(Default)"]) {
        [self ame317_rejectValue:@"(Default) 拒绝重命名"];
        return NO;
    }
    if ([PLProfiles current].profiles[oldName] == nil) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", oldName]];
        return NO;
    }
    if ([PLProfiles current].profiles[newName] != nil) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile exists: %@", newName]];
        return NO;
    }
    BOOL wasSelected = [oldName isEqualToString:[PLProfiles current].selectedProfileName ?: @""];
    [[PLProfiles current] applyChanges:^(NSMutableDictionary<NSString *, id> *all) {
        all[newName] = all[oldName];
        [all removeObjectForKey:oldName];
    }];
    if (wasSelected) [[PLProfiles current] setSelectedProfileName:newName];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    return YES;
}

- (nullable id)getProfileKey:(NSString *)key profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"profile.read"]) return nil;
    if (![self ame317_validPrefKey:key]) return nil;
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) return nil;
    NSDictionary *entry = [PLProfiles current].profiles[name];
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    return entry[key];
}

- (BOOL)setProfileKey:(NSString *)key value:(id)value profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    if (![self ame317_validPrefKey:key]) return NO;
    value = [self ame317_unwrapJs:value];
    // 值域与 setPref 同口径：字符串/数值/布尔（防脏类型污染 profiles.json）
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return NO;
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", profileName ?: @""]];
        return NO;
    }
    [[PLProfiles current] applyChanges:^(NSMutableDictionary<NSString *, id> *all) {
        NSMutableDictionary *entry = all[name];
        if (![entry isKindOfClass:[NSMutableDictionary class]]) {
            entry = [NSMutableDictionary dictionary];
            all[name] = entry;
        }
        entry[key] = value;
    }];
    return YES;
}

- (nullable NSString *)getServerIpForProfile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"profile.read"]) return nil;
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) return nil;
    return [[PLProfiles current] serverIpForProfile:name];
}

- (BOOL)setServerIpForProfile:(NSString *)ip profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"profile.write"]) return NO;
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"profile missing: %@", profileName ?: @""]];
        return NO;
    }
    [[PLProfiles current] setServerIp:ip ?: @"" forProfile:name];
    return YES;
}

/// 实例名解析：空 = 当前选中；不存在 = nil
- (nullable NSString *)ame366_resolveProfileName:(NSString *)profileName {
    if (profileName.length == 0) return [PLProfiles current].selectedProfileName;
    if ([PLProfiles current].profiles[profileName] != nil) return profileName;
    return nil;
}

#pragma mark - Task366 游戏状态（game.read 安全）

- (nullable NSDictionary *)getGameState {
    if (![self ame317_requirePerm:@"game.read"]) return nil;
    UIWindow *window = [self ame317_keyWindow];
    UIViewController *root = window.rootViewController;
    BOOL running = [NSStringFromClass(root.class) isEqualToString:@"SurfaceViewController"];
    return @{
        @"running": @(running),
        @"profile": [PLProfiles current].selectedProfileName ?: @"",
        @"jit": @(isJITEnabled(NO)),
    };
}

- (nullable NSDictionary *)getLastGameExit {
    if (![self ame317_requirePerm:@"game.read"]) return nil;
    return [AmePluginRuntime ame366_lastGameExit];
}

- (nullable NSDictionary *)getMemoryAllocation {
    if (![self ame317_requirePerm:@"game.read"]) return nil;
    id v = getPrefObject(@"general.ram_allocation");
    return @{@"mb": [v isKindOfClass:[NSNumber class]] ? v : @(0),
             @"note": @"0 = 跟随默认；其余为堆上限 MB（128-8192）"};
}

- (BOOL)setMemoryAllocation:(double)mb {
    if (![self ame317_requirePerm:@"settings.write"]) return NO;
    if (mb != 0 && !(mb >= 128 && mb <= 8192)) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"ram %g 越界（0 或 128-8192）", mb]];
        return NO;
    }
    setPrefInt(@"general.ram_allocation", (NSInteger)mb);
    return YES;
}

- (nullable NSString *)getControlLayout {
    if (![self ame317_requirePerm:@"game.read"]) return nil;
    id v = getPrefObject(@"control.default_ctrl");
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (BOOL)setControlLayout:(NSString *)name {
    if (![self ame317_requirePerm:@"settings.write"]) return NO;
    if (name.length == 0 || [name rangeOfString:@"/"].location != NSNotFound ||
        [name rangeOfString:@".."].location != NSNotFound) return NO;
    const char *home = getenv("POJAV_HOME");
    if (!home || !*home) return NO;
    NSString *layout = [[NSString stringWithUTF8String:home]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"controlmap/%@.json", name]];
    if (![NSFileManager.defaultManager fileExistsAtPath:layout]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"布局不存在: %@", name]];
        return NO;
    }
    setPrefString(@"control.default_ctrl", name);
    return YES;
}

#pragma mark - Task366 JIT 扩展（jit.read / jit.write†）

- (BOOL)setJITScheme:(NSString *)scheme {
    if (![self ame317_requirePerm:@"jit.write"]) return NO;
    NSArray *schemes = @[@"auto", @"builtin", @"stikjit", @"sidestore", @"stosdebug", @"jitstreamer"];
    if (![schemes containsObject:scheme ?: @""]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"未知 JIT 方案: %@", scheme ?: @""]];
        return NO;
    }
    setPrefString(@"debug.jit_enabler", scheme);
    return YES;
}

- (nullable NSArray *)getJITSchemes {
    if (![self ame317_requirePerm:@"jit.read"]) return nil;
    return @[
        @{@"id": @"auto",       @"note": @"自动选择（推荐）"},
        @{@"id": @"builtin",    @"note": @"内置轨（iOS 17.4+ 配对文件）"},
        @{@"id": @"stikjit",    @"note": @"StikJIT app"},
        @{@"id": @"sidestore",  @"note": @"SideStore JIT"},
        @{@"id": @"stosdebug",  @"note": @"StOS Debug"},
        @{@"id": @"jitstreamer", @"note": @"JITStreamer"},
    ];
}

#pragma mark - Task366 日志扩展（logs.read）

- (nullable NSArray *)listLogFiles:(NSString *)which {
    if (![self ame317_requirePerm:@"logs.read"]) return nil;
    NSString *key = which.length ? which : @"launcher";
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    NSString *dir = nil;
    NSArray *suffixFilter = nil;
    if ([key isEqualToString:@"launcher"] || [key isEqualToString:@"launcherOld"]) {
        dir = home;
        suffixFilter = @[@"latestlog.txt", @"latestlog.old.txt"];
    } else if ([key isEqualToString:@"game"]) {
        const char *gd = getenv("POJAV_GAME_DIR");
        dir = (gd && *gd) ? [[NSString stringWithUTF8String:gd] stringByAppendingPathComponent:@"logs"] : nil;
        suffixFilter = @[@".log", @".gz"];
    } else if ([key isEqualToString:@"crash"]) {
        dir = [self ame365_latestCrashReportPath].stringByDeletingLastPathComponent;
        suffixFilter = @[@".txt"];
    } else {
        [self ame317_rejectValue:[NSString stringWithFormat:@"unknown log: %@", key]];
        return nil;
    }
    if (!dir.length) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
        BOOL match = NO;
        for (NSString *suf in suffixFilter ?: @[]) {
            if ([name hasSuffix:suf] || [name isEqualToString:suf]) { match = YES; break; }
        }
        if (!match) continue;
        NSString *p = [dir stringByAppendingPathComponent:name];
        NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
        [out addObject:@{@"name": name,
                         @"size": @(at ? (double)[at fileSize] : 0),
                         @"mtime": at[NSFileModificationDate] ?: [NSNull null]}];
    }
    return out;
}

- (nullable NSArray *)searchLog:(NSString *)which pattern:(NSString *)pattern limit:(double)limit {
    if (![self ame317_requirePerm:@"logs.read"]) return nil;
    NSString *text = [self ame366_logTextFor:which];
    if (!text) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern ?: @""
                                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    if (!re) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"非法正则: %@", pattern ?: @""]];
        return nil;
    }
    NSUInteger cap = limit >= 1 ? (NSUInteger)MIN(limit, 200) : 50;
    NSMutableArray *out = [NSMutableArray array];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count && out.count < cap; i++) {
        NSString *line = lines[i];
        if ([re firstMatchInString:line options:0 range:NSMakeRange(0, line.length)]) {
            [out addObject:@{@"line": @(i + 1), @"text": line.length > 2000 ? [line substringToIndex:2000] : line}];
        }
    }
    return out;
}

/// 日志全文读取（readLog/searchLog 共用；4MB 尾读封顶 + 单行 2000 字截断）
- (nullable NSString *)ame366_logTextFor:(NSString *)which {
    NSString *key = which.length ? which : @"launcher";
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    NSString *path = nil;
    if ([key isEqualToString:@"launcher"]) {
        path = home.length ? [home stringByAppendingPathComponent:@"latestlog.txt"] : nil;
    } else if ([key isEqualToString:@"launcherOld"]) {
        path = home.length ? [home stringByAppendingPathComponent:@"latestlog.old.txt"] : nil;
    } else if ([key isEqualToString:@"game"]) {
        const char *gd = getenv("POJAV_GAME_DIR");
        path = (gd && *gd) ? [[NSString stringWithUTF8String:gd] stringByAppendingPathComponent:@"logs/latest.log"] : nil;
    } else if ([key isEqualToString:@"crash"]) {
        path = [self ame365_latestCrashReportPath];
    } else {
        return nil;
    }
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0) return nil;
    if (data.length > 4 * 1024 * 1024) {
        data = [data subdataWithRange:NSMakeRange(data.length - 4 * 1024 * 1024, 4 * 1024 * 1024)];
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Task366 模组 / 光影（mods.read / mods.write†）

/// 有效 mods 目录（实例隔离感知；profile 空 = 当前选中）
- (nullable NSString *)ame366_modsFolderForProfile:(NSString *)profileName {
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) return nil;
    NSString *folder = [[ModService sharedService] ame264_effectiveModsFolderForProfile:name];
    if (!folder) folder = [[ModService sharedService] ensureModsFolderForProfile:name error:nil];
    return folder;
}

/// 有效 shaderpacks 目录
- (nullable NSString *)ame366_shadersFolderForProfile:(NSString *)profileName {
    NSString *name = [self ame366_resolveProfileName:profileName];
    if (!name) return nil;
    return [[ShaderService sharedService] ensureShadersFolderForProfile:name error:nil];
}

/// 文件名防穿越（模组/光影/触控布局共用：纯文件名，禁分隔符与 ..）
- (BOOL)ame366_isPlainFileName:(NSString *)name {
    if (name.length == 0 || name.length > 255) return NO;
    if ([name containsString:@"/"] || [name containsString:@"\\"]) return NO;
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) return NO;
    return YES;
}

- (nullable NSArray *)listModsWithProfile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.read"]) return nil;
    return [self ame366_listFilesInFolder:[self ame366_modsFolderForProfile:profileName]];
}

- (nullable NSArray *)listShadersWithProfile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.read"]) return nil;
    return [self ame366_listFilesInFolder:[self ame366_shadersFolderForProfile:profileName]];
}

/// 目录文件清单（mods/shaders 通用；.disabled 尾缀 → disabled 标记）
- (nullable NSArray *)ame366_listFilesInFolder:(NSString *)folder {
    if (!folder) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:folder error:nil] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [folder stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:p isDirectory:&isDir] || isDir) continue;
        NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
        BOOL disabled = [name.lowercaseString hasSuffix:@".disabled"];
        [out addObject:@{@"fileName": name,
                         @"disabled": @(disabled),
                         @"size": @(at ? (double)[at fileSize] : 0),
                         @"mtime": at[NSFileModificationDate] ?: [NSNull null]}];
    }
    return out;
}

/// 模组/光影启停（语义与管理页同链：.disabled 重命名制；分服务判型消费各自 selector）
- (BOOL)ame366_toggleInFolder:(NSString *)folder fileName:(NSString *)fileName kind:(NSString *)kind {
    if (!folder || ![self ame366_isPlainFileName:fileName]) return NO;
    NSString *path = [folder stringByAppendingPathComponent:fileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"%@ 不存在: %@", kind, fileName]];
        return NO;
    }
    BOOL disabled = [fileName.lowercaseString hasSuffix:@".disabled"];
    BOOL ok = NO;
    NSError *err = nil;
    if ([kind isEqualToString:@"mod"]) {
        ModItem *item = [[ModItem alloc] initWithFilePath:path];
        item.disabled = disabled;
        ok = [[ModService sharedService] toggleEnableForMod:item error:&err];
    } else {
        ShaderItem *item = [[ShaderItem alloc] initWithFilePath:path];
        item.disabled = disabled;
        ok = [[ShaderService sharedService] toggleEnableForShader:item error:&err];
    }
    if (!ok && err) [self ame317_rejectValue:err.localizedDescription ?: @"toggle 失败"];
    return ok;
}

/// 模组/光影删除（启停同链语义；目录文件皆可删）
- (BOOL)ame366_removeInFolder:(NSString *)folder fileName:(NSString *)fileName kind:(NSString *)kind {
    if (!folder || ![self ame366_isPlainFileName:fileName]) return NO;
    NSString *path = [folder stringByAppendingPathComponent:fileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"%@ 不存在: %@", kind, fileName]];
        return NO;
    }
    return [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

- (BOOL)toggleMod:(NSString *)fileName profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.write"]) return NO;
    return [self ame366_toggleInFolder:[self ame366_modsFolderForProfile:profileName]
                              fileName:fileName kind:@"mod"];
}

- (BOOL)removeMod:(NSString *)fileName profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.write"]) return NO;
    return [self ame366_removeInFolder:[self ame366_modsFolderForProfile:profileName]
                              fileName:fileName kind:@"mod"];
}

- (nullable NSString *)getModsFolderForProfile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.read"]) return nil;
    return [self ame366_modsFolderForProfile:profileName];
}

- (BOOL)toggleShader:(NSString *)fileName profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.write"]) return NO;
    return [self ame366_toggleInFolder:[self ame366_shadersFolderForProfile:profileName]
                              fileName:fileName kind:@"shader"];
}

- (BOOL)removeShader:(NSString *)fileName profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"mods.write"]) return NO;
    return [self ame366_removeInFolder:[self ame366_shadersFolderForProfile:profileName]
                              fileName:fileName kind:@"shader"];
}

#pragma mark - Task366 存档（worlds.read / worlds.write†）

- (nullable NSArray *)listWorldsForProfile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"worlds.read"]) return nil;
    NSString *saves = [[self ame366_gameDirForProfile:profileName] stringByAppendingPathComponent:@"saves"];
    if (!saves.length) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:saves error:nil] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [saves stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:p isDirectory:&isDir] || !isDir) continue;
        NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
        [out addObject:@{@"name": name,
                         @"mtime": at[NSFileModificationDate] ?: [NSNull null],
                         @"sizeBytes": @([self ame366_recursiveSize:p entries:nil])}];
    }
    return out;
}

- (nullable NSDictionary *)describeWorld:(NSString *)name profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"worlds.read"]) return nil;
    if (![self ame366_isPlainFileName:name]) return nil;
    NSString *p = [[[self ame366_gameDirForProfile:profileName] stringByAppendingPathComponent:@"saves"]
                   stringByAppendingPathComponent:name];
    BOOL isDir = NO;
    if (!p.length || ![NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&isDir] || !isDir) return nil;
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    return @{@"name": name,
             @"hasLevelDat": @([NSFileManager.defaultManager fileExistsAtPath:[p stringByAppendingPathComponent:@"level.dat"]]),
             @"hasIcon": @([NSFileManager.defaultManager fileExistsAtPath:[p stringByAppendingPathComponent:@"icon.png"]]),
             @"sizeBytes": @([self ame366_recursiveSize:p entries:nil]),
             @"mtime": at[NSFileModificationDate] ?: [NSNull null]};
}

- (BOOL)renameWorld:(NSString *)oldName to:(NSString *)newName profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"worlds.write"]) return NO;
    if (![self ame366_isPlainFileName:oldName] || ![self ame366_isPlainFileName:newName]) return NO;
    NSString *saves = [[self ame366_gameDirForProfile:profileName] stringByAppendingPathComponent:@"saves"];
    NSString *from = [saves stringByAppendingPathComponent:oldName];
    NSString *to = [saves stringByAppendingPathComponent:newName];
    if (![NSFileManager.defaultManager fileExistsAtPath:from]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"存档不存在: %@", oldName]];
        return NO;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:to]) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"目标同名存档已存在: %@", newName]];
        return NO;
    }
    BOOL ok = [NSFileManager.defaultManager moveItemAtPath:from toPath:to error:nil];
    if (ok) [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadWorldList" object:nil];
    return ok;
}

- (BOOL)removeWorld:(NSString *)name profile:(NSString *)profileName {
    if (![self ame317_requirePerm:@"worlds.write"]) return NO;
    if (![self ame366_isPlainFileName:name]) return NO;
    NSString *p = [[[self ame366_gameDirForProfile:profileName] stringByAppendingPathComponent:@"saves"]
                   stringByAppendingPathComponent:name];
    BOOL isDir = NO;
    if (!p.length || ![NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&isDir] || !isDir) {
        [self ame317_rejectValue:[NSString stringWithFormat:@"存档不存在: %@", name]];
        return NO;
    }
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:p error:nil];
    if (ok) [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadWorldList" object:nil];
    return ok;
}

/// 实例游戏目录解析（空/选中 = POJAV_GAME_DIR；指定实例 = profiles 键）
- (nullable NSString *)ame366_gameDirForProfile:(NSString *)profileName {
    NSString *selected = [PLProfiles current].selectedProfileName;
    if (profileName.length == 0 || [profileName isEqualToString:selected]) {
        const char *gd = getenv("POJAV_GAME_DIR");
        if (gd && *gd) return [NSString stringWithUTF8String:gd];
    }
    NSDictionary *p = [PLProfiles current].profiles[profileName ?: @""];
    if ([p isKindOfClass:[NSDictionary class]]) {
        id dir = p[@"gameDir"];
        if ([dir isKindOfClass:[NSString class]] && ((NSString *)dir).length > 0) return dir;
    }
    const char *gd2 = getenv("POJAV_GAME_DIR");
    return (gd2 && *gd2) ? [NSString stringWithUTF8String:gd2] : nil;
}

/// 递归尺寸（文件 = 自身；目录 = 深度优先；entries 出参可空，容量防呆 20 万项）
- (double)ame366_recursiveSize:(NSString *)path entries:(NSUInteger *)entries {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    if (!isDir) return (double)[fm attributesOfItemAtPath:path error:nil].fileSize;
    if (entries) { (*entries)++; if (*entries > 200000) return 0; }
    double total = 0;
    for (NSString *child in [fm contentsOfDirectoryAtPath:path error:nil] ?: @[]) {
        total += [self ame366_recursiveSize:[path stringByAppendingPathComponent:child] entries:entries];
    }
    return total;
}

#pragma mark - Task366 账户（accounts.read；凭据字段永不入 JS）

- (nullable NSArray *)getAccountList {
    if (![self ame317_requirePerm:@"accounts.read"]) return nil;
    return [self ame366_scanAccounts];
}

- (nullable NSDictionary *)getCurrentAccount {
    if (![self ame317_requirePerm:@"accounts.read"]) return nil;
    NSString *sel = nil;
    id v = getPrefObject(@"internal.selected_account");
    if ([v isKindOfClass:[NSString class]]) sel = v;
    if (!sel.length) return nil;
    for (NSDictionary *acc in [self ame366_scanAccounts] ?: @[]) {
        if ([acc[@"accountId"] isKindOfClass:[NSString class]] &&
            [acc[@"accountId"] isEqualToString:sel]) {
            return acc;
        }
    }
    return nil;
}

/// 账户元数据扫描（$POJAV_HOME/accounts/*.json；白名单三键，凭据零透出）
- (nullable NSArray *)ame366_scanAccounts {
    const char *home = getenv("POJAV_HOME");
    if (!home || !*home) return nil;
    NSString *dir = [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"accounts"];
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
    if (!files) return nil;
    id sel = getPrefObject(@"internal.selected_account");
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file hasSuffix:@".json"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
        if (!data) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        NSString *accountId = [json[@"accountId"] isKindOfClass:[NSString class]] ? json[@"accountId"] : @"";
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"accountId"] = accountId;
        if ([json[@"username"] isKindOfClass:[NSString class]]) item[@"username"] = json[@"username"];
        item[@"type"] = [json[@"accountType"] isKindOfClass:[NSString class]] ? json[@"accountType"] : @"unknown";
        item[@"selected"] = @([accountId isKindOfClass:[NSString class]] && [accountId isEqualToString:sel]);
        [out addObject:item];
    }
    return out;
}

#pragma mark - Task366 下载历史（downloads.read）

- (nullable NSArray *)getDownloadHistory {
    if (![self ame317_requirePerm:@"downloads.read"]) return nil;
    NSArray *entries = [[DownloadHistoryStore sharedStore] allEntries] ?: @[];
    NSUInteger start = entries.count > 100 ? entries.count - 100 : 0;
    return [entries subarrayWithRange:NSMakeRange(start, entries.count - start)];
}

#pragma mark - Task366 AI（ai.call†）

- (void)aiAsk:(NSString *)prompt callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"ai.call"]) return;
    if (!cb.isObject) return;
    if (prompt.length == 0 || prompt.length > 4000) {
        [self ame317_rejectValue:@"ai.ask prompt 须为 1-4000 字"];
        return;
    }
    AiProvider *provider = [AiProviderStore sharedStore].selectedProvider;
    if (!provider) {
        [self ame317_callCallback:cb arguments:@[@{@"ok": @NO,
            @"error": @"未配置 AI 供应商：请到 AI 页 → 供应商设置 配置后重试"}]];
        return;
    }
    AiAPIClient *client = [[AiAPIClient alloc] init];
    AiMessage *sys = [AiMessage messageWithRole:@"system"
        content:@"你是 Prisma 启动器插件的内置 AI 助手。回答精炼、直接可执行，排查类问题优先给出步骤。"];
    AiMessage *user = [AiMessage messageWithRole:@"user" content:prompt];
    __weak typeof(self) wself = self;
    [client streamChatWithProvider:provider messages:@[sys, user] tools:nil onChunk:nil
        onComplete:^(NSDictionary *fullResponse, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            if (error) {
                [sself ame317_callCallback:cb arguments:@[@{@"ok": @NO,
                    @"error": error.localizedDescription ?: @"AI 请求失败"}]];
                return;
            }
            NSString *text = @"";
            if ([fullResponse isKindOfClass:[NSDictionary class]] &&
                [fullResponse[@"content"] isKindOfClass:[NSString class]]) {
                text = fullResponse[@"content"];
            }
            [sself ame317_callCallback:cb arguments:@[@{@"ok": @YES, @"reply": text ?: @""}]];
        });
    }];
}

- (nullable NSDictionary *)getAIStatus {
    if (![self ame317_requirePerm:@"settings.read"]) return nil;
    AiProvider *provider = [AiProviderStore sharedStore].selectedProvider;
    return @{@"configured": @(provider != nil),
             @"name": provider.name ?: @"",
             @"model": provider.model ?: @"",
             @"selectedId": [AiSettings sharedSettings].selectedProviderId ?: @""};
}

#pragma mark - Task366 触控布局（controls.read / controls.write†）

- (nullable NSArray *)listControlLayouts {
    if (![self ame317_requirePerm:@"controls.read"]) return nil;
    const char *home = getenv("POJAV_HOME");
    if (!home || !*home) return nil;
    NSString *dir = [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"controlmap"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
        if (![name hasSuffix:@".json"]) continue;
        NSDictionary *at = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
        [out addObject:@{@"name": [name stringByDeletingPathExtension],
                         @"size": @(at ? (double)[at fileSize] : 0)}];
    }
    return out;
}

- (nullable NSString *)readControlLayout:(NSString *)name {
    if (![self ame317_requirePerm:@"controls.read"]) return nil;
    NSString *p = [self ame366_controlLayoutPath:name];
    if (!p) return nil;
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    if ([at fileSize] > ame327_fileReadMax) return nil;
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)writeControlLayout:(NSString *)name content:(NSString *)content {
    if (![self ame317_requirePerm:@"controls.write"]) return NO;
    NSString *p = [self ame366_controlLayoutPath:name];
    if (!p || content.length > ame327_fileWriteMax) return NO;
    return [[content dataUsingEncoding:NSUTF8StringEncoding] writeToFile:p atomically:YES];
}

- (BOOL)removeControlLayout:(NSString *)name {
    if (![self ame317_requirePerm:@"controls.write"]) return NO;
    NSString *p = [self ame366_controlLayoutPath:name];
    if (!p) return NO;
    return [NSFileManager.defaultManager removeItemAtPath:p error:nil];
}

- (nullable NSString *)ame366_controlLayoutPath:(NSString *)name {
    if (![self ame366_isPlainFileName:name]) return nil;
    if (![name.lowercaseString hasSuffix:@".json"]) name = [name stringByAppendingString:@".json"];
    const char *home = getenv("POJAV_HOME");
    if (!home || !*home) return nil;
    return [[NSString stringWithUTF8String:home]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"controlmap/%@", name]];
}

#pragma mark - Task366 启动器沙盒文件面（fs.launcher†；POJAV_HOME 内相对路径）

/// POJAV_HOME 沙盒路径守卫（与 ame327_gamePathFor 同规：禁 ..//绝对路径/symlink 逃逸）
- (nullable NSString *)ame366_homePathFor:(NSString *)relPath {
    const char *home = getenv("POJAV_HOME");
    if (!home || !*home) return nil;
    NSString *base = [NSString stringWithUTF8String:home];
    if (relPath.length == 0 || relPath.length > 512) return nil;
    if ([relPath isEqualToString:@"."]) return base;
    if ([relPath hasPrefix:@"/"]) return nil;
    for (NSString *seg in [relPath pathComponents]) {
        if ([seg isEqualToString:@".."] || seg.length == 0) return nil;
    }
    NSString *full = [base stringByAppendingPathComponent:relPath];
    NSString *resolved = [full stringByResolvingSymlinksInPath];
    NSString *resolvedBase = [base stringByResolvingSymlinksInPath];
    if (![resolved hasPrefix:resolvedBase]) return nil;
    return full;
}

- (nullable NSArray *)fsList:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return nil;
    NSString *dir = [self ame366_homePathFor:relPath ?: @"."];
    if (!dir) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL d = NO;
        [fm fileExistsAtPath:p isDirectory:&d];
        NSUInteger sz = d ? 0 : (NSUInteger)[fm attributesOfItemAtPath:p error:nil].fileSize;
        [out addObject:@{@"name": name, @"isDir": @(d), @"size": @(sz)}];
    }
    return out;
}

- (nullable NSString *)fsRead:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return nil;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    if (!p) return nil;
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    if ([at fileSize] > ame327_fileReadMax) return nil;
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)fsWrite:(NSString *)relPath content:(NSString *)content append:(BOOL)append {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    if (!p || content.length > ame327_fileWriteMax) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = p.stringByDeletingLastPathComponent;
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    if (append && [fm fileExistsAtPath:p]) {
        NSMutableData *mut = [NSMutableData dataWithContentsOfFile:p] ?: [NSMutableData data];
        [mut appendData:data];
        if (mut.length > ame327_fileWriteMax) return NO;
        return [mut writeToFile:p atomically:YES];
    }
    return [data writeToFile:p atomically:YES];
}

- (BOOL)fsRemove:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    if (!p) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:p isDirectory:&isDir]) return NO;
    if (isDir) {
        NSArray *children = [fm contentsOfDirectoryAtPath:p error:nil];
        if (children.count > 0) return NO;   // 仅空目录可删（防一键清空）
    }
    return [fm removeItemAtPath:p error:nil];
}

- (BOOL)fsExists:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    return p && [NSFileManager.defaultManager fileExistsAtPath:p];
}

- (BOOL)fsMkdir:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    if (!p) return NO;
    return [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
}

- (BOOL)fsMove:(NSString *)fromPath to:(NSString *)toPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *from = [self ame366_homePathFor:fromPath ?: @""];
    NSString *to = [self ame366_homePathFor:toPath ?: @""];
    if (!from || !to) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:to]) return NO;
    return [NSFileManager.defaultManager moveItemAtPath:from toPath:to error:nil];
}

- (BOOL)fsCopy:(NSString *)fromPath to:(NSString *)toPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return NO;
    NSString *from = [self ame366_homePathFor:fromPath ?: @""];
    NSString *to = [self ame366_homePathFor:toPath ?: @""];
    if (!from || !to) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:to]) return NO;
    return [NSFileManager.defaultManager copyItemAtPath:from toPath:to error:nil];
}

- (nullable NSNumber *)fsSize:(NSString *)relPath {
    if (![self ame317_requirePerm:@"fs.launcher"]) return nil;
    NSString *p = [self ame366_homePathFor:relPath ?: @""];
    if (!p) return nil;
    NSUInteger entries = 0;
    double size = [self ame366_recursiveSize:p entries:&entries];
    if (entries > 200000) return nil;
    return @(size);
}

#pragma mark - Task366 下载到文件（net† + fs.launcher† 双闸）

- (void)downloadWithURL:(NSString *)urlString to:(NSString *)relPath callback:(JSValue *)cb {
    if (![self ame317_requirePerm:@"net"]) return;
    if (![self ame317_requirePerm:@"fs.launcher"]) return;
    if (!cb.isObject) return;
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *dest = [self ame366_homePathFor:relPath ?: @""];
    if (!url.scheme || !url.host || !dest) {
        [self ame317_callCallback:cb arguments:@[@{@"ok": @NO, @"error": @"URL 非法或目标路径非法（须为启动器沙盒内相对路径）"}]];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            if (err || !location) {
                [sself ame317_callCallback:cb arguments:@[@{@"ok": @NO,
                    @"error": err.localizedDescription ?: @"下载失败"}]];
                return;
            }
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dir = dest.stringByDeletingLastPathComponent;
            if (![fm fileExistsAtPath:dir]) {
                [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            }
            if ([fm fileExistsAtPath:dest]) [fm removeItemAtPath:dest error:nil];
            BOOL ok = [fm moveItemAtPath:location.path toPath:dest error:nil];
            [sself ame317_callCallback:cb arguments:@[@{@"ok": @(ok),
                @"bytes": @((double)[fm attributesOfItemAtPath:dest error:nil].fileSize),
                @"path": ok ? dest : @""}]];
        });
    }];
    [task resume];
}

#pragma mark - Task366 崩溃分析（logs.read；hs_err JVM 崩溃日志）

- (nullable NSArray *)listHsErrFiles {
    if (![self ame317_requirePerm:@"logs.read"]) return nil;
    NSMutableArray *roots = [NSMutableArray array];
    const char *gd = getenv("POJAV_GAME_DIR");
    const char *home = getenv("POJAV_HOME");
    if (gd && *gd) [roots addObject:[NSString stringWithUTF8String:gd]];
    if (home && *home) [roots addObject:[NSString stringWithUTF8String:home]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    for (NSString *root in roots) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
            if (![name hasPrefix:@"hs_err"] || ![name hasSuffix:@".log"]) continue;
            NSString *p = [root stringByAppendingPathComponent:name];
            NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
            [files addObject:@{@"name": name, @"path": p,
                               @"mtime": at[NSFileModificationDate] ?: [NSNull null]}];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        id am = a[@"mtime"], bm = b[@"mtime"];
        if (![am isKindOfClass:[NSDate class]] || ![bm isKindOfClass:[NSDate class]]) return NSOrderedSame;
        return [bm compare:am];
    }];
    if (files.count > 20) files = [[files subarrayWithRange:NSMakeRange(0, 20)] mutableCopy];
    return files;
}

- (nullable NSDictionary *)analyzeLatestHsErr {
    if (![self ame317_requirePerm:@"logs.read"]) return nil;
    NSArray *files = [self listHsErrFiles];
    NSString *latest = files.firstObject[@"path"];
    if (![latest isKindOfClass:[NSString class]] || latest.length == 0) return nil;
    return [CrashAnalyzer analyzeHsErrFile:latest];
}

#pragma mark - Task366 内部工具

/// 回调进 JS（主线程；异常吞并记录，绝不让插件异常带崩启动器）
- (void)ame317_callCallback:(JSValue *)cb arguments:(NSArray *)args {
    if (!cb || !cb.isObject) return;
    @try {
        [cb callWithArguments:args];
        JSContext *ctx = cb.context;
        if (ctx.exception && !ctx.exception.isUndefined) {
            NSLog(@"[AmePlugin:%@] JS 异常: %@", self.pluginId, ctx.exception);
            ctx.exception = nil;
        }
    } @catch (NSException *ex) {
        NSLog(@"[AmePlugin:%@] 回调异常: %@", self.pluginId, ex);
    }
}

- (NSString *)ame317_string:(id)raw {
    return [raw isKindOfClass:[NSString class]] ? raw : nil;
}

/// JSC 桥 id 参数防呆：对象/数组可能以 JSValue 到达，递归解包为原生容器
- (id)ame317_unwrapJs:(id)raw {
    if (![raw isKindOfClass:[JSValue class]]) return raw;
    id obj = [(JSValue *)raw toObject];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
            out[k] = [self ame317_unwrapJs:v];
        }];
        return out;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id v in (NSArray *)obj) [out addObject:[self ame317_unwrapJs:v]];
        return out;
    }
    return obj;
}

- (UIWindow *)ame317_keyWindow {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in scene.windows) if (w.isKeyWindow) return w;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

- (void)teardown {
    [self.eventTable removeAllObjects];
    [self.rowTable removeAllObjects];
    [self.rowSpecTable removeAllObjects];
    [self ame364_teardownViews];   // ★ Task364：摘手势+还原几何，卸载零残留
}

@end
