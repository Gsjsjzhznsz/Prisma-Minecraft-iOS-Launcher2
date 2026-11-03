//
// AmeIpodFlowView.m — ★ Task393：iPod 式竖排封面流实现（设计契约见 .h 头注释）
//
// 帧驱动：CADisplayLink 弹簧衰减（offset 逼近 target，临界阻尼）；
// 摆位：条目 center.y = 视口中点 + (i − offset) × 步距，条目按 |d| 缩放/
// 透明（transform + alpha + zPosition，零约束逐帧更新）；
// 手势：UIPanGestureRecognizer（拖动；末端速度折算惯性弹位）+
//       UITapGestureRecognizer（点按非居中条目 = 定点吸附）+
//       UIAccessibilityTraitAdjustable（VoiceOver 上下滑逐枚换选）。
// 红线：iOS 14.0+；零颜色落点；零 viewWithTag；条目 frame 手动摆位。
//

#import "AmeIpodFlowView.h"

// 远近衰减系数（iPod 封面流口径；连续插值无跳变）
static const CGFloat AmeIpodFlowScalePerStep    = 0.15;  // scale = 1 − 0.15×|d|
static const CGFloat AmeIpodFlowAlphaPerStep    = 0.32;  // alpha = 1 − 0.32×|d|
static const CGFloat AmeIpodFlowAlphaFloor      = 0.28;  // 最远可见透明度下限
static const CGFloat AmeIpodFlowVisibleRange    = 2.4;   // |d| ≤ 此值可见（五枚口径）
static const CGFloat AmeIpodFlowHideRange       = 2.6;   // |d| > 此值隐藏
static const CGFloat AmeIpodFlowRubberBand      = 0.35;  // 越界拖拽阻尼（回弹）
static const CGFloat AmeIpodFlowFlickVelocity   = 1400.0; // 惯性判定速度阈值（pt/s）
static const CGFloat AmeIpodFlowSpringStiffness = 90.0;   // 弹簧刚度（临界阻尼配平）
static const CGFloat AmeIpodFlowSnapEpsilon     = 0.002;  // 吸附收敛判定（步距比）
static const NSTimeInterval AmeIpodFlowSnapDuration = 0.42; // 程序化滚动时长

@interface AmeIpodFlowView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableArray<UIView *> *ame_items;
/// 连续位相（居中条目 = round(offset)；拖动/惯性中连续变化）
@property (nonatomic, assign) CGFloat ame_offset;
/// 弹簧目标（吸附落点；拖动中 = 拖动位相）
@property (nonatomic, assign) CGFloat ame_target;
@property (nonatomic, assign) CGFloat ame_velocity;
@property (nonatomic, strong, nullable) CADisplayLink *ame_displayLink;
@property (nonatomic, assign) CGFloat ame_lastTick;
@property (nonatomic, assign) BOOL ame_hasSettledIdx;  // 落定下标有效性（0 条目 = 无效）
@property (nonatomic, assign) NSInteger ame_settledIdx;
@property (nonatomic, assign) CGFloat ame_dragStartOffset;
@end

@implementation AmeIpodFlowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _itemHeight = 58;
        _interItemGap = 10;
        _ame_items = [NSMutableArray array];
        self.clipsToBounds = YES;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        // 文案落点归宿主（账户页/版本选择各自 set accessibilityLabel，
        // 复用宿主既有 i18n 键，本组件零词条纪律）

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(ame_handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(ame_handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc {
    [self ame_stopTicker];
}

#pragma mark - 布局

- (CGFloat)ame_pitch {
    return self.itemHeight + self.interItemGap;
}

- (CGFloat)viewportHeight {
    return self.itemHeight + 4.0 * [self ame_pitch];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ame_layoutItems];
}

/// 摆位核心：条目按当前位相连续排布（拖动/惯性每帧调用）
- (void)ame_layoutItems {
    CGFloat ame_centerY = CGRectGetMidY(self.bounds);
    CGFloat ame_width = CGRectGetWidth(self.bounds);
    CGFloat ame_pitch = [self ame_pitch];
    CGFloat ame_half = self.itemHeight / 2.0;

    [self.ame_items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        CGFloat ame_d = (CGFloat)i - self.ame_offset;
        CGFloat ame_absd = fabs(ame_d);

        if (ame_absd > AmeIpodFlowHideRange || self.bounds.size.height < 1.0) {
            item.hidden = YES;
            return;
        }
        item.hidden = NO;

        // 远近衰减：选中（d=0）= 正常大小全不透明；越远越小越透明（连续插值）
        CGFloat ame_scale = 1.0 - AmeIpodFlowScalePerStep * ame_absd;
        CGFloat ame_alpha = 1.0 - AmeIpodFlowAlphaPerStep * ame_absd;
        if (ame_alpha < AmeIpodFlowAlphaFloor) ame_alpha = AmeIpodFlowAlphaFloor;

        // 条目手动摆位（帧驱动口径，见 .h 头注释；条目内部子视图仍 AutoLayout）
        CGFloat ame_h = self.itemHeight * ame_scale;
        CGFloat ame_w = ame_width * ame_scale;
        item.frame = CGRectMake((ame_width - ame_w) / 2.0,
                                ame_centerY + ame_d * ame_pitch - ame_h / 2.0,
                                ame_w, ame_h);
        item.alpha = ame_alpha;
        item.zPosition = 100.0 - ame_absd;             // 越近居中越在上层
    }];
}

#pragma mark - 公开 API

- (void)configureItems:(NSArray<UIView *> *)items {
    for (UIView *item in self.ame_items) {
        [item removeFromSuperview];
    }
    [self.ame_items removeAllObjects];
    [self.ame_stopTicker];

    for (UIView *item in items) {
        // 条目接管摆位：关闭 AutoLayout 参与（条目内部子视图不受影响）
        item.translatesAutoresizingMaskIntoConstraints = YES;
        item.userInteractionEnabled = NO;
        [self addSubview:item];
        [self.ame_items addObject:item];
    }

    if (self.ame_items.count == 0) {
        self.ame_offset = 0.0;
        self.ame_target = 0.0;
        self.ame_hasSettledIdx = NO;
        [self ame_layoutItems];
        return;
    }

    // 初始落定 = 0（宿主随即 setSelectedIndex: 定位到当前选中）
    self.ame_offset = 0.0;
    self.ame_target = 0.0;
    self.ame_hasSettledIdx = YES;
    self.ame_settledIdx = 0;
    [self ame_layoutItems];
}

- (NSInteger)selectedIndex {
    if (self.ame_items.count == 0) return NSNotFound;
    NSInteger ame_idx = (NSInteger)lround((double)self.ame_offset);
    if (ame_idx < 0) ame_idx = 0;
    if ((NSUInteger)ame_idx >= self.ame_items.count) ame_idx = (NSInteger)self.ame_items.count - 1;
    return ame_idx;
}

- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated {
    if (self.ame_items.count == 0) return;
    if (index < 0) index = 0;
    if ((NSUInteger)index >= self.ame_items.count) index = (NSInteger)self.ame_items.count - 1;

    self.ame_hasSettledIdx = YES;
    self.ame_settledIdx = index;

    if (!animated || self.window == nil) {
        self.ame_offset = (CGFloat)index;
        self.ame_target = (CGFloat)index;
        [self ame_stopTicker];
        [self ame_layoutItems];
        return;
    }
    self.ame_target = (CGFloat)index;
    self.ame_velocity = 0.0;
    [self ame_startTicker];
}

#pragma mark - 手势

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.interactionLocked || self.ame_items.count == 0) return NO;
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        // 只认纵向为主的拖动（横向滑动让给宿主滚动视图）
        CGPoint ame_vel = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return fabs(ame_vel.y) > fabs(ame_vel.x);
    }
    return YES;
}

- (void)ame_handlePan:(UIPanGestureRecognizer *)pan {
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            [self ame_stopTicker];
            self.ame_velocity = 0.0;
            self.ame_dragStartOffset = self.ame_offset;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat ame_dy = [pan translationInView:self].y;
            CGFloat ame_raw = self.ame_dragStartOffset - ame_dy / [self ame_pitch];
            // 越界橡皮筋（两端阻尼回弹）
            CGFloat ame_max = (CGFloat)(self.ame_items.count - 1);
            if (ame_raw < 0.0) {
                self.ame_offset = ame_raw * AmeIpodFlowRubberBand;
            } else if (ame_raw > ame_max) {
                self.ame_offset = ame_max + (ame_raw - ame_max) * AmeIpodFlowRubberBand;
            } else {
                self.ame_offset = ame_raw;
            }
            self.ame_target = self.ame_offset;
            [self ame_layoutItems];
            break;
        }
        default: {
            // 结束/取消：速度折算惯性弹位后吸附最近条目
            CGFloat ame_vy = [pan velocityInView:self].y;
            CGFloat ame_flick = 0.0;
            if (fabs(ame_vy) > AmeIpodFlowFlickVelocity) {
                ame_flick = (ame_vy > 0.0) ? -1.0 : 1.0;
            }
            NSInteger ame_maxIdx = (NSInteger)self.ame_items.count - 1;
            CGFloat ame_dest = round(self.ame_offset) + ame_flick;
            if (ame_dest < 0.0) ame_dest = 0.0;
            if (ame_dest > (CGFloat)ame_maxIdx) ame_dest = (CGFloat)ame_maxIdx;
            self.ame_target = ame_dest;
            self.ame_velocity = 0.0;
            [self ame_startTicker];
            break;
        }
    }
}

- (void)ame_handleTap:(UITapGestureRecognizer *)tap {
    if (self.interactionLocked || self.ame_items.count == 0) return;
    CGPoint ame_pt = [tap locationInView:self];
    CGFloat ame_centerY = CGRectGetMidY(self.bounds);
    // 点按位置 → 位相反解（点哪枚吸哪枚；点居中条目 = 重选自己 = 落定不回调）
    CGFloat ame_hit = self.ame_offset + (ame_pt.y - ame_centerY) / [self ame_pitch];
    NSInteger ame_maxIdx = (NSInteger)self.ame_items.count - 1;
    NSInteger ame_dest = (NSInteger)lround((double)ame_hit);
    if (ame_dest < 0) ame_dest = 0;
    if (ame_dest > ame_maxIdx) ame_dest = ame_maxIdx;
    self.ame_target = (CGFloat)ame_dest;
    self.ame_velocity = 0.0;
    [self ame_startTicker];
}

#pragma mark - 弹簧吸附（CADisplayLink 临界阻尼逼近）

- (void)ame_startTicker {
    if (self.ame_displayLink) return;
    self.ame_displayLink = [CADisplayLink displayLinkWithTarget:self
                                                       selector:@selector(ame_tick:)];
    self.ame_lastTick = 0.0;
    [self.ame_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                               forMode:NSRunLoopCommonModes];
}

- (void)ame_stopTicker {
    [self.ame_displayLink invalidate];
    self.ame_displayLink = nil;
}

- (void)ame_tick:(CADisplayLink *)link {
    if (self.ame_lastTick <= 0.0) {
        self.ame_lastTick = link.timestamp;
        return;
    }
    NSTimeInterval ame_dt = link.timestamp - self.ame_lastTick;
    self.ame_lastTick = link.timestamp;
    if (ame_dt <= 0.0) ame_dt = 1.0 / 60.0;

    // 临界阻尼弹簧（无过冲；到达即停 = 吸附手感）
    CGFloat ame_gap = self.ame_target - self.ame_offset;
    self.ame_velocity += AmeIpodFlowSpringStiffness * ame_gap * (CGFloat)ame_dt;
    self.ame_velocity *= (CGFloat)(1.0 - fmin(1.0, 2.0 * sqrt(AmeIpodFlowSpringStiffness) * ame_dt));
    self.ame_offset += self.ame_velocity * (CGFloat)ame_dt;

    [self ame_layoutItems];

    if (fabs(self.ame_target - self.ame_offset) < AmeIpodFlowSnapEpsilon
        && fabs(self.ame_velocity) < 0.02) {
        self.ame_offset = self.ame_target;
        self.ame_velocity = 0.0;
        [self ame_stopTicker];
        [self ame_layoutItems];
        [self ame_commitSettle];
    }
}

/// 落定提交：下标与上次落定不同才回调（拖到哪里选中哪里的提交点）
- (void)ame_commitSettle {
    NSInteger ame_idx = self.selectedIndex;
    if (!self.ame_settledIndex || ame_idx != self.ame_settledIdx) {
        self.ame_hasSettledIdx = YES;
        self.ame_settledIdx = ame_idx;
        if (self.onSettle) self.onSettle(ame_idx);
    }
}

#pragma mark - VoiceOver（可调节条目：上下滑逐枚换选）

- (BOOL)accessibilityIncrement {
    NSInteger ame_idx = self.selectedIndex;
    if (ame_idx == NSNotFound || (NSUInteger)(ame_idx + 1) >= self.ame_items.count) return NO;
    [self setSelectedIndex:ame_idx + 1 animated:YES];
    [self ame_commitSettle];
    return YES;
}

- (BOOL)accessibilityDecrement {
    NSInteger ame_idx = self.selectedIndex;
    if (ame_idx == NSNotFound || ame_idx <= 0) return NO;
    [self setSelectedIndex:ame_idx - 1 animated:YES];
    [self ame_commitSettle];
    return YES;
}

@end
