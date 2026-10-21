//
// FluentButton.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// 蓝本：fluent2_kit lib/src/components/fluent_components/fluent_button/
//   （fluent_button_style_variants/: accent / outline_accent / outline /
//    subtle / default 五变体；iOS 32/40 双高度档）
// 规格：高度 Regular 40 / Compact 32；圆角 medium(4)；文字 body1Strong 17sb；
//   accent=品牌实底白字，outline=描边品牌字，subtle=无底品牌字，default=
//   bg5 实底 fg1 字；disabled=bg5 底 fg3 字。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FluentButtonStyle) {
    FluentButtonStyleAccent   = 0, ///< 品牌实底（主操作）
    FluentButtonStyleOutline  = 1, ///< 描边（次操作）
    FluentButtonStyleSubtle   = 2, ///< 无底（三级操作）
    FluentButtonStyleDefault  = 3, ///< 中性实底（表单默认）
};

@interface FluentButton : UIButton

/// 按变体构造（尺寸默认 Regular 40）
+ (instancetype)buttonWithStyle:(FluentButtonStyle)style
                          title:(NSString *)title
                         target:(nullable id)target
                         action:(nullable SEL)action;

/// 紧凑档（高度 32）
+ (instancetype)compactButtonWithStyle:(FluentButtonStyle)style
                                 title:(NSString *)title
                                target:(nullable id)target
                                action:(nullable SEL)action;

@property (nonatomic, readonly) FluentButtonStyle fluentStyle;

/// 重新应用变体配色（主题切换后调用；动态色场景通常无需手动）
- (void)applyFluentStyle;

@end

NS_ASSUME_NONNULL_END
