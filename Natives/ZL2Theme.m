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

static UIColor *ZL2ColorLightDark(int light, int dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *traits) {
        int value = (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                               green:((value >> 8) & 0xFF) / 255.0
                                blue:(value & 0xFF) / 255.0
                               alpha:1.0];
    }];
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

// 宏：getter 一行式覆盖检查（GNU 语句表达式，clang 默认支持）
#define AME317_PLUGIN_COLOR(token, light, dark) \
    ({ UIColor *ame317_ov = AmePluginColorOverride(@#token); \
       ame317_ov ? ame317_ov : ZL2ColorLightDark(light, dark); })

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
static void ame346_requestRootRebuild(void) {
    if (ame346_rebuildScheduled) return;   // 同拍连发合并（连点循环去抖）
    ame346_rebuildScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        ame346_rebuildScheduled = NO;
        @try {
            UIViewController *ame346_root = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *ame346_scene in UIApplication.sharedApplication.connectedScenes) {
                    if (![ame346_scene isKindOfClass:[UIWindowScene class]]) continue;
                    for (UIWindow *ame346_w in ((UIWindowScene *)ame346_scene).windows) {
                        if (ame346_w.isKeyWindow) {
                            ame346_root = ame346_w.rootViewController;
                            break;
                        }
                    }
                    if (ame346_root) break;
                }
            }
            if (!ame346_root) return;   // 启动期根未建：重放路径无需重建
            [[NSNotificationCenter defaultCenter] postNotificationName:@"AppLanguageChanged" object:nil];
            NSLog(@"[ZL2Theme] Task346: token change -> root rebuild posted (AppLanguageChanged lever)");
        } @catch (NSException *ame346_e) {
            NSLog(@"[ZL2Theme] Task346: root rebuild dispatch exception (%@)", ame346_e);
        }
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
          Ame347StructureOverride(@"shellLayout", @"topbar"));
    ame346_requestRootRebuild();   // ★ Task346：结构落表即整壳重建
    return YES;
}

+ (NSString *)ame347_shellLayout {
    return Ame347StructureOverride(@"shellLayout", @"topbar");
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
