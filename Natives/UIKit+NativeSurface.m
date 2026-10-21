//
//  UIKit+NativeSurface.m
//  Amethyst
//
//  Task210：新拟态引擎整体退役后的卡片表面样式辅助（设计说明见头文件）。
//  保留三件套：平贴表面色 + 深浅自适应主/次文字色（命名去 Neumorph 字样；
//  AmeNeumorphShadowView 承载引擎、渐变表面、双阴影、卡体透明度原语与圆角
//  钉住全部随 Task210 删除）。
//  ★ 7.0-UI-5f：三件套色值由 Task177 定稿硬编码迁至 AmeTheme Fluent 令牌
//  （卡面→surfaceCard / 主文本→textPrimary / 次文本→textSecondary，令牌
//  自带 dynamicProvider 深浅自适应，AmeCardDynamicColor 包裹保留零逻辑变动）。
//

#import "UIKit+NativeSurface.h"
#import "AmeTheme.h" // ★ 7.0-UI-5f：Fluent 设计令牌层（卡面/主次文字 → surfaceCard/textPrimary/textSecondary）
#import <objc/runtime.h>

#pragma mark - Task210 卡面色（动态 provider，深浅色自适应）

static UIColor *AmeCardDynamicColor(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        }];
    }
    return light;
}

UIColor *AmeCardSurfaceColor(void) {
    // 7.0-UI-5f：系统层卡面 → surfaceCard（原 Task177 定稿 #e0e0e0/#2c2c2c 退役）
    return AmeCardDynamicColor([AmeTheme surfaceCard], [AmeTheme surfaceCard]);
}

UIColor *AmeCardPrimaryTextColor(void) {
    // 7.0-UI-5f：系统层主文本 → textPrimary（原 Task177 定稿 #333333/#f5f5f5 退役）
    return AmeCardDynamicColor([AmeTheme textPrimary], [AmeTheme textPrimary]);
}

UIColor *AmeCardSecondaryTextColor(void) {
    // 7.0-UI-5f：系统层次文本 → textSecondary（原 Task177 定稿 #888888/#a0a0a0 退役）
    return AmeCardDynamicColor([AmeTheme textSecondary], [AmeTheme textSecondary]);
}

#pragma mark - 平贴表面分类

@implementation UIView (AmeNativeSurface)

- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task210：纯平贴卡面（表面色 + 圆角）。双阴影承载引擎已随新拟态退役；
    // 裁剪保持（Task152 直角露出修复不变）。
    self.backgroundColor = AmeCardSurfaceColor();
    self.layer.cornerRadius = MAX(8.0, MIN(cornerRadius, 50.0));
    self.layer.masksToBounds = YES;
}

- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task163 语义保留：侧栏/右面板等大面板平贴（无阴影承载层）。
    [self ame_applyCardSurfaceWithRadius:cornerRadius];
}

@end

#pragma mark - AmeBadgeLabel（Task137 胶囊徽章，实现不变）

@implementation AmeBadgeLabel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self ame137_commonInit];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self ame137_commonInit];
    }
    return self;
}

- (void)ame137_commonInit {
    _textInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    self.textAlignment = NSTextAlignmentCenter;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    // 胶囊永不压缩变形：宽度始终 = 文字 + 内边距，空间不足时由相邻视图让位
    [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

// 关键修复：UILabel 默认 intrinsicContentSize 不含自定义内边距，
// 必须显式补上，否则约束宽度 < 绘制宽度，文字尾部必然截断成 …
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + _textInsets.left + _textInsets.right,
                      size.height + _textInsets.top + _textInsets.bottom);
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self invalidateIntrinsicContentSize];
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    [self invalidateIntrinsicContentSize];
}

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect insetRect = UIEdgeInsetsInsetRect(bounds, self.textInsets);
    CGRect textRect = [super textRectForBounds:insetRect limitedToNumberOfLines:numberOfLines];
    textRect.origin.x -= self.textInsets.left;
    textRect.origin.y -= self.textInsets.top;
    return textRect;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 胶囊：圆角 = 高度一半（任意高度/文本长度均保持胶囊形状）
    CGFloat h = self.bounds.size.height;
    if (h > 0) self.layer.cornerRadius = h / 2.0;
}

@end
