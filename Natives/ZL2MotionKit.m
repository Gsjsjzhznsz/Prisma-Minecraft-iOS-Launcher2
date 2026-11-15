//
// ZL2MotionKit.m — MD3 动效体系实现（★Task429：第五版 §9.2 + 第六版 §3.2.2
// 全局杠杆）
//
// 移植对照（第五版表 9-1 / 第六版 §3.2.2）：
//   - 页面转场 → UIViewControllerAnimatedTransitioning 自定义 push/pop：
//       退场 fade+下移 70ms（kAme429MotionExit）、进场 spring 错峰 350ms
//       （UISpringTimingParameters damping 0.8 + kAme429MotionStagger 70ms
//       错峰，delayFactor = 70/350 恰为一档错峰）；总时长 = 0.07+0.35；
//   - 列表入场 → reloadData 后按 indexPath 递增 20ms 延迟 alpha+8pt 上移；
//   - 按压缩放+触觉 → PressableCard（ZL2M3Kit ⑦，缩放 0.94~0.97 档 +
//       ZL2MotionHaptics light）；Chip 选中 expandIn → transform scale +
//       spring（ZL2M3Kit ② 扩展）；
//   - MotionScheme.expressive → UISpringTimingParameters damping 0.8 档；
//   - Shimmer → CAGradientLayer 循环骨架（本文件 ④）。
//
// 防御守卫原则（第六版 N1/N2 判例：写了守卫漏实现 = 静默失效，宁可
// fail-loud NSLog）：转场上下文缺 from/to VC 直接 NSLog + 立即
// completeTransition（绝不把 nav 卡死在转场中）；CoreHaptics 引擎创建/
// 启动失败 NSLog 原因并真降级 UIImpactFeedbackGenerator；触觉总开关关闭
// 是产品语义静默，不属于该判例范畴。
//
// 红线：颜色一律 ZL2Theme 动态令牌；iOS 14.0 API 上限；reduceMotion 全链
// 尊重（开启即直落无动画，不预置不可见态）。
//

#import "ZL2MotionKit.h"
#import "ZL2Theme.h"
#import "LauncherPreferences.h"   // getPrefBool：PLPreferences 只读链路（触觉总开关）
#import <CoreHaptics/CoreHaptics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - 时长常量

const NSTimeInterval kAme429MotionFast = 0.15;      // 快
const NSTimeInterval kAme429MotionStandard = 0.25;  // 标准
const NSTimeInterval kAme429MotionSlow = 0.40;      // 慢
const NSTimeInterval kAme429MotionExit = 0.07;      // 转场退场档（fade+下移 70ms）
const NSTimeInterval kAme429MotionStagger = 0.07;   // 转场错峰档（退场→进场 70ms）

// expressive 档弹簧阻尼（表 9-1：MotionScheme.expressive → damping 0.8；
// 转场进场 spring 与 ZL2M3Kit PressableCard/Chip expandIn 共用同一档）
const CGFloat kAme429SpringDamping = 0.8;

// 进场默认 spring 时长（表 9-1「进场 spring 错峰 350ms」）
static const NSTimeInterval kAme429EnterDefault = 0.35;

#pragma mark - ① ZL2MotionTransition

// 转场执行体（单类两态：operation 决定 push/pop 方向语义）
@interface ZL2MotionAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, assign) UINavigationControllerOperation operation;
@property (nonatomic, assign) NSTimeInterval enterDuration;
// 进场 property animator（nav 控制器持有本执行体直至 completeTransition，
// 挂为属性保活防半途释放——运行中 animator 无人持有会被提前中断）
@property (nonatomic, strong, nullable) UIViewPropertyAnimator *enterAnimator;
@end

@implementation ZL2MotionAnimator

- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)transitionContext {
    // 总时长 = 错峰 + 进场 spring（退场 70ms 与错峰并行，不叠加）
    return kAme429MotionStagger + _enterDuration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toVC = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    // 防御守卫（fail-loud + 真实现：立即收尾，nav 绝不卡死转场中）
    if (!fromVC || !toVC || !fromVC.view || !toVC.view) {
        NSLog(@"[ZL2Motion] Task429 transition context missing from/to VC (from=%@ to=%@) — complete immediately",
              fromVC, toVC);
        [transitionContext completeTransition:YES];
        return;
    }

    UIView *containerView = [transitionContext containerView];
    UIView *fromView = fromVC.view;
    UIView *toView = toVC.view;
    BOOL pushing = (_operation == UINavigationControllerOperationPush);

    // z 序：push 进场视图盖顶；pop 进场视图垫底（系统 pop 层级语义）——
    // reduceMotion 快速淡入路径同样需要（否则 pop 的进场页不入容器）
    if (pushing) {
        [containerView addSubview:toView];
    } else if (fromView.superview == containerView) {
        [containerView insertSubview:toView belowSubview:fromView];
    } else {
        [containerView addSubview:toView];
    }

    // reduceMotion → 快速交叉淡入淡出直落（辅助功能语义：跳过位移/spring）
    if (UIAccessibilityIsReduceMotionEnabled()) {
        toView.alpha = 0.0;
        [UIView animateWithDuration:kAme429MotionFast animations:^{
            toView.alpha = 1.0;
        } completion:^(BOOL finished) {
            [transitionContext completeTransition:YES];
        }];
        return;
    }

    // 进场初始态：alpha 0 + 水平错位（push 自右、pop 自左，12% 幅度）
    CGFloat enterOffset = containerView.bounds.size.width * 0.12;
    toView.alpha = 0.0;
    toView.transform = CGAffineTransformMakeTranslation(pushing ? enterOffset : -enterOffset, 0.0);
    // 退场终态：fade + 下移（表 9-1「退场 fade+下移 70ms」）
    CGAffineTransform exitTransform = CGAffineTransformMakeTranslation(0.0, 16.0);

    // 退场：70ms 快退（fade+下移）
    [UIView animateWithDuration:kAme429MotionExit
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        fromView.alpha = 0.0;
        fromView.transform = exitTransform;
    } completion:nil];

    // 进场：错峰 70ms 后 spring 350ms 归位（MotionScheme.expressive damping 0.8）
    // ★Task429-r1 热修（dev/smoke CI 实录）：+springTimingWithDampingRatio: 类
    //   方法在本 SDK 不存在（no known class method）——改 alloc/initWithDampingRatio:
    //   实名实例方法（Apple 文档面，同义同参）。
    UISpringTimingParameters *spring =
        [[UISpringTimingParameters alloc] initWithDampingRatio:kAme429SpringDamping];
    UIViewPropertyAnimator *enter =
        [[UIViewPropertyAnimator alloc] initWithDuration:_enterDuration timingParameters:spring];
    [enter addAnimations:^{
        toView.alpha = 1.0;
        toView.transform = CGAffineTransformIdentity;
    } delayFactor:kAme429MotionStagger / MAX(_enterDuration, 0.001)];
    __weak id<UIViewControllerContextTransitioning> weakCtx = transitionContext;
    UIView *ame429_exitView = fromView;
    [enter addCompletion:^(UIViewAnimatingPosition finalPosition) {
        // 退场页状态复位（VC 若被宿主持有复用——如缓存导航栈——不留残态）
        ame429_exitView.alpha = 1.0;
        ame429_exitView.transform = CGAffineTransformIdentity;
        [weakCtx completeTransition:YES];
    }];
    self.enterAnimator = enter;
    [enter startAnimation];
}

@end

@implementation ZL2MotionTransition

- (instancetype)init {
    self = [super init];
    if (self) {
        _enterDuration = kAme429EnterDefault;
    }
    return self;
}

// 关联对象键（install 保活 delegate 实例——UINavigationController.delegate
// 是弱引用，宿主不显式持有时由本关联兜底，随 nav 生命周期消亡）
static void *kAme429MotionDelegateKey = &kAme429MotionDelegateKey;

+ (void)installOnNavigationController:(UINavigationController *)nav
                            onDidShow:(void (^)(UINavigationController *, UIViewController *, BOOL))onDidShow {
    if (!nav) {
        NSLog(@"[ZL2Motion] Task429 installOnNavigationController nil nav — skipped");
        return;
    }
    ZL2MotionTransition *transition = [[ZL2MotionTransition alloc] init];
    transition.onDidShow = onDidShow;
    objc_setAssociatedObject(nav, kAme429MotionDelegateKey, transition, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nav.delegate = transition;
}

- (nullable id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                   animationControllerForOperation:(UINavigationControllerOperation)operation
                                                fromViewController:(UIViewController *)fromVC
                                                  toViewController:(UIViewController *)toVC {
    if (operation != UINavigationControllerOperationPush &&
        operation != UINavigationControllerOperationPop) {
        return nil;   // None/未知操作交还系统默认
    }
    ZL2MotionAnimator *animator = [[ZL2MotionAnimator alloc] init];
    animator.operation = operation;
    animator.enterDuration = _enterDuration;
    return animator;
}

- (void)navigationController:(UINavigationController *)navigationController
      didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    // 旁挂转发：壳层顶栏刷新等既有 delegate 消费方语义不变
    if (self.onDidShow) self.onDidShow(navigationController, viewController, animated);
}

@end

#pragma mark - ② ZL2MotionHaptics

// 引擎进程级单例（懒加载复用；停止态下次 fire 时重启）
static CHHapticEngine *s_ame429HapticEngine = nil;
// 降级生成器进程级复用（ControlButton ame428 同款：dispatch_once 预热，绝不随触摸新建）
static UIImpactFeedbackGenerator *s_ame429ImpactLight = nil;
static UIImpactFeedbackGenerator *s_ame429ImpactMedium = nil;
static dispatch_once_t s_ame429ImpactOnce;
static dispatch_once_t s_ame429EngineOnce;
static BOOL s_ame429CoreHapticsAvailable = NO;

@implementation ZL2MotionHaptics

+ (BOOL)hapticsEnabled {
    // PLPreferences 只读链路（LauncherPreferences.getPrefBool → pref.getObject），
    // 与 ControlButton/SurfaceViewController 同一开关同一口径
    return getPrefBool(@"control.mod_touch_vibrate_enable");
}

// CoreHaptics 可用性（进程级一次判定；不可用 = 老设备/系统限制，真降级路径）
// ★Task429-r1 热修（smoke CI 实录）：CHHapticCapabilities 类/
//   capabilitiesForType:error:/CHHapticCapabilityTypeHaptics 三者在本 SDK 均
//   未声明（use of undeclared identifier × 3）——能力探测改用引擎创建探针：
//   [CHHapticEngine alloc] initAndReturnError: 成败本身就是设备能力判据
//   （创建成功 = 支持；失败 fail-loud 降级），探针引擎直接转正为进程级
//   引擎零浪费。isAutoShutdownEnabled setter 实名 setAutoShutdownEnabled:
//   （原 setIsAutoShutdownEnabled: 系虚构族）；state/CHHapticEngineStateRunning
//   两符号同样未声明——停止态重启简化为每次 startAndReturnError:（幂等）。
+ (BOOL)ame429_supportsCoreHaptics {
    dispatch_once(&s_ame429EngineOnce, ^{
        NSError *initError = nil;
        CHHapticEngine *probe = [[CHHapticEngine alloc] initAndReturnError:&initError];
        s_ame429CoreHapticsAvailable = (probe != nil);
        if (!s_ame429CoreHapticsAvailable) {
            NSLog(@"[ZL2Motion] Task429 CoreHaptics engine unavailable: %@ — fallback to UIImpactFeedbackGenerator",
                  initError);
        } else {
            // 探针引擎转正（进程级复用，不自动关停）
            s_ame429HapticEngine = probe;
            s_ame429HapticEngine.autoShutdownEnabled = NO;
        }
    });
    return s_ame429CoreHapticsAvailable;
}

// 引擎懒加载 + 停止态重启（失败 NSLog + NO = 调用方走降级）
+ (BOOL)ame429_ensureEngineRunning {
    if (!s_ame429HapticEngine) {
        NSError *initError = nil;
        s_ame429HapticEngine = [[CHHapticEngine alloc] initAndReturnError:&initError];
        if (!s_ame429HapticEngine) {
            NSLog(@"[ZL2Motion] Task429 CHHapticEngine init failed: %@ — fallback to UIImpactFeedbackGenerator",
                  initError);
            return NO;
        }
        s_ame429HapticEngine.autoShutdownEnabled = NO;   // 进程级复用，不自动关停
    }
    // ★Task429-r1 热修：state/CHHapticEngineStateRunning 在本 SDK 未声明——
    //   停止态重启改每次 startAndReturnError:（运行态再 start 幂等无副作用）。
    NSError *startError = nil;
    BOOL started = [s_ame429HapticEngine startAndReturnError:&startError];
    if (!started) {
        NSLog(@"[ZL2Motion] Task429 CHHapticEngine start failed: %@ — fallback to UIImpactFeedbackGenerator",
              startError);
        s_ame429CoreHapticsAvailable = NO;
        s_ame429HapticEngine = nil;
        return NO;
    }
    return YES;
}

+ (void)ame429_fireTransientIntensity:(float)intensity {
    if (![self ame429_ensureEngineRunning]) {
        [self ame429_fireImpactIntensity:intensity];
        return;
    }
    NSError *paramError = nil;
    CHHapticEventParameter *intensityParam =
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                      value:intensity];
    CHHapticEvent *event =
        [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                      parameters:@[ intensityParam ]
                                     relativeTime:0.0];
    CHHapticPattern *pattern =
        [[CHHapticPattern alloc] initWithEvents:@[ event ] parameters:@[] error:&paramError];
    if (!pattern) {
        NSLog(@"[ZL2Motion] Task429 CHHapticPattern build failed: %@ — fallback", paramError);
        [self ame429_fireImpactIntensity:intensity];
        return;
    }
    NSError *playerError = nil;
    id<CHHapticPatternPlayer> player =
        [s_ame429HapticEngine createPlayerWithPattern:pattern error:&playerError];
    if (!player) {
        NSLog(@"[ZL2Motion] Task429 CHHapticPatternPlayer create failed: %@ — fallback", playerError);
        [self ame429_fireImpactIntensity:intensity];
        return;
    }
    NSError *playError = nil;
    BOOL played = [player startAtTime:0.0 error:&playError];
    if (!played) {
        NSLog(@"[ZL2Motion] Task429 haptic play failed: %@ — fallback", playError);
        [self ame429_fireImpactIntensity:intensity];
    }
}

// 真降级路径：UIImpactFeedbackGenerator 静态复用 + prepare 预热
+ (void)ame429_fireImpactIntensity:(float)intensity {
    dispatch_once(&s_ame429ImpactOnce, ^{
        s_ame429ImpactLight = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        s_ame429ImpactMedium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [s_ame429ImpactLight prepare];
        [s_ame429ImpactMedium prepare];
    });
    if (intensity > 0.6) {
        [s_ame429ImpactMedium impactOccurred];
    } else {
        [s_ame429ImpactLight impactOccurred];
    }
}

+ (void)light {
    if (![self hapticsEnabled]) return;
    if ([self ame429_supportsCoreHaptics]) {
        [self ame429_fireTransientIntensity:0.5];
    } else {
        [self ame429_fireImpactIntensity:0.5];
    }
}

+ (void)medium {
    if (![self hapticsEnabled]) return;
    if ([self ame429_supportsCoreHaptics]) {
        [self ame429_fireTransientIntensity:0.8];
    } else {
        [self ame429_fireImpactIntensity:0.8];
    }
}

@end

#pragma mark - ③ ZL2MotionList

@implementation ZL2MotionList

// 同批防重入：上一批次播完前（= 末行错峰 + 单格时长）重复调用幂等跳过。
// 进程级窗口足够——入场景本就是全局节奏（两列表同时入场叠播无意义）。
static CFTimeInterval s_ame429ListBatchUntil = 0.0;

// 错峰延迟：按 indexPath 递增 20ms，封顶 0.30s（长列表尾不拖沓）
static NSTimeInterval Ame429ListStaggerDelay(NSUInteger row) {
    return MIN((CGFloat)row * 0.02, 0.30);
}

// 单格入场：alpha 0→1 + 8pt 上移归位（标准档 ease-out）
static void Ame429ListAnimateCell(UIView *cellView, NSTimeInterval delay) {
    cellView.alpha = 0.0;
    cellView.transform = CGAffineTransformMakeTranslation(0.0, 8.0);
    [UIView animateWithDuration:kAme429MotionStandard
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        cellView.alpha = 1.0;
        cellView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        cellView.alpha = 1.0;
        cellView.transform = CGAffineTransformIdentity;
    }];
}

// 批次窗口登记 + 同批判重（先判后记；返回 YES = 本批放行）
static BOOL Ame429ListBeginBatch(NSUInteger visibleCount) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now < s_ame429ListBatchUntil) return NO;   // 同批防重入
    CFTimeInterval batchSpan = Ame429ListStaggerDelay(visibleCount) + kAme429MotionStandard;
    s_ame429ListBatchUntil = now + batchSpan + 0.05;   // 50ms 余量覆盖 completion
    return YES;
}

+ (void)animateEntranceOfTableView:(UITableView *)tableView {
    if (!tableView) return;
    // 守卫语义（N1/N2：守卫必须配真实现）：reduceMotion / 未挂窗 / 空列表
    // 直落「不动画」，绝不预置不可见态——本方法入口先判，_alpha/transform
    // 只在放行后才置位。
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (!tableView.window) return;
    NSArray<NSIndexPath *> *visible = tableView.indexPathsForVisibleRows;
    if (visible.count == 0) return;
    if (!Ame429ListBeginBatch(visible.count)) return;

    // indexPath 升序错峰（reload 后可见行即入场批次）
    NSArray<NSIndexPath *> *sorted =
        [visible sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
            if (a.section != b.section) return (NSComparisonResult)(a.section > b.section ? 1 : -1);
            return (NSComparisonResult)(a.row > b.row ? 1 : (a.row < b.row ? -1 : 0));
        }];
    for (NSUInteger idx = 0; idx < sorted.count; idx++) {
        NSIndexPath *indexPath = sorted[idx];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        Ame429ListAnimateCell(cell, Ame429ListStaggerDelay(idx));
    }
}

+ (void)animateEntranceOfCollectionView:(UICollectionView *)collectionView {
    if (!collectionView) return;
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (!collectionView.window) return;
    NSArray<NSIndexPath *> *visible = collectionView.indexPathsForVisibleItems;
    if (visible.count == 0) return;
    if (!Ame429ListBeginBatch(visible.count)) return;

    NSArray<NSIndexPath *> *sorted =
        [visible sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
            if (a.section != b.section) return (NSComparisonResult)(a.section > b.section ? 1 : -1);
            return (NSComparisonResult)(a.item > b.item ? 1 : (a.item < b.item ? -1 : 0));
        }];
    for (NSUInteger idx = 0; idx < sorted.count; idx++) {
        NSIndexPath *indexPath = sorted[idx];
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        if (!cell) continue;
        Ame429ListAnimateCell(cell, Ame429ListStaggerDelay(idx));
    }
}

@end

#pragma mark - ④ ZL2MotionShimmer

@interface ZL2MotionShimmer ()
@property (nonatomic, strong) CAGradientLayer *ame429BandLayer;   // 高光带（2×宽，平移循环）
@end

@implementation ZL2MotionShimmer

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _cycleDuration = 1.2;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.masksToBounds = YES;   // 高光带越界裁切（扫过观感）
        self.userInteractionEnabled = NO;

        _ame429BandLayer = [CAGradientLayer layer];
        _ame429BandLayer.startPoint = CGPointMake(0.0, 0.5);
        _ame429BandLayer.endPoint = CGPointMake(1.0, 0.5);
        [self.layer addSublayer:_ame429BandLayer];
        [self ame429_refreshColors];
    }
    return self;
}

// 令牌配色：onSurface 三档透明（底/高光/底），浅深主题跟随
//（colorWithAlphaComponent 会塌缩动态色——先按当前 trait 落定再叠 alpha，
// traitCollectionDidChange 重刷）
- (void)ame429_refreshColors {
    UITraitCollection *traits = self.traitCollection;
    UIColor *base = [[ZL2Theme onSurface] resolvedColorWithTraitCollection:traits];
    // 三档 alpha：0.03 / 0.14 / 0.03（骨架光典型对比档）
    UIColor *low = [base colorWithAlphaComponent:0.03];
    UIColor *mid = [base colorWithAlphaComponent:0.14];
    _ame429BandLayer.colors = @[ (id)low.CGColor, (id)mid.CGColor, (id)low.CGColor ];
    _ame429BandLayer.locations = @[ @0.0, @0.5, @1.0 ];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // ★Task429-r1 热修：hasDifferentColorAppearanceComparedTo: 在 Xcode 26.3/
    //   iPhoneOS26.2 SDK 下 no visible @interface（Task379-r1 判例同族，iOS 17
    //   trait 注册 API 世代被 SDK 软移除）——正解 = userInterfaceStyle 直比
    //   （iOS 12 稳定面，语义等价仅明暗变化即刷；previous nil 不误发）。
    if (previousTraitCollection != nil &&
        self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
        [self ame429_refreshColors];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 高光带 2×宽（左缘对齐），translation.x 从 -宽 → 0 扫过：高光中心
    // 自左缘走到右缘，一个循环一次扫过
    CGFloat bandWidth = MAX(self.bounds.size.width * 2.0, 1.0);
    _ame429BandLayer.frame = CGRectMake(0.0, 0.0, bandWidth, self.bounds.size.height);
    if (self.animating) [self ame429_installCycleAnimation];   // 尺寸变更重装循环
}

- (void)ame429_installCycleAnimation {
    [_ame429BandLayer removeAnimationForKey:@"ame429ShimmerCycle"];
    CGFloat travel = -MAX(self.bounds.size.width, 1.0);
    CABasicAnimation *sweep =
        [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    sweep.fromValue = @(travel);
    sweep.toValue = @(0.0);
    sweep.duration = _cycleDuration;
    sweep.repeatCount = HUGE_VALF;
    [_ame429BandLayer addAnimation:sweep forKey:@"ame429ShimmerCycle"];
}

- (void)startAnimating {
    [self layoutIfNeeded];
    [self ame429_installCycleAnimation];
}

- (void)stopAnimating {
    [_ame429BandLayer removeAnimationForKey:@"ame429ShimmerCycle"];
}

- (BOOL)isAnimating {
    return [_ame429BandLayer animationForKey:@"ame429ShimmerCycle"] != nil;
}

+ (instancetype)shimmerAttachedToView:(UIView *)hostView {
    ZL2MotionShimmer *shimmer = [[ZL2MotionShimmer alloc] initWithFrame:CGRectZero];
    // 便捷挂层走 frame/autoresizing 语义（初始化默认 translates=NO 面向约束
    // 消费方；此处显式翻开，autoresizing 随宿主铺满才生效）
    shimmer.translatesAutoresizingMaskIntoConstraints = YES;
    shimmer.frame = hostView.bounds;
    shimmer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [hostView addSubview:shimmer];
    return shimmer;
}

// 离窗摘动画（防离屏空转；回窗由宿主按需 startAnimating）
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopAnimating];
}

@end
