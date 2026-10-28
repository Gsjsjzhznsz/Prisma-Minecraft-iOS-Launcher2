//
//  AMEFluentTheme.h — Fluent 2 / Apple 设计令牌系统（依据 microsoft/fluentui-apple）
//
// ★ Task339（用户："依据 https://github.com/microsoft/fluentui-apple 重新设计
//   界面，而不是依旧套用 ZL2 的"）：启动器原生 UI 视觉源从 ZL2Theme（M3 对标
//   ZalithLauncher2）整体切换到 Fluent 2 / Apple 令牌。本头是唯一样式事实源，
//   逐值溯源 fluentui-apple（Fluent 2 Apple 官方实现）：
//
//   颜色（Fluent2 / Colors.swift 通行口径，亮暗双态动态色）：
//     · Brand10   #0F6CBD（亮）/ #4CC2FF（暗） —— 品牌主色（338 插件同源口径）
//     · Brand20   #115EA3 / #2886DE            —— 品牌按压/深档
//     · BrandTint #C7E0F4 / #002244            —— 品牌容器
//     · Neutral   fg1 #242424 / #FFFFFF；fg2 #424242 / #D6D6D6；
//                 fg3 #616161 / #A0A0A0；
//                 bg1 #FFFFFF / #000000（卡面）；bg2 #F5F5F5 / #141414（页面）；
//                 bg3 #EBEBEB / #1F1F1F（沉底/ stencil）；
//                 stroke1 #D1D1D1 / #3D3D3D；stroke2 #E0E0E0 / #4A4A4A
//     · 语义色    error #C50F1F / #FF99A4；success #0E700E / #6CCB5F；
//                 warning #BC4B09 / #FDBE5B
//   字体 ramp（Fluent 2 iOS Typography）：
//     Title2 28 Semibold / Title3 22 Semibold / Body 17 Regular /
//     BodyStrong 17 Semibold / Callout 16 Regular / Subheadline 15 Regular /
//     Caption 12 Regular / CaptionStrong 12 Semibold
//   圆角：Fluent 2 控件 4 / 卡片 8 / 大面板 12
//   间距：4pt 栅格（4/8/12/16/20/24/32）
//   阴影：Fluent shadow 8（y2 blur8 α0.14）卡片级；shadow 16 浮层级
//
// 红线遵守（ZL2Home 判例全量继承）：iOS 14.0+；动态色全部
// colorWithDynamicProvider（零 traitCollection 分支）；SF 符号 1.0 级；
// 全部子视图 translatesAutoresizingMaskIntoConstraints = NO。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMEFluentTheme : NSObject

// ── Brand（fluentui-apple brandColor 家族）────────────────────
+ (UIColor *)brand;              // Brand10：#0F6CBD / #4CC2FF
+ (UIColor *)brandShade;         // Brand20：#115EA3 / #2886DE（按压态）
+ (UIColor *)brandContainer;     // BrandTint 容器：#C7E0F4 / #002244
+ (UIColor *)onBrand;            // 品牌底上的前景：#FFFFFF / #000000

// ── Neutral / Alias（fluentui-apple aliasForeground/Background/Stroke）──
+ (UIColor *)fg1;                // 主文本
+ (UIColor *)fg2;                // 次级文本
+ (UIColor *)fg3;                // 三级/占位
+ (UIColor *)bg1;                // 卡面
+ (UIColor *)bg2;                // 页面底
+ (UIColor *)bg3;                // 沉底/stencil
+ (UIColor *)stroke1;            // 强描边
+ (UIColor *)stroke2;            // 弱描边（分隔）

// ── 语义色 ──────────────────────────────────────────────────
+ (UIColor *)error;              // #C50F1F / #FF99A4
+ (UIColor *)success;            // #0E700E / #6CCB5F
+ (UIColor *)warning;            // #BC4B09 / #FDBE5B

// ── 字体 ramp（Fluent 2 iOS Typography）────────────────────
+ (UIFont *)fontTitleLarge;      // Title2   28 / Semibold
+ (UIFont *)fontTitleMedium;     // Title3   22 / Semibold
+ (UIFont *)fontBody;            // Body     17 / Regular
+ (UIFont *)fontBodyStrong;      // BodyStrong 17 / Semibold
+ (UIFont *)fontCallout;         // Callout  16 / Regular
+ (UIFont *)fontSubheadline;     // Subheadline 15 / Regular
+ (UIFont *)fontSubheadlineStrong; // 15 / Semibold
+ (UIFont *)fontCaption;         // Caption  12 / Regular
+ (UIFont *)fontCaptionStrong;   // CaptionStrong 12 / Semibold

// ── 圆角（Fluent 2：控件 4 / 卡片 8 / 面板 12）──────────────
+ (CGFloat)radiusControl;
+ (CGFloat)radiusCard;
+ (CGFloat)radiusPanel;

// ── 间距（4pt 栅格）────────────────────────────────────────
+ (CGFloat)spacingXXS;           // 4
+ (CGFloat)spacingXS;            // 8
+ (CGFloat)spacingS;             // 12
+ (CGFloat)spacingM;             // 16
+ (CGFloat)spacingL;             // 20
+ (CGFloat)spacingXL;            // 24
+ (CGFloat)spacingXXL;           // 32

// ── 阴影辅助（Fluent shadow 8 / 16）────────────────────────
+ (void)applyCardShadow:(UIView *)view;   // shadow8：y2 blur8 α0.14
+ (void)applyFlyoutShadow:(UIView *)view; // shadow16：y4 blur16 α0.18

@end

NS_ASSUME_NONNULL_END
