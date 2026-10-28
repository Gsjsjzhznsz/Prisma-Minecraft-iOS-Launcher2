//
//  AMEFluentTheme.m — Fluent 2 / Apple 设计令牌系统实现
//  逐值溯源 microsoft/fluentui-apple（Fluent 2 / Apple 官方实现）；详见头文件。
//  动态色全部 colorWithDynamicProvider（ZL2Home 判例：零 traitCollection 分支）。
//

#import "AMEFluentTheme.h"

@implementation AMEFluentTheme

// ── 动态色便捷构造 ─────────────────────────────────────────
static UIColor *AMEFluentDynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
    }];
}

// ── Brand ──────────────────────────────────────────────────
+ (UIColor *)brand {
    return AMEFluentDynamic([UIColor colorWithRed:0x0F/255.0 green:0x6C/255.0 blue:0xBD/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x4C/255.0 green:0xC2/255.0 blue:0xFF/255.0 alpha:1.0]);
}
+ (UIColor *)brandShade {
    return AMEFluentDynamic([UIColor colorWithRed:0x11/255.0 green:0x5E/255.0 blue:0xA3/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x28/255.0 green:0x86/255.0 blue:0xDE/255.0 alpha:1.0]);
}
+ (UIColor *)brandContainer {
    return AMEFluentDynamic([UIColor colorWithRed:0xC7/255.0 green:0xE0/255.0 blue:0xF4/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x00/255.0 green:0x22/255.0 blue:0x44/255.0 alpha:1.0]);
}
+ (UIColor *)onBrand {
    return AMEFluentDynamic([UIColor whiteColor],
                            [UIColor colorWithRed:0x00/255.0 green:0x00/255.0 blue:0x00/255.0 alpha:1.0]);
}

// ── Neutral / Alias ────────────────────────────────────────
+ (UIColor *)fg1 {
    return AMEFluentDynamic([UIColor colorWithRed:0x24/255.0 green:0x24/255.0 blue:0x24/255.0 alpha:1.0],
                            [UIColor whiteColor]);
}
+ (UIColor *)fg2 {
    return AMEFluentDynamic([UIColor colorWithRed:0x42/255.0 green:0x42/255.0 blue:0x42/255.0 alpha:1.0],
                            [UIColor colorWithRed:0xD6/255.0 green:0xD6/255.0 blue:0xD6/255.0 alpha:1.0]);
}
+ (UIColor *)fg3 {
    return AMEFluentDynamic([UIColor colorWithRed:0x61/255.0 green:0x61/255.0 blue:0x61/255.0 alpha:1.0],
                            [UIColor colorWithRed:0xA0/255.0 green:0xA0/255.0 blue:0xA0/255.0 alpha:1.0]);
}
+ (UIColor *)bg1 {
    return AMEFluentDynamic([UIColor whiteColor],
                            [UIColor colorWithRed:0x00/255.0 green:0x00/255.0 blue:0x00/255.0 alpha:1.0]);
}
+ (UIColor *)bg2 {
    return AMEFluentDynamic([UIColor colorWithRed:0xF5/255.0 green:0xF5/255.0 blue:0xF5/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x14/255.0 green:0x14/255.0 blue:0x14/255.0 alpha:1.0]);
}
+ (UIColor *)bg3 {
    return AMEFluentDynamic([UIColor colorWithRed:0xEB/255.0 green:0xEB/255.0 blue:0xEB/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x1F/255.0 green:0x1F/255.0 blue:0x1F/255.0 alpha:1.0]);
}
+ (UIColor *)stroke1 {
    return AMEFluentDynamic([UIColor colorWithRed:0xD1/255.0 green:0xD1/255.0 blue:0xD1/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x3D/255.0 green:0x3D/255.0 blue:0x3D/255.0 alpha:1.0]);
}
+ (UIColor *)stroke2 {
    return AMEFluentDynamic([UIColor colorWithRed:0xE0/255.0 green:0xE0/255.0 blue:0xE0/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x4A/255.0 green:0x4A/255.0 blue:0x4A/255.0 alpha:1.0]);
}

// ── 语义色 ──────────────────────────────────────────────────
+ (UIColor *)error {
    return AMEFluentDynamic([UIColor colorWithRed:0xC5/255.0 green:0x0F/255.0 blue:0x1F/255.0 alpha:1.0],
                            [UIColor colorWithRed:0xFF/255.0 green:0x99/255.0 blue:0xA4/255.0 alpha:1.0]);
}
+ (UIColor *)success {
    return AMEFluentDynamic([UIColor colorWithRed:0x0E/255.0 green:0x70/255.0 blue:0x0E/255.0 alpha:1.0],
                            [UIColor colorWithRed:0x6C/255.0 green:0xCB/255.0 blue:0x5F/255.0 alpha:1.0]);
}
+ (UIColor *)warning {
    return AMEFluentDynamic([UIColor colorWithRed:0xBC/255.0 green:0x4B/255.0 blue:0x09/255.0 alpha:1.0],
                            [UIColor colorWithRed:0xFD/255.0 green:0xBE/255.0 blue:0x5B/255.0 alpha:1.0]);
}

// ── 字体 ramp ──────────────────────────────────────────────
+ (UIFont *)fontTitleLarge      { return [UIFont systemFontOfSize:28.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontTitleMedium     { return [UIFont systemFontOfSize:22.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontBody            { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontBodyStrong      { return [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontCallout         { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontSubheadline     { return [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontSubheadlineStrong { return [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontCaption         { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]; }
+ (UIFont *)fontCaptionStrong   { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]; }

// ── 圆角 ───────────────────────────────────────────────────
+ (CGFloat)radiusControl { return 4.0; }
+ (CGFloat)radiusCard    { return 8.0; }
+ (CGFloat)radiusPanel   { return 12.0; }

// ── 间距 ───────────────────────────────────────────────────
+ (CGFloat)spacingXXS { return 4.0; }
+ (CGFloat)spacingXS  { return 8.0; }
+ (CGFloat)spacingS   { return 12.0; }
+ (CGFloat)spacingM   { return 16.0; }
+ (CGFloat)spacingL   { return 20.0; }
+ (CGFloat)spacingXL  { return 24.0; }
+ (CGFloat)spacingXXL { return 32.0; }

// ── 阴影（Fluent shadow 8 / 16）────────────────────────────
+ (void)applyCardShadow:(UIView *)view {
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.14;
    view.layer.shadowRadius = 8.0;
    view.layer.shadowOffset = CGSizeMake(0, 2);
}
+ (void)applyFlyoutShadow:(UIView *)view {
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.18;
    view.layer.shadowRadius = 16.0;
    view.layer.shadowOffset = CGSizeMake(0, 4);
}

@end
