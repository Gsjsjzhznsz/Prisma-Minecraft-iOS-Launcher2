//
// FluentBanner.m — fluent2_kit fluent_info_bar 规格的 ObjC 实现
//

#import "FluentBanner.h"
#import "AmeTheme.h"

@implementation FluentBanner {
    UIView *_iconBubble;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UIButton *_closeButton;
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                     severity:(FluentBannerSeverity)severity {
    if (self = [super initWithFrame:CGRectZero]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AmeTheme surfaceOverlay];
        self.layer.cornerRadius = [AmeTheme radiusL];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [AmeTheme divider].CGColor; // 快照，trait 变化刷新

        UIColor *accent = [self ame_accentForSeverity:severity];

        // 左图标圆底：语义色 12% alpha（动态色带 alpha，仍随深浅自动切换）
        _iconBubble = [[UIView alloc] init];
        _iconBubble.backgroundColor = [accent colorWithAlphaComponent:0.12];
        _iconBubble.layer.cornerRadius = 14.0;
        _iconBubble.layer.cornerCurve = kCACornerCurveContinuous;
        _iconBubble.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconBubble];

        _iconView = [[UIImageView alloc]
            initWithImage:[UIImage systemImageNamed:[self ame_symbolForSeverity:severity]]];
        _iconView.tintColor = accent;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconBubble addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [AmeTheme fontButton];            // body1Strong 17sb
        _titleLabel.textColor = [AmeTheme textPrimary];
        _titleLabel.numberOfLines = 0;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _messageLabel = [[UILabel alloc] init];
        _messageLabel.text = message;
        _messageLabel.font = [AmeTheme fontCaption];         // caption1 13
        _messageLabel.textColor = [AmeTheme textSecondary];
        _messageLabel.numberOfLines = 0;
        _messageLabel.hidden = (message.length == 0);
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_messageLabel];

        // 关闭 X：32pt 方形热区（约等于圆形触控目标，layer 圆角 16）
        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark"]
                      forState:UIControlStateNormal];
        _closeButton.tintColor = [AmeTheme textSecondary];
        _closeButton.layer.cornerRadius = 16.0;
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeButton addTarget:self action:@selector(ame_closeTapped)
               forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBubble.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_iconBubble.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_iconBubble.widthAnchor constraintEqualToConstant:28],
            [_iconBubble.heightAnchor constraintEqualToConstant:28],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBubble.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBubble.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:16],
            [_iconView.heightAnchor constraintEqualToConstant:16],

            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBubble.trailingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor constant:-4],

            [_messageLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_messageLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_closeButton.leadingAnchor constant:-4],
            [_messageLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],

            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:32],
            [_closeButton.heightAnchor constraintEqualToConstant:32],
        ]];
    }
    return self;
}

#pragma mark - Show / Dismiss

- (void)showInView:(UIView *)parent {
    [self removeFromSuperview]; // 幂等：重复 show 先摘旧挂载与旧约束
    self.alpha = 0.0;
    self.transform = CGAffineTransformMakeTranslation(0, -12);
    [parent addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.topAnchor constant:12],
        [self.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:16],
        [self.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-16],
    ]];
    [UIView animateWithDuration:0.28
                          delay:0.0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.alpha = 1.0; self.transform = CGAffineTransformIdentity; }
                     completion:nil];
}

- (void)ame_closeTapped {
    if (self.closeHandler) self.closeHandler();
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0.0;
        self.transform = CGAffineTransformMakeTranslation(0, -12);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

#pragma mark - Severity 映射

- (UIColor *)ame_accentForSeverity:(FluentBannerSeverity)severity {
    switch (severity) {
        case FluentBannerSeveritySuccess: return [AmeTheme statusSuccess];
        case FluentBannerSeverityWarning: return [AmeTheme statusWarning];
        case FluentBannerSeverityError:   return [AmeTheme statusDanger];
        default:                          return [AmeTheme brandPrimary];
    }
}

- (NSString *)ame_symbolForSeverity:(FluentBannerSeverity)severity {
    switch (severity) {
        case FluentBannerSeveritySuccess: return @"checkmark.circle";
        case FluentBannerSeverityWarning: return @"exclamationmark.triangle";
        case FluentBannerSeverityError:   return @"xmark.octagon";
        default:                          return @"info.circle";
    }
}

// 深浅切换：描边为 CGColor 静态快照需重设（其余 UIView/UILabel 动态色自动刷新）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.layer.borderColor = [AmeTheme divider].CGColor;
    }
}

@end
