//
// AmeTheme.m
// Prisma-Minecraft-iOS-Launcher2 — Fluent 2 令牌层实现（v2 · fluent2_kit 官方取值）
//
// 取值溯源：graundtech/fluent2_kit（MIT）lib/src/fluent_models/fluent_colors.dart
// / fluent_corner_radius.dart + lib/theme_data.dart（_brandColor ramp 与
// MixedFluentTextTheme iOS 分支）。API 与 v1 完全兼容，已迁文件零改动。
//

#import "AmeTheme.h"

// 动态色构造助手：light/dark 双值一次成型
static UIColor *AmeDynamic(uint32_t light, uint32_t dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        uint32_t hex = (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:1.0];
    }];
}

@implementation AmeTheme

#pragma mark - Brand

+ (UIColor *)brandPrimary { return AmeDynamic(0x0F6CBD, 0x2A93EE); }

+ (UIColor *)brandTinted {
    // brandBackgroundTint 对偶：主色低 alpha 淡底
    return [[AmeTheme brandPrimary] colorWithAlphaComponent:0.12];
}

+ (UIColor *)textOnBrand { return [UIColor whiteColor]; }

#pragma mark - Background & Surface

+ (UIColor *)bgPrimary      { return AmeDynamic(0xF5F5F5, 0x141414); } // canvas
+ (UIColor *)bgSecondary    { return AmeDynamic(0xFFFFFF, 0x1F1F1F); } // bg2
+ (UIColor *)surfaceCard    { return AmeDynamic(0xFFFFFF, 0x292929); } // bg3
+ (UIColor *)surfaceOverlay { return AmeDynamic(0xFAFAFA, 0x333333); } // bg4

#pragma mark - Text

+ (UIColor *)textPrimary   { return AmeDynamic(0x242424, 0xFFFFFF); } // fg1
+ (UIColor *)textSecondary { return AmeDynamic(0x616161, 0xD6D6D6); } // fg2
+ (UIColor *)textTertiary  { return AmeDynamic(0x808080, 0xADADAD); } // fg3

#pragma mark - Fill & Divider

+ (UIColor *)fillSubtle { return AmeDynamic(0xF0F0F0, 0x3D3D3D); } // bg5
+ (UIColor *)fillStrong { return AmeDynamic(0xD1D1D1, 0x5C5C5C); } // bg6
+ (UIColor *)divider    { return AmeDynamic(0xD1D1D1, 0x4D4D4D); } // stroke1

#pragma mark - Status

+ (UIColor *)statusDanger  { return AmeDynamic(0xC50F1F, 0xDC626D); }
+ (UIColor *)statusSuccess { return AmeDynamic(0x107C10, 0x54B054); }
+ (UIColor *)statusWarning { return AmeDynamic(0xBC4B09, 0xFAA06B); }

#pragma mark - Typography（SF Pro · MixedFluentTextTheme）

+ (UIFont *)fontCaption  { return [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontBody2    { return [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontBody     { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontButton   { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontSubtitle { return [UIFont systemFontOfSize:20.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontTitle2   { return [UIFont systemFontOfSize:22.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontTitle    { return [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold]; }

#pragma mark - Metrics

+ (CGFloat)radiusS  { return 2.0; }
+ (CGFloat)radiusM  { return 4.0; }
+ (CGFloat)radiusL  { return 8.0; }
+ (CGFloat)radiusXL { return 12.0; }
+ (CGFloat)radiusGlass { return 24.0; }  ///< Task316：玻璃面板专用（连续曲线由调用方 cornerCurve 承担）

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

    UITabBar *tabProxy = [UITabBar appearance];
    tabProxy.barTintColor = [AmeTheme bgSecondary];
    tabProxy.tintColor = [AmeTheme brandPrimary];
    tabProxy.unselectedItemTintColor = [AmeTheme textSecondary];

    UITableView *tableProxy = [UITableView appearance];
    tableProxy.backgroundColor = [AmeTheme bgPrimary];
    tableProxy.separatorColor = [AmeTheme divider];

    [UISwitch appearance].onTintColor = [AmeTheme brandPrimary];
    [UISlider appearance].tintColor = [AmeTheme brandPrimary];
    [UIPageControl appearance].currentPageIndicatorTintColor = [AmeTheme brandPrimary];
    [UIPageControl appearance].pageIndicatorTintColor = [AmeTheme fillStrong];
    [UIProgressView appearance].progressTintColor = [AmeTheme brandPrimary];
    [UIProgressView appearance].trackTintColor = [AmeTheme fillSubtle];

    [UIWindow appearance].tintColor = [AmeTheme brandPrimary];
}

@end
