//
// FluentToast.m — fluent2_kit fluent_toast 规格的 ObjC 实现
//

#import "FluentToast.h"
#import "AmeTheme.h"

static FluentToast *_ame_currentToast = nil;

@implementation FluentToast {
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_detailLabel;
    NSTimer *_timer;
}

#pragma mark - Public

+ (void)showWithTitle:(NSString *)title detail:(NSString *)detail variant:(FluentToastVariant)variant {
    [self showWithTitle:title detail:detail variant:variant duration:3.0];
}

+ (void)showWithTitle:(NSString *)title
               detail:(NSString *)detail
              variant:(FluentToastVariant)variant
             duration:(NSTimeInterval)duration {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_ame_currentToast ame_dismissAnimated:NO]; // 同屏单例：顶掉旧条
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).keyWindow;
                break;
            }
        }
        if (!window) return;

        FluentToast *toast = [[FluentToast alloc] initWithFrame:CGRectZero variant:variant];
        toast->_titleLabel.text = title;
        toast->_detailLabel.hidden = (detail.length == 0);
        toast->_detailLabel.text = detail;
        _ame_currentToast = toast;

        [window addSubview:toast];

        UILayoutGuide *safe = window.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [toast.leadingAnchor constraintEqualToAnchor:window.leadingAnchor constant:16],
            [toast.trailingAnchor constraintEqualToAnchor:window.trailingAnchor constant:-16],
            [toast.topAnchor constraintGreaterThanOrEqualToAnchor:window.topAnchor constant:80],
            [toast.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        ]];
        [window layoutIfNeeded];

        // 入场：transform 上浮（避免双 bottom 约束冲突）
        toast.transform = CGAffineTransformMakeTranslation(0, 80);
        [UIView animateWithDuration:0.28
                              delay:0
             usingSpringWithDamping:0.85
              initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ toast.transform = CGAffineTransformIdentity; }
                         completion:nil];

        if (duration > 0) {
            toast->_timer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                             target:toast
                                                           selector:@selector(ame_timerFired:)
                                                           userInfo:nil
                                                            repeats:NO];
        }
    });
}

+ (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_ame_currentToast ame_dismissAnimated:YES];
    });
}

#pragma mark - Instance

- (instancetype)initWithFrame:(CGRect)frame variant:(FluentToastVariant)variant {
    if (self = [super initWithFrame:frame]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AmeTheme surfaceOverlay];
        self.layer.cornerRadius = [AmeTheme radiusM];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.18;   // shadow8 档
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 8.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [AmeTheme divider].CGColor;

        static NSArray<NSString *> *symbols;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            symbols = @[
                @"info.circle.fill",              // neutral
                @"checkmark.circle.fill",         // success
                @"exclamationmark.triangle.fill", // warning
                @"xmark.octagon.fill",            // danger
            ];
        });

        UIColor *accent = [self ame_accentForVariant:variant];
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[variant]]];
        _iconView.tintColor = accent;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [AmeTheme fontButton];
        _titleLabel.textColor = [AmeTheme textPrimary];
        _titleLabel.numberOfLines = 0;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [AmeTheme fontBody2];
        _detailLabel.textColor = [AmeTheme textSecondary];
        _detailLabel.numberOfLines = 0;
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_detailLabel];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _detailLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 2;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:22],
            [_iconView.heightAnchor constraintEqualToConstant:22],
            [stack.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        ]];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ame_tapped:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (UIColor *)ame_accentForVariant:(FluentToastVariant)variant {
    switch (variant) {
        case FluentToastVariantSuccess: return [AmeTheme statusSuccess];
        case FluentToastVariantWarning: return [AmeTheme statusWarning];
        case FluentToastVariantDanger:  return [AmeTheme statusDanger];
        default: return [AmeTheme textSecondary];
    }
}

- (void)ame_tapped:(UITapGestureRecognizer *)sender {
    [self ame_dismissAnimated:YES];
}

- (void)ame_timerFired:(NSTimer *)timer {
    [self ame_dismissAnimated:YES];
}

- (void)ame_dismissAnimated:(BOOL)animated {
    [_timer invalidate];
    if (_ame_currentToast == self) _ame_currentToast = nil;
    if (!animated) { [self removeFromSuperview]; return; }
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeTranslation(0, 12);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end
