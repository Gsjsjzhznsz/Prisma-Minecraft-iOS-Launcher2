//
// ZL2SearchIdViewController.m — ZL2 按项目 ID 直查页（结构契约见 .h）
//
// ★Task432 实锤三（查询→下载闭环）：结果卡补「前往下载」/ 截图卡 /
//   mcmod 中文资料卡三段（语义基准 zl2-ref SearchIdScreen.kt ResultLayout：
//   ResultProjectLayout onClick→onView→swapToDownload + urls 卡含 mcmod +
//   screenshots items）。路由形态：
//   · 前往下载 = 找宿主 ZL2DownloadViewController → ame_showCategory: 切轨 →
//     轨内 ZL2AssetSearchViewController 打开本项目版本页（delegate = 轨页，
//     pending* 状态经文件尾自含声明类目回填，分支构造与 ame_openResultAtIndex:
//     1:1 对表——安装/依赖解析/整合包导入全链零重复）。
//   · 轨桥接私有成员经「运行期合成访问器」消费（消费方 TU 自含声明判例：
//     类扩展 property 的 getter/setter 在主实现 TU 编译期合成，本 TU 声明
//     同名 property 走 objc_msgSend 运行期命中；选择器逐一对应勿漂移）。
//

#import "ZL2SearchIdViewController.h"
#import "utils.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2FavoritesStore.h"
// ★Task432 实锤三：下载轨桥接（真头均轻量无重链——ModItem/WorldItem 等
//   纯模型头、三版本页头仅依赖模型头；预览 TU 由 ZL2PagesStub 桩同名类
//   自洽，正式构建由真实 .m 提供类符号，双构建自洽）
#import "ZL2DownloadViewController.h"
#import "ZL2AssetSearchViewController.h"   // ZL2AssetSearchType 枚举
#import "ModItem.h"
#import "ShaderItem.h"
#import "ResourcePackItem.h"
#import "WorldItem.h"
#import "ModVersionViewController.h"
#import "ShaderVersionViewController.h"
#import "AssetVersionViewController.h"

#include <stdlib.h>

#pragma mark - API 双源本地最小类声明（7.0-UI-10-f import 手术判例同款：
#pragma mark 真实头依赖链在预览 TU 会与桩实现撞符号，消费方 TU 自含声明，
#pragma mark 选择器一一对应；主构建由桩/真实实现按链接目标自洽）

@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
@end

#pragma mark - ★Task432 下载轨桥接自含声明（方法/访问器运行期命中真实实现）

// 轨搜索页私有面：pending* = 版本页回填状态（类扩展合成访问器，运行期命中）；
// assetType 只读（构造注入后只读）；ame_profile* = 轨内偏好快照（旧页语义）
@interface ZL2AssetSearchViewController (Task432SearchIdBridge)
    <ModVersionViewControllerDelegate, ShaderVersionViewControllerDelegate,
     AssetVersionViewControllerDelegate>
@property (nonatomic, copy, nullable) NSString *pendingDownloadType;
@property (nonatomic, strong, nullable) NSDictionary *pendingModpackDict;
@property (nonatomic, strong, nullable) ResourcePackItem *pendingResourcePackItem;
@property (nonatomic, strong, nullable) WorldItem *pendingWorldItem;
@property (nonatomic, assign, readonly) ZL2AssetSearchType assetType;
// ★Task432：收藏轨占位资产类型防串——initWithFavorites 置 assetType=Mod 仅占位
//   （ZL2AssetSearchViewController.m initWithFavorites：“占位（收藏模式按项内
//   projectType 分流）”），轨定位时须跳过，防收藏轨先入缓存后冒充模组轨
@property (nonatomic, assign, readonly) BOOL favoritesMode;
- (NSString *)ame_profileMinecraftVersion;
- (NSString *)ame_profileLoader;
@end

// 下载壳私有面：切轨入口（SearchId = 壳 case 6 子页；ZL2 swapToCategoryAddon
// 的 navigateToDownload(downloadModScreen) 语义对应物）
@interface ZL2DownloadViewController (Task432SearchIdShell)
- (void)ame_showCategory:(NSInteger)index;
@end

// SF Symbols 取图兜底（符号名异常时降级旧名；ZL2Download 同款 helper）
static UIImage *ZL2SIDSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

@interface ZL2SearchIdViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *idField;
@property (nonatomic, strong) NSMutableArray<UIControl *> *platformChips;
@property (nonatomic, strong) NSMutableArray<UILabel *> *platformChipLabels;
@property (nonatomic, assign) NSInteger platform;   // 1 = Modrinth / 2 = CurseForge
@property (nonatomic, strong) UIControl *searchButton;

@property (nonatomic, strong) UIView *resultCard;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *downloadsLabel;
@property (nonatomic, strong) UILabel *categoriesLabel;
@property (nonatomic, strong) UIControl *favoriteButton;
@property (nonatomic, strong) UILabel *favoriteLabel;
@property (nonatomic, strong) UIControl *openLinkButton;

// ★Task432 实锤三：结果卡三段增量（动作列 = 截图卡 + 前往下载 + 浏览器 + mcmod）
@property (nonatomic, strong) UIStackView *actionStack;        // 结果卡尾段纵排列
@property (nonatomic, strong) UILabel *galleryHeader;          // 截图小节标题
@property (nonatomic, strong) UIScrollView *galleryScroll;     // 截图横滑
@property (nonatomic, strong) UIStackView *galleryRowStack;    // 截图缩略图行
@property (nonatomic, strong) UIControl *goDownloadButton;     // 前往下载（primary 实底）
@property (nonatomic, strong) UILabel *goDownloadLabel;
@property (nonatomic, strong) UIControl *mcmodButton;          // mcmod 中文资料外链卡
@property (nonatomic, strong) UILabel *mcmodLabel;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong, nullable) NSDictionary *fetchedProject;
@property (nonatomic, strong, nullable) NSDictionary *fetchedRaw;   // ★Task432：原始响应（轨路由 + gallery 消费）
@end

@implementation ZL2SearchIdViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    _platform = 1;
    [self ame_buildViews];
}

#pragma mark - 布局

- (void)ame_buildViews {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    _idField = [[UITextField alloc] init];
    _idField.placeholder = localize(@"ame369.sid.id_placeholder", @"项目 ID / 别名（slug）");
    _idField.font = [ZL2Theme fontBodyMedium];
    _idField.textColor = [ZL2Theme onSurface];
    _idField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:localize(@"ame369.sid.id_placeholder", @"项目 ID / 别名（slug）")
                                        attributes:@{NSForegroundColorAttributeName: [ZL2Theme onSurfaceVariant]}];
    _idField.backgroundColor = [ZL2Theme surfaceContainer];
    _idField.layer.cornerRadius = [ZL2Theme radiusS];
    _idField.delegate = self;
    _idField.returnKeyType = UIReturnKeySearch;
    _idField.autocorrectionType = UITextAutocorrectionTypeNo;
    _idField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _idField.leftView = leftPad;
    _idField.leftViewMode = UITextFieldViewModeAlways;
    _idField.translatesAutoresizingMaskIntoConstraints = NO;
    _idField.isAccessibilityElement = YES;
    _idField.accessibilityLabel = localize(@"ame369.sid.id_a11y", @"项目 ID 输入");
    [self.view addSubview:_idField];

    // 平台 chips（ZL2 PlatformListLayout 语义：Modrinth / CurseForge 单选）
    _platformChips = [NSMutableArray array];
    _platformChipLabels = [NSMutableArray array];
    UIStackView *chips = [[UIStackView alloc] init];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 8;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:chips];
    NSArray<NSString *> *platforms = @[@"Modrinth", @"CurseForge"];
    [platforms enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
        UIControl *chip = [[UIControl alloc] init];
        chip.backgroundColor = [ZL2Theme surfaceContainer];
        chip.layer.cornerRadius = [ZL2Theme radiusS];
        chip.layer.borderWidth = 1.0;
        chip.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.isAccessibilityElement = YES;
        chip.accessibilityLabel = name;
        [chip addTarget:self
                 action:@selector(ame_platformTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        chip.tag = (NSInteger)(idx + 1);
        UILabel *label = [[UILabel alloc] init];
        label.text = name;
        label.font = [ZL2Theme fontLabelMedium];
        label.textColor = [ZL2Theme onSurfaceVariant];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.userInteractionEnabled = NO;
        [chip addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:chip.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:chip.leadingAnchor constant:12],
            [chip.trailingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
            [chip.heightAnchor constraintEqualToConstant:32],
        ]];
        [chips addArrangedSubview:chip];
        [_platformChips addObject:chip];
        [_platformChipLabels addObject:label];
    }];

    _searchButton = [[UIControl alloc] init];
    _searchButton.backgroundColor = [ZL2Theme primary];
    _searchButton.layer.cornerRadius = [ZL2Theme radiusS];
    _searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    _searchButton.isAccessibilityElement = YES;
    _searchButton.accessibilityLabel = localize(@"ame369.sid.lookup", @"查询");
    [_searchButton addTarget:self
                      action:@selector(ame_searchTapped)
            forControlEvents:UIControlEventTouchUpInside];
    UILabel *searchLabel = [[UILabel alloc] init];
    searchLabel.text = localize(@"ame369.sid.lookup", @"查询");
    searchLabel.font = [ZL2Theme fontLabelLarge];
    searchLabel.textColor = [ZL2Theme onPrimary];
    searchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    searchLabel.userInteractionEnabled = NO;
    [_searchButton addSubview:searchLabel];
    [self.view addSubview:_searchButton];

    // 结果卡（ZL2 ResultProjectLayout 简化：图标 + 标题/作者 + 描述 + 统计 + 标签）
    _resultCard = [[UIView alloc] init];
    _resultCard.backgroundColor = [ZL2Theme surfaceBright];
    _resultCard.layer.cornerRadius = [ZL2Theme radiusL];
    _resultCard.translatesAutoresizingMaskIntoConstraints = NO;
    _resultCard.hidden = YES;
    [self.view addSubview:_resultCard];

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.layer.cornerRadius = [ZL2Theme radiusS];
    _iconView.clipsToBounds = YES;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_titleLabel];

    _authorLabel = [[UILabel alloc] init];
    _authorLabel.font = [ZL2Theme fontLabelMedium];
    _authorLabel.textColor = [ZL2Theme onSurfaceVariant];
    _authorLabel.numberOfLines = 1;
    _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_authorLabel];

    _descLabel = [[UILabel alloc] init];
    _descLabel.font = [ZL2Theme fontBodyMedium];
    _descLabel.textColor = [ZL2Theme onSurfaceVariant];
    _descLabel.numberOfLines = 2;
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_descLabel];

    _downloadsLabel = [[UILabel alloc] init];
    _downloadsLabel.font = [ZL2Theme fontLabelMedium];
    _downloadsLabel.textColor = [ZL2Theme onSurfaceVariant];
    _downloadsLabel.numberOfLines = 1;
    _downloadsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_downloadsLabel];

    _categoriesLabel = [[UILabel alloc] init];
    _categoriesLabel.font = [ZL2Theme fontLabelMedium];
    _categoriesLabel.textColor = [ZL2Theme onSurfaceVariant];
    _categoriesLabel.numberOfLines = 1;
    _categoriesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_categoriesLabel];

    _favoriteButton = [[UIControl alloc] init];
    _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteButton.isAccessibilityElement = YES;
    _favoriteButton.accessibilityLabel = localize(@"ame369.common.favorites", @"收藏");
    // ★Task429：收藏钮加大（用户复诉“收藏按钮太小了”）——命中面升级见布局段
    //   （高 44/宽 ≥64，HIG 最小命中面）；label 装配见下方 ★Task429 注释块
    [_favoriteButton addTarget:self
                        action:@selector(ame_favoriteTapped)
              forControlEvents:UIControlEventTouchUpInside];
    UIImageView *heartIcon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"heart"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    heartIcon.tintColor = [ZL2Theme onSurfaceVariant];
    heartIcon.contentMode = UIViewContentModeScaleAspectFit;
    heartIcon.translatesAutoresizingMaskIntoConstraints = NO;
    heartIcon.userInteractionEnabled = NO;
    heartIcon.tag = 101;
    [_favoriteButton addSubview:heartIcon];

    // ★Task429：收藏钮加大——用户复诉“收藏按钮太小了”+ZL2 口径：此前本页
    //   favoriteLabel 只有声明无装配（纯图标小钮）；现按 ZL2AssetSearch 卡
    //   FavoriteToggleLabel 基准装配为“心形+文字”胶囊钮（label 用既有字体阶
    //   fontLabelLarge，文案复用既有键 ame369.common.favorites，无新增 i18n）
    _favoriteLabel = [[UILabel alloc] init];
    _favoriteLabel.text = localize(@"ame369.common.favorites", @"收藏");
    _favoriteLabel.font = [ZL2Theme fontLabelLarge];
    _favoriteLabel.textColor = [ZL2Theme onSurfaceVariant];
    _favoriteLabel.numberOfLines = 1;
    _favoriteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteLabel.userInteractionEnabled = NO;
    [_favoriteButton addSubview:_favoriteLabel];
    [_resultCard addSubview:_favoriteButton];

    _openLinkButton = [[UIControl alloc] init];
    _openLinkButton.backgroundColor = [ZL2Theme surfaceContainer];
    _openLinkButton.layer.cornerRadius = [ZL2Theme radiusS];
    _openLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    _openLinkButton.isAccessibilityElement = YES;
    _openLinkButton.accessibilityLabel = localize(@"ame369.sid.open_in_browser", @"在浏览器打开");
    [_openLinkButton addTarget:self
                        action:@selector(ame_openLinkTapped)
              forControlEvents:UIControlEventTouchUpInside];
    UILabel *linkLabel = [[UILabel alloc] init];
    linkLabel.text = localize(@"ame369.sid.open_project_page", @"在浏览器打开项目页");
    linkLabel.font = [ZL2Theme fontLabelLarge];
    linkLabel.textColor = [ZL2Theme primary];
    linkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    linkLabel.userInteractionEnabled = NO;
    [_openLinkButton addSubview:linkLabel];
    [_resultCard addSubview:_openLinkButton];

    // ★Task432 实锤三：结果卡尾段动作列（ZL2 ResultLayout 纵排语义）：
    //   截图卡（Modrinth gallery）→「前往下载」→ 浏览器外链 → mcmod 中文资料卡
    _galleryHeader = [[UILabel alloc] init];
    _galleryHeader.text = localize(@"ame432.searchid.gallery", @"截图");
    _galleryHeader.font = [ZL2Theme fontTitleMedium];
    _galleryHeader.textColor = [ZL2Theme onSurface];
    _galleryHeader.numberOfLines = 1;
    _galleryHeader.translatesAutoresizingMaskIntoConstraints = NO;
    _galleryHeader.hidden = YES;

    _galleryScroll = [[UIScrollView alloc] init];
    _galleryScroll.showsHorizontalScrollIndicator = NO;
    _galleryScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _galleryScroll.hidden = YES;

    _galleryRowStack = [[UIStackView alloc] init];
    _galleryRowStack.axis = UILayoutConstraintAxisHorizontal;
    _galleryRowStack.alignment = UIStackViewAlignmentCenter;
    _galleryRowStack.spacing = 8;
    _galleryRowStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_galleryScroll addSubview:_galleryRowStack];
    [NSLayoutConstraint activateConstraints:@[
        [_galleryRowStack.topAnchor constraintEqualToAnchor:_galleryScroll.topAnchor],
        [_galleryRowStack.bottomAnchor constraintEqualToAnchor:_galleryScroll.bottomAnchor],
        [_galleryRowStack.leadingAnchor constraintEqualToAnchor:_galleryScroll.contentLayoutGuide.leadingAnchor],
        [_galleryRowStack.trailingAnchor constraintEqualToAnchor:_galleryScroll.contentLayoutGuide.trailingAnchor],
        [_galleryRowStack.heightAnchor constraintEqualToAnchor:_galleryScroll.heightAnchor],
    ]];

    _goDownloadButton = [[UIControl alloc] init];
    _goDownloadButton.backgroundColor = [ZL2Theme primary];
    _goDownloadButton.layer.cornerRadius = [ZL2Theme radiusS];
    _goDownloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    _goDownloadButton.isAccessibilityElement = YES;
    _goDownloadButton.accessibilityLabel = localize(@"ame432.searchid.go_download", @"前往下载");
    // ★Task432：无对应轨的类型不给按钮（诚实边界）——hidden 由查询结果
    //   projectType/classId 映射动态置位，默认隐藏
    _goDownloadButton.hidden = YES;
    [_goDownloadButton addTarget:self
                          action:@selector(ame_goDownloadTapped)
                forControlEvents:UIControlEventTouchUpInside];
    _goDownloadLabel = [[UILabel alloc] init];
    _goDownloadLabel.text = localize(@"ame432.searchid.go_download", @"前往下载");
    _goDownloadLabel.font = [ZL2Theme fontLabelLarge];
    _goDownloadLabel.textColor = [ZL2Theme onPrimary];
    _goDownloadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _goDownloadLabel.userInteractionEnabled = NO;
    [_goDownloadButton addSubview:_goDownloadLabel];

    // mcmod 中文资料外链卡（search.mcmod.cn/s?key=<项目名>；不虚构 API，
    // 纯搜索页外链 = ZL2 ProjectUrlsContent mcmod 项的诚实等价物）
    _mcmodButton = [[UIControl alloc] init];
    _mcmodButton.backgroundColor = [ZL2Theme surfaceContainer];
    _mcmodButton.layer.cornerRadius = [ZL2Theme radiusS];
    _mcmodButton.translatesAutoresizingMaskIntoConstraints = NO;
    _mcmodButton.isAccessibilityElement = YES;
    _mcmodButton.accessibilityLabel = localize(@"ame432.searchid.mcmod", @"mcmod 中文资料搜索");
    [_mcmodButton addTarget:self
                     action:@selector(ame_mcmodTapped)
           forControlEvents:UIControlEventTouchUpInside];

    UIImageView *mcmodIcon = [[UIImageView alloc] initWithImage:
        [ZL2SIDSystemImage(@"book", @"doc.text") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    mcmodIcon.tintColor = [ZL2Theme onSurfaceVariant];
    mcmodIcon.contentMode = UIViewContentModeScaleAspectFit;
    mcmodIcon.translatesAutoresizingMaskIntoConstraints = NO;
    mcmodIcon.userInteractionEnabled = NO;
    [_mcmodButton addSubview:mcmodIcon];

    _mcmodLabel = [[UILabel alloc] init];
    _mcmodLabel.text = localize(@"ame432.searchid.mcmod", @"mcmod 中文资料搜索");
    _mcmodLabel.font = [ZL2Theme fontLabelLarge];
    _mcmodLabel.textColor = [ZL2Theme primary];
    _mcmodLabel.numberOfLines = 1;
    _mcmodLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _mcmodLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _mcmodLabel.userInteractionEnabled = NO;
    [_mcmodButton addSubview:_mcmodLabel];

    UIImageView *mcmodArrow = [[UIImageView alloc] initWithImage:
        [ZL2SIDSystemImage(@"arrow.up.right", @"arrow.up.forward") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    mcmodArrow.tintColor = [ZL2Theme onSurfaceVariant];
    mcmodArrow.contentMode = UIViewContentModeScaleAspectFit;
    mcmodArrow.translatesAutoresizingMaskIntoConstraints = NO;
    mcmodArrow.userInteractionEnabled = NO;
    [_mcmodButton addSubview:mcmodArrow];

    [NSLayoutConstraint activateConstraints:@[
        [mcmodIcon.leadingAnchor constraintEqualToAnchor:_mcmodButton.leadingAnchor constant:12],
        [mcmodIcon.centerYAnchor constraintEqualToAnchor:_mcmodButton.centerYAnchor],
        [mcmodIcon.widthAnchor constraintEqualToConstant:18],
        [mcmodIcon.heightAnchor constraintEqualToConstant:18],
        [_mcmodLabel.leadingAnchor constraintEqualToAnchor:mcmodIcon.trailingAnchor constant:8],
        [_mcmodLabel.centerYAnchor constraintEqualToAnchor:_mcmodButton.centerYAnchor],
        [mcmodArrow.leadingAnchor constraintGreaterThanOrEqualToAnchor:_mcmodLabel.trailingAnchor constant:8],
        [mcmodArrow.trailingAnchor constraintEqualToAnchor:_mcmodButton.trailingAnchor constant:-12],
        [mcmodArrow.centerYAnchor constraintEqualToAnchor:_mcmodButton.centerYAnchor],
        [mcmodArrow.widthAnchor constraintEqualToConstant:16],
        [mcmodArrow.heightAnchor constraintEqualToConstant:16],
    ]];

    _actionStack = [[UIStackView alloc] initWithArrangedSubviews:
        @[_galleryHeader, _galleryScroll, _goDownloadButton, _openLinkButton, _mcmodButton]];
    _actionStack.axis = UILayoutConstraintAxisVertical;
    _actionStack.alignment = UIStackViewAlignmentFill;
    _actionStack.spacing = 10;
    _actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_actionStack];

    // 状态件
    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [ZL2Theme onSurfaceVariant];
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.text = localize(@"ame369.sid.idle_hint", @"输入项目 ID 或 slug，选择平台后查询");
    _statusLabel.font = [ZL2Theme fontBodyLarge];
    _statusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    UILayoutGuide *cardLG = _resultCard.layoutMarginsGuide;
    _resultCard.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 12);
    [NSLayoutConstraint activateConstraints:@[
        [_idField.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_idField.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_idField.heightAnchor constraintEqualToConstant:40],

        [chips.centerYAnchor constraintEqualToAnchor:_idField.centerYAnchor],
        [chips.leadingAnchor constraintGreaterThanOrEqualToAnchor:_idField.trailingAnchor constant:12],
        [chips.trailingAnchor constraintEqualToAnchor:_searchButton.leadingAnchor constant:-8],

        [_searchButton.centerYAnchor constraintEqualToAnchor:_idField.centerYAnchor],
        [_searchButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_searchButton.widthAnchor constraintEqualToConstant:88],
        [_searchButton.heightAnchor constraintEqualToConstant:40],
        [searchLabel.centerXAnchor constraintEqualToAnchor:_searchButton.centerXAnchor],
        [searchLabel.centerYAnchor constraintEqualToAnchor:_searchButton.centerYAnchor],

        [_resultCard.topAnchor constraintEqualToAnchor:_idField.bottomAnchor constant:16],
        [_resultCard.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_resultCard.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [_iconView.topAnchor constraintEqualToAnchor:cardLG.topAnchor constant:12],
        [_iconView.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:72],
        [_iconView.heightAnchor constraintEqualToConstant:72],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.topAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
        [_authorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
        [_authorLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_authorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cardLG.trailingAnchor],

        [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_descLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cardLG.trailingAnchor],

        // ★Task429：收藏钮加大——desc 尾部避让加宽后的收藏钮（≤ 双保险：
        //   原有 ≤ cardLG.trailing 保留；收藏钮透明命中冗余区不再压描述文字）
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_favoriteButton.leadingAnchor constant:-8],

        [_downloadsLabel.topAnchor constraintEqualToAnchor:_descLabel.bottomAnchor constant:4],
        [_downloadsLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],

        [_categoriesLabel.topAnchor constraintEqualToAnchor:_downloadsLabel.bottomAnchor constant:2],
        [_categoriesLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_categoriesLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_favoriteButton.leadingAnchor constant:-8],

        [_favoriteButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_favoriteButton.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],
        // ★Task429：收藏钮加大——命中面 32x32→高 44/宽 ≥64（HIG 最小命中面；
        //   宽度由内容撑出，含 12pt 左侧隐形命中冗余，对齐 ZL2 搜索卡基准）
        [_favoriteButton.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [_favoriteButton.heightAnchor constraintEqualToConstant:44],
        // ★Task429：心形锚点 centerX→左缘定距 12（同 ZL2 基准：图标靠左、
        //   label 靠右，中段留隐形命中冗余）；图标保持 22pt
        [heartIcon.leadingAnchor constraintEqualToAnchor:_favoriteButton.leadingAnchor constant:12],
        [heartIcon.centerYAnchor constraintEqualToAnchor:_favoriteButton.centerYAnchor],
        [heartIcon.widthAnchor constraintEqualToConstant:22],
        [heartIcon.heightAnchor constraintEqualToConstant:22],
        // ★Task429：收藏 label 装配（HeartToggleLabel 口径：紧跟心形 + 右缘贴钮）
        [_favoriteLabel.leadingAnchor constraintEqualToAnchor:heartIcon.trailingAnchor constant:6],
        [_favoriteLabel.trailingAnchor constraintEqualToAnchor:_favoriteButton.trailingAnchor],
        [_favoriteLabel.centerYAnchor constraintEqualToAnchor:_favoriteButton.centerYAnchor],

        // ★Task432：结果卡尾段 = 动作列（截图卡/前往下载/浏览器/mcmod 纵排，
        //   hidden 成员自收）；卡底钉动作列尾（原单钮形态退役）
        [_actionStack.topAnchor constraintEqualToAnchor:_categoriesLabel.bottomAnchor constant:8],
        [_actionStack.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
        [_actionStack.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],
        [_resultCard.bottomAnchor constraintEqualToAnchor:_actionStack.bottomAnchor constant:12],

        [_galleryScroll.heightAnchor constraintEqualToConstant:96],
        [_goDownloadButton.heightAnchor constraintEqualToConstant:40],
        [_goDownloadLabel.centerXAnchor constraintEqualToAnchor:_goDownloadButton.centerXAnchor],
        [_goDownloadLabel.centerYAnchor constraintEqualToAnchor:_goDownloadButton.centerYAnchor],
        [_openLinkButton.heightAnchor constraintEqualToConstant:40],
        [linkLabel.centerXAnchor constraintEqualToAnchor:_openLinkButton.centerXAnchor],
        [linkLabel.centerYAnchor constraintEqualToAnchor:_openLinkButton.centerYAnchor],
        [_mcmodButton.heightAnchor constraintEqualToConstant:44],

        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];
}

#pragma mark - 平台切换

- (void)ame_platformTapped:(UIControl *)sender {
    self.platform = sender.tag;
    [self ame_applyPlatformAppearance];
}

- (void)ame_applyPlatformAppearance {
    for (NSUInteger i = 0; i < self.platformChips.count; i++) {
        UIControl *chip = self.platformChips[i];
        BOOL selected = (chip.tag == self.platform);
        chip.backgroundColor = selected ? [ZL2Theme secondaryContainer] : [ZL2Theme surfaceContainer];
        self.platformChipLabels[i].textColor = selected ? [ZL2Theme onSecondaryContainer]
                                                        : [ZL2Theme onSurfaceVariant];
    }
}

#pragma mark - 查询（ZL2 SearchIdScreen 状态机语义：Loading/Result/NotFound/Error）

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self ame_searchTapped];
    return YES;
}

- (void)ame_searchTapped {
    [self.idField resignFirstResponder];
    NSString *query = [self.idField.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) return;

    self.fetchedProject = nil;
    self.fetchedRaw = nil;
    self.resultCard.hidden = YES;
    self.statusLabel.hidden = YES;
    [self.spinner startAnimating];

    NSString *endpoint = nil;
    if (self.platform == 1) {
        // Modrinth：ID 或 slug 均可直达 /project/{id|slug}
        endpoint = [NSString stringWithFormat:@"project/%@",
                    [query stringByAddingPercentEncodingWithAllowedCharacters:
                     [NSCharacterSet URLPathAllowedCharacterSet]]];
    } else {
        // CurseForge：/mods/{id}（数字 ID）
        endpoint = [NSString stringWithFormat:@"mods/%@", query];
    }

    __weak typeof(self) weakSelf = self;
    id api = (self.platform == 1) ? (id)[ModrinthAPI sharedInstance]
                                  : (id)[CurseForgeAPI sharedInstance];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        id response = [api getEndpoint:endpoint params:nil];
        // CurseForge 响应带 data 包裹（响应字段解包在外层 block 完成，
        // 避免嵌套 block 对局部变量的 __block 要求）
        if (self.platform == 2 && [response isKindOfClass:[NSDictionary class]]) {
            response = response[@"data"] ?: response;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;
            [s.spinner stopAnimating];
            if (!response) {
                s.statusLabel.text = localize(@"ame369.sid.lookup_failed", @"查询失败：项目不存在或网络异常");
                s.statusLabel.hidden = NO;
                return;
            }
            [s ame_applyResult:response];
        });
    });
}

/// 平台响应 → 统一展示字典（Modrinth hit / CurseForge data 字段映射）
- (void)ame_applyResult:(NSDictionary *)raw {
    // ★Task432：原始响应留存（轨路由 classId/projectType + Modrinth gallery 消费）
    self.fetchedRaw = raw;

    NSString *title = raw[@"title"] ?: raw[@"name"] ?: @"";
    NSString *desc = raw[@"description"] ?: raw[@"summary"] ?: @"";
    NSString *iconUrl = raw[@"icon_url"] ?: raw[@"iconUrl"] ?: @"";
    NSString *author = raw[@"author"] ?: @"";
    if (author.length == 0 && [raw[@"authors"] isKindOfClass:[NSArray class]] &&
        [raw[@"authors"] count] > 0) {
        author = raw[@"authors"][0][@"name"] ?: @"";
    }
    NSNumber *downloads = raw[@"downloads"] ?: raw[@"downloadCount"] ?: @0;
    NSArray *categories = raw[@"categories"] ?: raw[@"display_categories"] ?: @[];
    NSString *projectId = raw[@"project_id"] ?: raw[@"id"] ?: @"";
    if (![projectId isKindOfClass:[NSString class]]) {
        projectId = [projectId description] ?: @"";
    }
    NSString *slug = raw[@"slug"] ?: projectId;
    NSString *projectType = raw[@"project_type"] ?: @"";

    self.fetchedProject = @{
        @"platform": @(self.platform),
        @"projectId": projectId,
        @"title": title ?: @"",
        @"description": desc ?: @"",
        @"imageUrl": iconUrl ?: @"",
        @"author": author ?: @"",
        @"downloads": downloads ?: @0,
        @"projectType": projectType ?: @"",
        @"slug": slug ?: @"",
        @"categories": categories ?: @[],
    };

    self.titleLabel.text = title;
    self.authorLabel.text = author.length > 0 ? [NSString stringWithFormat:localize(@"ame369.sid.author_fmt", @"作者：%@"), author] : @"";
    self.descLabel.text = desc;
    self.downloadsLabel.text = [NSString stringWithFormat:localize(@"ame369.sid.downloads_fmt", @"下载 %@"), downloads];
    self.categoriesLabel.text = [categories componentsJoinedByString:@" · "];

    if (iconUrl.length > 0) {
        [self ame_loadIcon:iconUrl];
    }
    [self ame_refreshFavoriteState];

    // ★Task432：三段增量填充（顺序 = ZL2 ResultLayout：信息卡 → 截图 → 动作列）
    [self ame432_applyGallery:raw];
    NSInteger assetType = [self ame432_assetTypeForFetchedProject];
    // 无对应轨的类型（datapack/server/未知）不给按钮——诚实边界
    self.goDownloadButton.hidden = (assetType < 0);
    self.resultCard.hidden = NO;
}

- (void)ame_loadIcon:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            s.iconView.image = image;
        });
    }];
    [task resume];
}

#pragma mark - ★Task432 实锤三：结果卡三段（截图卡 / 前往下载 / mcmod）

/// 截图卡填充（Modrinth /project/{id} 响应自带 gallery 数组——ZL2
/// ModrinthSingleProject.gallery: Array<Gallery{url, featured, title,
/// description}> 同源字段；CurseForge 响应无该字段 → 不显示该段，不虚构数据）
- (void)ame432_applyGallery:(NSDictionary *)raw {
    for (UIView *v in [_galleryRowStack.arrangedSubviews copy]) [v removeFromSuperview];
    BOOL hasGallery = (self.platform == 1 && [raw[@"gallery"] isKindOfClass:[NSArray class]] &&
                       ((NSArray *)raw[@"gallery"]).count > 0);
    _galleryHeader.hidden = !hasGallery;
    _galleryScroll.hidden = !hasGallery;
    if (!hasGallery) return;

    NSArray *gallery = (NSArray *)raw[@"gallery"];
    // 取前 3 张（Task432 规格 1-3 张；ZL2 SearchIdScreen ScreenshotItemLayout
    //   items 横滑语义——条目级自滑，不因张数改布局）
    NSUInteger shown = MIN(gallery.count, (NSUInteger)3);
    for (NSUInteger i = 0; i < shown; i++) {
        NSDictionary *item = gallery[i];
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *urlString = item[@"url"];
        if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) continue;
        UIImageView *thumb = [[UIImageView alloc] init];
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.layer.cornerRadius = [ZL2Theme radiusS];
        thumb.backgroundColor = [ZL2Theme surfaceVariant];
        thumb.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [thumb.widthAnchor constraintEqualToConstant:140],
            [thumb.heightAnchor constraintEqualToConstant:96],
        ]];
        [_galleryRowStack addArrangedSubview:thumb];
        [self ame432_loadGalleryImage:urlString into:thumb];
    }
}

/// 截图缩略图异步装载（ame_loadIcon 同款 NSURLSession 手法，目标视图参数化）。
/// ★Task432 诚实边界：加载失败该缩略图自撤（不虚构占位图），行清空后整段
///   收起（规格“源无截图或加载失败则不显示该段”）。
- (void)ame432_loadGalleryImage:(NSString *)urlString into:(UIImageView *)thumbView {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self ame432_galleryThumbFailed:thumbView];   // 非法 URL = 立即按失败处理
        return;
    }
    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakThumb = thumbView;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = (data && !error) ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) {
                weakThumb.image = image;
                return;
            }
            __strong typeof(weakSelf) s = weakSelf;
            if (s) {
                [s ame432_galleryThumbFailed:weakThumb];
            } else if (weakThumb) {
                [weakThumb removeFromSuperview];   // 页面已亡：仅自撤防泄漏
            }
        });
    }];
    [task resume];
}

/// 截图缩略图失败自撤 + 行空整段收起（arrangedSubview 移除自动收缩，不虚构占位）
- (void)ame432_galleryThumbFailed:(UIImageView *)thumbView {
    [thumbView removeFromSuperview];
    if (_galleryRowStack.arrangedSubviews.count == 0) {
        _galleryHeader.hidden = YES;
        _galleryScroll.hidden = YES;
    }
}

/// 查询结果 → 轨内资产类型映射（ZL2AssetSearchType；-1 = 无对应轨 → 不给按钮）。
/// Modrinth：project_type 直通（mod/modpack/resourcepack/shader/world；
///   datapack 轨随 Task432 八轨收敛摘除 → 无轨）；CurseForge：项目对象无
///   project_type → classId 映射（CurseForgeAPI.m kCurseForgeClassID* 常量
///   表同源：6=mods/12=resourcepacks/17=worlds/4471=modpacks/6552=shaders）。
- (NSInteger)ame432_assetTypeForFetchedProject {
    NSDictionary *raw = self.fetchedRaw;
    if (!raw) return -1;
    if (self.platform == 1) {
        NSString *pt = raw[@"project_type"];
        if (![pt isKindOfClass:[NSString class]]) return -1;
        NSDictionary *map = @{@"mod": @(ZL2AssetSearchTypeMod),
                              @"modpack": @(ZL2AssetSearchTypeModpack),
                              @"resourcepack": @(ZL2AssetSearchTypeResourcePack),
                              @"shader": @(ZL2AssetSearchTypeShader),
                              @"world": @(ZL2AssetSearchTypeWorld)};
        NSNumber *hit = map[pt];
        return hit ? hit.integerValue : -1;
    }
    NSInteger classId = -1;
    if ([raw[@"classId"] isKindOfClass:[NSNumber class]]) {
        classId = [raw[@"classId"] integerValue];
    }
    switch (classId) {
        case 6:    return ZL2AssetSearchTypeMod;
        case 12:   return ZL2AssetSearchTypeResourcePack;
        case 17:   return ZL2AssetSearchTypeWorld;
        case 4471: return ZL2AssetSearchTypeModpack;
        case 6552: return ZL2AssetSearchTypeShader;
        default:   return -1;
    }
}

/// 轨内资产类型 → 下载壳八轨下标（ZL2DownloadViewController.h 轨序契约：
/// 0 游戏 / 1 整合包 / 2 模组 / 3 资源包 / 4 存档 / 5 光影包 / 6 按ID搜索 / 7 收藏）
- (NSInteger)ame432_shellIndexForAssetType:(NSInteger)assetType {
    switch (assetType) {
        case ZL2AssetSearchTypeMod:          return 2;
        case ZL2AssetSearchTypeModpack:      return 1;
        case ZL2AssetSearchTypeResourcePack: return 3;
        case ZL2AssetSearchTypeWorld:        return 4;
        case ZL2AssetSearchTypeShader:       return 5;
        default:                             return -1;
    }
}

/// 前往下载：找宿主下载壳 → 切对应轨 → 轨内打开本项目版本详情/安装页
/// （ZL2 SearchIdScreen onView → swapToDownload → swapToCategoryAddon 语义：
///   navigateToDownload(downloadModScreen) = 切轨 + 直达项目详情）
- (void)ame_goDownloadTapped {
    NSDictionary *raw = self.fetchedRaw;
    if (!raw) return;
    NSInteger assetType = [self ame432_assetTypeForFetchedProject];
    if (assetType < 0) return;
    NSInteger shellIndex = [self ame432_shellIndexForAssetType:assetType];
    if (shellIndex < 0) return;

    // ① 宿主下载壳（SearchId = 壳 case 6 子页；沿父链找防挂点漂移）
    ZL2DownloadViewController *shell = nil;
    UIViewController *host = self.parentViewController;
    while (host) {
        if ([host isKindOfClass:[ZL2DownloadViewController class]]) {
            shell = (ZL2DownloadViewController *)host;
            break;
        }
        host = host.parentViewController;
    }
    if (!shell) return;

    // ② 切到目标下载轨（左轨选中态/内容区随壳内 ame_showCategory 切换）
    [shell ame_showCategory:shellIndex];

    // ③ 轨内打开本项目版本页（delegate = 轨搜索页 → 安装链全量复用）
    ZL2AssetSearchViewController *track = [self ame432_findTrackInShell:shell assetType:assetType];
    if (!track) return;
    [self ame432_openTrackDetail:track assetType:assetType rawDict:raw];
}

/// 轨搜索页定位（壳子页缓存集合内按 assetType 匹配；childViewControllers 公共面）。
/// ★Task432：跳过收藏轨——initWithFavorites 的 assetType=Mod 仅为占位
///   （ZL2AssetSearchViewController.m:762），用户先逛过收藏时收藏轨先入
///   childViewControllers，按类型盲匹配会拿它冒充真轨；favoritesMode 经
///   桥接类目运行期访问器读取（真 getter 在轨页主 TU 合成）。
- (ZL2AssetSearchViewController *)ame432_findTrackInShell:(ZL2DownloadViewController *)shell
                                                assetType:(NSInteger)assetType {
    for (UIViewController *child in shell.childViewControllers) {
        if ([child isKindOfClass:[ZL2AssetSearchViewController class]]) {
            ZL2AssetSearchViewController *track = (ZL2AssetSearchViewController *)child;
            if (track.favoritesMode) continue;   // 收藏轨占位类型不参与匹配
            if ((NSInteger)track.assetType == assetType) return track;
        }
    }
    return nil;
}

/// 轨内版本页构造（分支构造与 ZL2AssetSearch ame_openResultAtIndex: 1:1 对表；
/// delegate = 轨搜索页 → 下载/依赖解析/整合包导入/资源包装入全链零重复）。
/// pending* 经文件尾自含声明类目的运行期合成访问器回填。
/// ★Task432 预填边界（如实）：轨页搜索框无公开预填属性，查询关键词不经轨
///   内搜索框回填；项目 id 经条目字典（ModItem/ShaderItem 等 onlineID 同键
///   "id" 直取）直进版本页定位版本列表——语义强于仅切轨+空搜索框。
- (void)ame432_openTrackDetail:(ZL2AssetSearchViewController *)track
                     assetType:(NSInteger)assetType
                       rawDict:(NSDictionary *)rawDict {
    // 条目级来源随直查页平台（防轨内平台档与直查源错位 → 版本页拉错 API）；
    // ame_openResultAtIndex apiSource 优先级同款：条目自带 > 轨默认，1/2 收敛
    NSMutableDictionary *entry = [rawDict mutableCopy];
    NSInteger itemSource = self.platform;
    if (itemSource != 1 && itemSource != 2) itemSource = 1;
    entry[@"apiSource"] = @(itemSource);

    // 轨内偏好快照（ame_openResultAtIndex 同款：preferredGameVersion/Loader 透传）
    NSString *mcVersion = [track ame_profileMinecraftVersion];
    NSString *loader = [track ame_profileLoader];

    UIViewController *versionVC = nil;
    switch (assetType) {
        case ZL2AssetSearchTypeMod: {
            // 防轨内 pending 残留串扰（模组分支不吃 modpack 回填态）
            track.pendingDownloadType = nil;
            ModItem *modItem = [[ModItem alloc] initWithOnlineData:entry];
            ModVersionViewController *vc = [[ModVersionViewController alloc] init];
            vc.modItem = modItem;
            vc.delegate = track;
            vc.title = modItem.displayName;
            vc.apiSource = itemSource;
            vc.preferredGameVersion = mcVersion;
            vc.preferredLoader = loader;
            versionVC = vc;
            break;
        }
        case ZL2AssetSearchTypeModpack: {
            // 旧页 installModpackAtIndexPath 形态：模组版版本页复用 +
            // pendingDownloadType="modpack" + pendingModpackDict 分流安装流
            ModItem *modItem = [[ModItem alloc] initWithOnlineData:entry];
            ModVersionViewController *vc = [[ModVersionViewController alloc] init];
            vc.modItem = modItem;
            vc.delegate = track;
            vc.title = modItem.displayName;
            vc.apiSource = itemSource;
            vc.preferredGameVersion = mcVersion;
            vc.preferredLoader = loader;
            track.pendingDownloadType = @"modpack";
            track.pendingModpackDict = entry;
            versionVC = vc;
            break;
        }
        case ZL2AssetSearchTypeResourcePack: {
            ResourcePackItem *item = [[ResourcePackItem alloc] initWithOnlineData:entry];
            track.pendingDownloadType = @"resourcepack";
            track.pendingResourcePackItem = item;
            AssetVersionViewController *vc = [[AssetVersionViewController alloc] init];
            vc.assetType = AssetVersionTypeResourcePack;
            vc.projectID = item.onlineID;
            vc.apiSource = itemSource;
            vc.projectDisplayName = item.displayName;
            vc.delegate = track;
            vc.title = item.displayName;
            vc.projectIconURL = item.iconURL;
            vc.projectAuthor = item.author;
            vc.projectDownloads = item.downloads;
            vc.projectLikes = item.likes;
            vc.projectDescription = item.resourcePackDescription;
            vc.projectCategories = item.categories;
            vc.projectLastUpdated = item.lastUpdated;
            vc.preferredGameVersion = mcVersion;
            versionVC = vc;
            break;
        }
        case ZL2AssetSearchTypeWorld: {
            WorldItem *item = [[WorldItem alloc] initWithOnlineData:entry];
            track.pendingDownloadType = @"world";
            track.pendingWorldItem = item;
            AssetVersionViewController *vc = [[AssetVersionViewController alloc] init];
            vc.assetType = AssetVersionTypeWorld;
            vc.projectID = item.onlineID;
            vc.apiSource = itemSource;
            vc.projectDisplayName = item.displayName;
            vc.delegate = track;
            vc.title = item.displayName;
            vc.projectIconURL = item.iconURL;
            vc.projectAuthor = item.author;
            vc.projectDownloads = item.downloads;
            vc.projectLikes = item.likes;
            vc.projectDescription = item.worldDescription;
            vc.projectCategories = item.categories;
            vc.projectLastUpdated = item.lastUpdated;
            vc.preferredGameVersion = mcVersion;
            versionVC = vc;
            break;
        }
        case ZL2AssetSearchTypeShader: {
            ShaderItem *shaderItem = [[ShaderItem alloc] initWithOnlineData:entry];
            ShaderVersionViewController *vc = [[ShaderVersionViewController alloc] init];
            vc.shaderItem = shaderItem;
            vc.delegate = track;
            vc.title = shaderItem.displayName;
            vc.apiSource = itemSource;
            vc.preferredGameVersion = mcVersion;
            vc.preferredLoader = loader;
            versionVC = vc;
            break;
        }
        default:
            return;   // 无对应轨（调用方已拦，双保险）
    }
    if (!versionVC) return;

    // push（宿主 nav；无 nav 宿主时 present 包 nav 兜底——ame_pushViewController 同判例）
    if (self.navigationController) {
        [self.navigationController pushViewController:versionVC animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:versionVC];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

/// mcmod 中文资料外链（search.mcmod.cn/s?key=<项目名>；URL 编码后 openURL）
- (void)ame_mcmodTapped {
    if (!self.fetchedProject) return;
    NSString *title = self.fetchedProject[@"title"];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) return;
    NSString *encoded = [title stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://search.mcmod.cn/s?key=%@", encoded];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - 收藏 + 浏览器

- (void)ame_refreshFavoriteState {
    if (!self.fetchedProject) return;
    BOOL fav = [[ZL2FavoritesStore sharedStore]
        isFavoritePlatform:self.platform
                 projectId:self.fetchedProject[@"projectId"]];
    UIImageView *heart = [self.favoriteButton viewWithTag:101];
    heart.image = [UIImage systemImageNamed:(fav ? @"heart.fill" : @"heart")];
    heart.tintColor = fav ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    // ★Task429：收藏钮加大同步——label 选中态色随心形（tertiary/次级），
    //   a11y 标签随选中态切换（复用既有键，同 ZL2 搜索卡/详情胶囊口径）
    self.favoriteLabel.textColor = fav ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    self.favoriteButton.accessibilityLabel = fav
        ? localize(@"ame369.asearch.unfavorite", @"取消收藏")
        : localize(@"ame369.common.favorites", @"收藏");
}

- (void)ame_favoriteTapped {
    if (!self.fetchedProject) return;
    [[ZL2FavoritesStore sharedStore] toggleFavoriteWithProject:self.fetchedProject];
    [self ame_refreshFavoriteState];
}

- (void)ame_openLinkTapped {
    if (!self.fetchedProject) return;
    NSString *urlString = nil;
    if (self.platform == 1) {
        urlString = [NSString stringWithFormat:@"https://modrinth.com/mod/%@", self.fetchedProject[@"slug"]];
        if ([self.fetchedProject[@"projectType"] isEqualToString:@"modpack"]) {
            urlString = [NSString stringWithFormat:@"https://modrinth.com/modpack/%@", self.fetchedProject[@"slug"]];
        }
    } else {
        urlString = [NSString stringWithFormat:@"https://www.curseforge.com/projects/%@", self.fetchedProject[@"slug"]];
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end
