#import "utils.h"
#import "ZL2GamePath.h" // ★Task473: ZL2 版本隔离系统单入口
//
//  ModpackExportViewController.m
//  Amethyst
//
//  ★Task428（工作项二 2.3）：导出体验升级为 ZL2 三步向导
//    SelectType → EditInfo → SelectFiles（顶部 1/2/3 步骤指示器 + 上一步/下一步/导出）
//
//  设计口径：
//    步骤 1 选格式：五种格式卡片（Modrinth .mrpack / CurseForge manifest zip /
//      MultiMC / 纯 zip / 链接列表——枚举沿用 ModpackExportService 既有定义），
//      MD3 卡片语言（ZL2M3Kit/ZL2Theme/ZL2SettingCards 既有件）；
//    步骤 2 填信息：实例选择（沿用既有 Profile 数据源与预填逻辑：包名=实例名、
//      版本 1.0、作者 Amethyst User——不造新偏好键）+ 包名/版本号/作者/描述；
//    步骤 3 勾文件：实例目录白名单勾选（目录分组 + 全选/反选 + 常见默认勾选
//      mods/configs/saves/scripts），树数据从实例根目录枚举，排除
//      logs/crash-reports/.DS_Store 等噪声（白名单 = 现有导出 fileOptions 语义）；
//    导出进度与完成页（文件位置提示）沿用既有导出执行链（ModpackExportService）。
//

#import "ModpackExportViewController.h"
#import "AmeNativeMenu.h"       // ★ Task240：菜单全面系统原生 UIMenu 化
#import "BackgroundManager.h"
#import "ModpackExportService.h"
#import "PLProfiles.h"
// ★Task428：三步向导换装 ZL2 域 M3 组件（7.0-UI 判例：色/形/字走 ZL2Theme）
#import "ZL2Theme.h"
#import "ZL2SettingCards.h"

#pragma mark - ★Task428：步骤指示器（1/2/3 圆点 + 连线，CoreGraphics 绘制）

@interface Ame428StepIndicatorView : UIView
@property (nonatomic, assign) NSInteger currentStep;          // 0..2
@property (nonatomic, copy) NSArray<NSString *> *stepTitles;  // 三个短标题
- (void)ame428_setCurrentStep:(NSInteger)step;
@end

@interface Ame428StepIndicatorView ()
@property (nonatomic, strong) NSArray<UILabel *> *titleLabels;
@end

@implementation Ame428StepIndicatorView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.currentStep = 0;
        self.stepTitles = @[@"", @"", @""];
        // 标题用子视图标签（drawRect 只画圆点/连线/数字；标签按 1/3 宽度分栏居中）
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        NSMutableArray<NSLayoutConstraint *> *labelConstraints = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            UILabel *label = [[UILabel alloc] init];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.font = [ZL2Theme fontLabelMedium];
            label.textAlignment = NSTextAlignmentCenter;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.7;
            [self addSubview:label];
            [labels addObject:label];
            // 分栏居中：label.centerX = self.width * (i+1)/3
            // ★Task428-r1：NSLayoutXAxisAnchor 无 multiplier 变体（系统间距除外）——
            //   回退 NSLayoutConstraint constraintWithItem 经典 API（multiplier 原生支持）
            // ★ Task446: 根因修复"Invalid pairing of layout attributes"闪退——原第二属性
            //   写成 NSLayoutAttributeWidth，centerX（水平位置属性）配 width（尺寸属性）
            //   属跨维度配对，iOS 17+ 在 constraintWithItem 创建时即抛异常。
            //   改为 centerX↔centerX + multiplier ×2(i+1)/3：self.centerX = self.width/2，
            //   故 label.centerX = width/2 * 2(i+1)/3 = width*(i+1)/3，与原设计意图等价。
            [labelConstraints addObject:[NSLayoutConstraint
                constraintWithItem:label attribute:NSLayoutAttributeCenterX
                relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterX
                multiplier:((CGFloat)(i + 1) * 2.0 / 3.0) constant:0.0]];
            [labelConstraints addObject:[label.topAnchor constraintEqualToAnchor:self.topAnchor constant:38]];
            [labelConstraints addObject:[label.heightAnchor constraintLessThanOrEqualToConstant:20]];
        }
        self.titleLabels = [labels copy];
        [NSLayoutConstraint activateConstraints:labelConstraints];
    }
    return self;
}

- (void)ame428_setCurrentStep:(NSInteger)step {
    if (step < 0) step = 0;
    if (step > 2) step = 2;
    _currentStep = step;
    for (NSInteger i = 0; i < 3; i++) {
        self.titleLabels[i].text = (i < self.stepTitles.count) ? self.stepTitles[i] : @"";
        self.titleLabels[i].textColor = (i <= step) ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat width = rect.size.width;
    CGFloat cy = 18.0;                    // 圆心高度
    CGFloat radius = 11.0;
    CGFloat gap = 8.0;                    // 圆与连线间隙
    CGFloat xs[3];
    for (NSInteger i = 0; i < 3; i++) {
        xs[i] = width * ((CGFloat)(i + 1) / 3.0);
    }

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    // 连线：已完成段 primary，未到段 outlineVariant
    for (NSInteger i = 0; i < 2; i++) {
        CGFloat x1 = xs[i] + radius + gap;
        CGFloat x2 = xs[i + 1] - radius - gap;
        BOOL done = (i < self.currentStep);
        CGContextSetStrokeColorWithColor(ctx, done ? [ZL2Theme primary].CGColor : [ZL2Theme outlineVariant].CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextMoveToPoint(ctx, x1, cy);
        CGContextAddLineToPoint(ctx, x2, cy);
        CGContextStrokePath(ctx);
    }

    // 圆点 + 数字：当前/已完成 = primary 底 onPrimary 字；未到 = surfaceVariant 底 onSurfaceVariant 字
    for (NSInteger i = 0; i < 3; i++) {
        BOOL reached = (i <= self.currentStep);
        UIColor *fill = reached ? [ZL2Theme primary] : [ZL2Theme surfaceVariant];
        UIColor *numberColor = reached ? [ZL2Theme onPrimary] : [ZL2Theme onSurfaceVariant];

        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(xs[i] - radius, cy - radius, radius * 2, radius * 2));

        NSString *number = [NSString stringWithFormat:@"%ld", (long)(i + 1)];
        NSDictionary *attrs = @{
            NSFontAttributeName: [ZL2Theme fontLabelLarge],
            NSForegroundColorAttributeName: numberColor
        };
        CGSize sz = [number sizeWithAttributes:attrs];
        [number drawAtPoint:CGPointMake(xs[i] - sz.width / 2.0, cy - sz.height / 2.0) withAttributes:attrs];
    }
}

@end

#pragma mark - 导出控制器

@interface ModpackExportViewController ()

// 数据（沿用既有导出链）
@property (nonatomic, strong) NSArray<NSString *> *profileNames;
@property (nonatomic, copy) NSString *selectedProfileName;
@property (nonatomic, assign) ModpackExportFormat selectedFormat;
@property (nonatomic, assign) ModpackExportFileOptions fileOptions;

// ★Task428：向导步骤状态（0=SelectType 1=EditInfo 2=SelectFiles）
@property (nonatomic, assign) NSInteger ame428_step;
// ★Task428：三个步骤内容视图（懒建一次，切换时复挂）
@property (nonatomic, strong, nullable) UIView *ame428_typeView;
@property (nonatomic, strong, nullable) UIView *ame428_infoView;
@property (nonatomic, strong, nullable) UIView *ame428_filesView;

// UI 骨架
@property (nonatomic, strong) Ame428StepIndicatorView *stepIndicator;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStackView;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *nextButton;

// 步骤 1：格式卡片
@property (nonatomic, strong) NSArray<ZL2SettingRowAction *> *formatRows;

// 步骤 2：信息输入
@property (nonatomic, strong) ZL2SettingRowAction *profileRow;
@property (nonatomic, strong) ZL2SettingRowInput *nameInput;
@property (nonatomic, strong) ZL2SettingRowInput *versionInput;
@property (nonatomic, strong) ZL2SettingRowInput *authorInput;
@property (nonatomic, strong) ZL2SettingRowInput *descInput;

// 步骤 3：文件勾选
@property (nonatomic, strong) ZL2SettingCardGroup *filesGroup;
@property (nonatomic, strong) ZL2SettingCardGroup *extraGroup;
@property (nonatomic, strong) NSArray<NSDictionary *> *categorySpecs;   // {bit,title,dirs,files}
@property (nonatomic, strong) NSArray<ZL2SettingRowAction *> *categoryRows;
@property (nonatomic, strong) UIButton *selectAllButton;
@property (nonatomic, strong) UIButton *invertButton;

// 进度卡片（沿用既有导出执行链）
@property (nonatomic, strong) UIView *progressOverlay;
@property (nonatomic, strong) UIView *progressCard;
@property (nonatomic, strong) UILabel *progressTitleLabel;
@property (nonatomic, strong) UILabel *progressPercentLabel;
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, strong) UILabel *progressStageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner;
@property (nonatomic, strong) UIButton *progressCancelButton;

@end

@implementation ModpackExportViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.title = localize(@"i18n_str_490", nil);
    self.view.backgroundColor = [UIColor clearColor];
    [[BackgroundManager sharedManager] applyEffectToView:self.view];

    // ★Task428：默认格式沿用 Modrinth；默认勾选 = 既有 ModpackExportFileDefault
    //   + Saves（报告口径：常见默认勾选 mods/configs/saves/scripts；Servers 维持
    //   既有不默认——含敏感信息，服务层注释既有判定）
    self.selectedFormat = ModpackExportFormatModrinth;
    self.fileOptions = ModpackExportFileDefault | ModpackExportFileSaves;
    self.ame428_step = 0;

    [self loadProfiles];
    [self setupSkeletonUI];
    [self ame428_applyStep:0 animated:NO];
    [self refreshProfileRow];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
}

- (void)loadProfiles {
    NSDictionary *profiles = PLProfiles.current.profiles;
    self.profileNames = [profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (self.profileNames.count == 0) {
        // 没有 profile，禁用导出（步骤指示器照常，下一步按钮置灰）
        return;
    }
    // 预选 profile（沿用既有逻辑：preselected > current > 首个）
    if (self.preselectedProfileName && [self.profileNames containsObject:self.preselectedProfileName]) {
        self.selectedProfileName = self.preselectedProfileName;
    } else {
        NSString *current = PLProfiles.current.selectedProfileName;
        if (current && [self.profileNames containsObject:current]) {
            self.selectedProfileName = current;
        } else {
            self.selectedProfileName = self.profileNames.firstObject;
        }
    }
}

#pragma mark - ★Task428：UI 骨架（指示器 + 滚动内容 + 底部按钮条）

- (void)setupSkeletonUI {
    self.stepIndicator = [[Ame428StepIndicatorView alloc] init];
    self.stepIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.stepIndicator.stepTitles = @[
        localize(@"ame428.export.step1", nil),
        localize(@"ame428.export.step2", nil),
        localize(@"ame428.export.step3", nil)
    ];
    [self.view addSubview:self.stepIndicator];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentStackView = [[UIStackView alloc] init];
    self.contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStackView.axis = UILayoutConstraintAxisVertical;
    self.contentStackView.spacing = [ZL2SettingCardGroup preferredGroupSpacing] + 6;
    self.contentStackView.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStackView];

    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.bottomBar];

    self.prevButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.prevButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.prevButton setTitle:localize(@"ame428.export.prev", nil) forState:UIControlStateNormal];
    self.prevButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    self.prevButton.backgroundColor = [ZL2Theme surfaceContainerHigh];
    self.prevButton.layer.cornerRadius = [ZL2Theme radiusS];
    self.prevButton.layer.masksToBounds = YES;
    [self.prevButton setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
    [self.prevButton addTarget:self action:@selector(ame428_prevStep) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.prevButton];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.nextButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    self.nextButton.backgroundColor = [ZL2Theme primary];
    self.nextButton.layer.cornerRadius = [ZL2Theme radiusS];
    self.nextButton.layer.masksToBounds = YES;
    [self.nextButton setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
    self.nextButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.nextButton.titleLabel.minimumScaleFactor = 0.7;
    [self.nextButton addTarget:self action:@selector(ame428_nextStep) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.nextButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.stepIndicator.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.stepIndicator.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.stepIndicator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.stepIndicator.heightAnchor constraintEqualToConstant:64],

        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:8],
        [self.bottomBar.heightAnchor constraintEqualToConstant:48],

        [self.prevButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
        [self.prevButton.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
        [self.prevButton.bottomAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor],
        [self.prevButton.widthAnchor constraintGreaterThanOrEqualToConstant:96],

        [self.nextButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
        [self.nextButton.leadingAnchor constraintEqualToAnchor:self.prevButton.trailingAnchor constant:12],
        [self.nextButton.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
        [self.nextButton.bottomAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.stepIndicator.bottomAnchor constant:2],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:-4],

        [self.contentStackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:10],
        [self.contentStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16],
        [self.contentStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16],
        [self.contentStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
        [self.contentStackView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32]
    ]];
}

#pragma mark - ★Task428：步骤切换（三步数据流：SelectType → EditInfo → SelectFiles → 导出执行）

- (void)ame428_applyStep:(NSInteger)step animated:(BOOL)animated {
    if (step < 0) step = 0;
    if (step > 2) step = 2;
    self.ame428_step = step;

    // 内容切换：清空 arranged 子视图后挂当前步骤内容（三个步骤视图懒建一次）
    for (UIView *v in [self.contentStackView.arrangedSubviews copy]) {
        [self.contentStackView removeArrangedSubview:v];
        v.hidden = YES;
    }
    UIView *content = nil;
    if (step == 0) {
        content = [self ame428_stepTypeView];
    } else if (step == 1) {
        content = [self ame428_stepInfoView];
    } else {
        // 进入步骤 3 时重建文件清单（实例目录内容可能已变化）
        [self ame428_rebuildFilesGroup];
        content = [self ame428_stepFilesView];
    }
    content.hidden = NO;
    [self.contentStackView addArrangedSubview:content];

    [self.stepIndicator ame428_setCurrentStep:step];
    [self ame428_refreshBottomBar];

    if (animated) {
        [UIView animateWithDuration:0.18 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
    [self.scrollView setContentOffset:CGPointZero animated:NO];
}

- (void)ame428_refreshBottomBar {
    // 上一步：步骤 0 隐藏
    self.prevButton.hidden = (self.ame428_step == 0);
    // 下一步/导出按钮：步骤 2 = 导出（沿用既有导出文案键）
    [self.nextButton setTitle:(self.ame428_step == 2)
            ? localize(@"i18n_str_513", nil)
            : localize(@"ame428.export.next", nil)
        forState:UIControlStateNormal];
    // 可用性：无实例时步骤 0/1/2 全禁；步骤 2 还要求至少勾选一类文件
    BOOL hasProfiles = self.profileNames.count > 0;
    BOOL enabled = hasProfiles;
    if (enabled && self.ame428_step == 2) {
        enabled = (self.fileOptions != 0);
    }
    self.nextButton.enabled = enabled;
    self.nextButton.backgroundColor = enabled ? [ZL2Theme primary] : [ZL2Theme launchDisabledTint];
    [self.nextButton setTitleColor:(enabled ? [ZL2Theme onPrimary] : [ZL2Theme onSurfaceVariant]) forState:UIControlStateNormal];
}

- (void)ame428_prevStep {
    if (self.ame428_step > 0) {
        [self ame428_applyStep:(self.ame428_step - 1) animated:YES];
    }
}

- (void)ame428_nextStep {
    if (self.ame428_step < 2) {
        [self ame428_applyStep:(self.ame428_step + 1) animated:YES];
        return;
    }
    [self startExport];
}

#pragma mark - ★Task428：步骤 1（SelectType）——五种格式卡片

- (UIView *)ame428_stepTypeView {
    if (self.ame428_typeView) return self.ame428_typeView;
    ZL2SettingCardGroup *group = [[ZL2SettingCardGroup alloc] init];
    group.translatesAutoresizingMaskIntoConstraints = NO;
    // ★Task429 N5（第六版报告）：row.onTap block 强捕 self（self → row →
    //   block → self = 保留环）→ __weak weakSelf（对齐全仓惯例）
    __weak typeof(self) weakSelf = self;

    // 格式枚举沿用 ModpackExportService 既有定义（顺序 = 枚举值 0..4）
    NSArray<NSDictionary *> *specs = @[
        @{@"fmt": @(ModpackExportFormatModrinth),
          @"title": localize(@"ame428.export.fmt.modrinth.title", nil),
          @"desc": localize(@"ame428.export.fmt.modrinth.desc", nil)},
        @{@"fmt": @(ModpackExportFormatCurseForge),
          @"title": localize(@"ame428.export.fmt.curseforge.title", nil),
          @"desc": localize(@"ame428.export.fmt.curseforge.desc", nil)},
        @{@"fmt": @(ModpackExportFormatMMC),
          @"title": localize(@"ame428.export.fmt.mmc.title", nil),
          @"desc": localize(@"ame428.export.fmt.mmc.desc", nil)},
        @{@"fmt": @(ModpackExportFormatPlainZip),
          @"title": localize(@"ame428.export.fmt.plainzip.title", nil),
          @"desc": localize(@"ame428.export.fmt.plainzip.desc", nil)},
        @{@"fmt": @(ModpackExportFormatLinkList),
          @"title": localize(@"ame428.export.fmt.linklist.title", nil),
          @"desc": localize(@"ame428.export.fmt.linklist.desc", nil)},
    ];

    NSMutableArray<ZL2SettingRowAction *> *rows = [NSMutableArray array];
    for (NSDictionary *spec in specs) {
        ModpackExportFormat fmt = (ModpackExportFormat)[spec[@"fmt"] integerValue];
        ZL2SettingRowAction *row = [[ZL2SettingRowAction alloc] initWithTitle:spec[@"title"]
                                                                      subtitle:spec[@"desc"]];
        row.onTap = ^{
            weakSelf.selectedFormat = fmt;              // ★Task429 N5：weakSelf 断环
            [weakSelf ame428_refreshFormatSelection];
        };
        [rows addObject:row];
        [group ame_addRow:row];
    }
    self.formatRows = [rows copy];
    [self ame428_refreshFormatSelection];
    self.ame428_typeView = group;
    return group;
}

- (void)ame428_refreshFormatSelection {
    for (ZL2SettingRowAction *row in self.formatRows) {
        NSUInteger idx = [self.formatRows indexOfObject:row];
        ModpackExportFormat fmt = (ModpackExportFormat)idx;   // 行序 = 枚举序
        row.detailText = (fmt == self.selectedFormat) ? localize(@"ame428.export.selected", nil) : @"";
    }
}

#pragma mark - ★Task428：步骤 2（EditInfo）——实例选择 + 包名/版本号/作者/描述

- (UIView *)ame428_stepInfoView {
    if (self.ame428_infoView) return self.ame428_infoView;
    // 组 1：实例选择（沿用既有 Profile 数据源；detailText = 当前实例名）
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    group1.translatesAutoresizingMaskIntoConstraints = NO;

    self.profileRow = [[ZL2SettingRowAction alloc] initWithTitle:localize(@"ame428.export.profile", nil)
                                                        subtitle:nil];
    // ★Task429 N5（第六版报告）：onTap 强捕 self → __weak weakSelf 断保留环
    __weak typeof(self) weakSelf = self;
    self.profileRow.onTap = ^{
        [weakSelf showProfilePicker];
    };
    [group1 ame_addRow:self.profileRow];

    // 组 2：信息输入（预填沿用既有取值：包名=实例名、版本 1.0、作者 Amethyst User）
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    group2.translatesAutoresizingMaskIntoConstraints = NO;

    self.nameInput = [[ZL2SettingRowInput alloc] initWithTitle:localize(@"ame428.export.field.name", nil)
                                                      subtitle:nil
                                                   placeholder:localize(@"ame428.export.field.name.ph", nil)
                                                          text:(self.selectedProfileName ?: @"")];
    self.versionInput = [[ZL2SettingRowInput alloc] initWithTitle:localize(@"ame428.export.field.version", nil)
                                                         subtitle:nil
                                                      placeholder:localize(@"ame428.export.field.version.ph", nil)
                                                             text:@"1.0"];
    self.authorInput = [[ZL2SettingRowInput alloc] initWithTitle:localize(@"ame428.export.field.author", nil)
                                                        subtitle:nil
                                                     placeholder:localize(@"ame428.export.field.author.ph", nil)
                                                            text:@"Amethyst User"];
    self.descInput = [[ZL2SettingRowInput alloc] initWithTitle:localize(@"ame428.export.field.desc", nil)
                                                      subtitle:nil
                                                   placeholder:localize(@"ame428.export.field.desc.ph", nil)
                                                          text:@""];
    [group2 ame_addRows:@[self.nameInput, self.versionInput, self.authorInput, self.descInput]];

    // 外层包装竖栈（两组卡纵向排布）
    UIStackView *wrapper = [[UIStackView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    wrapper.axis = UILayoutConstraintAxisVertical;
    wrapper.spacing = [ZL2SettingCardGroup preferredGroupSpacing] + 6;
    wrapper.alignment = UIStackViewAlignmentFill;
    [wrapper addArrangedSubview:group1];
    [wrapper addArrangedSubview:group2];
    self.ame428_infoView = wrapper;
    return wrapper;
}

- (void)refreshProfileRow {
    if (!self.profileRow) return;
    if (self.profileNames.count == 0) {
        self.profileRow.detailText = @"";
        self.profileRow.subtitle = localize(@"ame428.export.profile.none", nil);
        self.profileRow.errorState = YES;
        return;
    }
    self.profileRow.errorState = NO;
    self.profileRow.detailText = self.selectedProfileName ?: @"";

    NSDictionary *profile = PLProfiles.current.profiles[self.selectedProfileName];
    if (![profile isKindOfClass:[NSDictionary class]]) {
        self.profileRow.subtitle = localize(@"i18n_str_495", nil);
        return;
    }
    // 沿用既有信息口径（loader/mc 版本/gameDir 预览）
    NSString *lastVersionId = profile[@"lastVersionId"] ?: @"";
    NSString *gameDir = profile[@"gameDir"] ?: @".";
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    NSString *mcVer = parsed[@"minecraft"] ?: localize(@"i18n_str_121", nil);
    NSString *loader = parsed[@"loader"] ?: @"vanilla";
    NSString *loaderVer = parsed[@"loaderVersion"] ?: @"";
    self.profileRow.subtitle = [NSString stringWithFormat:localize(@"i18n_str_496", nil),
                                 mcVer, loader, loaderVer, gameDir];
}

- (void)showProfilePicker {
    if (self.profileNames.count == 0) return;

    // ★Task432（P2 强捕 self）：菜单 handler 强捕 self（dict → menu 持有期跨
    //   页面存活）→ 照 Task429 N5 判例形态 __weak weakSelf 断链
    __weak typeof(self) weakSelf = self;
    // ★ Task240：换装系统原生 UIMenu（旧 actionSheet 退役）。
    NSMutableArray<NSDictionary *> *ame240_items = [NSMutableArray array];
    for (NSString *name in self.profileNames) {
        NSString *title = name;
        if ([name isEqualToString:self.selectedProfileName]) {
            title = [NSString stringWithFormat:@"%@ ✓", name];
        }
        [ame240_items addObject:@{
            @"title": title,
            @"handler": ^{
                weakSelf.selectedProfileName = name;   // ★Task432：weakSelf 断链
                [weakSelf refreshProfileRow];
                // 沿用既有行为：包名未编辑（空/仍为旧实例名）时跟随实例切换
                if (weakSelf.nameInput.ame_text.length == 0 ||
                    [weakSelf.profileNames containsObject:weakSelf.nameInput.ame_text]) {
                    [weakSelf.nameInput ame_setText:name];
                }
            },
        }];
    }
    [AmeNativeMenu ame240_presentMenuWithTitle:localize(@"ame428.export.profile", nil)
                                     dictItems:ame240_items
                                    sourceView:self.profileRow ?: self.view];
}

#pragma mark - ★Task428：步骤 3（SelectFiles）——白名单勾选 + 全选/反选

- (UIView *)ame428_stepFilesView {
    if (self.ame428_filesView) return self.ame428_filesView;
    // 白名单类别定义（bit = 既有 ModpackExportFileOptions；标题沿用既有 i18n 键）
    self.categorySpecs = @[
        @{@"bit": @(ModpackExportFileMods),          @"title": localize(@"i18n_str_505", nil), @"dirs": @[@"mods"], @"files": @[]},
        @{@"bit": @(ModpackExportFileConfigs),       @"title": localize(@"i18n_str_506", nil), @"dirs": @[@"config", @"defaultconfigs"], @"files": @[]},
        @{@"bit": @(ModpackExportFileResourcePacks), @"title": localize(@"i18n_str_507", nil), @"dirs": @[@"resourcepacks"], @"files": @[]},
        @{@"bit": @(ModpackExportFileShaderPacks),   @"title": localize(@"i18n_str_508", nil), @"dirs": @[@"shaderpacks"], @"files": @[]},
        @{@"bit": @(ModpackExportFileScripts),       @"title": localize(@"i18n_str_509", nil), @"dirs": @[@"kubejs", @"scripts", @"localization", @"patchouli_books"], @"files": @[]},
        @{@"bit": @(ModpackExportFileGameSettings),  @"title": localize(@"i18n_str_510", nil), @"dirs": @[], @"files": @[@"options.txt", @"optionsof.txt", @"optionsshaders.txt", @"hotbar.nbt"]},
        @{@"bit": @(ModpackExportFileSaves),         @"title": localize(@"i18n_str_511", nil), @"dirs": @[@"saves"], @"files": @[]},
        @{@"bit": @(ModpackExportFileServers),       @"title": localize(@"i18n_str_512", nil), @"dirs": @[], @"files": @[@"servers.dat", @"servers.dat_old", @"realms_persistence.json"]},
    ];

    UIStackView *wrapper = [[UIStackView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    wrapper.axis = UILayoutConstraintAxisVertical;
    wrapper.spacing = [ZL2SettingCardGroup preferredGroupSpacing] + 6;
    wrapper.alignment = UIStackViewAlignmentFill;

    // 全选/反选按钮行（目录分组顶部动作区）
    UIStackView *actionRow = [[UIStackView alloc] init];
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 10;
    actionRow.distribution = UIStackViewDistributionFillEqually;
    actionRow.alignment = UIStackViewAlignmentFill;

    self.selectAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectAllButton setTitle:localize(@"ame428.export.files.selectall", nil) forState:UIControlStateNormal];
    self.selectAllButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    self.selectAllButton.backgroundColor = [ZL2Theme secondaryContainer];
    self.selectAllButton.layer.cornerRadius = [ZL2Theme radiusS];
    self.selectAllButton.layer.masksToBounds = YES;
    [self.selectAllButton setTitleColor:[ZL2Theme onSecondaryContainer] forState:UIControlStateNormal];
    [self.selectAllButton addTarget:self action:@selector(ame428_selectAll) forControlEvents:UIControlEventTouchUpInside];

    self.invertButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.invertButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.invertButton setTitle:localize(@"ame428.export.files.invert", nil) forState:UIControlStateNormal];
    self.invertButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    self.invertButton.backgroundColor = [ZL2Theme surfaceContainerHigh];
    self.invertButton.layer.cornerRadius = [ZL2Theme radiusS];
    self.invertButton.layer.masksToBounds = YES;
    [self.invertButton setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
    [self.invertButton addTarget:self action:@selector(ame428_invertSelection) forControlEvents:UIControlEventTouchUpInside];

    [actionRow addArrangedSubview:self.selectAllButton];
    [actionRow addArrangedSubview:self.invertButton];
    [actionRow.heightAnchor constraintEqualToConstant:40].active = YES;
    [wrapper addArrangedSubview:actionRow];

    // 白名单分组卡（进入本步时 ame428_rebuildFilesGroup 填充行）
    self.filesGroup = [[ZL2SettingCardGroup alloc] init];
    self.filesGroup.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addArrangedSubview:self.filesGroup];

    // 其他目录分组卡（发现但暂不支持打包的顶层目录；只读展示行）
    self.extraGroup = [[ZL2SettingCardGroup alloc] init];
    self.extraGroup.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addArrangedSubview:self.extraGroup];

    // 首建即填充白名单行（applyStep 的重建调用发生在首建前会因 group 尚未存在而空转）
    [self ame428_rebuildFilesGroup];
    self.ame428_filesView = wrapper;
    return wrapper;
}

/// 步骤 3 白名单清单重建：树数据从实例根目录枚举（排除噪声目录/隐藏文件）
- (void)ame428_rebuildFilesGroup {
    if (!self.filesGroup) return;
    [self.filesGroup ame_removeAllRows];
    [self.extraGroup ame_removeAllRows];
    // ★Task429 N5（第六版报告）：onTap 强捕 self → __weak weakSelf 断保留环
    __weak typeof(self) weakSelf = self;

    NSString *gameDir = [self ame428_gameDirForSelectedProfile];

    NSMutableArray<ZL2SettingRowAction *> *rows = [NSMutableArray array];
    NSMutableArray<ZL2SettingRowAction *> *extraRows = [NSMutableArray array];

    for (NSDictionary *spec in self.categorySpecs) {
        ModpackExportFileOptions bit = (ModpackExportFileOptions)[spec[@"bit"] integerValue];
        ZL2SettingRowAction *row = [[ZL2SettingRowAction alloc] initWithTitle:spec[@"title"]
                                                                      subtitle:[self ame428_subtitleForSpec:spec gameDir:gameDir]];
        row.onTap = ^{
            // 勾选语义：位开关（服务层 fileOptions 的既有契约）
            // ★Task429 N5：weakSelf 断环（self → row → block → self）
            if (weakSelf.fileOptions & bit) {
                weakSelf.fileOptions &= ~bit;
            } else {
                weakSelf.fileOptions |= bit;
            }
            [weakSelf ame428_refreshCategoryRows];
            [weakSelf ame428_refreshBottomBar];
        };
        [rows addObject:row];
        [self.filesGroup ame_addRow:row];
    }
    self.categoryRows = [rows copy];
    [self ame428_refreshCategoryRows];

    // 其他目录：非白名单、非噪声的实例顶层目录 → 只读展示（暂不支持打包）
    for (NSString *dirName in [self ame428_extraTopLevelDirsForGameDir:gameDir]) {
        ZL2SettingRowAction *row = [[ZL2SettingRowAction alloc] initWithTitle:dirName
                                                                      subtitle:localize(@"ame428.export.files.unsupported", nil)];
        // onTap = nil → 只读展示行（无 chevron、不响应点击）
        [extraRows addObject:row];
        [self.extraGroup ame_addRow:row];
    }
    self.extraGroup.hidden = (extraRows.count == 0);
}

- (void)ame428_refreshCategoryRows {
    for (NSUInteger i = 0; i < self.categoryRows.count; i++) {
        ModpackExportFileOptions bit = (ModpackExportFileOptions)[self.categorySpecs[i][@"bit"] integerValue];
        self.categoryRows[i].detailText = (self.fileOptions & bit) ? localize(@"ame428.export.selected", nil) : @"";
    }
}

- (void)ame428_selectAll {
    self.fileOptions = ModpackExportFileAll;
    [self ame428_refreshCategoryRows];
    [self ame428_refreshBottomBar];
}

- (void)ame428_invertSelection {
    self.fileOptions = (ModpackExportFileOptions)
        (self.fileOptions ^ ModpackExportFileAll);
    [self ame428_refreshCategoryRows];
    [self ame428_refreshBottomBar];
}

/// 实例根目录（沿用 ModpackExportService 的 gameDir 解析口径；无 profile 时回退主目录）
- (NSString *)ame428_gameDirForSelectedProfile {
    // ★Task473: 导出取材根经 ZL2GamePath 单入口（隔离版本导出 = 版本目录内取材）
    return [ZL2GamePath gameDirForProfile:nil];
}

/// 类别副标题：目录/文件计数 + 体积（NSByteCountFormatter 本地化）；目录不存在给明确提示
- (NSString *)ame428_subtitleForSpec:(NSDictionary *)spec gameDir:(NSString *)gameDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger count = 0;
    unsigned long long bytes = 0;

    for (NSString *dir in spec[@"dirs"]) {
        NSString *dirPath = [gameDir stringByAppendingPathComponent:dir];
        if (![fm fileExistsAtPath:dirPath]) continue;
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:dirPath];
        NSString *rel;
        while ((rel = [e nextObject])) {
            NSString *full = [dirPath stringByAppendingPathComponent:rel];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && !isDir) {
                count++;
                bytes += [[fm attributesOfItemAtPath:full error:nil] fileSize];
            }
        }
    }
    for (NSString *file in spec[@"files"]) {
        NSString *filePath = [gameDir stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:filePath]) {
            count++;
            bytes += [[fm attributesOfItemAtPath:filePath error:nil] fileSize];
        }
    }
    if (count == 0) {
        return localize(@"ame428.export.files.none", nil);
    }
    static NSByteCountFormatter *ame428_fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ame428_fmt = [[NSByteCountFormatter alloc] init];
        ame428_fmt.countStyle = NSByteCountFormatterCountStyleFile;
    });
    return [NSString stringWithFormat:localize(@"ame428.export.files.count", nil),
            (NSInteger)count, [ame428_fmt stringFromByteCount:(long long)bytes]];
}

/// 实例顶层目录枚举：排除白名单目录、噪声（logs/crash-reports/versions/备份/隐藏项）
- (NSArray<NSString *> *)ame428_extraTopLevelDirsForGameDir:(NSString *)gameDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (gameDir.length == 0 || ![fm fileExistsAtPath:gameDir]) return @[];

    // ★Task428 噪声清单（沿用「现有导出排除逻辑」的白名单思路 + 报告点名的噪声目录）
    NSArray<NSString *> *noise = @[@"logs", @"crash-reports", @"versions", @"__MACOSX",
                                   @"screenshots", @"@LRInstances", @".ame269_backup"];
    NSMutableSet<NSString *> *whitelistDirs = [NSMutableSet set];
    for (NSDictionary *spec in self.categorySpecs) {
        for (NSString *dir in spec[@"dirs"]) [whitelistDirs addObject:dir];
    }

    NSMutableArray<NSString *> *extras = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:gameDir error:nil]) {
        if (![name isKindOfClass:[NSString class]] || name.length == 0) continue;
        if ([name hasPrefix:@"."]) continue;                              // .DS_Store 等隐藏项
        if ([noise containsObject:name]) continue;
        if ([name hasSuffix:@"-backup"] || [name hasPrefix:@"ame169_modpack_"]) continue;
        NSString *full = [gameDir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || !isDir) continue;   // 只展示目录
        if ([whitelistDirs containsObject:name]) continue;
        [extras addObject:name];
    }
    return [extras sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark - Export（沿用既有导出执行链）

- (void)startExport {
    if (self.profileNames.count == 0 || !self.selectedProfileName) {
        [self showAlertWithTitle:localize(@"i18n_str_514", nil) message:localize(@"i18n_str_515", nil)];
        return;
    }
    if (self.fileOptions == 0) {
        [self showAlertWithTitle:localize(@"i18n_str_514", nil) message:localize(@"i18n_str_516", nil)];
        return;
    }

    // 信息字段（沿用既有缺省口径；描述字段当前仅入向导状态，格式规范无对应键位）
    NSString *name = self.nameInput.ame_text ?: @"";
    NSString *version = self.versionInput.ame_text ?: @"1.0";
    NSString *author = self.authorInput.ame_text ?: @"Amethyst User";
    if (name.length == 0) name = self.selectedProfileName;
    if (version.length == 0) version = @"1.0";
    if (author.length == 0) author = @"Amethyst User";

    // 确定扩展名（沿用既有映射）
    NSString *ext = @"zip";
    switch (self.selectedFormat) {
        case ModpackExportFormatModrinth:   ext = @"mrpack"; break;
        case ModpackExportFormatCurseForge: ext = @"zip";    break;
        case ModpackExportFormatMMC:        ext = @"zip";    break;
        case ModpackExportFormatPlainZip:   ext = @"zip";    break;
        case ModpackExportFormatLinkList:   ext = @"txt";    break;
    }

    // 文件名清理（沿用既有实现）
    NSString *destPath = [self buildExportPathWithName:name version:version ext:ext];

    [self showProgressCardWithTitle:localize(@"i18n_str_517", nil)];
    [self setProgress:0.0 stageMessage:localize(@"i18n_str_518", nil)];

    // 重置取消状态
    [[ModpackExportService sharedService] resetCancelState];

    // ★Task432（P2 强捕 self）：后台导出块 + 内嵌 progress 回调 + 收尾块三层
    //   强捕 self（导出耗时期间整页被 GCD 链强持有）→ 照 Task429 N5 判例
    //   形态 weakSelf/strongSelf 断链（进块强取，页面已释放则安全放弃）。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        BOOL success = NO;
        // ★Task431（用户报告「导出整合包闪退」，无设备报告文件）：后台导出链
        //   整体套 @try 网——UZKArchive（预编译 framework，内部含 raise 路径）/
        //   JSON 序列化/字典插 nil 等 NSException 类崩溃（后台线程异常 =
        //   hooked_abort 直杀、无机会走 UI 错误分支）在本页转成可见错误弹窗，
        //   完整异常栈落 latestlog（[ModpackExport][Task431] 前缀，配合
        //   reportProgress 既有逐阶段面包屑一击定位阶段）。非异常类崩溃
        //   （jetsam/EXC_BAD_ACCESS）不受此网影响，仍走系统崩溃取证。
        @try {
            success = [[ModpackExportService sharedService] exportModpackForProfile:strongSelf.selectedProfileName
                                                                             toPath:destPath
                                                                                name:name
                                                                             version:version
                                                                              author:author
                                                                             format:strongSelf.selectedFormat
                                                                        fileOptions:strongSelf.fileOptions
                                                                           progress:^(double p, NSString *stageMessage) {
                __strong typeof(weakSelf) progressSelf = weakSelf;
                if (!progressSelf) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf setProgress:p stageMessage:stageMessage];
                });
            }
                                                                             error:&error];
        } @catch (NSException *ame431_exc) {
            NSLog(@"[ModpackExport][Task431] export exception: %@ (%@)\n%@", ame431_exc.name, ame431_exc.reason, ame431_exc.callStackSymbols);
            error = [NSError errorWithDomain:@"ModpackExportService" code:999
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"export exception: %@ (%@)",
                                             ame431_exc.name, ame431_exc.reason ?: @""]}];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) finishSelf = weakSelf;
            if (!finishSelf) return;
            BOOL wasCancelled = [[error.userInfo objectForKey:NSLocalizedDescriptionKey] containsString:localize(@"Cancel", @"取消")];
            [finishSelf hideProgressCard];
            if (success) {
                [finishSelf showExportSuccessWithPath:destPath];
            } else if (wasCancelled) {
                [finishSelf showAlertWithTitle:localize(@"i18n_str_127", nil) message:localize(@"i18n_str_469", nil)];
            } else {
                [finishSelf showAlertWithTitle:localize(@"i18n_str_519", nil) message:error.localizedDescription ?: localize(@"i18n_str_97", nil)];
            }
        });
    });
}

- (NSString *)buildExportPathWithName:(NSString *)name version:(NSString *)version ext:(NSString *)ext {
    NSString *exportsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Exports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:exportsDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSMutableString *safeName = [[[name componentsSeparatedByCharactersInSet:invalidChars] componentsJoinedByString:@"_"] mutableCopy];

    while (safeName.length > 0 && ([safeName hasPrefix:@" "] || [safeName hasPrefix:@"."])) {
        [safeName deleteCharactersInRange:NSMakeRange(0, 1)];
    }
    while (safeName.length > 0 && ([safeName hasSuffix:@" "] || [safeName hasSuffix:@"."])) {
        [safeName deleteCharactersInRange:NSMakeRange(safeName.length - 1, 1)];
    }
    NSArray *reservedNames = @[@"CON", @"PRN", @"AUX", @"NUL",
        @"COM1", @"COM2", @"COM3", @"COM4", @"COM5", @"COM6", @"COM7", @"COM8", @"COM9",
        @"LPT1", @"LPT2", @"LPT3", @"LPT4", @"LPT5", @"LPT6", @"LPT7", @"LPT8", @"LPT9"];
    if ([reservedNames containsObject:safeName.uppercaseString]) {
        [safeName appendString:@"_modpack"];
    }
    if (safeName.length > 200) {
        [safeName deleteCharactersInRange:NSMakeRange(200, safeName.length - 200)];
    }
    if (safeName.length == 0) {
        [safeName setString:@"ExportedModpack"];
    }

    // 版本号也清理
    NSMutableString *safeVersion = [[[version componentsSeparatedByCharactersInSet:invalidChars] componentsJoinedByString:@"_"] mutableCopy];
    if (safeVersion.length == 0) {
        [safeVersion setString:@"1.0"];
    }

    return [exportsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-v%@.%@", safeName, safeVersion, ext]];
}

#pragma mark - Progress Card（沿用既有链；配色迁移 ZL2Theme 保持页面一致）

- (void)showProgressCardWithTitle:(NSString *)title {
    [self hideProgressCard];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [self.view addSubview:overlay];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [ZL2Theme surfaceContainerHigh];
    card.layer.cornerRadius = [ZL2Theme radiusXL];
    card.layer.masksToBounds = YES;
    [overlay addSubview:card];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [ZL2Theme fontTitleLarge];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:titleLabel];

    UILabel *percentLabel = [[UILabel alloc] init];
    percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    percentLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightHeavy];
    percentLabel.textColor = [ZL2Theme onSurface];
    percentLabel.textAlignment = NSTextAlignmentCenter;
    percentLabel.text = @"0%";
    [card addSubview:percentLabel];

    UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.progressTintColor = [ZL2Theme primary];
    [card addSubview:bar];

    UILabel *stageLabel = [[UILabel alloc] init];
    stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    stageLabel.font = [ZL2Theme fontBodyMedium];
    stageLabel.textColor = [ZL2Theme onSurfaceVariant];
    stageLabel.textAlignment = NSTextAlignmentCenter;
    stageLabel.numberOfLines = 0;
    [card addSubview:stageLabel];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.color = [ZL2Theme primary];
    spinner.hidesWhenStopped = YES;
    [card addSubview:spinner];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelBtn setTitle:localize(@"i18n_str_520", nil) forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [ZL2Theme fontLabelLarge];
    [cancelBtn setTitleColor:[ZL2Theme error] forState:UIControlStateNormal];
    [cancelBtn addTarget:self action:@selector(cancelExport) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:300],

        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],

        [percentLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [percentLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [spinner.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [spinner.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [bar.topAnchor constraintEqualToAnchor:percentLabel.bottomAnchor constant:12],
        [bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [bar.heightAnchor constraintEqualToConstant:8],

        [stageLabel.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:12],
        [stageLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stageLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],

        [cancelBtn.topAnchor constraintEqualToAnchor:stageLabel.bottomAnchor constant:16],
        [cancelBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20]
    ]];

    self.progressOverlay = overlay;
    self.progressCard = card;
    self.progressTitleLabel = titleLabel;
    self.progressPercentLabel = percentLabel;
    self.progressBar = bar;
    self.progressStageLabel = stageLabel;
    self.progressSpinner = spinner;
    self.progressCancelButton = cancelBtn;

    [self setProgress:-1 stageMessage:localize(@"i18n_str_2052", nil)];
}

- (void)setProgress:(double)progress stageMessage:(NSString *)stageMessage {
    if (!self.progressCard) return;

    if (progress < 0) {
        self.progressBar.hidden = YES;
        self.progressPercentLabel.hidden = YES;
        self.progressSpinner.hidden = NO;
        [self.progressSpinner startAnimating];
    } else {
        self.progressBar.hidden = NO;
        self.progressPercentLabel.hidden = NO;
        self.progressSpinner.hidden = YES;
        [self.progressSpinner stopAnimating];
        double clamped = MAX(0.0, MIN(1.0, progress));
        NSInteger percent = (NSInteger)(clamped * 100);
        self.progressPercentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
        [self.progressBar setProgress:(float)clamped animated:YES];
    }
    self.progressStageLabel.text = stageMessage ?: @"";
}

- (void)hideProgressCard {
    if (self.progressOverlay) {
        [self.progressOverlay removeFromSuperview];
        self.progressOverlay = nil;
        self.progressCard = nil;
        self.progressTitleLabel = nil;
        self.progressPercentLabel = nil;
        self.progressBar = nil;
        self.progressStageLabel = nil;
        self.progressSpinner = nil;
        self.progressCancelButton = nil;
    }
}

- (void)cancelExport {
    // 真正取消：通过 service 的 cancel 信号
    [ModpackExportService sharedService].cancelled = YES;
    [self setProgress:-1 stageMessage:localize(@"i18n_str_521", nil)];
}

#pragma mark - 完成提示（沿用既有链：文件位置提示 + 分享）

- (void)showExportSuccessWithPath:(NSString *)path {
    // ★Task432（P2 强捕 self 同族补漏）：动作回调强捕 self → weakSelf 断链
    //   （弹窗在屏期间 presented 栈互持不受影响；行为与 Task429 N5 判例一致）
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_522", nil)
                                                                   message:[NSString stringWithFormat:localize(@"i18n_str_523", nil), path]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_141", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_524", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf shareExportedFile:path];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareExportedFile:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
        [[BackgroundManager sharedManager] applyEffectToView:self.view];
        [self.stepIndicator setNeedsDisplay];
    });
}

@end
