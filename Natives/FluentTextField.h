//
// FluentTextField.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// 蓝本：fluent2_kit fluent_text_field
// 规格：浮动式上方 label（caption1 fg2，必填时带 danger 星号）+ 输入框
//   高 40、bg5 实底、stroke1 描边、焦点态 brandPrimary 2px 描边 +
//   surfaceCard 底；错误态 danger 描边 + 下方 helper 文本 fg3/danger。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FluentTextField : UIView

/// 便捷构造（含上方 label；isRequired 时 label 尾部带 * ）
- (instancetype)initWithFieldLabel:(nullable NSString *)fieldLabel
                       placeholder:(nullable NSString *)placeholder
                        isRequired:(BOOL)isRequired;

@property (nonatomic, readonly) UITextField *textField;

/// 错误/帮助文本（nil 隐藏）；error 状态时文本与描边走 danger
@property (nonatomic, copy, nullable) NSString *helperText;
@property (nonatomic, assign, getter=isErrorShown) BOOL errorShown;

/// 焦点态描边接管（内部监听 editing 状态自动切换，无需手动）
@end

NS_ASSUME_NONNULL_END
