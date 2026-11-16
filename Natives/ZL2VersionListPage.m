//
// ZL2VersionListPage.m — ZL2 版本列表统一页（结构契约见 .h）
//
// 【旧页功能面对表】（★Task436 批次二④；三旧页 = ModVersionViewController /
//   ShaderVersionViewController / AssetVersionViewController，逐项登记）：
//
//  ┌────────────────────────────┬──────────────────────────────────────────┐
//  │ 旧页功能面                  │ 新页落位                                  │
//  ├────────────────────────────┼──────────────────────────────────────────┤
//  │ chips 筛选条（来源/版本/     │ 筛选面板卡（ZL2M3FilterChip 横滑行）；     │
//  │ 加载器/排序）四行            │ 行形态按域裁剪：Asset 无来源/加载器行      │
//  │ 下载源切换（Mod/Shader）     │ 来源行 Modrinth/CurseForge chips +        │
//  │                            │ CurseForgeAPI isSourceAvailable 门控       │
//  │ Task247 跨源 id 解析（仅Mod）│ ame_resolveCounterpart 1:1 移植（含缓存）  │
//  │ 版本行卡片（名/版本号/发布   │ ZL2VersionRowCell（surfaceContainer 卡 +  │
//  │ 类型徽章/加载器徽章/日期/    │ 发布类型徽章 + ModLoaderIconHelper 品牌    │
//  │ 大小/游戏版本/chevron）     │ 色徽章 + 日期/大小/游戏版本右列；ZL2 卡片 │
//  │                            │ 家族无 chevron——整行点击即选择）          │
//  │ 项目详情头（封面/标题/作者/  │ 详情头卡（同字段面）+ ★Task436 收藏胶囊   │
//  │ 下载量/关注/描述/标签/更新） │ （ZL2FavoritesStore 直连，旧 Task428/429  │
//  │                            │ 胶囊口径：44pt 命中面/heart.fill 选中态） │
//  │ preferred 自动选中 + 置顶    │ processFilters/applyFiltersAndSort 1:1    │
//  │ 排序四档（相关度/下载量/     │ 同值域同键（i18n_str_162/32/33/34）；     │
//  │ 最新更新/创建时间）         │ 下载量档回退 API 原序（版本级无该字段）    │
//  │ 拉取链（Modrinth/CurseForge  │ getVersionsForModWithID: 统一（Modrinth   │
//  │ getVersionsForModWithID /   │ 光影旧走 getVersionsForShaderWithID:——   │
//  │ getVersionsForShaderWithID）│ 同端点同解析，仅模型类名差异，登记口径）   │
//  │ 拉取失败/空列表提示（alert）  │ InlineMessageView 错误条 + ZL2 空态卡     │
//  │                            │ （反馈面等价，ZL2 家族形态）               │
//  │ 加载指示（大 spinner 居中）   │ 同款（ZL2Theme primary 色）               │
//  │ 前置区（Task236 富条目，仅Mod）│ 不随迁（如实偏差）：ZL2 下载链已有       │
//  │                            │ Task227 依赖确认单承接（父页 ame227 链），│
//  │                            │ 预展示区功能性重复                        │
//  │ BackgroundManager 毛玻璃适配 │ ZL2 域实底（ZL2Theme surface，ZL2 红线：  │
//  │                            │ 零 AmeTheme / 零 BackgroundManager）      │
//  └────────────────────────────┴──────────────────────────────────────────┘
//
// 【预览 harness 判例】API 双源走自含最小 @interface（不 import ModrinthAPI.h /
//   CurseForgeAPI.h——UnzipKit.h 传递链在 ui_fluent_smoke COMMON -I 下不可达，
//   ZL2AssetSearch 7.0-UI-10-f 判例同款）；类符号由预览桩 Preview/ZL2PagesStub.m
//   或真实 .m 按链接目标供给。
//

#import "ZL2VersionListPage.h"
#import "utils.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ModItem.h"
#import "ShaderItem.h"
#import "IconLoader.h"
#import "ModLoaderIconHelper.h"
#import "InlineMessageView.h"
#import "ZL2FavoritesStore.h"

// ── API 双源本地最小声明（仅声明，无实现——类符号 OBJC_CLASS_$_ModrinthAPI /
//    OBJC_CLASS_$_CurseForgeAPI 由预览 harness 桩 TU 或真实 .m 按链接目标供给。
//    签名照抄 installer/modpack/ModrinthAPI.h / CurseForgeAPI.h，本 TU 消费面：
//    sharedInstance / isSourceAvailable / getVersionsForModWithID / 跨源解析
//    复用的 searchModWithFilters）
@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

#pragma mark - 静态工具

static const NSInteger ZL2VListSourceModrinth   = 1;
static const NSInteger ZL2VListSourceCurseForge = 2;

// 排序方式常量（与旧页 kSort* 同值域同序）
static NSString *const ZL2VListSortRelevance = @"relevance";
static NSString *const ZL2VListSortDownloads = @"downloads";
static NSString *const ZL2VListSortUpdated   = @"updated";
static NSString *const ZL2VListSortCreated   = @"created";

// SF Symbols 取图兜底（ZL2Home/ZL2Download 同款 helper：符号名异常时降级旧名）
static UIImage *ZL2VListSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

// 格式化下载量数字（ZL2 中文量级口径 1:1 复刻 ZL2AssetSearch 同名 helper：
// 1234567 → 123.5万；量级文案复用既有键 ame369.asearch.dl_*_fmt）
static NSString *ZL2VListFormatTrimZero(NSString *text) {
    if ([text hasSuffix:@".0"]) {
        return [text substringToIndex:text.length - 2];
    }
    return text;
}

static NSString *ZL2VListFormatDownloadCount(NSNumber *downloads) {
    if (!downloads) return @"0";
    NSInteger dl = [downloads integerValue];
    if (dl >= 100000000) {
        NSString *raw = [NSString stringWithFormat:localize(@"ame369.asearch.dl_yi_fmt", @"%.1f亿"), dl / 100000000.0];
        return ZL2VListFormatTrimZero(raw);
    }
    if (dl >= 10000) {
        NSString *raw = [NSString stringWithFormat:localize(@"ame369.asearch.dl_wan_fmt", @"%.1f万"), dl / 10000.0];
        return ZL2VListFormatTrimZero(raw);
    }
    return [NSString stringWithFormat:@"%ld", (long)dl];
}

// 排序选项表（旧页 SortOptionItems 同值域：文案复用旧页既有 i18n 键，零新键）
static NSArray<NSDictionary *> *ZL2VListSortOptionItems(void) {
    static NSArray *items = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            @{ @"key": ZL2VListSortRelevance, @"title": localize(@"i18n_str_162", nil) },
            @{ @"key": ZL2VListSortDownloads, @"title": localize(@"i18n_str_32", nil) },
            @{ @"key": ZL2VListSortUpdated,   @"title": localize(@"i18n_str_33", nil) },
            @{ @"key": ZL2VListSortCreated,   @"title": localize(@"i18n_str_34", nil) },
        ];
    });
    return items;
}

#pragma mark - 版本行卡片 Cell（旧 ModVersionTableViewCell ZL2 化）

// 卡片结构（ZL2 卡片家族形态，对齐 ZL2AssetResultCell 卡面惯例）：
//   卡（surfaceContainer / radiusL / 内边距 10）
//   ├ 左列：版本名（fontTitleMedium）+ 发布类型徽章（Release绿/Beta橙/Alpha红）
//   │        版本号（fontBodyMedium 次级）
//   │        加载器徽章行（ModLoaderIconHelper 品牌色 pill，最多 4 个 + "+N"）
//   └ 右列：发布日期 / 文件大小 / 游戏版本（fontLabelMedium 次级，右对齐）
@interface ZL2VersionRowCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *releaseBadge;
@property (nonatomic, strong) UILabel *versionNumberLabel;
@property (nonatomic, strong) UIStackView *loaderBadgeStack;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *gameVersionsLabel;
- (void)ame_configureWithVersion:(ModVersion *)version;
@end

@implementation ZL2VersionRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = [ZL2Theme surfaceContainer];
        _cardView.layer.cornerRadius = [ZL2Theme radiusL];
        _cardView.layer.masksToBounds = YES;
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [ZL2Theme fontTitleMedium];
        _nameLabel.textColor = [ZL2Theme onSurface];
        _nameLabel.numberOfLines = 1;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.7;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_nameLabel];

        _releaseBadge = [[UILabel alloc] init];
        _releaseBadge.font = [ZL2Theme fontLabelMedium];
        _releaseBadge.textColor = [UIColor whiteColor];
        _releaseBadge.textAlignment = NSTextAlignmentCenter;
        _releaseBadge.layer.cornerRadius = 7;
        _releaseBadge.layer.masksToBounds = YES;
        _releaseBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _releaseBadge.hidden = YES;   // configure 时按发布类型显示
        [_releaseBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_releaseBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_cardView addSubview:_releaseBadge];

        _versionNumberLabel = [[UILabel alloc] init];
        _versionNumberLabel.font = [ZL2Theme fontBodyMedium];
        _versionNumberLabel.textColor = [ZL2Theme onSurfaceVariant];
        _versionNumberLabel.numberOfLines = 1;
        _versionNumberLabel.adjustsFontSizeToFitWidth = YES;
        _versionNumberLabel.minimumScaleFactor = 0.7;
        _versionNumberLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _versionNumberLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_versionNumberLabel];

        _loaderBadgeStack = [[UIStackView alloc] init];
        _loaderBadgeStack.axis = UILayoutConstraintAxisHorizontal;
        _loaderBadgeStack.spacing = 5;
        _loaderBadgeStack.alignment = UIStackViewAlignmentCenter;
        _loaderBadgeStack.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_loaderBadgeStack];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [ZL2Theme fontLabelMedium];
        _dateLabel.textColor = [ZL2Theme onSurfaceVariant];
        _dateLabel.textAlignment = NSTextAlignmentRight;
        _dateLabel.numberOfLines = 1;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_dateLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [ZL2Theme fontLabelMedium];
        _sizeLabel.textColor = [ZL2Theme onSurfaceVariant];
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.numberOfLines = 1;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_sizeLabel];

        _gameVersionsLabel = [[UILabel alloc] init];
        _gameVersionsLabel.font = [ZL2Theme fontLabelMedium];
        _gameVersionsLabel.textColor = [ZL2Theme onSurfaceVariant];
        _gameVersionsLabel.textAlignment = NSTextAlignmentRight;
        _gameVersionsLabel.numberOfLines = 1;
        _gameVersionsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _gameVersionsLabel.adjustsFontSizeToFitWidth = YES;
        _gameVersionsLabel.minimumScaleFactor = 0.7;
        _gameVersionsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_gameVersionsLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:10],
            [_nameLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:8],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_dateLabel.leadingAnchor constant:-12],

            [_releaseBadge.leadingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor constant:6],
            [_releaseBadge.centerYAnchor constraintEqualToAnchor:_nameLabel.centerYAnchor],
            [_releaseBadge.heightAnchor constraintEqualToConstant:16],
            [_releaseBadge.trailingAnchor constraintLessThanOrEqualToAnchor:_dateLabel.leadingAnchor constant:-12],

            [_versionNumberLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:10],
            [_versionNumberLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
            [_versionNumberLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_dateLabel.leadingAnchor constant:-12],

            [_loaderBadgeStack.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:10],
            [_loaderBadgeStack.topAnchor constraintEqualToAnchor:_versionNumberLabel.bottomAnchor constant:4],
            [_loaderBadgeStack.trailingAnchor constraintLessThanOrEqualToAnchor:_dateLabel.leadingAnchor constant:-12],
            [_loaderBadgeStack.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-8],

            [_dateLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:9],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10],

            [_sizeLabel.topAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor constant:3],
            [_sizeLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10],

            [_gameVersionsLabel.topAnchor constraintEqualToAnchor:_sizeLabel.bottomAnchor constant:3],
            [_gameVersionsLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10],
            [_gameVersionsLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-9],
            [_gameVersionsLabel.widthAnchor constraintLessThanOrEqualToConstant:120],
        ]];
    }
    return self;
}

// 加载器徽章 pill（旧 cell 同款形态 ZL2 化：ModLoaderIconHelper 品牌色统一
// 配色源，最多 4 个 + "+N" 溢出徽章——旧 configureLoaderBadges 口径 1:1）
- (UILabel *)ame_loaderBadgeForName:(NSString *)loaderName {
    UILabel *badge = [[UILabel alloc] init];
    badge.text = loaderName;
    badge.font = [ZL2Theme fontLabelMedium];
    badge.textColor = [UIColor whiteColor];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [ModLoaderIconHelper brandColorForLoader:loaderName];
    badge.layer.cornerRadius = 7;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [badge.heightAnchor constraintEqualToConstant:16],
    ]];
    return badge;
}

- (void)ame_configureWithVersion:(ModVersion *)version {
    _nameLabel.text = version.name;
    _versionNumberLabel.text = version.versionNumber;

    // 发布类型徽章（旧 cell 同色档：Release 绿 / Beta 橙 / Alpha 红——ZL2Theme 令牌）
    NSString *vType = version.versionType.lowercaseString;
    if ([vType isEqualToString:@"beta"]) {
        _releaseBadge.text = @" Beta ";
        _releaseBadge.backgroundColor = [ZL2Theme warning];
        _releaseBadge.hidden = NO;
    } else if ([vType isEqualToString:@"alpha"]) {
        _releaseBadge.text = @" Alpha ";
        _releaseBadge.backgroundColor = [ZL2Theme error];
        _releaseBadge.hidden = NO;
    } else {
        // release / 空 = Release 档（旧 cell 口径：非 beta/alpha 恒绿徽）
        _releaseBadge.text = @" Release ";
        _releaseBadge.backgroundColor = [ZL2Theme success];
        _releaseBadge.hidden = NO;
    }

    // 发布日期（ISO 8601 → 短日期；解析失败 = "未知日期"，旧 cell 同文案键）
    NSISO8601DateFormatter *dateFormatter = [[NSISO8601DateFormatter alloc] init];
    NSDate *date = [dateFormatter dateFromString:version.datePublished];
    if (date) {
        NSDateFormatter *displayFormatter = [[NSDateFormatter alloc] init];
        displayFormatter.dateStyle = NSDateFormatterShortStyle;
        displayFormatter.timeStyle = NSDateFormatterNoStyle;
        _dateLabel.text = [displayFormatter stringFromDate:date];
    } else {
        _dateLabel.text = localize(@"i18n_str_460", nil);
    }

    // 文件大小（primaryFile 优先 → fileSize 兜底 → "未知大小"，旧 cell 同链）
    if (version.primaryFile) {
        _sizeLabel.text = [NSByteCountFormatter stringFromByteCount:[version.primaryFile[@"size"] longValue]
                                                          countStyle:NSByteCountFormatterCountStyleFile];
    } else if (version.fileSize) {
        _sizeLabel.text = [NSByteCountFormatter stringFromByteCount:[version.fileSize longValue]
                                                          countStyle:NSByteCountFormatterCountStyleFile];
    } else {
        _sizeLabel.text = localize(@"i18n_str_461", nil);
    }

    // 游戏版本兼容（旧 cell 同款 ", " 连接；宽度过窄自动截断）
    _gameVersionsLabel.text = [version.gameVersions componentsJoinedByString:@", "];

    // 加载器徽章（最多 4 + "+N"，旧 cell 口径 1:1）
    [_loaderBadgeStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSArray<NSString *> *loaders = version.loaders;
    if ([loaders isKindOfClass:[NSArray class]]) {
        NSInteger maxBadges = MIN(4, (NSInteger)loaders.count);
        for (NSInteger i = 0; i < maxBadges; i++) {
            NSString *loader = loaders[i];
            if (![loader isKindOfClass:[NSString class]] || loader.length == 0) continue;
            [_loaderBadgeStack addArrangedSubview:[self ame_loaderBadgeForName:loader]];
        }
        if ((NSInteger)loaders.count > 4) {
            UILabel *moreBadge = [[UILabel alloc] init];
            moreBadge.text = [NSString stringWithFormat:@"+%ld", (long)(loaders.count - 4)];
            moreBadge.font = [ZL2Theme fontLabelMedium];
            moreBadge.textColor = [ZL2Theme onSurface];
            moreBadge.textAlignment = NSTextAlignmentCenter;
            moreBadge.backgroundColor = [ZL2Theme surfaceContainerHighest];
            moreBadge.layer.cornerRadius = 7;
            moreBadge.layer.masksToBounds = YES;
            moreBadge.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [moreBadge.heightAnchor constraintEqualToConstant:16],
                [moreBadge.widthAnchor constraintEqualToConstant:24],
            ]];
            [_loaderBadgeStack addArrangedSubview:moreBadge];
        }
        _loaderBadgeStack.hidden = (loaders.count == 0);
    } else {
        _loaderBadgeStack.hidden = YES;
    }
}

// 旧页 cell 同款：高亮态压暗卡片（ZL2 Compose 的 ripple 等价物）
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardView.alpha = highlighted ? 0.7 : 1.0;
}

@end

#pragma mark - 主页面

@interface ZL2VersionListPage () <UITableViewDataSource, UITableViewDelegate>

// 筛选状态（旧页 selected* 同语义）
@property (nonatomic, assign) NSInteger selectedSource;      // 1=Modrinth 2=CurseForge
@property (nonatomic, copy) NSString *selectedSort;          // ZL2VListSort* 键
@property (nonatomic, copy) NSString *selectedGameVersion;   // "全部" 或版本号
@property (nonatomic, copy) NSString *selectedLoader;        // "全部" 或首字母大写加载器名

// 数据源（旧页 allVersions/filteredVersions 同语义；统一 ModVersion 承载）
@property (nonatomic, strong) NSArray<ModVersion *> *allVersions;
@property (nonatomic, strong) NSArray<ModVersion *> *filteredVersions;
@property (nonatomic, strong) NSArray<NSString *> *availableGameVersions;
@property (nonatomic, strong) NSArray<NSString *> *availableLoaders;

// ★Task436：Task247 跨源 id 解析缓存（key = selectedSource；旧页
// ame247_resolvedIDs 同语义——源切换后旧源 id 对另一源无意义）
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *resolvedIDs;

// 视图件
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerAuthorLabel;
@property (nonatomic, strong) UILabel *headerStatsLabel;
@property (nonatomic, strong) UILabel *headerDescLabel;
@property (nonatomic, strong) UILabel *headerTagsLabel;
@property (nonatomic, strong) UIControl *favoriteCapsule;
@property (nonatomic, strong) UIImageView *favoriteHeartIcon;
@property (nonatomic, strong) UILabel *favoriteLabel;

@property (nonatomic, strong) UIView *filterPanel;
@property (nonatomic, strong) UIStackView *filterMainStack;
@property (nonatomic, strong) UIView *sourceRow;
@property (nonatomic, strong) UIStackView *sourceChipStack;
@property (nonatomic, strong) UIView *versionRow;
@property (nonatomic, strong) UIStackView *versionChipStack;
@property (nonatomic, strong) UIView *loaderRow;
@property (nonatomic, strong) UIStackView *loaderChipStack;
@property (nonatomic, strong) UIView *sortRow;
@property (nonatomic, strong) UIStackView *sortChipStack;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UIImageView *emptyIconView;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation ZL2VersionListPage

#pragma mark - Lifecycle

- (instancetype)initWithDomain:(ZL2VersionListDomain)domain {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _domainType = domain;
        _selectedSource = ZL2VListSourceModrinth;
        _selectedSort = ZL2VListSortRelevance;
        _resolvedIDs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pageTitle;
    self.view.backgroundColor = [ZL2Theme surface];

    // 拉取源：沿用搜索/直查阶段携带的 API 来源（旧页同语义——CF 数字 id 拿去
    // 请求 Modrinth 必然拉空，关键修复随旧页移植）
    self.selectedSource = (self.apiSource == ZL2VListSourceCurseForge)
        ? ZL2VListSourceCurseForge : ZL2VListSourceModrinth;

    [self ame_buildViews];
    [self ame_refreshFavoriteState];
    [self ame_fetchVersionsFromCurrentSource];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 旧页 Task428 同款：回本页时同步收藏态（收藏可能在推入页变更）
    [self ame_refreshFavoriteState];
}

#pragma mark - 详情头数据派生（Mod/Shader 域从 item 模型派生，Asset 域用显式字段）

- (NSString *)ame_headerTitleValue {
    if (self.modItem.displayName.length > 0) return self.modItem.displayName;
    if (self.shaderItem.displayName.length > 0) return self.shaderItem.displayName;
    return self.headerTitle ?: @"";
}

- (NSString *)ame_headerIconValue {
    if (self.modItem.iconURL.length > 0) return self.modItem.iconURL;
    if (self.shaderItem.iconURL.length > 0) return self.shaderItem.iconURL;
    return self.headerIconURL ?: @"";
}

- (NSString *)ame_headerAuthorValue {
    if (self.modItem.author.length > 0) return self.modItem.author;
    if (self.shaderItem.author.length > 0) return self.shaderItem.author;
    return self.headerAuthor ?: @"";
}

- (NSNumber *)ame_headerDownloadsValue {
    if (self.modItem.downloads) return self.modItem.downloads;
    if (self.shaderItem.downloads) return self.shaderItem.downloads;
    return self.headerDownloads;
}

- (NSNumber *)ame_headerLikesValue {
    if (self.modItem.likes) return self.modItem.likes;
    if (self.shaderItem.likes) return self.shaderItem.likes;
    return self.headerLikes;
}

- (NSString *)ame_headerDescriptionValue {
    if (self.modItem.modDescription.length > 0) return self.modItem.modDescription;
    if (self.shaderItem.shaderDescription.length > 0) return self.shaderItem.shaderDescription;
    return self.headerDescription ?: @"";
}

- (NSArray<NSString *> *)ame_headerCategoriesValue {
    if (self.modItem.categories.count > 0) return self.modItem.categories;
    if (self.shaderItem.categories.count > 0) return self.shaderItem.categories;
    return self.headerCategories ?: @[];
}

- (NSString *)ame_headerLastUpdatedValue {
    if (self.modItem.lastUpdated.length > 0) return self.modItem.lastUpdated;
    if (self.shaderItem.lastUpdated.length > 0) return self.shaderItem.lastUpdated;
    return self.headerLastUpdated ?: @"";
}

// 收藏键三件（platform 收敛 1/2——旧页 ame428_isFavorite 同口径；projectId 空
// = 本地/无平台侧 id，胶囊整体隐藏）
- (NSInteger)ame_platformForSnapshot {
    return (self.apiSource == ZL2VListSourceCurseForge) ? ZL2VListSourceCurseForge : ZL2VListSourceModrinth;
}

- (NSString *)ame_projectIDForSnapshot {
    NSString *pid = self.projectID;
    if (pid.length == 0 && self.modItem) pid = self.modItem.onlineID;
    if (pid.length == 0 && self.shaderItem) pid = self.shaderItem.onlineID;
    return pid ?: @"";
}

- (NSString *)ame_projectTypeForSnapshot {
    if (self.snapshotProjectType.length > 0) return self.snapshotProjectType;
    switch (self.domainType) {
        case ZL2VersionListDomainMod:    return @"mod";
        case ZL2VersionListDomainShader: return @"shader";
        case ZL2VersionListDomainAsset:  return @"resourcepack";   // 资产域请显式传入（.h 注记）
    }
    return @"mod";
}

#pragma mark - Layout

- (void)ame_buildViews {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ① 详情头卡（旧页 AssetDetailHeaderView 字段面 ZL2 卡片化；收藏胶囊挂右上）
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [ZL2Theme surfaceContainer];
    _headerCard.layer.cornerRadius = [ZL2Theme radiusL];
    _headerCard.layer.masksToBounds = YES;
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    _headerIconView = [[UIImageView alloc] init];
    _headerIconView.contentMode = UIViewContentModeScaleAspectFit;
    _headerIconView.layer.cornerRadius = [ZL2Theme radiusM];
    _headerIconView.layer.masksToBounds = YES;
    _headerIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _headerIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerIconView];

    _headerTitleLabel = [[UILabel alloc] init];
    _headerTitleLabel.font = [ZL2Theme fontTitleMedium];
    _headerTitleLabel.textColor = [ZL2Theme onSurface];
    _headerTitleLabel.numberOfLines = 1;
    _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerTitleLabel];

    _headerAuthorLabel = [[UILabel alloc] init];
    _headerAuthorLabel.font = [ZL2Theme fontBodyMedium];
    _headerAuthorLabel.textColor = [ZL2Theme onSurfaceVariant];
    _headerAuthorLabel.numberOfLines = 1;
    _headerAuthorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerAuthorLabel];

    _headerStatsLabel = [[UILabel alloc] init];
    _headerStatsLabel.font = [ZL2Theme fontLabelMedium];
    _headerStatsLabel.textColor = [ZL2Theme onSurfaceVariant];
    _headerStatsLabel.numberOfLines = 1;
    _headerStatsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerStatsLabel];

    _headerDescLabel = [[UILabel alloc] init];
    _headerDescLabel.font = [ZL2Theme fontBodyMedium];
    _headerDescLabel.textColor = [ZL2Theme onSurfaceVariant];
    _headerDescLabel.numberOfLines = 2;
    _headerDescLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerDescLabel];

    _headerTagsLabel = [[UILabel alloc] init];
    _headerTagsLabel.font = [ZL2Theme fontLabelMedium];
    _headerTagsLabel.textColor = [ZL2Theme onSurfaceVariant];
    _headerTagsLabel.numberOfLines = 1;
    _headerTagsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerTagsLabel];

    // ★Task436：收藏胶囊（旧页 Task428/429 口径 ZL2 化——44pt 命中面 /
    // heart.fill 选中态 / ZL2FavoritesStore 单例直连；旧页 AmeTheme 粉 → ZL2
    // tertiary 主题令牌）
    _favoriteCapsule = [[UIControl alloc] init];
    _favoriteCapsule.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _favoriteCapsule.layer.cornerRadius = 22;
    _favoriteCapsule.layer.cornerCurve = kCACornerCurveContinuous;
    _favoriteCapsule.layer.borderWidth = 0.5;
    _favoriteCapsule.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    _favoriteCapsule.isAccessibilityElement = YES;
    _favoriteCapsule.accessibilityLabel = localize(@"ame369.common.favorites", @"收藏");
    _favoriteCapsule.accessibilityTraits = UIAccessibilityTraitButton;
    _favoriteCapsule.translatesAutoresizingMaskIntoConstraints = NO;
    [_favoriteCapsule addTarget:self
                         action:@selector(ame_favoriteTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:_favoriteCapsule];

    _favoriteHeartIcon = [[UIImageView alloc] init];
    _favoriteHeartIcon.contentMode = UIViewContentModeScaleAspectFit;
    _favoriteHeartIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteHeartIcon.userInteractionEnabled = NO;
    [_favoriteCapsule addSubview:_favoriteHeartIcon];

    _favoriteLabel = [[UILabel alloc] init];
    _favoriteLabel.font = [ZL2Theme fontLabelLarge];
    _favoriteLabel.textColor = [ZL2Theme onSurfaceVariant];
    _favoriteLabel.numberOfLines = 1;
    _favoriteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteLabel.userInteractionEnabled = NO;
    [_favoriteCapsule addSubview:_favoriteLabel];

    // 详情头数据填充（描述/标签空值整行隐藏自收——ZL2 卡 stack 语义）
    _headerTitleLabel.text = [self ame_headerTitleValue] ?: localize(@"i18n_str_38", nil);
    NSString *author = [self ame_headerAuthorValue];
    if (author.length > 0) {
        _headerAuthorLabel.text = [NSString stringWithFormat:localize(@"ame369.asearch.author_fmt", @"| 作者: %@"), author];
    } else {
        _headerAuthorLabel.text = nil;
        _headerAuthorLabel.hidden = YES;
    }
    NSString *stats = [NSString stringWithFormat:@"⬇ %@  ♡ %@",
                       ZL2VListFormatDownloadCount([self ame_headerDownloadsValue]),
                       ZL2VListFormatDownloadCount([self ame_headerLikesValue])];
    NSString *updated = [self ame_headerLastUpdatedValue];
    if (updated.length > 0) stats = [stats stringByAppendingFormat:@"  ·  %@", updated];
    _headerStatsLabel.text = stats;
    NSString *desc = [self ame_headerDescriptionValue];
    _headerDescLabel.text = desc;
    _headerDescLabel.hidden = (desc.length == 0);
    NSMutableString *tags = [NSMutableString string];
    for (NSString *category in [self ame_headerCategoriesValue]) {
        if (![category isKindOfClass:[NSString class]] || category.length == 0) continue;
        if (tags.length > 0) [tags appendString:@" "];
        [tags appendString:category];
    }
    _headerTagsLabel.text = tags;
    _headerTagsLabel.hidden = (tags.length == 0);

    UIImage *placeholderSymbol = [ZL2VListSystemImage(@"puzzlepiece.extension", @"puzzlepiece")
                                  imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _headerIconView.image = placeholderSymbol;
    [IconLoader loadIconForImageView:_headerIconView
                                URL:[self ame_headerIconValue]
                        placeholder:placeholderSymbol
                           fallback:placeholderSymbol
                         targetSize:CGSizeMake(56, 56)
                            options:IconLoaderOptionsDefault
                         completion:nil];

    // ② 筛选面板卡（行形态按域裁剪：Asset 无来源/加载器行——旧 Asset 页
    //    「移除下载源和加载器行」口径 1:1）
    _filterPanel = [[UIView alloc] init];
    _filterPanel.backgroundColor = [ZL2Theme surfaceContainer];
    _filterPanel.layer.cornerRadius = [ZL2Theme radiusL];
    _filterPanel.layer.masksToBounds = YES;
    _filterPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_filterPanel];

    _filterMainStack = [[UIStackView alloc] init];
    _filterMainStack.axis = UILayoutConstraintAxisVertical;
    _filterMainStack.spacing = 6;
    _filterMainStack.alignment = UIStackViewAlignmentFill;
    _filterMainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_filterPanel addSubview:_filterMainStack];

    if (self.domainType == ZL2VersionListDomainMod || self.domainType == ZL2VersionListDomainShader) {
        _sourceRow = [self ame_filterRowWithCaption:localize(@"i18n_str_462", nil)
                                         chipStackOut:&_sourceChipStack];
        [_filterMainStack addArrangedSubview:_sourceRow];
        [self ame_rebuildSourceChips];
    }

    _versionRow = [self ame_filterRowWithCaption:localize(@"i18n_str_39", nil)
                                    chipStackOut:&_versionChipStack];
    [_filterMainStack addArrangedSubview:_versionRow];
    [self ame_addChip:localize(@"i18n_str_463", nil) selected:NO toStack:_versionChipStack identifier:nil tag:0];

    if (self.domainType == ZL2VersionListDomainMod || self.domainType == ZL2VersionListDomainShader) {
        _loaderRow = [self ame_filterRowWithCaption:localize(@"i18n_str_114", nil)
                                       chipStackOut:&_loaderChipStack];
        [_filterMainStack addArrangedSubview:_loaderRow];
        [self ame_addChip:localize(@"i18n_str_464", nil) selected:NO toStack:_loaderChipStack identifier:nil tag:0];
    }

    _sortRow = [self ame_filterRowWithCaption:localize(@"i18n_str_41", nil)
                                 chipStackOut:&_sortChipStack];
    [_filterMainStack addArrangedSubview:_sortRow];
    [self ame_rebuildSortChips];

    // ③ 结果列表（ZL2 卡 cell；自动行高适配徽章行）
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 84;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.accessibilityLabel = localize(@"ame369.asearch.version_list_a11y", @"版本列表");
    [self.view addSubview:_tableView];
    [_tableView registerClass:[ZL2VersionRowCell class] forCellReuseIdentifier:@"ZL2VersionRowCell"];

    // ④ 加载指示 / ⑤ 空态（ZL2 家族形态：旧页 alert 反馈面等价移植）
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.color = [ZL2Theme primary];
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingIndicator];

    _emptyContainer = [[UIView alloc] init];
    _emptyContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyContainer.hidden = YES;
    [self.view addSubview:_emptyContainer];

    _emptyIconView = [[UIImageView alloc] init];
    _emptyIconView.contentMode = UIViewContentModeScaleAspectFit;
    _emptyIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _emptyIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyContainer addSubview:_emptyIconView];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.font = [ZL2Theme fontBodyMedium];
    _emptyLabel.textColor = [ZL2Theme onSurfaceVariant];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyContainer addSubview:_emptyLabel];

    // ⑥ 约束链：详情头 → 筛选面板 → 列表（纵排，全宽）
    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [_headerIconView.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_headerIconView.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:12],
        [_headerIconView.widthAnchor constraintEqualToConstant:56],
        [_headerIconView.heightAnchor constraintEqualToConstant:56],

        [_headerTitleLabel.leadingAnchor constraintEqualToAnchor:_headerIconView.trailingAnchor constant:12],
        [_headerTitleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:12],
        [_headerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_favoriteCapsule.leadingAnchor constant:-10],

        [_headerAuthorLabel.leadingAnchor constraintEqualToAnchor:_headerTitleLabel.leadingAnchor],
        [_headerAuthorLabel.topAnchor constraintEqualToAnchor:_headerTitleLabel.bottomAnchor constant:2],
        [_headerAuthorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_favoriteCapsule.leadingAnchor constant:-10],

        [_headerStatsLabel.leadingAnchor constraintEqualToAnchor:_headerTitleLabel.leadingAnchor],
        [_headerStatsLabel.topAnchor constraintEqualToAnchor:_headerAuthorLabel.bottomAnchor constant:3],
        [_headerStatsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_headerStatsLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_headerCard.bottomAnchor constant:-10],

        [_headerDescLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_headerDescLabel.topAnchor constraintEqualToAnchor:_headerIconView.bottomAnchor constant:10],
        [_headerDescLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],

        [_headerTagsLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_headerTagsLabel.topAnchor constraintEqualToAnchor:_headerDescLabel.bottomAnchor constant:6],
        [_headerTagsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_headerTagsLabel.bottomAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:-10],

        [_favoriteCapsule.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [_favoriteCapsule.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_favoriteCapsule.heightAnchor constraintEqualToConstant:44],
        [_favoriteCapsule.widthAnchor constraintGreaterThanOrEqualToConstant:64],

        [_favoriteHeartIcon.leadingAnchor constraintEqualToAnchor:_favoriteCapsule.leadingAnchor constant:12],
        [_favoriteHeartIcon.centerYAnchor constraintEqualToAnchor:_favoriteCapsule.centerYAnchor],
        [_favoriteHeartIcon.widthAnchor constraintEqualToConstant:22],
        [_favoriteHeartIcon.heightAnchor constraintEqualToConstant:22],

        [_favoriteLabel.leadingAnchor constraintEqualToAnchor:_favoriteHeartIcon.trailingAnchor constant:6],
        [_favoriteLabel.trailingAnchor constraintEqualToAnchor:_favoriteCapsule.trailingAnchor constant:-12],
        [_favoriteLabel.centerYAnchor constraintEqualToAnchor:_favoriteCapsule.centerYAnchor],

        [_filterPanel.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8],
        [_filterPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_filterPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [_filterMainStack.topAnchor constraintEqualToAnchor:_filterPanel.topAnchor constant:8],
        [_filterMainStack.leadingAnchor constraintEqualToAnchor:_filterPanel.leadingAnchor constant:10],
        [_filterMainStack.trailingAnchor constraintEqualToAnchor:_filterPanel.trailingAnchor constant:-10],
        [_filterMainStack.bottomAnchor constraintEqualToAnchor:_filterPanel.bottomAnchor constant:-8],

        [_tableView.topAnchor constraintEqualToAnchor:_filterPanel.bottomAnchor constant:6],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor],

        [_emptyContainer.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_emptyContainer.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor],
        [_emptyContainer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [_emptyContainer.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],

        [_emptyIconView.topAnchor constraintEqualToAnchor:_emptyContainer.topAnchor],
        [_emptyIconView.centerXAnchor constraintEqualToAnchor:_emptyContainer.centerXAnchor],
        [_emptyIconView.widthAnchor constraintEqualToConstant:68],
        [_emptyIconView.heightAnchor constraintEqualToConstant:68],

        [_emptyLabel.topAnchor constraintEqualToAnchor:_emptyIconView.bottomAnchor constant:12],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_emptyContainer.centerXAnchor],
        [_emptyLabel.bottomAnchor constraintEqualToAnchor:_emptyContainer.bottomAnchor],
    ]];
}

// 通用筛选行（左 caption + 右横滑 chips；旧页 createFilterRowWithIconName
// 行结构 ZL2 化——图标省略，caption fontLabelMedium）
- (UIView *)ame_filterRowWithCaption:(NSString *)caption
                        chipStackOut:(UIStackView **)chipStackOut {
    UILabel *captionLabel = [[UILabel alloc] init];
    captionLabel.text = caption;
    captionLabel.font = [ZL2Theme fontLabelMedium];
    captionLabel.textColor = [ZL2Theme onSurfaceVariant];
    captionLabel.numberOfLines = 1;
    captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [captionLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [captionLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.alwaysBounceHorizontal = YES;

    UIStackView *chipStack = [[UIStackView alloc] init];
    chipStack.axis = UILayoutConstraintAxisHorizontal;
    chipStack.spacing = 6;
    chipStack.alignment = UIStackViewAlignmentCenter;
    chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:chipStack];

    [NSLayoutConstraint activateConstraints:@[
        [chipStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [chipStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [chipStack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [chipStack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [chipStack.heightAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor],
        [captionLabel.widthAnchor constraintEqualToConstant:44],
    ]];

    if (chipStackOut) *chipStackOut = chipStack;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[captionLabel, scrollView]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:40].active = YES;
    return row;
}

// 追加一枚 ZL2M3FilterChip（identifier/tag 载荷 = 值；ZL2 红线「chip.tag 仅作
// 下标载荷」口径——值载荷走 accessibilityIdentifier，下标载荷走 tag）
- (ZL2M3FilterChip *)ame_addChip:(NSString *)title selected:(BOOL)selected
                        toStack:(UIStackView *)stack
                     identifier:(NSString *)identifier
                            tag:(NSInteger)tag {
    ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:title];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.accessibilityIdentifier = identifier;
    chip.tag = tag;
    chip.selected = selected;
    [chip addTarget:self action:@selector(ame_chipTapped:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:chip];
    return chip;
}

// chips 点击统一入口（按 payload 分流：tag = 来源档；identifier = 排序键；
// 其余按 title 文本 = 版本/加载器值——旧页四个 chip 回调合并形态）
- (void)ame_chipTapped:(ZL2M3FilterChip *)chip {
    if (chip.superview == self.sourceChipStack) {
        [self ame_sourceChipTapped:chip];
        return;
    }
    if (chip.superview == self.sortChipStack) {
        [self ame_sortChipTapped:chip];
        return;
    }
    if (chip.superview == self.versionChipStack) {
        [self ame_valueChipTapped:chip inStack:self.versionChipStack key:&_selectedGameVersion];
        return;
    }
    if (chip.superview == self.loaderChipStack) {
        [self ame_valueChipTapped:chip inStack:self.loaderChipStack key:&_selectedLoader];
        return;
    }
}

#pragma mark - chips 重建与点击（旧页 rebuild*/ChipTapped 同构 ZL2 化）

- (void)ame_rebuildSourceChips {
    [self.sourceChipStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self ame_addChip:@"Modrinth" selected:(self.selectedSource == ZL2VListSourceModrinth)
             toStack:self.sourceChipStack identifier:nil tag:ZL2VListSourceModrinth];
    [self ame_addChip:@"CurseForge" selected:(self.selectedSource == ZL2VListSourceCurseForge)
             toStack:self.sourceChipStack identifier:nil tag:ZL2VListSourceCurseForge];
}

- (void)ame_rebuildVersionChips {
    [self.versionChipStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    if (self.availableGameVersions.count == 0) {
        [self ame_addChip:localize(@"i18n_str_463", nil) selected:NO toStack:self.versionChipStack identifier:nil tag:0];
        return;
    }
    for (NSString *version in self.availableGameVersions) {
        [self ame_addChip:version
                 selected:[self.selectedGameVersion isEqualToString:version]
                 toStack:self.versionChipStack identifier:nil tag:0];
    }
}

- (void)ame_rebuildLoaderChips {
    [self.loaderChipStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    if (self.availableLoaders.count == 0) {
        [self ame_addChip:localize(@"i18n_str_464", nil) selected:NO toStack:self.loaderChipStack identifier:nil tag:0];
        return;
    }
    for (NSString *loader in self.availableLoaders) {
        [self ame_addChip:loader
                 selected:[self.selectedLoader isEqualToString:loader]
                 toStack:self.loaderChipStack identifier:nil tag:0];
    }
}

- (void)ame_rebuildSortChips {
    [self.sortChipStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    for (NSDictionary *item in ZL2VListSortOptionItems()) {
        NSString *key = item[@"key"];
        [self ame_addChip:item[@"title"]
                 selected:[self.selectedSort isEqualToString:key]
                 toStack:self.sortChipStack identifier:key tag:0];
    }
}

// 来源 chip：切源重拉（CurseForge 源门控 = Task162 口径：key 仅官方直连需要，
// 无 key 时镜像可用——旧页 isSourceAvailable 门控 1:1）
- (void)ame_sourceChipTapped:(ZL2M3FilterChip *)chip {
    NSInteger newSource = chip.tag;
    if (newSource != ZL2VListSourceModrinth && newSource != ZL2VListSourceCurseForge) return;
    if (newSource == self.selectedSource) return;
    if (newSource == ZL2VListSourceCurseForge && ![CurseForgeAPI isSourceAvailable]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_465", nil)
                                                                       message:localize(@"i18n_str_466", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                                  style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.selectedSource = newSource;
    [self ame_rebuildSourceChips];
    self.allVersions = nil;
    self.filteredVersions = nil;
    [self.tableView reloadData];
    [self ame_fetchVersionsFromCurrentSource];
}

// 排序 chip（identifier 载荷 = 排序键；旧页 sortChipTapped 同语义）
- (void)ame_sortChipTapped:(ZL2M3FilterChip *)chip {
    NSString *key = chip.accessibilityIdentifier;
    if (key.length == 0 || [key isEqualToString:self.selectedSort]) return;
    self.selectedSort = key;
    for (UIView *sub in self.sortChipStack.arrangedSubviews) {
        if (![sub isKindOfClass:[ZL2M3FilterChip class]]) continue;
        ((ZL2M3FilterChip *)sub).selected = [sub.accessibilityIdentifier isEqualToString:key];
    }
    [self ame_applyFiltersAndSort];
}

// 版本/加载器 chip（accessibilityLabel 载荷 = 值——ZL2M3FilterChip 构造时把
// 文本同步进 accessibilityLabel，比对免翻内部子视图；key 出参指回对应状态
// 属性——两行逻辑同构合并，避免旧页 versionChipTapped/loaderChipTapped 双份复制）
- (void)ame_valueChipTapped:(ZL2M3FilterChip *)chip
                    inStack:(UIStackView *)stack
                        key:(NSString **)key {
    NSString *value = chip.accessibilityLabel ?: @"";
    if (value.length == 0 || [value isEqualToString:*key]) return;
    *key = value;
    for (UIView *sub in stack.arrangedSubviews) {
        if (![sub isKindOfClass:[ZL2M3FilterChip class]]) continue;
        ((ZL2M3FilterChip *)sub).selected = [sub.accessibilityLabel isEqualToString:value];
    }
    [self ame_applyFiltersAndSort];
}

#pragma mark - 数据拉取（旧页 fetchVersionsFromCurrentSource 链 1:1 移植）

- (void)ame_fetchVersionsFromCurrentSource {
    [self.loadingIndicator startAnimating];

    NSString *fetchID = self.projectID;
    if (fetchID.length == 0 && self.modItem) fetchID = self.modItem.onlineID;
    if (fetchID.length == 0 && self.shaderItem) fetchID = self.shaderItem.onlineID;
    fetchID = fetchID ?: @"";

    // ★Task436：跨源解析仅 Mod 域（旧页 Task247 域限定 1:1——Shader/Asset 域
    // 旧页本就直拉；Modrinth 光影旧走 getVersionsForShaderWithID: 同端点同
    // 解析，统一 getVersionsForModWithID: + ModVersion 承载，登记口径）
    if (self.domainType != ZL2VersionListDomainMod) {
        [self ame_fetchVersionsWithID:fetchID];
        return;
    }

    NSString *projectName = self.modItem.displayName ?: (self.pageTitle ?: @"");
    BOOL numeric = (fetchID.length > 0 &&
        [fetchID rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound);
    // CF 源要数字 id；Modrinth 源要 slug/项目码（非全数字）
    BOOL needResolve = (self.selectedSource == ZL2VListSourceCurseForge) ? !numeric : numeric;
    if (!needResolve) {
        [self ame_fetchVersionsWithID:fetchID];
        return;
    }
    // 会话级解析缓存命中：切过去再切回来不重复搜索（旧页 ame247 口径）
    NSString *cached = self.resolvedIDs[@(self.selectedSource)];
    if (cached.length > 0) {
        [self ame_fetchVersionsWithID:cached];
        return;
    }
    [self ame_resolveCrossSourceCounterpartWithID:fetchID projectName:projectName];
}

// Task247（T11）1:1 移植：以项目名搜索对端源解析项目 id；displayName 去空格
// 完全等值（忽略大小写）优先 → 首个结果兜底；解析结果入缓存。
- (void)ame_resolveCrossSourceCounterpartWithID:(NSString *)originID
                                    projectName:(NSString *)projectName {
    NSString *query = projectName ?: @"";
    NSString *normalized = [query stringByReplacingOccurrencesOfString:@" " withString:@""].lowercaseString;
    __weak typeof(self) weakSelf = self;
    void (^finish)(NSString * _Nullable) = ^(NSString * _Nullable resolved) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (resolved.length > 0) {
                strongSelf.resolvedIDs[@(strongSelf.selectedSource)] = resolved;
                NSLog(@"[ZL2VersionListPage] Task436 Task247: cross-source id resolved (source=%ld): %@",
                      (long)strongSelf.selectedSource, resolved);
                [strongSelf ame_fetchVersionsWithID:resolved];
            } else {
                NSLog(@"[ZL2VersionListPage] Task436 Task247: cross-source id unresolved (source=%ld) -- empty fallback",
                      (long)strongSelf.selectedSource);
                [strongSelf ame_handleVersionsResponse:@[] error:nil];
            }
        });
    };
    void (^pick)(NSArray * _Nullable, NSError * _Nullable) = ^(NSArray * _Nullable results, NSError * _Nullable error) {
        if (error != nil || results.count == 0) {
            finish(nil);
            return;
        }
        // 异步搜索返回字典数组（Task248 判例同款：双形态兼容——字典读 id/title
        // 键，ModItem 对象保留防御）
        NSString *best = nil;
        for (id entry in results) {
            NSString *pid = nil;
            NSString *pname = nil;
            if ([entry isKindOfClass:[NSDictionary class]]) {
                id rawID = [(NSDictionary *)entry objectForKey:@"id"];
                pid = [rawID isKindOfClass:[NSString class]] ? rawID
                    : ([rawID isKindOfClass:[NSNumber class]] ? [(NSNumber *)rawID stringValue] : nil);
                pname = [(NSDictionary *)entry objectForKey:@"title"];
            } else if ([entry isKindOfClass:[ModItem class]]) {
                pid = [(ModItem *)entry onlineID];
                pname = [(ModItem *)entry displayName];
            }
            if (pid.length == 0) continue;
            NSString *dn = (pname ?: @"").lowercaseString;
            NSString *dsq = [dn stringByReplacingOccurrencesOfString:@" " withString:@""];
            if ([dsq isEqualToString:normalized]) {
                best = pid;
                break;
            }
            if (best == nil) best = pid;   // 兜底取首个
        }
        finish(best);
    };
    NSDictionary *filters = @{
        @"name": query,
        @"projectType": @"mod",
        @"limit": @20,
    };
    NSLog(@"[ZL2VersionListPage] Task436 Task247: resolving cross-source id (source=%ld) via search: %@",
          (long)self.selectedSource, query);
    if (self.selectedSource == ZL2VListSourceCurseForge) {
        [[CurseForgeAPI sharedInstance] searchModWithFilters:filters completion:pick];
    } else {
        [[ModrinthAPI sharedInstance] searchModWithFilters:filters completion:pick];
    }
}

- (void)ame_fetchVersionsWithID:(NSString *)fetchID {
    __weak typeof(self) weakSelf = self;
    void (^onDone)(NSArray<ModVersion *> * _Nullable, NSError * _Nullable) = ^(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf ame_handleVersionsResponse:versions error:error];
        });
    };
    if (self.selectedSource == ZL2VListSourceCurseForge) {
        [[CurseForgeAPI sharedInstance] getVersionsForModWithID:fetchID completion:onDone];
    } else {
        [[ModrinthAPI sharedInstance] getVersionsForModWithID:fetchID completion:onDone];
    }
}

// 统一版本回调（旧页 handleVersionsResponse 等价移植；alert 反馈面换
// InlineMessageView + ZL2 空态卡——文件头对表登记）
- (void)ame_handleVersionsResponse:(NSArray<ModVersion *> *)versions error:(NSError *)error {
    [self.loadingIndicator stopAnimating];
    if (error) {
        NSLog(@"[ZL2VersionListPage] Error fetching versions (source=%ld): %@",
              (long)self.selectedSource, error);
        [InlineMessageView showInViewController:self
                                          title:localize(@"i18n_str_42", nil)
                                        message:localize(@"i18n_str_467", nil)
                                           type:InlineMessageTypeError];
        return;
    }
    if (!versions || versions.count == 0) {
        [self ame_showEmptyState];
        return;
    }
    self.allVersions = versions;
    [self ame_processFilters];
    [self ame_applyFiltersAndSort];
}

#pragma mark - 筛选 + 排序（旧页 processFilters/applyFiltersAndSort/sortVersions 1:1）

- (void)ame_processFilters {
    NSMutableSet<NSString *> *gameVersions = [NSMutableSet setWithObject:localize(@"ame193.misc.1", @"全部")];
    NSMutableSet<NSString *> *loaders = [NSMutableSet setWithObject:localize(@"ame193.misc.1", @"全部")];

    for (ModVersion *version in self.allVersions) {
        for (NSString *gameVersion in version.gameVersions) {
            [gameVersions addObject:gameVersion];
        }
        for (NSString *loader in version.loaders) {
            [loaders addObject:[loader capitalizedString]];   // 首字母大写用于显示（旧页口径）
        }
    }

    // 游戏版本按语义版本号降序（新的在前），"全部"恒在最前；加载器按字母序
    self.availableGameVersions = [[gameVersions allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSString *all = localize(@"ame193.misc.1", @"全部");
        if ([obj1 isEqualToString:all]) return NSOrderedAscending;
        if ([obj2 isEqualToString:all]) return NSOrderedDescending;
        return [obj2 compare:obj1 options:NSNumericSearch];
    }];
    self.availableLoaders = [[loaders allObjects] sortedArrayUsingSelector:@selector(compare:)];

    // 默认"全部"；preferred 在可选列表中时自动选中（大小写不敏感，旧页口径）
    self.selectedGameVersion = self.availableGameVersions.firstObject ?: localize(@"ame193.misc.1", @"全部");
    self.selectedLoader = self.availableLoaders.firstObject ?: localize(@"ame193.misc.1", @"全部");
    if (self.preferredGameVersion.length > 0) {
        for (NSString *gv in self.availableGameVersions) {
            if ([gv caseInsensitiveCompare:self.preferredGameVersion] == NSOrderedSame) {
                self.selectedGameVersion = gv;
                break;
            }
        }
    }
    if (self.preferredLoader.length > 0) {
        NSString *preferredCapitalized = self.preferredLoader.capitalizedString;
        for (NSString *ld in self.availableLoaders) {
            if ([ld caseInsensitiveCompare:preferredCapitalized] == NSOrderedSame) {
                self.selectedLoader = ld;
                break;
            }
        }
    }

    [self ame_rebuildVersionChips];
    [self ame_rebuildLoaderChips];
}

- (void)ame_applyFiltersAndSort {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ModVersion *evaluatedObject, NSDictionary *bindings) {
        NSString *all = localize(@"ame193.misc.1", @"全部");
        BOOL gameVersionMatch = [self.selectedGameVersion isEqualToString:all] ||
                                 [evaluatedObject.gameVersions containsObject:self.selectedGameVersion];
        BOOL loaderMatch = [self.selectedLoader isEqualToString:all] ||
                            [evaluatedObject.loaders containsObject:self.selectedLoader.lowercaseString];
        return gameVersionMatch && loaderMatch;
    }];
    NSArray<ModVersion *> *filtered = [self.allVersions filteredArrayUsingPredicate:predicate];
    NSArray<ModVersion *> *sorted = [self ame_sortVersions:filtered];

    // FCL 风格：preferred 版本+加载器双匹配置顶（旧页同口径：用户从 profile
    // 进入版本列表时自动把完全匹配的版本置顶）
    if (self.preferredGameVersion.length > 0 || self.preferredLoader.length > 0) {
        NSMutableArray<ModVersion *> *pinned = [NSMutableArray array];
        NSMutableArray<ModVersion *> *rest = [NSMutableArray array];
        for (ModVersion *v in sorted) {
            BOOL versionMatch = (self.preferredGameVersion.length == 0) ||
                                [v.gameVersions containsObject:self.preferredGameVersion];
            BOOL loaderMatch = (self.preferredLoader.length == 0) ||
                               [v.loaders containsObject:self.preferredLoader.lowercaseString];
            if (versionMatch && loaderMatch) {
                [pinned addObject:v];
            } else {
                [rest addObject:v];
            }
        }
        if (pinned.count > 0 && pinned.count < sorted.count) {
            sorted = [pinned arrayByAddingObjectsFromArray:rest];
        }
    }

    self.filteredVersions = sorted;
    [self.tableView reloadData];
    [self ame_refreshEmptyState];
}

// 排序四档（旧页 sortVersions 1:1：相关度/下载量保持 API 原序——版本级无
// 下载量字段；最新更新 = datePublished 降序 / 创建时间 = 升序）
- (NSArray<ModVersion *> *)ame_sortVersions:(NSArray<ModVersion *> *)versions {
    if (!versions || versions.count <= 1) return versions;
    if ([self.selectedSort isEqualToString:ZL2VListSortRelevance] ||
        [self.selectedSort isEqualToString:ZL2VListSortDownloads]) {
        return versions;
    }
    NSISO8601DateFormatter *dateFormatter = [[NSISO8601DateFormatter alloc] init];
    NSMutableArray<ModVersion *> *sorted = [versions mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(ModVersion *v1, ModVersion *v2) {
        NSDate *d1 = [dateFormatter dateFromString:v1.datePublished];
        NSDate *d2 = [dateFormatter dateFromString:v2.datePublished];
        if (!d1) d1 = [NSDate distantPast];
        if (!d2) d2 = [NSDate distantPast];
        if ([self.selectedSort isEqualToString:ZL2VListSortUpdated]) {
            return [d2 compare:d1];
        } else if ([self.selectedSort isEqualToString:ZL2VListSortCreated]) {
            return [d1 compare:d2];
        }
        return NSOrderedSame;
    }];
    return [sorted copy];
}

#pragma mark - 空态 / 加载 / 错误

- (void)ame_showEmptyState {
    UIImage *icon = [UIImage systemImageNamed:@"square.stack"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:68]];
    if (!icon) icon = ZL2VListSystemImage(@"square.stack", @"list.bullet");
    self.emptyIconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.emptyLabel.text = localize(@"ame436.vlist.empty", @"暂无可下载版本");
    self.emptyContainer.hidden = NO;
}

- (void)ame_refreshEmptyState {
    self.emptyContainer.hidden = (self.filteredVersions.count > 0);
}

#pragma mark - UITableView DataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.filteredVersions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZL2VersionRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2VersionRowCell"
                                                             forIndexPath:indexPath];
    if (indexPath.row < (NSInteger)self.filteredVersions.count) {
        [cell ame_configureWithVersion:self.filteredVersions[indexPath.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.filteredVersions.count) return;
    ModVersion *selectedVersion = self.filteredVersions[indexPath.row];
    // 旧页同序：先 delegate（父页回调内 pop 起转场）→ 本页 pop 兜底
    // （转场期 UINavigationController 忽略二次 pop，双 pop 不成立）
    if ([self.delegate respondsToSelector:@selector(zl2VersionListPage:didSelectVersion:)]) {
        [self.delegate zl2VersionListPage:self didSelectVersion:selectedVersion];
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - 收藏胶囊（★Task436：旧页 Task428/429 口径，ZL2FavoritesStore 直连）

- (void)ame_favoriteTapped {
    NSString *pid = [self ame_projectIDForSnapshot];
    if (pid.length == 0) return;
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"platform"] = @([self ame_platformForSnapshot]);
    snapshot[@"projectId"] = pid;
    snapshot[@"title"] = [self ame_headerTitleValue] ?: @"";
    snapshot[@"description"] = [self ame_headerDescriptionValue] ?: @"";
    snapshot[@"imageUrl"] = [self ame_headerIconValue] ?: @"";
    snapshot[@"author"] = [self ame_headerAuthorValue] ?: @"";
    snapshot[@"downloads"] = [self ame_headerDownloadsValue] ?: @0;
    snapshot[@"projectType"] = [self ame_projectTypeForSnapshot];
    [[ZL2FavoritesStore sharedStore] toggleFavoriteWithProject:snapshot];
    [self ame_refreshFavoriteState];
}

- (void)ame_refreshFavoriteState {
    if (!self.favoriteCapsule) return;
    NSString *pid = [self ame_projectIDForSnapshot];
    // 旧页同口径：无平台侧项目 id（本地防御位）整钮隐藏——无从收藏
    self.favoriteCapsule.hidden = (pid.length == 0);
    if (pid.length == 0) return;
    BOOL fav = [[ZL2FavoritesStore sharedStore] isFavoritePlatform:[self ame_platformForSnapshot] projectId:pid];
    UIImage *heart = [UIImage systemImageNamed:(fav ? @"heart.fill" : @"heart")];
    self.favoriteHeartIcon.image = [heart imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.favoriteHeartIcon.tintColor = fav ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    self.favoriteLabel.text = localize(@"ame369.common.favorites", @"收藏");
    self.favoriteLabel.textColor = fav ? [ZL2Theme tertiary] : [ZL2Theme onSurface];
    self.favoriteCapsule.accessibilityLabel = fav
        ? localize(@"ame369.asearch.unfavorite", @"取消收藏")
        : localize(@"ame369.common.favorites", @"收藏");
}

@end
