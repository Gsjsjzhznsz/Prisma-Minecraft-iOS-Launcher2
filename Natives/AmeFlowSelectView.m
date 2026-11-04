//
// AmeFlowSelectView.m — ★ Task401：封面流选择器实现（设计契约见 .h 头注释；
//   原 Task393 竖排组件更名并扩展横轴，交互物理 1:1 保留）
//
// 帧驱动：CADisplayLink 弹簧衰减（offset 逼近 target，临界阻尼）；
// 摆位：竖轴条目 center.y = 视口中点 + (i − offset) × 步距，横轴条目
//       center.x 同式；条目按 |d| 缩放/透明（transform 语义经 frame 直算
//       + alpha + zPosition，零约束逐帧更新）；
// 手势：UIPanGestureRecognizer（拖动；末端速度折算惯性弹位；对宿主
//       UIScrollView 平移具有动态优先权）+
//       UITapGestureRecognizer（点按非居中条目 = 定点吸附）+
//       UIAccessibilityTraitAdjustable（VoiceOver 逐枚换选）。
// 红线：iOS 14.0+；零颜色落点；零 viewWithTag；条目 frame 手动摆位。
//

#import "AmeFlowSelectView.h"
#import <math.h>   // lround/fabs/sqrt/fmin（弹簧积分与位相取整）

// 远近衰减系数（封面流口径；连续插值无跳变）
// 选中态以“尺寸带动透明度”：更大的条目必然更不透明。衰减刻意收窄，
// 保留列表的层级而不再像 iPod Cover Flow 一样夸张、跳动。
static const CGFloat AmeFlowSelectScalePerStep    = 0.05;  // 轻微层级，避免 Cover Flow 式跳变
static const CGFloat AmeFlowSelectAlphaFloor      = 0.72;  // 拖拽越界时的可读性下限
static const CGFloat AmeFlowSelectHideRange       = 2.6;   // |d| > 此值隐藏（可见窗 |d| ≤ 2.4，五枚口径）
static const CGFloat AmeFlowSelectRubberBand      = 0.35;  // 越界拖拽阻尼（回弹）
static const CGFloat AmeFlowSelectFlickVelocity   = 1400.0; // 惯性判定速度阈值（pt/s）
static const CGFloat AmeFlowSelectSpringStiffness = 280.0;  // 弹簧刚度（临界阻尼配平；吸附 ~0.35s 收束）
static const CGFloat AmeFlowSelectSnapEpsilon     = 0.002;  // 吸附收敛判定（步距比）
static const NSTimeInterval AmeFlowSelectSnapDuration = 0.42; // 程序化滚动时长
/// 横轴五枚不变式：步距 = 视口宽 ÷ 此值（|d|≤2.4 全部落在视口内）
static const CGFloat AmeFlowSelectFiveAcrossDivisor = 4.8;

@interface AmeFlowSelectView () <UIGestureRecognizerDelegate>
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

@implementation AmeFlowSelectView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _axis = AmeFlowSelectAxisVertical;
        _itemHeight = 58;
        _interItemGap = 10;
        _ame_items = [NSMutableArray array];
        self.clipsToBounds = YES;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        // 文案落点归宿主（主页双滚轮各自 set accessibilityLabel，
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

- (CGFloat)pitch {
    if (self.axis == AmeFlowSelectAxisHorizontal) {
        // 横轴五枚不变式：视口宽 ÷ 4.8（选中 ±2 枚恒在视口内，无重叠）
        CGFloat ame_w = CGRectGetWidth(self.bounds);
        if (ame_w < 1.0) return _itemHeight + _interItemGap;   // 未布局兜底
        return ame_w / AmeFlowSelectFiveAcrossDivisor;
    }
    return self.itemHeight + self.interItemGap;
}

- (CGFloat)viewportHeight {
    return self.itemHeight + 4.0 * [self pitch];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ame_layoutItems];
}

/// 摆位核心：条目按当前位相连续排布（拖动/惯性每帧调用）
- (void)ame_layoutItems {
    CGFloat ame_pitch = [self pitch];
    CGFloat ame_absdMax = AmeFlowSelectHideRange;

    if (self.axis == AmeFlowSelectAxisHorizontal) {
        CGFloat ame_centerX = CGRectGetMidX(self.bounds);
        CGFloat ame_height = CGRectGetHeight(self.bounds);
        CGFloat ame_itemW = ame_pitch - self.interItemGap;   // 槽宽 = 步距 − 间隙（不重叠）

        [self.ame_items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
            CGFloat ame_d = (CGFloat)i - self.ame_offset;
            CGFloat ame_absd = fabs(ame_d);

            if (ame_absd > ame_absdMax || self.bounds.size.width < 1.0) {
                item.hidden = YES;
                return;
            }
            item.hidden = NO;

            // 尺寸与透明度同源：更大即更不透明，且正反两个方向完全对称。
            CGFloat ame_scale = 1.0 - AmeFlowSelectScalePerStep * ame_absd;
            CGFloat ame_alpha = ame_scale;
            if (ame_alpha < AmeFlowSelectAlphaFloor) ame_alpha = AmeFlowSelectAlphaFloor;

            // 条目手动摆位（帧驱动口径；条目内部子视图仍 AutoLayout）
            CGFloat ame_h = ame_height * ame_scale;
            CGFloat ame_w = ame_itemW * ame_scale;
            item.frame = CGRectMake(ame_centerX + ame_d * ame_pitch - ame_w / 2.0,
                                    (ame_height - ame_h) / 2.0,
                                    ame_w, ame_h);
            item.alpha = ame_alpha;
            item.layer.zPosition = 100.0 - ame_absd;     // 越近居中越在上层
        }];
        return;
    }

    CGFloat ame_centerY = CGRectGetMidY(self.bounds);
    CGFloat ame_width = CGRectGetWidth(self.bounds);
    CGFloat ame_half = self.itemHeight / 2.0;

    [self.ame_items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        CGFloat ame_d = (CGFloat)i - self.ame_offset;
        CGFloat ame_absd = fabs(ame_d);

        if (ame_absd > ame_absdMax || self.bounds.size.height < 1.0) {
            item.hidden = YES;
            return;
        }
        item.hidden = NO;

        // 尺寸与透明度同源：不再出现“越往上越不透明”的方向性错觉。
        CGFloat ame_scale = 1.0 - AmeFlowSelectScalePerStep * ame_absd;
        CGFloat ame_alpha = ame_scale;
        if (ame_alpha < AmeFlowSelectAlphaFloor) ame_alpha = AmeFlowSelectAlphaFloor;

        // 条目手动摆位（帧驱动口径，见 .h 头注释；条目内部子视图仍 AutoLayout）
        CGFloat ame_h = self.itemHeight * ame_scale;
        CGFloat ame_w = ame_width * ame_scale;
        item.frame = CGRectMake((ame_width - ame_w) / 2.0,
                                ame_centerY + ame_d * ame_pitch - ame_h / 2.0,
                                ame_w, ame_h);
        item.alpha = ame_alpha;
        item.layer.zPosition = 100.0 - ame_absd;     // 越近居中越在上层
    }];
}

#pragma mark - 公开 API

- (void)configureItems:(NSArray<UIView *> *)items {
    for (UIView *item in self.ame_items) {
        [item removeFromSuperview];
    }
    [self.ame_items removeAllObjects];
    [self ame_stopTicker];

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

- (NSUInteger)ame_itemsCount {
    return (NSUInteger)self.ame_items.count;
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
        CGPoint ame_vel = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        if (self.axis == AmeFlowSelectAxisHorizontal) {
            // 只认横向为主的拖动（纵向滑动让给宿主滚动视图）
            return fabs(ame_vel.x) > fabs(ame_vel.y);
        }
        // 只认纵向为主的拖动（横向滑动让给宿主滚动视图）
        return fabs(ame_vel.y) > fabs(ame_vel.x);
    }
    return YES;
}

// ★ Task401 手势优先级：本组件平移手势 对 宿主 UIScrollView 平移手势
//   具有优先权（动态失败要求语义：滚动视图的 pan 必须等本 pan 先失败）——
//   滚轮上的拖动恒给滚轮（修复 Task400 版本滚轮被宿主滚动抢走 =「只能
//   拖动再回弹」的手势竞争根因）；滚轮外的触摸本 pan 不参与，宿主照常滚动。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] &&
        [otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
        return YES;
    }
    return NO;
}

- (void)ame_handlePan:(UIPanGestureRecognizer *)pan {
    BOOL ame_horizontal = (self.axis == AmeFlowSelectAxisHorizontal);
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            [self ame_stopTicker];
            self.ame_velocity = 0.0;
            self.ame_dragStartOffset = self.ame_offset;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat ame_dDrag = ame_horizontal
                ? [pan translationInView:self].x
                : [pan translationInView:self].y;
            CGFloat ame_raw = self.ame_dragStartOffset - ame_dDrag / [self pitch];
            // 越界橡皮筋（两端阻尼回弹）
            CGFloat ame_max = (CGFloat)(self.ame_items.count - 1);
            if (ame_raw < 0.0) {
                self.ame_offset = ame_raw * AmeFlowSelectRubberBand;
            } else if (ame_raw > ame_max) {
                self.ame_offset = ame_max + (ame_raw - ame_max) * AmeFlowSelectRubberBand;
            } else {
                self.ame_offset = ame_raw;
            }
            self.ame_target = self.ame_offset;
            [self ame_layoutItems];
            break;
        }
        default: {
            // 结束/取消：速度折算惯性弹位后吸附最近条目
            CGFloat ame_v = ame_horizontal
                ? [pan velocityInView:self].x
                : [pan velocityInView:self].y;
            CGFloat ame_flick = 0.0;
            if (fabs(ame_v) > AmeFlowSelectFlickVelocity) {
                ame_flick = (ame_v > 0.0) ? -1.0 : 1.0;
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
    BOOL ame_horizontal = (self.axis == AmeFlowSelectAxisHorizontal);
    // 点按位置 → 位相反解（点哪枚吸哪枚；点居中条目 = 重选自己 = 落定不回调）
    CGFloat ame_hit;
    if (ame_horizontal) {
        ame_hit = self.ame_offset + (ame_pt.x - CGRectGetMidX(self.bounds)) / [self pitch];
    } else {
        ame_hit = self.ame_offset + (ame_pt.y - CGRectGetMidY(self.bounds)) / [self pitch];
    }
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
    // dt 尖峰钳制（后台恢复/主线程卡顿恢复时显式积分爆炸防御）
    if (ame_dt > 0.05) ame_dt = 0.05;

    // 临界阻尼弹簧（无过冲；到达即停 = 吸附手感）
    CGFloat ame_gap = self.ame_target - self.ame_offset;
    self.ame_velocity += AmeFlowSelectSpringStiffness * ame_gap * (CGFloat)ame_dt;
    self.ame_velocity *= (CGFloat)(1.0 - fmin(1.0, 2.0 * sqrt(AmeFlowSelectSpringStiffness) * ame_dt));
    self.ame_offset += self.ame_velocity * (CGFloat)ame_dt;

    [self ame_layoutItems];

    if (fabs(self.ame_target - self.ame_offset) < AmeFlowSelectSnapEpsilon
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
    if (!self.ame_hasSettledIdx || ame_idx != self.ame_settledIdx) {
        self.ame_hasSettledIdx = YES;
        self.ame_settledIdx = ame_idx;
        if (self.onSettle) self.onSettle(ame_idx);
    }
}

#pragma mark - VoiceOver（可调节条目：逐枚换选）

// 协议签名为 - (void)（UIAccessibilityAction；CI 实锤返回类型冲突热修）
- (void)accessibilityIncrement {
    NSInteger ame_idx = self.selectedIndex;
    if (ame_idx == NSNotFound || (NSUInteger)(ame_idx + 1) >= self.ame_items.count) return;
    [self setSelectedIndex:ame_idx + 1 animated:YES];
    [self ame_commitSettle];
}

- (void)accessibilityDecrement {
    NSInteger ame_idx = self.selectedIndex;
    if (ame_idx == NSNotFound || ame_idx <= 0) return;
    [self setSelectedIndex:ame_idx - 1 animated:YES];
    [self ame_commitSettle];
}

@end
