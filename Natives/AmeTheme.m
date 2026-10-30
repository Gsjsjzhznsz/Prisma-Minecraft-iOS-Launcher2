//
// AmeTheme.m
// Prisma-Minecraft-iOS-Launcher2 — 设计令牌层实现（v3 · M3 承载层）
//
// ★ Task354（MD3 设计语言统一，用户指令"全面修改为 md3 样式，避免 ui 设计
//   语言混杂"）：v2 的 Fluent 2 官方取值（fluent2_kit）整体退役，全部 getter
//   重指向 ZL2Theme（Material 3 embermire 令牌层）的对应角色——API 与 v1/v2
//   完全兼容，既有消费面（FluentToast/FluentButton/FluentListCell/欢迎页/
//   管理页/崩溃视图/游戏内浮层等 20+ 文件）零改动即整面切换 M3 视觉。
//
//   语义映射（Fluent → M3）：
//     brandPrimary→primary          textPrimary→onSurface
//     brandTinted→secondaryContainer  textSecondary→onSurfaceVariant
//     textOnBrand→onPrimary           textTertiary→outline
//     bgPrimary→surface             fillSubtle→surfaceContainerHighest
//     bgSecondary→surfaceContainerLow fillStrong→surfaceVariant
//     surfaceCard→surfaceBright（ZL2 cardColor() 同源） divider→outlineVariant
//     surfaceOverlay→surfaceContainerHigh
//     statusDanger→error  statusSuccess→success  statusWarning→warning
//   字阶（M3 刻度）：
//     fontCaption→labelMedium(12)  fontBody2→bodyMedium(14)  fontBody→bodyLarge(16)
//     fontButton→labelLarge(14 medium)  fontSubtitle→titleLarge(22)
//     fontTitle2→titleLarge(22)  fontTitle→headline(28 semibold)
//   形状（M3 圆角阶）：
//     radiusS→4  radiusM→8  radiusL→12  radiusXL→16  radiusGlass→28
//
// 旧 Fluent 取值档案：git 历史 v2（7.0-UI-4 起至 Task353 止）。
//

#import "AmeTheme.h"
#import "ZL2Theme.h"

@implementation AmeTheme

#pragma mark - Brand（→ M3 primary 系）

+ (UIColor *)brandPrimary { return [ZL2Theme primary]; }

+ (UIColor *)brandTinted {
    // 选中态淡底 → M3 secondaryContainer（实色阶，替代 v2 alpha 淡底）
    return [ZL2Theme secondaryContainer];
}

+ (UIColor *)textOnBrand { return [ZL2Theme onPrimary]; }

#pragma mark - Background & Surface（→ M3 surface 容器阶）

+ (UIColor *)bgPrimary      { return [ZL2Theme surface]; }              // 页面画布
+ (UIColor *)bgSecondary    { return [ZL2Theme surfaceContainerLow]; }  // 次级/内嵌
+ (UIColor *)surfaceCard    { return [ZL2Theme surfaceBright]; }        // 卡面（ZL2 cardColor() 同源）
+ (UIColor *)surfaceOverlay { return [ZL2Theme surfaceContainerHigh]; } // 浮层

#pragma mark - Text（→ M3 onSurface 系）

+ (UIColor *)textPrimary   { return [ZL2Theme onSurface]; }        // 一级
+ (UIColor *)textSecondary { return [ZL2Theme onSurfaceVariant]; } // 二级
+ (UIColor *)textTertiary  { return [ZL2Theme outline]; }          // 三级

#pragma mark - Fill & Divider（→ M3 surfaceVariant 系）

+ (UIColor *)fillSubtle { return [ZL2Theme surfaceContainerHighest]; }
+ (UIColor *)fillStrong { return [ZL2Theme surfaceVariant]; }
+ (UIColor *)divider    { return [ZL2Theme outlineVariant]; }

#pragma mark - Status（→ M3 状态色）

+ (UIColor *)statusDanger  { return [ZL2Theme error]; }
+ (UIColor *)statusSuccess { return [ZL2Theme success]; }
+ (UIColor *)statusWarning { return [ZL2Theme warning]; }

#pragma mark - Typography（→ M3 字阶）

+ (UIFont *)fontCaption  { return [ZL2Theme fontLabelMedium]; } // 12 medium
+ (UIFont *)fontBody2    { return [ZL2Theme fontBodyMedium]; }  // 14
+ (UIFont *)fontBody     { return [ZL2Theme fontBodyLarge]; }   // 16
+ (UIFont *)fontButton   { return [ZL2Theme fontLabelLarge]; }  // 14 medium（M3 按钮刻度）
+ (UIFont *)fontSubtitle { return [ZL2Theme fontTitleLarge]; }  // 22
+ (UIFont *)fontTitle2   { return [ZL2Theme fontTitleLarge]; }  // 22
+ (UIFont *)fontTitle    { return [ZL2Theme fontHeadline]; }    // 28 semibold

#pragma mark - Metrics（→ M3 圆角阶）

+ (CGFloat)radiusS  { return [ZL2Theme radiusXS]; }  // 4
+ (CGFloat)radiusM  { return [ZL2Theme radiusS]; }   // 8
+ (CGFloat)radiusL  { return [ZL2Theme radiusM]; }   // 12
+ (CGFloat)radiusXL { return [ZL2Theme radiusL]; }   // 16
+ (CGFloat)radiusGlass { return [ZL2Theme radiusXL]; } ///< 28（浮层/玻璃面板；连续曲线由调用方 cornerCurve 承担）

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
