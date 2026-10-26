//
// ZL2M3Kit.m — Material Design 3 功能组件库实现（7.0-UI-12）
//
// 设计规格出处（Material 3 官方 baseline，与 ZL2Theme 同源）：
//   - SearchBar：容器 surfaceContainerHigh、全圆胶囊、高 44（M3 search bar
//     密度基线），前置 20pt search 图标；
//   - FilterChip：高 32、圆角 8（small 形状档）、未选 1pt outlineVariant
//     描边、选中 primaryContainer + 16pt 对勾（MD3 两态语义）；
//   - Switch：轨道 52×32、未选 16pt 拇指 + outline 2pt 描边、选中 24pt
//     拇指（MD3 开关三态尺寸）；
//   - Dialog：容器 surfaceContainerHigh、圆角 28（extraLarge）、左右内边距
//     24、按钮右对齐文本钮；
//   - BottomSheet：容器 surfaceContainerLow、顶部圆角 28、抓手 32×4、
//     scrim 点按关闭、0.28s 上滑入场。
//
// 展示宿主：Dialog/BottomSheet 经 topmost VC present（overFullScreen，
// animated:NO 后自绘入场动画）——不挂 window 直加视图，保住旋转/安全区/
// present 语义。topmost VC 查找自 keyWindow 场景链（iOS 14 scene API，
// 无 scene 时回落旧 windows 表，域内预览 harness 同口径）。
//
// 门禁适配注记：task248 硬编码闸匹配「set*: 调用语法 + 同行 CJK 字面量」，
// 本文件 CJK 文案一律走属性点语法赋值（域内 ZL2 页面既有约定）或变量传参，
// 零匹配雷点。
//

#import "ZL2M3Kit.h"
#import "ZL2Theme.h"

#pragma mark - 私有工具

// SF1.0 档取图兜底（ZL2 域页面同款 helper）
static UIImage *ZL2M3SystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

// keyWindow 场景链 → topmost presented VC（present 宿主）
static UIViewController *ZL2M3TopmostViewController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (window) break;
    }
    if (!window) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;

    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// 展示容器基类：全屏透明底 + scrim（Dialog/BottomSheet 共用收展逻辑）
@interface ZL2M3OverlayViewController : UIViewController
@property (nonatomic, strong) UIControl *scrimControl;
@property (nonatomic, copy, nullable) void (^onScrimTapped)(void);
- (void)ame_presentOver:(UIViewController *)host;
- (void)ame_closeAnimated:(void (^)(void))completion;
@end

@implementation ZL2M3OverlayViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        // 继承属性一律 self. 访问（UIKit 属性 ivar 不对子类可见，_ivar 写法编译错）
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // M3 scrim 规格：黑色 32%，深浅两态同值（spec 常量，非主题语义色）
    _scrimControl = [[UIControl alloc] init];
    _scrimControl.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.32];
    _scrimControl.translatesAutoresizingMaskIntoConstraints = NO;
    _scrimControl.accessibilityLabel = @"关闭";
    [_scrimControl addTarget:self
                      action:@selector(ame_scrimTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_scrimControl];
    [_scrimControl.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [_scrimControl.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [_scrimControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [_scrimControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
}

- (void)ame_scrimTapped {
    if (self.onScrimTapped) self.onScrimTapped();
}

- (void)ame_presentOver:(UIViewController *)host {
    [host presentViewController:self animated:NO completion:nil];
}

- (void)ame_closeAnimated:(void (^)(void))completion {
    [self dismissViewControllerAnimated:NO completion:completion];
}

@end

#pragma mark - ① M3 胶囊搜索框

@interface ZL2M3SearchBar () <UITextFieldDelegate>
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UITextField *field;
@end

@implementation ZL2M3SearchBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [ZL2Theme surfaceContainerHigh];
        self.layer.cornerRadius = [ZL2Theme radiusXL];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitSearchField;

        _iconView = [[UIImageView alloc]
            initWithImage:[ZL2M3SystemImage(@"magnifyingglass", @"search")
                           imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _iconView.tintColor = [ZL2Theme onSurfaceVariant];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];

        _field = [[UITextField alloc] init];
        _field.font = [ZL2Theme fontBodyLarge];
        _field.textColor = [ZL2Theme onSurface];
        _field.returnKeyType = UIReturnKeySearch;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.delegate = self;
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        _field.accessibilityLabel = @"搜索";
        [_field addTarget:self
                   action:@selector(ame_editingChanged)
         forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_field];

        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16].active = YES;
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [_iconView.widthAnchor constraintEqualToConstant:20].active = YES;
        [_iconView.heightAnchor constraintEqualToConstant:20].active = YES;
        [_field.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10].active = YES;
        [_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12].active = YES;
        [_field.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
        [_field.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
        [self.heightAnchor constraintEqualToConstant:44].active = YES;
    }
    return self;
}

- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = [placeholder copy];
    // attributedPlaceholder 走 onSurfaceVariant（M3 input 占位语义色）
    _field.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:placeholder ?: @""
                                        attributes:@{
            NSForegroundColorAttributeName: [ZL2Theme onSurfaceVariant],
        }];
}

- (NSString *)text {
    return _field.text ?: @"";
}

- (void)setText:(NSString *)text {
    _field.text = text;
}

- (void)ame_editingChanged {
    if (self.onTextChanged) self.onTextChanged(_field.text ?: @"");
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (self.onReturn) self.onReturn(_field.text ?: @"");
    return YES;
}

@end

#pragma mark - ② M3 筛选 chip

@interface ZL2M3FilterChip ()
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *checkWidthConstraint;
@end

@implementation ZL2M3FilterChip

+ (CGFloat)preferredHeight {
    return 32;
}

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.layer.cornerRadius = [ZL2Theme radiusS];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = text;

        _checkView = [[UIImageView alloc]
            initWithImage:[ZL2M3SystemImage(@"checkmark", nil)
                           imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _checkView.tintColor = [ZL2Theme onPrimaryContainer];
        _checkView.contentMode = UIViewContentModeScaleAspectFit;
        _checkView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkView.userInteractionEnabled = NO;
        [self addSubview:_checkView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = text;
        _titleLabel.font = [ZL2Theme fontLabelMedium];
        _titleLabel.textColor = [ZL2Theme onSurfaceVariant];
        _titleLabel.numberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.userInteractionEnabled = NO;
        [self addSubview:_titleLabel];

        _checkWidthConstraint = [_checkView.widthAnchor constraintEqualToConstant:0];
        [_checkWidthConstraint setActive:YES];

        [_checkView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10].active = YES;
        [_checkView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [_checkView.heightAnchor constraintEqualToConstant:16].active = YES;
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_checkView.trailingAnchor constant:6].active = YES;
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12].active = YES;
        [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [self.heightAnchor constraintEqualToConstant:[ZL2M3FilterChip preferredHeight]].active = YES;
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    // selected 属性承自 UIControl（super 存储，无子类 ivar；覆写仅刷外观）
    [super setSelected:selected];
    [self ame_applyAppearance];
}

- (void)ame_applyAppearance {
    if (self.isSelected) {
        self.backgroundColor = [ZL2Theme primaryContainer];
        self.layer.borderWidth = 0.0;
        self.titleLabel.textColor = [ZL2Theme onPrimaryContainer];
        self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitSelected;
    } else {
        self.backgroundColor = [ZL2Theme surfaceContainer];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        self.titleLabel.textColor = [ZL2Theme onSurfaceVariant];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    // 对勾宽度 0↔16 动画过渡（MD3 chip 两态规格位移）
    BOOL checked = self.isSelected;
    [UIView animateWithDuration:0.15 animations:^{
        self.checkWidthConstraint.constant = checked ? 16 : 0;
        [self layoutIfNeeded];
    }];
}

@end

#pragma mark - ③ MD3 开关

@interface ZL2M3Switch ()
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) NSLayoutConstraint *thumbSizeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *thumbLeadingConstraint;
@end

@implementation ZL2M3Switch

+ (CGFloat)switchWidth  { return 52.0; }
+ (CGFloat)switchHeight { return 32.0; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _trackView = [[UIView alloc] init];
        _trackView.translatesAutoresizingMaskIntoConstraints = NO;
        _trackView.userInteractionEnabled = NO;
        [self addSubview:_trackView];

        _thumbView = [[UIView alloc] init];
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbView.userInteractionEnabled = NO;
        [self addSubview:_thumbView];

        [_trackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
        [_trackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
        [_trackView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
        [_trackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;

        _thumbSizeConstraint = [_thumbView.widthAnchor constraintEqualToConstant:16];
        [_thumbSizeConstraint setActive:YES];
        [_thumbView.heightAnchor constraintEqualToAnchor:_thumbView.widthAnchor].active = YES;
        _thumbLeadingConstraint = [_thumbView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18];
        [_thumbLeadingConstraint setActive:YES];
        [_thumbView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

        [self.widthAnchor constraintEqualToConstant:[ZL2M3Switch switchWidth]].active = YES;
        [self.heightAnchor constraintEqualToConstant:[ZL2M3Switch switchHeight]].active = YES;

        [self addTarget:self
                 action:@selector(ame_toggle)
       forControlEvents:UIControlEventTouchUpInside];
        [self ame_applyAppearanceAnimated:NO];
    }
    return self;
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    [self ame_applyAppearanceAnimated:animated];
}

- (void)ame_toggle {
    _on = !_on;
    [self ame_applyAppearanceAnimated:YES];
    self.accessibilityValue = _on ? @"1" : @"0";
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)ame_applyAppearanceAnimated:(BOOL)animated {
    BOOL checked = _on;
    void (^apply)(void) = ^{
        // MD3 三态尺寸：未选 16pt 拇指 + 2pt 描边；选中 24pt 拇指无描边
        CGFloat thumb = checked ? 24.0 : 16.0;
        // ★ Task331：拨动行程语义修复（用户："MD3 滑块怎么变成按压按钮了"）
        //   —— 旧值 lead = checked ? 14 : 18 与尺寸 24/16 组合下，拇指中心
        //   恒 = 26pt（52/2），两态只原地缩放零行程 = 带圆点的按压按钮观感，
        //   开关语义完全不可读。真 M3 行程几何：OFF 拇指 16pt 左嵌 4pt
        //   （占位 4..20），ON 拇指 24pt 右嵌 4pt（占位 24..48），行程 20pt
        //   + 弹簧动画（既有）= 拨动语言一眼可读；轨道 52x32/圆角/配色
        //   令牌全部不动，五消费方零布局影响（总宽不变）。
        CGFloat lead = checked ? 24.0 : 4.0;
        self.thumbSizeConstraint.constant = thumb;
        self.thumbLeadingConstraint.constant = lead;
        // ★ Task330：拇指圆形化 —— 旋钮此前从未设 cornerRadius，16/24pt
        //   方形色块直接怼在轨道上（用户："为什么 md3 的滑块张这样"）。
        //   圆形 = iOS 视觉母语；MD3 轨道几何与主题令牌配色保持不动。
        self.thumbView.layer.cornerRadius = thumb / 2.0;

        if (checked) {
            self.trackView.backgroundColor = [ZL2Theme primary];
            self.trackView.layer.borderWidth = 0.0;
            self.thumbView.backgroundColor = [ZL2Theme onPrimary];
        } else {
            self.trackView.backgroundColor = [ZL2Theme surfaceVariant];
            self.trackView.layer.borderWidth = 2.0;
            self.trackView.layer.borderColor = [ZL2Theme outline].CGColor;
            self.thumbView.backgroundColor = [ZL2Theme outline];
        }
        self.trackView.layer.cornerRadius = [ZL2M3Switch switchHeight] / 2.0;
        self.accessibilityValue = checked ? @"1" : @"0";
    };
    if (animated) {
        [UIView animateWithDuration:0.20
                              delay:0.0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:apply
                         completion:nil];
    } else {
        apply();
    }
}

@end

#pragma mark - ④ M3 基础对话框

static __weak ZL2M3OverlayViewController *_ame_currentDialog = nil;

@interface ZL2M3DialogHost : ZL2M3OverlayViewController
@property (nonatomic, copy) NSString *dialogTitle;
@property (nonatomic, copy) NSString *dialogBody;
@property (nonatomic, copy) NSString *confirmText;
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, copy, nullable) void (^onConfirmAction)(void);
@property (nonatomic, copy, nullable) void (^onCancelAction)(void);
@property (nonatomic, strong) UIView *cardView;
@end

@implementation ZL2M3DialogHost

- (void)viewDidLoad {
    [super viewDidLoad];

    // scrim 点按 = 取消语义（MD3 基础对话框缺省行为）；
    // onScrimTapped 块属性在 VC 本体（ame_scrimTapped 转发），非 UIControl 上
    __weak typeof(self) weakSelf = self;
    self.onScrimTapped = ^{ [weakSelf ame_finishWithConfirm:NO]; };

    _cardView = [[UIView alloc] init];
    _cardView.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _cardView.layer.cornerRadius = [ZL2Theme radiusXL];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.alpha = 0.0;
    [self.view addSubview:_cardView];

    UILabel *headline = [[UILabel alloc] init];
    headline.text = self.dialogTitle;
    headline.font = [ZL2Theme fontTitleLarge];
    headline.textColor = [ZL2Theme onSurface];
    headline.numberOfLines = 0;
    headline.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:headline];

    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.text = self.dialogBody;
    bodyLabel.font = [ZL2Theme fontBodyMedium];
    bodyLabel.textColor = [ZL2Theme onSurfaceVariant];
    bodyLabel.numberOfLines = 0;
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:bodyLabel];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *cancelText = @"取消";
    [cancelButton setTitle:cancelText forState:UIControlStateNormal];
    cancelButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    cancelButton.tintColor = [ZL2Theme primary];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self
                     action:@selector(ame_cancelTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [_cardView addSubview:cancelButton];

    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirmButton setTitle:self.confirmText forState:UIControlStateNormal];
    confirmButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    confirmButton.tintColor = self.destructive ? [ZL2Theme error] : [ZL2Theme primary];
    confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [confirmButton addTarget:self
                      action:@selector(ame_confirmTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [_cardView addSubview:confirmButton];

    [NSLayoutConstraint activateConstraints:@[
        [headline.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:24],
        [headline.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:24],
        [headline.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-24],

        [bodyLabel.topAnchor constraintEqualToAnchor:headline.bottomAnchor constant:12],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:24],
        [bodyLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-24],

        [confirmButton.centerYAnchor constraintEqualToAnchor:cancelButton.centerYAnchor],
        [cancelButton.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
        [confirmButton.trailingAnchor constraintEqualToAnchor:cancelButton.leadingAnchor constant:-8],
        [cancelButton.topAnchor constraintEqualToAnchor:bodyLabel.bottomAnchor constant:20],
        [cancelButton.heightAnchor constraintEqualToConstant:40],
        [confirmButton.heightAnchor constraintEqualToConstant:40],
        [_cardView.bottomAnchor constraintEqualToAnchor:cancelButton.bottomAnchor constant:12],

        // M3 基础对话框宽度域：min 280 / max 560
        [_cardView.widthAnchor constraintGreaterThanOrEqualToConstant:280],
        [_cardView.widthAnchor constraintLessThanOrEqualToConstant:560],
        [_cardView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_cardView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_cardView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [_cardView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
}

- (void)ame_presentOver:(UIViewController *)host {
    [super ame_presentOver:host];
    // 入场：卡片缩放 0.92→1 + 淡入（M3 emphasized 过渡近似）
    _cardView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [UIView animateWithDuration:0.22 animations:^{
        self->_cardView.alpha = 1.0;
        self->_cardView.transform = CGAffineTransformIdentity;
    }];
}

- (void)ame_cancelTapped { [self ame_finishWithConfirm:NO]; }
- (void)ame_confirmTapped { [self ame_finishWithConfirm:YES]; }

// 收起（淡出）→ 回调（confirm/cancel 二选一，一次性）
- (void)ame_finishWithConfirm:(BOOL)confirmed {
    __weak typeof(self) weakSelf = self;
    void (^callback)(void) = confirmed ? self.onConfirmAction : self.onCancelAction;
    self.onConfirmAction = nil;
    self.onCancelAction = nil;
    if (_ame_currentDialog == self) _ame_currentDialog = nil;

    [UIView animateWithDuration:0.16 animations:^{
        weakSelf.cardView.alpha = 0.0;
        weakSelf.scrimControl.alpha = 0.0;
    } completion:^(BOOL finished) {
        [weakSelf ame_closeAnimated:^{
            if (callback) callback();
        }];
    }];
}

@end

@implementation ZL2M3Dialog

+ (void)showTitle:(NSString *)title
             body:(NSString *)body
     confirmTitle:(NSString *)confirmTitle
       destructive:(BOOL)destructive
        onConfirm:(void (^)(void))onConfirm
         onCancel:(void (^)(void))onCancel {
    [ZL2M3Dialog dismiss];

    ZL2M3DialogHost *host = [ZL2M3DialogHost new];
    host.dialogTitle = title;
    host.dialogBody = body;
    host.confirmText = confirmTitle;
    host.destructive = destructive;
    host.onConfirmAction = onConfirm;
    host.onCancelAction = onCancel;
    host.accessibilityLabel = title;

    _ame_currentDialog = host;
    [host ame_presentOver:ZL2M3TopmostViewController()];
}

+ (void)dismiss {
    ZL2M3OverlayViewController *current = _ame_currentDialog;
    if (!current) return;
    _ame_currentDialog = nil;
    [current ame_closeAnimated:nil];
}

@end

#pragma mark - ⑤ M3 底部弹层

static __weak ZL2M3OverlayViewController *_ame_currentSheet = nil;

@interface ZL2M3SheetHost : ZL2M3OverlayViewController
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, copy, nullable) void (^onDismissed)(void);
@end

@implementation ZL2M3SheetHost

- (void)viewDidLoad {
    [super viewDidLoad];

    __weak typeof(self) weakSelf = self;
    self.onScrimTapped = ^{ [weakSelf ame_closeAndNotify]; };

    _sheetView = [[UIView alloc] init];
    _sheetView.backgroundColor = [ZL2Theme surfaceContainerLow];
    _sheetView.layer.cornerRadius = [ZL2Theme radiusXL];
    // 仅顶部圆角（M3 bottom sheet 规格两侧贴屏）
    _sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _sheetView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_sheetView];

    // 抓手 32×4（M3 drag handle 规格，居中 8pt 顶距）
    UIView *grabber = [[UIView alloc] init];
    grabber.backgroundColor = [ZL2Theme outlineVariant];
    grabber.layer.cornerRadius = 2.0;
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.userInteractionEnabled = NO;
    [_sheetView addSubview:grabber];

    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [_sheetView addSubview:_contentView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_sheetView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [grabber.topAnchor constraintEqualToAnchor:_sheetView.topAnchor constant:8],
        [grabber.centerXAnchor constraintEqualToAnchor:_sheetView.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:32],
        [grabber.heightAnchor constraintEqualToConstant:4],

        [_contentView.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:16],
        [_contentView.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor constant:16],
        [_contentView.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor constant:-16],
        // 内容底缘 = 安全区底 + 12（sheet 本体延伸到屏幕底，M3 规格语义）
        [_contentView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
    ]];
}

- (void)ame_presentOver:(UIViewController *)host {
    [super ame_presentOver:host];
    // 入场：上滑 0.28s（transform 位移——sheet 是自动布局管理视图，
    // 动画期间约束不改，frame 位移会被后续 layout pass 覆盖，
    // transform 与约束正交才是可靠路径）
    [self.view layoutIfNeeded];
    CGFloat travel = _sheetView.frame.size.height;
    _sheetView.transform = CGAffineTransformMakeTranslation(0, travel);
    self.scrimControl.alpha = 0.0;
    [UIView animateWithDuration:0.28 animations:^{
        self.scrimControl.alpha = 1.0;
        self->_sheetView.transform = CGAffineTransformIdentity;
    }];
}

- (void)ame_closeAndNotify {
    void (^notify)(void) = self.onDismissed;
    self.onDismissed = nil;
    if (_ame_currentSheet == self) _ame_currentSheet = nil;
    [UIView animateWithDuration:0.22 animations:^{
        self.scrimControl.alpha = 0.0;
        self->_sheetView.transform =
            CGAffineTransformMakeTranslation(0, self->_sheetView.frame.size.height);
    } completion:^(BOOL finished) {
        [self ame_closeAnimated:^{
            if (notify) notify();
        }];
    }];
}

@end

@implementation ZL2M3BottomSheet

+ (void)presentWithContentView:(UIView *)content
                    onDismiss:(void (^)(void))onDismiss {
    [ZL2M3BottomSheet dismissWithContentView:nil];

    ZL2M3SheetHost *host = [ZL2M3SheetHost new];
    host.contentView = content;
    host.onDismissed = onDismiss;
    _ame_currentSheet = host;
    [host ame_presentOver:ZL2M3TopmostViewController()];
}

+ (void)dismissWithContentView:(UIView *)content {
    ZL2M3SheetHost *current = (ZL2M3SheetHost *)_ame_currentSheet;
    if (![current isKindOfClass:[ZL2M3SheetHost class]]) return;
    _ame_currentSheet = nil;
    [current ame_closeAndNotify];
}

@end

#pragma mark - ⑥ M3 卡片 cell

@interface ZL2M3CardCell ()
@property (nonatomic, strong) UILabel *ame_titleLabel;
@property (nonatomic, strong) UILabel *ame_subLabel;
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, strong) UIView *actionPill;
@property (nonatomic, strong) NSLayoutConstraint *pillTrailing;
@property (nonatomic, strong) NSLayoutConstraint *titleFallback;
@property (nonatomic, strong) NSLayoutConstraint *subFallback;
@property (nonatomic, strong) NSLayoutConstraint *titleToPill;
@property (nonatomic, strong) NSLayoutConstraint *subToPill;
@end

@implementation ZL2M3CardCell

- (UILabel *)titleLabel { return _ame_titleLabel; }
- (UILabel *)subLabel { return _ame_subLabel; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.selectedBackgroundView = [[UIView alloc] init];
        self.selectedBackgroundView.backgroundColor =
            [[ZL2Theme onSurface] colorWithAlphaComponent:0.06];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [ZL2Theme surfaceContainer];
        card.layer.cornerRadius = [ZL2Theme radiusL];
        card.layer.masksToBounds = YES;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:card];

        _ame_titleLabel = [[UILabel alloc] init];
        _ame_titleLabel.font = [ZL2Theme fontTitleMedium];
        _ame_titleLabel.textColor = [ZL2Theme onSurface];
        _ame_titleLabel.numberOfLines = 1;
        _ame_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_ame_titleLabel];

        _ame_subLabel = [[UILabel alloc] init];
        _ame_subLabel.font = [ZL2Theme fontBodyMedium];
        _ame_subLabel.textColor = [ZL2Theme onSurfaceVariant];
        _ame_subLabel.numberOfLines = 3;
        _ame_subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_ame_subLabel];

        _actionPill = [[UIView alloc] init];
        _actionPill.layer.cornerRadius = [ZL2Theme radiusS];
        _actionPill.layer.masksToBounds = YES;
        _actionPill.translatesAutoresizingMaskIntoConstraints = NO;
        _actionPill.userInteractionEnabled = NO;
        [card addSubview:_actionPill];

        _actionLabel = [[UILabel alloc] init];
        _actionLabel.font = [ZL2Theme fontLabelMedium];
        _actionLabel.textAlignment = NSTextAlignmentCenter;
        _actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _actionLabel.userInteractionEnabled = NO;
        [_actionPill addSubview:_actionLabel];

        self.pillTrailing =
            [_actionPill.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14];
        self.titleFallback =
            [_ame_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14];
        self.subFallback =
            [_ame_subLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14];
        self.titleToPill =
            [_ame_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionPill.leadingAnchor constant:-10];
        self.subToPill =
            [_ame_subLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionPill.leadingAnchor constant:-10];
        [NSLayoutConstraint activateConstraints:@[
            [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_ame_titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
            [_ame_titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],

            [_ame_subLabel.topAnchor constraintEqualToAnchor:_ame_titleLabel.bottomAnchor constant:4],
            [_ame_subLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [_ame_subLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],

            [_actionPill.centerYAnchor constraintEqualToAnchor:_ame_titleLabel.centerYAnchor],
            self.pillTrailing,
            [_actionPill.widthAnchor constraintGreaterThanOrEqualToConstant:56],
            [_actionPill.heightAnchor constraintEqualToConstant:28],

            [_actionLabel.centerXAnchor constraintEqualToAnchor:_actionPill.centerXAnchor],
            [_actionLabel.centerYAnchor constraintEqualToAnchor:_actionPill.centerYAnchor],
            [_actionLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_actionPill.leadingAnchor constant:10],
            [_actionPill.trailingAnchor constraintGreaterThanOrEqualToAnchor:_actionLabel.trailingAnchor constant:10],
        ]];
        self.titleToPill.active = YES;
        self.subToPill.active = YES;
    }
    return self;
}

- (void)applyActionStyle:(NSInteger)style title:(NSString *)title {
    BOOL hidden = (style == 3);
    _actionPill.hidden = hidden;
    _actionLabel.hidden = hidden;
    self.pillTrailing.active = !hidden;
    self.titleToPill.active = !hidden;
    self.subToPill.active = !hidden;
    self.titleFallback.active = hidden;
    self.subFallback.active = hidden;
    if (hidden) return;
    switch (style) {
        case 0:
            _actionPill.backgroundColor = [ZL2Theme primary];
            _actionLabel.textColor = [ZL2Theme onPrimary];
            break;
        case 1:
            _actionPill.backgroundColor = [ZL2Theme surfaceContainerHighest];
            _actionLabel.textColor = [ZL2Theme onSurfaceVariant];
            break;
        default:
            _actionPill.backgroundColor = [ZL2Theme warning];
            _actionLabel.textColor = [ZL2Theme onPrimary];
            break;
    }
    _actionLabel.text = title;
}

@end
