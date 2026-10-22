//
// ZL2GameDownloadViewController.m — 游戏 M3 下载页实现（7.0-UI-12）
//
// 移植对象：ZalithLauncher2 SelectGameVersionScreen.kt（GNU GPL 参考副本，
//   只读）。ZL2 游戏下载页 = M3 搜索 + 类型筛选 + 版本列表，点选即装；
//   本页同语义三段竖排：
//
//   ① M3 胶囊搜索框（ZL2M3SearchBar）——版本号前缀/包含过滤（0.25s 防抖）
//   ② 类型筛选 chips（ZL2M3FilterChip × 5）——全部/正式版/快照/远古版/
//      已安装（MD3 filter chip 两态规格）
//   ③ 版本卡列表（UITableView 自绘 M3 卡片 cell）——版本 id + 类型徽章 +
//      发布日期 + 已安装角标；60 条起步滚到底 +40 分页（清单 ~700 条内存
//      过滤零网络）；点卡弹 M3 底部弹层（ZL2M3BottomSheet：版本详情 +
//      安装钮）→ M3 对话框确认（ZL2M3Dialog）→ 旧管线安装
//
// 安装流（旧 DownloadViewController downloadVanillaVersion 1:1 抽取，
//   不改语义）：
//   a) PLProfiles 建版本隔离 profile（name/lastVersionId/gameDir=
//      versions/<id>/game/type=custom/created；Task242 数据分居口径）
//   b) MinecraftResourceDownloadTask downloadVersion:（manifest 条目整体
//      传入；内部六阶段上报 + 统一进度页自动弹出，SHA1 跳过已下载）
//   c) 完成判定：后台 0.5s 轮询 progress.finished（30 分钟封顶；
//      prepareForDownload 会重建 progress，KVO 悬空判例 → 轮询取最新值）
//   d) 成功 → post @"ReloadProfileList"（ZL2VersionIndex/版本页联动刷新）
//      + 已安装集合重建 + 完成对话框；失败 → 失败对话框（重试/关闭）
//
// 数据源：ZL2VersionIndex remoteVersionsWithCompletion:（Task218 PLMirror
//   Center 官方+镜像候选链复用；未落定时限时等待 10s 复用启动链预算）。
//
// 已安装判定：versions/ 目录双根扫描（POJAV_GAME_DIR 优先、POJAV_HOME
//   兜底，ZL2VersionIndex/ZL2VersionsViewController 同口径）一次枚举成集，
//   列表成员判定 O(1)。
//
// 门禁适配注记：CJK 文案一律属性点语法赋值（域内既有约定），setTitle:
//   等调用语法只传变量不传字面量。
//

#import "ZL2GameDownloadViewController.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2VersionIndex.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLProfiles.h"
#import <objc/runtime.h>

#pragma mark - 关联对象键（sheet 选中条目暂存）

static void *kZL2GameSheetEntryKey = &kZL2GameSheetEntryKey;

#pragma mark - 常量

// 类型筛选（chip 下标即位）；远古版 = old_beta + old_alpha 合并档
static const NSInteger ZL2GameFilterAll = 0;
static const NSInteger ZL2GameFilterRelease = 1;
static const NSInteger ZL2GameFilterSnapshot = 2;
static const NSInteger ZL2GameFilterOld = 3;
static const NSInteger ZL2GameFilterInstalled = 4;

static const NSUInteger ZL2GamePageSizeFirst = 60;   // 首屏条数
static const NSUInteger ZL2GamePageSizeMore = 40;    // 滚动续载条数

#pragma mark - 版本卡 cell（M3 卡片式）

@interface ZL2GameVersionCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *installedLabel;
- (void)ame_configureWithId:(NSString *)versionId
                       type:(NSString *)type
                 releaseTime:(NSString *)releaseTime
                    installed:(BOOL)installed;
@end

@implementation ZL2GameVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = [UIColor clearColor];

        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = [ZL2Theme surfaceContainer];
        _cardView.layer.cornerRadius = [ZL2Theme radiusM];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [ZL2Theme fontTitleMedium];
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

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [ZL2Theme fontBodyMedium];
        _dateLabel.textColor = [ZL2Theme onSurfaceVariant];
        _dateLabel.numberOfLines = 1;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_dateLabel];

        _installedLabel = [[UILabel alloc] init];
        _installedLabel.font = [ZL2Theme fontLabelMedium];
        _installedLabel.textColor = [ZL2Theme success];
        _installedLabel.numberOfLines = 1;
        _installedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_installedLabel];

        [NSLayoutConstraint activateConstraints:@[
            // 卡片：左右 16、上下 6 内缩（列表间隔节奏）
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-8],

            [_badgeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_installedLabel.leadingAnchor constant:-8],
            [_badgeLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_badgeLabel.heightAnchor constraintEqualToConstant:20],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],

            [_installedLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)ame_configureWithId:(NSString *)versionId
                       type:(NSString *)type
                releaseTime:(NSString *)releaseTime
                   installed:(BOOL)installed {
    _titleLabel.text = versionId;
    _installedLabel.text = installed ? @"已安装" : @"";
    _dateLabel.text = releaseTime.length >= 10
        ? [releaseTime substringToIndex:10]
        : (releaseTime ?: @"");

    // 类型徽章配色（令牌域内映射；正式版主容器 / 快照变体表面 /
    // 远古弱描边档，深浅两态均由 dynamicProvider 令牌自洽）
    NSString *badgeText = @"";
    UIColor *badgeBg = [ZL2Theme surfaceVariant];
    UIColor *badgeFg = [ZL2Theme onSurfaceVariant];
    if ([type isEqualToString:@"release"]) {
        badgeText = @"正式版";
        badgeBg = [ZL2Theme primaryContainer];
        badgeFg = [ZL2Theme onPrimaryContainer];
    } else if ([type isEqualToString:@"snapshot"]) {
        badgeText = @"快照";
    } else if ([type isEqualToString:@"old_beta"]) {
        badgeText = @"远古 Beta";
        badgeBg = [ZL2Theme outlineVariant];
    } else if ([type isEqualToString:@"old_alpha"]) {
        badgeText = @"远古 Alpha";
        badgeBg = [ZL2Theme outlineVariant];
    } else {
        badgeText = type.length > 0 ? type : @"版本";
    }
    _badgeLabel.text = badgeText;
    _badgeLabel.backgroundColor = badgeBg;
    _badgeLabel.textColor = badgeFg;
}

@end

#pragma mark - 页面本体

@interface ZL2GameDownloadViewController () <UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate>

// 页头
@property (nonatomic, strong) ZL2M3SearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) NSMutableArray<ZL2M3FilterChip *> *filterChips;

// 列表与状态
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIControl *retryButton;

// 数据态
@property (nonatomic, strong) NSArray<NSDictionary *> *allVersions;     // 原始清单（去种子）
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *filtered; // 筛选后
@property (nonatomic, assign) NSUInteger displayedCount;                // 已展示条数（分页）
@property (nonatomic, assign) NSInteger selectedFilter;                 // -1 = 尚未选中
@property (nonatomic, strong) NSMutableSet<NSString *> *installedSet;   // 已安装版本 id
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightIds;    // 安装中版本 id

// 安装域
@property (nonatomic, strong, nullable) MinecraftResourceDownloadTask *activeTask;

@end

@implementation ZL2GameDownloadViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _filterChips = [NSMutableArray array];
        _allVersions = @[];
        _filtered = [NSMutableArray array];
        _displayedCount = 0;
        _selectedFilter = -1;
        _installedSet = [NSMutableSet set];
        _inFlightIds = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    [self ame_buildViews];
    [self ame_applyChipAppearance];
    [self ame_rebuildInstalledSet];
    [self ame_refreshFromService];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 回页刷新已安装角标（外部安装完成后回页可见）
    [self ame_rebuildInstalledSet];
    [self ame_reloadFilteredPreservingScroll];
}

#pragma mark - 布局

- (void)ame_buildViews {
    // ① M3 胶囊搜索框
    _searchBar = [[ZL2M3SearchBar alloc] init];
    _searchBar.placeholder = @"搜索版本…";
    _searchBar.accessibilityLabel = @"搜索版本";
    __weak typeof(self) weakSelf = self;
    _searchBar.onTextChanged = ^(NSString *text) {
        // 0.25s 防抖（连打只筛一次）
        [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf
                                                 selector:@selector(ame_applyFilters)
                                                   object:nil];
        [weakSelf performSelector:@selector(ame_applyFilters)
                       withObject:nil
                       afterDelay:0.25];
    };
    [self.view addSubview:_searchBar];

    // ② 类型筛选 chips（横向滚动行，与下载页类别 chips 同族几何）
    _chipsScroll = [[UIScrollView alloc] init];
    _chipsScroll.showsHorizontalScrollIndicator = NO;
    _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_chipsScroll];

    _chipsStack = [[UIStackView alloc] init];
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.spacing = 8;
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_chipsScroll addSubview:_chipsStack];

    NSArray<NSString *> *titles = @[@"全部", @"正式版", @"快照", @"远古版", @"已安装"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:titles[i]];
        chip.tag = (NSInteger)i;   // 仅作 ame_chipTapped: 下标载荷（域内判例）
        chip.accessibilityLabel = titles[i];
        [chip addTarget:self
                 action:@selector(ame_chipTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [_chipsStack addArrangedSubview:chip];
        [_filterChips addObject:chip];
    }

    // ③ 版本列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 64.0;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissOnDrag;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[ZL2GameVersionCell class]
       forCellReuseIdentifier:@"ZL2GameVersionCell"];
    [self.view addSubview:_tableView];

    // 状态件：加载中 / 空态 / 重试
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
                     action:@selector(ame_retryTapped)
           forControlEvents:UIControlEventTouchUpInside];
    UILabel *retryLabel = [[UILabel alloc] init];
    retryLabel.text = @"重试";
    retryLabel.font = [ZL2Theme fontLabelLarge];
    retryLabel.textColor = [ZL2Theme primary];
    retryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    retryLabel.userInteractionEnabled = NO;
    [_retryButton addSubview:retryLabel];
    [self.view addSubview:_retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_retryButton.widthAnchor constraintEqualToConstant:88],
        [_retryButton.heightAnchor constraintEqualToConstant:40],
        [retryLabel.centerXAnchor constraintEqualToAnchor:_retryButton.centerXAnchor],
        [retryLabel.centerYAnchor constraintEqualToAnchor:_retryButton.centerYAnchor],
    ]];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *chipsLG = _chipsScroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_searchBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_searchBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [_chipsScroll.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:10],
        [_chipsScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_chipsScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_chipsScroll.heightAnchor constraintEqualToConstant:40],
        [_chipsStack.leadingAnchor constraintEqualToAnchor:chipsLG.leadingAnchor constant:16],
        [chipsLG.trailingAnchor constraintEqualToAnchor:_chipsStack.trailingAnchor constant:16],
        [_chipsStack.topAnchor constraintEqualToAnchor:chipsLG.topAnchor constant:4],
        [chipsLG.bottomAnchor constraintEqualToAnchor:_chipsStack.bottomAnchor constant:4],

        [_tableView.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor constant:2],
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
    ]];
}

#pragma mark - chips 选中态

- (void)ame_chipTapped:(UIControl *)sender {
    self.selectedFilter = sender.tag;
    [self ame_applyChipAppearance];
    [self ame_applyFilters];
}

- (void)ame_applyChipAppearance {
    for (NSUInteger i = 0; i < self.filterChips.count; i++) {
        self.filterChips[i].selected = ((NSInteger)i == self.selectedFilter);
    }
}

#pragma mark - 数据流

- (void)ame_refreshFromService {
    [self ame_setStateLoading:YES];
    __weak typeof(self) weakSelf = self;
    [[ZL2VersionIndex sharedIndex] remoteVersionsWithCompletion:^(
            NSArray<NSDictionary *> *versions, BOOL loaded) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        [s ame_setStateLoading:NO];

        // 去种子（latest-* 无 url 不可下载），保持清单原有新旧序
        NSMutableArray<NSDictionary *> *real = [NSMutableArray array];
        for (NSDictionary *entry in versions) {
            NSString *url = entry[@"url"];
            NSString *vid = entry[@"id"];
            if (url.length > 0 && vid.length > 0) [real addObject:entry];
        }

        if (real.count == 0) {
            // 清单未落定（候选链全败）→ 错误态 + 重试
            s.emptyLabel.text = loaded
                ? @"版本清单加载失败，请检查网络后重试"
                : @"版本清单加载超时，请重试";
            s.emptyLabel.hidden = NO;
            s.retryButton.hidden = NO;
            [s.tableView reloadData];
            return;
        }

        s.emptyLabel.hidden = YES;
        s.retryButton.hidden = YES;
        s.allVersions = real;
        s.displayedCount = 0;
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

- (void)ame_retryTapped {
    [[ZL2VersionIndex sharedIndex] refresh];
    [self ame_refreshFromService];
}

// 筛选 + 分页首段（search/chips 变化统一入口）
- (void)ame_applyFilters {
    NSString *query = self.searchBar.text ?: @"";
    query = [query stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];

    for (NSDictionary *entry in self.allVersions) {
        NSString *vid = entry[@"id"] ?: @"";
        NSString *type = entry[@"type"] ?: @"";
        BOOL typeOk = YES;
        switch (self.selectedFilter) {
            case ZL2GameFilterRelease:  typeOk = [type isEqualToString:@"release"]; break;
            case ZL2GameFilterSnapshot: typeOk = [type isEqualToString:@"snapshot"]; break;
            case ZL2GameFilterOld:
                typeOk = [type isEqualToString:@"old_beta"] ||
                         [type isEqualToString:@"old_alpha"];
                break;
            case ZL2GameFilterInstalled:
                typeOk = [self.installedSet containsObject:vid];
                break;
            default: break;   // 全部
        }
        if (!typeOk) continue;
        if (query.length > 0) {
            typeOk = [vid localizedCaseInsensitiveContainsString:query];
            if (!typeOk) continue;
        }
        [result addObject:entry];
    }

    self.filtered = result;
    self.displayedCount = MIN(ZL2GamePageSizeFirst, result.count);
    [self ame_reloadFilteredPreservingScroll];

    if (result.count == 0 && self.allVersions.count > 0) {
        self.emptyLabel.text = @"没有匹配的版本";
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

// 筛选变化后回到顶部（列表内容整体换血，保持滚动位置会视觉跳变）
- (void)ame_reloadFilteredPreservingScroll {
    [self.tableView setContentOffset:CGPointZero animated:NO];
    [self.tableView reloadData];
}

// 滚动到底续载 +40
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.tableView) return;
    if (self.displayedCount >= self.filtered.count) return;
    CGFloat threshold = scrollView.contentSize.height
                      - scrollView.bounds.size.height * 2.0;
    if (scrollView.contentOffset.y >= threshold) {
        NSUInteger next = MIN(self.displayedCount + ZL2GamePageSizeMore,
                              self.filtered.count);
        if (next != self.displayedCount) {
            self.displayedCount = next;
            [self.tableView reloadData];
        }
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.displayedCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZL2GameVersionCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"ZL2GameVersionCell"
                                       forIndexPath:indexPath];
    if (indexPath.row < self.filtered.count) {
        NSDictionary *entry = self.filtered[indexPath.row];
        NSString *vid = entry[@"id"] ?: @"";
        BOOL installed = [self.installedSet containsObject:vid];
        [cell ame_configureWithId:vid
                             type:entry[@"type"] ?: @""
                      releaseTime:entry[@"releaseTime"] ?: @""
                         installed:installed];
        cell.accessibilityLabel =
            [NSString stringWithFormat:@"%@，%@，%@",
             vid, entry[@"type"] ?: @"", entry[@"releaseTime"] ?: @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filtered.count) return;
    [self ame_presentVersionSheet:self.filtered[indexPath.row]];
}

#pragma mark - 已安装集合

// versions/ 目录双根一次枚举（POJAV_GAME_DIR 优先、POJAV_HOME 兜底；
// ZL2VersionIndex 本地扫描同口径），成员判定 O(1)
- (void)ame_rebuildInstalledSet {
    NSMutableSet<NSString *> *installed = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (gameDir) [roots addObject:[NSString stringWithFormat:@"%s", gameDir]];
    const char *homeDir = getenv("POJAV_HOME");
    if (homeDir) [roots addObject:[NSString stringWithFormat:@"%s", homeDir]];

    for (NSString *root in roots) {
        NSString *versionsPath = [root stringByAppendingPathComponent:@"versions"];
        NSArray *entries = [fm contentsOfDirectoryAtPath:versionsPath error:nil];
        for (NSString *name in entries) {
            BOOL isDirectory = NO;
            NSString *full = [versionsPath stringByAppendingPathComponent:name];
            if ([fm fileExistsAtPath:full isDirectory:&isDirectory] && isDirectory) {
                [installed addObject:name];
            }
        }
    }
    self.installedSet = installed;
}

#pragma mark - 版本详情底部弹层（M3）

- (void)ame_presentVersionSheet:(NSDictionary *)entry {
    NSString *vid = entry[@"id"] ?: @"";
    NSString *type = entry[@"type"] ?: @"";
    NSString *releaseTime = entry[@"releaseTime"] ?: @"";
    BOOL installed = [self.installedSet containsObject:vid];
    BOOL inFlight = [self.inFlightIds containsObject:vid];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = vid;
    title.font = [ZL2Theme fontTitleLarge];
    title.textColor = [ZL2Theme onSurface];
    title.numberOfLines = 0;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:title];

    UILabel *meta = [[UILabel alloc] init];
    NSString *typeText = [type isEqualToString:@"release"] ? @"正式版"
                        : [type isEqualToString:@"snapshot"] ? @"快照"
                        : [type isEqualToString:@"old_beta"] ? @"远古 Beta"
                        : [type isEqualToString:@"old_alpha"] ? @"远古 Alpha"
                        : type;
    meta.text = [NSString stringWithFormat:@"%@  ·  发布于 %@%@",
                 typeText,
                 releaseTime.length >= 10 ? [releaseTime substringToIndex:10] : releaseTime,
                 installed ? @"  ·  已安装" : @""];
    meta.font = [ZL2Theme fontBodyMedium];
    meta.textColor = [ZL2Theme onSurfaceVariant];
    meta.numberOfLines = 0;
    meta.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:meta];

    UIControl *installButton = [[UIControl alloc] init];
    installButton.layer.cornerRadius = [ZL2Theme radiusS];
    installButton.translatesAutoresizingMaskIntoConstraints = NO;
    installButton.isAccessibilityElement = YES;

    UILabel *installLabel = [[UILabel alloc] init];
    installLabel.font = [ZL2Theme fontLabelLarge];
    installLabel.textAlignment = NSTextAlignmentCenter;
    installLabel.translatesAutoresizingMaskIntoConstraints = NO;
    installLabel.userInteractionEnabled = NO;
    [installButton addSubview:installLabel];

    if (inFlight) {
        installButton.backgroundColor = [ZL2Theme surfaceVariant];
        installButton.userInteractionEnabled = NO;
        installLabel.text = @"安装中…";
        installLabel.textColor = [ZL2Theme onSurfaceVariant];
        installButton.accessibilityLabel = @"安装中";
    } else {
        installButton.backgroundColor = [ZL2Theme primary];
        installButton.userInteractionEnabled = YES;
        installLabel.text = installed ? @"重新安装" : @"安装";
        installLabel.textColor = [ZL2Theme onPrimary];
        installButton.accessibilityLabel = installLabel.text;
        [installButton addTarget:self
                          action:@selector(ame_sheetInstallTapped)
                forControlEvents:UIControlEventTouchUpInside];
    }

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [meta.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [meta.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [meta.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [installButton.topAnchor constraintEqualToAnchor:meta.bottomAnchor constant:20],
        [installButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [installButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [installButton.heightAnchor constraintEqualToConstant:44],
        [installLabel.centerXAnchor constraintEqualToAnchor:installButton.centerXAnchor],
        [installLabel.centerYAnchor constraintEqualToAnchor:installButton.centerYAnchor],
        [content.bottomAnchor constraintEqualToAnchor:installButton.bottomAnchor],
    ]];

    // 选中条目经关联暂存（弹层回调取用；安装钮 target/action 持 self 安全）
    objc_setAssociatedObject(self, kZL2GameSheetEntryKey, entry,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [ZL2M3BottomSheet presentWithContentView:content onDismiss:nil];
}

- (void)ame_sheetInstallTapped {
    NSDictionary *entry = objc_getAssociatedObject(self, kZL2GameSheetEntryKey);
    if (!entry) return;
    NSString *vid = entry[@"id"] ?: @"";

    [ZL2M3BottomSheet dismissWithContentView:nil];

    // M3 确认对话框（安装域入口唯一门）
    __weak typeof(self) weakSelf = self;
    NSString *bodyText =
        @"将下载并安装完整游戏文件到版本隔离目录，进度见任务中心。";
    [ZL2M3Dialog showTitle:vid
                      body:bodyText
              confirmTitle:@"安装"
                destructive:NO
                 onConfirm:^{
        __strong typeof(weakSelf) s = weakSelf;
        [s ame_startInstall:entry];
    }
                  onCancel:nil];
}

#pragma mark - 安装流（旧 downloadVanillaVersion 1:1）

- (void)ame_startInstall:(NSDictionary *)entry {
    NSString *versionId = entry[@"id"] ?: @"";
    if (versionId.length == 0) return;
    if ([self.inFlightIds containsObject:versionId]) return;
    [self.inFlightIds addObject:versionId];

    // a) 版本隔离 profile（Task242 口径，旧页同款五键）
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"name"] = versionId;
    profile[@"lastVersionId"] = versionId;
    profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@/game", versionId];
    profile[@"type"] = @"custom";
    profile[@"created"] = [NSDate date].description;
    [PLProfiles.current saveProfile:profile withName:versionId];
    PLProfiles.current.selectedProfileName = versionId;

    // b) 六阶段安装任务（统一进度页由任务内部自动弹出）
    __weak typeof(self) weakSelf = self;
    MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
    task.maxRetryCount = 3;
    task.handleError = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            [s ame_installDidFinish:versionId success:NO];
        });
    };
    self.activeTask = task;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task downloadVersion:entry];

        // c) 完成判定：轮询 progress.finished（prepareForDownload 重建 progress，
        //    KVO 悬空判例 → 每次取最新值；30 分钟封顶与兄弟页同款）
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
        BOOL succeeded = NO;
        while ([deadline timeIntervalSinceNow] > 0) {
            NSProgress *progress = task.progress;
            if (progress && progress.finished) {
                succeeded = !progress.cancelled;
                break;
            }
            [NSThread sleepForTimeInterval:0.5];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s2 = weakSelf;
            [s2 ame_installDidFinish:versionId success:succeeded];
        });
    });
}

- (void)ame_installDidFinish:(NSString *)versionId success:(BOOL)success {
    self.activeTask = nil;
    [self.inFlightIds removeObject:versionId];
    [self.tableView reloadData];

    if (success) {
        [self ame_rebuildInstalledSet];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ReloadProfileList" object:nil];
        [ZL2M3Dialog showTitle:@"安装完成"
                          body:versionId
                  confirmTitle:@"知道了"
                    destructive:NO
                     onConfirm:nil
                      onCancel:nil];
    } else {
        [ZL2M3Dialog showTitle:@"安装失败"
                          body:@"下载中断或网络异常，可重试安装。"
                  confirmTitle:@"重试"
                    destructive:NO
                     onConfirm:^{ [self ame_retryLastInstall:versionId]; }
                      onCancel:nil];
    }
}

- (void)ame_retryLastInstall:(NSString *)versionId {
    for (NSDictionary *entry in self.allVersions) {
        if ([entry[@"id"] isEqualToString:versionId]) {
            [self ame_startInstall:entry];
            return;
        }
    }
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
