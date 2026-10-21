//
// ZL2HomeViewController.m — ZL2 风格主页实现（7.0-UI-8：全面对标 ZalithLauncher 2）
//
// 信息架构（竖向滚动单列，内容最大宽 520pt，单侧边距 20，垂直间距 16）：
//   问候区（Prisma Launcher / Minecraft: Java Edition · 测试版）
//   → 账户卡（点击 → @"ShowAccountManager"）
//   → 版本选择卡（点击 → @"ZL2ShellNavigate" index=2）
//   → 大圆形启动按钮 92×92 + 三态状态 label（登录并启动 / 下载中 / 启动游戏）
//   → 快捷入口 chips（版本管理 2 / 下载中心 1 / 设置 4 → @"ZL2ShellNavigate"）
//
// 启动链 1:1 复用旧 LauncherRightPanelViewController L1403-1550 语义（与旧右
// 面板 UI 解耦）：self.task 反查统一进度页 → 无账号挂 pending 后切账户页
// （@"UpdateAccountInfo" 回来自动续启动）→ ShowHomePage 旧契约 → profile/
// versionId 校验 → lastPlayed 时间戳 → @"FindVersionInRemoteList" 回调回调
// → MinecraftResourceDownloadTask 下载 + KVO 百分比刷新（handleError 桩遵循
// KVO 野指针纪律：task=nil 之前先移除观察者）。任务完成后统一进度页由任务
// 内部（autoPresentDetail）接管，本页仅收尾刷新。
//
// 红线遵守：iOS 14.0+（无 button.configuration 等 iOS 15+ API；SF 符号全为
// SF1.0 级并带旧名 fallback）；颜色/字体/圆角一律取 ZL2Theme 动态令牌（无
// traitCollection 分支）；全部子视图 translatesAutoresizingMaskIntoConstraints
// = NO；视图身份直接属性持有（sender.tag 仅作导航页序载荷，不做 viewWithTag:
// 身份查找）；alert 一律 present 到本 VC。
//

#import "ZL2HomeViewController.h"
#import "ZL2Theme.h"
#import "authenticator/BaseAuthenticator.h"
#import "PLProfiles.h"
#import "MinecraftResourceDownloadTask.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskProgressViewController.h"
#import "utils.h"   // localize()

// KVO 观察上下文（旧链 ProgressObserverContext 同款静态指针判别，防父类/他人混淆）
static void *ZL2HomeProgressObserverContext = &ZL2HomeProgressObserverContext;

// 内容列最大宽（iPad 横屏居中；iPhone 占满减边距）
static const CGFloat ZL2HomeContentMaxWidth = 520;

// SF Symbols 取图兜底（本页符号全为 SF1.0 级，正常路径不会走 fallback；
// 保留兜底是历史判例纪律：符号名异常时降级到旧名而不是空白）
static UIImage *ZL2HomeSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

@interface ZL2HomeViewController ()

// 布局
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *greetingTitleLabel;
@property (nonatomic, strong) UILabel *greetingSubtitleLabel;

// 账户卡
@property (nonatomic, strong) UIView *accountCard;
@property (nonatomic, strong) UIImageView *accountIconView;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UIImageView *accountChevronView;

// 版本选择卡
@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) UIView *versionIconBg;
@property (nonatomic, strong) UIImageView *versionIconView;
@property (nonatomic, strong) UILabel *profileNameLabel;
@property (nonatomic, strong) UILabel *versionIdLabel;
@property (nonatomic, strong) UILabel *switchLabel;

// 启动区
@property (nonatomic, strong) UIControl *launchButton;
@property (nonatomic, strong) UIImageView *playIconView;
@property (nonatomic, strong) UILabel *launchStatusLabel;

// 快捷 chips 行（水平 StackView，外层容器负责整行居中）
@property (nonatomic, strong) UIStackView *chipsStack;

// 启动链状态
@property (nonatomic, strong) MinecraftResourceDownloadTask *task;
// FCL 风格：无账号点启动 → 挂标记切账户页，登录成功（UpdateAccountInfo）自动续启动
@property (nonatomic, assign) BOOL ame_pendingLaunchAfterLogin;
// 启动链进行中（FindVersionInRemoteList 反查 → 下载就绪的窗口期防双击；
// 与 self.task 一并构成按钮禁用的单一来源，恢复交互时统一清位）
@property (nonatomic, assign) BOOL ame_launchChainActive;

@end

@implementation ZL2HomeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    [self buildViews];
    [self refreshLaunchState];

    // 通知监听：账号信息变化 / 壳切回主页 → 刷新三态；dealloc 统一移除
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountOrHomeDidChange:)
                                                 name:@"UpdateAccountInfo"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountOrHomeDidChange:)
                                                 name:@"ShowHomePage"
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLaunchState];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // 异常路径兜底：若 KVO 仍在观察（handleError/完成分支均未触达），解除注册
    @try {
        [self.task.progress removeObserver:self
                                forKeyPath:@"fractionCompleted"
                                   context:ZL2HomeProgressObserverContext];
    } @catch (NSException *e) {}
}

#pragma mark - Layout

- (void)buildViews {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.backgroundColor = [ZL2Theme surface];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.spacing = 16;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];

    [self buildGreetingBlock];
    [self buildAccountCard];
    [self buildVersionCard];
    [self buildLaunchArea];
    [self buildChipsRow];

    UILayoutGuide *contentLG = _scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = _scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:24],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.bottomAnchor constant:24],
        // 两侧 inequality 边距：窄屏时被 999 宽度等式推到贴边（=20），宽屏时
        // 与 centerX/<=520 联立自动让位（列居中，不越界）
        [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.trailingAnchor constant:20],
        [_contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        // 最大宽 520（spec：widthAnchor <= constant）
        [_contentStack.widthAnchor constraintLessThanOrEqualToConstant:ZL2HomeContentMaxWidth],
    ]];
    // 宽度正定（优先级 999）：窄屏占满可用宽（frame-40）；与 <=520 上限联立后
    // 宽屏（iPad 横屏）由求解器收敛到 520（999 误差最小解），centerX 居中
    NSLayoutConstraint *fillWidth = [_contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor
                                                                              constant:-40];
    fillWidth.priority = 999;
    fillWidth.active = YES;
}

- (void)buildGreetingBlock {
    _greetingTitleLabel = [[UILabel alloc] init];
    _greetingTitleLabel.text = @"Prisma Launcher";
    _greetingTitleLabel.font = [ZL2Theme fontHeadline];
    _greetingTitleLabel.textColor = [ZL2Theme onSurface];
    _greetingTitleLabel.textAlignment = NSTextAlignmentCenter;
    _greetingTitleLabel.numberOfLines = 1;
    _greetingTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _greetingTitleLabel.isAccessibilityElement = YES;
    _greetingTitleLabel.accessibilityLabel = @"Prisma Launcher";

    _greetingSubtitleLabel = [[UILabel alloc] init];
    _greetingSubtitleLabel.text = @"Minecraft: Java Edition · 测试版";
    _greetingSubtitleLabel.font = [ZL2Theme fontBodyMedium];
    _greetingSubtitleLabel.textColor = [ZL2Theme onSurfaceVariant];
    _greetingSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    _greetingSubtitleLabel.numberOfLines = 1;
    _greetingSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [_contentStack addArrangedSubview:_greetingTitleLabel];
    [_contentStack addArrangedSubview:_greetingSubtitleLabel];
}

- (void)buildAccountCard {
    _accountCard = [[UIView alloc] init];
    _accountCard.backgroundColor = [ZL2Theme surfaceContainer];
    _accountCard.layer.cornerRadius = [ZL2Theme radiusM];
    _accountCard.translatesAutoresizingMaskIntoConstraints = NO;
    _accountCard.isAccessibilityElement = YES;
    _accountCard.accessibilityTraits = UIAccessibilityTraitButton;

    UIImage *personImage = ZL2HomeSystemImage(@"person.crop.circle.fill", @"person.circle.fill");
    _accountIconView = [[UIImageView alloc] initWithImage:[personImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _accountIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _accountIconView.contentMode = UIViewContentModeScaleAspectFit;
    _accountIconView.translatesAutoresizingMaskIntoConstraints = NO;

    _accountNameLabel = [[UILabel alloc] init];
    _accountNameLabel.font = [ZL2Theme fontTitleMedium];
    _accountNameLabel.textColor = [ZL2Theme onSurface];
    _accountNameLabel.numberOfLines = 1;
    _accountNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *chevronImage = ZL2HomeSystemImage(@"chevron.right", @"chevron.forward");
    _accountChevronView = [[UIImageView alloc] initWithImage:[chevronImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _accountChevronView.tintColor = [ZL2Theme onSurfaceVariant];
    _accountChevronView.contentMode = UIViewContentModeScaleAspectFit;
    _accountChevronView.translatesAutoresizingMaskIntoConstraints = NO;

    [_accountCard addSubview:_accountIconView];
    [_accountCard addSubview:_accountNameLabel];
    [_accountCard addSubview:_accountChevronView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(accountCardTapped)];
    [_accountCard addGestureRecognizer:tap];

    [_contentStack addArrangedSubview:_accountCard];
    [NSLayoutConstraint activateConstraints:@[
        [_accountCard.heightAnchor constraintEqualToConstant:64],
        [_accountIconView.leadingAnchor constraintEqualToAnchor:_accountCard.leadingAnchor constant:16],
        [_accountIconView.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountIconView.widthAnchor constraintEqualToConstant:28],
        [_accountIconView.heightAnchor constraintEqualToConstant:28],
        [_accountNameLabel.leadingAnchor constraintEqualToAnchor:_accountIconView.trailingAnchor constant:12],
        [_accountNameLabel.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountChevronView.leadingAnchor constant:-8],
        [_accountChevronView.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-16],
        [_accountChevronView.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountChevronView.widthAnchor constraintEqualToConstant:15],
        [_accountChevronView.heightAnchor constraintEqualToConstant:15],
    ]];
}

- (void)buildVersionCard {
    _versionCard = [[UIView alloc] init];
    _versionCard.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _versionCard.layer.cornerRadius = [ZL2Theme radiusL];
    _versionCard.translatesAutoresizingMaskIntoConstraints = NO;
    _versionCard.isAccessibilityElement = YES;
    _versionCard.accessibilityTraits = UIAccessibilityTraitButton;

    _versionIconBg = [[UIView alloc] init];
    _versionIconBg.backgroundColor = [ZL2Theme primaryContainer];
    _versionIconBg.layer.cornerRadius = [ZL2Theme radiusS];
    _versionIconBg.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *controllerImage = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
    _versionIconView = [[UIImageView alloc] initWithImage:[controllerImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _versionIconView.tintColor = [ZL2Theme onPrimaryContainer];
    _versionIconView.contentMode = UIViewContentModeScaleAspectFit;
    _versionIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_versionIconBg addSubview:_versionIconView];

    _profileNameLabel = [[UILabel alloc] init];
    _profileNameLabel.font = [ZL2Theme fontTitleMedium];
    _profileNameLabel.textColor = [ZL2Theme onSurface];
    _profileNameLabel.numberOfLines = 1;
    _profileNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _versionIdLabel = [[UILabel alloc] init];
    _versionIdLabel.font = [ZL2Theme fontBodyMedium];
    _versionIdLabel.textColor = [ZL2Theme onSurfaceVariant];
    _versionIdLabel.numberOfLines = 1;
    _versionIdLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *textStack = [[UIStackView alloc] init];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [textStack addArrangedSubview:_profileNameLabel];
    [textStack addArrangedSubview:_versionIdLabel];

    _switchLabel = [[UILabel alloc] init];
    _switchLabel.text = @"切换";
    _switchLabel.font = [ZL2Theme fontLabelLarge];
    _switchLabel.textColor = [ZL2Theme primary];
    _switchLabel.numberOfLines = 1;
    _switchLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [_versionCard addSubview:_versionIconBg];
    [_versionCard addSubview:textStack];
    [_versionCard addSubview:_switchLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(versionCardTapped)];
    [_versionCard addGestureRecognizer:tap];

    [_contentStack addArrangedSubview:_versionCard];
    [NSLayoutConstraint activateConstraints:@[
        [_versionCard.heightAnchor constraintEqualToConstant:76],
        [_versionIconBg.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:16],
        [_versionIconBg.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],
        [_versionIconBg.widthAnchor constraintEqualToConstant:44],
        [_versionIconBg.heightAnchor constraintEqualToConstant:44],
        [_versionIconView.centerXAnchor constraintEqualToAnchor:_versionIconBg.centerXAnchor],
        [_versionIconView.centerYAnchor constraintEqualToAnchor:_versionIconBg.centerYAnchor],
        [_versionIconView.widthAnchor constraintEqualToConstant:22],
        [_versionIconView.heightAnchor constraintEqualToConstant:22],
        [textStack.leadingAnchor constraintEqualToAnchor:_versionIconBg.trailingAnchor constant:12],
        [textStack.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_switchLabel.leadingAnchor constant:-8],
        [_switchLabel.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-16],
        [_switchLabel.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],
    ]];
}

- (void)buildLaunchArea {
    _launchButton = [[UIControl alloc] init];
    _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
    // 92×92 圆形（cornerRadius 46 = 直径一半）
    _launchButton.layer.cornerRadius = 46;
    // 轻微阴影：black alpha 0.18 / radius 12 / offset(0,4)
    _launchButton.layer.shadowColor = UIColor.blackColor.CGColor;
    _launchButton.layer.shadowOpacity = 0.18f;
    _launchButton.layer.shadowRadius = 12.0f;
    _launchButton.layer.shadowOffset = CGSizeMake(0, 4);

    UIImage *playImage = ZL2HomeSystemImage(@"play.fill", @"play");
    _playIconView = [[UIImageView alloc] initWithImage:[playImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _playIconView.contentMode = UIViewContentModeScaleAspectFit;
    _playIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchButton addSubview:_playIconView];

    [_launchButton addTarget:self
                      action:@selector(launchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];

    _launchStatusLabel = [[UILabel alloc] init];
    _launchStatusLabel.font = [ZL2Theme fontLabelLarge];
    _launchStatusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _launchStatusLabel.textAlignment = NSTextAlignmentCenter;
    _launchStatusLabel.numberOfLines = 1;
    _launchStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchStatusLabel.isAccessibilityElement = YES;

    UIStackView *launchStack = [[UIStackView alloc] init];
    launchStack.axis = UILayoutConstraintAxisVertical;
    launchStack.alignment = UIStackViewAlignmentCenter;
    launchStack.spacing = 10; // 状态 label 顶部间距 10
    launchStack.translatesAutoresizingMaskIntoConstraints = NO;
    [launchStack addArrangedSubview:_launchButton];
    [launchStack addArrangedSubview:_launchStatusLabel];

    [_contentStack addArrangedSubview:launchStack];
    [NSLayoutConstraint activateConstraints:@[
        [_launchButton.widthAnchor constraintEqualToConstant:92],
        [_launchButton.heightAnchor constraintEqualToConstant:92],
        [_playIconView.centerXAnchor constraintEqualToAnchor:_launchButton.centerXAnchor],
        [_playIconView.centerYAnchor constraintEqualToAnchor:_launchButton.centerYAnchor],
        [_playIconView.widthAnchor constraintEqualToConstant:34],
        [_playIconView.heightAnchor constraintEqualToConstant:34],
    ]];
}

- (void)buildChipsRow {
    // 外层容器占满内容列宽，chipsStack 整行水平居中
    UIView *chipsContainer = [[UIView alloc] init];
    chipsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    _chipsStack = [[UIStackView alloc] init];
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.spacing = 10;
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;

    // 页序载荷与壳契约对齐：0 主页 / 1 下载 / 2 版本管理 / 3 账户 / 4 设置
    UIControl *versionChip = [self chipWithTitle:@"版本管理"];
    versionChip.tag = 2;
    UIControl *downloadChip = [self chipWithTitle:@"下载中心"];
    downloadChip.tag = 1;
    UIControl *settingsChip = [self chipWithTitle:@"设置"];
    settingsChip.tag = 4;

    [_chipsStack addArrangedSubview:versionChip];
    [_chipsStack addArrangedSubview:downloadChip];
    [_chipsStack addArrangedSubview:settingsChip];

    [chipsContainer addSubview:_chipsStack];
    [NSLayoutConstraint activateConstraints:@[
        [_chipsStack.centerXAnchor constraintEqualToAnchor:chipsContainer.centerXAnchor],
        [_chipsStack.topAnchor constraintEqualToAnchor:chipsContainer.topAnchor],
        [_chipsStack.bottomAnchor constraintEqualToAnchor:chipsContainer.bottomAnchor],
    ]];

    [_contentStack addArrangedSubview:chipsContainer];
}

- (UIControl *)chipWithTitle:(NSString *)title {
    UIControl *chip = [[UIControl alloc] init];
    chip.backgroundColor = [ZL2Theme surfaceVariant];
    chip.layer.cornerRadius = [ZL2Theme radiusS];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    // sender.tag 仅作 ZL2ShellNavigate 页序载荷（不经 viewWithTag: 做身份查找）
    chip.isAccessibilityElement = YES;
    chip.accessibilityLabel = title;
    chip.accessibilityTraits = UIAccessibilityTraitButton;

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [chip addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:chip.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor constant:-8],
    ]];

    [chip addTarget:self
             action:@selector(chipTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    return chip;
}

#pragma mark - State Refresh (public)

- (void)refreshLaunchState {
    // —— 账户卡 ——（显示名取 BaseAuthenticator.current.authData[@"username"]，旧链同款 Demo. 规整）
    NSString *displayName = @"未登录";
    BaseAuthenticator *auth = BaseAuthenticator.current;
    if (auth && auth.authData) {
        NSString *username = auth.authData[@"username"];
        if ([username isKindOfClass:[NSString class]] && username.length > 0) {
            if ([username hasPrefix:@"Demo."]) {
                username = [username substringFromIndex:5];
            }
            displayName = username;
        }
    }
    self.accountNameLabel.text = displayName;
    self.accountCard.accessibilityLabel = [NSString stringWithFormat:@"账户：%@", displayName];

    // —— 版本卡 ——（profile/lastVersionId 取 PLProfiles，与旧链同源）
    NSString *selectedProfile = PLProfiles.current.selectedProfileName;
    if (selectedProfile) {
        NSDictionary *profile = PLProfiles.current.profiles[selectedProfile];
        self.profileNameLabel.text = selectedProfile;
        self.versionIdLabel.text = profile[@"lastVersionId"] ?: @"unknown";
    } else {
        self.profileNameLabel.text = @"未选择实例";
        self.versionIdLabel.text = @"";
    }
    self.versionCard.accessibilityLabel =
        [NSString stringWithFormat:@"实例：%@，版本：%@，点按切换",
            self.profileNameLabel.text ?: @"", self.versionIdLabel.text ?: @""];

    // —— 启动按钮三态 ——
    // 禁用判定：本页下载任务存在或启动链进行中（无账号不禁用——FCL 风格可点进登录）
    BOOL buttonEnabled = (self.task == nil) && !self.ame_launchChainActive;
    self.launchButton.enabled = buttonEnabled;
    self.launchButton.backgroundColor = buttonEnabled ? [ZL2Theme launchReadyTint]
                                                      : [ZL2Theme launchDisabledTint];
    self.playIconView.tintColor = buttonEnabled ? [ZL2Theme onPrimary]
                                                : [ZL2Theme onSurfaceVariant];

    BOOL hasActiveTasks = [[DownloadTaskManager sharedManager] hasActiveTasks];
    BOOL hasAccount = (auth != nil);
    NSString *statusText;
    if (hasActiveTasks) {
        statusText = localize(@"i18n_str_434", nil);   // 下载中
    } else if (!hasAccount) {
        statusText = localize(@"i18n_str_435", nil);   // 登录并启动
    } else {
        statusText = localize(@"i18n_str_412", nil);   // 启动游戏
    }
    self.launchStatusLabel.text = statusText;
    self.launchButton.accessibilityLabel = statusText;
    self.launchButton.accessibilityTraits = UIAccessibilityTraitButton;
}

#pragma mark - Notifications

- (void)accountOrHomeDidChange:(NSNotification *)notification {
    [self refreshLaunchState];

    // FCL 风格续启动：用户从启动按钮进入登录（pending=YES），账号就绪后自动继续启动链
    if ([notification.name isEqualToString:@"UpdateAccountInfo"] &&
        self.ame_pendingLaunchAfterLogin &&
        BaseAuthenticator.current != nil) {
        self.ame_pendingLaunchAfterLogin = NO;
        [self launchGame];
    }
}

#pragma mark - Tap Handlers

- (void)accountCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

- (void)versionCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @2}];
}

- (void)chipTapped:(UIControl *)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @(sender.tag)}];
}

#pragma mark - Launch Chain（1:1 旧链语义，LauncherRightPanelViewController L1403-1550）

- (void)launchButtonTapped {
    if (self.task) {
        // 下载中点击启动按钮 → 反查 DownloadTaskManager 打开统一进度页
        // （任务由 MinecraftResourceDownloadTask 内部注册，按 rawTask 反查 taskId）
        NSString *taskId = nil;
        for (DownloadTaskItem *item in [DownloadTaskManager sharedManager].allTasks) {
            if (item.rawTask == self.task) {
                taskId = item.taskId;
                break;
            }
        }
        if (taskId) {
            [PLTaskProgressViewController presentForTaskId:taskId];
        }
        return;
    }

    if ([[DownloadTaskManager sharedManager] hasActiveTasks]) {
        // 旧链语义：无本页发起的任务但存在其他进行中下载 → 提示后仍允许启动
        // （某些下载与游戏本体启动无依赖关系，强制等待反而阻塞体验）
        [self showAlert:localize(@"i18n_str_388", nil) message:localize(@"i18n_str_430", nil)];
    }

    [self launchGame];
}

- (void)launchGame {
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    if (!currentAuth) {
        // FCL 风格：无账号 → 挂 pending 标记切账户管理页，
        // @"UpdateAccountInfo" 回来（accountOrHomeDidChange:）自动继续启动
        self.ame_pendingLaunchAfterLogin = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
        return;
    }
    self.ame_pendingLaunchAfterLogin = NO;

    // 旧契约：启动链发生在主页语境（Task261 判例：点启动 → 确定性秒回主页）
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];

    NSString *selectedProfile = PLProfiles.current.selectedProfileName;
    if (!selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }

    NSString *versionId = PLProfiles.current.profiles[selectedProfile][@"lastVersionId"];
    if (!versionId) {
        [self showAlert:localize(@"i18n_str_43", nil)];
        return;
    }

    // FCL 风格：记录最后游玩时间戳到 profile，供版本管理页显示
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableDictionary *profile = [profiles[selectedProfile] mutableCopy];
    if (profile) {
        profile[@"lastPlayed"] = @([[NSDate date] timeIntervalSince1970]);
        profiles[selectedProfile] = profile;
        [PLProfiles.current save];
    }

    // 设置 UI 为下载状态（反查窗口期防双击；恢复点：回调失败/完成/handleError）
    [self setLaunchInteractionEnabled:NO];

    // 通过通知从远程版本列表反查版本对象（本地版本查不到 → 提示 + 恢复交互）
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[@"versionId"] = versionId;
    __weak ZL2HomeViewController *weakSelf = self;
    userInfo[@"callback"] = ^(NSDictionary *version) {
        if (version) {
            [weakSelf startDownloadWithVersion:version profileName:selectedProfile];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setLaunchInteractionEnabled:YES];
                [weakSelf showAlert:localize(@"i18n_str_432", nil)];
            });
        }
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FindVersionInRemoteList"
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)startDownloadWithVersion:(NSDictionary *)versionObject profileName:(NSString *)profileName {
    self.task = [MinecraftResourceDownloadTask new];

    __weak ZL2HomeViewController *weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // handleError 桩：主线程恢复交互 + KVO 野指针纪律（task=nil 之前先移除观察者）。
        // 注：本页无 UIProgressView，旧链的 progressView.observedProgress = nil 在此无对应物。
        weakSelf.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setLaunchInteractionEnabled:YES];
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ZL2HomeProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
                [weakSelf refreshLaunchState];
            });
        };

        [weakSelf.task downloadVersion:versionObject];

        dispatch_async(dispatch_get_main_queue(), ^{
            // KVO 观察下载进度（OptionInitial：挂上即回调一次，状态 label 立即进百分比态）
            [weakSelf.task.progress addObserver:weakSelf
                                     forKeyPath:@"fractionCompleted"
                                        options:NSKeyValueObservingOptionInitial
                                        context:ZL2HomeProgressObserverContext];
            // 统一进度页由任务内部阶段上报（autoPresentDetail）自动弹出，此处不手动 present
            [weakSelf refreshLaunchState];
        });
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != ZL2HomeProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // 强持有 progress 快照：即便 task 在异步落地前被 handleError 清空，
    // removeObserver 的对象依然存活（wild-pointer 双保险）
    NSProgress *progress = self.task.progress;
    if (!progress) return;
    NSInteger percent = (NSInteger)(progress.fractionCompleted * 100.0 + 0.5);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (percent >= 100) {
            // 下载完成：统一进度页由任务内部接管（autoPresentDetail），本页仅收尾刷新。
            // KVO 野指针纪律：task=nil 之前先移除观察者（旧链完成分支同款）。
            @try {
                [progress removeObserver:self
                              forKeyPath:@"fractionCompleted"
                                 context:ZL2HomeProgressObserverContext];
            } @catch (NSException *e) {}
            self.task = nil;
            [self setLaunchInteractionEnabled:YES];
            // 旧链同款：通知刷新版本列表（新版本已落盘可被版本管理页发现）
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        } else {
            self.launchStatusLabel.text =
                [NSString stringWithFormat:@"%@ %ld%%", localize(@"i18n_str_434", nil), (long)percent];
        }
    });
}

- (void)setLaunchInteractionEnabled:(BOOL)enabled {
    self.ame_launchChainActive = !enabled;
    // 旧链同款：启动/下载期间保持屏幕常亮
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
    // 按钮可用态统一由 refreshLaunchState 依据 task/pending 派生（单一来源）
    [self refreshLaunchState];
}

#pragma mark - Alerts

- (void)showAlert:(NSString *)message {
    [self showAlert:message message:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
