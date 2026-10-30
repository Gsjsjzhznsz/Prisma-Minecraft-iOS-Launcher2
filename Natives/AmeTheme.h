//
// AmeTheme.h
// Prisma-Minecraft-iOS-Launcher2 — 设计令牌层（v3 · M3 承载层）
//
// ★ Task354（MD3 设计语言统一，用户指令"全面修改为 md3 样式，避免 ui 设计
//   语言混杂"）：本层从"Fluent 2 官方取值"（v2，fluent2_kit 溯源）整体转位为
//   M3 承载层——全部 getter 重指向 ZL2Theme（Material 3 embermire 令牌），
//   API 形状与 v1/v2 完全兼容，既有消费面零改动即整面切换 MD3 视觉。
//   语义映射总表见 AmeTheme.m 文件头。旧 Fluent 取值档案在 git 历史 v2。
//
// 历史溯源存档：
//   v1→v2（7.0-UI-4）：令牌取值整体对齐 graundtech/fluent2_kit（MIT）的官方
//   Fluent 2 token 系统（lib/src/fluent_models/*），逐值溯源：
//     颜色   ← FluentColors / FluentDarkColors（neutralForeground/Background/
//              Stroke + status* 全阶，canvas #F5F5F5/#141414）
//     品牌   ← theme_data.dart _brandColor ramp（#0F6CBD，dark 取 400 #2A93EE）
//     圆角   ← FluentCornerRadius small2/medium4/large8/xLarge12
//     字体   ← MixedFluentTextTheme iOS(SF Pro)：caption1 13/body2 15/body1 17/
//              title3 20/title2 22/title1 28
//   深浅适配：dynamicProvider（iOS 13+，部署目标 14.0 安全），业务代码禁止
//   自行判 traitCollection（v3 起由 ZL2Theme 动态色承担，语义不变）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmeTheme : NSObject

#pragma mark - Brand（M3 primary 系）
/// M3 primary（embermire 动态深浅）
+ (UIColor *)brandPrimary;
/// 选中态底色（M3 secondaryContainer，v2 为 alpha 淡底）
+ (UIColor *)brandTinted;
/// 品牌色上的文字/图标（M3 onPrimary，恒对比安全）
+ (UIColor *)textOnBrand;

#pragma mark - Background & Surface（FluentColors neutralBackground*）
/// 页面画布 canvas：Light #F5F5F5 / Dark #141414
+ (UIColor *)bgPrimary;
/// 次级/内嵌背景 bg2：Light #FFFFFF / Dark #1F1F1F
+ (UIColor *)bgSecondary;
/// 卡片/单元格表面 bg3：Light #FFFFFF / Dark #292929
+ (UIColor *)surfaceCard;
/// 浮层表面 bg4：Light #FAFAFA / Dark #333333
+ (UIColor *)surfaceOverlay;

#pragma mark - Text（neutralForeground*）
/// 一级文本 fg1：Light #242424 / Dark #FFFFFF
+ (UIColor *)textPrimary;
/// 二级文本 fg2：Light #616161 / Dark #D6D6D6
+ (UIColor *)textSecondary;
/// 三级文本 fg3：Light #808080 / Dark #ADADAD
+ (UIColor *)textTertiary;

#pragma mark - Fill & Divider（neutralBackground5/6 + neutralStroke1）
/// 浅填充 bg5：Light #F0F0F0 / Dark #3D3D3D（subtle 控件底/进度槽/代码块）
+ (UIColor *)fillSubtle;
/// 强填充 bg6：Light #D1D1D1 / Dark #5C5C5C（按压态/滑轨/徽章）
+ (UIColor *)fillStrong;
/// 分隔/描边 stroke1：Light #D1D1D1 / Dark #4D4D4D
+ (UIColor *)divider;

#pragma mark - Status（status*Foreground 官方值）
/// 危险 dangerForeground2：Light #C50F1F / Dark #DC626D
+ (UIColor *)statusDanger;
/// 成功 successForeground2：Light #107C10 / Dark #54B054
+ (UIColor *)statusSuccess;
/// 警告 warningForeground1：Light #BC4B09 / Dark #FAA06B
+ (UIColor *)statusWarning;

#pragma mark - Typography（MixedFluentTextTheme · SF Pro）
+ (UIFont *)fontCaption;   ///< caption1 13 regular
+ (UIFont *)fontBody;      ///< body1 17 regular
+ (UIFont *)fontBody2;     ///< body2 15 regular
+ (UIFont *)fontButton;    ///< body1Strong 17 semibold
+ (UIFont *)fontSubtitle;  ///< title3 20 regular
+ (UIFont *)fontTitle2;    ///< title2 22 semibold
+ (UIFont *)fontTitle;     ///< title1 28 bold

#pragma mark - Metrics（FluentCornerRadius）
+ (CGFloat)radiusS;    ///< small 2
+ (CGFloat)radiusM;    ///< medium 4
+ (CGFloat)radiusL;    ///< large 8
+ (CGFloat)radiusXL;   ///< xLarge 12
+ (CGFloat)radiusGlass; ///< 玻璃面板 24（连续曲线；iOS26 液态玻璃观感，浮窗/游戏内菜单同源——Task316 用户'伪玻璃r角太小好锋利'根修：原 26pt 在 7.0-UI-3e 令牌化时误绑 Fluent radiusL=8）

#pragma mark - Environment
/// 当前是否深色（无动态色能力 API 的逃生门，慎用）
+ (BOOL)isDarkMode;

#pragma mark - Global Appearance
/// 全局外观接线（AppDelegate scene 配置期调用一次）
+ (void)applyGlobalAppearance;

@end

NS_ASSUME_NONNULL_END
