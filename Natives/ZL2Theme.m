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
    return YES;
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

+ (CGFloat)radiusXS { return 4.0; }
+ (CGFloat)radiusS  { return 8.0; }
+ (CGFloat)radiusM  { return 12.0; }
+ (CGFloat)radiusL  { return 16.0; }
+ (CGFloat)radiusXL { return 28.0; }

#pragma mark - 字体阶

+ (UIFont *)fontHeadline    { return [UIFont systemFontOfSize:28.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontTitleLarge  { return [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontTitleMedium { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium]; }
+ (UIFont *)fontBodyLarge   { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontBodyMedium  { return [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontLabelLarge  { return [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium]; }
+ (UIFont *)fontLabelMedium { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]; }

#pragma mark - 语义

+ (UIColor *)launchReadyTint    { return [self primary]; }
+ (UIColor *)launchDisabledTint { return [self outlineVariant]; }

@end
