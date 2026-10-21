//
// ZL2Theme.m — Material 3 令牌层实现（7.0-UI-8）
//
// 浅/深两态经 +[UIColor colorWithDynamicProvider:] 跟随 traitCollection
// 切换（系统正统路径）；所有取值为 M3 官方 baseline 静态移植。
//

#import "ZL2Theme.h"

#pragma mark - 私有：浅/深双态构造

static UIColor *ZL2ColorLightDark(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (@available(iOS 13.0, *)) {
            if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) return dark;
        }
        return light;
    }];
}

@implementation ZL2Theme

#pragma mark - M3 角色 色

+ (UIColor *)primary {
    // M3 baseline primary：浅 #6750A4 / 深 #D0BCFF
    return ZL2ColorLightDark([UIColor colorWithRed:0x67/255.0 green:0x50/255.0 blue:0xA4/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xD0/255.0 green:0xBC/255.0 blue:0xFF/255.0 alpha:1.0]);
}

+ (UIColor *)onPrimary {
    return ZL2ColorLightDark([UIColor whiteColor],
                             [UIColor colorWithRed:0x38/255.0 green:0x1E/255.0 blue:0x72/255.0 alpha:1.0]);
}

+ (UIColor *)primaryContainer {
    return ZL2ColorLightDark([UIColor colorWithRed:0xEA/255.0 green:0xDD/255.0 blue:0xFF/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x4F/255.0 green:0x37/255.0 blue:0x8B/255.0 alpha:1.0]);
}

+ (UIColor *)onPrimaryContainer {
    return ZL2ColorLightDark([UIColor colorWithRed:0x21/255.0 green:0x00/255.0 blue:0x5D/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xEA/255.0 green:0xDD/255.0 blue:0xFF/255.0 alpha:1.0]);
}

+ (UIColor *)surface {
    return ZL2ColorLightDark([UIColor colorWithRed:0xFE/255.0 green:0xF7/255.0 blue:0xFF/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x14/255.0 green:0x12/255.0 blue:0x18/255.0 alpha:1.0]);
}

+ (UIColor *)onSurface {
    return ZL2ColorLightDark([UIColor colorWithRed:0x1D/255.0 green:0x1B/255.0 blue:0x20/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xE6/255.0 green:0xE0/255.0 blue:0xE9/255.0 alpha:1.0]);
}

+ (UIColor *)onSurfaceVariant {
    return ZL2ColorLightDark([UIColor colorWithRed:0x49/255.0 green:0x45/255.0 blue:0x4F/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xCA/255.0 green:0xC4/255.0 blue:0xD0/255.0 alpha:1.0]);
}

+ (UIColor *)surfaceVariant {
    return ZL2ColorLightDark([UIColor colorWithRed:0xE7/255.0 green:0xE0/255.0 blue:0xEC/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x49/255.0 green:0x45/255.0 blue:0x4F/255.0 alpha:1.0]);
}

+ (UIColor *)surfaceContainerLow {
    return ZL2ColorLightDark([UIColor colorWithRed:0xF7/255.0 green:0xF2/255.0 blue:0xFA/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x1D/255.0 green:0x1B/255.0 blue:0x20/255.0 alpha:1.0]);
}

+ (UIColor *)surfaceContainer {
    return ZL2ColorLightDark([UIColor colorWithRed:0xF3/255.0 green:0xED/255.0 blue:0xF7/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x21/255.0 green:0x1F/255.0 blue:0x26/255.0 alpha:1.0]);
}

+ (UIColor *)surfaceContainerHigh {
    return ZL2ColorLightDark([UIColor colorWithRed:0xEC/255.0 green:0xE6/255.0 blue:0xF0/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x2B/255.0 green:0x29/255.0 blue:0x30/255.0 alpha:1.0]);
}

+ (UIColor *)outline {
    return ZL2ColorLightDark([UIColor colorWithRed:0x79/255.0 green:0x74/255.0 blue:0x7E/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x93/255.0 green:0x8F/255.0 blue:0x99/255.0 alpha:1.0]);
}

+ (UIColor *)outlineVariant {
    return ZL2ColorLightDark([UIColor colorWithRed:0xCA/255.0 green:0xC4/255.0 blue:0xD0/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x49/255.0 green:0x45/255.0 blue:0x4F/255.0 alpha:1.0]);
}

+ (UIColor *)error {
    return ZL2ColorLightDark([UIColor colorWithRed:0xB3/255.0 green:0x26/255.0 blue:0x1E/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xF2/255.0 green:0xB8/255.0 blue:0xB5/255.0 alpha:1.0]);
}

+ (UIColor *)errorContainer {
    return ZL2ColorLightDark([UIColor colorWithRed:0xF9/255.0 green:0xDE/255.0 blue:0xDC/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x8C/255.0 green:0x1D/255.0 blue:0x18/255.0 alpha:1.0]);
}

+ (UIColor *)success {
    // M3 无标准 success：沿用项目绿档判例（Fluent 107C10/54B054 与 M3 兼容）
    return ZL2ColorLightDark([UIColor colorWithRed:0x10/255.0 green:0x7C/255.0 blue:0x10/255.0 alpha:1.0],
                             [UIColor colorWithRed:0x54/255.0 green:0xB0/255.0 blue:0x54/255.0 alpha:1.0]);
}

+ (UIColor *)warning {
    // M3 无标准 warning：沿用项目橙档判例（Fluent BC4B09/FAA06B）
    return ZL2ColorLightDark([UIColor colorWithRed:0xBC/255.0 green:0x4B/255.0 blue:0x09/255.0 alpha:1.0],
                             [UIColor colorWithRed:0xFA/255.0 green:0xA0/255.0 blue:0x6B/255.0 alpha:1.0]);
}

#pragma mark - M3 形状

+ (CGFloat)radiusXS   { return 4.0;  }
+ (CGFloat)radiusS    { return 8.0;  }
+ (CGFloat)radiusM    { return 12.0; }
+ (CGFloat)radiusL    { return 16.0; }
+ (CGFloat)radiusXL   { return 28.0; }

#pragma mark - M3 字体阶

+ (UIFont *)fontHeadline    { return [UIFont systemFontOfSize:28.0 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontTitleLarge  { return [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];  }
+ (UIFont *)fontTitleMedium { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];   }
+ (UIFont *)fontBodyLarge   { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];  }
+ (UIFont *)fontBodyMedium  { return [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];  }
+ (UIFont *)fontLabelLarge  { return [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];   }
+ (UIFont *)fontLabelMedium { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];   }

#pragma mark - 语义

+ (UIColor *)launchReadyTint    { return [self primary]; }
+ (UIColor *)launchDisabledTint { return [self outlineVariant]; }

@end
