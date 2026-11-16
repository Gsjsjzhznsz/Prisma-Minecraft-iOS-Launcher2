//
// ZL2AnimationKit.h — MD3 动效体系（★Task429：PDF 第五版 §9.2 + 第六版 §3.2.2
// 「MD3 动画体系」全局杠杆落地）
//
// 定位：ZL2 域动效统一供给层，四个全局杠杆一次成型——
//
//   ① ZL2MotionTransition  自定义 push/pop 转场器（UINavigationControllerDelegate，
//                          退场 fade+下移 70ms、进场 spring 错峰 350ms；
//                          消除「应用像网页跳转」观感的单点接入）
//   ② ZL2MotionHaptics     CoreHaptics 轻触觉（light/medium；engine 懒加载复用，
//                          CHHapticEngine 不可用降级 UIImpactFeedbackGenerator；
//                          尊重 control.mod_touch_vibrate_enable 开关——内部读
//                          PLPreferences 只读链路 LauncherPreferences.getPrefBool，
//                          与 ControlButton/SurfaceViewController 同口径）
//   ③ ZL2MotionList        列表入场 helper（reloadData 后可见行按 indexPath
//                          递增 20ms 延迟 alpha+8pt 上移归位；同批防重入）
//   ④ ZL2MotionShimmer     CAGradientLayer 循环骨架光（Shimmer 组件）
//
// 时长常量（第六版 §3.2.2 动效时长常量化：快/标准/慢三档）：
//   kAme429MotionFast      0.15（高频微动：chip 选中、状态变化）
//   kAme429MotionStandard  0.25（常规过渡：壳层切页、列表入场）
//   kAme429MotionSlow      0.40（强调入场：弹层、大容器）
//   kAme429MotionExit      0.07（转场退场档：fade+下移 70ms，表 9-1）
//   kAme429MotionStagger   0.07（转场错峰档：退场→进场延迟 70ms，表 9-1）
//
// MotionScheme.expressive → UISpringTimingParameters damping 0.8 档（转场
//   进场 spring 与 PressableCard 回弹共用同一阻尼档，全域手感一致）。
//
// 红线同 ZL2 域：颜色一律 ZL2Theme 动态令牌（零硬编码 UIColor、零 trait
//   分支）；iOS 14.0 API 上限；reduceMotion 全链尊重（开启即无动效直落，
//   绝不把内容留在不可见态——守卫只跳过动画，不改动可见性终态）。
//
// ⚠️ 新 TU：ZL2AnimationKit.m 需主控注册 Natives/CMakeLists.txt 源列表
//   （Task429 工位 429-E 报备；CMakeLists.txt 属本工位禁改清单）。
//   CoreHaptics 依赖 clang autolink（lld LC_LINKER_OPTION）；若主控构建
//   关闭 autolink，需在链接面追加 -framework CoreHaptics。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 动效时长档（第六版 §3.2.2 常量化）

/// 快档 0.15（高频微动）
FOUNDATION_EXPORT const NSTimeInterval kAme429MotionFast;
/// 标准档 0.25（常规过渡）
FOUNDATION_EXPORT const NSTimeInterval kAme429MotionStandard;
/// 慢档 0.40（强调入场）
FOUNDATION_EXPORT const NSTimeInterval kAme429MotionSlow;
/// 转场退场档 0.07（fade+下移 70ms，表 9-1）
FOUNDATION_EXPORT const NSTimeInterval kAme429MotionExit;
/// 转场错峰档 0.07（退场→进场延迟 70ms，表 9-1）
FOUNDATION_EXPORT const NSTimeInterval kAme429MotionStagger;
/// expressive 档弹簧阻尼 0.8（表 9-1 MotionScheme.expressive；全域共用）
FOUNDATION_EXPORT const CGFloat kAme429SpringDamping;

#pragma mark - ① 自定义 push/pop 转场器（全局杠杆一次接入）

/// UINavigationControllerDelegate 转场器（push/pop 两态）。
/// 接入方式二选一：
///   a) 一行接入：+installOnNavigationController:onDidShow:（delegate 弱引用
///      由 objc 关联对象保活，随 nav 存活；壳层多子 nav 批量挂最省）；
///   b) 手动持有：nav.delegate = motion（宿主须强持有本实例）。
@interface ZL2MotionTransition : NSObject <UINavigationControllerDelegate>

/// 进场 spring 时长（默认 0.35，表 9-1「进场 spring 错峰 350ms」）
@property (nonatomic, assign) NSTimeInterval enterDuration;

/// 旁挂 didShow（转场器占用 delegate 位后，壳层顶栏刷新等既有 delegate
/// 消费方经此转发；nav/已显示 VC/animated 原样透传，nil 安全）
@property (nonatomic, copy, nullable) void (^onDidShow)(UINavigationController *nav,
                                                        UIViewController *viewController,
                                                        BOOL animated);

/// 一次接入：挂到 nav（弱引用 delegate 保活 + onDidShow 旁挂转发）
+ (void)installOnNavigationController:(UINavigationController *)nav
                            onDidShow:(nullable void (^)(UINavigationController *nav,
                                                         UIViewController *viewController,
                                                         BOOL animated))onDidShow;

@end

#pragma mark - ② CoreHaptics 轻触觉

/// 轻触觉统一出口（light = 轻点/按压触发起手、medium = 确认/触发动作）。
/// CoreHaptics 引擎懒加载进程级复用；设备/引擎不可用时降级
/// UIImpactFeedbackGenerator（ControlButton ame428 同款静态复用预热）。
/// 总开关：control.mod_touch_vibrate_enable（关闭即全程静默）。
@interface ZL2MotionHaptics : NSObject

/// 轻触觉（CHHapticEvent intensity 0.5 transient / 降级 Light impact）
+ (void)light;
/// 确认触觉（CHHapticEvent intensity 0.8 transient / 降级 Medium impact）
+ (void)medium;

/// 触觉偏好总开关现读（PLPreferences 只读链路；组件内部已门控，
/// 宿主如需预判可自查）
+ (BOOL)hapticsEnabled;

@end

#pragma mark - ③ 列表入场 helper

/// 列表入场动画（reloadData 之后调用）：可见 cell 按 indexPath 递增 20ms
/// 延迟，alpha 0→1 + 8pt 上移归位（表 9-1「列表入场」行）。
/// 同批防重入：上一批次未播完的窗口内重复调用幂等跳过（进刷数据源连发
/// reloadData 不重摆）。reduceMotion / 视图未挂窗 / 空列表 → 直落不动画
/// （绝不预置不可见态）。错峰延迟封顶 0.30s（长列表尾不拖沓）。
@interface ZL2MotionList : NSObject

/// UITableView 入场（reloadData 后一行调用）
+ (void)animateEntranceOfTableView:(UITableView *)tableView;
/// UICollectionView 入场（reloadData 后一行调用）
+ (void)animateEntranceOfCollectionView:(UICollectionView *)collectionView;

@end

#pragma mark - ④ CAGradientLayer 循环骨架光

/// Shimmer 组件：宿主视图盖一层高光扫过循环（CAGradientLayer 平移循环）。
/// 颜色走 ZL2Theme onSurface 透明度档（浅/深自动）；stopAnimating 彻底
/// 摘除动画（不留挂空 CADisplayLink/CAAnimation）。
@interface ZL2MotionShimmer : UIView

/// 循环周期（默认 1.2s）
@property (nonatomic, assign) NSTimeInterval cycleDuration;

- (void)startAnimating;
- (void)stopAnimating;
@property (nonatomic, assign, getter=isAnimating, readonly) BOOL animating;

/// 便捷盖层：挂到宿主（autoresizing 随宿主铺满，宿主需 clipsToBounds）
+ (instancetype)shimmerAttachedToView:(UIView *)hostView;

@end

NS_ASSUME_NONNULL_END
