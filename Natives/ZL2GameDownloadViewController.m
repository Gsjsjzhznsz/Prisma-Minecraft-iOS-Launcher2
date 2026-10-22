//
// ZL2GameDownloadViewController.m — ZL2 选版屏 1:1（7.0-UI-14 全页面全逻辑移植
//                                     第三轮：真机截图逐像素对标版）
//
// 移植对象：ZalithLauncher2 SelectGameVersionScreen.kt + VersionHeader +
// VersionItemLayout（GNU GPL 参考副本，只读；真机截图 12 张交叉验证）。
//
// 布局（ZL2 VersionHeader 实证结构，旧"搜索框顶置+单选 chips"废弃）：
//   ① 单行头：[4 枚多选 toggle chips（横向滚动，最多 3/5 宽）] + [搜索框
//      weight 1] + [刷新钮]；chips = 正式版（默认选中）/ 快照版 / 愚人节版 /
//      远古版（old_beta + old_alpha 合并档）——ZL2 VersionFilter 语义：
//      release=true, snapshot=false, aprilFools=false, old=false 起步，
//      点按 toggle 翻转，可多选叠加。
//   ② 分隔线（onSurface 0.3 alpha，ZL2 HorizontalDivider 同位）。
//   ③ 版本卡列表（LazyColumn h12 v6 节奏；卡内 padding 12）：
//      [类型图标 32] + [名称 labelLarge + 类型小 chip] / [摘要 labelMedium
//      0.7（仅愚人节版内置表）] / [日期 labelMedium 0.7："2026 年 09 月 15 日
//      19:23:02"] + [Wiki 链接钮 32（release/snapshot/愚人节三型有）]。
//      类型→图标（ZL2 drawable 直移，Natives/ZL2Assets/）：
//        Release=img_minecraft（草方块）/ Snapshot=img_command_block（命令
//        方块）/ AprilFools=img_diamond_block（钻石块）/ OldBeta=
//        img_old_cobblestone（圆石）/ OldAlpha=img_old_grass_block（老草方块）。
//      类型→chip 文案（ZL2 download_game_type_* zh-CN）：正式版 / 快照版 /
//        愚人节版 / Beta 版 / Alpha 版。
//      愚人节摘要：ZL2 _MinecraftVersionCatalog allAprilFools 13 项 +
//        version_summary_fools_* zh-CN 文案 1:1 移植（见 ame_aprilFoolsSummary）。
//      Wiki URL（ZL2 zh-CN strings 1:1）：release →
//        https://zh.minecraft.wiki/w/Java版{id}?variant=zh-cn；snapshot/愚人节
//        → https://zh.minecraft.wiki/w/{id}?variant=zh-cn；远古两型无 Wiki。
//   ④ 点版本卡 → push ZL2GameAddonsViewController（ZL2 DownloadGameWithAddon
//      屏语义；旧底部弹层+确认框直装废弃——加载器组合在 Addons 屏完成）。
//   ⑤ 数据流保留：ZL2VersionIndex remoteVersions（去 latest-* 种子）+ 首屏 60
//      滚动续载 40 + 失败重试；已安装角标删除（ZL2 真机截图无此元素）。
//
// 红线：颜色/字体/圆角一律 ZL2Theme；iOS 14.0 API 上限；SF 符号 SF1.0 级；
// 新建视图 translatesAutoresizingMaskIntoConstraints = NO；零 viewWithTag
// 存状态（tag 仅作事件载荷）。
//

#import "ZL2GameDownloadViewController.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2GameAddonsViewController.h"
#import "ZL2VersionIndex.h"

#import <objc/runtime.h>

#pragma mark - 常量

static const NSUInteger ZL2GamePageSizeFirst = 60;
static const NSUInteger ZL2GamePageSizeMore = 40;

#pragma mark - 版本卡 cell（ZL2 VersionItemLayout 三行结构）

@interface ZL2GameVersionCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *typeIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIControl *wikiButton;
@property (nonatomic, strong) NSLayoutConstraint *summaryHeight;
@property (nonatomic, strong) NSLayoutConstraint *wikiWidth;
- (void)ame_configureWithId:(NSString *)versionId
                 chipText:(NSString *)chipText
                    chipBg:(UIColor *)chipBg
                    chipFg:(UIColor *)chipFg
                iconBundle:(NSString *)iconBundleName
                   summary:(nullable NSString *)summary
                     dateText:(NSString *)dateText
                     wikiUrl:(nullable NSString *)wikiUrl
                  wikiTarget:(nullable id)wikiTarget
                     wikiAction:(nullable SEL)wikiAction;
@end

@implementation ZL2GameVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = [UIColor clearColor];

        // 卡面（shapes.large = radiusL 16，ZL2 MaterialTheme.shapes.large）
        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = [ZL2Theme surfaceContainer];
        _cardView.layer.cornerRadius = [ZL2Theme radiusL];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardView];

        _typeIconView = [[UIImageView alloc] init];
        _typeIconView.contentMode = UIViewContentModeScaleAspectFit;
        _typeIconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_typeIconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [ZL2Theme fontLabelLarge];
        _titleLabel.textColor = [ZL2Theme onSurface];
        _titleLabel.numberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_titleLabel];

        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.font = [ZL2Theme fontLabelMedium];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.numberOfLines = 1;
        _badgeLabel.layer.cornerRadius = [ZL2Theme radiusXS];
        _badgeLabel.clipsToBounds = YES;
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_badgeLabel];

        _summaryLabel = [[UILabel alloc] init];
        _summaryLabel.font = [ZL2Theme fontLabelMedium];
        _summaryLabel.textColor = [ZL2Theme onSurfaceVariant];
        _summaryLabel.numberOfLines = 1;
        _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_summaryLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [ZL2Theme fontLabelMedium];
        _dateLabel.textColor = [ZL2Theme onSurfaceVariant];
        _dateLabel.numberOfLines = 1;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_dateLabel];

        _wikiButton = [[UIControl alloc] init];
        _wikiButton.translatesAutoresizingMaskIntoConstraints = NO;
        _wikiButton.isAccessibilityElement = YES;
        _wikiButton.accessibilityLabel = @"查看 Wiki";
        UIImageView *wikiIcon = [[UIImageView alloc] initWithImage:
            [[UIImage systemImageNamed:@"link"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        wikiIcon.tintColor = [ZL2Theme onSurfaceVariant];
        wikiIcon.contentMode = UIViewContentModeScaleAspectFit;
        wikiIcon.translatesAutoresizingMaskIntoConstraints = NO;
        wikiIcon.userInteractionEnabled = NO;
        [_wikiButton addSubview:wikiIcon];
        [_cardView addSubview:_wikiButton];

        _summaryHeight = [_summaryLabel.heightAnchor constraintEqualToConstant:0];
        _summaryHeight.active = YES;
        _wikiWidth = [_wikiButton.widthAnchor constraintEqualToConstant:32];
        _wikiWidth.active = YES;

        UILayoutGuide *cardLG = _cardView.layoutMarginsGuide;
        _cardView.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 12);
        [NSLayoutConstraint activateConstraints:@[
            // 卡片：左右 12（LazyColumn h12）、上下 6（items v6 节奏）
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

            // 图标 32（ZL2 Image size(32.dp)），垂直居中
            [_typeIconView.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
            [_typeIconView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_typeIconView.widthAnchor constraintEqualToConstant:32],
            [_typeIconView.heightAnchor constraintEqualToConstant:32],

            // 文本列
            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_typeIconView.trailingAnchor constant:12],
            [_badgeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:8],
            [_badgeLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_badgeLabel.heightAnchor constraintEqualToConstant:20],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:36],

            [_summaryLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_wikiButton.leadingAnchor constant:-4],

            [_dateLabel.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:2],
            [_dateLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_dateLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12],

            // Wiki 钮 32（ZL2 IconButton size(32.dp)）右侧垂直居中
            [_wikiButton.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],
            [_wikiButton.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_wikiButton.heightAnchor constraintEqualToConstant:32],
            [wikiIcon.centerXAnchor constraintEqualToAnchor:_wikiButton.centerXAnchor],
            [wikiIcon.centerYAnchor constraintEqualToAnchor:_wikiButton.centerYAnchor],
            [wikiIcon.widthAnchor constraintEqualToConstant:18],
            [wikiIcon.heightAnchor constraintEqualToConstant:18],
        ]];
    }
    return self;
}

- (void)ame_configureWithId:(NSString *)versionId
                   chipText:(NSString *)chipText
                     chipBg:(UIColor *)chipBg
                     chipFg:(UIColor *)chipFg
                 iconBundle:(NSString *)iconBundleName
                    summary:(NSString *)summary
                   dateText:(NSString *)dateText
                    wikiUrl:(NSString *)wikiUrl
                 wikiTarget:(id)wikiTarget
                 wikiAction:(SEL)wikiAction {
    _titleLabel.text = versionId;

    _badgeLabel.text = chipText;
    _badgeLabel.backgroundColor = chipBg;
    _badgeLabel.textColor = chipFg;

    // 类型图标（bundle 资产：ZL2 drawable 直移）
    if (iconBundleName.length > 0) {
        NSString *assetsPath = [[NSBundle mainBundle].resourcePath
            stringByAppendingPathComponent:@"ZL2Assets"];
        NSString *iconPath = [assetsPath stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"%@.png", iconBundleName]];
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        _typeIconView.image = icon;
        _typeIconView.hidden = (icon == nil);
    } else {
        _typeIconView.image = nil;
        _typeIconView.hidden = YES;
    }

    BOOL hasSummary = summary.length > 0;
    _summaryLabel.text = hasSummary ? summary : nil;
    _summaryHeight.constant = hasSummary ? 16.0 : 0.0;

    _dateLabel.text = dateText;

    BOOL hasWiki = wikiUrl.length > 0;
    _wikiButton.hidden = !hasWiki;
    _wikiWidth.constant = hasWiki ? 32.0 : 0.0;
    if (hasWiki && wikiTarget && wikiAction) {
        [_wikiButton addTarget:wikiTarget
                         action:wikiAction
               forControlEvents:UIControlEventTouchUpInside];
    }
}

@end

#pragma mark - 页面本体

@interface ZL2GameDownloadViewController () <UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate>

// ZL2 VersionHeader：chips 行 + 搜索 + 刷新（单行）
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) NSMutableArray<ZL2M3FilterChip *> *filterChips;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIControl *refreshButton;

// 分隔线（onSurface 0.3）
@property (nonatomic, strong) UIView *headerDivider;

// 列表与状态
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIControl *retryButton;

// 数据态
@property (nonatomic, strong) NSArray<NSDictionary *> *allVersions;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *filtered;
@property (nonatomic, assign) NSUInteger displayedCount;

// ZL2 VersionFilter 多选语义（release 默认 ON）
@property (nonatomic, assign) BOOL filterRelease;
@property (nonatomic, assign) BOOL filterSnapshot;
@property (nonatomic, assign) BOOL filterAprilFools;
@property (nonatomic, assign) BOOL filterOld;
@property (nonatomic, copy) NSString *searchQuery;

// 数据加载代际（防抖刷新竞态）
@property (nonatomic, assign) NSInteger loadGeneration;

@end

@implementation ZL2GameDownloadViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _filterChips = [NSMutableArray array];
        _allVersions = @[];
        _filtered = [NSMutableArray array];
        _displayedCount = 0;
        // ZL2 VersionFilter 默认：release=true / snapshot=false /
        // aprilFools=false / old=false
        _filterRelease = YES;
        _filterSnapshot = NO;
        _filterAprilFools = NO;
        _filterOld = NO;
        _searchQuery = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    [self ame_buildViews];
    [self ame_applyChipAppearance];
    [self ame_refreshFromService];
}

#pragma mark - 布局（ZL2 VersionHeader 单行 + divider + 列表）

- (void)ame_buildViews {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ① chips 行（横向滚动，ZL2 max 3/5 宽约束）
    _chipsScroll = [[UIScrollView alloc] init];
    _chipsScroll.showsHorizontalScrollIndicator = NO;
    _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_chipsScroll];

    _chipsStack = [[UIStackView alloc] init];
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.spacing = 12;   // ZL2 spacedBy(12.dp)
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_chipsScroll addSubview:_chipsStack];

    NSArray<NSString *> *titles = @[@"正式版", @"快照版", @"愚人节版", @"远古版"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:titles[i]];
        chip.tag = (NSInteger)i;
        chip.accessibilityLabel = titles[i];
        [chip addTarget:self
                 action:@selector(ame_chipTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [_chipsStack addArrangedSubview:chip];
        [_filterChips addObject:chip];
    }

    // ② 搜索框（weight 1；ZL2 SimpleTextInputField 同款：surfaceContainer 底）
    _searchField = [[UITextField alloc] init];
    _searchField.placeholder = @"搜索";
    _searchField.font = [UIFont systemFontOfSize:12.0];
    _searchField.textColor = [ZL2Theme onSurface];
    _searchField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"搜索"
                                        attributes:@{NSForegroundColorAttributeName: [ZL2Theme onSurfaceVariant]}];
    _searchField.backgroundColor = [ZL2Theme surfaceContainer];
    _searchField.layer.cornerRadius = [ZL2Theme radiusS];
    _searchField.delegate = self;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _searchField.leftView = leftPad;
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.isAccessibilityElement = YES;
    _searchField.accessibilityLabel = @"搜索版本";
    [_searchField addTarget:self
                     action:@selector(ame_searchChanged:)
           forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_searchField];

    // ③ 刷新钮（ZL2 IconButton ic_refresh）
    _refreshButton = [[UIControl alloc] init];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    _refreshButton.isAccessibilityElement = YES;
    _refreshButton.accessibilityLabel = @"刷新";
    [_refreshButton addTarget:self
                       action:@selector(ame_refreshTapped)
             forControlEvents:UIControlEventTouchUpInside];
    UIImageView *refreshIcon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"arrow.clockwise"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    refreshIcon.tintColor = [ZL2Theme onSurface];
    refreshIcon.contentMode = UIViewContentModeScaleAspectFit;
    refreshIcon.translatesAutoresizingMaskIntoConstraints = NO;
    refreshIcon.userInteractionEnabled = NO;
    [_refreshButton addSubview:refreshIcon];
    [self.view addSubview:_refreshButton];

    // ④ 分隔线（onSurface 0.3，ZL2 HorizontalDivider 同位）
    _headerDivider = [[UIView alloc] init];
    _headerDivider.backgroundColor = [ZL2Theme onSurfaceVariant];
    _headerDivider.alpha = 0.3;
    _headerDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerDivider];

    // ⑤ 版本列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 84.0;   // 三行结构（12 头 + 名称 16 + 2 + 摘要/日期 + 12 尾）
    _tableView.estimatedRowHeight = 84.0;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 12, 0);
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[ZL2GameVersionCell class]
       forCellReuseIdentifier:@"ZL2GameVersionCell"];
    [self.view addSubview:_tableView];

    // 状态件
    _loadingView = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingView.color = [ZL2Theme onSurfaceVariant];
    _loadingView.hidesWhenStopped = YES;
    _loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingView];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.font = [ZL2Theme fontBodyLarge];
    _emptyLabel.textColor = [ZL2Theme onSurfaceVariant];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyLabel];

    _retryButton = [[UIControl alloc] init];
    _retryButton.backgroundColor = [ZL2Theme surfaceContainer];
    _retryButton.layer.cornerRadius = [ZL2Theme radiusS];
    _retryButton.hidden = YES;
    _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    _retryButton.isAccessibilityElement = YES;
    _retryButton.accessibilityLabel = @"重试";
    [_retryButton addTarget:self
                     action:@selector(ame_refreshTapped)
           forControlEvents:UIControlEventTouchUpInside];
    UILabel *retryLabel = [[UILabel alloc] init];
    retryLabel.text = @"重试";
    retryLabel.font = [ZL2Theme fontLabelLarge];
    retryLabel.textColor = [ZL2Theme primary];
    retryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    retryLabel.userInteractionEnabled = NO;
    [_retryButton addSubview:retryLabel];
    [self.view addSubview:_retryButton];

    UILayoutGuide *chipsLG = _chipsScroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_refreshButton.widthAnchor constraintEqualToConstant:40],
        [_refreshButton.heightAnchor constraintEqualToConstant:40],
        [refreshIcon.centerXAnchor constraintEqualToAnchor:_refreshButton.centerXAnchor],
        [refreshIcon.centerYAnchor constraintEqualToAnchor:_refreshButton.centerYAnchor],
        [refreshIcon.widthAnchor constraintEqualToConstant:20],
        [refreshIcon.heightAnchor constraintEqualToConstant:20],
        [retryLabel.centerXAnchor constraintEqualToAnchor:_retryButton.centerXAnchor],
        [retryLabel.centerYAnchor constraintEqualToAnchor:_retryButton.centerYAnchor],

        // 单行头：chips(≤3/5 宽) + 搜索(weight 1) + 刷新
        [_chipsScroll.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [_chipsScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_chipsScroll.trailingAnchor constraintEqualToAnchor:_searchField.leadingAnchor constant:-12],
        [_chipsScroll.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.6],
        [_chipsScroll.heightAnchor constraintEqualToConstant:40],
        [_chipsStack.leadingAnchor constraintEqualToAnchor:chipsLG.leadingAnchor constant:12],
        [chipsLG.trailingAnchor constraintEqualToAnchor:_chipsStack.trailingAnchor constant:4],
        [_chipsStack.topAnchor constraintEqualToAnchor:chipsLG.topAnchor constant:4],
        [chipsLG.bottomAnchor constraintEqualToAnchor:_chipsStack.bottomAnchor constant:4],

        [_searchField.centerYAnchor constraintEqualToAnchor:_chipsScroll.centerYAnchor],
        [_searchField.heightAnchor constraintEqualToConstant:36],
        [_searchField.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor constant:-8],

        [_refreshButton.centerYAnchor constraintEqualToAnchor:_chipsScroll.centerYAnchor],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_headerDivider.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor constant:2],
        [_headerDivider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_headerDivider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_headerDivider.heightAnchor constraintEqualToConstant:0.5],

        [_tableView.topAnchor constraintEqualToAnchor:_headerDivider.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24],
        [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24],

        [_retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_retryButton.topAnchor constraintEqualToAnchor:_emptyLabel.bottomAnchor constant:16],
        [_retryButton.widthAnchor constraintEqualToConstant:88],
        [_retryButton.heightAnchor constraintEqualToConstant:40],
    ]];
}

#pragma mark - chips 多选 toggle（ZL2 VersionFilter 语义）

- (void)ame_chipTapped:(UIControl *)sender {
    switch (sender.tag) {
        case 0: self.filterRelease = !self.filterRelease; break;
        case 1: self.filterSnapshot = !self.filterSnapshot; break;
        case 2: self.filterAprilFools = !self.filterAprilFools; break;
        case 3: self.filterOld = !self.filterOld; break;
        default: break;
    }
    [self ame_applyChipAppearance];
    [self ame_applyFilters];
}

- (void)ame_applyChipAppearance {
    NSArray<NSNumber *> *states = @[@(self.filterRelease),
                                    @(self.filterSnapshot),
                                    @(self.filterAprilFools),
                                    @(self.filterOld)];
    for (NSUInteger i = 0; i < self.filterChips.count && i < states.count; i++) {
        self.filterChips[i].selected = states[i].boolValue;
    }
}

#pragma mark - 搜索

- (void)ame_searchChanged:(UITextField *)field {
    // 0.25s 防抖（连打只筛一次）
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(ame_applyFilters)
                                               object:nil];
    [self performSelector:@selector(ame_applyFilters)
               withObject:nil
               afterDelay:0.25];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self ame_applyFilters];
    return YES;
}

- (void)ame_refreshTapped {
    [self ame_refreshFromService];
}

#pragma mark - 数据流（ZL2VersionIndex + 去种子 + 分页）

- (void)ame_refreshFromService {
    self.loadGeneration += 1;
    [self ame_setStateLoading:YES];
    __weak typeof(self) weakSelf = self;
    NSInteger gen = self.loadGeneration;
    [[ZL2VersionIndex sharedIndex] remoteVersionsWithCompletion:^(
            NSArray<NSDictionary *> *versions, BOOL loaded) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        if (gen != s.loadGeneration) return;   // 过期响应丢弃（刷新代际防护）

        [s ame_setStateLoading:NO];

        // 去种子（latest-* 无 url 不可下载），保持清单原有新旧序
        NSMutableArray<NSDictionary *> *real = [NSMutableArray array];
        for (NSDictionary *entry in versions) {
            NSString *url = entry[@"url"];
            NSString *vid = entry[@"id"];
            if (url.length > 0 && vid.length > 0) [real addObject:entry];
        }

        if (real.count == 0) {
            s.emptyLabel.text = loaded
                ? @"版本清单加载失败，请检查网络后重试"
                : @"版本清单加载超时，请重试";
            s.emptyLabel.hidden = NO;
            s.retryButton.hidden = NO;
            return;
        }

        s.allVersions = [real copy];
        s.retryButton.hidden = YES;
        [s ame_applyFilters];
    }];
}

- (void)ame_setStateLoading:(BOOL)loading {
    if (loading) {
        [self.loadingView startAnimating];
        self.emptyLabel.hidden = YES;
        self.retryButton.hidden = YES;
    } else {
        [self.loadingView stopAnimating];
    }
}

- (void)ame_applyFilters {
    self.searchQuery = (self.searchField.text ?: @"");
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(ame_applyFilters)
                                               object:nil];

    NSMutableArray *out_ = [NSMutableArray array];
    for (NSDictionary *entry in self.allVersions) {
        NSString *vid = entry[@"id"] ?: @"";
        NSString *type = entry[@"type"] ?: @"";
        BOOL isAprilFools = ([self ame_aprilFoolsSummaryForId:vid] != nil);
        BOOL take = NO;
        if ([type isEqualToString:@"release"]) {
            take = self.filterRelease && !isAprilFools;
        } else if ([type isEqualToString:@"snapshot"]) {
            // 愚人节快照（26w14a 等）归愚人节档（ZL2 isType aprilFools 同口径：
            // allAprilFools 命中优先归档）
            take = isAprilFools ? self.filterAprilFools : self.filterSnapshot;
        } else if ([type isEqualToString:@"old_beta"] ||
                   [type isEqualToString:@"old_alpha"]) {
            take = self.filterOld;
        }
        if (!take) continue;
        if (self.searchQuery.length > 0 &&
            [vid rangeOfString:self.searchQuery
                       options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        [out_ addObject:entry];
    }

    self.filtered = out_;
    self.displayedCount = MIN((NSUInteger)ZL2GamePageSizeFirst, out_.count);
    [self.tableView reloadData];
    [self ame_refreshEmptyState];
}

- (void)ame_refreshEmptyState {
    BOOL empty = (self.filtered.count == 0);
    self.emptyLabel.hidden = !empty;
    self.retryButton.hidden = YES;
    if (empty) {
        self.emptyLabel.text = @"没有符合筛选条件的版本";
    }
}

#pragma mark - 愚人节表（ZL2 _MinecraftVersionCatalog 1:1 移植）

/// ZL2 allAprilFools 13 项；返回中文摘要（version_summary_fools_* zh-CN）或 nil
- (nullable NSString *)ame_aprilFoolsSummaryForId:(NSString *)versionId {
    static NSArray<NSArray<NSString *> *> *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // @[版本 id, 摘要]（ZL2 _MinecraftVersionCatalog allAprilFools 顺序）
        table = @[
            @[@"26w14a", @"别整理背包了，你的物品和方块想跟你一起浪！"],
            @[@"25w14craftmine", @"现在你可以合成任何东西，甚至合成整个世界！"],
            @[@"24w14potato", @"多年来，毒马铃薯一直被玩家忽视和低估，于是我们史诗级加强了它！"],
            @[@"23w13a_or_b", @"研究表明：玩家最喜欢作出选择，所以我们让你为一切投票！"],
            @[@"22w13oneblockatatime", @"我们精简了游戏到最纯粹的形态：一次只能拿一个方块。"],
            @[@"20w14infinite", @"我们加入了 20 亿个（准确地说是 2,147,483,647 个）新维度！"],
            @[@"20w14∞", @"我们加入了 20 亿个（准确地说是 2,147,483,647 个）新维度！"],
            @[@"3D Shareware v1.34", @"我们从地下室深处挖出了这款“1994 年 DOS 版”Minecraft！"],
            @[@"1.RV-Pre1", @"未来已来！我们为 Minecraft 加入了现代科技！"],
            @[@"15w14a", @"爱与拥抱更新，让世界充满和平与彩虹。"],
            @[@"2.0_blue", @"我们不会更新它们！如果您发现漏洞，那您就倒霉了！XD"],
            @[@"2.0_red", @"我们不会更新它们！如果您发现漏洞，那您就倒霉了！XD"],
            @[@"2.0_purple", @"我们不会更新它们！如果您发现漏洞，那您就倒霉了！XD"],
        ];
    });
    for (NSArray *entry in table) {
        if ([entry[0] caseInsensitiveCompare:versionId] == NSOrderedSame) return entry[1];
    }
    return nil;
}

#pragma mark - 类型→视觉映射（ZL2 getVersionComponents 1:1）

/// 返回 @[chipText, iconBundleName, wikiKind]
/// 类型 chip 统一 ZL2 LittleTextLabel 语义（tertiary 底 + onTertiary 字）
/// wikiKind: @"release" / @"snapshot" / @"none"
- (NSArray *)ame_visualsForEntry:(NSDictionary *)entry {
    NSString *vid = entry[@"id"] ?: @"";
    NSString *type = entry[@"type"] ?: @"";
    BOOL isAprilFools = ([self ame_aprilFoolsSummaryForId:vid] != nil);

    if (isAprilFools) {
        return @[@"愚人节版", @"img_diamond_block", @"snapshot"];
    }
    if ([type isEqualToString:@"release"]) {
        return @[@"正式版", @"img_minecraft", @"release"];
    }
    if ([type isEqualToString:@"snapshot"]) {
        return @[@"快照版", @"img_command_block", @"snapshot"];
    }
    if ([type isEqualToString:@"old_beta"]) {
        return @[@"Beta 版", @"img_old_cobblestone", @"none"];
    }
    if ([type isEqualToString:@"old_alpha"]) {
        return @[@"Alpha 版", @"img_old_grass_block", @"none"];
    }
    return @[@"版本", @"", @"none"];
}

/// ZL2 日期格式（date_format zh-CN："yyyy 年 MM 月 dd 日 HH:mm:ss"）
- (NSString *)ame_dateTextForEntry:(NSDictionary *)entry {
    NSString *iso = entry[@"releaseTime"] ?: @"";
    if (iso.length == 0) return @"";
    static NSDateFormatter *parser = nil;
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = [[NSDateFormatter alloc] init];
        parser.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        parser.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy 年 MM 月 dd 日 HH:mm:ss";
    });
    NSDate *date = [parser dateFromString:iso];
    if (!date) return iso;
    return [formatter stringFromDate:date];
}

- (NSString *)ame_wikiUrlForEntry:(NSDictionary *)entry wikiKind:(NSString *)kind {
    if ([kind isEqualToString:@"none"]) return nil;
    NSString *vid = entry[@"id"] ?: @"";
    if (vid.length == 0) return nil;
    // ZL2 urlSuffix：2.0_blue/red/purple → "2.0"（wiki 页共用）
    NSString *suffix = vid;
    if ([suffix hasPrefix:@"2.0_"]) suffix = @"2.0";
    NSString *encoded = [suffix stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLPathAllowedCharacterSet]];
    if ([kind isEqualToString:@"release"]) {
        return [NSString stringWithFormat:@"https://zh.minecraft.wiki/w/Java%%E7%%89%%88%@?variant=zh-cn", encoded];
    }
    return [NSString stringWithFormat:@"https://zh.minecraft.wiki/w/%@?variant=zh-cn", encoded];
}

static void *kZL2GameWikiURLKey = &kZL2GameWikiURLKey;

- (void)ame_wikiTapped:(UIControl *)sender {
    NSString *url = objc_getAssociatedObject(sender, kZL2GameWikiURLKey);
    if (url.length == 0) return;
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) return;
    // 系统浏览器打开（ZL2 EventViewModel.OpenLink 同语义）
    [[UIApplication sharedApplication] openURL:nsurl options:@{} completionHandler:nil];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.displayedCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZL2GameVersionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2GameVersionCell"
                                                              forIndexPath:indexPath];
    NSDictionary *entry = self.filtered[(NSUInteger)indexPath.row];
    NSArray *visuals = [self ame_visualsForEntry:entry];

    // 类型 chip：ZL2 LittleTextLabel（tertiary 底 + onTertiary 字，全部五型统一）
    NSString *wikiUrl = [self ame_wikiUrlForEntry:entry wikiKind:visuals[2]];

    [cell ame_configureWithId:(entry[@"id"] ?: @"")
                     chipText:visuals[0]
                       chipBg:[ZL2Theme tertiary]
                       chipFg:[ZL2Theme onTertiary]
                   iconBundle:visuals[1]
                      summary:[self ame_aprilFoolsSummaryForId:(entry[@"id"] ?: @"")]
                     dateText:[self ame_dateTextForEntry:entry]
                      wikiUrl:wikiUrl
                   wikiTarget:wikiUrl ? self : nil
                   wikiAction:wikiUrl ? @selector(ame_wikiTapped:) : nil];

    // Wiki URL 挂钮（关联存储，点击读取打开）
    if (wikiUrl) {
        objc_setAssociatedObject(cell.wikiButton,
                                 kZL2GameWikiURLKey,
                                 wikiUrl,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = self.filtered[(NSUInteger)indexPath.row];
    NSString *vid = entry[@"id"] ?: @"";
    if (vid.length == 0) return;
    // ZL2 语义：选版 → Addons 加载器屏（旧底部弹层安装流退役）
    ZL2GameAddonsViewController *addons =
        [[ZL2GameAddonsViewController alloc] initWithGameVersion:vid];
    [self.navigationController pushViewController:addons animated:YES];
}

// 滚动续载（首屏 60 + 续载 40）
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (![scrollView isEqual:self.tableView]) return;
    if (self.displayedCount >= self.filtered.count) return;
    CGPoint offset = scrollView.contentOffset;
    CGFloat threshold = scrollView.contentSize.height - scrollView.bounds.size.height - 400;
    if (threshold < 0 || offset.y >= threshold) {
        NSUInteger next = MIN(self.displayedCount + ZL2GamePageSizeMore,
                              self.filtered.count);
        if (next != self.displayedCount) {
            NSArray *indexPaths = [self ameIndexPathsFrom:self.displayedCount to:next];
            self.displayedCount = next;
            [self.tableView insertRowsAtIndexPaths:indexPaths
                                  withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (NSArray *)ameIndexPathsFrom:(NSUInteger)from to:(NSUInteger)to {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSUInteger i = from; i < to; i++) {
        [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    return paths;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
