#import "AmePluginRuntime.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"   // Task317：主题令牌覆盖钩子（ame317_setPluginThemeTokens）

#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 运行时实现（Task 317）
// 口径注释：
//  · 每插件独立 JSContext；上下文仅主队列访问（bootstrap/事件/回调同队
//    列串行，无锁口径）；teardown 与 load 亦主队列
//  · context.exceptionHandler 兜底：插件未捕获异常只记录不崩进程
//  · 主题令牌还原本地记账：_themeTokensByPlugin 保存每插件上次覆盖，
//    停用时 setPluginThemeTokens:nil 精确回收自己的令牌
//  · 前后台/实例事件经 NSNotificationCenter 订阅一次（单例生命周期）
// ═══════════════════════════════════════════════════════════════════

@interface AmePluginRuntime ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, JSContext *> *contexts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AmePluginBridge *> *bridges;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *themeTokensByPlugin;
@property (nonatomic, assign) BOOL booted;
@end

@implementation AmePluginRuntime

+ (instancetype)sharedRuntime {
    static AmePluginRuntime *rt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rt = [[AmePluginRuntime alloc] init];
    });
    return rt;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _contexts = [NSMutableDictionary dictionary];
        _bridges = [NSMutableDictionary dictionary];
        _themeTokensByPlugin = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 门面（友好 JS API 名）

// JSC 桥方法名规则 = 选择器去冒号拼接（on:handler: → onHandler），
// 门面把外部 API 整形成 ame.on/dialog/storage.* 等惯用形态。
static NSString *ame317_facadeSource(void) {
    return @"(function(raw){"
    "var ame={};"
    "ame.log=function(m){return raw.log(String(m));};"
    "ame.toast=function(t){return raw.toast(String(t));};"
    "ame.dialog=function(spec,cb){return raw.dialogCallback(spec||{},cb||function(){});};"
    "ame.on=function(ev,fn){return raw.onHandler(String(ev),fn||function(){});};"
    "ame.off=function(ev){return raw.off(ev===undefined?'':String(ev));};"
    "ame.addLauncherRow=function(spec,cb){return raw.addLauncherRowHandler(spec||{},cb||function(){});};"
    "ame.setThemeToken=function(tokens){return raw.setThemeToken(tokens||{});};"
    "ame.getPref=function(k){return raw.getPref(String(k));};"
    "ame.setPref=function(k,v){return raw.setPrefValue(String(k),v);};"
    "ame.getRenderer=function(){return raw.getRenderer();};"
    "ame.setRenderer=function(cfg){return raw.setRenderer(cfg||{});};"
    "ame.getProfiles=function(){return raw.getProfiles();};"
    "ame.storage={"
    "get:function(k){return raw.storageGet(String(k));},"
    // ★ Task331：storageSet:value: 经 JSExport 整形后 JS 名 = storageSetValue
    //   （旧调用 raw.storageSet 在协议桥下必 undefined → theme-sunset 调色
    //   落盘链/storage 全族静默断链）
    "set:function(k,v){return raw.storageSetValue(String(k),v);},"
    "remove:function(k){return raw.storageRemove(String(k));},"
    "keys:function(){return raw.storageKeys();}};"
    "ame.fetch=function(url,opts,cb){"
    "if(typeof opts==='function'){cb=opts;opts={};}"
    "return raw.fetchOptionsCallback(String(url),opts||{},cb||function(){});};"
    // ★ Task327：权限扩大 API 面（ui.nav / profile.write / files.game）
    "ame.openPage=function(id){return raw.openPage(String(id));};"
    "ame.createProfile=function(o){return raw.createProfile(o||{});};"
    "ame.deleteProfile=function(n){return raw.deleteProfile(String(n));};"
    "ame.listFiles=function(p){return raw.listGameFiles(String(p||'.'));};"
    "ame.readFile=function(p){return raw.readGameFile(String(p));};"
    "ame.writeFile=function(p,c,ap){return raw.writeGameFileContentAppend(String(p),String(c),!!ap);};"
    "ame.removeFile=function(p){return raw.removeGameFile(String(p));};"
    "return ame;"
    "})(ameRaw);";
}

#pragma mark - 装载 / 卸载

/// ★ Task326：内置插件首方信任自愈。病历（装机 568628f 日志实锤）：
///   [AmePlugin:theme-sunset] 权限拒绝: storage —— 内置四插件里 launch-counter/
///   renderer-quickswitch 的 storage 正常，theme-sunset 却被拒 = 存量安装的
///   state.json 授权表与现行 manifest 脱节（旧代安装/迁移期写入的残缺表，
///   installFromZip ⑥ 的"已有授权即跳过"口径让残缺永久化）。而三个高危权限
///   （theme-sunset 的 ui.theme / modrinth-hot 的 net / renderer-quickswitch 的
///   renderer.write）按 Task317 设计默认拒，用户不进详情页手动授权 = 插件
///   功能整体不可用（用户报障"插件功能无法正常使用"）。
///   修法 = 首方信任口径：包内 builtin-plugins 清单里的插件（应用签名随发、
///   仓库方维护的四件演示件）视为可信第一方——每次启动把其全部【声明】权限
///   同步为已授权（幂等全量覆盖）。第三方插件（用户 zip 导入/仓库外来源）
///   完全不受影响：高危默认拒 + 详情页手动授权的 Task317 安全口径原样保留。
///   代价（有意接受）：首方内置件的高危权限撤销不跨启动持久（下一轮启动
///   自愈回授）——四件均为启动器自带演示内容，不存在"长期吊销"场景；
///   详情页开关仍可即时生效（会话内撤销当次会话有效）。
+ (NSArray<NSString *> *)ame326_bundleBuiltinPluginIds {
    NSString *root = [[NSBundle mainBundle].resourcePath
                      stringByAppendingPathComponent:@"builtin-plugins"];
    NSArray<NSString *> *dirs = [NSFileManager.defaultManager
                                 contentsOfDirectoryAtPath:root error:nil];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSString *dir in dirs) {
        if ([dir hasPrefix:@"."]) continue;
        NSData *data = [NSData dataWithContentsOfFile:
            [[root stringByAppendingPathComponent:dir]
             stringByAppendingPathComponent:@"manifest.json"]];
        if (!data) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        NSString *pid = json[@"id"];
        if ([pid isKindOfClass:[NSString class]] && pid.length > 0) {
            [ids addObject:pid];
        }
    }
    return ids;
}

+ (void)ame326_healFirstPartyGrants {
    NSArray<NSString *> *builtin = [self ame326_bundleBuiltinPluginIds];
    if (builtin.count == 0) return;
    for (NSString *pid in [AmePluginManager installedPluginIds]) {
        if (![builtin containsObject:pid]) continue;   // 仅首方内置件，第三方不碰
        AmePluginManifest *m = [AmePluginManager manifestForPlugin:pid];
        if (!m || m.permissions.count == 0) continue;
        NSDictionary<NSString *, NSNumber *> *cur =
            [AmePluginPermissions grantsForPlugin:pid];
        BOOL needHeal = (cur.count != m.permissions.count);
        if (!needHeal) {
            for (NSString *p in m.permissions) {
                if (![cur[p] boolValue]) { needHeal = YES; break; }
            }
        }
        if (!needHeal) continue;
        NSMutableDictionary<NSString *, NSNumber *> *g =
            [NSMutableDictionary dictionary];
        for (NSString *p in m.permissions) g[p] = @1;   // 首方信任：全量授
        [AmePluginPermissions replaceGrants:g forPlugin:pid];
        [AmePluginPermissions setPluginEnabled:YES pluginId:pid];
        NSLog(@"[AmePlugin] Task326 first-party grant heal: %@ (%@ perms -> granted)",
              pid, @(m.permissions.count));
    }
}

/// ★ Task330：内置插件内容自愈 —— "插件还是无法使用"终审收口。
/// 病历（装机 6f27abab latestlog 实锤）：四内置件"已装载"且权限计数与包内
/// manifest 全符（4/3/5/3），但 [Ame326] 授权自愈零日志、全脚本 ame.log
/// 零输出、贡献行分区恒空、全程零权限拒绝零 JS 异常 —— 唯一自洽解释：
/// 设备安装副本是【旧代 main.js】（manifest 自 Task318 未变故计数对上；
/// 旧 JS 无贡献行注册/无尾日志），而 installFromZip"已有授权即跳过"
/// （Task326 注记在案）+ 仓库重装同样被拦 = 陈旧副本无任何升级通道，
/// 残缺永久化。修法 = 首方信任口径延伸到内容：每次启动把包内
/// builtin-plugins 的 manifest.json/main.js 与安装副本逐字节对比，不一致
/// 即整文件覆盖（NSDataWritingAtomic 原子替换）。第三方插件零触碰。
/// 幂等：一致即跳过零写。时机：bootIfNeeded 内授权自愈之后、装载循环
/// 之前（装载拿到的必是新件，无需热重载路径）。
+ (void)ame330_refreshFirstPartyContent {
    NSString *ame330_bundleRoot = [[NSBundle mainBundle].resourcePath
        stringByAppendingPathComponent:@"builtin-plugins"];
    NSArray<NSString *> *ame330_builtin = [self ame326_bundleBuiltinPluginIds];
    if (ame330_builtin.count == 0) return;
    // ★ Task330 编译雷预防：AmePluginManager 无 +pluginsRoot 类方法声明
    //   （ame317_pluginsRootDir C 函数是跨文件公开面，AmePluginPermissions.h
    //   声明）——直接用 C 面入口，勿添 .h 新 API 面。
    NSString *ame330_installRoot = ame317_pluginsRootDir();
    if (ame330_installRoot.length == 0) return;
    NSFileManager *ame330_fm = [NSFileManager defaultManager];
    for (NSString *pid in [AmePluginManager installedPluginIds]) {
        if (![ame330_builtin containsObject:pid]) continue;   // 仅首方内置件
        NSString *ame330_srcDir = [ame330_bundleRoot stringByAppendingPathComponent:pid];
        NSString *ame330_dstDir = [ame330_installRoot
            stringByAppendingPathComponent:pid];
        BOOL ame330_refreshed = NO;
        // ★ Task331：首方内置件开机普查行 —— 每件每次启动一行，bundle 侧与
        //   安装侧 main.js 双向大小 + 判定词。装机 adb63d33 实锤：刷新静默
        //   无日志 = bundle 缺 src 与 bundle==installed 两种病灶不可分辨，
        //   旧代 main.js 无升级通道永久化的死案再无取证手段。bundle 侧
        //   main.js 缺失升格为 ERROR（payload cp -R 链路完备时应永不发生，
        //   发生即包体残缺实锤）。
        NSData *ame331_bundleMain = [NSData dataWithContentsOfFile:
            [ame330_srcDir stringByAppendingPathComponent:@"main.js"]];
        NSData *ame331_instMain = [NSData dataWithContentsOfFile:
            [ame330_dstDir stringByAppendingPathComponent:@"main.js"]];
        NSString *ame331_verdict =
            (ame331_bundleMain.length == 0) ? @"bundle-missing-main" :
            (ame331_instMain == nil)        ? @"installed-missing-main" :
            ([ame331_instMain isEqualToData:ame331_bundleMain] ? @"same" : @"stale");
        NSLog(@"[AmePlugin] Task331 builtin census: %@ bundle(main=%@B) installed(main=%@B) verdict=%@",
              pid, @(ame331_bundleMain.length), @(ame331_instMain.length), ame331_verdict);
        if (ame331_bundleMain.length == 0) {
            NSLog(@"[AmePlugin] Task331 ERROR: bundle builtin-plugins missing main.js for %@ -- refresh channel dead, check payload packaging", pid);
        }
        for (NSString *ame330_fname in @[@"manifest.json", @"main.js"]) {
            NSString *ame330_src = [ame330_srcDir stringByAppendingPathComponent:ame330_fname];
            NSString *ame330_dst = [ame330_dstDir stringByAppendingPathComponent:ame330_fname];
            NSData *ame330_new = [NSData dataWithContentsOfFile:ame330_src];
            if (ame330_new.length == 0) continue;   // 包内缺失（异常态）不覆盖
            NSData *ame330_old = [NSData dataWithContentsOfFile:ame330_dst];
            if (ame330_old && [ame330_old isEqualToData:ame330_new]) continue;
            if (![ame330_fm fileExistsAtPath:ame330_dstDir]) {
                [ame330_fm createDirectoryAtPath:ame330_dstDir
                  withIntermediateDirectories:YES attributes:nil error:nil];
            }
            if (![ame330_new writeToFile:ame330_dst options:NSDataWritingAtomic error:nil]) {
                NSLog(@"[AmePlugin] Task330 content refresh write failed: %@/%@", pid, ame330_fname);
                continue;
            }
            ame330_refreshed = YES;
        }
        if (ame330_refreshed) {
            NSLog(@"[AmePlugin] Task330 first-party content refresh: %@ (bundle builtin-plugins -> installed copy, rows/log/effect surface revived)", pid);
        }
    }
}

+ (void)bootIfNeeded {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self bootIfNeeded]; });
        return;
    }
    AmePluginRuntime *rt = [self sharedRuntime];
    if (rt.booted) return;
    rt.booted = YES;
    [rt ame317_observeSystemEvents];

    // ★ Task326：首方授权自愈先于装载循环（本启动内装载即拿到完整授权）
    [self ame326_healFirstPartyGrants];

    // ★ Task330：首方内容自愈（旧代 main.js 安装副本升级到包内现役版，
    //   贡献行/尾日志/效果面全部复活；先于装载循环 = 装载必是新件）
    [self ame330_refreshFirstPartyContent];

    for (NSString *pid in [AmePluginManager installedPluginIds]) {
        AmePluginManifest *m = [AmePluginManager manifestForPlugin:pid];
        if (!m) {
            NSLog(@"[AmePlugin] 跳过损坏插件目录: %@", pid);
            continue;
        }
        if (![AmePluginPermissions pluginEnabled:pid]) continue;
        [rt ame317_loadPlugin:pid manifest:m dispatchLaunchEvent:YES];
    }
}

+ (void)setPluginEnabled:(NSString *)pluginId enabled:(BOOL)enabled {
    if (pluginId.length == 0) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setPluginEnabled:pluginId enabled:enabled];
        });
        return;
    }
    AmePluginRuntime *rt = [self sharedRuntime];
    if (enabled) {
        AmePluginManifest *m = [AmePluginManager manifestForPlugin:pluginId];
        if (!m) return;
        if (rt.contexts[pluginId]) return; // 已在跑
        [rt ame317_loadPlugin:pluginId manifest:m dispatchLaunchEvent:YES];
    } else {
        [rt ame317_unloadPlugin:pluginId];
    }
    [AmePluginPermissions setPluginEnabled:enabled pluginId:pluginId];
}

+ (BOOL)isRunning:(NSString *)pluginId {
    return [self sharedRuntime].contexts[pluginId] != nil;
}

- (void)ame317_loadPlugin:(NSString *)pluginId
                 manifest:(AmePluginManifest *)m
      dispatchLaunchEvent:(BOOL)dispatchLaunchEvent {
    NSAssert([NSThread isMainThread], @"AmePlugin 装载必须主线程");
    if (self.contexts[pluginId]) return;

    NSString *entryPath = [AmePluginManager entryPathForPlugin:pluginId];
    if (!entryPath) {
        NSLog(@"[AmePlugin:%@] 入口脚本缺失，跳过", pluginId);
        return;
    }
    NSString *source = [NSString stringWithContentsOfFile:entryPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    if (source.length == 0) {
        NSLog(@"[AmePlugin:%@] 入口脚本为空或不可读", pluginId);
        return;
    }

    JSContext *ctx = [[JSContext alloc] init];
    __weak JSContext *weakCtx = ctx;
    ctx.name = [NSString stringWithFormat:@"AmePlugin:%@", pluginId];
    ctx.exceptionHandler = ^(JSContext *exceptionCtx, JSValue *exception) {
        NSLog(@"[AmePlugin:%@] 未捕获 JS 异常: %@", pluginId,
              exception ?: (weakCtx ? weakCtx.exception : nil));
    };

    AmePluginBridge *bridge = [[AmePluginBridge alloc]
                               initWithPluginId:pluginId
                               declaredPermissions:m.permissions];
    self.bridges[pluginId] = bridge;
    self.contexts[pluginId] = ctx;

    // 原始桥对象 + 友好门面
    [ctx setObject:bridge forKeyedSubscript:@"ameRaw"];
    [ctx evaluateScript:ame317_facadeSource()];
    // 极简运行环境补齐（JSC 无 console；ameLogFn 先赋值再入对象字面量，
    // 避免 console.log 自引用求值时 console 尚未赋值的 undefined 雷）
    [ctx evaluateScript:
     @"var ameLogFn=function(){var a=[].slice.call(arguments).join(' ');"
     "ame.log(a);};"
     "this.console={log:ameLogFn,warn:ameLogFn,error:ameLogFn,info:ameLogFn};"];

    @try {
        [ctx evaluateScript:source];
    } @catch (NSException *ex) {
        NSLog(@"[AmePlugin:%@] 装载异常: %@", pluginId, ex);
    }
    JSValue *topException = ctx.exception;
    if (topException && !topException.isUndefined) {
        NSLog(@"[AmePlugin:%@] 装载期 JS 异常: %@", pluginId, topException);
        ctx.exception = nil;
    }
    // ★ Task331：装载普查行 —— 每件装载后一行，四要素一锤定音：源长度
    //   （=0 即空脚本）/ ame.addLauncherRow 可调性（JSExport 桥面健康度：
    //   MISSING = 桥面未导出，TypeError 将随之）/ 已注册贡献行数（行注册
    //   是否落地）/ 装载期 JS 异常。设备端“陈旧副本 vs 桥不可调 vs JS
    //   异常”三类病灶自此日志直接分型，不再依赖外围症状拼图。
    {
        JSValue *ame331_ame = [ctx objectForKeyedSubscript:@"ame"];
        JSValue *ame331_fn = [ame331_ame objectForKeyedSubscript:@"addLauncherRow"];
        BOOL ame331_ameOk = ame331_ame.isObject && ame331_fn.isObject;
        NSUInteger ame331_rows = [self.bridges[pluginId] contributedRows].count;
        BOOL ame331_exc = topException && !topException.isUndefined;
        NSLog(@"[AmePlugin:%@] Task331 load census: src=%@B ame(addLauncherRow)=%@ rows=%lu jsException=%@",
              pluginId, @(source.length),
              ame331_ameOk ? @"callable" : @"MISSING",
              (unsigned long)ame331_rows,
              ame331_exc ? @"YES" : @"no");
    }

    // 主题令牌：storage 里若有 __theme 且仍有授权 → 开机重放
    // ★ Task326：重放读取前置 storage 授权守卫——storageGet 内部走桥边界
    //   执法（ame317_requirePerm），未声明/未授权 storage 的插件在此必然
    //   触发"权限拒绝: storage"假告警（装机日志实锤：modrinth-hot 根本不用
    //   storage，其 JS 只调 fetch/dialog/rows，拒绝日志纯由本重放无守卫
    //   调用产生）。无授权时静默跳过重放 = 语义本就正确（无 storage 即无
    //   持久化主题可重放）。
    AmePluginBridge *b = self.bridges[pluginId];
    id savedTheme = nil;
    if ([AmePluginPermissions pluginHasGrant:pluginId permission:@"storage"]) {
        savedTheme = [b storageGet:@"__theme"];
    }
    if ([savedTheme isKindOfClass:[NSDictionary class]] &&
        [AmePluginPermissions pluginHasGrant:pluginId permission:@"ui.theme"]) {
        [self ame317_applyThemeTokens:pluginId tokens:savedTheme];
    }

    if (dispatchLaunchEvent) {
        [self ame317_dispatchEvent:@"app.launch" payload:pluginId toPlugin:pluginId];
    }
    NSLog(@"[AmePlugin:%@] 已装载（v%@，%@ 项权限）", pluginId, m.version,
          @(m.permissions.count));
}

- (void)ame317_unloadPlugin:(NSString *)pluginId {
    NSAssert([NSThread isMainThread], @"AmePlugin 卸载必须主线程");
    // 主题令牌还原本插件贡献
    [self ame317_applyThemeTokens:pluginId tokens:nil];
    AmePluginBridge *bridge = self.bridges[pluginId];
    [bridge teardown];
    JSContext *ctx = self.contexts[pluginId];
    if (ctx) {
        [ctx setName:@"AmePlugin:dead"];
        // JSC 无显式销毁 API；置空引用由 ARC 回收（回调表已清，不再有入流）
        ctx.exception = nil;
    }
    [self.bridges removeObjectForKey:pluginId];
    [self.contexts removeObjectForKey:pluginId];
    NSLog(@"[AmePlugin:%@] 已卸载", pluginId);
}

#pragma mark - 主题令牌（覆盖与还原）

- (void)ame317_applyThemeTokens:(NSString *)pluginId
                         tokens:(NSDictionary<NSString *, NSString *> *)tokens {
    NSDictionary *previous = self.themeTokensByPlugin[pluginId];
    if (previous) {
        // 先精确还原上一次本插件的令牌，再应用新集合（防残留）
        [ZL2Theme ame317_setPluginThemeTokens:pluginId tokens:nil];
    }
    if (tokens.count > 0) {
        BOOL ok = [ZL2Theme ame317_setPluginThemeTokens:pluginId tokens:tokens];
        if (ok) {
            self.themeTokensByPlugin[pluginId] = tokens;
        } else {
            self.themeTokensByPlugin[pluginId] = @{};
        }
    } else {
        [self.themeTokensByPlugin removeObjectForKey:pluginId];
    }
}

#pragma mark - 事件派发

+ (void)emitEvent:(NSString *)event payload:(id)payload {
    if (event.length == 0) return;
    AmePluginRuntime *rt = [self sharedRuntime];
    if (!rt.booted) return;
    for (NSString *pid in [rt.contexts allKeys]) {
        [rt ame317_dispatchEvent:event payload:payload toPlugin:pid];
    }
}

- (void)ame317_dispatchEvent:(NSString *)event payload:(id)payload toPlugin:(NSString *)pluginId {
    if (![NSThread isMainThread]) {
        // 快照 payload（调用方容器可能在派发前被改）；类型只按 id 语义使用
        id snapshot = [payload copy] ?: [NSNull null];
        AmePluginRuntime *rt = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [rt ame317_dispatchEvent:event payload:snapshot toPlugin:pluginId];
        });
        return;
    }
    AmePluginBridge *bridge = self.bridges[pluginId];
    if (!bridge) return;
    NSArray<JSValue *> *handlers = [bridge handlersForEvent:event];
    if (handlers.count == 0) return;
    id jsPayload = payload ?: [NSNull null];
    for (JSValue *handler in handlers) {
        @try {
            [handler callWithArguments:@[event, jsPayload]];
            JSContext *ctx = handler.context;
            if (ctx.exception && !ctx.exception.isUndefined) {
                NSLog(@"[AmePlugin:%@] 事件 %@ 处理异常: %@", pluginId, event, ctx.exception);
                ctx.exception = nil;
            }
        } @catch (NSException *ex) {
            NSLog(@"[AmePlugin:%@] 事件 %@ 回调崩溃防护: %@", pluginId, event, ex);
        }
    }
}

#pragma mark - 贡献行

+ (NSArray<NSDictionary *> *)allContributedRows {
    AmePluginRuntime *rt = [self sharedRuntime];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *pid in [rt.contexts allKeys]) {
        AmePluginBridge *b = rt.bridges[pid];
        [rows addObjectsFromArray:[b contributedRows]];
    }
    return rows;
}

+ (void)invokeRowTap:(NSString *)rowId {
    if (rowId.length == 0) return;
    // 行 id = "<pluginId>.<rowId>"；插件 id 本身可含点（manifest 规范
    // ^[a-z0-9][a-z0-9._-]{2,63}$），禁用首个点切分——遍历桥对象按
    // "pluginId." 前缀找唯一归属（前缀重叠时最长者赢）。
    AmePluginRuntime *rt = [self sharedRuntime];
    AmePluginBridge *owner = nil;
    NSUInteger best = 0;
    for (NSString *pid in rt.bridges) {
        NSString *prefix = [pid stringByAppendingString:@"."];
        if ([rowId hasPrefix:prefix] && prefix.length >= best) {
            best = prefix.length;
            owner = rt.bridges[pid];
        }
    }
    [owner invokeRowTap:rowId];
}

#pragma mark - 游戏启停 / 前后台接线

+ (void)notifyGameStarting {
    [self emitEvent:@"game.starting" payload:nil];
}

+ (void)notifyGameExited:(NSInteger)exitCode {
    [self emitEvent:@"game.exited" payload:@(exitCode)];
}

+ (void)notifyAppEnteringForeground {
    [self emitEvent:@"app.foreground" payload:nil];
}

+ (void)notifyAppEnteringBackground {
    [self emitEvent:@"app.background" payload:nil];
}

#pragma mark - 系统事件订阅（单例一次性）

- (void)ame317_observeSystemEvents {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    __weak typeof(self) wself = self;

    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_) {
        [wself ame317_dispatchAll:@"app.foreground" payload:nil];
    }];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_) {
        [wself ame317_dispatchAll:@"app.background" payload:nil];
    }];
    // 实例域：既有通知直通（Task 既有事件面，零新增接线）
    [nc addObserverForName:@"SelectedProfileChanged"
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [wself ame317_dispatchAll:@"profile.changed" payload:note.object];
    }];
    [nc addObserverForName:@"ReloadProfileList"
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_) {
        [wself ame317_dispatchAll:@"profile.listChanged" payload:nil];
    }];
}

- (void)ame317_dispatchAll:(NSString *)event payload:(id)payload {
    if (!self.booted) return;
    for (NSString *pid in [self.contexts allKeys]) {
        [self ame317_dispatchEvent:event payload:payload toPlugin:pid];
    }
}

@end
