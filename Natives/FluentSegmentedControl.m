//
// FluentSegmentedControl.m — fluent2_kit custom_sliding_segmented_control
// 规格的 ObjC 实现
//

#import "FluentSegmentedControl.h"
#import "AmeTheme.h"

static const CGFloat FluentSegmentedHeight     = 32.0;
static const CGFloat FluentSegmentedMinSegment = 64.0;

@implementation FluentSegmentedControl {
    NSArray<UIButton *> *_buttons;
    UIView *_thumb;
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items {
    NSParameterAssert(items.count > 0);
    if (self = [super initWithFrame:CGRectZero]) {
        _enabled = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AmeTheme fillSubtle];        // 轨道 fillSubtle
        self.layer.cornerRadius = [AmeTheme radiusL];        // large 8
        self.layer.cornerCurve = kCACornerCurveContinuous;

        // 滑块 thumb：独立视图，先 addSubview 压在按钮层之下
        _thumb = [[UIView alloc] init];
        _thumb.backgroundColor = [AmeTheme surfaceCard];
        _thumb.layer.cornerRadius = [AmeTheme radiusL];
        _thumb.layer.cornerCurve = kCACornerCurveContinuous;
        // 功能性投影恒黑（shadow2 低仰角档，Fluent 规范阴影不随深浅翻转）
        _thumb.layer.shadowColor = [UIColor blackColor].CGColor;
        _thumb.layer.shadowOpacity = 0.10;
        _thumb.layer.shadowOffset = CGSizeMake(0, 2);
        _thumb.layer.shadowRadius = 4.0;
        [self addSubview:_thumb];

        // 均分 segments：fillEqually 栈 + 内部 UIButton
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        for (NSString *title in items) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            btn.translatesAutoresizingMaskIntoConstraints = NO;
            [btn setTitle:title forState:UIControlStateNormal];
            [btn addTarget:self action:@selector(ame_segmentTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
            [buttons addObject:btn];
        }
        _buttons = buttons;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:_buttons];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        [self ame_applyState];
    }
    return self;
}

#pragma mark - Selection

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [self setSelectedIndex:selectedIndex animated:YES];
}

- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated {
    if (index >= _buttons.count || index == _selectedIndex) return;
    _selectedIndex = index;
    [self ame_applyState];
    [self ame_applyThumbFrameAnimated:animated];
}

- (void)ame_segmentTapped:(UIButton *)sender {
    NSUInteger idx = [_buttons indexOfObject:sender];
    if (idx == NSNotFound || idx == _selectedIndex) return;
    [self setSelectedIndex:idx animated:YES];
    if (self.onChange) self.onChange(idx);
}

#pragma mark - Enabled

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    self.userInteractionEnabled = enabled;
    [self ame_applyState];
}

#pragma mark - Appearance

- (void)ame_applyState {
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        UIButton *btn = _buttons[i];
        if (!_enabled) {
            btn.titleLabel.font = [AmeTheme fontBody];
            [btn setTitleColor:[AmeTheme textTertiary] forState:UIControlStateNormal];
        } else if (i == _selectedIndex) {
            btn.titleLabel.font = [AmeTheme fontButton];     // body1Strong 17sb
            [btn setTitleColor:[AmeTheme textPrimary] forState:UIControlStateNormal];
        } else {
            btn.titleLabel.font = [AmeTheme fontBody];
            [btn setTitleColor:[AmeTheme textSecondary] forState:UIControlStateNormal];
        }
    }
}

// thumb 滑移（UIView animation，iOS 14 安全；frame 手工管理免约束乘数动画）
- (void)ame_applyThumbFrameAnimated:(BOOL)animated {
    CGFloat width = self.bounds.size.width;
    if (width <= 0 || _buttons.count == 0) return;
    CGFloat segmentWidth = width / _buttons.count;
    CGRect frame = CGRectMake(segmentWidth * _selectedIndex, 0.0,
                              segmentWidth, self.bounds.size.height);
    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                                  | UIViewAnimationOptionCurveEaseInOut
                         animations:^{ self->_thumb.frame = frame; }
                         completion:nil];
    } else {
        _thumb.frame = frame;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ame_applyThumbFrameAnimated:NO];
}

// 深浅切换兜底：重算选中/未选中字色（动态色本身自适应，对齐 FluentCard 做法）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self ame_applyState];
    }
}

- (CGSize)intrinsicContentSize {
    CGFloat width = MAX(_buttons.count * FluentSegmentedMinSegment, FluentSegmentedMinSegment);
    return CGSizeMake(width, FluentSegmentedHeight);
}

@end
