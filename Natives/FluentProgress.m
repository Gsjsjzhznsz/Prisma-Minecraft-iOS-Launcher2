//
// FluentProgress.m — fluent2_kit fluent_progress 规格的 ObjC 实现
//

#import "FluentProgress.h"
#import "AmeTheme.h"

static const CGFloat FluentProgressBarHeight   = 3.0;
static const CGFloat FluentProgressRingSize    = 20.0;
static const CGFloat FluentProgressRingLine    = 2.0;

@implementation FluentProgress {
    // Bar
    UIView *_fillView;
    BOOL _barAnimating;
    // Ring
    CAShapeLayer *_ringTrack;   // 全环底
    CAShapeLayer *_ringArc;     // 旋转圆弧
}

- (instancetype)initWithStyle:(FluentProgressStyle)style {
    if (self = [super initWithFrame:CGRectZero]) {
        _style = style;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        if (style == FluentProgressStyleBar) {
            self.backgroundColor = [AmeTheme fillSubtle];    // track
            self.layer.cornerRadius = [AmeTheme radiusS];    // small 2
            self.layer.cornerCurve = kCACornerCurveContinuous;
            self.clipsToBounds = YES;

            _fillView = [[UIView alloc] init];
            _fillView.backgroundColor = [AmeTheme brandPrimary];
            _fillView.layer.cornerRadius = [AmeTheme radiusS];
            _fillView.layer.cornerCurve = kCACornerCurveContinuous;
            [self addSubview:_fillView];                     // frame 手工管理便于动画
        } else {
            _ringTrack = [CAShapeLayer layer];
            _ringTrack.fillColor = nil;
            _ringTrack.lineWidth = FluentProgressRingLine;
            // CGColor 为静态快照，深浅切换在 traitCollectionDidChange 重设
            _ringTrack.strokeColor = [AmeTheme fillSubtle].CGColor;
            [self.layer addSublayer:_ringTrack];

            _ringArc = [CAShapeLayer layer];
            _ringArc.fillColor = nil;
            _ringArc.lineWidth = FluentProgressRingLine;
            _ringArc.lineCap = kCALineCapRound;
            _ringArc.strokeColor = [AmeTheme brandPrimary].CGColor;
            [self.layer addSublayer:_ringArc];

            // 7.0-UI-7 冒烟（run 39592623337）实锤：StackView FILL 分布会把
            // 环横向拉伸（280×20），而弧线半径旧实现取宽/2、圆心在 20pt 高
            // 视图中心，CAShapeLayer 不裁剪 → 巨大圆弧外溢成全屏蓝圈。
            // 双保险：①固定尺寸环抗拉伸/抗压缩 REQUIRED；②ame_layoutRing
            // 半径改取短边（非方 bounds 退化安全，见下方）。
            [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
            [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        }
    }
    return self;
}

#pragma mark - Progress（Bar）

- (void)setProgress:(double)progress {
    [self setProgress:progress animated:YES];
}

- (void)setProgress:(double)progress animated:(BOOL)animated {
    if (_style != FluentProgressStyleBar) return;
    _progress = MIN(MAX(progress, 0.0), 1.0);
    [self ame_applyBarProgress:animated];
}

- (void)ame_applyBarProgress:(BOOL)animated {
    CGFloat width = self.bounds.size.width * _progress;
    CGRect frame = CGRectMake(0.0, 0.0, width, self.bounds.size.height);
    if (animated && width != _fillView.frame.size.width && self.bounds.size.width > 0) {
        _barAnimating = YES;
        [UIView animateWithDuration:0.25
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                                  | UIViewAnimationOptionCurveEaseInOut
                         animations:^{ self->_fillView.frame = frame; }
                         completion:^(BOOL finished) { self->_barAnimating = NO; }];
    } else {
        _fillView.frame = frame;
    }
}

#pragma mark - Running（Ring）

- (void)setRunning:(BOOL)running {
    _running = running;
    if (_style != FluentProgressStyleRing) return;
    if (running) {
        CABasicAnimation *spin =
            [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @(0.0);
        spin.toValue = @(2.0 * M_PI);
        spin.duration = 0.9;
        spin.repeatCount = HUGE_VALF;
        [_ringArc addAnimation:spin forKey:@"ame_spin"];
    } else {
        [_ringArc removeAnimationForKey:@"ame_spin"];
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_style == FluentProgressStyleBar) {
        if (!_barAnimating) [self ame_applyBarProgress:NO];
    } else {
        [self ame_layoutRing];
    }
}

- (void)ame_layoutRing {
    CGRect bounds = self.bounds;
    if (CGRectIsEmpty(bounds)) return;
    CGFloat inset = FluentProgressRingLine / 2.0 + 0.5;
    // 7.0-UI-7：非方 bounds（被外部拉伸）时按短边取正方圆，杜绝溢出；
    // 环常态由 REQUIRED 抗拉伸保证 20×20，此处为防御性兑现
    CGFloat diameter = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) - inset * 2.0;
    if (diameter <= 0) return;
    CGRect circleRect = CGRectMake(CGRectGetMidX(bounds) - diameter / 2.0,
                                   CGRectGetMidY(bounds) - diameter / 2.0,
                                   diameter, diameter);
    _ringTrack.path = [UIBezierPath bezierPathWithOvalInRect:circleRect].CGPath;
    // 270° 圆弧：12 点钟起顺时针至 9 点钟，缺口留在左上象限
    UIBezierPath *arc = [UIBezierPath
        bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
                         radius:diameter / 2.0
                     startAngle:-M_PI_2
                       endAngle:M_PI
                      clockwise:YES];
    _ringArc.path = arc.CGPath;
}

// 深浅切换：Ring 的 CGColor 快照需重设（Bar 侧 UIView 动态色自动刷新，无需处理）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        if (_style == FluentProgressStyleRing) {
            _ringTrack.strokeColor = [AmeTheme fillSubtle].CGColor;
            _ringArc.strokeColor = [AmeTheme brandPrimary].CGColor;
        }
    }
}

- (CGSize)intrinsicContentSize {
    if (_style == FluentProgressStyleBar) {
        return CGSizeMake(UIViewNoIntrinsicMetric, FluentProgressBarHeight);
    }
    return CGSizeMake(FluentProgressRingSize, FluentProgressRingSize);
}

@end
