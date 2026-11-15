//
// ZL2ThemeCustomSheet.m — ★Task429（PDF 第五版 §8.1）CUSTOM 取色弹层实现
//
// 组件口径：ZL2Theme 令牌 + M3 圆角/字体阶（本 TU 自包含，无 ZL2M3Kit 依赖
// ——ZL2M3Kit.m 归并行工位 E，勿引）。确认写键触发生效链：
//   写 general.custom_seed_color / general.custom_palette_style /
//   general.theme_mode=8 → [ZL2DynamicPalette ame429_reloadAndApply]
//   → HCT 色板 → 推 ZL2Theme 活动覆盖层 → Task346 根重建。
//

#import "ZL2ThemeCustomSheet.h"

#import "ZL2Theme.h"
#import "AmeHCTPalette.h"
#import "ZL2DynamicPalette.h"
#import "LauncherPreferences.h"   // setPrefString/setPrefInt（注册面归主控合流）
#import "utils.h"                 // localize

#pragma mark - 常量实名表（★Task429）

// 12 主色圆点种子（与 AmeHCTPalette 视觉家族同域；hex 注释直读）
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

// 三新键（与 ZL2DynamicPalette.m 同名常量逐字一致；注册面归主控合流）
static NSString * const Ame429SheetKeyThemeMode       = @"general.theme_mode";
static NSString * const Ame429SheetKeyCustomSeedColor = @"general.custom_seed_color";
static NSString * const Ame429SheetKeyPaletteStyle    = @"general.custom_palette_style";

@interface ZL2ThemeCustomSheet ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *seedLabel;
@property (nonatomic, strong) UIView *dotBoard;                      // 圆点画布（两行网格）
@property (nonatomic, strong) NSMutableArray<UIView *> *dotWraps;    // 选中环宿主引用
@property (nonatomic, strong) UISegmentedControl *styleControl;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIStackView *previewRow;
@property (nonatomic, strong) NSMutableArray<UIView *> *previewBlocks;
@property (nonatomic, strong) NSMutableArray<UILabel *> *previewCaptions;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, assign) NSInteger selectedDotIndex;            // -1 = 未选
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

    // ── 种子色段 ──
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

    // ── 调色风格段 ──
    UILabel *styleLabel = [[UILabel alloc] init];
    styleLabel.text = localize(@"ame429.f.custom.style", @"调色风格");
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
        // 预览行高
        [self.previewRow.heightAnchor constraintEqualToConstant:Ame429SheetPreviewHeight],
    ]];

    [self ame429_refreshPreview];   // 初次渲染（未选种子 = 描边占位态）
    [self ame429_refreshConfirmState];
}

// 圆点（两行网格：行内 x = i % 6，行 y = i / 6；anchor 三参口径）
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

#pragma mark - 交互

- (void)ame429_dotTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 1;   // tag = 序号 + 1（0 非法值隔离）
    if (index < 0 || index >= 12) return;   // 防御守卫
    self.selectedDotIndex = index;
    for (NSUInteger i = 0; i < self.dotWraps.count; i++) {
        self.dotWraps[i].hidden = (NSInteger)i != index;
    }
    [self ame429_refreshPreview];
    [self ame429_refreshConfirmState];
}

- (void)ame429_styleChanged {
    [self ame429_refreshPreview];
}

- (void)ame429_closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ame429_confirmTapped {
    if (self.selectedDotIndex < 0 || self.selectedDotIndex >= 12) return;   // 防御守卫

    int hex = Ame429CustomSeedDots[self.selectedDotIndex];
    NSString *hexString = [NSString stringWithFormat:@"#%06X", (unsigned int)hex];
    NSInteger style = self.styleControl.selectedSegmentIndex;

    // 三键落盘（setPrefString/setPrefInt = PLPreferences 写面；注册面归主控
    // 合流——未注册期写值静默丢弃，读侧缺键回退默认）
    setPrefString(Ame429SheetKeyCustomSeedColor, hexString);
    setPrefInt(Ame429SheetKeyPaletteStyle, style);
    setPrefInt(Ame429SheetKeyThemeMode, (NSInteger)Ame429ThemeModeCustom);

    // 生效链：HCT 色板 → 推 ZL2Theme 活动覆盖层 → Task346 根重建
    [[ZL2DynamicPalette shared] ame429_reloadAndApply];

    NSLog(@"[Ame429] custom sheet confirm seed=%@ style=%ld", hexString, (long)style);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 预览刷新（实时）

- (void)ame429_refreshPreview {
    // 预览色 = 当前圆点 + 风格的 HCT 三角色（浅色态 tone 40/90/90三板）；
    // 未选种子时三块维持占位（surfaceVariant），caption 灰显。
    if (self.selectedDotIndex < 0 || self.selectedDotIndex >= 12) {
        for (UIView *block in self.previewBlocks) {
            block.backgroundColor = [ZL2Theme surfaceVariant];
        }
        return;
    }
    int hex = Ame429CustomSeedDots[self.selectedDotIndex];
    UIColor *seed = [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                                    green:((hex >> 8) & 0xFF) / 255.0
                                     blue:(hex & 0xFF) / 255.0
                                    alpha:1.0];
    AmeHCTPaletteStyle style = AmeHCTPaletteStyleNatural;
    if (self.styleControl.selectedSegmentIndex == 1) style = AmeHCTPaletteStyleVivid;
    if (self.styleControl.selectedSegmentIndex == 2) style = AmeHCTPaletteStyleSoft;
    AmeHCTPalette *palette = [AmeHCTPalette ame429_paletteWithSeed:seed style:style];
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
    BOOL ready = (self.selectedDotIndex >= 0);
    self.confirmButton.enabled = ready;
    self.confirmButton.backgroundColor = ready ? [ZL2Theme primary]
                                               : [ZL2Theme outlineVariant];
    [self.confirmButton setTitleColor:ready ? [ZL2Theme onPrimary]
                                            : [ZL2Theme onSurfaceVariant]
                             forState:UIControlStateNormal];
}

@end
