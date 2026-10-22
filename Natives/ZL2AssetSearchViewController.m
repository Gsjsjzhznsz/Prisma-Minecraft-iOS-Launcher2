//
// ZL2AssetSearchViewController.m — ZL2 风格通用远程资产搜索列表页（7.0-UI-10-a）
//
// 【语义纠错】ZL2 下载页六类全部是远程搜索下载（ZalithLauncher2 的
//   DownloadModPack/Mod/ResourcePack/Saves/ShadersScreen.kt 均 route 到
//   assets/search/SearchXXXScreen.kt）；本地管理器（模组/存档/资源包/光影
//   管理）在 ZL2 属版本管理域，绝不属于下载页。上轮（7.0-UI-9-a）误把
//   五类挂到本地管理器 VC，本轮以本页纠错重接（ZL2DownloadViewController
//   ame_childForIndex: case 1-5）。
//
// 【类型 → 端点 → 版本页映射表】（全部 1:1 复刻旧 DownloadViewController.m
//   真实代码，锚点行号以基线 24e5aa6 的 DownloadViewController.m 为准）
//
//  ┌──────────┬────────────────────────────┬───────────────────────────────┐
//  │ 类型     │ 搜索端点（filters 键）      │ 结果卡点击 → 版本页（锚点）    │
//  ├──────────┼────────────────────────────┼───────────────────────────────┤
//  │ 模组     │ Modrinth/CF search         │ ModVersionViewController      │
//  │          │ limit/offset/query/sort    │ modItem + apiSource +         │
//  │          │ （projectType 缺省=mod）    │ preferredGameVersion/Loader   │
//  │          │                            │ （旧页 L5274-5292）           │
//  ├──────────┼────────────────────────────┼───────────────────────────────┤
//  │ 整合包   │ 同上 + isModpack=YES +     │ ModVersionViewController      │
//  │          │ projectType=modpack + sort │ + pendingDownloadType=        │
//  │          │                            │ @"modpack" + pendingModpackDict│
//  │          │                            │ （旧页 L4712-4735）；选完版本  │
//  │          │                            │ 走 startModpackInstallation   │
//  │          │                            │ （L4737-4946：zip 下载 3 重试  │
//  │          │                            │ → parse → 原版预装 → 导入，    │
//  │          │                            │ 6 阶段任务上报）               │
//  ├──────────┼────────────────────────────┼───────────────────────────────┤
//  │ 资源包   │ projectType=resourcepack   │ AssetVersionViewController    │
//  │          │                            │ assetType=ResourcePack +      │
//  │          │                            │ project* 全字段（L5324-5353） │
//  ├──────────┼────────────────────────────┼───────────────────────────────┤
//  │ 存档     │ projectType=world          │ AssetVersionViewController    │
//  │          │ （强制 CurseForge，        │ assetType=World，apiSource=2  │
//  │          │  Modrinth 无 world facet） │ （L5396-5425，显式 2）        │
//  ├──────────┼────────────────────────────┼───────────────────────────────┤
//  │ 光影包   │ projectType=shader         │ ShaderVersionViewController   │
//  │          │                            │ shaderItem + apiSource +      │
//  │          │                            │ preferred*（L5299-5317）      │
//  └──────────┴────────────────────────────┴───────────────────────────────┘
//
//   API 来源口径 = 旧页 apiSourceForType:（L1881-1883）/currentAPIForTabType:
//   （L1866-1877）：world 强制 CurseForge；其余按 PLPreferences
//   currentDownloadSourceForType:（"curseforge" → 2，否则 Modrinth 1）。
//   搜索 filters 字典键 = 旧页 loadModList（L2029-2044）/loadModpackList
//   （L2191-2213）/loadShaderList（L2114-2124）/loadResourcePackList
//   （L2273-2283）/loadWorldList（L2433-2443）真实键名：limit/offset/query/
//   projectType/isModpack/sort；版本/加载器筛选不预置（ZL2 搜索过滤栏缺省
//   为空 = PlatformSearchFilter gameVersion=""，与旧页 autoApplyProfileFilters
//   不同——旧页有版本/加载器选择器可改，本页无选择器，预置会把用户锁死在
//   无结果的过滤态；版本页 preferredGameVersion/preferredLoader 仍按当前
//   profile 推导传入，承担"匹配当前环境"职责）。
//
// 【delegate 回调链】版本页 delegate 三协议全部由本页实现（旧页同款语义）：
//   ModVersionViewControllerDelegate（模组 + 整合包复用，pendingDownloadType
//   分流）→ Task227 依赖解析确认单（L5469-5560）→ ModService 下载；
//   整合包分支 → startModpackInstallation（L5439-5455）。
//   ShaderVersionViewControllerDelegate → ShaderService（L5816-5857）。
//   AssetVersionViewControllerDelegate → ResourcePackService / WorldService
//   按 pendingDownloadType 分流（L5564-5602）。
//
// 【ZL2 视觉来源】SearchAssetsScreen.kt（搜索过滤栏语义）、_Search.Result.kt
//   （结果卡：card 底 shape large + 72dp 图标 radius10 + 标题/作者/描述/
//   下载量 + 标签行；本页按任务规格适配为 56×56 图标 + 名称/作者/下载点赞
//   三行）、_Search.Filter.kt + PlatformSortField.kt（排序五档真实值域：
//   relevance/downloads/follows/newest/updated；文案复用旧页既有 i18n 键）。
//   ZL2 分页为页码控制器（PageController），本页按任务规格改为滚到底自动
//   加载（旧页 hasMoreXxx/loadXxxList 语义，L5225-5264 同款判定）。
//
// 【红线】颜色/字体/圆角一律 ZL2Theme；iOS 14 API 上限；SF1.0 档符号 +
//   fallback；新建视图 translatesAutoresizingMaskIntoConstraints=NO；
//   无 viewWithTag 状态查找（chip.tag 仅作下标载荷）；中文文案硬编码/
//   既有 i18n 键复用（新文案入表为既有待办口径）。
//

#import "ZL2AssetSearchViewController.h"
#import "ZL2Theme.h"
#import "utils.h"
// 7.0-UI-10-f #import 手术（预览 harness 集成轮）：以下两条 API 头在本 TU 的
// 原位置移除——其传递链 ModrinthAPI.h/CurseForgeAPI.h → ModpackAPI.h →
// ModpackUtils.h → UnzipKit.h 在 ui_fluent_smoke COMMON 的 -I（仅 Natives 根）
// 下不可达（UnzipKit.h 位于 Natives/external/UnzipKit/，不在搜索路径；与
// AFNetworking submodule 判例 365219f 同源：ui-smoke checkout 不含 external
// 头链）。正式构建走 CMake include 路径不受影响；仅本 .m 以本 import 块后方的
// 本地最小 @interface 替代真实头（签名逐条照抄 ModrinthAPI.h / CurseForgeAPI.h，
// 本 TU 未消费的成员不收——ModpackAPI 基类 / reachedLastPage / lastError /
// CurseForgeResponse* 常量均未引用），逻辑零改动。
#import "PLPreferences.h"
#import "ModItem.h"
#import "ShaderItem.h"
#import "ResourcePackItem.h"
#import "WorldItem.h"
#import "ModVersionViewController.h"
#import "ShaderVersionViewController.h"
#import "AssetVersionViewController.h"
#import "ModService.h"
#import "ShaderService.h"
#import "ResourcePackService.h"
#import "WorldService.h"
#import "ModDependencyResolver.h"
#import "ModpackExportService.h"
#import "PLProfiles.h"
#import "IconLoader.h"
#import "ZL2FavoritesStore.h"
#import "InlineMessageView.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "PLMirrorCenter.h"
#import "installer/ForgeDirectInstaller.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackImportService.h"

// ── 7.0-UI-10-f #import 手术配套：API 双源本地最小声明（仅声明，无实现——类
//    符号 OBJC_CLASS_$_ModrinthAPI / OBJC_CLASS_$_CurseForgeAPI 由预览 harness
//    桩 TU Preview/ZL2PagesStub.m 提供；正式构建由真实 .m 提供）。签名逐条照抄
//    installer/modpack/ModrinthAPI.h / CurseForgeAPI.h（本 TU 消费面：
//    +sharedInstance / +isSourceAvailable / 搜索异步版 / ame227_fetch*Title /
//    getVersionsForModWithID）；ARC 下对仅 @class 前向声明的类发类消息是
//    error（receiver forward class），故此处必须给完整最小 @interface。
@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)ame227_fetchProjectTitle:(NSString *)projectID
                      completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
- (void)ame227_fetchModTitle:(NSString *)modID
                  completion:(void (^)(NSString * _Nullable title, NSError * _Nullable error))completion;
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;
@end

#pragma mark - 静态工具（旧页同款实现，TU 本地）

// SF Symbols 取图兜底（ZL2Home/ZL2Download 同款 helper：符号名异常时降级旧名）
static UIImage *ZL2AssetSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

// 从版本模型 primaryFile 提取 SHA1（旧页 PLSha1FromPrimaryFile 同款实现，
// DownloadViewController.m L5431-5437；改名避免阅读混淆，static 无链接冲突）
static NSString *ZL2AssetSha1FromPrimaryFile(NSDictionary *primaryFile) {
    NSDictionary *hashes = primaryFile[@"hashes"];
    if (![hashes isKindOfClass:[NSDictionary class]]) return nil;
    NSString *sha1 = hashes[@"sha1"];
    if ([sha1 isKindOfClass:[NSString class]] && sha1.length > 0) return sha1;
    return nil;
}

// 格式化下载量数字（旧页 formatDownloadCount 同款：1234 → 1.2K / 1234567 → 1.2M）
static NSString *ZL2AssetFormatDownloadCount(NSNumber *downloads) {
    if (!downloads) return @"0";
    NSInteger dl = [downloads integerValue];
    if (dl >= 1000000) {
        return [NSString stringWithFormat:@"%.1fM", dl / 1000000.0];
    } else if (dl >= 1000) {
        return [NSString stringWithFormat:@"%.1fK", dl / 1000.0];
    }
    return [NSString stringWithFormat:@"%ld", (long)dl];
}

// 搜索结果分页页大小（旧页六类 loadXxxList 统一 @30 + results.count >= 30 判定）
static NSInteger const ZL2AssetSearchPageSize = 30;

#pragma mark - 结果卡 Cell（ZL2 _Search.Result ResultProjectLayout 适配）

// 卡片结构（任务规格 + ZL2 视觉综合）：
//   UIControl 卡（surfaceContainer / radiusL / 内边距 12）
//   ├ 左图标 56×56 radiusM（IconLoader：占位 SF 符号 → 异步真实图标）
//   ├ 中列（行间距 8）：名称 fontLabelLarge / 作者 fontBodyMedium /
//   │                   下载点赞行 fontLabelMedium（arrow.down.circle 12pt）
//   └ 右下载图标钮 32×32（arrow.down.circle.fill，与卡片同动作）
@interface ZL2AssetResultCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UIStackView *metaStack;
@property (nonatomic, strong) UIImageView *downloadsIconView;
@property (nonatomic, strong) UILabel *downloadsLabel;
@property (nonatomic, strong) UIImageView *likesIconView;
@property (nonatomic, strong) UILabel *likesLabel;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIButton *favoriteButton;   // 7.0-UI-14：收藏心形（ZL2 FavoriteToggleLabel 语义）
@property (nonatomic, copy) void (^onDownload)(void);
@property (nonatomic, copy) void (^onFavorite)(void);

- (void)ame_configureWithData:(NSDictionary *)data
              placeholderName:(NSString *)symbolName
               fallbackSymbol:(NSString *)fallbackName;

@end

@implementation ZL2AssetResultCell

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

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.cornerRadius = [ZL2Theme radiusM];
        _iconView.layer.masksToBounds = YES;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [ZL2Theme fontLabelLarge];
        _nameLabel.textColor = [ZL2Theme onSurface];
        _nameLabel.numberOfLines = 1;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _authorLabel = [[UILabel alloc] init];
        _authorLabel.font = [ZL2Theme fontBodyMedium];
        _authorLabel.textColor = [ZL2Theme onSurfaceVariant];
        _authorLabel.numberOfLines = 1;
        _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _downloadsIconView = [[UIImageView alloc] init];
        _downloadsIconView.contentMode = UIViewContentModeScaleAspectFit;
        _downloadsIconView.translatesAutoresizingMaskIntoConstraints = NO;

        _downloadsLabel = [[UILabel alloc] init];
        _downloadsLabel.font = [ZL2Theme fontLabelMedium];
        _downloadsLabel.textColor = [ZL2Theme onSurfaceVariant];
        _downloadsLabel.numberOfLines = 1;
        _downloadsLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _likesIconView = [[UIImageView alloc] init];
        _likesIconView.contentMode = UIViewContentModeScaleAspectFit;
        _likesIconView.translatesAutoresizingMaskIntoConstraints = NO;

        _likesLabel = [[UILabel alloc] init];
        _likesLabel.font = [ZL2Theme fontLabelMedium];
        _likesLabel.textColor = [ZL2Theme onSurfaceVariant];
        _likesLabel.numberOfLines = 1;
        _likesLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _metaStack = [[UIStackView alloc] initWithArrangedSubviews:@[_downloadsIconView, _downloadsLabel,
                                                                     _likesIconView, _likesLabel]];
        _metaStack.axis = UILayoutConstraintAxisHorizontal;
        _metaStack.alignment = UIStackViewAlignmentCenter;
        _metaStack.spacing = 4;
        _metaStack.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _authorLabel, _metaStack]];
        column.axis = UILayoutConstraintAxisVertical;
        column.alignment = UIStackViewAlignmentLeading;
        column.spacing = 8;
        column.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:column];

        _downloadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
        _downloadButton.accessibilityLabel = @"下载";
        [_downloadButton addTarget:self
                            action:@selector(ame_downloadTapped)
                  forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_downloadButton];

        // 收藏心形（ZL2 FavoriteToggleLabel：已收藏 tertiary 实心 / 未收藏 描边）
        _favoriteButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteButton.accessibilityLabel = @"收藏";
        [_favoriteButton addTarget:self
                            action:@selector(ame_favoriteTapped)
                  forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_favoriteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

            [_iconView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12],
            [_iconView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:56],
            [_iconView.heightAnchor constraintEqualToConstant:56],

            [_downloadButton.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
            [_downloadButton.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_downloadButton.widthAnchor constraintEqualToConstant:32],
            [_downloadButton.heightAnchor constraintEqualToConstant:32],

            [_favoriteButton.trailingAnchor constraintEqualToAnchor:_downloadButton.leadingAnchor constant:-4],
            [_favoriteButton.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_favoriteButton.widthAnchor constraintEqualToConstant:32],
            [_favoriteButton.heightAnchor constraintEqualToConstant:32],

            [column.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [column.trailingAnchor constraintEqualToAnchor:_favoriteButton.leadingAnchor constant:-8],
            [column.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [column.topAnchor constraintGreaterThanOrEqualToAnchor:_cardView.topAnchor constant:12],
            [column.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-12],

            [_downloadsIconView.widthAnchor constraintEqualToConstant:12],
            [_downloadsIconView.heightAnchor constraintEqualToConstant:12],
            [_likesIconView.widthAnchor constraintEqualToConstant:12],
            [_likesIconView.heightAnchor constraintEqualToConstant:12],
        ]];
    }
    return self;
}

- (void)ame_downloadTapped {
    if (self.onDownload) self.onDownload();
}

- (void)ame_favoriteTapped {
    if (self.onFavorite) self.onFavorite();
}

- (void)ame_setFavorite:(BOOL)favorite {
    UIImage *heart = [UIImage systemImageNamed:(favorite ? @"heart.fill" : @"heart")];
    [self.favoriteButton setImage:heart forState:UIControlStateNormal];
    self.favoriteButton.tintColor = favorite ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    self.favoriteButton.accessibilityLabel = favorite ? @"取消收藏" : @"收藏";
}

// 旧页 cell 同款：高亮态压暗卡片（ZL2 Compose 的 ripple 等价物）
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardView.alpha = highlighted ? 0.7 : 1.0;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onDownload = nil;
    self.onFavorite = nil;
    [self ame_setFavorite:NO];
    self.nameLabel.text = nil;
    self.authorLabel.text = nil;
    self.authorLabel.hidden = NO;
    self.likesLabel.text = nil;
    self.likesIconView.hidden = NO;
    // 图标复位为占位形态（IconLoader 加载时会重设占位图，这里复位形态属性）
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [ZL2Theme onSurfaceVariant];
}

- (void)ame_configureWithData:(NSDictionary *)data
              placeholderName:(NSString *)symbolName
               fallbackSymbol:(NSString *)fallbackName {
    // 占位图：类型 SF 符号（模板渲染，加载中/失败均显示，旧页 cell 同款）
    UIImage *symbol = ZL2AssetSystemImage(symbolName, fallbackName);
    UIImage *placeholder = [symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.iconView.image = placeholder;
    self.iconView.tintColor = [ZL2Theme onSurfaceVariant];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;

    // 名称（旧页 cell：title ?: slug ?: Unknown）
    NSString *title = data[@"title"];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) title = data[@"slug"];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) title = @"Unknown";
    self.nameLabel.text = title;

    // 作者（CF 搜索结果无 author 键 → 隐藏该行，StackView 自动收起）
    NSString *author = data[@"author"];
    if ([author isKindOfClass:[NSString class]] && author.length > 0) {
        self.authorLabel.text = author;
        self.authorLabel.hidden = NO;
    } else {
        self.authorLabel.text = nil;
        self.authorLabel.hidden = YES;
    }

    // 下载量行（arrow.down.circle 12pt + 数字）+ 点赞（有数据才显示，CF 无此键）
    // 注：C 辅助函数结果先落局部变量再套消息方括号（编译三真雷判例：
    // 禁 [func(...) selector:] 形态的 C 函数接收者写法）
    UIImage *downloadsSymbol = ZL2AssetSystemImage(@"arrow.down.circle", @"arrow.down");
    self.downloadsIconView.image = [downloadsSymbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.downloadsIconView.tintColor = [ZL2Theme onSurfaceVariant];
    self.downloadsLabel.text = ZL2AssetFormatDownloadCount(data[@"downloads"]);

    NSNumber *likes = data[@"likes"];
    if ([likes isKindOfClass:[NSNumber class]] && [likes integerValue] > 0) {
        UIImage *likesSymbol = ZL2AssetSystemImage(@"heart.fill", @"heart");
        self.likesIconView.image = [likesSymbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.likesIconView.tintColor = [ZL2Theme onSurfaceVariant];
        self.likesLabel.text = ZL2AssetFormatDownloadCount(likes);
        self.likesIconView.hidden = NO;
        self.likesLabel.hidden = NO;
    } else {
        self.likesIconView.hidden = YES;
        self.likesLabel.hidden = YES;
    }

    // 下载钮（32×32，arrow.down.circle.fill，primary 着色）
    UIImage *downloadIcon = ZL2AssetSystemImage(@"arrow.down.circle.fill", @"arrow.down.circle");
    [self.downloadButton setImage:[downloadIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                         forState:UIControlStateNormal];
    self.downloadButton.tintColor = [ZL2Theme primary];

    // 图标异步加载（IconLoader：取消旧请求 → 占位 → 双层缓存 → 降采样 → CDN 镜像 → 兜底；
    // 旧页 cell loadIconFromURL 同款二次校验与 AspectFill 切换）
    NSString *iconUrl = data[@"imageUrl"];
    if (![iconUrl isKindOfClass:[NSString class]] || iconUrl.length == 0) iconUrl = data[@"icon_url"];
    __weak typeof(self) weakSelf = self;
    [IconLoader loadIconForImageView:self.iconView
                                 URL:iconUrl
                         placeholder:placeholder
                            fallback:placeholder
                          targetSize:CGSizeMake(56, 56)
                             options:IconLoaderOptionsDefault
                          completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        // 真实项目图标 AspectFill 填充，覆盖占位 SF 符号的 AspectFit 形态
        strongSelf.iconView.contentMode = UIViewContentModeScaleAspectFill;
        // [UIColor clearColor] = 壳 container 同款透明容器判例（非主题色硬编码，
        // 语义为解除模板着色，ZL2DownloadViewController/旧下载页 cell 同款）
        strongSelf.iconView.tintColor = [UIColor clearColor];
    }];
}

@end

#pragma mark - 主页面

@interface ZL2AssetSearchViewController () <
    UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate,
    ModVersionViewControllerDelegate, ShaderVersionViewControllerDelegate,
    AssetVersionViewControllerDelegate>

// 构造入参（init 注入后只读）
@property (nonatomic, assign, readwrite) ZL2AssetSearchType assetType;
@property (nonatomic, copy, readwrite) NSString *pageTitle;

// 顶部搜索行
@property (nonatomic, strong) UIView *searchCapsule;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIControl *sortToggleControl;

// 排序 chips 横排行（ZL2DownloadViewController 同款 chip 工厂变体）
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) NSMutableArray<UIControl *> *chipControls;
@property (nonatomic, strong) NSMutableArray<UILabel *> *chipLabels;
@property (nonatomic, strong) NSLayoutConstraint *chipsHeightConstraint;

// 结果列表与空态
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UIImageView *emptyIconView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// 搜索状态
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, copy) NSString *sortField;
@property (nonatomic, assign) BOOL chipsExpanded;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@property (nonatomic, assign) NSInteger currentOffset;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) BOOL hasSearched;
@property (nonatomic, assign) NSInteger requestGeneration;   // 过期响应防护（搜索词/排序变更即失效）
@property (nonatomic, assign) NSInteger inputGeneration;     // 0.5s 防抖代际
@property (nonatomic, assign) BOOL pendingSearchAfterFlight; // 请求期间到达的新搜索（latest-wins）

// 排序 chips 平行数组（ZL2 PlatformSortField 真实值域 + 旧页既有 i18n 文案键）
@property (nonatomic, copy) NSArray<NSString *> *sortValues;
@property (nonatomic, copy) NSArray<NSString *> *sortTitleKeys;

// 版本页 pending（旧页 pendingDownloadType/pendingModpackDict 语义 1:1）
@property (nonatomic, copy) NSString *pendingDownloadType;
@property (nonatomic, strong) NSDictionary *pendingModpackDict;
@property (nonatomic, strong) ResourcePackItem *pendingResourcePackItem;
@property (nonatomic, strong) WorldItem *pendingWorldItem;

// 目标实例快照（旧页 targetProfileName 语义：打开页面时锁定，防操作期间切实例错写目录）
@property (nonatomic, copy) NSString *lockedProfileName;

// 收藏模式（7.0-UI-14）：数据源 = ZL2FavoritesStore，其余全链同构复用
@property (nonatomic, assign) BOOL favoritesMode;

// 整合包安装流的原版预装任务句柄（旧页 vanillaPreinstallTask 语义）
@property (nonatomic, strong) MinecraftResourceDownloadTask *vanillaPreinstallTask;

@end

@implementation ZL2AssetSearchViewController

#pragma mark - Lifecycle

- (instancetype)initWithType:(ZL2AssetSearchType)type title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _assetType = type;
        _pageTitle = [title copy] ?: @"";
        _results = [NSMutableArray array];
        _chipControls = [NSMutableArray array];
        _chipLabels = [NSMutableArray array];
        _searchQuery = @"";
        _sortField = @"relevance";   // ZL2 PlatformSearchFilter 缺省 RELEVANCE
        _hasMore = YES;
        _hasSearched = NO;
        _currentOffset = 0;
        _requestGeneration = 0;
        _inputGeneration = 0;
        _sortValues = @[@"relevance", @"downloads", @"follows", @"newest", @"updated"];
        // ZL2 PlatformSortField 语义（相关度/下载量/人气=关注/新创建/最近更新），
        // 文案复用旧页排序菜单既有 i18n 键（零新键）
        _sortTitleKeys = @[@"i18n_str_162", @"i18n_str_2061", @"i18n_str_2035", @"i18n_str_2064", @"i18n_str_2033"];
    }
    return self;
}

- (instancetype)initWithFavorites {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _assetType = ZL2AssetSearchTypeMod;   // 占位（收藏模式按项内 projectType 分流）
        _pageTitle = @"收藏";
        _favoritesMode = YES;
        _results = [NSMutableArray array];
        _chipControls = [NSMutableArray array];
        _chipLabels = [NSMutableArray array];
        _searchQuery = @"";
        _sortField = @"relevance";
        _hasMore = NO;
        _hasSearched = YES;   // 收藏直出，不走网络搜索态
        _currentOffset = 0;
        _requestGeneration = 0;
        _inputGeneration = 0;
        _sortValues = @[];
        _sortTitleKeys = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // 旧页 targetProfileName 同款：打开页面瞬间快照当前选中实例
    // （DownloadViewController.m L695-701；下载完成回调统一用快照，防切实例错写）
    self.lockedProfileName = PLProfiles.current.selectedProfileName;

    [self buildViews];
    [self ame_applyChipAppearance];
    [self ame_refreshEmptyAndLoading];

    if (self.favoritesMode) {
        [self ame_reloadFavorites];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame_favoritesDidChange:)
                                                     name:ZL2FavoritesDidChangeNotification
                                                   object:nil];
    }
}

- (void)dealloc {
    if (self.favoritesMode) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    // 无 timer（防抖走 dispatch_after + 代际号自失效）；
    // IconLoader 对 imageView 弱引用，无需手动取消
}

#pragma mark - 类型派生表

// PLPreferences / projectType 口径令牌（旧页 currentAPIForTabType 同款键名）
- (NSString *)ame_typeToken {
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:          return @"mod";
        case ZL2AssetSearchTypeModpack:      return @"modpack";
        case ZL2AssetSearchTypeResourcePack: return @"resourcepack";
        case ZL2AssetSearchTypeWorld:        return @"world";
        case ZL2AssetSearchTypeShader:       return @"shader";
    }
    return @"mod";
}

// 搜索框占位（按类型区分中文文案，任务规格）
- (NSString *)ame_placeholderText {
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:          return @"搜索模组";
        case ZL2AssetSearchTypeModpack:      return @"搜索整合包";
        case ZL2AssetSearchTypeResourcePack: return @"搜索资源包";
        case ZL2AssetSearchTypeWorld:        return @"搜索存档";
        case ZL2AssetSearchTypeShader:       return @"搜索光影包";
    }
    return @"搜索";
}

// 引导空态文案（初始未搜索时，ZL2 式引导）
- (NSString *)ame_guideText {
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:          return @"搜索你感兴趣的模组";
        case ZL2AssetSearchTypeModpack:      return @"搜索你感兴趣的整合包";
        case ZL2AssetSearchTypeResourcePack: return @"搜索你感兴趣的资源包";
        case ZL2AssetSearchTypeWorld:        return @"搜索你感兴趣的存档";
        case ZL2AssetSearchTypeShader:       return @"搜索你感兴趣的光影包";
    }
    return @"输入关键词开始搜索";
}

// 类型符号（与 ZL2DownloadViewController categorySymbols 同表，SF1.0 档）
- (NSString *)ame_guideSymbol {
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:          return @"puzzlepiece";
        case ZL2AssetSearchTypeModpack:      return @"archivebox";
        case ZL2AssetSearchTypeResourcePack: return @"paintbrush";
        case ZL2AssetSearchTypeWorld:        return @"globe";
        case ZL2AssetSearchTypeShader:       return @"lightbulb";
    }
    return @"magnifyingglass";
}

// API 来源口径（旧页 apiSourceForType:/currentAPIForTabType: 等价：
// world 强制 CurseForge——Modrinth 无 project_type:world facet；
// 其余按 PLPreferences 下载源偏好；1=Modrinth 2=CurseForge）
- (NSInteger)ame_apiSourceForType {
    if (self.assetType == ZL2AssetSearchTypeWorld) return 2;
    NSString *source = [PLPreferences currentDownloadSourceForType:[self ame_typeToken]];
    return [source isEqualToString:@"curseforge"] ? 2 : 1;
}

- (id)ame_searchAPI {
    return ([self ame_apiSourceForType] == 2) ? (id)[CurseForgeAPI sharedInstance]
                                              : (id)[ModrinthAPI sharedInstance];
}

// 旧页 currentProfileMinecraftVersion 等价移植（L2643-2650，不链接旧页本体）：
// selectedProfile.lastVersionId → ModpackExportService.parseVersionId → minecraft
- (NSString *)ame_profileMinecraftVersion {
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    NSString *lastVersionId = profile[@"lastVersionId"];
    if (![lastVersionId isKindOfClass:[NSString class]] || lastVersionId.length == 0) return nil;
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    return parsed[@"minecraft"];
}

// 旧页 currentProfileLoader 等价移植（L2654-2661）
- (NSString *)ame_profileLoader {
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    NSString *lastVersionId = profile[@"lastVersionId"];
    if (![lastVersionId isKindOfClass:[NSString class]] || lastVersionId.length == 0) return nil;
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    return parsed[@"loader"];
}

#pragma mark - Layout

- (void)buildViews {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ① M3 胶囊搜索框（surfaceContainerHigh 底 / radiusXL / 高 44；高 44 +
    //    圆角 28 渲染为全圆胶囊，任务规格）+ 右侧 40×40 排序入口钮
    _searchCapsule = [[UIView alloc] init];
    _searchCapsule.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _searchCapsule.layer.cornerRadius = [ZL2Theme radiusXL];
    _searchCapsule.layer.masksToBounds = YES;
    _searchCapsule.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_searchCapsule];

    UIImage *searchIcon = ZL2AssetSystemImage(@"magnifyingglass", @"search");
    UIImageView *searchIconView = [[UIImageView alloc] initWithImage:[searchIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    searchIconView.tintColor = [ZL2Theme onSurfaceVariant];
    searchIconView.contentMode = UIViewContentModeScaleAspectFit;
    searchIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchCapsule addSubview:searchIconView];

    _searchField = [[UITextField alloc] init];
    _searchField.placeholder = [self ame_placeholderText];
    _searchField.font = [ZL2Theme fontBodyLarge];
    _searchField.textColor = [ZL2Theme onSurface];
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.delegate = self;
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.accessibilityLabel = [self ame_placeholderText];
    [_searchField addTarget:self
                     action:@selector(ame_searchTextChanged:)
           forControlEvents:UIControlEventEditingChanged];
    [_searchCapsule addSubview:_searchField];

    // 排序/过滤入口（40×40 surfaceContainer radiusS；点击展开/收起排序 chips 行）
    _sortToggleControl = [[UIControl alloc] init];
    _sortToggleControl.backgroundColor = [ZL2Theme surfaceContainer];
    _sortToggleControl.layer.cornerRadius = [ZL2Theme radiusS];
    _sortToggleControl.translatesAutoresizingMaskIntoConstraints = NO;
    _sortToggleControl.isAccessibilityElement = YES;
    _sortToggleControl.accessibilityLabel = @"排序方式";
    _sortToggleControl.accessibilityTraits = UIAccessibilityTraitButton;
    [_sortToggleControl addTarget:self
                           action:@selector(ame_sortToggleTapped)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_sortToggleControl];

    UIImage *sortIcon = ZL2AssetSystemImage(@"arrow.up.arrow.down", @"line.3.horizontal");
    UIImageView *sortIconView = [[UIImageView alloc] initWithImage:[sortIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    sortIconView.tintColor = [ZL2Theme onSurfaceVariant];
    sortIconView.contentMode = UIViewContentModeScaleAspectFit;
    sortIconView.translatesAutoresizingMaskIntoConstraints = NO;
    sortIconView.userInteractionEnabled = NO;
    [_sortToggleControl addSubview:sortIconView];

    // ② 排序 chips 横排行（默认收起；结构照抄 ZL2DownloadViewController chips 行）
    _chipsScroll = [[UIScrollView alloc] init];
    _chipsScroll.showsHorizontalScrollIndicator = NO;
    _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _chipsScroll.hidden = YES;
    [self.view addSubview:_chipsScroll];

    _chipsStack = [[UIStackView alloc] init];
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.spacing = 8;
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_chipsScroll addSubview:_chipsStack];

    for (NSUInteger i = 0; i < self.sortValues.count; i++) {
        [_chipsStack addArrangedSubview:[self ame_sortChipAtIndex:i]];
    }

    // ③ 结果列表（UITableView + 自绘 M3 卡 cell，支持滚到底自动分页）
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 100;
    _tableView.estimatedRowHeight = 0;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.accessibilityLabel = @"搜索结果";
    [self.view addSubview:_tableView];
    [_tableView registerClass:[ZL2AssetResultCell class] forCellReuseIdentifier:@"ZL2AssetResultCell"];

    // ④ 空态（初始引导 / 无结果；ZL2Versions 空态同款手法：图标 68pt + 文案）
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

    // ⑤ 加载指示（ZL2 Searching 态 LinearWavyProgressIndicator 的 iOS14 等价物）
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.color = [ZL2Theme primary];
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingIndicator];

    NSLayoutConstraint *chipsHeight = [_chipsScroll.heightAnchor constraintEqualToConstant:0];
    self.chipsHeightConstraint = chipsHeight;

    [NSLayoutConstraint activateConstraints:@[
        [_searchCapsule.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_searchCapsule.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_searchCapsule.heightAnchor constraintEqualToConstant:44],

        [_sortToggleControl.leadingAnchor constraintEqualToAnchor:_searchCapsule.trailingAnchor constant:8],
        [_sortToggleControl.centerYAnchor constraintEqualToAnchor:_searchCapsule.centerYAnchor],
        [_sortToggleControl.widthAnchor constraintEqualToConstant:40],
        [_sortToggleControl.heightAnchor constraintEqualToConstant:40],
        [_sortToggleControl.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [searchIconView.leadingAnchor constraintEqualToAnchor:_searchCapsule.leadingAnchor constant:16],
        [searchIconView.centerYAnchor constraintEqualToAnchor:_searchCapsule.centerYAnchor],
        [searchIconView.widthAnchor constraintEqualToConstant:18],
        [searchIconView.heightAnchor constraintEqualToConstant:18],

        [_searchField.leadingAnchor constraintEqualToAnchor:searchIconView.trailingAnchor constant:10],
        [_searchField.trailingAnchor constraintEqualToAnchor:_searchCapsule.trailingAnchor constant:-12],
        [_searchField.topAnchor constraintEqualToAnchor:_searchCapsule.topAnchor],
        [_searchField.bottomAnchor constraintEqualToAnchor:_searchCapsule.bottomAnchor],

        [_chipsScroll.topAnchor constraintEqualToAnchor:_searchCapsule.bottomAnchor constant:4],
        [_chipsScroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_chipsScroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        chipsHeight,

        [_tableView.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

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

        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor],
    ]];

    // chips 行内容四边钉定（首尾 +16 内边距，与搜索行对齐）
    UILayoutGuide *chipsLG = _chipsScroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_chipsStack.leadingAnchor constraintEqualToAnchor:chipsLG.leadingAnchor constant:16],
        [chipsLG.trailingAnchor constraintEqualToAnchor:_chipsStack.trailingAnchor constant:16],
        [_chipsStack.topAnchor constraintEqualToAnchor:chipsLG.topAnchor constant:4],
        [chipsLG.bottomAnchor constraintEqualToAnchor:_chipsStack.bottomAnchor constant:4],
    ]];
}

// 单枚排序 chip（ZL2DownloadViewController ame_chipAtIndex 同款规格：
// 高 32 / 水平内边距 16 / radiusS / fontLabelMedium；无图标纯文字）
- (UIControl *)ame_sortChipAtIndex:(NSUInteger)index {
    UIControl *chip = [[UIControl alloc] init];
    chip.backgroundColor = [ZL2Theme surfaceContainer];
    chip.layer.cornerRadius = [ZL2Theme radiusS];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    // tag 仅作 ame_sortChipTapped: 的排序下标载荷（不做 viewWithTag: 身份查找）
    chip.tag = (NSInteger)index;
    chip.isAccessibilityElement = YES;
    chip.accessibilityLabel = localize(self.sortTitleKeys[index], nil);
    chip.accessibilityTraits = UIAccessibilityTraitButton;

    UILabel *label = [[UILabel alloc] init];
    label.text = localize(self.sortTitleKeys[index], nil);
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [chip addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [chip.heightAnchor constraintEqualToConstant:32],
        [label.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-16],
    ]];

    [chip addTarget:self
             action:@selector(ame_sortChipTapped:)
   forControlEvents:UIControlEventTouchUpInside];

    [_chipControls addObject:chip];
    [_chipLabels addObject:label];
    return chip;
}

- (void)ame_applyChipAppearance {
    NSInteger selected = [self.sortValues indexOfObject:self.sortField ?: @""];
    for (NSUInteger i = 0; i < self.chipControls.count; i++) {
        BOOL isSelected = ((NSInteger)i == selected);
        UIControl *chip = self.chipControls[i];
        chip.backgroundColor = isSelected ? [ZL2Theme primaryContainer]
                                          : [ZL2Theme surfaceContainer];
        self.chipLabels[i].textColor = isSelected ? [ZL2Theme onPrimaryContainer]
                                                  : [ZL2Theme onSurfaceVariant];
        chip.accessibilityTraits = UIAccessibilityTraitButton |
                                   (isSelected ? UIAccessibilityTraitSelected : 0);
    }
}

#pragma mark - 收藏模式（7.0-UI-14：收藏仓库直出 + 全链同构复用）

- (void)ame_reloadFavorites {
    [self.results removeAllObjects];
    for (NSDictionary *snapshot in [[ZL2FavoritesStore sharedStore] allFavorites]) {
        // 快照 → 搜索结果同形字典（openResult 全链直接消费）
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"apiSource"] = snapshot[@"platform"] ?: @(1);
        item[@"id"] = snapshot[@"projectId"] ?: @"";
        item[@"title"] = snapshot[@"title"] ?: @"";
        item[@"description"] = snapshot[@"description"] ?: @"";
        item[@"imageUrl"] = snapshot[@"imageUrl"] ?: @"";
        item[@"author"] = snapshot[@"author"] ?: @"";
        item[@"downloads"] = snapshot[@"downloads"] ?: @0;
        item[@"projectType"] = snapshot[@"projectType"] ?: @"mod";
        item[@"isModpack"] = @([item[@"projectType"] isEqualToString:@"modpack"]);
        [self.results addObject:item];
    }
    [self.tableView reloadData];
    [self ame_refreshEmptyAndLoading];
}

- (void)ame_favoritesDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame_reloadFavorites];
    });
}

#pragma mark - 搜索触发（return 键 + 0.5s 防抖文本变化）

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self ame_triggerSearchWithQuery:(textField.text ?: @"")];
    return YES;
}

- (void)ame_searchTextChanged:(UITextField *)textField {
    // 0.5s 防抖（任务规格）：代际号失效旧回调，停止输入 0.5s 后自动触发
    NSString *text = textField.text ?: @"";
    self.inputGeneration += 1;
    NSInteger gen = self.inputGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen != self.inputGeneration) return;   // 0.5s 内又有输入
        if ([text isEqualToString:self.searchQuery ?: @""]) return;   // 内容未变不重搜
        [self ame_triggerSearchWithQuery:text];
    });
}

- (void)ame_sortToggleTapped {
    // 展开/收起排序 chips 行（高度 0 ↔ 40 平滑收展）
    self.chipsExpanded = !self.chipsExpanded;
    self.chipsScroll.hidden = NO;   // 收起态高度 0，无视觉占位
    self.chipsHeightConstraint.constant = self.chipsExpanded ? 40 : 0;
    [UIView animateWithDuration:0.18 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)ame_sortChipTapped:(UIControl *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.sortValues.count) return;
    NSString *next = self.sortValues[index];
    if ([next isEqualToString:self.sortField ?: @""]) return;
    self.sortField = next;
    [self ame_applyChipAppearance];
    // 已有搜索词时立即按新排序重搜；引导态仅记住选择
    if (self.hasSearched) {
        [self ame_triggerSearchWithQuery:(self.searchQuery ?: @"")];
    }
}

- (void)ame_triggerSearchWithQuery:(NSString *)query {
    self.searchQuery = query ?: @"";
    self.hasSearched = YES;
    self.requestGeneration += 1;   // 新搜索使在途响应过期
    [self ame_loadListWithReset:YES];
}

#pragma mark - 数据加载（旧页 loadXxxList 语义等价移植）

- (void)ame_loadListWithReset:(BOOL)reset {
    if (reset) {
        self.currentOffset = 0;
        self.hasMore = YES;
        [self.results removeAllObjects];
        [self.tableView reloadData];
        [self ame_refreshEmptyAndLoading];
    }
    if (self.inFlight) {
        // 请求期间防重入（任务规格）：记住 latest-wins，当前请求收尾后自动补发
        if (reset) self.pendingSearchAfterFlight = YES;
        return;
    }

    // 存档 tab 门控（旧页 loadWorldList L2420-2431 同款：CurseForge 源不可用
    // 时空态拦截；Task162 口径——key 仅官方直连需要）
    if (self.assetType == ZL2AssetSearchTypeWorld && ![CurseForgeAPI isSourceAvailable]) {
        self.inFlight = NO;
        [self ame_showEmptyStateWithIcon:@"globe" fallback:@"globe.fill"
                                    text:localize(@"i18n_str_185", nil)];
        [self.loadingIndicator stopAnimating];
        return;
    }

    self.inFlight = YES;
    [self ame_refreshEmptyAndLoading];

    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @(ZL2AssetSearchPageSize);
    filters[@"offset"] = @(self.currentOffset);
    if (self.searchQuery.length > 0) {
        filters[@"query"] = self.searchQuery;
    }
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:
            // projectType 缺省 = mod（旧页 loadModList 不发该键，L2029-2044）
            break;
        case ZL2AssetSearchTypeModpack:
            // 旧页 loadModpackList L2191-2213：isModpack + projectType 双保险
            filters[@"isModpack"] = @YES;
            filters[@"projectType"] = @"modpack";
            break;
        case ZL2AssetSearchTypeResourcePack:
            filters[@"projectType"] = @"resourcepack";
            break;
        case ZL2AssetSearchTypeWorld:
            filters[@"projectType"] = @"world";
            break;
        case ZL2AssetSearchTypeShader:
            filters[@"projectType"] = @"shader";
            break;
    }
    if (self.sortField.length > 0) {
        filters[@"sort"] = self.sortField;
    }

    NSInteger gen = self.requestGeneration;
    __weak typeof(self) weakSelf = self;
    id api = [self ame_searchAPI];
    [api searchModWithFilters:filters
                   completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.inFlight = NO;

            // 过期响应防护：发起后搜索词/排序已变更（generation 已递增）直接丢弃；
            // 若期间有新搜索排队（latest-wins）则补发
            if (gen != strongSelf.requestGeneration) {
                if (strongSelf.pendingSearchAfterFlight) {
                    strongSelf.pendingSearchAfterFlight = NO;
                    [strongSelf ame_loadListWithReset:YES];
                }
                return;
            }

            if (results) {
                if (strongSelf.currentOffset == 0) {
                    [strongSelf.results removeAllObjects];
                }
                [strongSelf.results addObjectsFromArray:results];
                strongSelf.hasMore = ((NSInteger)results.count >= ZL2AssetSearchPageSize);
                strongSelf.currentOffset += (NSInteger)results.count;
                [strongSelf.tableView reloadData];
            } else if (error) {
                [strongSelf ame_showError:error.localizedDescription];
            }
            [strongSelf ame_refreshEmptyAndLoading];

            if (strongSelf.pendingSearchAfterFlight) {
                strongSelf.pendingSearchAfterFlight = NO;
                [strongSelf ame_loadListWithReset:YES];
            }
        });
    }];
}

#pragma mark - UITableView DataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZL2AssetResultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2AssetResultCell"
                                                             forIndexPath:indexPath];
    NSDictionary *item = (indexPath.row < (NSInteger)self.results.count) ? self.results[indexPath.row] : nil;
    if (item) {
        NSString *symbol = [self ame_guideSymbol];
        [cell ame_configureWithData:item
                    placeholderName:symbol
                     fallbackSymbol:[symbol stringByAppendingString:@".fill"]];
    }
    // 收藏心形（7.0-UI-14：搜索卡与收藏页共用 toggle，写入 ZL2FavoritesStore）
    {
        NSString *pid = item[@"id"] ?: @"";
        NSInteger source = [item[@"apiSource"] isKindOfClass:NSNumber.class]
            ? [item[@"apiSource"] integerValue] : [self ame_apiSourceForType];
        BOOL fav = [[ZL2FavoritesStore sharedStore] isFavoritePlatform:source projectId:pid];
        [cell ame_setFavorite:fav];
    }
    __weak typeof(self) weakSelf = self;
    NSInteger row = indexPath.row;
    cell.onDownload = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf ame_openResultAtIndex:row];
    };
    cell.onFavorite = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *entry = strongSelf.results[row];
        if (![entry isKindOfClass:[NSDictionary class]]) return;
        NSMutableDictionary *snapshot = [entry mutableCopy];
        NSInteger source = [entry[@"apiSource"] isKindOfClass:NSNumber.class]
            ? [entry[@"apiSource"] integerValue] : [strongSelf ame_apiSourceForType];
        snapshot[@"platform"] = @(source);
        snapshot[@"projectId"] = entry[@"id"] ?: @"";
        [[ZL2FavoritesStore sharedStore] toggleFavoriteWithProject:snapshot];
    };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self ame_openResultAtIndex:indexPath.row];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // 滚到底自动加载下一页（旧页 hasMoreXxx/loadXxxList 语义，临近底部 3 行预触发）
    if (self.hasMore && !self.inFlight && self.results.count > 0 &&
        indexPath.row >= (NSInteger)self.results.count - 3) {
        [self ame_loadListWithReset:NO];
    }
    // 图标预取（旧页 prefetchIconsForTableView 同款：后续 5 个 cell 图标进缓存）
    for (NSInteger row = indexPath.row + 1; row <= indexPath.row + 5; row++) {
        if (row >= (NSInteger)self.results.count) break;
        NSDictionary *item = self.results[row];
        NSString *iconUrl = item[@"imageUrl"];
        if (![iconUrl isKindOfClass:[NSString class]] || iconUrl.length == 0) iconUrl = item[@"icon_url"];
        if ([iconUrl isKindOfClass:[NSString class]] && iconUrl.length > 0) {
            [IconLoader prefetchIconWithURL:iconUrl targetSize:CGSizeMake(56, 56)];
        }
    }
}

#pragma mark - 结果卡点击 → 版本页（1:1 复刻旧页各类型配置）

- (void)ame_openResultAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.results.count) return;
    NSDictionary *dict = self.results[index];

    // 项内 apiSource 优先（收藏模式按快照平台分流；搜索模式两平台同源）
    NSInteger itemSource = [dict[@"apiSource"] isKindOfClass:NSNumber.class]
        ? [dict[@"apiSource"] integerValue] : [self ame_apiSourceForType];

    switch (self.assetType) {
        case ZL2AssetSearchTypeMod: {
            // 旧页 downloadModAtIndexPath:（L5274-5292）1:1
            ModItem *modItem = [[ModItem alloc] initWithOnlineData:dict];
            ModVersionViewController *versionVC = [[ModVersionViewController alloc] init];
            versionVC.modItem = modItem;
            versionVC.delegate = self;
            versionVC.title = modItem.displayName;
            versionVC.apiSource = itemSource;
            versionVC.preferredGameVersion = [self ame_profileMinecraftVersion];
            versionVC.preferredLoader = [self ame_profileLoader];
            [self ame_pushViewController:versionVC];
            break;
        }
        case ZL2AssetSearchTypeModpack: {
            // 旧页 installModpackAtIndexPath:（L4712-4735）1:1：模组版版本页复用，
            // pendingDownloadType="modpack" + pendingModpackDict 分流安装流
            ModItem *modItem = [[ModItem alloc] initWithOnlineData:dict];
            ModVersionViewController *versionVC = [[ModVersionViewController alloc] init];
            versionVC.modItem = modItem;
            versionVC.delegate = self;
            versionVC.title = modItem.displayName;
            versionVC.apiSource = itemSource;
            versionVC.preferredGameVersion = [self ame_profileMinecraftVersion];
            versionVC.preferredLoader = [self ame_profileLoader];
            self.pendingDownloadType = @"modpack";
            self.pendingModpackDict = dict;
            [self ame_pushViewController:versionVC];
            break;
        }
        case ZL2AssetSearchTypeResourcePack: {
            // 旧页 downloadResourcepackAtIndexPath:（L5324-5353）1:1
            ResourcePackItem *item = [[ResourcePackItem alloc] initWithOnlineData:dict];
            self.pendingDownloadType = @"resourcepack";
            self.pendingResourcePackItem = item;
            AssetVersionViewController *versionVC = [[AssetVersionViewController alloc] init];
            versionVC.assetType = AssetVersionTypeResourcePack;
            versionVC.projectID = item.onlineID;
            versionVC.apiSource = itemSource;
            versionVC.projectDisplayName = item.displayName;
            versionVC.delegate = self;
            versionVC.title = item.displayName;
            versionVC.projectIconURL = item.iconURL;
            versionVC.projectAuthor = item.author;
            versionVC.projectDownloads = item.downloads;
            versionVC.projectLikes = item.likes;
            versionVC.projectDescription = item.resourcePackDescription;
            versionVC.projectCategories = item.categories;
            versionVC.projectLastUpdated = item.lastUpdated;
            versionVC.preferredGameVersion = [self ame_profileMinecraftVersion];
            [self ame_pushViewController:versionVC];
            break;
        }
        case ZL2AssetSearchTypeWorld: {
            // 旧页 downloadWorldAtIndexPath:（L5396-5425）1:1：世界强制 CurseForge
            WorldItem *item = [[WorldItem alloc] initWithOnlineData:dict];
            self.pendingDownloadType = @"world";
            self.pendingWorldItem = item;
            AssetVersionViewController *versionVC = [[AssetVersionViewController alloc] init];
            versionVC.assetType = AssetVersionTypeWorld;
            versionVC.projectID = item.onlineID;
            versionVC.apiSource = 2;
            versionVC.projectDisplayName = item.displayName;
            versionVC.delegate = self;
            versionVC.title = item.displayName;
            versionVC.projectIconURL = item.iconURL;
            versionVC.projectAuthor = item.author;
            versionVC.projectDownloads = item.downloads;
            versionVC.projectLikes = item.likes;
            versionVC.projectDescription = item.worldDescription;
            versionVC.projectCategories = item.categories;
            versionVC.projectLastUpdated = item.lastUpdated;
            versionVC.preferredGameVersion = [self ame_profileMinecraftVersion];
            [self ame_pushViewController:versionVC];
            break;
        }
        case ZL2AssetSearchTypeShader: {
            // 旧页 downloadShaderAtIndexPath:（L5299-5317）1:1
            ShaderItem *shaderItem = [[ShaderItem alloc] initWithOnlineData:dict];
            ShaderVersionViewController *versionVC = [[ShaderVersionViewController alloc] init];
            versionVC.shaderItem = shaderItem;
            versionVC.delegate = self;
            versionVC.title = shaderItem.displayName;
            versionVC.apiSource = itemSource;
            versionVC.preferredGameVersion = [self ame_profileMinecraftVersion];
            versionVC.preferredLoader = [self ame_profileLoader];
            [self ame_pushViewController:versionVC];
            break;
        }
    }
}

// 宿主 nav push；无 nav 宿主（预览 harness 直嵌）时 present 包 nav 兜底（任务规格）
- (void)ame_pushViewController:(UIViewController *)viewController {
    if (self.navigationController) {
        [self.navigationController pushViewController:viewController animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:viewController];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

// 选完版本 pop 回本页（旧页 L5452/L5475 等同款；无 nav 时消息落空安全）
- (void)ame_popVersionPage {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - ModVersionViewControllerDelegate（模组 + 整合包复用分流）

// 旧页 modVersionViewController:didSelectVersion:（L5439-5560）等价移植
- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version {
    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self ame_showError:localize(@"i18n_str_265", nil)];
        return;
    }

    // 整合包走独立安装流程（下载+解析+原版预装+导入），与普通 Mod 下载不同
    if ([self.pendingDownloadType isEqualToString:@"modpack"]) {
        NSDictionary *modpack = self.pendingModpackDict;
        self.pendingDownloadType = nil;
        self.pendingModpackDict = nil;
        // 子页面已 push 到导航栈，选完版本后 pop 回搜索列表
        [self ame_popVersionPage];
        [self ame_startModpackInstallation:version modpack:modpack];
        return;
    }

    ModItem *itemToDownload = viewController.modItem;
    itemToDownload.selectedVersionDownloadURL = primaryFile[@"url"];
    itemToDownload.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.jar", itemToDownload.displayName];
    itemToDownload.fileSHA1 = ZL2AssetSha1FromPrimaryFile(primaryFile);

    self.pendingDownloadType = nil;

    // 子页面已 push 到导航栈，选完版本后 pop 回搜索列表
    [self ame_popVersionPage];

    // ★ Task227（旧页 L5469-5560 1:1）：下载前依赖解析 + 双源 + PCL2CE 确认单。
    //   ① ModDependencyResolver 递归解析必需/可选前置（双源归一）；
    //   ② 有必需前置 → 确认单【一起安装前置 / 仅安装本体】；
    //   ③ 选"一起安装" → 串行下载前置到同一 mods 目录，全部结束后再下主模组。
    __weak typeof(self) weakSelf = self;
    NSString *profileName = self.lockedProfileName ?: @"default";
    [[ModDependencyResolver sharedResolver] resolveDependenciesFromVersionDetail:version.rawDictionary
                                                                       apiSource:version.apiSource
                                                            installedProjectIds:nil
                                                                          loader:[self ame_profileLoader]
                                                                     gameVersion:[self ame_profileMinecraftVersion]
                                                                      completion:^(ModDependencyPlan *plan, NSError *ame227_err) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSArray<ModDependencyItem *> *ame227_deps = plan.required ?: @[];
        NSLog(@"[ZL2AssetSearch] Task227 dep-resolve: %@ -> %lu required / %lu optional / %lu truncated (err=%@)",
              itemToDownload.displayName,
              (unsigned long)ame227_deps.count, (unsigned long)plan.optional.count,
              (unsigned long)plan.truncated.count, ame227_err.localizedDescription ?: @"none");
        if (ame227_deps.count == 0) {
            [strongSelf ame_startDownloadForModItem:itemToDownload];
            return;
        }
        // ③.5 依赖名 enrichment（双源各自的项目名接口；失败回退 projectId；
        // 旧页 1.8s dispatch_after 兜底为空操作，此处不复制）
        dispatch_group_t ame227_titleGroup = dispatch_group_create();
        for (ModDependencyItem *ame227_dep in ame227_deps) {
            dispatch_group_enter(ame227_titleGroup);
            void (^ame227_storeTitle)(NSString *) = ^(NSString *ame227_title) {
                ame227_dep.displayName = ame227_title ?: ame227_dep.projectId;
                dispatch_group_leave(ame227_titleGroup);
            };
            if (ame227_dep.apiSource == 1) {
                [[ModrinthAPI sharedInstance] ame227_fetchProjectTitle:ame227_dep.projectId
                                                            completion:^(NSString * _Nullable title, NSError * _Nullable err) {
                    ame227_storeTitle(title);
                }];
            } else {
                [[CurseForgeAPI sharedInstance] ame227_fetchModTitle:ame227_dep.projectId
                                                          completion:^(NSString * _Nullable title, NSError * _Nullable err) {
                    ame227_storeTitle(title);
                }];
            }
        }
        dispatch_group_notify(ame227_titleGroup, dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return;
            NSMutableString *ame227_list = [NSMutableString string];
            for (ModDependencyItem *ame227_dep in ame227_deps) {
                [ame227_list appendFormat:@"\u2022 %@\n", ame227_dep.displayName ?: ame227_dep.projectId];
            }
            if (plan.optional.count > 0) {
                [ame227_list appendString:localize(@"ame227.deps.optional_note", nil)];
            }
            UIAlertController *ame227_sheet = [UIAlertController
                alertControllerWithTitle:localize(@"ame227.deps.title", nil)
                                 message:[NSString stringWithFormat:localize(@"ame227.deps.message", nil),
                                            itemToDownload.displayName, ame227_list]
                          preferredStyle:UIAlertControllerStyleAlert];
            [ame227_sheet addAction:[UIAlertAction
                actionWithTitle:localize(@"ame227.deps.only_mod", nil)
                          style:UIAlertActionStyleCancel
                        handler:^(UIAlertAction * _Nonnull action) {
                [strongSelf2 ame_startDownloadForModItem:itemToDownload];
            }]];
            [ame227_sheet addAction:[UIAlertAction
                actionWithTitle:localize(@"ame227.deps.install_all", nil)
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction * _Nonnull action) {
                [strongSelf2 ame227_installDependencies:ame227_deps
                                              toProfile:profileName
                                             completion:^{
                    [strongSelf2 ame_startDownloadForModItem:itemToDownload];
                }];
            }]];
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                ame227_sheet.popoverPresentationController.sourceView = strongSelf2.view;
                ame227_sheet.popoverPresentationController.sourceRect =
                    CGRectMake(strongSelf2.view.bounds.size.width / 2.0,
                               strongSelf2.view.bounds.size.height / 2.0, 1.0, 1.0);
            }
            [strongSelf2 presentViewController:ame227_sheet animated:YES completion:nil];
        });
    }];
}

// 旧页 startDownloadForModItem:（L5606-5631）等价移植：
// 进度由 Service 内部注册的下载任务 + 统一进度页驱动，调用方只做收尾提示
- (void)ame_startDownloadForModItem:(ModItem *)item {
    NSString *profileName = self.lockedProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ModService sharedService] downloadMod:item
                                  toProfile:profileName
                               expectedSHA1:item.fileSHA1
                                   progress:nil
                                 completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf ame_showError:error.localizedDescription];
                return;
            }
            [strongSelf ame_showSuccess:[NSString stringWithFormat:localize(@"i18n_str_266", nil), item.displayName]];
        });
    }];
}

// 旧页 ame227_installDependencies:toProfile:completion:（L5637-5740）1:1 移植：
// 前置串行安装（单失败不中断，最后汇总）；挑选链从严到宽（Task230 口径）：
// ① 版本+加载器双匹配 ② 仅加载器 ③ 仅版本（标记 loaderMismatch）④ 全失配跳过
- (void)ame227_installDependencies:(NSArray<ModDependencyItem *> *)deps
                         toProfile:(NSString *)profileName
                        completion:(void (^)(void))completion {
    if (deps.count == 0) {
        if (completion) completion();
        return;
    }
    NSMutableArray<ModDependencyItem *> *remaining = [deps mutableCopy];
    NSMutableArray<NSString *> *failures = [NSMutableArray new];

    __block void (^nextStep)(void) = nil;
    __weak typeof(self) weakSelf = self;
    nextStep = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (remaining.count == 0) {
            if (failures.count > 0) {
                NSLog(@"[ZL2AssetSearch] Task227 %lu dependency(ies) failed: %@",
                      (unsigned long)failures.count, [failures componentsJoinedByString:@", "]);
            } else {
                NSLog(@"[ZL2AssetSearch] Task227 all %lu required dependencies installed", (unsigned long)deps.count);
            }
            if (completion) completion();
            return;
        }
        ModDependencyItem *dep = remaining.firstObject;
        [remaining removeObjectAtIndex:0];

        void (^pickAndDownload)(NSArray<ModVersion *> *, NSError *) = ^(NSArray<ModVersion *> *versions, NSError *error) {
            __strong typeof(weakSelf) strongSelfPick = weakSelf;
            if (!strongSelfPick) return;
            ModVersion *picked = nil;
            NSString *ame227_gv = [strongSelfPick ame_profileMinecraftVersion];
            NSString *ame230_loader = [strongSelfPick ame_profileLoader];
            BOOL (^ame230_loaderOK)(ModVersion *) = ^BOOL(ModVersion *v) {
                if (ame230_loader.length == 0 || v.loaders.count == 0) return YES;
                NSString *ame230_lower = ame230_loader.lowercaseString;
                for (NSString *l in v.loaders) {
                    if ([[l lowercaseString] containsString:ame230_lower] ||
                        [ame230_lower containsString:[l lowercaseString]]) return YES;
                }
                return NO;
            };
            ModVersion *ame230_loaderOnly = nil;
            ModVersion *ame230_gvOnly = nil;
            for (ModVersion *v in versions) {
                BOOL ame230_gvOK = (ame227_gv.length == 0) || [v.gameVersions containsObject:ame227_gv];
                BOOL ame230_ldOK = ame230_loaderOK(v);
                if (ame230_gvOK && ame230_ldOK) { picked = v; break; }
                if (ame230_ldOK && ame230_loaderOnly == nil) ame230_loaderOnly = v;
                if (ame230_gvOK && ame230_gvOnly == nil) ame230_gvOnly = v;
            }
            BOOL ame230_loaderMismatch = NO;
            if (picked == nil) picked = ame230_loaderOnly;   // ② 仅加载器匹配
            if (picked == nil) { picked = ame230_gvOnly; ame230_loaderMismatch = (picked != nil); }  // ③ 仅版本匹配
            if (picked == nil && versions.count > 0) {       // ④ 全失配：跳过，不装错加载器
                NSLog(@"[ZL2AssetSearch] Task230 dep skipped (no version matches loader=%@ gv=%@): %@",
                      ame230_loader, ame227_gv, dep.projectId);
                [failures addObject:[NSString stringWithFormat:@"%@ (loader mismatch)", dep.projectId ?: @"?"]];
                nextStep();
                return;
            }
            if (ame230_loaderMismatch) {
                NSLog(@"[ZL2AssetSearch] Task230 dep loader-mismatch fallback (loader=%@ has no matching build; installing gv-matched %@)",
                      ame230_loader, picked.name);
            }
            NSDictionary *pf = picked.primaryFile;
            if (error || ![pf[@"url"] isKindOfClass:[NSString class]]) {
                [failures addObject:dep.projectId ?: @"?"];
                nextStep();
                return;
            }
            ModItem *depItem = [[ModItem alloc] init];
            depItem.displayName = picked.name ?: dep.projectId;
            depItem.fileName = pf[@"filename"] ?: [NSString stringWithFormat:@"%@.jar", dep.projectId];
            depItem.selectedVersionDownloadURL = pf[@"url"];
            depItem.fileSHA1 = ZL2AssetSha1FromPrimaryFile(pf);
            [[ModService sharedService] downloadMod:depItem
                                          toProfile:profileName
                                       expectedSHA1:depItem.fileSHA1
                                           progress:nil
                                         completion:^(NSError * _Nullable dlError) {
                if (dlError) [failures addObject:dep.projectId ?: @"?"];
                nextStep();
            }];
        };

        if (dep.apiSource == 1) {
            [[ModrinthAPI sharedInstance] getVersionsForModWithID:dep.projectId completion:pickAndDownload];
        } else {
            [[CurseForgeAPI sharedInstance] getVersionsForModWithID:dep.projectId completion:pickAndDownload];
        }
    };
    nextStep();
}

#pragma mark - ShaderVersionViewControllerDelegate

// 旧页 shaderVersionViewController:didSelectVersion:（L5816-5833）等价移植
- (void)shaderVersionViewController:(ShaderVersionViewController *)viewController didSelectVersion:(ShaderVersion *)version {
    ShaderItem *itemToDownload = viewController.shaderItem;

    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self ame_showError:localize(@"i18n_str_265", nil)];
        return;
    }

    itemToDownload.selectedVersionDownloadURL = primaryFile[@"url"];
    itemToDownload.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.zip", itemToDownload.displayName];
    itemToDownload.fileSHA1 = ZL2AssetSha1FromPrimaryFile(primaryFile);

    // 子页面已 push 到导航栈，选完版本后 pop 回搜索列表
    [self ame_popVersionPage];
    [self ame_startDownloadForShaderItem:itemToDownload];
}

// 旧页 startDownloadForShaderItem:（L5837-5857）等价移植
- (void)ame_startDownloadForShaderItem:(ShaderItem *)item {
    NSString *profileName = self.lockedProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ShaderService sharedService] downloadShader:item
                                        toProfile:profileName
                                     expectedSHA1:item.fileSHA1
                                         progress:nil
                                       completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf ame_showError:error.localizedDescription];
            } else {
                [strongSelf ame_showSuccess:[NSString stringWithFormat:localize(@"i18n_str_266", nil), item.displayName]];
            }
        });
    }];
}

#pragma mark - AssetVersionViewControllerDelegate（资源包 / 存档分流）

// 旧页 assetVersionViewController:didSelectVersion:（L5564-5602）等价移植
- (void)assetVersionViewController:(AssetVersionViewController *)viewController didSelectVersion:(ModVersion *)version {
    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self ame_showError:localize(@"i18n_str_265", nil)];
        return;
    }

    NSString *downloadType = self.pendingDownloadType;
    self.pendingDownloadType = nil;

    // 子页面已 push 到导航栈，选完版本后 pop 回搜索列表
    [self ame_popVersionPage];

    if ([downloadType isEqualToString:@"resourcepack"]) {
        ResourcePackItem *item = self.pendingResourcePackItem;
        self.pendingResourcePackItem = nil;
        if (!item) return;
        item.selectedVersionDownloadURL = primaryFile[@"url"];
        item.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.zip", item.displayName];
        item.fileSHA1 = ZL2AssetSha1FromPrimaryFile(primaryFile);
        [self ame_startDownloadForResourcePackItem:item];
    } else if ([downloadType isEqualToString:@"world"]) {
        WorldItem *item = self.pendingWorldItem;
        self.pendingWorldItem = nil;
        if (!item) return;
        item.selectedVersionDownloadURL = primaryFile[@"url"];
        [self ame_startDownloadForWorldItem:item];
    }
}

// 旧页 startDownloadForResourcePackItem:（L5742-5762）等价移植
- (void)ame_startDownloadForResourcePackItem:(ResourcePackItem *)item {
    NSString *profileName = self.lockedProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ResourcePackService sharedService] downloadResourcePack:item
                                                    toProfile:profileName
                                                 expectedSHA1:item.fileSHA1
                                                     progress:nil
                                                   completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success && !error) {
                [strongSelf ame_showSuccess:[NSString stringWithFormat:localize(@"i18n_str_267", nil), item.displayName]];
            } else {
                [strongSelf ame_showError:error.localizedDescription ?: localize(@"i18n_str_268", nil)];
            }
        });
    }];
}

// 旧页 startDownloadForWorldItem:（L5793-5812）等价移植
- (void)ame_startDownloadForWorldItem:(WorldItem *)item {
    NSString *profileName = self.lockedProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[WorldService sharedService] downloadWorld:item
                                      toProfile:profileName
                                       progress:nil
                                     completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success && !error) {
                [strongSelf ame_showSuccess:[NSString stringWithFormat:localize(@"i18n_str_271", nil), item.displayName]];
            } else {
                [strongSelf ame_showError:error.localizedDescription ?: localize(@"i18n_str_272", nil)];
            }
        });
    }];
}

#pragma mark - 整合包安装流（旧页 startModpackInstallation:modpack: L4737-4946 1:1）

// zip 下载（3 次重试 / 1.5s 退避）→ 6 阶段任务注册（autoPresentDetail 自动弹
// 统一进度页）→ 解析 → 原版预装 → 导入。阶段映射：0=解析整合包(含 zip 下载)
// 1=解压文件(parse 内部完成) 2=下载依赖文件 3=安装加载器 4=下载游戏文件(原版预装) 5=完成配置
- (void)ame_startModpackInstallation:(ModVersion *)version modpack:(NSDictionary *)modpack {
    NSString *downloadURL = version.primaryFile[@"url"];
    if (!downloadURL) {
        [self ame_showError:localize(@"i18n_str_254", nil)];
        return;
    }

    NSURL *url = [NSURL URLWithString:downloadURL];
    // Task218：来源标签收敛到 PLMirrorCenter（整合包下载任务）
    NSString *downloadSource = [PLMirrorCenter legacySourceTokenForType:PLMirrorResourceTypeAssetDownload];
    __block DownloadTaskItem *taskItem = nil;

    // 关键修复（参照 FCL/ZL2 整合包下载容错）：单次下载无重试会因网络偶发
    // 抖动/镜像 5xx 整体失败——最多 3 次重试（旧页同款）。
    __block NSInteger downloadAttempt = 0;
    __block NSURL *downloadLocation = nil;
    __block NSError *downloadError = nil;
    __weak typeof(self) weakSelf = self;

    // Task231：递归（失败重试）block 必须 __block——非 __block 自引用捕获
    // 赋值前的 nil（ARC 零初始化），重试分支 nil->invoke EXC_BAD_ACCESS（旧页同款判例）
    __block void (^attemptDownload)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        downloadAttempt++;
        NSLog(@"[ModpackDownload] Modpack download attempt %ld: %@", (long)downloadAttempt, downloadURL);
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf2 = weakSelf;
                if (!strongSelf2) return;
                if (error || !location) {
                    downloadError = error ?: [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Download returned empty data"}];
                    NSLog(@"[ModpackDownload] Attempt %ld failed: %@", (long)downloadAttempt, downloadError.localizedDescription);
                    if (downloadAttempt < 3) {
                        // 间隔 1.5s 后重试，避免连续请求触发限流
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            attemptDownload();
                        });
                    } else {
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                 stageAtIndex:0
                                                                     status:PLTaskStageStatusFailed];
                        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:downloadError];
                        [strongSelf2 ame_showError:[NSString stringWithFormat:@"Modpack download failed (retried %ld times): %@",
                                                    (long)downloadAttempt, downloadError.localizedDescription ?: @"Unknown error"]];
                    }
                    return;
                }
                downloadLocation = location;
                downloadError = nil;

                // 移动到临时文件
                NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"%@_%@.mrpack", modpack[@"id"] ?: @"modpack", [[NSUUID UUID] UUIDString]]];
                [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
                NSError *moveError = nil;
                [[NSFileManager defaultManager] moveItemAtPath:downloadLocation.path toPath:tempPath error:&moveError];
                if (moveError) {
                    if (downloadAttempt < 3) {
                        NSLog(@"[ModpackDownload] File move failed, retrying: %@", moveError.localizedDescription);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            attemptDownload();
                        });
                        return;
                    }
                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                             stageAtIndex:0
                                                                 status:PLTaskStageStatusFailed];
                    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:moveError];
                    [strongSelf2 ame_showError:moveError.localizedDescription];
                    return;
                }

                // zip 下载完成 → 进入解析阶段（任务整体保持 Downloading，导入完成才标记 Completed）
                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                         stageAtIndex:0
                                                             progress:-1
                                                              message:localize(@"i18n_str_255", nil)];
                ModpackImportService *importService = [[ModpackImportService alloc] init];
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    NSError *parseError = nil;
                    NSDictionary *modpackInfo = [importService parseModpackAtURL:[NSURL fileURLWithPath:tempPath] error:&parseError];
                    if (!modpackInfo) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:0
                                                                         status:PLTaskStageStatusFailed];
                            [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:parseError];
                            [weakSelf ame_showError:parseError.localizedDescription ?: localize(@"i18n_str_256", nil)];
                        });
                        return;
                    }
                    // 用在线 modpack 信息补充（title、icon 等）
                    NSMutableDictionary *mutableInfo = [modpackInfo mutableCopy];
                    if (!mutableInfo[@"name"] || [mutableInfo[@"name"] isEqualToString:[tempPath.lastPathComponent stringByDeletingPathExtension]]) {
                        mutableInfo[@"name"] = modpack[@"title"] ?: mutableInfo[@"name"];
                    }
                    if (modpack[@"imageUrl"]) {
                        // 不强制下载 icon，保留原整合包内的（旧页同款注释）
                    }

                    // 阶段14增强（参照 FCL/ZL2/HMCL）：安装整合包前先安装对应的原版
                    // Minecraft——否则启动时 Java 端 Tools.getVersionInfo() 因
                    // FileNotFoundException 崩溃（旧页同款）
                    NSString *mcVersion = mutableInfo[@"minecraftVersion"];
                    if (![mcVersion isKindOfClass:[NSString class]] || mcVersion.length == 0) {
                        mcVersion = mutableInfo[@"dependencies"][@"minecraft"];
                    }
                    if ([mcVersion isKindOfClass:[NSString class]] && mcVersion.length > 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            __strong typeof(weakSelf) strongSelf3 = weakSelf;
                            if (!strongSelf3) return;
                            // 解析 + 解压完成，进入原版预装（阶段4 下载游戏文件）
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:0 status:PLTaskStageStatusCompleted];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:1 status:PLTaskStageStatusCompleted];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:4 status:PLTaskStageStatusRunning];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:4
                                                                         progress:-1
                                                                          message:[NSString stringWithFormat:localize(@"i18n_str_257", nil), mcVersion]];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:4];

                            // 原版预装（已安装则直接跳过）
                            NSDictionary *vanillaVersion = @{@"id": mcVersion};
                            [strongSelf3 ame_ensureVanillaInstalled:vanillaVersion completion:^(BOOL vanillaSuccess) {
                                __strong typeof(weakSelf) strongSelf4 = weakSelf;
                                if (!strongSelf4) return;
                                if (!vanillaSuccess) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                                 stageAtIndex:4
                                                                                     status:PLTaskStageStatusFailed];
                                        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId
                                                                          completedWithError:[NSError errorWithDomain:@"DownloadError" code:-1
                                                                                                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_258", nil), mcVersion]}]];
                                        [strongSelf4 ame_showError:[NSString stringWithFormat:localize(@"i18n_str_194", nil), mcVersion]];
                                    });
                                    return;
                                }
                                // 原版安装完成，继续导入整合包（进入阶段2 下载依赖文件）
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                             stageAtIndex:4 status:PLTaskStageStatusCompleted];
                                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                             stageAtIndex:2 status:PLTaskStageStatusRunning];
                                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                             stageAtIndex:2
                                                                                 progress:-1
                                                                                message:localize(@"i18n_str_259", nil)];
                                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:2];
                                });
                                // 在后台线程执行整合包导入
                                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                                    [weakSelf ame_importModpackWithService:importService info:mutableInfo taskId:taskItem.taskId tempPath:tempPath];
                                });
                            }];
                        });
                    } else {
                        // 无法提取游戏版本，跳过原版预安装（阶段4 标记 Skipped），直接导入
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:0 status:PLTaskStageStatusCompleted];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:1 status:PLTaskStageStatusCompleted];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:4 status:PLTaskStageStatusSkipped];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                     stageAtIndex:2 status:PLTaskStageStatusRunning];
                            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:2];
                        });
                        [weakSelf ame_importModpackWithService:importService info:mutableInfo taskId:taskItem.taskId tempPath:tempPath];
                    }
                });
            });
        }];

        // 注册到下载任务管理器（每次重试均重新注册，taskId 不变因 taskItem 是外层 __block）
        if (!taskItem) {
            taskItem = [[DownloadTaskManager sharedManager]
                registerTaskWithResourceType:DownloadTaskResourceTypeModpack
                                resourceName:modpack[@"title"] ?: @"modpack"
                                 displayName:modpack[@"title"] ?: localize(@"i18n_str_118", nil)
                              downloadSource:downloadSource
                                     rawTask:task
                              supportsResume:YES
                                     iconURL:modpack[@"imageUrl"]];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesModpack()];
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                     stageAtIndex:0
                                                         status:PLTaskStageStatusRunning];
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                     stageAtIndex:0
                                                         progress:-1
                                                          message:localize(@"i18n_str_260", nil)];
            taskItem.autoPresentDetail = YES;
            [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId state:DownloadTaskStateDownloading];
        }

        [task resume];
    };

    // 启动首次下载尝试
    attemptDownload();
}

// 阶段14：整合包导入辅助（旧页 importModpackWithService:info:taskId:tempPath:
// L4955-5034 1:1）。应在后台线程调用；进度区间：0.1-0.3=下载mods(阶段2)，
// 0.3-0.7=安装加载器(阶段3)，0.7-1.0=写配置(阶段5)。
- (void)ame_importModpackWithService:(ModpackImportService *)importService
                                info:(NSDictionary *)info
                              taskId:(NSString *)taskId
                            tempPath:(NSString *)tempPath {
    NSError *importError = nil;
    __weak typeof(self) weakSelf = self;
    BOOL success = [importService importModpack:info
                                       progress:^(double p, NSString *stage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
            if (p < 0.3) {
                // 阶段2 下载依赖文件进行中
                [manager updateTaskWithId:taskId
                             stageAtIndex:2
                                 progress:p / 0.3
                                  message:stage];
            } else if (p < 0.7) {
                // 阶段2 完成，阶段3 安装加载器进行中
                [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId
                             stageAtIndex:3
                                 progress:(p - 0.3) / 0.4
                                  message:stage];
                [manager updateTaskWithId:taskId currentStageIndex:3];
            } else if (p < 1.0) {
                // 阶段3 完成，阶段5 完成配置进行中
                [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId
                             stageAtIndex:5
                                 progress:(p - 0.7) / 0.3
                                  message:stage];
                [manager updateTaskWithId:taskId currentStageIndex:5];
            } else {
                // 全部阶段完成
                [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId stageAtIndex:5 status:PLTaskStageStatusCompleted];
            }
        });
    } error:&importError];

    // 清理临时文件
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
        if (success) {
            [manager setTaskWithId:taskId completedWithError:nil];
            // 关键修复（Task 72，"找不到版本信息"根因）：整合包在线安装成功后
            // 必须补发 ReloadProfileList——版本卡片列表扫描快照不含刚写入的
            // 唯一化版本（旧页 L5007-5018 同款）
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
            NSLog(@"[ModpackImport] Task72 ReloadProfileList posted after online modpack install");
            NSString *loader = info[@"loader"];
            NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_261", nil), info[@"name"]];
            if ([loader isEqualToString:@"Forge"] || [loader isEqualToString:@"NeoForge"]) {
                msg = [msg stringByAppendingFormat:localize(@"i18n_str_262", nil), loader, info[@"loaderVersion"]];
            }
            [strongSelf ame_showSuccess:msg];
        } else {
            // 失败时将当前运行中的阶段（2/3/5）标记为 Failed
            [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusFailed];
            [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusFailed];
            [manager updateTaskWithId:taskId stageAtIndex:5 status:PLTaskStageStatusFailed];
            [manager setTaskWithId:taskId completedWithError:importError];
            [strongSelf ame_showError:importError.localizedDescription ?: localize(@"i18n_str_263", nil)];
        }
    });
}

// 旧页 ensureVanillaInstalled:completion:（L3161-3286）+ ensureVanillaVersionJSONExists:
// （L3111-3152）合并等价移植：JSON 缺失时走 ForgeDirectInstaller.ensureParentVersionExists
// （与 Forge 直装/ModpackImportService 同一条已验证路径），再 MinecraftResourceDownloadTask
// 下载完整原版（轮询等待，进度页由任务内部阶段上报自动弹出）
- (void)ame_ensureVanillaInstalled:(NSDictionary *)version completion:(void (^)(BOOL success))completion {
    if (![version isKindOfClass:[NSDictionary class]]) {
        if (completion) completion(NO);
        return;
    }
    NSString *versionId = version[@"id"];
    if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) {
        if (completion) completion(NO);
        return;
    }

    // 用 POJAV_GAME_DIR（与 MinecraftResourceDownloadTask 一致），而非 POJAV_HOME
    NSString *gameDir = @(getenv("POJAV_GAME_DIR"));
    if (gameDir.length == 0) {
        gameDir = @(getenv("POJAV_HOME"));
    }
    NSString *versionJsonPath = [gameDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];

    // 精细化跳过（旧页同款）：JSON 存在不代表安装完整——client.jar 缺失则继续
    // 预装补全；MinecraftResourceDownloadTask 对已存在且 SHA1 正确的文件自动跳过
    if ([NSFileManager.defaultManager fileExistsAtPath:versionJsonPath]) {
        NSString *clientJarPath = [[gameDir stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"versions/%@", versionId]]
                                   stringByAppendingPathComponent:
                                   [NSString stringWithFormat:@"%@.jar", versionId]];
        if ([NSFileManager.defaultManager fileExistsAtPath:clientJarPath]) {
            NSLog(@"[ZL2AssetSearch] Vanilla %@ already installed (JSON + jar exist), skip preinstall", versionId);
            if (completion) completion(YES);
            return;
        }
        NSLog(@"[ZL2AssetSearch] Vanilla %@ JSON exists but client.jar missing, resuming preinstall", versionId);
    }

    NSLog(@"[ZL2AssetSearch] Vanilla %@ not installed, preinstalling...", versionId);

    // 1. 确保 version JSON 存在（Task70 收敛路径：PLMirrorCenter GameFile 候选 + 重试）
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *fetchError = nil;
        BOOL ok = [ForgeDirectInstaller ensureParentVersionExists:versionId error:&fetchError];
        if (!ok) {
            NSLog(@"[ZL2AssetSearch] ensureVanillaVersionJSONExists: %@ failed: %@",
                  versionId, fetchError.localizedDescription ?: @"unknown");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO);
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) {
                if (completion) completion(NO);
                return;
            }

            // 2. 创建下载任务（进度页由任务内部阶段上报自动弹出）
            MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
            task.maxRetryCount = 3;
            s.vanillaPreinstallTask = task;

            task.handleError = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) ss = weakSelf;
                    if (!ss) return;
                    ss.vanillaPreinstallTask = nil;
                    if (completion) completion(NO);
                });
            };

            // 3. 后台线程启动下载 + 轮询等待完成（最长 30 分钟；旧页同款——
            //    downloadVersion: 内部 prepareForDownload 会重建 progress，KVO 会悬空，
            //    轮询访问最新 progress.finished 才可靠）
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                __strong typeof(weakSelf) ss2 = weakSelf;
                if (!ss2) {
                    if (completion) completion(NO);
                    return;
                }
                MinecraftResourceDownloadTask *waitTask = ss2.vanillaPreinstallTask;
                [waitTask downloadVersion:version];

                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
                BOOL succeeded = NO;
                while ([deadline timeIntervalSinceNow] > 0) {
                    NSProgress *p = waitTask.progress;
                    if (p && p.finished) {
                        succeeded = !p.cancelled;
                        break;
                    }
                    [NSThread sleepForTimeInterval:0.5];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) ss3 = weakSelf;
                    if (!ss3) return;
                    ss3.vanillaPreinstallTask = nil;
                    if (completion) completion(succeeded);
                });
            });
        });
    });
}

#pragma mark - 空态 / 加载 / 提示

// 空态派生：初始未搜索 → 类型引导；已搜索无结果 → 类型无结果文案；
// 结果非空 → 隐藏。加载指示仅在"加载中且无结果"时显示（分页追加不打断列表）
- (void)ame_refreshEmptyAndLoading {
    BOOL hasResults = (self.results.count > 0);
    if (!hasResults) {
        if (!self.hasSearched) {
            NSString *symbol = [self ame_guideSymbol];
            [self ame_showEmptyStateWithIcon:symbol
                                    fallback:[symbol stringByAppendingString:@".fill"]
                                        text:[self ame_guideText]];
        } else {
            NSString *key = nil;
            switch (self.assetType) {
                case ZL2AssetSearchTypeMod:          key = @"i18n_str_180"; break;   // 暂无模组
                case ZL2AssetSearchTypeModpack:      key = @"i18n_str_182"; break;   // 暂无整合包
                case ZL2AssetSearchTypeResourcePack: key = @"i18n_str_183"; break;   // 暂无资源包
                case ZL2AssetSearchTypeWorld:        key = @"i18n_str_186"; break;   // 暂无世界
                case ZL2AssetSearchTypeShader:       key = @"i18n_str_181"; break;   // 暂无光影
            }
            [self ame_showEmptyStateWithIcon:@"magnifyingglass" fallback:@"search"
                                        text:localize(key, nil)];
        }
    } else {
        self.emptyContainer.hidden = YES;
    }

    if (self.inFlight && !hasResults) {
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
    }
}

- (void)ame_showEmptyStateWithIcon:(NSString *)symbol fallback:(NSString *)fallback text:(NSString *)text {
    // 68pt 矢量渲染（UIImageSymbolConfiguration 为 iOS13 档 API，部署目标 14.0 内；
    // 符号名异常时降级旧名 + 默认点尺寸兜底）
    UIImage *icon = [UIImage systemImageNamed:symbol
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:68]];
    if (!icon) icon = ZL2AssetSystemImage(symbol, fallback);
    self.emptyIconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.emptyLabel.text = text;
    self.emptyContainer.hidden = NO;
}

// 旧页 showError:/showSuccessMessage: 同款 InlineMessageView（错误红/成功绿）
- (void)ame_showError:(NSString *)message {
    [InlineMessageView showInViewController:self
                                      title:localize(@"i18n_str_42", nil)
                                   message:message
                                      type:InlineMessageTypeError];
}

- (void)ame_showSuccess:(NSString *)message {
    [InlineMessageView showInViewController:self
                                      title:localize(@"i18n_str_253", nil)
                                   message:message
                                      type:InlineMessageTypeSuccess];
}

@end
