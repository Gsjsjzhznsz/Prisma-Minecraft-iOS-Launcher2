//
// FluentCard.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// 蓝本：fluent2_kit lib/src/components/fluent_components/fluent_card.dart
//   + fluent_card_container.dart
// 规格：surfaceCard 面 + stroke1 发丝描边 + shadow2 低仰角投影 +
//   圆角 large(8)；内边距 12；可选点击态（按压 fillSubtle 反馈）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FluentCard : UIView

/// 内容视图（调用方往里塞子视图；四边已按 Fluent 规格留 12pt 内边距）
@property (nonatomic, readonly) UIView *contentView;

/// 是否可点击（YES 时挂按压态：fillSubtle 底 + 缩放 0.98 反馈）
@property (nonatomic, assign, getter=isFluentClickable) BOOL fluentClickable;

/// 点击回调（仅 fluentClickable 时触发）
@property (nonatomic, copy, nullable) void (^fluentTapHandler)(void);

/// 关闭内边距（贴边内容用）
@property (nonatomic, assign) BOOL fluentEdgeToEdge;

@end

NS_ASSUME_NONNULL_END
