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

#pragma mark - Task317 插件主题令牌覆盖（高危权限 ui.theme）

// tokens: {@"primary": @"#RRGGBB[AA]", ...}；未知令牌忽略（白名单见 .m），
// tokens 空/nil = 清除该插件全部覆盖（停用/卸载还原用）。后写者胜。
// 覆盖表自包含于 ZL2Theme.m（smoke 目标零新增依赖）；getter 侧 28 个
// 色值令牌经 AME317_PLUGIN_COLOR 宏先行检查覆盖。
+ (BOOL)ame317_setPluginThemeTokens:(NSString *)pluginId
                             tokens:(nullable NSDictionary<NSString *, NSString *> *)tokens;

#pragma mark - Task341 插件形状/字体令牌覆盖（高危权限 ui.theme，同 ame317 记账还原语义）

// Fluent 2 等非 M3 设计语言「完全重设计」的引擎承载面：色令牌（ame317）之外
// 的形状阶与字体阶从此可被插件整体重塑（ZL2 页面 71 处圆角 + 144 处字体全部
// 经 getter 消费，覆盖即全页面生效；默认值 M3 刻度不变 = 本引擎不携带任何
// Fluent 视觉资产，Fluent 形态全部住在插件侧）。
//
// tokens 结构（混合键空间，白名单见 .m）：
//   radius* 键 → NSNumber（pt，钳制 0...40）；
//   font*   键 → NSDictionary {@{@"size": 15, @"weight": @"semibold"}}，
//                weight 接受 "regular"/"medium"/"semibold"/"bold"（数字
//                400/500/600/700 同义映射）。未知键忽略；类型不合法跳过。
// 空/nil = 清除该插件全部形状/字体覆盖（停用/卸载还原用）。后写者胜。
// 与 ame317 色令牌覆盖相互独立（可单独应用、单独还原）。
+ (BOOL)ame341_setPluginThemeShape:(NSString *)pluginId
                            tokens:(nullable NSDictionary *)tokens;

#pragma mark - Task343 插件布局令牌覆盖（高危权限 ui.theme，同 ame317/341 记账还原语义）

// 排版/间距刻度的插件承载面（ame341 形状/字体之外的第四令牌族）：列表密度、
// 卡片解剖（内外边距/内容间隙）、动作胶囊与搜索框/chip/对话框/按钮的几何
// 全部经 ame343_layoutMetric:fallback: 消费（默认值 = 现行 ZL2 硬编码刻度，
// 零覆盖零变化 = 引擎不携带任何非 M3 视觉资产；Fluent 等非 M3 设计语言的
// 排版形态全部住在插件侧）。
//
// tokens 结构（数值键空间，白名单 + 钳制见 .m）：键 → NSNumber（pt）。
//   searchBarHeight(32...64) / chipHeight(24...48) /
//   cardMarginV(0...24) / cardMarginH(0...40) / cardInsetX(0...40) /
//   cardInsetTop(0...40) / cardInsetBottom(0...40) / cardContentGap(0...24) /
//   pillMinWidth(32...160) / pillHeight(20...56) / pillGap(0...32) /
//   dialogInset(8...48) / buttonHeight(28...64)
// 未知键忽略；类型不合法/越界跳过。空/nil = 清除该插件全部布局覆盖
// （停用/卸载还原用）。后写者胜。与色/形状/字体三族相互独立。
+ (BOOL)ame343_setPluginThemeLayout:(NSString *)pluginId
                             tokens:(nullable NSDictionary *)tokens;

// 布局刻度读取（消费侧一行式）：token 未被插件覆盖时返回 fallback（即
// 消费点既有硬编码值——改动最小化，默认行为逐位不变）。
+ (CGFloat)ame343_layoutMetric:(NSString *)token fallback:(CGFloat)fallback;

@end

NS_ASSUME_NONNULL_END
