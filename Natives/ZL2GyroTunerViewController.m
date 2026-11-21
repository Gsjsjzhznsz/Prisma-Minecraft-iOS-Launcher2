//
// ZL2GyroTunerViewController.m — ★Task436 陀螺仪游戏内实时调参浮层实现
//
// 组件口径：ZL2Theme 令牌（本 TU 自包含，无 ZL2M3Kit 依赖——对齐
// ZL2ThemeCustomSheet 判例）。七行参数控件每次改动即时写偏好 + 热应用：
//   setPref*(general.gyro_*) → [GyroInput ame436_applyCurrentPreferences]
//   → CMMotionManager 采样率/平滑窗口/反转乘子当场生效（游戏进行中
//   SurfaceViewController tick 直发视角增量，拖动即体感）。
//
// 挂载模式：统一进度页家族（PLTaskProgressViewController）——iPhone
// PageSheet 近全屏模态 / iPad FormSheet 居中卡片；+presentFrom: 沿
// presented 链上溯（ZL2ThemeCustomSheet ame429_presentFromViewController
// 同判例），host 为 nil 时回退 keyWindow 顶层。游戏内入口由主控接
// SurfaceViewController 菜单（本浮层不触碰该文件——属主隔离）。
//

#import "ZL2GyroTunerViewController.h"

#import "ZL2Theme.h"
#import "input/GyroInput.h"
#import "LauncherPreferences.h"   // getPref*/setPref*（新键注册见 PLPreferences.m general 节 ★Task436 注记）
#import "utils.h"                 // localize

#pragma mark - 常量实名表（★Task436）

// 七参数键（general.gyro_* 单族——Task432 键族 + Task436 平滑双键；
// 与 PLPreferences.m general 节注册逐字一致）
static NSString * const Ame436TunerKeyEnable       = @"general.gyro_enable";
static NSString * const Ame436TunerKeySensitivity  = @"general.gyro_sensitivity";
static NSString * const Ame436TunerKeyInvertX      = @"general.gyro_invert_x";
static NSString * const Ame436TunerKeyInvertY      = @"general.gyro_invert_y";
static NSString * const Ame436TunerKeySampleRate   = @"general.gyro_sample_rate";
static NSString * const Ame436TunerKeySmoothEnable = @"general.gyro_smooth_enable";
static NSString * const Ame436TunerKeySmoothWindow = @"general.gyro_smooth_window";

// 参数域（与 GyroInput.m AME436_GYRO_* 域常量同源；浮层侧独立具名防越界 UI 档）
static const NSInteger Ame436TunerSensMin       = 25;    // ★Task436 下限 50→25 对齐 ZL2
static const NSInteger Ame436TunerSensMax       = 300;
static const NSInteger Ame436TunerRateMin       = 5;     // Hz
static const NSInteger Ame436TunerRateMax       = 50;
static const NSInteger Ame436TunerWindowMin     = 2;     // 滑动均值样本数
static const NSInteger Ame436TunerWindowMax     = 10;
static const NSInteger Ame436TunerWindowDefault = 4;     // 契约默认（旧 smoothing=30 等价窗口）

// 几何刻度（M3/壳层判例同族）
static const CGFloat Ame436TunerInset       = 20.0;
static const CGFloat Ame436TunerPad         = 16.0;
static const CGFloat Ame436TunerStackGap    = 18.0;
static const CGFloat Ame436TunerBadgeWidth  = 76.0;
static const CGFloat Ame436TuneriPadWidth   = 480.0;
static const CGFloat Ame436TuneriPadHeight  = 520.0;

@interface ZL2GyroTunerViewController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
// 行状态登记（tag → 索引；写侧闭包与徽章/后缀按索引反查，无行子类）
@property (nonatomic, strong) NSMutableArray<UILabel *> *sliderBadges;
@property (nonatomic, strong) NSMutableArray<NSString *> *sliderSuffixes;
@property (nonatomic, strong) NSMutableArray<void (^)(NSInteger)> *sliderWriters;
@property (nonatomic, strong) NSMutableArray<NSString *> *switchKeys;
@end

@implementation ZL2GyroTunerViewController

#pragma mark - 生命周期

- (instancetype)init {
    self = [super init];
    if (self) {
        _sliderBadges = [NSMutableArray array];
        _sliderSuffixes = [NSMutableArray array];
        _sliderWriters = [NSMutableArray array];
        _switchKeys = [NSMutableArray array];
        self.title = localize(@"ame436.gyro.title", @"陀螺仪实时调参");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surfaceContainerHigh];

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    self.stack = [[UIStackView alloc] init];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = Ame436TunerStackGap;
    [self.scroll addSubview:self.stack];

    // ── 即时生效说明（游戏内调参体验差异点：无需退出重进）──
    UILabel *hint = [[UILabel alloc] init];
    hint.text = localize(@"ame436.gyro.hint", @"七项参数改动即时生效，收起浮层即可体感验证");
    hint.font = [ZL2Theme fontLabelMedium];
    hint.textColor = [ZL2Theme onSurfaceVariant];
    hint.numberOfLines = 0;
    [self.stack addArrangedSubview:hint];

    // ── 七参数行（顺序 = 报告口径：开关/灵敏度/采样率/平滑开关+窗口/双轴反转）──
    //   现值回显读 PLPreferences plist（getPref*），缺键/越界按契约默认；
    //   写走 setPref*（Setter 只写已注册键——Task436 双键已注册）。
    [self ame436_addSwitchRowWithTitle:localize(@"ame436.gyro.enable", @"陀螺仪")
                                   key:Ame436TunerKeyEnable];
    [self ame436_addSliderRowWithTitle:localize(@"ame436.gyro.sensitivity", @"灵敏度")
                              minimum:Ame436TunerSensMin
                              maximum:Ame436TunerSensMax
                                suffix:@"%"
                             initValue:[self ame436_echoSensitivity]
                            writeBlock:^(NSInteger value) {
                                setPrefFloat(Ame436TunerKeySensitivity, (float)value);
                            }];
    [self ame436_addSliderRowWithTitle:localize(@"ame436.gyro.sample_rate", @"采样率")
                              minimum:Ame436TunerRateMin
                              maximum:Ame436TunerRateMax
                                suffix:@" Hz"
                             initValue:[self ame436_echoSampleRate]
                            writeBlock:^(NSInteger value) {
                                setPrefFloat(Ame436TunerKeySampleRate, (float)value);
                            }];
    [self ame436_addSwitchRowWithTitle:localize(@"ame436.gyro.smooth_enable", @"平滑")
                                   key:Ame436TunerKeySmoothEnable];
    [self ame436_addSliderRowWithTitle:localize(@"ame436.gyro.smooth_window", @"平滑窗口")
                              minimum:Ame436TunerWindowMin
                              maximum:Ame436TunerWindowMax
                                suffix:localize(@"ame449.gyro.samples_suffix", @" 样本")
                             initValue:[self ame436_echoSmoothWindow]
                            writeBlock:^(NSInteger value) {
                                setPrefInt(Ame436TunerKeySmoothWindow, value);
                            }];
    [self ame436_addSwitchRowWithTitle:localize(@"ame436.gyro.invert_x", @"反转 X 轴")
                                   key:Ame436TunerKeyInvertX];
    [self ame436_addSwitchRowWithTitle:localize(@"ame436.gyro.invert_y", @"反转 Y 轴")
                                   key:Ame436TunerKeyInvertY];

    // 关闭钮（导航条左上；收起 = 回游戏，参数已即时生效无需确认页）
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                             target:self
                             action:@selector(ame436_closeTapped)];
    self.navigationItem.leftBarButtonItem = closeItem;

    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor
                                             constant:Ame436TunerInset],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor
                                                constant:-Ame436TunerInset],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor
                                                 constant:Ame436TunerInset],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor
                                               constant:-2.0 * Ame436TunerInset],
    ]];
}

#pragma mark - 便捷呈现（统一进度页式浮层挂载）

// host 链上溯（ZL2ThemeCustomSheet ame429_presentFromViewController 同判例）；
// host 为 nil 回退 keyWindow 顶层（PLTaskProgressViewController
// +presentForTaskId pl_topMostViewController 同判例）。
+ (void)presentFrom:(UIViewController *)host {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentFrom:host];
        });
        return;
    }
    UIViewController *ame436_target = host;
    if (ame436_target == nil) {
        UIWindow *ame436_keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *ame436_scene in UIApplication.sharedApplication.connectedScenes) {
                if (ame436_scene.activationState == UISceneActivationStateForegroundActive) {
                    ame436_keyWindow = ame436_scene.windows.firstObject;
                    break;
                }
            }
        }
        if (!ame436_keyWindow) {
            ame436_keyWindow = UIApplication.sharedApplication.windows.firstObject;
        }
        ame436_target = ame436_keyWindow.rootViewController;
        if (ame436_target == nil) return;   // 防御守卫（窗口未就绪）
    }
    while (ame436_target.presentedViewController != nil &&
           !ame436_target.presentedViewController.isBeingDismissed) {
        ame436_target = ame436_target.presentedViewController;
    }
    ZL2GyroTunerViewController *ame436_vc = [[ZL2GyroTunerViewController alloc] init];
    UINavigationController *ame436_nav =
        [[UINavigationController alloc] initWithRootViewController:ame436_vc];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // iPad：FormSheet 居中卡片（统一进度页同款）
        ame436_nav.modalPresentationStyle = UIModalPresentationFormSheet;
        ame436_nav.preferredContentSize = CGSizeMake(Ame436TuneriPadWidth, Ame436TuneriPadHeight);
    } else {
        // iPhone：PageSheet 近全屏模态（统一进度页同款）
        ame436_nav.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    [ame436_target presentViewController:ame436_nav animated:YES completion:nil];
}

#pragma mark - 现值回显（缺键/越界按契约默认）

- (NSInteger)ame436_echoSensitivity {
    NSInteger ame436_v = (NSInteger)getPrefFloat(Ame436TunerKeySensitivity);
    if (ame436_v < Ame436TunerSensMin || ame436_v > Ame436TunerSensMax) ame436_v = 100;
    return ame436_v;
}

- (NSInteger)ame436_echoSampleRate {
    id ame436_obj = getPrefObject(Ame436TunerKeySampleRate);
    NSInteger ame436_v = ame436_obj ? (NSInteger)lroundf([ame436_obj floatValue]) : 20;
    if (ame436_v < Ame436TunerRateMin || ame436_v > Ame436TunerRateMax) ame436_v = 20;
    return ame436_v;
}

- (NSInteger)ame436_echoSmoothWindow {
    id ame436_obj = getPrefObject(Ame436TunerKeySmoothWindow);
    NSInteger ame436_v = ame436_obj ? [ame436_obj integerValue] : Ame436TunerWindowDefault;
    if (ame436_v < Ame436TunerWindowMin || ame436_v > Ame436TunerWindowMax) ame436_v = Ame436TunerWindowDefault;
    return ame436_v;
}

#pragma mark - 行构建

// 开关行：标题 + UISwitch；改动即写偏好 + 热应用（tag = switchKeys 索引）
- (void)ame436_addSwitchRowWithTitle:(NSString *)title key:(NSString *)key {
    UILabel *ame436_label = [[UILabel alloc] init];
    ame436_label.text = title;
    ame436_label.font = [ZL2Theme fontBodyLarge];
    ame436_label.textColor = [ZL2Theme onSurface];

    UISwitch *ame436_switch = [[UISwitch alloc] init];
    ame436_switch.onTintColor = [ZL2Theme primary];
    [ame436_switch setOn:getPrefBool(key) animated:NO];
    ame436_switch.tag = (NSInteger)self.switchKeys.count;
    [ame436_switch addTarget:self
                      action:@selector(ame436_switchChanged:)
            forControlEvents:UIControlEventValueChanged];
    [self.switchKeys addObject:[key copy]];

    UIStackView *ame436_row = [[UIStackView alloc] init];
    ame436_row.translatesAutoresizingMaskIntoConstraints = NO;
    ame436_row.axis = UILayoutConstraintAxisHorizontal;
    ame436_row.alignment = UIStackViewAlignmentCenter;
    ame436_row.spacing = Ame436TunerPad;
    [ame436_row addArrangedSubview:ame436_label];
    UIView *ame436_spacer = [[UIView alloc] init];
    [ame436_row addArrangedSubview:ame436_spacer];
    [ame436_row addArrangedSubview:ame436_switch];
    [self.stack addArrangedSubview:ame436_row];
    [NSLayoutConstraint activateConstraints:@[
        [ame436_row.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];
}

// 滑条行：标题 + [UISlider | 数值徽章]；拖动每 tick 写偏好 + 热应用
// （ZL2SettingRowSlider 每 tick 回调同判例；tag = 滑条登记索引）
- (void)ame436_addSliderRowWithTitle:(NSString *)title
                            minimum:(NSInteger)minimum
                            maximum:(NSInteger)maximum
                              suffix:(NSString *)suffix
                           initValue:(NSInteger)initValue
                          writeBlock:(void (^)(NSInteger))writeBlock {
    UILabel *ame436_label = [[UILabel alloc] init];
    ame436_label.text = title;
    ame436_label.font = [ZL2Theme fontBodyLarge];
    ame436_label.textColor = [ZL2Theme onSurface];

    UILabel *ame436_badge = [[UILabel alloc] init];
    ame436_badge.font = [ZL2Theme fontLabelLarge];
    ame436_badge.textColor = [ZL2Theme primary];
    ame436_badge.textAlignment = NSTextAlignmentRight;
    ame436_badge.text = [NSString stringWithFormat:@"%ld%@", (long)initValue, suffix];

    UISlider *ame436_slider = [[UISlider alloc] init];
    ame436_slider.minimumValue = (float)minimum;
    ame436_slider.maximumValue = (float)maximum;
    ame436_slider.value = (float)initValue;
    ame436_slider.tintColor = [ZL2Theme primary];
    ame436_slider.tag = (NSInteger)self.sliderWriters.count;
    [ame436_slider addTarget:self
                      action:@selector(ame436_sliderChanged:)
            forControlEvents:UIControlEventValueChanged];
    [self.sliderBadges addObject:ame436_badge];
    [self.sliderSuffixes addObject:[suffix copy]];
    [self.sliderWriters addObject:[writeBlock copy]];

    UIStackView *ame436_head = [[UIStackView alloc] init];
    ame436_head.translatesAutoresizingMaskIntoConstraints = NO;
    ame436_head.axis = UILayoutConstraintAxisHorizontal;
    ame436_head.alignment = UIStackViewAlignmentCenter;
    ame436_head.spacing = Ame436TunerPad;
    [ame436_head addArrangedSubview:ame436_label];
    UIView *ame436_spacer = [[UIView alloc] init];
    [ame436_head addArrangedSubview:ame436_spacer];
    [ame436_head addArrangedSubview:ame436_badge];

    UIStackView *ame436_row = [[UIStackView alloc] init];
    ame436_row.translatesAutoresizingMaskIntoConstraints = NO;
    ame436_row.axis = UILayoutConstraintAxisVertical;
    ame436_row.spacing = 8.0;
    [ame436_row addArrangedSubview:ame436_head];
    [ame436_row addArrangedSubview:ame436_slider];
    [self.stack addArrangedSubview:ame436_row];
    [NSLayoutConstraint activateConstraints:@[
        [ame436_badge.widthAnchor constraintGreaterThanOrEqualToConstant:Ame436TunerBadgeWidth],
    ]];
}

#pragma mark - 交互（改动即写偏好 + 即时生效）

// 开关改动：写 bool → 热应用（灵敏度 0 = 停采样的语义在 GyroInput 侧）
- (void)ame436_switchChanged:(UISwitch *)sender {
    NSInteger ame436_index = sender.tag;
    if (ame436_index < 0 || (NSUInteger)ame436_index >= self.switchKeys.count) return;   // 防御守卫
    setPrefBool(self.switchKeys[ame436_index], sender.on);
    [GyroInput ame436_applyCurrentPreferences];
}

// 滑条改动：round + 夹取（UISlider 自身 min/max 即合法域）→ 写偏好 → 热应用
- (void)ame436_sliderChanged:(UISlider *)sender {
    NSInteger ame436_index = sender.tag;
    if (ame436_index < 0 || (NSUInteger)ame436_index >= self.sliderWriters.count) return;   // 防御守卫
    NSInteger ame436_value = (NSInteger)roundf(sender.value);
    if (ame436_value < (NSInteger)sender.minimumValue) ame436_value = (NSInteger)sender.minimumValue;
    if (ame436_value > (NSInteger)sender.maximumValue) ame436_value = (NSInteger)sender.maximumValue;
    UILabel *ame436_badge = self.sliderBadges[ame436_index];
    ame436_badge.text = [NSString stringWithFormat:@"%ld%@", (long)ame436_value,
                         self.sliderSuffixes[ame436_index]];
    self.sliderWriters[ame436_index](ame436_value);
    [GyroInput ame436_applyCurrentPreferences];
}

- (void)ame436_closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
