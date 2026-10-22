//
// ZL2Theme.h — Material 3 令牌层（7.0-UI-14：embermire 色板 1:1 真机对齐版）
//
// 背景：7.0-UI-8 初版取 M3 baseline 紫色种子，与 ZL2 真机截图（用户 12 张
//   实机取证）全面不符——ZL2 出厂默认色板为 **Embermire 暖棕系**（Android 12+
//   默认动态取色、12 以下默认 EMBERMIRE；iOS 无 Material You，取 EMBERMIRE
//   静态板为唯一正确对齐源）。本轮把 34 枚 M3 角色全部按 ZL2 Theme.kt
//   embermireLight/embermireDark 逐枚 1:1 移植（浅/深两态，dynamicProvider
//   跟随系统）。
//
// 色值来源：ZalithLauncher2 ui/theme/Color.kt 第一列（embermire 位）+ Theme.kt
//   embermireLight/embermireDark 组装；形状/字体阶不变（M3 官方刻度）。
//
// 消费面：全部 ZL2 系页面。新增角色：secondary/secondaryContainer/
//   tertiary/tertiaryContainer 系（下载页类型 chip=tertiary、顶栏选中
//   pill=secondaryContainer 均为截图实证语义）+ surfaceBright（ZL2
//   cardColor() 的真实卡底）+ surfaceContainerHighest。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2Theme : NSObject

#pragma mark - M3 角色 色（embermire 浅/深跟随系统）

// 主色系
+ (UIColor *)primary;              // M3 primary（深色态 = 桃色 0xFFB59F）
+ (UIColor *)onPrimary;
+ (UIColor *)primaryContainer;
+ (UIColor *)onPrimaryContainer;

// 次色系（顶栏选中 pill 底 = secondaryContainer）
+ (UIColor *)secondary;
+ (UIColor *)onSecondary;
+ (UIColor *)secondaryContainer;
+ (UIColor *)onSecondaryContainer;

// 三色系（下载页版本类型 chip = LittleTextLabel tertiary 档）
+ (UIColor *)tertiary;
+ (UIColor *)onTertiary;
+ (UIColor *)tertiaryContainer;
+ (UIColor *)onTertiaryContainer;

// 表面系（页面底 → 卡片底逐级抬升）
+ (UIColor *)surface;              // 页面底
+ (UIColor *)onSurface;            // 表面上的正文
+ (UIColor *)onSurfaceVariant;     // 表面上的次级文字
+ (UIColor *)surfaceVariant;       // 变体表面（输入框/分隔底）
+ (UIColor *)surfaceContainerLowest;
+ (UIColor *)surfaceContainerLow;  // 容器低
+ (UIColor *)surfaceContainer;     // 容器中
+ (UIColor *)surfaceContainerHigh; // 容器高（浮层/菜单）
+ (UIColor *)surfaceContainerHighest;
+ (UIColor *)surfaceBright;        // ZL2 cardColor() 真实卡底（对齐源）

// 描边系
+ (UIColor *)outline;              // 强描边
+ (UIColor *)outlineVariant;       // 弱描边（分隔线）

// 状态系
+ (UIColor *)error;                // 错误
+ (UIColor *)errorContainer;
+ (UIColor *)success;              // 成功（M3 无标准 success，取绿档判例）
+ (UIColor *)warning;              // 警告（橙档判例）

#pragma mark - M3 形状（圆角阶）

+ (CGFloat)radiusXS;               // 4 （chip/小件）
+ (CGFloat)radiusS;                // 8  （按钮/输入框）
+ (CGFloat)radiusM;                // 12 （卡片）
+ (CGFloat)radiusL;                // 16 （大卡/导航胶囊）
+ (CGFloat)radiusXL;               // 28 （FAB/大容器）

#pragma mark - M3 字体阶

+ (UIFont *)fontHeadline;          // 28  semibold（页首横幅）
+ (UIFont *)fontTitleLarge;        // 22  regular（页标题）
+ (UIFont *)fontTitleMedium;       // 16  medium（卡标题/列表主文）
+ (UIFont *)fontBodyLarge;         // 16  regular（正文）
+ (UIFont *)fontBodyMedium;        // 14  regular（次级正文）
+ (UIFont *)fontLabelLarge;        // 14  medium（按钮/导航标签）
+ (UIFont *)fontLabelMedium;       // 12  medium（chip/角标）

#pragma mark - 语义语义（ZL2 壳约定）

// 启动按钮态着色：可用=primary，不可用=outlineVariant 底
+ (UIColor *)launchReadyTint;
+ (UIColor *)launchDisabledTint;

@end

NS_ASSUME_NONNULL_END
