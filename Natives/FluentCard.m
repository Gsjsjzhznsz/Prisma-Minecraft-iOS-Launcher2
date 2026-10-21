//
// FluentCard.m — fluent2_kit fluent_card 规格的 ObjC 实现
//

#import "FluentCard.h"
#import "AmeTheme.h"

@implementation FluentCard {
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_top;
    NSLayoutConstraint *_bottom;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _fluentClickable = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AmeTheme surfaceCard];
        self.layer.cornerRadius = [AmeTheme radiusL];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [AmeTheme divider].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.08;   // shadow2 低仰角档
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 4.0;

        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentView];

        _leading  = [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12];
        _trailing = [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12];
        _top      = [_contentView.topAnchor constraintEqualToAnchor:self.topAnchor constant:12];
        _bottom   = [_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12];
        [NSLayoutConstraint activateConstraints:@[_leading, _trailing, _top, _bottom]];
    }
    return self;
}

- (void)setFluentEdgeToEdge:(BOOL)fluentEdgeToEdge {
    _fluentEdgeToEdge = fluentEdgeToEdge;
    CGFloat inset = fluentEdgeToEdge ? 0.0 : 12.0;
    _leading.constant = inset;
    _trailing.constant = -inset;
    _top.constant = inset;
    _bottom.constant = -inset;
}

- (void)setFluentClickable:(BOOL)fluentClickable {
    _fluentClickable = fluentClickable;
    if (fluentClickable) {
        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ame_tapped)];
        [self addGestureRecognizer:tap];
    }
}

- (void)ame_tapped {
    // 按压反馈：fillSubtle 短暂反白 + 微缩
    UIView *flash = [[UIView alloc] initWithFrame:self.bounds];
    flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    flash.backgroundColor = [AmeTheme fillSubtle];
    flash.layer.cornerRadius = self.layer.cornerRadius;
    flash.userInteractionEnabled = NO;
    [self addSubview:flash];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [flash removeFromSuperview];
        if (self.fluentTapHandler) self.fluentTapHandler();
    });
}

// 描边/面随深浅自动刷新（CGColor 是静态快照，trait 变化时重设）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.layer.borderColor = [AmeTheme divider].CGColor;
    }
}

@end
