//
// FluentSegmentedControl.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// Task: 7.0-UI-5g（组件库第二批三组件之一）
// 蓝本：fluent2_kit custom_sliding_segmented_control（滑块式分段控件形态）
//   + 微软 Fluent 2 segmented control 规格
// 规格：轨道 = fillSubtle、圆角 large(8)、高 32；滑块 thumb = surfaceCard
//   + shadow2 轻投影（黑 0.10/半径 4/偏移 0,2）+ 圆角 large(8) 动画滑移；
//   选中段 textPrimary + body1Strong(fontButton)，未选中 textSecondary +
//   body1(fontBody)；均分 segments，enabled 总开关置灰。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FluentSegmentedControl : UIView

/// 均分 segments 构造（items 为各段标题，段数 >= 1；宽高走 intrinsicContentSize）
- (instancetype)initWithItems:(NSArray<NSString *> *)items;

/// 当前选中下标（可读写；赋值默认带滑移动画）
@property (nonatomic, assign) NSUInteger selectedIndex;

/// 带动画切换选中段
- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated;

/// 用户点击导致选中变化时回调（程序赋值 selectedIndex 不触发）
@property (nonatomic, copy, nullable) void (^onChange)(NSUInteger index);

/// 总开关（NO 时整条不响应点击且文字置灰 textTertiary）
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

@end

NS_ASSUME_NONNULL_END
