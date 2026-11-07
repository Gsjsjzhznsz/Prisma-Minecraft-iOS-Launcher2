//
// AmeFlowSelectView.m — ★ Task401：封面流选择器实现（设计契约见 .h 头注释；
//   原 Task393 竖排组件更名并扩展横轴，交互物理 1:1 保留）
//
// ★Task409 恒定尺寸 + 无缝循环槽位复制（第 17 轮复诉四项之三）：
//   ① 「左侧图标缩小依旧」——旧判例 scale = 1 − 0.15×|d| 整体退役，条目
//      尺寸不随位相变化（缩放面是图标缩小与标签变窄的共同根因）；
//   ② 「账号转盘没有无限衔接」——小集合接缝（|d| = 槽数/2 的 remainder
//      跳变点）落在可视窗内 = 跨越时对侧条目瞬移可见；槽位复制把接缝
//      推到窗外，副本由宿主 ame_copyFactory 现建，全链映射回逻辑下标；
//   ③ 窗缘渐隐带：临近可视窗边缘 alpha 线性归零，条目进出窗零突现零突隐。
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

// 远近衰减系数（★Task409 恒定尺寸：缩放系数退役，仅存透明度层级）
// alpha 渐退保留列表层级；窗缘渐隐带使条目进出可视窗零突现零突隐
//（接缝复制槽位从窗缘入窗时 alpha≈0 起步渐显，循环衔接视觉无缝）。
static const CGFloat AmeFlowSelectAlphaPerStep    = 0.25;
static const CGFloat AmeFlowSelectAlphaFloor      = 0.25;
static const CGFloat AmeFlowSelectHideRange       = 2.6;   // |d| > 此值隐藏（可见窗 |d| ≤ 2.4，五枚口径）
static const CGFloat AmeFlowSelectEdgeFadeH       = 1.55;  // ★Task409 横轴可视窗半宽（三项视口同旧口径）
static const CGFloat AmeFlowSelectEdgeFadeBand    = 0.4;   // ★Task409 窗缘渐隐带宽（步距）
static const CGFloat AmeFlowSelectFlickVelocity   = 1400.0; // 惯性判定速度阈值（pt/s）
static const CGFloat AmeFlowSelectSpringStiffness = 180.0;  // 更柔和的原生滚动式收束
static const CGFloat AmeFlowSelectSnapEpsilon     = 0.002;  // 吸附收敛判定（步距比）
static const NSTimeInterval AmeFlowSelectSnapDuration = 0.42; // 程序化滚动时长
/// 账户横列只保留当前项及相邻两项，避免密集的 iPod Cover Flow 观感。
static const CGFloat AmeFlowSelectThreeAcrossDivisor = 2.8;

@interface AmeFlowSelectView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableArray<UIView *> *ame_items;
/// 逻辑条目数（★Task409：ame_items = 槽位 = 逻辑数 × 复制份数；
/// selectedIndex/onSettle/ame_itemsCount 全链按逻辑下标说话）
@property (nonatomic, assign) NSUInteger ame_logicalCount;
// ★Task409 槽位复制工厂 ame_copyFactory（.h 公开声明；.m 内经
// _ame_copyFactory ivar 直取——extension 同款重声明 = 非法（clang 仅允
// readonly→readwrite 升格，CI run 42398735188 实锤），ivar 直取亦天然
// 绕开 task393 审计 B 族 self.ame* 启发式。
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
        // 三项视口：当前项与左右相邻项同时可见。
        CGFloat ame_w = CGRectGetWidth(self.bounds);
        if (ame_w < 1.0) return _itemHeight + _interItemGap;   // 未布局兜底
        return ame_w / AmeFlowSelectThreeAcrossDivisor;
    }
    return self.itemHeight + self.interItemGap;
}

/// ★Task409 可视窗半宽（按轴；ame_layoutItems 隐藏判定与窗缘渐隐共用）
- (CGFloat)ame_windowHalfRange {
    return (self.axis == AmeFlowSelectAxisHorizontal)
        ? AmeFlowSelectEdgeFadeH          // 横轴 1.55（三项视口）
        : AmeFlowSelectHideRange;         // 竖轴 2.6（五枚视口）
}

/// ★Task409 需要的槽位复制份数：槽数 > 2×窗半宽 ⇒ remainder 接缝
/// （|d| = 槽数/2）被推出窗外，跨越跳变不可见 = 无限衔接。
/// 逻辑数 ≤ 1（无对手条目可衔接）或工厂缺席时单份（旧口径）。
- (NSUInteger)ame_requiredCopiesForLogicalCount:(NSUInteger)logicalCount {
    if (logicalCount <= 1 || _ame_copyFactory == nil) return 1;
    NSUInteger ame_copies = 1;
    while ((CGFloat)(ame_copies * logicalCount) <= 2.0 * [self ame_windowHalfRange]
           && ame_copies < 8) {
        ame_copies++;
    }
    return ame_copies;
}

- (CGFloat)viewportHeight {
    return self.itemHeight + 4.0 * [self pitch];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ame_layoutItems];
}

/// 摆位核心：条目按当前位相连续排布（拖动/惯性每帧调用）
/// ★Task409 恒定尺寸：条目尺寸 = 视口满尺寸（缩放判例退役）；层级感由
/// alpha 渐退承接，另加窗缘渐隐带（距窗缘 < 0.4 步距线性归零）。
- (void)ame_layoutItems {
    CGFloat ame_pitch = [self pitch];
    CGFloat ame_absdMax = [self ame_windowHalfRange];

    if (self.axis == AmeFlowSelectAxisHorizontal) {
        CGFloat ame_centerX = CGRectGetMidX(self.bounds);
        CGFloat ame_height = CGRectGetHeight(self.bounds);
        CGFloat ame_itemW = ame_pitch - self.interItemGap;   // 槽宽 = 步距 − 间隙（不重叠）

        [self.ame_items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
            CGFloat ame_d = remainder((CGFloat)i - self.ame_offset,
                                      (CGFloat)self.ame_items.count);
            CGFloat ame_absd = fabs(ame_d);

            if (ame_absd > ame_absdMax || self.bounds.size.width < 1.0) {
                item.hidden = YES;
                return;
            }

            // ★Task409 恒定尺寸：零缩放，图标/标签尺寸全列一致。
            CGFloat ame_alpha = 1.0 - AmeFlowSelectAlphaPerStep * ame_absd;
            if (ame_alpha < AmeFlowSelectAlphaFloor) ame_alpha = AmeFlowSelectAlphaFloor;
            // 窗缘渐隐带：距窗缘 < 0.4 步距线性归零（进出窗零突现零突隐）。
            CGFloat ame_edge = ame_absdMax - ame_absd;
            if (ame_edge < AmeFlowSelectEdgeFadeBand) {
                ame_alpha *= fmax(0.0, ame_edge / AmeFlowSelectEdgeFadeBand);
            }
            if (ame_alpha <= 0.003) {
                item.hidden = YES;
                return;
            }

            // 条目手动摆位（帧驱动口径；条目内部子视图仍 AutoLayout）
            item.frame = CGRectMake(ame_centerX + ame_d * ame_pitch - ame_itemW / 2.0,
                                    0.0,
                                    ame_itemW, ame_height);
            item.hidden = NO;
            item.alpha = ame_alpha;
            item.layer.zPosition = 100.0 - ame_absd;     // 越近居中越在上层
        }];
        return;
    }

    CGFloat ame_centerY = CGRectGetMidY(self.bounds);
    CGFloat ame_width = CGRectGetWidth(self.bounds);

    [self.ame_items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        CGFloat ame_d = remainder((CGFloat)i - self.ame_offset,
                                  (CGFloat)self.ame_items.count);
        CGFloat ame_absd = fabs(ame_d);

        if (ame_absd > ame_absdMax || self.bounds.size.height < 1.0) {
            item.hidden = YES;
            return;
        }

        // ★Task409 恒定尺寸：零缩放（同横轴口径）。
        CGFloat ame_alpha = 1.0 - AmeFlowSelectAlphaPerStep * ame_absd;
        if (ame_alpha < AmeFlowSelectAlphaFloor) ame_alpha = AmeFlowSelectAlphaFloor;
        CGFloat ame_edge = ame_absdMax - ame_absd;
        if (ame_edge < AmeFlowSelectEdgeFadeBand) {
            ame_alpha *= fmax(0.0, ame_edge / AmeFlowSelectEdgeFadeBand);
        }
        if (ame_alpha <= 0.003) {
            item.hidden = YES;
            return;
        }

        // 条目手动摆位（帧驱动口径，见 .h 头注释；条目内部子视图仍 AutoLayout）
        item.frame = CGRectMake(0.0,
                                ame_centerY + ame_d * ame_pitch - self.itemHeight / 2.0,
                                ame_width, self.itemHeight);
        item.hidden = NO;
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

    // ★Task409 槽位装配：ame_items = 槽位（逻辑数 × 复制份数，整数倍）；
    // 逻辑条目数 ≤ 2×窗半宽时复制槽位把 remainder 接缝推出窗外（无缝
    // 循环）；第 2+ 份由宿主 ame_copyFactory 按逻辑下标现建副本，工厂
    // 缺席/返回 nil 则保留已有整倍数份（退化为少份循环，映射仍自洽）。
    self.ame_logicalCount = items.count;
    NSUInteger ame_copies = [self ame_requiredCopiesForLogicalCount:items.count];

    void (^ame_attach)(UIView *) = ^(UIView *ame_v) {
        // 条目接管摆位：关闭 AutoLayout 参与（条目内部子视图不受影响）
        ame_v.translatesAutoresizingMaskIntoConstraints = YES;
        ame_v.userInteractionEnabled = NO;
        [self addSubview:ame_v];
        [self.ame_items addObject:ame_v];
    };
    for (UIView *item in items) {
        ame_attach(item);
    }
    for (NSUInteger ame_c = 1; ame_c < ame_copies; ame_c++) {
        NSMutableArray<UIView *> *ame_copy = [NSMutableArray array];
        BOOL ame_ok = YES;
        for (NSUInteger ame_i = 0; ame_i < items.count; ame_i++) {
            UIView *ame_v = _ame_copyFactory(ame_i);
            if (ame_v == nil) { ame_ok = NO; break; }
            [ame_copy addObject:ame_v];
        }
        if (!ame_ok) break;   // 整倍数纪律：残份不入境，逻辑映射不破
        [ame_copy enumerateObjectsUsingBlock:^(UIView *ame_v, NSUInteger idx, BOOL *stop) {
            ame_attach(ame_v);
        }];
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
    return self.ame_logicalCount;   // ★Task409：宿主守卫按逻辑数（非槽位数）
}

- (NSInteger)selectedIndex {
    if (self.ame_items.count == 0) return NSNotFound;
    NSInteger ame_slot = (NSInteger)lround((double)self.ame_offset);
    NSInteger ame_slots = (NSInteger)self.ame_items.count;
    ame_slot %= ame_slots;
    if (ame_slot < 0) ame_slot += ame_slots;
    // ★Task409 槽位 → 逻辑下标（槽位序 = 逻辑序循环复制，取模即原像）
    NSInteger ame_logical = (NSInteger)self.ame_logicalCount;
    if (ame_logical > 0 && ame_logical < ame_slots) ame_slot %= ame_logical;
    return ame_slot;
}

- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated {
    if (self.ame_items.count == 0) return;
    NSInteger ame_logical = (self.ame_logicalCount > 0)
        ? (NSInteger)self.ame_logicalCount
        : (NSInteger)self.ame_items.count;
    index %= ame_logical;
    if (index < 0) index += ame_logical;

    self.ame_hasSettledIdx = YES;
    self.ame_settledIdx = index;

    // ★Task409：等价槽位（index + k×逻辑数）中取相位距当前最近者，
    // 程序化定位恒走最短弧（0→末项与末项→0 都只移动一格）。
    CGFloat ame_slots = (CGFloat)self.ame_items.count;
    NSUInteger ame_copies = (ame_logical > 0) ? (self.ame_items.count / (NSUInteger)ame_logical) : 1;
    CGFloat ame_bestDelta = 0.0;
    BOOL ame_first = YES;
    for (NSUInteger ame_k = 0; ame_k < ame_copies; ame_k++) {
        CGFloat ame_delta = remainder((CGFloat)(index + (NSInteger)ame_k * ame_logical) - self.ame_offset,
                                      ame_slots);
        if (ame_first || fabs(ame_delta) < fabs(ame_bestDelta)) {
            ame_bestDelta = ame_delta;
            ame_first = NO;
        }
    }
    CGFloat ame_destination = self.ame_offset + ame_bestDelta;
    if (!animated || self.window == nil) {
        self.ame_offset = ame_destination;
        self.ame_target = ame_destination;
        [self ame_stopTicker];
        [self ame_layoutItems];
        return;
    }
    self.ame_target = ame_destination;
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
            // 无边界循环：首尾相接，拖过最后一项继续回到第一项。
            self.ame_offset = ame_raw;
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
            CGFloat ame_dest = round(self.ame_offset) + ame_flick;
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
    NSInteger ame_dest = (NSInteger)lround((double)ame_hit);
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
    if (ame_idx == NSNotFound || (NSInteger)(ame_idx + 1) >= (NSInteger)[self ame_itemsCount]) return;
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
