#import "AmePluginBridge.h"
#import "AmePluginPermissions.h"
#import "AmePluginManager.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"       // localize + 渲染器宏（RENDERER_NAME_*）
#import "ZL2M3Kit.h"    // MD3 对话框
#import "ZL2Theme.h"    // 主题令牌覆盖钩子
#import "ZL2ShellViewController.h"   // Task327：页面导航通知契约（ZL2ShellNavigate）

#import <UIKit/UIKit.h>

// ═══════════════════════════════════════════════════════════════════
// AmePluginBridge 实现（Task 317）
// 口径注释：
//  · 权限执法点：ame317_requirePerm 先查 manifest 声明（未声明=连查询都
//    不做），再查用户授权；拒绝即向 JS 抛本地化异常 + return
//  · 所有 JS 可见方法仅允许主线程调用（Runtime 保证事件/回调主线程派发）
//  · fetch 走 NSURLSession 异步，回调切主线程后进 JS；30s 超时
//  · storage 沙盒 = 插件目录内 storage.json（键值 JSON，4MB 上限防失控）
//  · 主题令牌覆盖经 ZL2Theme 的插件覆盖表（smoke 目标零新增依赖）
// ═══════════════════════════════════════════════════════════════════

static const NSUInteger ame317_storageMaxBytes = 4 * 1024 * 1024;

@interface AmePluginBridge ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<JSValue *> *> *eventTable;
@property (nonatomic, strong) NSMutableDictionary<NSString *, JSValue *> *rowTable; // rowId → handler
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *rowSpecTable;
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

#pragma mark - 内部工具

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
}

@end
