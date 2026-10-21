//
// FluentToast.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// 蓝本：fluent2_kit fluent_toast（example/lib/screens/components_example_view/
//   fluent_toast_view.dart）
// 规格：底部浮出条；surfaceOverlay 面 + shadow8 投影 + 圆角 medium(4)；
//   status 变体：neutral（fg1 正文）/ success / warning / danger（对应
//   status*Foreground 前导图标 tint + 正文 fg1）；auto dismiss 默认 3s；
//   同屏仅一条（新 toast 顶掉旧条）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FluentToastVariant) {
    FluentToastVariantNeutral = 0,
    FluentToastVariantSuccess = 1,
    FluentToastVariantWarning = 2,
    FluentToastVariantDanger  = 3,
};

@interface FluentToast : UIView

/// 展示（挂到 keyWindow scene；同屏单例）
/// @param title   主文案（body1Strong）
/// @param detail  副文案（body2 fg2，可空）
+ (void)showWithTitle:(NSString *)title
               detail:(nullable NSString *)detail
             variant:(FluentToastVariant)variant;

/// 自定义停留时长（秒；<=0 = 不自动消失）
+ (void)showWithTitle:(NSString *)title
               detail:(nullable NSString *)detail
             variant:(FluentToastVariant)variant
             duration:(NSTimeInterval)duration;

/// 主动收起（动画）
+ (void)dismiss;

@end

NS_ASSUME_NONNULL_END
