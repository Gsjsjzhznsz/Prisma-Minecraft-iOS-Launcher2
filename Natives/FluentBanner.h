//
// FluentBanner.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// Task: 7.0-UI-5g（组件库第二批三组件之三）
// 蓝本：fluent2_kit fluent_info_bar / 微软 Fluent 2 InfoBar
// 规格：surfaceOverlay 底 + 圆角 large(8) + divider 0.5pt 描边；左侧
//   severity 圆底图标（圆底 = 语义色 12% alpha，图标 SF Symbol 全色）；
//   标题 textPrimary + body1Strong(fontButton)、正文 textSecondary +
//   caption1(fontCaption)；右侧关闭 X 按钮圆形热区 32pt，closeHandler
//   回调 + 自带淡出移除动画；showInView 顶部插入带入场动画，宽度跟随 parent。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FluentBannerSeverity) {
    FluentBannerSeverityInformational = 0, ///< 品牌蓝 · info.circle
    FluentBannerSeveritySuccess       = 1, ///< 绿 · checkmark.circle
    FluentBannerSeverityWarning       = 2, ///< 橙 · exclamationmark.triangle
    FluentBannerSeverityError         = 3, ///< 红 · xmark.octagon
};

@interface FluentBanner : UIView

/// 构造（message 可空 = 仅标题单行；高度随内容自适应）
- (instancetype)initWithTitle:(NSString *)title
                      message:(nullable NSString *)message
                     severity:(FluentBannerSeverity)severity;

/// 关闭回调（点 X 触发；随后组件自带淡出移除动画）
@property (nonatomic, copy, nullable) void (^closeHandler)(void);

/// 顶部插入 parent（带入场动画；宽度 = parent 宽 - 32 边距，随 parent 自适应）
- (void)showInView:(UIView *)parent;

@end

NS_ASSUME_NONNULL_END
