//
// AmeTheme.h
// Prisma-Minecraft-iOS-Launcher2 — 7.0 Fluent 风格设计令牌层
//
// 7.0-UI-2: 全新主题基础设施。目标：
//   1) 收敛全仓 82 个文件的硬编码 UIColor，提供单一事实源的语义令牌
//   2) Fluent 2 视觉语言（微软 fluent2.microsoft.design 公开规范取值）
//   3) iOS 14.0+ 兼容：纯 ObjC、零依赖、动态色 dynamicProvider（iOS 13+）
//      自动适配 Light/Dark，业务代码禁止自行判 traitCollection
//
// 令牌消费规则（7.0-UI-3x 迁移批任务约定）：
//   [AmeTheme xxx] 类方法即用即取；不要缓存到静态变量（深浅模式切换需重取）。
//   语义优先：先判断"这个颜色在界面里扮演什么角色"，再选令牌；拿不准就选
//   最接近的并在迁移报告里记录，禁止为对色值造新令牌。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmeTheme : NSObject

#pragma mark - Brand（品牌）
/// 品牌主色（Fluent 2 communication blue：Light #0F6CBD / Dark #479EF5）
+ (UIColor *)brandPrimary;
/// 品牌浅底（品牌 10% 左右淡填充，用于选中态底色/tinted 按钮）
+ (UIColor *)brandTinted;
/// 品牌色上的文字/图标（恒白）
+ (UIColor *)textOnBrand;

#pragma mark - Background & Surface（背景与表面）
/// 页面级背景（大底）
+ (UIColor *)bgPrimary;
/// 次级/内嵌背景（侧栏、输入区内衬）
+ (UIColor *)bgSecondary;
/// 卡片/单元格表面
+ (UIColor *)surfaceCard;
/// 浮层表面（菜单、弹窗、悬浮件）
+ (UIColor *)surfaceOverlay;

#pragma mark - Text（文本）
/// 一级文本（标题、正文主色）
+ (UIColor *)textPrimary;
/// 二级文本（副标题、说明）
+ (UIColor *)textSecondary;
/// 三级文本（占位、脚注、禁用）
+ (UIColor *)textTertiary;

#pragma mark - Fill & Divider（填充与分隔）
/// 极浅填充（subtle 按钮底、chip、进度槽）
+ (UIColor *)fillSubtle;
/// 强填充（按压态、滑轨、开关底）
+ (UIColor *)fillStrong;
/// 分隔线/描边
+ (UIColor *)divider;

#pragma mark - Status（状态语义）
+ (UIColor *)statusDanger;   ///< 危险/删除/错误
+ (UIColor *)statusSuccess;  ///< 成功/在线
+ (UIColor *)statusWarning;  ///< 警告/等待

#pragma mark - Typography（字体阶，Fluent 2 比例）
+ (UIFont *)fontTitle;     ///< 28 bold 页面大标题
+ (UIFont *)fontSubtitle;  ///< 20 semibold 区块标题
+ (UIFont *)fontBody;      ///< 17 regular 正文
+ (UIFont *)fontCaption;   ///< 13 regular 辅助说明
+ (UIFont *)fontButton;    ///< 17 semibold 按钮

#pragma mark - Metrics（度量）
/// 小圆角（chip/输入框内元素）
+ (CGFloat)radiusS;
/// 中圆角（按钮/输入框/小卡片）
+ (CGFloat)radiusM;
/// 大圆角（卡片/浮层）
+ (CGFloat)radiusL;

#pragma mark - Environment
/// 当前是否深色（个别 UIKit 旧 API 无动态色能力时的逃生门，慎用）
+ (BOOL)isDarkMode;

#pragma mark - Global Appearance
/// 全局外观接线（AppDelegate scene 配置期调用一次）：
/// 导航栏/标签栏/表视图/开关/滑杆/UIAppearance 代理统一注入令牌。
/// 仅做外观代理注册，不触碰任何业务视图层级。
+ (void)applyGlobalAppearance;

@end

NS_ASSUME_NONNULL_END
