//
// ZL2ThemeCustomSheet.m — ★Task429（PDF 第五版 §8.1）CUSTOM 取色弹层实现
//                        ★Task436 取色自由化升级（色相条 + Hex 自由取色）
//
// 组件口径：ZL2Theme 令牌 + M3 圆角/字体阶（本 TU 自包含，无 ZL2M3Kit 依赖
// ——ZL2M3Kit.m 归并行工位 E，勿引）。确认写键触发生效链：
//   写 general.custom_seed_color / general.custom_palette_style /
//   general.theme_mode=8 → [ZL2DynamicPalette ame429_reloadAndApply]
//   → HCT 色板 → 推 ZL2Theme 活动覆盖层 → Task346 根重建。
//
// ★Task436 取色自由化（ZL2 CustomThemeDialog 全功能取色器对标）：12 圆点
// 降级为快选色（选点即同步色相条/Hex），新增色相条（渐变自绘拖条）与
// Hex 输入框（#RRGGBB 校验+解析）——取色自由度从 12 颗固定色 → 全色域。
// 下游管线零改动：确认钮落键仍是三键同格式（custom_seed_color 仍为
// "#RRGGBB" 六位十六进制——ZL2DynamicPalette ame429_colorFromHexString
// 只收 6 位 hex，alpha 无落点，故透明度滑条按任务书条件分支「若既有面
// 已有透明度则联动」不引入——既有面无透明度，扩 #RRGGBBAA 属管线改动，
// 留待后续轮登记）。风格档不扩枚举，文案如实称「三档」。
//

#import "ZL2ThemeCustomSheet.h"

#import "ZL2Theme.h"
#import "AmeHCTPalette.h"
#import "ZL2DynamicPalette.h"
#import "LauncherPreferences.h"   // setPrefString/setPrefInt（注册面归主控合流）
#import "utils.h"                 // localize

#pragma mark - 常量实名表（★Task429 / ★Task436）

// 12 主色圆点种子（与 AmeHCTPalette 视觉家族同域；hex 注释直读）。
// ★Task436：语义降级为快选色——点击仍写入同一自由取色态（色相条/Hex
// 同步），不再是唯一取色入口。
static const int Ame429CustomSeedDots[12] = {
    0xA63A17, // embermire 主棕
    0x2779B5, // 湖蓝
    0x3BA3DB, // 天蓝
    0x2E7D51, // 森绿
    0x2FA08A, // 薄荷
    0x6E56A6, // 暮紫
    0xB4424C, // 绯红
    0xB03A78, // 洋红
    0xA97A2C, // 琥珀
    0xB5941F, // 柠金
    0x5C6470, // 石墨
    0xC26E5A, // 玫瑰陶
};

// 几何刻度（M3/壳层判例同族）
static const CGFloat Ame429SheetDotSize       = 36.0;  // 圆点直径
static const CGFloat Ame429SheetDotGap        = 14.0;  // 圆点横向间距
static const CGFloat Ame429SheetPreviewHeight = 56.0;  // 预览色块高
static const CGFloat Ame429SheetInset         = 20.0;  // 弹层内容边距
static const NSInteger Ame429SheetDotsPerRow  = 6;     // 圆点网格每行数（12 点 = 2 行）

// ★Task436 色相条/Hex 刻度
static const CGFloat Ame436HueBarHeight  = 36.0;   // 色相条总高（含拇指）
static const CGFloat Ame436HueThumbSize  = 26.0;   // 拇指直径
static const CGFloat Ame436HexFieldHeight = 44.0;  // Hex 输入框高

// 三新键（与 ZL2DynamicPalette.m 同名常量逐字一致；注册面归主控合流）
static NSString * const Ame429SheetKeyThemeMode       = @"general.theme_mode";
static NSString * const Ame429SheetKeyCustomSeedColor = @"general.custom_seed_color";
static NSString * const Ame429SheetKeyPaletteStyle    = @"general.custom_palette_style";

#pragma mark - ★Task436 色相条（渐变自绘拖条）

// 渐变自绘：0-360° 全色相渐变层 + 白圈拇指，点击/拖动回 hue（0..1）。
// 不用 UISlider 私有子视图注轨（脆）——纯公开 API 自绘，判例同族。
@interface Ame436HueBar : UIView
@property (nonatomic, copy) void (^onHueChanged)(CGFloat hue);   // 拖动/点击回传（0..1）
@property (nonatomic, assign) CGFloat hue;                        // 0..1
- (void)ame436_setHue:(CGFloat)hue;                               // 程序赋值（不回调）
@end

@implementation Ame436HueBar {
    CAGradientLayer *_ame436_track;
    CALayer *_ame436_thumb;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _ame436_track = [CAGradientLayer layer];
        _ame436_track.startPoint = CGPointMake(0.0, 0.5);
        _ame436_track.endPoint = CGPointMake(1.0, 0.5);
        // 全色相 9 站渐变（S/B 固定鲜档，与色相条语义一致）
        NSMutableArray *ame436_colors = [NSMutableArray array];
        for (NSInteger ame436_i = 0; ame436_i <= 8; ame436_i++) {
            UIColor *ame436_c = [UIColor colorWithHue:ame436_i / 8.0
                                            saturation:0.85
                                            brightness:1.0
                                                 alpha:1.0];
            [ame436_colors addObject:(id)ame436_c.CGColor];
        }
        _ame436_track.colors = ame436_colors;
        _ame436_track.cornerRadius = (Ame436HueBarHeight - 12.0) / 2.0;
        _ame436_track.masksToBounds = YES;
        [self.layer addSublayer:_ame436_track];

        _ame436_thumb = [CALayer layer];
        _ame436_thumb.bounds = CGRectMake(0, 0, Ame436HueThumbSize, Ame436HueThumbSize);
        _ame436_thumb.cornerRadius = Ame436HueThumbSize / 2.0;
        _ame436_thumb.backgroundColor = [UIColor whiteColor].CGColor;
        _ame436_thumb.borderColor = [ZL2Theme outline].CGColor;
        _ame436_thumb.borderWidth = 2.0;
        _ame436_thumb.shadowColor = [UIColor blackColor].CGColor;
        _ame436_thumb.shadowOpacity = 0.25;
        _ame436_thumb.shadowRadius = 2.0;
        _ame436_thumb.shadowOffset = CGSizeMake(0, 1);
        [self.layer addSublayer:_ame436_thumb];

        UITapGestureRecognizer *ame436_tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                   action:@selector(ame436_gesture:)];
        [self addGestureRecognizer:ame436_tap];
        UIPanGestureRecognizer *ame436_pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(ame436_gesture:)];
        [self addGestureRecognizer:ame436_pan];

        _hue = 0.0;
    }
    return self;
}

+ (BOOL)requiresConstraintBasedLayout { return YES; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat ame436_insetX = Ame436HueThumbSize / 2.0;
    _ame436_track.frame = CGRectMake(0, (self.bounds.size.height - (Ame436HueBarHeight - 12.0)) / 2.0,
                                     self.bounds.size.width, Ame436HueBarHeight - 12.0);
    CGFloat ame436_span = self.bounds.size.width - 2.0 * ame436_insetX;
    CGFloat ame436_x = ame436_insetX + _hue * ame436_span;
    _ame436_thumb.position = CGPointMake(ame436_x, self.bounds.size.height / 2.0);
}

// 点击/拖动 → hue → 回调（程序赋值走 ame436_setHue: 不回调）
- (void)ame436_gesture:(UIGestureRecognizer *)sender {
    CGPoint ame436_p = [sender locationInView:self];
    CGFloat ame436_insetX = Ame436HueThumbSize / 2.0;
    CGFloat ame436_span = self.bounds.size.width - 2.0 * ame436_insetX;
    if (ame436_span <= 0) return;
    CGFloat ame436_hue = (ame436_p.x - ame436_insetX) / ame436_span;
    if (ame436_hue < 0) ame436_hue = 0;
    if (ame436_hue > 1) ame436_hue = 1;
    self.hue = ame436_hue;
    [self setNeedsLayout];
    if (self.onHueChanged) self.onHueChanged(ame436_hue);
}

- (void)ame436_setHue:(CGFloat)hue {
    if (hue < 0) hue = 0;
    if (hue > 1) hue = 1;
    self.hue = hue;
    [self setNeedsLayout];
}

// 触点命中整个条（含拇指外缘），无子控件
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (point.x < 0 || point.y < 0 ||
        point.x > self.bounds.size.width || point.y > self.bounds.size.height) return nil;
    return self;
}

@end

#pragma mark - ★Task436 Hex 解析/序列化助手

// "#RRGGBB"/"RRGGBB" → UIColor（非法回落 nil；与 ZL2DynamicPalette
// ame429_colorFromHexString 同族解析——下游零改动前提）
static UIColor *Ame436SheetColorFromHexString(NSString *hex) {
    if (hex.length == 0) return nil;
    NSString *s = hex;
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return nil;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < s.length; i++) {
        if (![ok characterIsMember:[s characterAtIndex:i]]) return nil;
    }
    unsigned long long v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    [sc scanHexLongLong:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:1.0];
}

// UIColor → "#RRGGBB"（下游种子格式；alpha 恒 1——管线无 alpha 落点）
static NSString *Ame436SheetHexStringFromColor(UIColor *color) {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)roundf(r * 255.0f),
            (unsigned int)roundf(g * 255.0f),
            (unsigned int)roundf(b * 255.0f)];
}

// 保留明度/饱和度的换相：拖色相条不改 S/B（从既有色继承；灰态给鲜档默认）
static UIColor *Ame436SheetColorByHue(CGFloat hue, UIColor *base) {
    CGFloat ame436_s = 0.82, ame436_b = 0.92;
    if (base != nil) {
        CGFloat ame436_h, ame436_s2, ame436_b2, ame436_a;
        if ([base getHue:&ame436_h saturation:&ame436_s2 brightness:&ame436_b2 alpha:&ame436_a] &&
            ame436_s2 > 0.002) {
            ame436_s = ame436_s2;
            ame436_b = ame436_b2;
        }
    }
    return [UIColor colorWithHue:hue saturation:ame436_s brightness:ame436_b alpha:1.0];
}

@interface ZL2ThemeCustomSheet () <UITextFieldDelegate>   // ★Task436：Hex 输入框 Done 收键盘
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *seedLabel;
@property (nonatomic, strong) UIView *dotBoard;                      // 圆点画布（两行网格）
@property (nonatomic, strong) NSMutableArray<UIView *> *dotWraps;    // 选中环宿主引用
@property (nonatomic, strong) Ame436HueBar *hueBar;                  // ★Task436 色相条
@property (nonatomic, strong) UITextField *hexField;                 // ★Task436 Hex 输入框
@property (nonatomic, strong) UISegmentedControl *styleControl;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIStackView *previewRow;
@property (nonatomic, strong) NSMutableArray<UIView *> *previewBlocks;
@property (nonatomic, strong) NSMutableArray<UILabel *> *previewCaptions;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, assign) NSInteger selectedDotIndex;            // -1 = 未选（自由取色态也置 -1）
@property (nonatomic, strong) UIColor *pickedColor;                  // ★Task436 自由取色态（nil = 未选）
@end

@implementation ZL2ThemeCustomSheet

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedDotIndex = -1;
        _dotWraps = [NSMutableArray array];
        _previewBlocks = [NSMutableArray array];
        _previewCaptions = [NSMutableArray array];
        self.title = localize(@"ame429.f.custom.sheet.title", @"自定义取色");
    }
    return self;
}

#pragma mark - 便捷呈现

- (void)ame429_presentFromViewController:(UIViewController *)host {
    if (host == nil) return;   // 防御守卫
    UIViewController *target = host;
    while (target.presentedViewController != nil &&
           !target.presentedViewController.isBeingDismissed) {
        target = target.presentedViewController;
    }
    // 导航容器包裹（关闭钮走 navigationItem.leftBarButtonItem，须有导航条承载）
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [target presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 构建

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
    self.stack.spacing = 14.0;
    [self.scroll addSubview:self.stack];

    // ── 种子色段（★Task436：快选色 + 色相条 + Hex 自由取色）──
    self.seedLabel = [[UILabel alloc] init];
    self.seedLabel.text = localize(@"ame429.f.custom.seed", @"种子色");
    self.seedLabel.font = [ZL2Theme fontLabelLarge];
    self.seedLabel.textColor = [ZL2Theme onSurfaceVariant];
    [self.stack addArrangedSubview:self.seedLabel];

    self.dotBoard = [[UIView alloc] init];
    self.dotBoard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stack addArrangedSubview:self.dotBoard];
    for (NSInteger i = 0; i < 12; i++) {
        [self ame429_buildDotAtIndex:i];
    }

    // ── ★Task436 色相条（HSL 换相：拖动只改色相，S/B 从当前色继承）──
    __weak typeof(self) weakSelf = self;   // 弱捕获口径统一（Task434 判例；防 self→hueBar→block→self 环）
    self.hueBar = [[Ame436HueBar alloc] initWithFrame:CGRectZero];
    self.hueBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.hueBar.onHueChanged = ^(CGFloat hue) {
        [weakSelf ame436_applyPickedColor:Ame436SheetColorByHue(hue, weakSelf.pickedColor)
                              fromDotIndex:-1];
    };
    [self.stack addArrangedSubview:self.hueBar];

    // ── ★Task436 Hex 输入框（#RRGGBB 校验+解析；非法态描边提示不落选）──
    self.hexField = [[UITextField alloc] init];
    self.hexField.translatesAutoresizingMaskIntoConstraints = NO;
    self.hexField.placeholder = localize(@"ame436.f.custom.hex.placeholder", @"#RRGGBB");
    self.hexField.font = [ZL2Theme fontBodyMedium];
    self.hexField.textColor = [ZL2Theme onSurface];
    self.hexField.backgroundColor = [ZL2Theme surfaceVariant];
    self.hexField.layer.cornerRadius = [ZL2Theme radiusS];
    self.hexField.layer.borderWidth = 1.0;
    self.hexField.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    self.hexField.keyboardType = UIKeyboardTypeASCIICapable;
    self.hexField.returnKeyType = UIReturnKeyDone;
    self.hexField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.hexField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.hexField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.hexField.textAlignment = NSTextAlignmentCenter;
    [self.hexField addTarget:self
                      action:@selector(ame436_hexEditingChanged)
            forControlEvents:UIControlEventEditingChanged];
    self.hexField.delegate = self;
    [self.stack addArrangedSubview:self.hexField];

    // ── 调色风格段（★Task436：不扩枚举，文案如实称「三档」）──
    UILabel *styleLabel = [[UILabel alloc] init];
    styleLabel.text = localize(@"ame436.f.custom.style", @"调色风格（三档）");
    styleLabel.font = [ZL2Theme fontLabelLarge];
    styleLabel.textColor = [ZL2Theme onSurfaceVariant];
    [self.stack addArrangedSubview:styleLabel];

    self.styleControl = [[UISegmentedControl alloc]
                         initWithItems:@[
                             localize(@"ame429.f.custom.style.natural", @"自然"),
                             localize(@"ame429.f.custom.style.vivid", @"鲜活"),
                             localize(@"ame429.f.custom.style.soft", @"柔和"),
                         ]];
    self.styleControl.selectedSegmentIndex = 0;
    // 现值回显（general.custom_palette_style；缺键 = 自然档——getPrefInt
    // 读 PLPreferences plist，勿直读 NSUserDefaults）
    NSInteger savedStyle = getPrefInt(Ame429SheetKeyPaletteStyle);
    if (savedStyle >= 0 && savedStyle <= 2) {
        self.styleControl.selectedSegmentIndex = savedStyle;
    }
    [self.styleControl addTarget:self
                          action:@selector(ame429_styleChanged)
                forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:self.styleControl];

    // ── 实时预览段 ──
    self.previewLabel = [[UILabel alloc] init];
    self.previewLabel.text = localize(@"ame429.f.custom.preview", @"实时预览");
    self.previewLabel.font = [ZL2Theme fontLabelLarge];
    self.previewLabel.textColor = [ZL2Theme onSurfaceVariant];
    [self.stack addArrangedSubview:self.previewLabel];

    self.previewRow = [[UIStackView alloc] init];
    self.previewRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewRow.axis = UILayoutConstraintAxisHorizontal;
    self.previewRow.spacing = 10.0;
    self.previewRow.distribution = UIStackViewDistributionFillEqually;
    [self.stack addArrangedSubview:self.previewRow];
    [self ame429_addPreviewBlockWithTitle:localize(@"ame429.f.custom.preview.primary", @"主色")];
    [self ame429_addPreviewBlockWithTitle:localize(@"ame429.f.custom.preview.container", @"容器")];
    [self ame429_addPreviewBlockWithTitle:localize(@"ame429.f.custom.preview.tertiary", @"三色")];

    // ── 确认钮 ──
    self.confirmButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmButton.layer.cornerRadius = [ZL2Theme radiusL];
    self.confirmButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [self.confirmButton setTitle:localize(@"ame429.f.custom.confirm", @"应用")
                        forState:UIControlStateNormal];
    [self.confirmButton addTarget:self
                           action:@selector(ame429_confirmTapped)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.confirmButton setEnabled:NO];   // 未选种子前禁用（守卫配真实现）
    [self.stack addArrangedSubview:self.confirmButton];

    // 关闭钮（导航条左上）
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                             target:self
                             action:@selector(ame429_closeTapped)];
    self.navigationItem.leftBarButtonItem = closeItem;

    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor
                                             constant:Ame429SheetInset],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor
                                                constant:-Ame429SheetInset],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor
                                                 constant:Ame429SheetInset],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor
                                               constant:-2.0 * Ame429SheetInset],

        // 圆点画布：两行网格高
        [self.dotBoard.heightAnchor constraintEqualToConstant:
            2.0 * Ame429SheetDotSize + Ame429SheetDotGap],
        // ★Task436：色相条/Hex 框高
        [self.hueBar.heightAnchor constraintEqualToConstant:Ame436HueBarHeight],
        [self.hexField.heightAnchor constraintEqualToConstant:Ame436HexFieldHeight],
        // 预览行高
        [self.previewRow.heightAnchor constraintEqualToConstant:Ame429SheetPreviewHeight],
    ]];

    // ★Task436 现值回显：CUSTOM 模式已有种子 → 还原自由取色态（色相条/
    //   Hex/预览同步，确认钮直接可用）
    [self ame436_echoCurrentSeed];
    [self ame429_refreshPreview];   // 初次渲染（未选种子 = 描边占位态）
    [self ame429_refreshConfirmState];
}

// 圆点（两行网格：行内 x = i % 6，行 y = i / 6；anchor 三参口径）。
// ★Task436：点击 = 快选色（写同一自由取色态并同步色相条/Hex）。
- (void)ame429_buildDotAtIndex:(NSInteger)index {
    int hex = Ame429CustomSeedDots[index];
    UIColor *color = [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                                     green:((hex >> 8) & 0xFF) / 255.0
                                      blue:(hex & 0xFF) / 255.0
                                     alpha:1.0];
    UIButton *dot = [UIButton buttonWithType:UIButtonTypeCustom];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = color;
    dot.layer.cornerRadius = Ame429SheetDotSize / 2.0;
    dot.layer.masksToBounds = NO;
    dot.tag = (NSInteger)index + 1;   // 反查载荷（tag = 序号 + 1，0 非法值隔离）
    dot.accessibilityLabel = [NSString stringWithFormat:@"seed %ld", (long)index];
    [dot addTarget:self
            action:@selector(ame429_dotTapped:)
  forControlEvents:UIControlEventTouchUpInside];

    // 选中环宿主（透明 wrap 圈住圆点，选中时描边显形）
    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    wrap.userInteractionEnabled = NO;
    wrap.layer.cornerRadius = (Ame429SheetDotSize + 12.0) / 2.0;
    wrap.layer.borderWidth = 2.0;
    wrap.layer.borderColor = [ZL2Theme primary].CGColor;
    wrap.hidden = YES;
    [self.dotBoard addSubview:wrap];
    [self.dotBoard addSubview:dot];
    [self.dotWraps addObject:wrap];

    NSInteger row = index / Ame429SheetDotsPerRow;
    NSInteger col = index % Ame429SheetDotsPerRow;
    [NSLayoutConstraint activateConstraints:@[
        [dot.widthAnchor constraintEqualToConstant:Ame429SheetDotSize],
        [dot.heightAnchor constraintEqualToConstant:Ame429SheetDotSize],
        [dot.leadingAnchor constraintEqualToAnchor:self.dotBoard.leadingAnchor
                                          constant:(CGFloat)col * (Ame429SheetDotSize + Ame429SheetDotGap)],
        [dot.topAnchor constraintEqualToAnchor:self.dotBoard.topAnchor
                                      constant:(CGFloat)row * (Ame429SheetDotSize + Ame429SheetDotGap)],
        [wrap.centerXAnchor constraintEqualToAnchor:dot.centerXAnchor],
        [wrap.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],
        [wrap.widthAnchor constraintEqualToConstant:Ame429SheetDotSize + 12.0],
        [wrap.heightAnchor constraintEqualToConstant:Ame429SheetDotSize + 12.0],
    ]];
}

// 预览三色块（容器圆角 + 底部 caption）
- (void)ame429_addPreviewBlockWithTitle:(NSString *)title {
    UIView *block = [[UIView alloc] init];
    block.translatesAutoresizingMaskIntoConstraints = NO;
    block.layer.cornerRadius = [ZL2Theme radiusM];
    block.backgroundColor = [ZL2Theme surfaceVariant];   // 未选种子占位
    block.layer.borderWidth = 1.0;
    block.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    [self.previewRow addArrangedSubview:block];

    UILabel *caption = [[UILabel alloc] init];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.text = title;
    caption.font = [ZL2Theme fontLabelMedium];
    caption.textAlignment = NSTextAlignmentCenter;
    caption.textColor = [ZL2Theme onSurfaceVariant];
    [block addSubview:caption];
    [NSLayoutConstraint activateConstraints:@[
        [caption.centerXAnchor constraintEqualToAnchor:block.centerXAnchor],
        [caption.bottomAnchor constraintEqualToAnchor:block.bottomAnchor constant:-8.0],
    ]];

    [self.previewBlocks addObject:block];
    [self.previewCaptions addObject:caption];
}

#pragma mark - ★Task436 自由取色态（快选/色相/Hex 三入口共用）

// 统一落点：写 pickedColor + 选中环显隐 + Hex/色相条同步 + 预览/确认刷新。
// fromDotIndex >= 0 = 快选来源（环显形）；-1 = 色相条/Hex 自由来源（环隐）。
- (void)ame436_applyPickedColor:(UIColor *)color fromDotIndex:(NSInteger)dotIndex {
    self.pickedColor = color;
    self.selectedDotIndex = dotIndex;
    for (NSUInteger i = 0; i < self.dotWraps.count; i++) {
        self.dotWraps[i].hidden = ((NSInteger)i != dotIndex);
    }
    // Hex 同步（程序赋值不触发 EditingChanged——无回环）
    NSString *ame436_hex = Ame436SheetHexStringFromColor(color);
    if (ame436_hex != nil) {
        self.hexField.text = ame436_hex;
    }
    self.hexField.layer.borderColor = [ZL2Theme outlineVariant].CGColor;   // 合法态复位描边
    // 色相条同步（程序赋值不回调——无回环）
    CGFloat ame436_h, ame436_s, ame436_b, ame436_a;
    if ([color getHue:&ame436_h saturation:&ame436_s brightness:&ame436_b alpha:&ame436_a] &&
        ame436_s > 0.002) {
        [self.hueBar ame436_setHue:ame436_h];
    }
    [self ame429_refreshPreview];
    [self ame429_refreshConfirmState];
}

// 现值回显：CUSTOM 模式（mode 8）且 custom_seed_color 可解析 → 还原取色态
- (void)ame436_echoCurrentSeed {
    id ame436_raw = getPrefObject(Ame429SheetKeyCustomSeedColor);
    if (![ame436_raw isKindOfClass:[NSString class]]) return;
    UIColor *ame436_seed = Ame436SheetColorFromHexString(ame436_raw);
    if (ame436_seed == nil) return;
    // 回显态不点亮快选环（种子可能来自命名色板/上一轮自由取色，非 12 点）
    [self ame436_applyPickedColor:ame436_seed fromDotIndex:-1];
}

// Hex 编辑：合法 #RRGGBB → 自由取色态；非法 → 错误描边（不落选、不回环）
- (void)ame436_hexEditingChanged {
    NSString *ame436_text = [self.hexField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    UIColor *ame436_color = Ame436SheetColorFromHexString(ame436_text);
    if (ame436_color == nil) {
        self.hexField.layer.borderColor = [ZL2Theme error].CGColor;   // 非法态提示
        return;
    }
    [self ame436_applyPickedColor:ame436_color fromDotIndex:-1];
}

// 键盘收起（Done 键）
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - 交互

- (void)ame429_dotTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 1;   // tag = 序号 + 1（0 非法值隔离）
    if (index < 0 || index >= 12) return;   // 防御守卫
    int hex = Ame429CustomSeedDots[index];
    UIColor *color = [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                                     green:((hex >> 8) & 0xFF) / 255.0
                                      blue:(hex & 0xFF) / 255.0
                                     alpha:1.0];
    [self ame436_applyPickedColor:color fromDotIndex:index];
}

- (void)ame429_styleChanged {
    [self ame429_refreshPreview];
}

- (void)ame429_closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ame429_confirmTapped {
    if (self.pickedColor == nil) return;   // 防御守卫（未选种子禁用配真实现）
    NSString *hexString = Ame436SheetHexStringFromColor(self.pickedColor);
    if (hexString == nil) return;   // 防御守卫（取色态不可序列化——理论不可达）
    NSInteger style = self.styleControl.selectedSegmentIndex;

    // 三键落盘（setPrefString/setPrefInt = PLPreferences 写面；注册面归主控
    // 合流——未注册期写值静默丢弃，读侧缺键回退默认）。
    // ★Task436：种子格式仍是 "#RRGGBB" 六位十六进制（下游
    // ame429_colorFromHexString 契约不变——管线零改动证据）。
    setPrefString(Ame429SheetKeyCustomSeedColor, hexString);
    setPrefInt(Ame429SheetKeyPaletteStyle, style);
    setPrefInt(Ame429SheetKeyThemeMode, (NSInteger)Ame429ThemeModeCustom);

    // 生效链：HCT 色板 → 推 ZL2Theme 活动覆盖层 → Task346 根重建
    [[ZL2DynamicPalette shared] ame429_reloadAndApply];

    NSLog(@"[Ame429] custom sheet confirm seed=%@ style=%ld (Task436 free-pick)", hexString, (long)style);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 预览刷新（实时）

- (void)ame429_refreshPreview {
    // 预览色 = 当前自由取色态 + 风格的 HCT 三角色（浅色态 tone 40/90/90
    // 三板）；未选种子时三块维持占位（surfaceVariant），caption 灰显。
    if (self.pickedColor == nil) {
        for (UIView *block in self.previewBlocks) {
            block.backgroundColor = [ZL2Theme surfaceVariant];
        }
        return;
    }
    AmeHCTPaletteStyle style = AmeHCTPaletteStyleNatural;
    if (self.styleControl.selectedSegmentIndex == 1) style = AmeHCTPaletteStyleVivid;
    if (self.styleControl.selectedSegmentIndex == 2) style = AmeHCTPaletteStyleSoft;
    AmeHCTPalette *palette = [AmeHCTPalette ame429_paletteWithSeed:self.pickedColor style:style];
    // 预览三色 = 主 tone40 / 主容器 tone90 / 三色容器 tone90（浅色态，公开 API）
    NSArray<UIColor *> *previewColors = [palette ame429_previewLightColors];
    if (previewColors.count < 3) return;
    if (self.previewBlocks.count >= 3) {
        self.previewBlocks[0].backgroundColor = previewColors[0];
        self.previewBlocks[1].backgroundColor = previewColors[1];
        self.previewBlocks[2].backgroundColor = previewColors[2];
    }
}

- (void)ame429_refreshConfirmState {
    BOOL ready = (self.pickedColor != nil);
    self.confirmButton.enabled = ready;
    self.confirmButton.backgroundColor = ready ? [ZL2Theme primary]
                                               : [ZL2Theme outlineVariant];
    [self.confirmButton setTitleColor:ready ? [ZL2Theme onPrimary]
                                            : [ZL2Theme onSurfaceVariant]
                             forState:UIControlStateNormal];
}

@end
