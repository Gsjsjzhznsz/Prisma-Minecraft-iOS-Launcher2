//
// FluentProgress.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// Task: 7.0-UI-5g（组件库第二批三组件之二）
// 蓝本：fluent2_kit fluent_progress / 微软 Fluent 2 Progress
// 规格：Bar（determinate）：高 3pt、track = fillSubtle、fill = brandPrimary、
//   圆角 small(2)，progress 0~1 支持动画更新；Ring（indeterminate）：自绘
//   小圆环（fillSubtle 全环底 + brandPrimary 270° 圆弧旋转，20×20）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FluentProgressStyle) {
    FluentProgressStyleBar  = 0, ///< determinate 进度条（高 3，宽度由调用方约束）
    FluentProgressStyleRing = 1, ///< indeterminate 转圈（intrinsic 20×20）
};

@interface FluentProgress : UIView

/// 按形态构造
- (instancetype)initWithStyle:(FluentProgressStyle)style;

@property (nonatomic, readonly) FluentProgressStyle style;

/// 进度 0~1（Bar 专属；越界自动收敛，赋值默认带动画）
@property (nonatomic, assign) double progress;

/// 带动画更新进度（Bar 专属）
- (void)setProgress:(double)progress animated:(BOOL)animated;

/// Ring 专属：YES 旋转 / NO 停转（默认 NO）
@property (nonatomic, assign, getter=isRunning) BOOL running;

@end

NS_ASSUME_NONNULL_END
