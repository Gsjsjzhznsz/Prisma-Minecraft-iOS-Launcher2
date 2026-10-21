//
// ZL2Theme.h — Material 3 令牌层（7.0-UI-8：全面对标 ZalithLauncher 2）
//
// 背景：7.0-UI-1~7 的 Fluent 2 迁移只换了令牌没换骨架，用户判定"没区别"，
//   定调全面对标 ZL2 启动器并抛弃旧 UI 壳。ZL2（ZalithLauncher2）使用
//   Jetpack Compose + Material Design 3；本层将其 M3 设计语言静态移植到
//   ObjC（iOS 14+，零依赖），作为 ZL2 系新壳/新页面的唯一令牌源。
//
// 色板取值：Material 3 官方 baseline（紫色种子 = ZL2 默认动态取色的出厂
//   视觉），浅/深两态完整 1:1 移植，经 UIColor dynamicProvider 跟随系统
//   深浅切换（系统正统路径，不手写 traitCollection 分支刷 UI）。
// 形状：M3 shape scale（extraSmall 4 / small 8 / medium 12 / large 16 /
//   extraLarge 28）。
// 字体：M3 type scale（titleLarge 22 / titleMedium 16 / bodyLarge 16 /
//   bodyMedium 14 / labelLarge 14 / labelSmall 11），systemFont 权重映射。
//
// 消费面：ZL2ShellViewController / ZL2HomeViewController 及后续 ZL2 系
//   新页面。旧 AmeTheme/Fluent 组件保留服务存量页面（增量退役，不做
//   破坏性删除——游戏域桥接仍引用旧类）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2Theme : NSObject

#pragma mark - M3 角色 色（浅/深跟随系统）

// 主色系
+ (UIColor *)primary;              // M3 primary
+ (UIColor *)onPrimary;            // 主色上的文字/图标
+ (UIColor *)primaryContainer;     // 主色容器（选中态底）
+ (UIColor *)onPrimaryContainer;   // 主色容器上的文字

// 表面系（页面底 → 卡片底逐级抬升）
+ (UIColor *)surface;              // 页面底
+ (UIColor *)onSurface;            // 表面上的正文
+ (UIColor *)onSurfaceVariant;     // 表面上的次级文字
+ (UIColor *)surfaceVariant;       // 变体表面（输入框/分隔底）
+ (UIColor *)surfaceContainerLow;  // 容器低（大卡片）
+ (UIColor *)surfaceContainer;     // 容器中（标准卡片）
+ (UIColor *)surfaceContainerHigh; // 容器高（浮层/菜单）

// 描边系
+ (UIColor *)outline;              // 强描边
+ (UIColor *)outlineVariant;       // 弱描边（分隔线）

// 状态系
+ (UIColor *)error;                // 错误
+ (UIColor *)errorContainer;       // 错误容器
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
