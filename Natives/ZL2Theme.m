//
// ZL2Theme.m — Material 3 令牌层（7.0-UI-14：embermire 色板 1:1）
//
// 色值来源（ZalithLauncher2 GNU GPL 参考副本，只读）：
//   ui/theme/Color.kt 各 ColorTheme(...) 第一列 = embermire；
//   ui/theme/Theme.kt embermireLight/embermireDark。
// 全部经 UIColor dynamicProvider 跟随系统深浅（系统正统路径，不手写
// traitCollection 分支）。
//

#import "ZL2Theme.h"
#import <math.h>   // Task341：isnan（形状/字体覆盖值防御钳制；smoke/Preview 目标自包含编译）

#pragma mark - ★Task429 主题中枢懒启动钩子（函数指针，运行时注册）

// mode≠0 的存档若无人触达中枢，色板永不生效（中枢无 AppDelegate/
// SceneDelegate 挂点，两文件均不在本工位写权内）。ZL2DynamicPalette
// +load 注册懒启动钩子（见彼处）；首个 ZL2Theme 色查询即壳层构建期，
// 此处触达中枢（init 读三键落板早于首建 = 零闪变）。
// ★ 链接依赖纪律（Task317 判例同口径）：本 TU 保持 smoke/Preview 目标
//   零新增链接依赖——中枢 TU 缺席的目标钩子恒 NULL = 静默跳过，
//   embermire 基线逐位不变；不直接 #import 中枢头。
static void (*ame429_paletteBootstrapHook)(void) = NULL;

static UIColor *ZL2ColorLightDark(int light, int dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *traits) {
        int value = (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                               green:((value >> 8) & 0xFF) / 255.0
                                blue:(value & 0xFF) / 255.0
                               alpha:1.0];
    }];
}

#pragma mark - ★Task429 活动色板覆盖层（8.1 跟随背景/预设/CUSTOM 动态主题）

// 覆盖表：token → @[浅 hexInt, 深 hexInt]（NSNumber）。主题中枢
// ZL2DynamicPalette 在色板生成后经 +ame429_setActivePaletteOverlay 整表
// 推送；nil/空 = 无覆盖（未初始化/模式 0 时 provider 逐位回落 embermire
// 静态值 = 零回归）。字典指针整体原子换（immutable，读侧无锁）。
static NSDictionary<NSString *, NSArray<NSNumber *> *> *ame429_activePaletteOverlay = nil;

// 覆盖点查询：token 命中返回对应态 hexInt，miss 返回 -1（回落信号）
static int Ame429OverlayHex(NSString *token, BOOL dark) {
    if (ame429_activePaletteOverlay.count == 0) return -1;
    NSArray *pair = ame429_activePaletteOverlay[token];
    if (![pair isKindOfClass:[NSArray class]] || pair.count != 2) return -1;
    NSNumber *v = pair[dark ? 1 : 0];
    if (![v isKindOfClass:[NSNumber class]]) return -1;
    return [v intValue];
}

#pragma mark - Task317 插件主题令牌覆盖（高危权限 ui.theme；smoke 目标零依赖）

// 覆盖基础设施（自包含，不依赖插件运行时）：
//   ame317_flatTokenOverride: token → @[pluginId, UIColor]（后写者胜）
//   setter 经 ZL2Theme.h 公开，AmePluginBridge 在 ui.theme 授权下调用。
static NSMutableDictionary<NSString *, NSArray *> *ame317_flatTokenOverride = nil;

static UIColor *AmePluginParseHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (![s isKindOfClass:[NSString class]]) return nil;
    if (s.length != 6 && s.length != 8) return nil;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < s.length; i++) {
        if (![ok characterIsMember:[s characterAtIndex:i]]) return nil;
    }
    unsigned long long v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    [sc scanHexLongLong:&v];
    CGFloat alpha = (s.length == 8) ? ((v & 0xFF) / 255.0) : 1.0;
    if (s.length == 8) v >>= 8;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:alpha];
}

static UIColor *AmePluginColorOverride(NSString *token) {
    if (ame317_flatTokenOverride.count == 0) return nil;
    NSArray *entry = ame317_flatTokenOverride[token];
    if (entry.count == 2) return entry[1];
    return nil;
}

// ★ Task379：插件感知动态色——原先插件覆盖返回【静态色】，而
//   AppDelegate 启动期（applyGlobalAppearance）预建的 Appearance 代理
//   （导航栏标题等）捕获的是覆盖前的【动态回退色】，插件换装后不回溯
//   → 装机实锤：详情页导航栏标题白字白底（IMG_0553）。改为恒返回动态
//   UIColor，provider 运行时实时查覆盖表：有覆盖 → 取覆盖值（随插件
//   换板/实时明暗切换即时生效，含预建代理）；无覆盖 → 经典深浅对。
static UIColor *Ame317_PluginAwareColor(NSString *token, int light, int dark) {
    if (ame429_paletteBootstrapHook != NULL) {
        ame429_paletteBootstrapHook();   // ★Task429：中枢懒启动（+load 注册 trampoline，首次触达自举）
    }
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *traits) {
        UIColor *ame317_ov = AmePluginColorOverride(token);
        if (ame317_ov) return [ame317_ov resolvedColorWithTraitCollection:traits];
        // ★Task429：活动色板覆盖点（第二优先级）——跟随背景/预设/CUSTOM
        //   动态主题经此贯通全部 28 枚色值角色；miss 回落 embermire 静态对
        //   （未初始化/模式 0 时逐位等价旧值 = 零回归）。
        BOOL ame429_dark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
        int ame429_v = Ame429OverlayHex(token, ame429_dark);
        if (ame429_v >= 0) {
            return [UIColor colorWithRed:((ame429_v >> 16) & 0xFF) / 255.0
                                   green:((ame429_v >> 8) & 0xFF) / 255.0
                                    blue:(ame429_v & 0xFF) / 255.0
                                   alpha:1.0];
        }
        int value = ame429_dark ? dark : light;
        return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                               green:((value >> 8) & 0xFF) / 255.0
                                blue:(value & 0xFF) / 255.0
                               alpha:1.0];
    }];
}

// 宏：getter 一行式覆盖检查（GNU 语句表达式，clang 默认支持）
// ★ Task379：覆盖分支改走插件感知动态色（provider 内实时查表，预建
//   Appearance 代理与运行时换板全部正确解析；宏展开语义对调用方透明）
#define AME317_PLUGIN_COLOR(token, light, dark) \
    Ame317_PluginAwareColor(@#token, light, dark)

#pragma mark - Task341 形状/字体覆盖基础设施（自包含，不依赖插件运行时）

// 记账口径与 ame317 逐位同构：token → @[pluginId, 值]（后写者胜）。
//   shape 表存 NSNumber（pt）；font 表存 UIFont（解析定型，getter 零重解析）。
static NSMutableDictionary<NSString *, NSArray *> *ame341_shapeOverride = nil;
static NSMutableDictionary<NSString *, NSArray *> *ame341_fontOverride = nil;

static CGFloat AmePluginShapeOverride(NSString *token, CGFloat fallback) {
    if (ame341_shapeOverride.count == 0) return fallback;
    NSArray *entry = ame341_shapeOverride[token];
    if (entry.count == 2) return [(NSNumber *)entry[1] doubleValue];
    return fallback;
}

static UIFont *AmePluginFontOverride(NSString *token, UIFont *fallback) {
    if (ame341_fontOverride.count == 0) return fallback;
    NSArray *entry = ame341_fontOverride[token];
    if (entry.count == 2) return (UIFont *)entry[1];
    return fallback;
}

#pragma mark - Task343 布局覆盖基础设施（与 ame341 逐位同构，自包含不依赖插件运行时）

// 记账口径同 ame341：token → @[pluginId, NSNumber(pt)]（后写者胜）。
static NSMutableDictionary<NSString *, NSArray *> *ame343_layoutOverride = nil;

static CGFloat Ame343LayoutOverride(NSString *token, CGFloat fallback) {
    if (ame343_layoutOverride.count == 0) return fallback;
    NSArray *entry = ame343_layoutOverride[token];
    if (entry.count == 2) return [(NSNumber *)entry[1] doubleValue];
    return fallback;
}

#pragma mark - Task347 结构覆盖基础设施（与 ame341/343 逐位同构，自包含不依赖插件运行时）

// 记账口径同 ame341：token → @[pluginId, NSString]（后写者胜）。
static NSMutableDictionary<NSString *, NSArray *> *ame347_structureOverride = nil;

static NSString *Ame347StructureOverride(NSString *token, NSString *fallback) {
    if (ame347_structureOverride.count == 0) return fallback;
    NSArray *entry = ame347_structureOverride[token];
    if (entry.count == 2) {
        NSString *v = entry[1];
        if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
    }
    return fallback;
}

// weight 字符串/数字 → UIFontWeight（白名单映射，未知值回落 regular）
static UIFontWeight Ame341WeightFromValue(id v) {
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"medium"] || [s isEqualToString:@"500"]) return UIFontWeightMedium;
        if ([s isEqualToString:@"semibold"] || [s isEqualToString:@"600"]) return UIFontWeightSemibold;
        if ([s isEqualToString:@"bold"] || [s isEqualToString:@"700"]) return UIFontWeightBold;
        return UIFontWeightRegular;   // "regular"/"400"/未知字符串
    }
    if ([v isKindOfClass:[NSNumber class]]) {
        double w = [(NSNumber *)v doubleValue];
        if (w >= 700) return UIFontWeightBold;
        if (w >= 600) return UIFontWeightSemibold;
        if (w >= 500) return UIFontWeightMedium;
        return UIFontWeightRegular;
    }
    return UIFontWeightRegular;
}


// ★ Task346（用户第五轮复诉「插件只变了配色」· 机械根因定案）：三个令牌
//   setter 原本只改静态覆盖字典 + 持久化，从不触发任何 UI 重建——而几何
//   （圆角/字体/布局度量）与色板全部在视图构建期经 getter 烘焙，在屏页
//   面永远看不到令牌变化；用户在主页点击循环时能观察到的只有零散的动
//   态色刷新 = 「只变了配色」。修法：复用 Task230/Task344 久经验证的根
//   视图重建杠杆（post AppLanguageChanged → SceneDelegate
//   applyLanguageChange 重建 ZL2Shell）——令牌落表后全界面以新刻度整体
//   重建，色/形/字/排版四族即时生效。启动期重放路径由 rootViewController
//   缺席守卫天然跳过（令牌先于首次构建在位，首建即新刻度，无需重建）。
static BOOL ame346_rebuildScheduled = NO;
static CFAbsoluteTime ame346_lastRebuildAt = 0.0;
static BOOL ame346_trailingPending = NO;
static const CFAbsoluteTime ame346_rebuildMinInterval = 0.4;   // ★ Task380：重建冷却（秒）

// ★ Task455：启动期令牌突发合并——装机 latestlog（2ed20a6 构建）实锤：
//   启动 ~500ms 窗口内三源令牌先后落表（插件装载色板 + Ame398 启动外观
//   同步广播 → JS 重应用 + Ame429 壁纸 palette overlay），Task346 杠杆逐
//   源整壳重建（日志壳 viewDidLoad ×3 + 第 4 次 in flight）+ 两次 0.3s
//   CrossDissolve 重叠 = "Unbalanced calls to begin/end appearance
//   transitions" + 启动卡死感。根修：首帧落地（首壳 viewDidAppear，进程
//   级一次）前，"根已建且视图已加载"状态下的令牌重建请求不再逐源放行，
//   只记脏；首帧落地时恰好补建一次（整壳重建总量 4→2）。根未建/视图未
//   加载的请求保持静默跳过（令牌烘焙进首建，既有语义）；首帧后的请求走
//   既有同拍合并 + Task380 冷却（交互语义零回退）。
static BOOL ame455_startupLanded = NO;
static BOOL ame455_startupRebuildDirty = NO;

// ★ Task456：重建回声沉降窗——装机 latestlog（c737883/Task455 构建）实锤：
//   首帧后整壳重建（Task455 flush 补建）自身的构建序列再落令牌（插件色板 /
//   Ame429 壁纸 overlay 等），echo 请求走既有同拍合并 + Task380 冷却(0.4s)，
//   但首建时 ame346_lastRebuildAt 尚无值（首建非 Task346 广播）→ 冷却守卫
//   ame346_lastRebuildAt > 0.0 恒假 → echo 直接放行 = "shell viewDidLoad
//   done → Task346 posted" 链式再排整壳重建（21:40:39.277 补建后回声广播 +
//   21:41:19.95 第三次壳构建 + 第 4 次 in flight = 「依旧启动卡死」残余）。
//   根修 = 每次 Task346 重建落地后 0.8s 沉降窗：窗口内请求一律视为重建自身
//   回声吞掉（不调度不尾沿）。令牌态全局现读，重建本身已烘焙当前值，无语义
//   损失；窗口外真变更（用户交互/插件新事件）照常即时重建。尾沿补排计时器
//   落窗内由 postRootRebuildNow 入口统一拦截（不追加新广播）。
static CFAbsoluteTime ame456_settleUntil = 0.0;

// 键窗根 VC 探测（ame346_postRootRebuildNow 既有场景遍历的公共化，唯一实现）
static UIViewController *ame455_keyRootViewController(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *ame455_scene in UIApplication.sharedApplication.connectedScenes) {
            if (![ame455_scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *ame455_w in ((UIWindowScene *)ame455_scene).windows) {
                if (ame455_w.isKeyWindow) return ame455_w.rootViewController;
            }
        }
    }
    return nil;
}

// 首帧落地锚点消费（ZL2ShellViewController viewDidAppear 进程级一次调用）：
//   返回 YES = 启动窗口内有被抑制的令牌重建请求，调用方应恰好补建一次。
//   （方法体在 @implementation 内，见 ame429_requestRootRebuild 邻位）

static void ame346_postRootRebuildNow(void) {
    @try {
        // ★ Task456：沉降窗拦截（含冷却期尾沿补排计时器落窗内的补排——
        //   补排若在窗内落地 = 回声重建，吞掉并留痕；真变更窗口外自然放行）
        CFAbsoluteTime ame456_now0 = CFAbsoluteTimeGetCurrent();
        if (ame456_settleUntil > 0.0 && ame456_now0 < ame456_settleUntil) {
            NSLog(@"[ZL2Theme] Task456: root rebuild request swallowed in settle window (%.2fs left)",
                  ame456_settleUntil - ame456_now0);
            return;
        }
        UIViewController *ame346_root = ame455_keyRootViewController();
        if (!ame346_root) return;   // 启动期根未建：重放路径无需重建
        ame346_lastRebuildAt = CFAbsoluteTimeGetCurrent();
        ame456_settleUntil = ame346_lastRebuildAt + 0.8;   // ★ Task456：回声沉降窗 0.8s
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AppLanguageChanged" object:nil];
        NSLog(@"[ZL2Theme] Task346: token change -> root rebuild posted (AppLanguageChanged lever)");
    } @catch (NSException *ame346_e) {
        NSLog(@"[ZL2Theme] Task346: root rebuild dispatch exception (%@)", ame346_e);
    }
}

static void ame346_requestRootRebuild(void) {
    // ★ Task455：启动期突发合并（首帧前抑制，首帧后一次补建；判例见上）
    //   根未建/根视图未加载 → 令牌烘焙进首建，零重建零记脏（原 234 行
    //   "rootViewController 缺席守卫"只查根分配、不查视图加载 = 插件装载
    //   期请求漏网，本轮一并收紧）。
    if (!ame455_startupLanded) {
        UIViewController *ame455_root = ame455_keyRootViewController();
        if (!ame455_root || !ame455_root.viewIfLoaded) return;
        ame455_startupRebuildDirty = YES;
        return;
    }
    if (ame346_rebuildScheduled) return;   // 同拍连发合并（连点循环去抖）
    ame346_rebuildScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        ame346_rebuildScheduled = NO;
        // ★ Task380：最小间隔冷却 + 尾沿补排——Task346 杠杆原语义「每次令牌
        //   落表即整壳重建」在 Task379 appearance.changed 事件面接入后成为
        //   反馈环放大器（重建→新壳 VC trait 事件→JS 重应用→再重建，~10 次/
        //   秒不可点击）。防环三层之一：同拍合并照旧 + 新增 400ms 冷却，冷却
        //   期内的请求不丢弃而是尾沿补排一次（保证最后一次变更终会落地重建，
        //   语义无损；配合壳层/JS 双侧去重，稳态下环在第一拍即断）。
        CFAbsoluteTime ame380_now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime ame380_elapsed = ame380_now - ame346_lastRebuildAt;
        if (ame346_lastRebuildAt > 0.0 && ame380_elapsed < ame346_rebuildMinInterval) {
            if (!ame346_trailingPending) {
                ame346_trailingPending = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((ame346_rebuildMinInterval - ame380_elapsed) * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    ame346_trailingPending = NO;
                    ame346_postRootRebuildNow();
                });
            }
            return;
        }
        ame346_postRootRebuildNow();
    });
}

@implementation ZL2Theme

+ (BOOL)ame317_setPluginThemeTokens:(NSString *)pluginId
                             tokens:(NSDictionary<NSString *, NSString *> *)tokens {
    if (pluginId.length == 0) return NO;
    static NSSet<NSString *> *overridable = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        overridable = [NSSet setWithArray:@[
            @"primary", @"onPrimary", @"primaryContainer", @"onPrimaryContainer",
            @"secondary", @"onSecondary", @"secondaryContainer", @"onSecondaryContainer",
            @"tertiary", @"onTertiary", @"tertiaryContainer", @"onTertiaryContainer",
            @"surface", @"onSurface", @"onSurfaceVariant", @"surfaceVariant",
            @"surfaceContainerLowest", @"surfaceContainerLow", @"surfaceContainer",
            @"surfaceContainerHigh", @"surfaceContainerHighest", @"surfaceBright",
            @"outline", @"outlineVariant",
            @"error", @"errorContainer", @"success", @"warning",
        ]];
    });
    if (!ame317_flatTokenOverride) {
        ame317_flatTokenOverride = [NSMutableDictionary dictionary];
    }
    // 先清本插件既有覆盖（还原语义），再落新集合（后写者胜）
    NSMutableArray *stale = [NSMutableArray array];
    [ame317_flatTokenOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *e, BOOL *_) {
        if ([e[0] isEqualToString:pluginId]) [stale addObject:k];
    }];
    for (NSString *k in stale) [ame317_flatTokenOverride removeObjectForKey:k];
    if (![tokens isKindOfClass:[NSDictionary class]] || tokens.count == 0) {
        ame346_requestRootRebuild();   // ★ Task346：还原语义同样即时生效
        return YES;
    }
    NSUInteger applied = 0;
    for (NSString *k in tokens) {
        if (![overridable containsObject:k]) continue;
        UIColor *c = AmePluginParseHex(tokens[k]);
        if (c) {
            ame317_flatTokenOverride[k] = @[pluginId, c];
            applied++;
        }
    }
    NSLog(@"[AmePlugin:%@] 主题令牌覆盖 %lu/%lu 项", pluginId,
          (unsigned long)applied, (unsigned long)tokens.count);
    ame346_requestRootRebuild();   // ★ Task346：覆盖落表即全界面重建
    return YES;
}

+ (BOOL)ame341_setPluginThemeShape:(NSString *)pluginId
                            tokens:(NSDictionary *)tokens {
    if (pluginId.length == 0) return NO;
    static NSSet<NSString *> *shapeKeys = nil;
    static NSSet<NSString *> *fontKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shapeKeys = [NSSet setWithArray:@[
            @"radiusXS", @"radiusS", @"radiusM", @"radiusL", @"radiusXL",
        ]];
        fontKeys = [NSSet setWithArray:@[
            @"fontHeadline", @"fontTitleLarge", @"fontTitleMedium",
            @"fontBodyLarge", @"fontBodyMedium",
            @"fontLabelLarge", @"fontLabelMedium",
        ]];
    });
    if (!ame341_shapeOverride) ame341_shapeOverride = [NSMutableDictionary dictionary];
    if (!ame341_fontOverride)  ame341_fontOverride  = [NSMutableDictionary dictionary];
    // 先清本插件既有覆盖（还原语义，两表同清），再落新集合（后写者胜）
    NSMutableArray *stale = [NSMutableArray array];
    [ame341_shapeOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *e, BOOL *_) {
        if ([e[0] isEqualToString:pluginId]) [stale addObject:k];
    }];
    [ame341_fontOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *e, BOOL *_) {
        if ([e[0] isEqualToString:pluginId]) [stale addObject:k];
    }];
    for (NSString *k in stale) {
        [ame341_shapeOverride removeObjectForKey:k];
        [ame341_fontOverride removeObjectForKey:k];
    }
    if (![tokens isKindOfClass:[NSDictionary class]] || tokens.count == 0) {
        ame346_requestRootRebuild();   // ★ Task346：还原语义同样即时生效
        return YES;
    }
    NSUInteger applied = 0;
    for (NSString *k in tokens) {
        id v = tokens[k];
        if ([shapeKeys containsObject:k] && [v isKindOfClass:[NSNumber class]]) {
            // pt 钳制 0...40（M3 最大 28、Fluent 2 最大 12，40 已留足插件自定余地）
            double r = [(NSNumber *)v doubleValue];
            if (r < 0 || r > 40 || isnan(r)) continue;
            ame341_shapeOverride[k] = @[pluginId, @(r)];
            applied++;
        } else if ([fontKeys containsObject:k] && [v isKindOfClass:[NSDictionary class]]) {
            NSDictionary *fs = (NSDictionary *)v;
            double size = [fs[@"size"] isKindOfClass:[NSNumber class]]
                          ? [(NSNumber *)fs[@"size"] doubleValue] : -1;
            if (size < 8 || size > 40 || isnan(size)) continue;
            UIFont *font = [UIFont systemFontOfSize:size
                                             weight:Ame341WeightFromValue(fs[@"weight"])];
            ame341_fontOverride[k] = @[pluginId, font];
            applied++;
        }
    }
    NSLog(@"[AmePlugin:%@] 形状/字体令牌覆盖 %lu/%lu 项", pluginId,
          (unsigned long)applied, (unsigned long)tokens.count);
    ame346_requestRootRebuild();   // ★ Task346：覆盖落表即全界面重建
    return YES;
}

+ (CGFloat)ame343_layoutMetric:(NSString *)token fallback:(CGFloat)fallback {
    return Ame343LayoutOverride(token, fallback);
}

+ (BOOL)ame343_setPluginThemeLayout:(NSString *)pluginId
                             tokens:(NSDictionary *)tokens {
    if (pluginId.length == 0) return NO;
    // 白名单 + 钳制区间（键名中性 spacing/density 语义，守 Task340
    // "引擎零 Fluent 资产"裁定：引擎只提供承载面，形态全部住在插件侧）
    static NSDictionary<NSString *, NSArray<NSNumber *> *> *layoutKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        layoutKeys = @{
            @"searchBarHeight": @[@32, @64],
            @"chipHeight":      @[@24, @48],
            @"cardMarginV":     @[@0,  @24],
            @"cardMarginH":     @[@0,  @40],
            @"cardInsetX":      @[@0,  @40],
            @"cardInsetTop":    @[@0,  @40],
            @"cardInsetBottom": @[@0,  @40],
            @"cardContentGap":  @[@0,  @24],
            @"pillMinWidth":    @[@32, @160],
            @"pillHeight":      @[@20, @56],
            @"pillGap":         @[@0,  @32],
            @"dialogInset":     @[@8,  @48],
            @"buttonHeight":    @[@28, @64],
        };
    });
    if (!ame343_layoutOverride) ame343_layoutOverride = [NSMutableDictionary dictionary];
    // 先清本插件既有覆盖（还原语义），再落新集合（后写者胜）
    NSMutableArray *stale = [NSMutableArray array];
    [ame343_layoutOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *e, BOOL *_) {
        if ([e[0] isEqualToString:pluginId]) [stale addObject:k];
    }];
    for (NSString *k in stale) [ame343_layoutOverride removeObjectForKey:k];
    if (![tokens isKindOfClass:[NSDictionary class]] || tokens.count == 0) {
        ame346_requestRootRebuild();   // ★ Task346：还原语义同样即时生效
        return YES;
    }
    NSUInteger applied = 0;
    for (NSString *k in tokens) {
        id v = tokens[k];
        if (![v isKindOfClass:[NSNumber class]]) continue;
        NSArray<NSNumber *> *range = layoutKeys[k];
        if (range.count != 2) continue;
        double p = [(NSNumber *)v doubleValue];
        if (isnan(p) || p < [range[0] doubleValue] || p > [range[1] doubleValue]) continue;
        ame343_layoutOverride[k] = @[pluginId, @(p)];
        applied++;
    }
    NSLog(@"[AmePlugin:%@] 布局令牌覆盖 %lu/%lu 项", pluginId,
          (unsigned long)applied, (unsigned long)tokens.count);
    ame346_requestRootRebuild();   // ★ Task346：覆盖落表即全界面重建
    return YES;
}

// ★ Task347：结构令牌 setter（白名单 = shellLayout 二值蓝图；同族记账
//   还原语义 + Task346 根重建杠杆——结构换蓝图必须整壳重建才有意义，
//   应用/还原双路径都即时生效）。
+ (BOOL)ame347_setPluginThemeStructure:(NSString *)pluginId
                                tokens:(NSDictionary *)tokens {
    if (pluginId.length == 0) return NO;
    // 白名单 + 值域（中性结构语义：壳层导航骨架蓝图选择；守 Task340
    // "引擎零 Fluent 资产"裁定——引擎只提供两种骨架承载面，形态语义
    // 全部住在插件侧）。
    static NSSet<NSString *> *structureKeys = nil;
    static NSDictionary<NSString *, NSSet<NSString *> *> *structureValues = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        structureKeys = [NSSet setWithArray:@[ @"shellLayout" ]];
        structureValues = @{
            @"shellLayout": [NSSet setWithArray:@[ @"topbar", @"navigationview" ]],
        };
    });
    if (!ame347_structureOverride) ame347_structureOverride = [NSMutableDictionary dictionary];
    // 先清本插件既有覆盖（还原语义），再落新集合（后写者胜）
    NSMutableArray *stale = [NSMutableArray array];
    [ame347_structureOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *e, BOOL *_) {
        if ([e[0] isEqualToString:pluginId]) [stale addObject:k];
    }];
    for (NSString *k in stale) [ame347_structureOverride removeObjectForKey:k];
    if (![tokens isKindOfClass:[NSDictionary class]] || tokens.count == 0) {
        ame346_requestRootRebuild();   // ★ Task346：还原语义同样即时生效
        return YES;
    }
    NSUInteger applied = 0;
    for (NSString *k in tokens) {
        id v = tokens[k];
        if (![structureKeys containsObject:k]) continue;
        if (![v isKindOfClass:[NSString class]]) continue;
        NSSet *allowed = structureValues[k];
        if (![allowed containsObject:v]) continue;
        ame347_structureOverride[k] = @[pluginId, v];
        applied++;
    }
    NSLog(@"[AmePlugin:%@] 结构令牌覆盖 %lu/%lu 项（shellLayout=%@）", pluginId,
          (unsigned long)applied, (unsigned long)tokens.count,
          Ame347StructureOverride(@"shellLayout", @"navigationview"));
    ame346_requestRootRebuild();   // ★ Task346：结构落表即整壳重建
    return YES;
}

+ (NSString *)ame347_shellLayout {
    // ★ Task456：骨架默认蓝图 topbar → navigationview（用户复诉「小屏幕设备
    //   怎么不是 zl2 的侧边栏」：ZL2 左窗格侧栏此前只在 fluent-ui 插件覆盖
    //   shellLayout=navigationview 时存在——小屏设备插件关/未覆盖即整壳落
    //   bare 骨架（无左栏），侧栏 = 插件奢侈品而非应用自有形态）。默认改
    //   navigationview 后：插件开 = 全维度换装（语义不变），插件关 = ZL2 侧
    //   栏裸形态（默认令牌，Task450⑥ 小屏简侧栏语义不变）；bare 骨架保留
    //   编译（结构令牌 topbar 仍可经插件覆盖进入）。
    return Ame347StructureOverride(@"shellLayout", @"navigationview");
}

+ (BOOL)ame347_shellLayoutPluginOverridden {
    // ★ Task458：覆盖在位判定（契约见 ZL2Theme.h 同名注释）。与
    // Ame347StructureOverride 同一判据形态（entry.count == 2）= nil 表/缺键/
    // 畸形条目三态全落 NO（默认 MD3 族），零新增失效面。
    NSArray *ame458_entry = ame347_structureOverride[@"shellLayout"];
    return ame458_entry.count == 2;
}

#pragma mark - ★Task429 活动色板覆盖层（8.1 动态主题中枢对接点）

+ (void)ame429_setActivePaletteOverlay:(NSDictionary<NSString *, NSArray<NSNumber *> *> *)overlay {
    // 整表原子换（immutable 指针替换，读侧 Ame429OverlayHex 无锁）；
    // nil/空 = 清除（未初始化/模式 0 逐位等价旧值 = 零回归）。
    if (![overlay isKindOfClass:[NSDictionary class]] || overlay.count == 0) {
        ame429_activePaletteOverlay = nil;
        NSLog(@"[ZL2Theme] Task429: active palette overlay cleared (embermire fallback)");
        return;
    }
    ame429_activePaletteOverlay = [overlay copy];
    NSLog(@"[ZL2Theme] Task429: active palette overlay applied (%lu tokens)",
          (unsigned long)overlay.count);
}

+ (void)ame429_requestRootRebuild {
    // Task346 根重建杠杆公开包装（ame346 冷却/尾沿补排/启动期守卫全在位）；
    // ZL2DynamicPalette 生效链复用，不发明第二套广播。
    ame346_requestRootRebuild();
}

// ★ Task455：启动期令牌突发合并——首帧落地锚点消费（类方法体，静态状态
//   ame455_startupLanded/ame455_startupRebuildDirty 见 ame346 块邻位判例）。
+ (BOOL)ame455_consumeStartupRebuild {
    if (ame455_startupLanded) return NO;
    ame455_startupLanded = YES;
    if (!ame455_startupRebuildDirty) return NO;
    ame455_startupRebuildDirty = NO;
    NSLog(@"[ZL2Theme] Task455: startup token burst coalesced -> trailing rebuild flush");
    return YES;
}

+ (void)ame429_setPaletteBootstrapHook:(void (*)(void))hook {
    // C 函数指针直存（注册面 = ZL2DynamicPalette +load 传入全局静态
    // trampoline，无上下文捕获；hook == NULL = 摘除，预览/冒烟目标默认态）
    ame429_paletteBootstrapHook = hook;
}

#pragma mark - 主色系

+ (UIColor *)primary {
    // embermire：浅 = 锈橙 0xA63A17；深 = 桃色 0xFFB59F（截图"启动游戏"钮）
    return AME317_PLUGIN_COLOR(primary, 0xA63A17, 0xFFB59F);
}
+ (UIColor *)onPrimary {
    return AME317_PLUGIN_COLOR(onPrimary, 0xFFFFFF, 0x5F1600);
}
+ (UIColor *)primaryContainer {
    return AME317_PLUGIN_COLOR(primaryContainer, 0xFE7A52, 0xC4502B);
}
+ (UIColor *)onPrimaryContainer {
    return AME317_PLUGIN_COLOR(onPrimaryContainer, 0x2F0700, 0xFFFFFF);
}

#pragma mark - 次色系

+ (UIColor *)secondary {
    return AME317_PLUGIN_COLOR(secondary, 0x894F3D, 0xFFB59F);
}
+ (UIColor *)onSecondary {
    return AME317_PLUGIN_COLOR(onSecondary, 0xFFFFFF, 0x512214);
}
+ (UIColor *)secondaryContainer {
    // 深 = 0x643122（截图顶栏"下载"选中 pill 底）
    return AME317_PLUGIN_COLOR(secondaryContainer, 0xFFBBA7, 0x643122);
}
+ (UIColor *)onSecondaryContainer {
    return AME317_PLUGIN_COLOR(onSecondaryContainer, 0x5C2B1C, 0xFFC8B9);
}

#pragma mark - 三色系

+ (UIColor *)tertiary {
    // 深 = 0xF0D44C（截图版本类型 chip 橄榄黄字色，LittleTextLabel tertiary 档）
    return AME317_PLUGIN_COLOR(tertiary, 0x6E5E00, 0xF0D44C);
}
+ (UIColor *)onTertiary {
    return AME317_PLUGIN_COLOR(onTertiary, 0xFFFFFF, 0x393000);
}
+ (UIColor *)tertiaryContainer {
    return AME317_PLUGIN_COLOR(tertiaryContainer, 0xBAA015, 0xC4AA22);
}
+ (UIColor *)onTertiaryContainer {
    return AME317_PLUGIN_COLOR(onTertiaryContainer, 0x1A1500, 0x272000);
}

#pragma mark - 表面系

+ (UIColor *)surface {
    // 深 = 0x1C110E（截图页面底暖深棕）
    return AME317_PLUGIN_COLOR(surface, 0xFFF8F6, 0x1C110E);
}
+ (UIColor *)onSurface {
    return AME317_PLUGIN_COLOR(onSurface, 0x241916, 0xF4DED8);
}
+ (UIColor *)onSurfaceVariant {
    return AME317_PLUGIN_COLOR(onSurfaceVariant, 0x58423B, 0xDFC0B7);
}
+ (UIColor *)surfaceVariant {
    return AME317_PLUGIN_COLOR(surfaceVariant, 0xFCDBD3, 0x58423B);
}
+ (UIColor *)surfaceContainerLowest {
    return AME317_PLUGIN_COLOR(surfaceContainerLowest, 0xFFFFFF, 0x160C09);
}
+ (UIColor *)surfaceContainerLow {
    return AME317_PLUGIN_COLOR(surfaceContainerLow, 0xFFF1ED, 0x241916);
}
+ (UIColor *)surfaceContainer {
    return AME317_PLUGIN_COLOR(surfaceContainer, 0xFFE9E4, 0x291D19);
}
+ (UIColor *)surfaceContainerHigh {
    return AME317_PLUGIN_COLOR(surfaceContainerHigh, 0xFAE3DD, 0x342723);
}
+ (UIColor *)surfaceContainerHighest {
    return AME317_PLUGIN_COLOR(surfaceContainerHighest, 0xF4DED8, 0x3B2C27);
}
+ (UIColor *)surfaceBright {
    // ZL2 cardColor() 真实卡底：深 = 0x443632（截图文件/版本卡底色）
    return AME317_PLUGIN_COLOR(surfaceBright, 0xFFF8F6, 0x443632);
}

#pragma mark - 描边系

+ (UIColor *)outline {
    return AME317_PLUGIN_COLOR(outline, 0x8B716A, 0xA68B83);
}
+ (UIColor *)outlineVariant {
    return AME317_PLUGIN_COLOR(outlineVariant, 0xDFC0B7, 0x58423B);
}

#pragma mark - 状态系

+ (UIColor *)error {
    return AME317_PLUGIN_COLOR(error, 0xBA1A1A, 0xFFB4AB);
}
+ (UIColor *)errorContainer {
    return AME317_PLUGIN_COLOR(errorContainer, 0xFFDAD6, 0x93000A);
}
+ (UIColor *)success {
    // M3 无标准 success：embermire 无绿档，取 M3 官方 baseline 绿（历史判例沿用）
    return AME317_PLUGIN_COLOR(success, 0x146C2E, 0x6DD58C);
}
+ (UIColor *)warning {
    // 橙档判例沿用（embermire primaryContainer 案）
    return AME317_PLUGIN_COLOR(warning, 0x8F4C38, 0xFFB693);
}

#pragma mark - 形状阶

// ★ Task341：五档圆角经 AmePluginShapeOverride 先行检查插件覆盖
//   （默认值 M3 刻度不变；覆盖全页面生效——ZL2 页面 71 处圆角全部经本组 getter）
+ (CGFloat)radiusXS { return AmePluginShapeOverride(@"radiusXS", 4.0); }
+ (CGFloat)radiusS  { return AmePluginShapeOverride(@"radiusS", 8.0); }
+ (CGFloat)radiusM  { return AmePluginShapeOverride(@"radiusM", 12.0); }
+ (CGFloat)radiusL  { return AmePluginShapeOverride(@"radiusL", 16.0); }
+ (CGFloat)radiusXL { return AmePluginShapeOverride(@"radiusXL", 28.0); }

#pragma mark - 字体阶

// ★ Task341：七档字体经 AmePluginFontOverride 先行检查插件覆盖
//   （默认值 M3 刻度不变；ZL2 页面 144 处字体全部经本组 getter）
+ (UIFont *)fontHeadline {
    return AmePluginFontOverride(@"fontHeadline",
                                 [UIFont systemFontOfSize:28.0 weight:UIFontWeightSemibold]);
}
+ (UIFont *)fontTitleLarge {
    return AmePluginFontOverride(@"fontTitleLarge",
                                 [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular]);
}
+ (UIFont *)fontTitleMedium {
    return AmePluginFontOverride(@"fontTitleMedium",
                                 [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium]);
}
+ (UIFont *)fontBodyLarge {
    return AmePluginFontOverride(@"fontBodyLarge",
                                 [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular]);
}
+ (UIFont *)fontBodyMedium {
    return AmePluginFontOverride(@"fontBodyMedium",
                                 [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular]);
}
+ (UIFont *)fontLabelLarge {
    return AmePluginFontOverride(@"fontLabelLarge",
                                 [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium]);
}
+ (UIFont *)fontLabelMedium {
    return AmePluginFontOverride(@"fontLabelMedium",
                                 [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]);
}

#pragma mark - 语义

+ (UIColor *)launchReadyTint    { return [self primary]; }
+ (UIColor *)launchDisabledTint { return [self outlineVariant]; }

@end
