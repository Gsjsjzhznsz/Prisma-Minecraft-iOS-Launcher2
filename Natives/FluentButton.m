//
// FluentButton.m — fluent2_kit fluent_button 变体规格的 ObjC 实现
//

#import "FluentButton.h"
#import "AmeTheme.h"

static const CGFloat FluentButtonHeightRegular = 40.0;
static const CGFloat FluentButtonHeightCompact = 32.0;
static const CGFloat FluentButtonHPadding      = 12.0;

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
