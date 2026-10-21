//
// ZL2HomeViewController.m — ZL2 风格主页实现（7.0-UI-10-d：主页网格化 HomeGrid）
//
// ZL2 对应关系（视觉与行为规格来源 ref/ZalithLauncher2/ZalithLauncher/
// .../ui/screens/content/home/）：
//   HomeGrid.kt                   → 可编辑网格区 + 编辑态（本文件网格段）
//   HomeCards.kt                  → 卡片注册表（本版固定五卡集合 home_* key 模型）
//   HomeGridPersistence.kt        → 布局持久化（本版简化为 NSUserDefaults 卡序
//                                    数组；ZL2 为 MMKV+Gson 存 x/y/w/h 自由
//                                    停靠矩形，系统卡不参与持久化）
//   ActionMenuDrag.kt             → 长按拖拽语义（iOS 用 UICollectionView
//                                    interactive movement 等价移植，iOS9+ 恒可用）
//   version/VersionCardContent.kt → 版本卡内容语义（iOS 侧合并旧启动链）
//   ../content/LauncherScreen.kt  → 主页装配 + 卡片导航目标
//
// 简化注记：ZL2 的自由拖拽停靠/卡片增删（CardGrid x/y/w/h 矩形 + removeCard/
// addCard + 卡片工具栏）本版简化为「固定卡集合 + 长按拖拽排序 + 排序持久化」；
// 版本卡恒为首张且不可拖（对齐 ZL2 持久化中系统卡语义的简化）。
//
// 网格结构（UICollectionViewFlowLayout，圆角 radiusL，间距 10，section inset
// 上下 12 左右 16；iPhone 2 列 / 网格宽 >600 时 3 列）：
//   顶部紧凑头行 44（「主页」fontTitleLarge onSurface + 编辑/完成 36×36 钮；
//   编辑态标题右侧显示「拖动卡片调整布局」）
//   home_version            版本卡（整行，高 132，surfaceContainerHigh，恒首张）
//   home_account            账户卡（整行，高 132，surfaceContainer）
//   home_actions_versions   操作卡（单列，高 96，→ ZL2ShellNavigate index=2）
//   home_actions_download   操作卡（单列，高 96，→ index=1）
//   home_actions_settings   操作卡（单列，高 96，→ index=4）
//   问候区旧版两行迁移：主标题语义由头行「主页」承接；副题
//   「Minecraft: Java Edition · 测试版」作为版本卡状态列问候线保留原文。
//   版本卡 132 高内「44 图标行 + 64 启动钮 + 时间戳」四段竖排放不下，
//   lastPlayed 以状态列第三行承载（视觉语义等价：时间戳位于启动钮右侧列底部）。
//
// 启动链 1:1 复用旧 LauncherRightPanelViewController L1403-1550 语义（与旧右
// 面板 UI 解耦）：self.task 反查统一进度页 → 无账号挂 pending 后切账户页
// （@"UpdateAccountInfo" 回来自动续启动）→ ShowHomePage 旧契约 → profile/
// versionId 校验 → lastPlayed 时间戳 → @"FindVersionInRemoteList" 回调回调
// → MinecraftResourceDownloadTask 下载 + KVO 百分比刷新（handleError 桩遵循
// KVO 野指针纪律：task=nil 之前先移除观察者）。任务完成后统一进度页由任务
// 内部（autoPresentDetail）接管，本页仅收尾刷新。
//
// 导航协议：本页不直接 push 任何页面——切页需求一律经壳的通知契约：
//   @"ShowAccountManager"  → 壳切到账户页（账户卡点击）
//   @"ZL2ShellNavigate"    → 壳切页（userInfo[@"index"] = @(pageIndex)；
//                             版本卡/「切换」钮=2、下载中心卡=1、设置卡=4）
//   @"ShowHomePage"        → 壳切回主页（启动链既有契约，兼容旧监听方）
//
// 红线遵守：iOS 14.0+（无 button.configuration 等 iOS 15+ API；拖拽排序用
// UICollectionView interactive movement iOS9+ 恒可用，不用 iOS15+ reconfiguration；
// SF 符号全为 SF1.0 级并带旧名 fallback）；颜色/字体/圆角一律取 ZL2Theme 动态
// 令牌（无 traitCollection 分支）；全部子视图 translatesAutoresizingMaskIntoConstraints
// = NO；视图身份直接属性持有（sender.tag / gesture.view.tag 仅作导航页序载荷，
// 不做 viewWithTag: 身份查找）；alert 一律 present 到本 VC；编辑态导航点击
// 拦截（防拖拽排序误触；启动链不拦——禁用派生 !task && !chainActive 不变）。
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

// 网格卡片 key（ZL2 HomeCards 卡片注册表的固定五卡集合简化等价）
static NSString * const ZL2HomeCardKeyVersion  = @"home_version";
static NSString * const ZL2HomeCardKeyAccount  = @"home_account";
static NSString * const ZL2HomeCardKeyVersions = @"home_actions_versions";
static NSString * const ZL2HomeCardKeyDownload = @"home_actions_download";
static NSString * const ZL2HomeCardKeySettings = @"home_actions_settings";

// 排序持久化 key（ZL2 HomeGridStore.homeCardLayout 的 iOS 简化等价：卡序数组）
static NSString * const ZL2HomeGridOrderDefaultsKey = @"zl2_home_grid_v1_order";

// 网格布局常量
static const CGFloat ZL2HomeHeaderHeight      = 44;   // 头行高
static const CGFloat ZL2HomeGridSpacing       = 10;   // 卡片间距（行/列同值）
static const CGFloat ZL2HomeGridInsetH        = 16;   // section 左右 inset
static const CGFloat ZL2HomeGridInsetV        = 12;   // section 上下 inset
static const CGFloat ZL2HomeCardVersionHeight = 132;  // 版本/账户卡高
static const CGFloat ZL2HomeCardActionHeight  = 96;   // 操作卡高
static const CGFloat ZL2HomeThreeColumnWidth  = 600;  // 网格宽超过该值切 3 列

// SF Symbols 取图兜底（本页符号除 pencil 为 iOS14 档外全为 SF1.0 级，均带旧名
// fallback；保留兜底是历史判例纪律：符号名异常时降级到旧名而不是空白）
static UIImage *ZL2HomeSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

@interface ZL2HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

// 头行
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *pageTitleLabel;   // 「主页」（ZL2 主页标题语义）
@property (nonatomic, strong) UILabel *editHintLabel;    // 编辑态提示「拖动卡片调整布局」
@property (nonatomic, strong) UIControl *editButton;     // 36×36 编辑/完成图标钮
@property (nonatomic, strong) UIImageView *editIconView;

// 网格
@property (nonatomic, strong) UICollectionView *gridView;
// 网格数据源顺序数组（模型 = 卡片 key；home_version 恒为 index 0 且不可拖）
@property (nonatomic, strong) NSMutableArray<NSString *> *cardKeys;
@property (nonatomic, assign) BOOL gridEditing;
// 交互式移动进行中（begin 成功后才允许 update/end/cancel，防乱序手势事件）
@property (nonatomic, assign) BOOL ame_dragInteractive;
@property (nonatomic, assign) NSInteger lastColumnCount;

// 版本卡（持久视图：cellForItem 时挂进对应 cell，状态刷新直刷属性）
@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) UIView *versionIconBg;
@property (nonatomic, strong) UIImageView *versionIconView;
@property (nonatomic, strong) UILabel *versionNameLabel;
@property (nonatomic, strong) UIControl *switchControl;
@property (nonatomic, strong) UILabel *switchLabel;

// 启动区（版本卡内）
@property (nonatomic, strong) UIControl *launchButton;
@property (nonatomic, strong) UIImageView *playIconView;
@property (nonatomic, strong) UILabel *greetingLabel;
@property (nonatomic, strong) UILabel *launchStatusLabel;
@property (nonatomic, strong) UILabel *lastPlayedLabel;

// 账户卡
@property (nonatomic, strong) UIView *accountCard;
@property (nonatomic, strong) UIImageView *accountIconView;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UILabel *accountTypeLabel;
@property (nonatomic, strong) UILabel *accountManageLabel;
@property (nonatomic, strong) UIImageView *accountChevronView;

// 操作卡 ×3
@property (nonatomic, strong) UIControl *versionsActionCard;
@property (nonatomic, strong) UIControl *downloadActionCard;
@property (nonatomic, strong) UIControl *settingsActionCard;

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
    // 卡片顺序恢复：持久化读取（缺省/脏数据回退默认序，版本卡恒首张）
    self.cardKeys = [self ame_restoreCardOrder];
    [self buildViews];
    // 复用注册（CI 实证：新 UIKit 数据源返回非 dequeue cell 直接崩溃）
    [self.gridView registerClass:[UICollectionViewCell class]
      forCellWithReuseIdentifier:@"ame_home_card_cell"];
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 列数（2/3）随网格宽切换：变化时失效布局重取 sizeForItem
    NSInteger columns = [self ame_columnsForWidth:self.gridView.bounds.size.width];
    if (columns != self.lastColumnCount) {
        self.lastColumnCount = columns;
        [self.gridView.collectionViewLayout invalidateLayout];
    }
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
    [self ame_buildHeader];
    [self ame_buildGrid];
    // 持久卡片视图先于首帧布局建好（cellForItem 挂载时已就绪）
    [self ame_buildVersionCard];
    [self ame_buildAccountCard];
    [self ame_buildActionCards];
}

- (void)ame_buildHeader {
    _headerView = [[UIView alloc] init];
    _headerView.backgroundColor = [UIColor clearColor];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerView];

    _pageTitleLabel = [[UILabel alloc] init];
    _pageTitleLabel.text = @"主页";
    _pageTitleLabel.font = [ZL2Theme fontTitleLarge];
    _pageTitleLabel.textColor = [ZL2Theme onSurface];
    _pageTitleLabel.numberOfLines = 1;
    _pageTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_pageTitleLabel];

    _editHintLabel = [[UILabel alloc] init];
    _editHintLabel.text = @"拖动卡片调整布局";
    _editHintLabel.font = [ZL2Theme fontLabelMedium];
    _editHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _editHintLabel.numberOfLines = 1;
    _editHintLabel.hidden = YES;
    _editHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_editHintLabel];

    _editButton = [[UIControl alloc] init];
    _editButton.backgroundColor = [ZL2Theme surfaceContainer];
    _editButton.layer.cornerRadius = [ZL2Theme radiusS];
    _editButton.translatesAutoresizingMaskIntoConstraints = NO;
    _editButton.isAccessibilityElement = YES;
    _editButton.accessibilityLabel = @"编辑";
    _editButton.accessibilityTraits = UIAccessibilityTraitButton;
    [_editButton addTarget:self
                    action:@selector(editButtonTapped)
          forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_editButton];

    UIImage *pencilImage = ZL2HomeSystemImage(@"pencil", @"square.and.pencil");
    _editIconView = [[UIImageView alloc] initWithImage:[pencilImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _editIconView.tintColor = [ZL2Theme onSurface];
    _editIconView.contentMode = UIViewContentModeScaleAspectFit;
    _editIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_editButton addSubview:_editIconView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:ZL2HomeHeaderHeight],
        [_pageTitleLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:16],
        [_pageTitleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_editHintLabel.leadingAnchor constraintEqualToAnchor:_pageTitleLabel.trailingAnchor constant:12],
        [_editHintLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_editHintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_editButton.leadingAnchor constant:-12],
        [_editButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-16],
        [_editButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_editButton.widthAnchor constraintEqualToConstant:36],
        [_editButton.heightAnchor constraintEqualToConstant:36],
        [_editIconView.centerXAnchor constraintEqualToAnchor:_editButton.centerXAnchor],
        [_editIconView.centerYAnchor constraintEqualToAnchor:_editButton.centerYAnchor],
        [_editIconView.widthAnchor constraintEqualToConstant:20],
        [_editIconView.heightAnchor constraintEqualToConstant:20],
    ]];
}

- (void)ame_buildGrid {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumInteritemSpacing = ZL2HomeGridSpacing;
    layout.minimumLineSpacing = ZL2HomeGridSpacing;
    layout.sectionInset = UIEdgeInsetsMake(ZL2HomeGridInsetV, ZL2HomeGridInsetH,
                                           ZL2HomeGridInsetV, ZL2HomeGridInsetH);

    _gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                   collectionViewLayout:layout];
    _gridView.backgroundColor = [ZL2Theme surface];
    _gridView.dataSource = self;
    _gridView.delegate = self;
    _gridView.alwaysBounceVertical = YES;
    _gridView.allowsSelection = NO;   // 点击走卡片自身手势/控件；选择态不用
    _gridView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_gridView];

    [NSLayoutConstraint activateConstraints:@[
        [_gridView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_gridView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_gridView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_gridView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 长按拖拽排序手势常驻（仅编辑态响应；版本卡在处理器内拦截）
    UILongPressGestureRecognizer *dragGesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(ame_handleDragGesture:)];
    [_gridView addGestureRecognizer:dragGesture];
}

- (void)ame_buildVersionCard {
    _versionCard = [[UIView alloc] init];
    _versionCard.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _versionCard.layer.cornerRadius = [ZL2Theme radiusL];
    _versionCard.translatesAutoresizingMaskIntoConstraints = NO;
    // 卡内含启动钮/切换钮两个可交互子件 → 卡本身不做无障碍元素（子件可达）

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

    _versionNameLabel = [[UILabel alloc] init];
    _versionNameLabel.font = [ZL2Theme fontTitleMedium];
    _versionNameLabel.textColor = [ZL2Theme onSurface];
    _versionNameLabel.numberOfLines = 1;
    _versionNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _switchControl = [[UIControl alloc] init];
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    _switchControl.isAccessibilityElement = YES;
    _switchControl.accessibilityLabel = @"切换版本";
    _switchControl.accessibilityTraits = UIAccessibilityTraitButton;
    [_switchControl addTarget:self
                       action:@selector(switchTapped)
             forControlEvents:UIControlEventTouchUpInside];

    _switchLabel = [[UILabel alloc] init];
    _switchLabel.text = @"切换";
    _switchLabel.font = [ZL2Theme fontLabelLarge];
    _switchLabel.textColor = [ZL2Theme primary];
    _switchLabel.numberOfLines = 1;
    _switchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_switchControl addSubview:_switchLabel];

    _launchButton = [[UIControl alloc] init];
    _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
    // 64×64 圆形（cornerRadius 32 = 直径一半；旧 92pt 圆钮语义缩小进卡）
    _launchButton.layer.cornerRadius = 32;
    // 阴影：black alpha 0.18 / radius 8 / offset(0,3)
    _launchButton.layer.shadowColor = UIColor.blackColor.CGColor;
    _launchButton.layer.shadowOpacity = 0.18f;
    _launchButton.layer.shadowRadius = 8.0f;
    _launchButton.layer.shadowOffset = CGSizeMake(0, 3);

    UIImage *playImage = ZL2HomeSystemImage(@"play.fill", @"play");
    _playIconView = [[UIImageView alloc] initWithImage:[playImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _playIconView.contentMode = UIViewContentModeScaleAspectFit;
    _playIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchButton addSubview:_playIconView];

    [_launchButton addTarget:self
                      action:@selector(launchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];

    // 状态列（启动钮右侧）：问候线 / 启动状态（含「下载中 xx%」KVO 态）/
    // lastPlayed 时间戳（下行以列底行承载，见文件头注记）
    _greetingLabel = [[UILabel alloc] init];
    _greetingLabel.text = @"Minecraft: Java Edition · 测试版";
    _greetingLabel.font = [ZL2Theme fontBodyMedium];
    _greetingLabel.textColor = [ZL2Theme onSurfaceVariant];
    _greetingLabel.numberOfLines = 1;
    _greetingLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _launchStatusLabel = [[UILabel alloc] init];
    _launchStatusLabel.font = [ZL2Theme fontLabelLarge];
    _launchStatusLabel.textColor = [ZL2Theme onSurface];
    _launchStatusLabel.numberOfLines = 1;
    _launchStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchStatusLabel.isAccessibilityElement = YES;

    _lastPlayedLabel = [[UILabel alloc] init];
    _lastPlayedLabel.font = [ZL2Theme fontLabelMedium];
    _lastPlayedLabel.textColor = [ZL2Theme onSurfaceVariant];
    _lastPlayedLabel.numberOfLines = 1;
    _lastPlayedLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [_versionCard addSubview:_versionIconBg];
    [_versionCard addSubview:_versionNameLabel];
    [_versionCard addSubview:_switchControl];
    [_versionCard addSubview:_launchButton];
    [_versionCard addSubview:_greetingLabel];
    [_versionCard addSubview:_launchStatusLabel];
    [_versionCard addSubview:_lastPlayedLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(versionCardTapped)];
    [_versionCard addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        // 上行：图标 44 + 版本名 + 「切换」
        [_versionIconBg.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:16],
        [_versionIconBg.topAnchor constraintEqualToAnchor:_versionCard.topAnchor constant:10],
        [_versionIconBg.widthAnchor constraintEqualToConstant:44],
        [_versionIconBg.heightAnchor constraintEqualToConstant:44],
        [_versionIconView.centerXAnchor constraintEqualToAnchor:_versionIconBg.centerXAnchor],
        [_versionIconView.centerYAnchor constraintEqualToAnchor:_versionIconBg.centerYAnchor],
        [_versionIconView.widthAnchor constraintEqualToConstant:22],
        [_versionIconView.heightAnchor constraintEqualToConstant:22],
        [_versionNameLabel.leadingAnchor constraintEqualToAnchor:_versionIconBg.trailingAnchor constant:12],
        [_versionNameLabel.centerYAnchor constraintEqualToAnchor:_versionIconBg.centerYAnchor],
        [_versionNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_switchControl.leadingAnchor constant:-8],
        [_switchControl.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-16],
        [_switchControl.centerYAnchor constraintEqualToAnchor:_versionIconBg.centerYAnchor],
        [_switchControl.heightAnchor constraintEqualToConstant:32],
        [_switchLabel.leadingAnchor constraintEqualToAnchor:_switchControl.leadingAnchor constant:8],
        [_switchLabel.trailingAnchor constraintEqualToAnchor:_switchControl.trailingAnchor constant:-8],
        [_switchLabel.centerYAnchor constraintEqualToAnchor:_switchControl.centerYAnchor],
        // 中行：启动钮 64（底距 10，132-10-44-4-64 收敛吻合）+ 右侧状态列
        [_launchButton.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:16],
        [_launchButton.topAnchor constraintEqualToAnchor:_versionIconBg.bottomAnchor constant:4],
        [_launchButton.widthAnchor constraintEqualToConstant:64],
        [_launchButton.heightAnchor constraintEqualToConstant:64],
        [_playIconView.centerXAnchor constraintEqualToAnchor:_launchButton.centerXAnchor],
        [_playIconView.centerYAnchor constraintEqualToAnchor:_launchButton.centerYAnchor],
        [_playIconView.widthAnchor constraintEqualToConstant:30],
        [_playIconView.heightAnchor constraintEqualToConstant:30],
        [_launchStatusLabel.leadingAnchor constraintEqualToAnchor:_launchButton.trailingAnchor constant:14],
        [_launchStatusLabel.centerYAnchor constraintEqualToAnchor:_launchButton.centerYAnchor],
        [_launchStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_versionCard.trailingAnchor constant:-16],
        [_greetingLabel.leadingAnchor constraintEqualToAnchor:_launchButton.trailingAnchor constant:14],
        [_greetingLabel.bottomAnchor constraintEqualToAnchor:_launchStatusLabel.topAnchor constant:-2],
        [_greetingLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_versionCard.trailingAnchor constant:-16],
        [_lastPlayedLabel.leadingAnchor constraintEqualToAnchor:_launchButton.trailingAnchor constant:14],
        [_lastPlayedLabel.topAnchor constraintEqualToAnchor:_launchStatusLabel.bottomAnchor constant:2],
        [_lastPlayedLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_versionCard.trailingAnchor constant:-16],
    ]];
}

- (void)ame_buildAccountCard {
    _accountCard = [[UIView alloc] init];
    _accountCard.backgroundColor = [ZL2Theme surfaceContainer];
    _accountCard.layer.cornerRadius = [ZL2Theme radiusL];
    _accountCard.translatesAutoresizingMaskIntoConstraints = NO;
    _accountCard.isAccessibilityElement = YES;
    _accountCard.accessibilityTraits = UIAccessibilityTraitButton;

    // 头像 48 圆（现行头像逻辑照旧：person.crop.circle.fill 模板图标，本身即圆形）
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

    _accountTypeLabel = [[UILabel alloc] init];
    _accountTypeLabel.font = [ZL2Theme fontBodyMedium];
    _accountTypeLabel.textColor = [ZL2Theme onSurfaceVariant];
    _accountTypeLabel.numberOfLines = 1;
    _accountTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _accountManageLabel = [[UILabel alloc] init];
    _accountManageLabel.text = @"管理";
    _accountManageLabel.font = [ZL2Theme fontLabelLarge];
    _accountManageLabel.textColor = [ZL2Theme primary];
    _accountManageLabel.numberOfLines = 1;
    _accountManageLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *chevronImage = ZL2HomeSystemImage(@"chevron.right", @"chevron.forward");
    _accountChevronView = [[UIImageView alloc] initWithImage:[chevronImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _accountChevronView.tintColor = [ZL2Theme onSurfaceVariant];
    _accountChevronView.contentMode = UIViewContentModeScaleAspectFit;
    _accountChevronView.translatesAutoresizingMaskIntoConstraints = NO;

    [_accountCard addSubview:_accountIconView];
    [_accountCard addSubview:_accountNameLabel];
    [_accountCard addSubview:_accountTypeLabel];
    [_accountCard addSubview:_accountManageLabel];
    [_accountCard addSubview:_accountChevronView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(accountCardTapped)];
    [_accountCard addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [_accountIconView.leadingAnchor constraintEqualToAnchor:_accountCard.leadingAnchor constant:16],
        [_accountIconView.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountIconView.widthAnchor constraintEqualToConstant:48],
        [_accountIconView.heightAnchor constraintEqualToConstant:48],
        // 名字/类型中列：两行围绕卡片中线对称展开
        [_accountNameLabel.leadingAnchor constraintEqualToAnchor:_accountIconView.trailingAnchor constant:12],
        [_accountNameLabel.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor constant:-9],
        [_accountNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountManageLabel.leadingAnchor constant:-8],
        [_accountTypeLabel.leadingAnchor constraintEqualToAnchor:_accountIconView.trailingAnchor constant:12],
        [_accountTypeLabel.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor constant:9],
        [_accountTypeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountManageLabel.leadingAnchor constant:-8],
        [_accountManageLabel.trailingAnchor constraintEqualToAnchor:_accountChevronView.leadingAnchor constant:-6],
        [_accountManageLabel.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountChevronView.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-16],
        [_accountChevronView.centerYAnchor constraintEqualToAnchor:_accountCard.centerYAnchor],
        [_accountChevronView.widthAnchor constraintEqualToConstant:15],
        [_accountChevronView.heightAnchor constraintEqualToConstant:15],
    ]];
}

- (void)ame_buildActionCards {
    // 页序载荷与壳契约对齐：0 主页 / 1 下载 / 2 版本管理 / 3 账户 / 4 设置
    // 图标沿用壳 rail 同词表（版本 folder.fill / 下载 arrow.down.circle.fill / 设置 gearshape.fill）
    _versionsActionCard = [self ame_actionCardWithTitle:@"版本管理"
                                                 symbol:@"folder.fill"
                                               fallback:@"folder"
                                                 ofType:ZL2HomeCardKeyVersions
                                                 index:2];
    _downloadActionCard = [self ame_actionCardWithTitle:@"下载中心"
                                                 symbol:@"arrow.down.circle.fill"
                                               fallback:@"arrow.down.circle"
                                                 ofType:ZL2HomeCardKeyDownload
                                                 index:1];
    _settingsActionCard = [self ame_actionCardWithTitle:@"设置"
                                                 symbol:@"gearshape.fill"
                                               fallback:@"gearshape"
                                                 ofType:ZL2HomeCardKeySettings
                                                 index:4];
}

- (UIControl *)ame_actionCardWithTitle:(NSString *)title
                                symbol:(NSString *)symbol
                              fallback:(NSString *)fallback
                                ofType:(NSString *)key
                                 index:(NSInteger)index {
    UIControl *card = [[UIControl alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusL];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.isAccessibilityElement = YES;
    card.accessibilityLabel = title;
    card.accessibilityTraits = UIAccessibilityTraitButton;
    // key 以 accessibilityIdentifier 载荷（数据模型对账用，不做视图查找）
    card.accessibilityIdentifier = key;
    // sender.tag 仅作 ZL2ShellNavigate 页序载荷（不经 viewWithTag: 做身份查找）
    card.tag = index;

    UIImage *iconImage = ZL2HomeSystemImage(symbol, fallback);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:iconView];

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [ZL2Theme fontLabelLarge];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(actionCardTapped:)];
    [card addGestureRecognizer:tap];

    // 图标 28 + 文案的竖排组：96 高卡内上下各 24 收敛居中
    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [iconView.widthAnchor constraintEqualToConstant:28],
        [iconView.heightAnchor constraintEqualToConstant:28],
        [label.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:6],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:8],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-8],
    ]];
    return card;
}

#pragma mark - Grid Datasource / Delegate

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return self.cardKeys.count;
}

// 卡片持久视图挂进 cell：dequeue 空白 cell 后挂载（五卡恒定，无复用收益；
// 重挂载时先清 contentView 旧卡，旧约束随旧 contentView 卸载，逐次重钉四边）
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ame_home_card_cell"
                                                                           forIndexPath:indexPath];
    cell.contentView.backgroundColor = [UIColor clearColor];
    // 复用残留防护：清掉旧卡（卡为 VC 属性单例，addSubview 自动换父）
    for (UIView *stale in cell.contentView.subviews) {
        [stale removeFromSuperview];
    }

    NSString *key = self.cardKeys[indexPath.item];
    UIView *card = [self ame_cardViewForKey:key];
    [cell.contentView addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
    ]];
    [self ame_applyEditingVisualToCard:card animated:NO];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat gridWidth = collectionView.bounds.size.width;
    NSInteger columns = [self ame_columnsForWidth:gridWidth];
    CGFloat available = gridWidth - ZL2HomeGridInsetH * 2;
    NSString *key = self.cardKeys[indexPath.item];
    BOOL fullSpan = [self ame_cardIsFullSpan:key];
    CGFloat itemWidth = fullSpan
        ? available
        : ((available - (columns - 1) * ZL2HomeGridSpacing) / columns);
    CGFloat itemHeight = fullSpan ? ZL2HomeCardVersionHeight : ZL2HomeCardActionHeight;
    return CGSizeMake(itemWidth, itemHeight);
}

// 版本卡恒首张：拖拽落点拦截（交互式移动中不允许越过/停上首张）
- (NSIndexPath *)collectionView:(UICollectionView *)collectionView
targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath *)originalIndexPath
             toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    if (originalIndexPath.item == 0) return originalIndexPath;
    if (proposedIndexPath.item == 0) {
        return [NSIndexPath indexPathForItem:1 inSection:0];
    }
    return proposedIndexPath;
}

- (void)collectionView:(UICollectionView *)collectionView
moveItemAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.item == 0) return;   // 版本卡恒首张不可拖
    NSUInteger dest = (destinationIndexPath.item == 0)
        ? 1
        : (NSUInteger)destinationIndexPath.item;
    NSString *key = self.cardKeys[sourceIndexPath.item];
    [self.cardKeys removeObjectAtIndex:(NSUInteger)sourceIndexPath.item];
    if (dest > self.cardKeys.count) dest = self.cardKeys.count;
    [self.cardKeys insertObject:key atIndex:dest];
}

#pragma mark - Grid Editing（ZL2 HomeGrid 编辑态 + HomeGridPersistence 简化等价）

- (void)editButtonTapped {
    [self ame_setGridEditing:!self.gridEditing];
}

- (void)ame_setGridEditing:(BOOL)editing {
    self.gridEditing = editing;
    // 编辑态切换时兜底：若交互式移动仍挂着，先取消（防布局态悬挂）
    if (self.ame_dragInteractive) {
        self.ame_dragInteractive = NO;
        [self.gridView cancelInteractiveMovement];
    }

    // 完成时把数组顺序写 NSUserDefaults（ZL2 HomeGridStore.save 简化等价）
    if (!editing) {
        [[NSUserDefaults standardUserDefaults] setObject:[self.cardKeys copy]
                                                  forKey:ZL2HomeGridOrderDefaultsKey];
    }

    // 编辑/完成图标切换 + 提示文案显隐
    NSString *symbol = editing ? @"checkmark" : @"pencil";
    NSString *fallback = editing ? @"check" : @"square.and.pencil";
    UIImage *icon = ZL2HomeSystemImage(symbol, fallback);
    self.editIconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.editButton.accessibilityLabel = editing ? @"完成" : @"编辑";
    self.editHintLabel.hidden = !editing;

    // 卡片视觉：编辑态缩放 0.97 + 阴影加强
    [UIView animateWithDuration:0.18 animations:^{
        for (UIView *card in [self ame_allCardViews]) {
            [self ame_applyEditingVisualToCard:card animated:NO];
        }
    }];
}

- (void)ame_applyEditingVisualToCard:(UIView *)card animated:(BOOL)animated {
    CGFloat scale = self.gridEditing ? 0.97 : 1.0;
    CGFloat opacity = self.gridEditing ? 0.22 : 0.10;
    CGFloat radius = self.gridEditing ? 12.0 : 6.0;
    CGSize offset = self.gridEditing ? CGSizeMake(0, 4) : CGSizeMake(0, 2);
    void (^apply)(void) = ^{
        card.transform = CGAffineTransformMakeScale(scale, scale);
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = (float)opacity;
        card.layer.shadowRadius = (float)radius;
        card.layer.shadowOffset = offset;
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:apply];
    } else {
        apply();
    }
}

- (void)ame_handleDragGesture:(UILongPressGestureRecognizer *)gesture {
    if (!self.gridEditing) return;   // 常驻手势仅编辑态响应
    CGPoint location = [gesture locationInView:self.gridView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *target = [self.gridView indexPathForItemAtPoint:location];
            if (!target || target.item == 0) return;   // 空白区/版本卡不可拖
            self.ame_dragInteractive = YES;
            [self.gridView beginInteractiveMovementForItemAtIndexPath:target];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!self.ame_dragInteractive) break;
            // 官方点基 API：updateInteractiveMovementTargetPosition:（CGPoint 入参，
            // 内部自行解析目标卡）；CI 实证 updateInteractiveMovementTargetItemAtIndexPath:
            // 不存在于 SDK（记忆混淆伪 API，首卡越界拦截仍由
            // targetIndexPathForMoveFromItemAtIndexPath 承担）
            [self.gridView updateInteractiveMovementTargetPosition:location];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            if (!self.ame_dragInteractive) break;
            self.ame_dragInteractive = NO;
            [self.gridView endInteractiveMovement];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (!self.ame_dragInteractive) break;
            self.ame_dragInteractive = NO;
            [self.gridView cancelInteractiveMovement];
            break;
        }
        default:
            break;
    }
}

#pragma mark - Grid Helpers

- (UIView *)ame_cardViewForKey:(NSString *)key {
    if ([key isEqualToString:ZL2HomeCardKeyVersion])  return self.versionCard;
    if ([key isEqualToString:ZL2HomeCardKeyAccount])  return self.accountCard;
    if ([key isEqualToString:ZL2HomeCardKeyVersions]) return self.versionsActionCard;
    if ([key isEqualToString:ZL2HomeCardKeyDownload]) return self.downloadActionCard;
    if ([key isEqualToString:ZL2HomeCardKeySettings]) return self.settingsActionCard;
    return nil;
}

- (BOOL)ame_cardIsFullSpan:(NSString *)key {
    // 版本/账户卡整行；操作卡单列
    return [key isEqualToString:ZL2HomeCardKeyVersion] ||
           [key isEqualToString:ZL2HomeCardKeyAccount];
}

- (NSInteger)ame_columnsForWidth:(CGFloat)width {
    return width > ZL2HomeThreeColumnWidth ? 3 : 2;
}

- (NSArray<UIView *> *)ame_allCardViews {
    return @[self.versionCard,
             self.accountCard,
             self.versionsActionCard,
             self.downloadActionCard,
             self.settingsActionCard];
}

// 卡序恢复：版本卡恒首张 + 持久化序优先 + 缺卡补默认序（脏 key 丢弃）
- (NSMutableArray<NSString *> *)ame_restoreCardOrder {
    NSMutableArray<NSString *> *order =
        [NSMutableArray arrayWithObject:ZL2HomeCardKeyVersion];
    NSArray<NSString *> *defaultRemainder = @[
        ZL2HomeCardKeyAccount,
        ZL2HomeCardKeyVersions,
        ZL2HomeCardKeyDownload,
        ZL2HomeCardKeySettings,
    ];
    NSArray<NSString *> *saved =
        [[NSUserDefaults standardUserDefaults] stringArrayForKey:ZL2HomeGridOrderDefaultsKey];
    if (saved.count > 0) {
        for (NSString *key in saved) {
            if (key.length > 0 && ![order containsObject:key] &&
                [defaultRemainder containsObject:key]) {
                [order addObject:key];
            }
        }
    }
    for (NSString *key in defaultRemainder) {
        if (![order containsObject:key]) {
            [order addObject:key];
        }
    }
    return order;
}

#pragma mark - State Refresh (public)

- (void)refreshLaunchState {
    // —— 账户卡 ——（显示名取 BaseAuthenticator.current.authData[@"username"]，旧链同款
    // Demo. 规整；类型文字 = Task220 判别口径本地推导，零新增外部符号）
    NSString *displayName = @"未登录";
    NSString *typeText = @"";
    BaseAuthenticator *auth = BaseAuthenticator.current;
    if (auth && auth.authData) {
        NSString *username = auth.authData[@"username"];
        if ([username isKindOfClass:[NSString class]] && username.length > 0) {
            if ([username hasPrefix:@"Demo."]) {
                username = [username substringFromIndex:5];
                typeText = localize(@"login.option.demo", @"演示");
            } else {
                typeText = [self ame_typeTextForAccountData:auth.authData];
            }
            displayName = username;
        }
    }
    self.accountNameLabel.text = displayName;
    self.accountTypeLabel.text = typeText;
    self.accountCard.accessibilityLabel = [NSString stringWithFormat:@"账户：%@", displayName];

    // —— 版本卡 ——（profile/lastPlayed 取 PLProfiles，与旧链同源；无版本显示「选择版本」）
    NSString *selectedProfile = PLProfiles.current.selectedProfileName;
    if (selectedProfile) {
        NSDictionary *profile = PLProfiles.current.profiles[selectedProfile];
        self.versionNameLabel.text = selectedProfile;
        self.versionNameLabel.textColor = [ZL2Theme onSurface];
        self.lastPlayedLabel.text = [self ame_formatLastPlayed:profile[@"lastPlayed"]];
    } else {
        self.versionNameLabel.text = @"选择版本";
        self.versionNameLabel.textColor = [ZL2Theme onSurfaceVariant];
        self.lastPlayedLabel.text = @"";
    }

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

- (void)versionCardTapped {
    if (self.gridEditing) return;   // 编辑态拦导航（防拖拽排序误触）
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @2}];
}

- (void)switchTapped {
    if (self.gridEditing) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @2}];
}

- (void)accountCardTapped {
    if (self.gridEditing) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

- (void)actionCardTapped:(UITapGestureRecognizer *)gesture {
    if (self.gridEditing) return;
    // gesture.view.tag 仅作 ZL2ShellNavigate 页序载荷（旧 chips tag 语义原样）
    NSInteger index = gesture.view.tag;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @(index)}];
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
            // KVO 观察下载进度（OptionInitial：挂上即回调一次，状态列立即进百分比态）
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

#pragma mark - Profile Metadata Helpers（账户页/版本页同口径本地移植，零新增外部符号）

// 账号类型文字（Task220 判别口径——accountType 显式优先，旧文件回退键位嗅探）
- (NSString *)ame_typeTextForAccountData:(NSDictionary *)accountData {
    NSString *type = accountData[@"accountType"];
    if ([type isKindOfClass:[NSString class]] && type.length > 0) {
        if ([type isEqualToString:@"thirdparty"]) {
            return localize(@"login.option.3rdparty", @"第三方");
        }
        if ([type isEqualToString:@"local"]) {
            return localize(@"login.option.local", @"本地");
        }
        return @"Microsoft";
    }
    // 旧文件回退（与 loadSavedName 同口径：clientToken 先于 xboxGamertag）
    if (accountData[@"clientToken"] != nil) {
        return localize(@"login.option.3rdparty", @"第三方");
    }
    if (accountData[@"xboxGamertag"] == nil) {
        return localize(@"login.option.local", @"本地");
    }
    return @"Microsoft";
}

// lastPlayed 时间戳 → 「最后游玩：xxx」（版本管理页 formatLastPlayed 1:1）
- (NSString *)ame_formatLastPlayed:(id)lastPlayedRaw {
    if (!lastPlayedRaw) return @"";
    NSTimeInterval ts;
    if ([lastPlayedRaw isKindOfClass:[NSNumber class]]) {
        ts = [lastPlayedRaw doubleValue];
    } else if ([lastPlayedRaw isKindOfClass:[NSString class]]) {
        ts = [(NSString *)lastPlayedRaw doubleValue];
    } else {
        return @"";
    }
    if (ts <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale currentLocale];
    fmt.doesRelativeDateFormatting = YES;
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:localize(@"i18n_str_1069", nil), [fmt stringFromDate:date]];
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
