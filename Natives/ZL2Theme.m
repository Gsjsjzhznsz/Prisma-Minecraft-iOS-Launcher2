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

@implementation ZL2Theme

#pragma mark - 主色系

+ (UIColor *)primary {
    // embermire：浅 = 锈橙 0xA63A17；深 = 桃色 0xFFB59F（截图"启动游戏"钮）
    return ZL2ColorLightDark(0xA63A17, 0xFFB59F);
}
+ (UIColor *)onPrimary {
    return ZL2ColorLightDark(0xFFFFFF, 0x5F1600);
}
+ (UIColor *)primaryContainer {
    return ZL2ColorLightDark(0xFE7A52, 0xC4502B);
}
+ (UIColor *)onPrimaryContainer {
    return ZL2ColorLightDark(0x2F0700, 0xFFFFFF);
}

#pragma mark - 次色系

+ (UIColor *)secondary {
    return ZL2ColorLightDark(0x894F3D, 0xFFB59F);
}
+ (UIColor *)onSecondary {
    return ZL2ColorLightDark(0xFFFFFF, 0x512214);
}
+ (UIColor *)secondaryContainer {
    // 深 = 0x643122（截图顶栏"下载"选中 pill 底）
    return ZL2ColorLightDark(0xFFBBA7, 0x643122);
}
+ (UIColor *)onSecondaryContainer {
    return ZL2ColorLightDark(0x5C2B1C, 0xFFC8B9);
}

#pragma mark - 三色系

+ (UIColor *)tertiary {
    // 深 = 0xF0D44C（截图版本类型 chip 橄榄黄字色，LittleTextLabel tertiary 档）
    return ZL2ColorLightDark(0x6E5E00, 0xF0D44C);
}
+ (UIColor *)onTertiary {
    return ZL2ColorLightDark(0xFFFFFF, 0x393000);
}
+ (UIColor *)tertiaryContainer {
    return ZL2ColorLightDark(0xBAA015, 0xC4AA22);
}
+ (UIColor *)onTertiaryContainer {
    return ZL2ColorLightDark(0x1A1500, 0x272000);
}

#pragma mark - 表面系

+ (UIColor *)surface {
    // 深 = 0x1C110E（截图页面底暖深棕）
    return ZL2ColorLightDark(0xFFF8F6, 0x1C110E);
}
+ (UIColor *)onSurface {
    return ZL2ColorLightDark(0x241916, 0xF4DED8);
}
+ (UIColor *)onSurfaceVariant {
    return ZL2ColorLightDark(0x58423B, 0xDFC0B7);
}
+ (UIColor *)surfaceVariant {
    return ZL2ColorLightDark(0xFCDBD3, 0x58423B);
}
+ (UIColor *)surfaceContainerLowest {
    return ZL2ColorLightDark(0xFFFFFF, 0x160C09);
}
+ (UIColor *)surfaceContainerLow {
    return ZL2ColorLightDark(0xFFF1ED, 0x241916);
}
+ (UIColor *)surfaceContainer {
    return ZL2ColorLightDark(0xFFE9E4, 0x291D19);
}
+ (UIColor *)surfaceContainerHigh {
    return ZL2ColorLightDark(0xFAE3DD, 0x342723);
}
+ (UIColor *)surfaceContainerHighest {
    return ZL2ColorLightDark(0xF4DED8, 0x3B2C27);
}
+ (UIColor *)surfaceBright {
    // ZL2 cardColor() 真实卡底：深 = 0x443632（截图文件/版本卡底色）
    return ZL2ColorLightDark(0xFFF8F6, 0x443632);
}

#pragma mark - 描边系

+ (UIColor *)outline {
    return ZL2ColorLightDark(0x8B716A, 0xA68B83);
}
+ (UIColor *)outlineVariant {
    return ZL2ColorLightDark(0xDFC0B7, 0x58423B);
}

#pragma mark - 状态系

+ (UIColor *)error {
    return ZL2ColorLightDark(0xBA1A1A, 0xFFB4AB);
}
+ (UIColor *)errorContainer {
    return ZL2ColorLightDark(0xFFDAD6, 0x93000A);
}
+ (UIColor *)success {
    // M3 无标准 success：embermire 无绿档，取 M3 官方 baseline 绿（历史判例沿用）
    return ZL2ColorLightDark(0x146C2E, 0x6DD58C);
}
+ (UIColor *)warning {
    // 橙档判例沿用（embermire primaryContainer 案）
    return ZL2ColorLightDark(0x8F4C38, 0xFFB693);
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
