//
// FluentButton.m — fluent2_kit fluent_button 变体规格的 ObjC 实现
//

#import "FluentButton.h"
#import "AmeTheme.h"

static const CGFloat FluentButtonHeightRegular = 40.0;
static const CGFloat FluentButtonHeightCompact = 32.0;
static const CGFloat FluentButtonHPadding      = 12.0;

@interface FluentButton ()
/// 图标档标记（iconButtonWithStyle: 置位）：applyFluentStyle 走 tintColor
/// 着色分支而非 setTitleColor（7.0-UI-6）
@property (nonatomic, assign) BOOL fluentIconOnly;
@end

@implementation FluentButton

+ (instancetype)buttonWithStyle:(FluentButtonStyle)style
                          title:(NSString *)title
                         target:(id)target
                         action:(SEL)action {
    return [self fluentButtonWithStyle:style title:title target:target action:action compact:NO];
}

+ (instancetype)compactButtonWithStyle:(FluentButtonStyle)style
                                 title:(NSString *)title
                                target:(id)target
                                action:(SEL)action {
    return [self fluentButtonWithStyle:style title:title target:target action:action compact:YES];
}

+ (instancetype)iconButtonWithStyle:(FluentButtonStyle)style
                               size:(CGFloat)size
                              image:(UIImage *)image
                             target:(id)target
                              action:(SEL)action {
    FluentButton *b = [super buttonWithType:UIButtonTypeSystem];
    // 先置图标档标记再赋 style（setFluentStyle 会触发 applyFluentStyle，
    // 需让首刷直接走图标分支）
    b.fluentIconOnly = YES;
    b.fluentStyle = style;
    b.layer.cornerRadius = [AmeTheme radiusM];
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    if (image) {
        // 恒模板渲染：着色权交给 tintColor（宿主可随选中态覆写）
        [b setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
           forState:UIControlStateNormal];
    }
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    // 正方形自约束：外部（StackView 等）无需再补尺寸约束
    [b.widthAnchor constraintEqualToConstant:size].active = YES;
    [b.heightAnchor constraintEqualToConstant:size].active = YES;
    return b;
}

+ (instancetype)fluentButtonWithStyle:(FluentButtonStyle)style
                                title:(NSString *)title
                               target:(id)target
                               action:(SEL)action
                              compact:(BOOL)compact {
    FluentButton *b = [super buttonWithType:UIButtonTypeSystem];
    b.fluentStyle = style;
    b.layer.cornerRadius = [AmeTheme radiusM];
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:compact ? FluentButtonHeightCompact
                                                      : FluentButtonHeightRegular].active = YES;
    [b.widthAnchor constraintGreaterThanOrEqualToConstant:FluentButtonHPadding * 2].active = YES;
    [b applyFluentStyle];
    return b;
}

- (void)setFluentStyle:(FluentButtonStyle)style {
    _fluentStyle = style;
    [self applyFluentStyle];
}

- (void)applyFluentStyle {
    self.titleLabel.font = [AmeTheme fontButton];
    // 图标档：着色走 tintColor（模板渲染图标），背景/描边语义与文字档同构
    if (_fluentIconOnly) {
        [self ame_applyIconStyle];
        return;
    }
    // iOS 14 安全：不用 UIButton.Configuration，全部走 setTitleColor/背景层
    switch (_fluentStyle) {
        case FluentButtonStyleAccent:
            [self setTitleColor:[AmeTheme textOnBrand] forState:UIControlStateNormal];
            self.backgroundColor = [AmeTheme brandPrimary];
            self.layer.borderWidth = 0;
            break;
        case FluentButtonStyleOutline:
            [self setTitleColor:[AmeTheme brandPrimary] forState:UIControlStateNormal];
            self.backgroundColor = [UIColor clearColor];
            self.layer.borderWidth = 1.0;
            self.layer.borderColor = [AmeTheme divider].CGColor;
            break;
        case FluentButtonStyleSubtle:
            [self setTitleColor:[AmeTheme brandPrimary] forState:UIControlStateNormal];
            self.backgroundColor = [UIColor clearColor];
            self.layer.borderWidth = 0;
            break;
        case FluentButtonStyleDefault:
        default:
            [self setTitleColor:[AmeTheme textPrimary] forState:UIControlStateNormal];
            self.backgroundColor = [AmeTheme fillSubtle];
            self.layer.borderWidth = 0;
            break;
    }
    // Disabled 态（fluent2_kit：bg5 底 + fg3 字）
    [self setTitleColor:[AmeTheme textTertiary] forState:UIControlStateDisabled];
    [self setBackgroundImage:[self ame_disabledImage] forState:UIControlStateDisabled];
}

// 图标档变体配色（7.0-UI-6）：与文字档同构，仅着色目标从 titleColor 换成
// tintColor（图标恒模板渲染）；disabled 复用 fillSubtle 实底图
- (void)ame_applyIconStyle {
    switch (_fluentStyle) {
        case FluentButtonStyleAccent:
            self.tintColor = [AmeTheme textOnBrand];
            self.backgroundColor = [AmeTheme brandPrimary];
            self.layer.borderWidth = 0;
            break;
        case FluentButtonStyleOutline:
            self.tintColor = [AmeTheme brandPrimary];
            self.backgroundColor = [UIColor clearColor];
            self.layer.borderWidth = 1.0;
            self.layer.borderColor = [AmeTheme divider].CGColor;
            break;
        case FluentButtonStyleSubtle:
            self.tintColor = [AmeTheme brandPrimary];
            self.backgroundColor = [UIColor clearColor];
            self.layer.borderWidth = 0;
            break;
        case FluentButtonStyleDefault:
        default:
            self.tintColor = [AmeTheme textPrimary];
            self.backgroundColor = [AmeTheme fillSubtle];
            self.layer.borderWidth = 0;
            break;
    }
    [self setBackgroundImage:[self ame_disabledImage] forState:UIControlStateDisabled];
}

// disabled 实底：fillSubtle 色渲染成 1x1 图（iOS 14 无 Configuration 可用）
- (UIImage *)ame_disabledImage {
    CGRect r = CGRectMake(0, 0, 1, 1);
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:r.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[AmeTheme fillSubtle] setFill];
        UIRectFill(r);
    }];
}

@end
