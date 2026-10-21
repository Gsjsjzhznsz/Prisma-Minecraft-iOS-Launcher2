//
// AmeTheme.m
// Prisma-Minecraft-iOS-Launcher2 — 7.0 Fluent 风格设计令牌层实现
//
// 7.0-UI-2: 动态色基于 +colorWithDynamicProvider:（iOS 13+，部署目标 14.0 安全）。
// 取值遵循 Fluent 2 公开设计规范（fluent2.microsoft.design），中性阶参考
// Windows 11 桌面/移动 token，并按 iOS 原生观感微调。
//

#import "AmeTheme.h"

// 动态色构造助手：light/dark 双值一次成型
static UIColor *AmeDynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
    }];
}

// hex 助手（0xRRGGBB）
static UIColor *AmeHex(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation AmeTheme

#pragma mark - Brand

+ (UIColor *)brandPrimary {
    // Fluent 2 brand：Light #0F6CBD（shade 10）/ Dark #479EF5（tint 100）
    return AmeDynamic(AmeHex(0x0F6CBD), AmeHex(0x479EF5));
}

+ (UIColor *)brandTinted {
    return AmeDynamic(([AmeHex(0x0F6CBD) colorWithAlphaComponent:0.10]),
                      ([AmeHex(0x479EF5) colorWithAlphaComponent:0.18]));
}

+ (UIColor *)textOnBrand {
    return [UIColor whiteColor];
}

#pragma mark - Background & Surface

+ (UIColor *)bgPrimary {
    // 页面大底：Light #F6F6F8 中性 / Dark #1B1B1D（Fluent 深底近黑）
    return AmeDynamic(AmeHex(0xF6F6F8), AmeHex(0x1B1B1D));
}

+ (UIColor *)bgSecondary {
    // 内嵌/侧栏：Light #FFFFFF / Dark #262629
    return AmeDynamic(AmeHex(0xFFFFFF), AmeHex(0x262629));
}

+ (UIColor *)surfaceCard {
    // 卡片表面：Light #FFFFFF / Dark #2C2C2F
    return AmeDynamic(AmeHex(0xFFFFFF), AmeHex(0x2C2C2F));
}

+ (UIColor *)surfaceOverlay {
    // 浮层：Light #FFFFFF / Dark #333338（比卡片再浮一档）
    return AmeDynamic(AmeHex(0xFFFFFF), AmeHex(0x333338));
}

#pragma mark - Text

+ (UIColor *)textPrimary {
    // Fluent text 900：Light #242424 / Dark #FFFFFF
    return AmeDynamic(AmeHex(0x242424), AmeHex(0xFFFFFF));
}

+ (UIColor *)textSecondary {
    // Fluent text 600：Light #616161 / Dark #D4D4D4
    return AmeDynamic(AmeHex(0x616161), AmeHex(0xD4D4D4));
}

+ (UIColor *)textTertiary {
    // Light #979797 / Dark #988F8F 附近（占位/禁用级）
    return AmeDynamic(AmeHex(0x979797), AmeHex(0x9B9B9B));
}

#pragma mark - Fill & Divider

+ (UIColor *)fillSubtle {
    return AmeDynamic(([UIColor blackColor] colorWithAlphaComponent:0.05),
                      ([UIColor whiteColor] colorWithAlphaComponent:0.07));
}

+ (UIColor *)fillStrong {
    return AmeDynamic(([UIColor blackColor] colorWithAlphaComponent:0.10),
                      ([UIColor whiteColor] colorWithAlphaComponent:0.14));
}

+ (UIColor *)divider {
    return AmeDynamic(([UIColor blackColor] colorWithAlphaComponent:0.09),
                      ([UIColor whiteColor] colorWithAlphaComponent:0.11));
}

#pragma mark - Status

+ (UIColor *)statusDanger {
    return AmeDynamic(AmeHex(0xD13438), AmeHex(0xFF6B6B));
}

+ (UIColor *)statusSuccess {
    return AmeDynamic(AmeHex(0x0E700E), AmeHex(0x6CCB5F));
}

+ (UIColor *)statusWarning {
    return AmeDynamic(AmeHex(0xC75B0B), AmeHex(0xFDB240));
}

#pragma mark - Typography

+ (UIFont *)fontTitle    { return [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold]; }
+ (UIFont *)fontSubtitle { return [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontBody     { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontCaption  { return [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontButton   { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]; }

#pragma mark - Metrics

+ (CGFloat)radiusS { return 4.0; }
+ (CGFloat)radiusM { return 8.0; }
+ (CGFloat)radiusL { return 12.0; }

#pragma mark - Environment

+ (BOOL)isDarkMode {
    UITraitCollection *t = [UITraitCollection currentTraitCollection];
    if (t.userInterfaceStyle != UIUserInterfaceStyleUnspecified) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return [[[UIApplication sharedApplication] keyWindow] traitCollection]
        .userInterfaceStyle == UIUserInterfaceStyleDark;
}

#pragma mark - Global Appearance

+ (void)applyGlobalAppearance {
    // —— 导航栏：令牌注入（保守策略：不动 translucent，避免布局回归）——
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithDefaultBackground];
    nav.backgroundColor = [AmeTheme bgSecondary];
    nav.titleTextAttributes = @{
        NSForegroundColorAttributeName: [AmeTheme textPrimary],
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold],
    };
    UINavigationBar *navProxy = [UINavigationBar appearance];
    [navProxy setStandardAppearance:nav];
    [navProxy setScrollEdgeAppearance:nav];
    [navProxy setTintColor:[AmeTheme brandPrimary]];

    // —— 标签栏 ——
    UITabBar *tabProxy = [UITabBar appearance];
    tabProxy.barTintColor = [AmeTheme bgSecondary];
    tabProxy.tintColor = [AmeTheme brandPrimary];
    tabProxy.unselectedItemTintColor = [AmeTheme textSecondary];

    // —— 表视图 ——
    UITableView *tableProxy = [UITableView appearance];
    tableProxy.backgroundColor = [AmeTheme bgPrimary];
    tableProxy.separatorColor = [AmeTheme divider];

    // —— 控件 ——
    [UISwitch appearance].onTintColor = [AmeTheme brandPrimary];
    [UISlider appearance].tintColor = [AmeTheme brandPrimary];
    [UIPageControl appearance].currentPageIndicatorTintColor = [AmeTheme brandPrimary];
    [UIPageControl appearance].pageIndicatorTintColor = [AmeTheme fillStrong];
    [UIProgressView appearance].progressTintColor = [AmeTheme brandPrimary];
    [UIProgressView appearance].trackTintColor = [AmeTheme fillSubtle];

    // —— 窗口 tint ——
    [UIWindow appearance].tintColor = [AmeTheme brandPrimary];
}

@end
