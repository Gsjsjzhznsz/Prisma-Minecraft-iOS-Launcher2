//
// FluentListCell.h
// Prisma-Minecraft-iOS-Launcher2 — Fluent 组件库
//
// 蓝本：fluent2_kit lib/screens/components_example_view/fluent_list_view/
//   （one_line_list_view / multi_line_list_view）
// 规格：one-line 44 高 / multi-line 64 高；title fg1 body1、subtitle fg2
//   body2、辅助文本 fg3 caption1；行高亮按压态 fillSubtle；圆角 medium(4)
//   常规态、选中态 bg5 实底。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FluentListCell : UITableViewCell

/// 单行构造（44 高）；trailingAccessory 可空
+ (instancetype)oneLineCellWithReuseIdentifier:(NSString *)identifier;

/// 双行构造（64 高）：title + subtitle
+ (instancetype)multiLineCellWithReuseIdentifier:(NSString *)identifier;

@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly, nullable) UILabel *subtitleLabel;   ///< multi-line 专属
@property (nonatomic, readonly, nullable) UILabel *detailLabel;     ///< 右侧辅助文本
@property (nonatomic, readonly, nullable) UIImageView *leadingIcon; ///< 20pt 前导图标

/// 是否双行布局
@property (nonatomic, readonly, getter=isMultiLine) BOOL multiLine;

@end

NS_ASSUME_NONNULL_END
