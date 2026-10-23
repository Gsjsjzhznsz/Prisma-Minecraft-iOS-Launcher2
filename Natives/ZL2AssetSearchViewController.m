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
// 【ZL2 视觉来源】SearchAssetsScreen.kt（右栏筛选语义）、_Search.Result.kt
//   （结果卡：card 底 shape large + 72dp 图标 + 标题|作者 / 描述 / 标签行 /
//   下载量 / 收藏）、_Search.Filter.kt + PlatformSortField.kt（排序五档真实
//   值域：relevance/downloads/follows/newest/updated；文案复用旧页既有 i18n
//   键）。7.0-UI-16 真机截图对齐重排：进门即搜（空关键词第 1 页浏览态）+
//   右栏筛选面板（搜索名称/游戏版本/导入整合包/目标平台/排序方式）+ 页码
//   控制器（PageController "N / M" 整页替换，两平台搜索响应 total 驱动）。
//
// 【红线】颜色/字体/圆角一律 ZL2Theme；iOS 14 API 上限；SF1.0 档符号 +
//   fallback；新建视图 translatesAutoresizingMaskIntoConstraints=NO；
//   无 viewWithTag 状态查找（chip.tag 仅作下标载荷）；中文文案硬编码/
//   既有 i18n 键复用（新文案入表为既有待办口径）。
//

#import "ZL2AssetSearchViewController.h"
#import "ZL2Theme.h"
#import "utils.h"
#import <objc/runtime.h>  // Task316：分类弹层 option→slug 关联对象
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
#import "ZL2M3Kit.h"
#import "ZL2VersionIndex.h"
#import "ModpackImportViewController.h"

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
@property (nonatomic, assign) NSUInteger lastSearchTotalCount;
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
@property (nonatomic, assign) NSUInteger lastSearchTotalCount;
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
// 格式化下载量数字（7.0-UI-16：ZL2 中文量级对齐——真机截图 1.9万/112万/137万；
// 旧 K/M 为英文社区口径，与 ZL2 上游不符）
static NSString *ZL2AssetFormatTrimZero(NSString *text) {
    if ([text hasSuffix:@".0"]) {
        return [text substringToIndex:text.length - 2];
    }
    return text;
}

static NSString *ZL2AssetFormatDownloadCount(NSNumber *downloads) {
    if (!downloads) return @"0";
    NSInteger dl = [downloads integerValue];
    if (dl >= 100000000) {
        NSString *raw = [NSString stringWithFormat:@"%.1f亿", dl / 100000000.0];
        return ZL2AssetFormatTrimZero(raw);
    }
    if (dl >= 10000) {
        NSString *raw = [NSString stringWithFormat:@"%.1f万", dl / 10000.0];
        return ZL2AssetFormatTrimZero(raw);
    }
    return [NSString stringWithFormat:@"%ld", (long)dl];
}

// 搜索结果分页页大小（旧页六类 loadXxxList 统一 @30；7.0-UI-16 页码控制器沿用，
// 整页替换语义下仍以"满页 30 条"判定 hasNext）
static NSInteger const ZL2AssetSearchPageSize = 30;

#pragma mark - 结果卡 Cell（7.0-UI-16：ZL2 _Search.Result 真机截图逐元素对齐）

// 卡片结构（用户上传 ZL2 真机截图 2026-10-22 像素级对齐）：
//   卡（surfaceContainer / radiusL / 内边距 12）
//   ├ 左图标 72×72 radiusM（ZL2 72dp 卡图；IconLoader 占位 → 异步真实图标）
//   ├ 标题行：名称（fontTitleMedium）+ " | 作者: X"（fontBodyMedium 次级色，
//   │  ZL2 "标题 | 作者: X" 单行同排；HorizontalStack 语义隐藏自收）
//   ├ 描述 2 行（fontBodyMedium / onSurfaceVariant）
//   ├ 标签行（categories 空格连接 / fontLabelMedium / onSurfaceVariant）
//   ├ 右上来源徽标（CurseForge 橙 / Modrinth 绿——平台品牌身份色，ZL2 上游
//   │  PlatformBadge 同口径；主题令牌体系外的例外，语义=平台识别非主题化 UI）
//   └ 右列：⬇ 下载量（万/亿中文量级）+ ♡ 收藏（FavoriteToggleLabel 语义）
//   旧版 56×56 图标 + 名称/作者/下载点赞三行形态由本形态取代（真机截图口径）。
@interface ZL2AssetResultCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UIView *sourceBadgeView;
@property (nonatomic, strong) UILabel *sourceBadgeLabel;
@property (nonatomic, strong) UIImageView *downloadsIconView;
@property (nonatomic, strong) UILabel *downloadsLabel;
@property (nonatomic, strong) UIControl *favoriteControl;
@property (nonatomic, strong) UIImageView *favoriteIconView;
@property (nonatomic, strong) UILabel *favoriteLabel;
@property (nonatomic, copy) void (^onFavorite)(void);

- (void)ame_configureWithData:(NSDictionary *)data
              placeholderName:(NSString *)symbolName
               fallbackSymbol:(NSString *)fallbackName;

@end

// 平台品牌徽标色（ZL2 上游 CurseForge #F16436 / Modrinth #02AF7C 对齐；
// 非主题令牌例外的依据见卡头注释）
static UIColor *ZL2AssetSourceBadgeColor(NSInteger apiSource) {
    if (apiSource == 2) {
        return [UIColor colorWithRed:0.945 green:0.392 blue:0.212 alpha:1.0];
    }
    return [UIColor colorWithRed:0.008 green:0.686 blue:0.486 alpha:1.0];
}

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

        // 标题行（HorizontalStack：名称压缩截断优先，作者行隐藏自收）
        UIStackView *titleStack = [[UIStackView alloc] init];
        titleStack.axis = UILayoutConstraintAxisHorizontal;
        titleStack.alignment = UIStackViewAlignmentCenter;
        titleStack.spacing = 6;
        titleStack.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:titleStack];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [ZL2Theme fontTitleMedium];
        _nameLabel.textColor = [ZL2Theme onSurface];
        _nameLabel.numberOfLines = 1;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [titleStack addArrangedSubview:_nameLabel];

        _authorLabel = [[UILabel alloc] init];
        _authorLabel.font = [ZL2Theme fontBodyMedium];
        _authorLabel.textColor = [ZL2Theme onSurfaceVariant];
        _authorLabel.numberOfLines = 1;
        _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [titleStack addArrangedSubview:_authorLabel];
        [_nameLabel setContentCompressionResistancePriority:749 forAxis:UILayoutConstraintAxisHorizontal];
        [_authorLabel setContentCompressionResistancePriority:750 forAxis:UILayoutConstraintAxisHorizontal];
        [_authorLabel setContentHuggingPriority:251 forAxis:UILayoutConstraintAxisHorizontal];

        _sourceBadgeView = [[UIView alloc] init];
        _sourceBadgeView.layer.cornerRadius = 10;
        _sourceBadgeView.layer.masksToBounds = YES;
        _sourceBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_sourceBadgeView];

        _sourceBadgeLabel = [[UILabel alloc] init];
        _sourceBadgeLabel.font = [ZL2Theme fontLabelMedium];
        _sourceBadgeLabel.textColor = [UIColor whiteColor];
        _sourceBadgeLabel.numberOfLines = 1;
        _sourceBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_sourceBadgeView addSubview:_sourceBadgeLabel];

        _descLabel = [[UILabel alloc] init];
        _descLabel.font = [ZL2Theme fontBodyMedium];
        _descLabel.textColor = [ZL2Theme onSurfaceVariant];
        _descLabel.numberOfLines = 2;
        _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_descLabel];

        _tagsLabel = [[UILabel alloc] init];
        _tagsLabel.font = [ZL2Theme fontLabelMedium];
        _tagsLabel.textColor = [ZL2Theme onSurfaceVariant];
        _tagsLabel.numberOfLines = 1;
        _tagsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_tagsLabel];

        // 右列（下载量 + 收藏，ZL2 卡右侧上下两行）
        _downloadsIconView = [[UIImageView alloc] init];
        _downloadsIconView.contentMode = UIViewContentModeScaleAspectFit;
        _downloadsIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _downloadsIconView.userInteractionEnabled = NO;
        [_cardView addSubview:_downloadsIconView];

        _downloadsLabel = [[UILabel alloc] init];
        _downloadsLabel.font = [ZL2Theme fontLabelLarge];
        _downloadsLabel.textColor = [ZL2Theme onSurface];
        _downloadsLabel.numberOfLines = 1;
        _downloadsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_downloadsLabel];

        _favoriteControl = [[UIControl alloc] init];
        _favoriteControl.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteControl.isAccessibilityElement = YES;
        _favoriteControl.accessibilityLabel = @"收藏";
        _favoriteControl.accessibilityTraits = UIAccessibilityTraitButton;
        [_favoriteControl addTarget:self
                             action:@selector(ame_favoriteTapped)
                   forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_favoriteControl];

        _favoriteIconView = [[UIImageView alloc] init];
        _favoriteIconView.contentMode = UIViewContentModeScaleAspectFit;
        _favoriteIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteIconView.userInteractionEnabled = NO;
        [_favoriteControl addSubview:_favoriteIconView];

        _favoriteLabel = [[UILabel alloc] init];
        _favoriteLabel.font = [ZL2Theme fontLabelMedium];
        _favoriteLabel.textColor = [ZL2Theme onSurfaceVariant];
        _favoriteLabel.numberOfLines = 1;
        _favoriteLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteLabel.userInteractionEnabled = NO;
        [_favoriteControl addSubview:_favoriteLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

            [_iconView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12],
            [_iconView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:72],
            [_iconView.heightAnchor constraintEqualToConstant:72],

            [_sourceBadgeView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10],
            [_sourceBadgeView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
            [_sourceBadgeView.heightAnchor constraintEqualToConstant:20],

            [_sourceBadgeLabel.leadingAnchor constraintEqualToAnchor:_sourceBadgeView.leadingAnchor constant:8],
            [_sourceBadgeLabel.trailingAnchor constraintEqualToAnchor:_sourceBadgeView.trailingAnchor constant:-8],
            [_sourceBadgeLabel.centerYAnchor constraintEqualToAnchor:_sourceBadgeView.centerYAnchor],

            [titleStack.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12],
            [titleStack.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:_downloadsLabel.leadingAnchor constant:-10],

            [_downloadsIconView.centerYAnchor constraintEqualToAnchor:_downloadsLabel.centerYAnchor],
            [_downloadsIconView.trailingAnchor constraintEqualToAnchor:_downloadsLabel.leadingAnchor constant:-4],
            [_downloadsIconView.widthAnchor constraintEqualToConstant:13],
            [_downloadsIconView.heightAnchor constraintEqualToConstant:13],
            [_downloadsLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14],
            [_downloadsLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],

            [_favoriteControl.topAnchor constraintEqualToAnchor:_downloadsLabel.bottomAnchor constant:12],
            [_favoriteControl.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],

            [_favoriteIconView.leadingAnchor constraintEqualToAnchor:_favoriteControl.leadingAnchor],
            [_favoriteIconView.centerYAnchor constraintEqualToAnchor:_favoriteControl.centerYAnchor],
            [_favoriteIconView.widthAnchor constraintEqualToConstant:14],
            [_favoriteIconView.heightAnchor constraintEqualToConstant:14],

            [_favoriteLabel.leadingAnchor constraintEqualToAnchor:_favoriteIconView.trailingAnchor constant:3],
            [_favoriteLabel.trailingAnchor constraintEqualToAnchor:_favoriteControl.trailingAnchor],
            [_favoriteLabel.centerYAnchor constraintEqualToAnchor:_favoriteControl.centerYAnchor],

            [_descLabel.topAnchor constraintEqualToAnchor:titleStack.bottomAnchor constant:5],
            [_descLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_downloadsLabel.leadingAnchor constant:-12],

            [_tagsLabel.topAnchor constraintEqualToAnchor:_descLabel.bottomAnchor constant:5],
            [_tagsLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [_tagsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_downloadsLabel.leadingAnchor constant:-12],
            [_tagsLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)ame_favoriteTapped {
    if (self.onFavorite) self.onFavorite();
}

- (void)ame_setFavorite:(BOOL)favorite {
    UIImage *heart = [UIImage systemImageNamed:(favorite ? @"heart.fill" : @"heart")];
    self.favoriteIconView.image = [heart imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.favoriteIconView.tintColor = favorite ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    self.favoriteLabel.text = @"收藏";
    self.favoriteLabel.textColor = favorite ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
    self.favoriteControl.accessibilityLabel = favorite ? @"取消收藏" : @"收藏";
}

// 旧页 cell 同款：高亮态压暗卡片（ZL2 Compose 的 ripple 等价物）
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardView.alpha = highlighted ? 0.7 : 1.0;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onFavorite = nil;
    [self ame_setFavorite:NO];
    self.nameLabel.text = nil;
    self.authorLabel.text = nil;
    self.authorLabel.hidden = NO;
    self.descLabel.text = nil;
    self.descLabel.hidden = NO;
    self.tagsLabel.text = nil;
    self.tagsLabel.hidden = NO;
    self.sourceBadgeLabel.text = nil;
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

    // 作者（ZL2 "标题 | 作者: X" 同排语义；CF/Modrinth 均补齐 author 键）
    NSString *author = data[@"author"];
    if ([author isKindOfClass:[NSString class]] && author.length > 0) {
        self.authorLabel.text = [NSString stringWithFormat:@"| 作者: %@", author];
        self.authorLabel.hidden = NO;
    } else {
        self.authorLabel.text = nil;
        self.authorLabel.hidden = YES;
    }

    // 描述（2 行截断，ZL2 卡描述行）
    NSString *desc = data[@"description"];
    if (![desc isKindOfClass:[NSString class]]) desc = @"";
    self.descLabel.text = desc;
    self.descLabel.hidden = (desc.length == 0);

    // 标签行（categories 空格连接；CF 侧暂无 id→名映射表，空数组整行隐藏）
    NSMutableString *tags = [NSMutableString string];
    NSArray *categories = data[@"categories"];
    if ([categories isKindOfClass:[NSArray class]]) {
        for (NSString *category in categories) {
            if (![category isKindOfClass:[NSString class]] || category.length == 0) continue;
            if (tags.length > 0) [tags appendString:@" "];
            [tags appendString:category];
        }
    }
    self.tagsLabel.text = tags;
    self.tagsLabel.hidden = (tags.length == 0);

    // 来源徽标（apiSource 项内优先：收藏快照/双源混排都能正确显示平台身份）
    NSInteger source = [data[@"apiSource"] isKindOfClass:[NSNumber class]]
        ? [data[@"apiSource"] integerValue] : 1;
    self.sourceBadgeView.backgroundColor = ZL2AssetSourceBadgeColor(source);
    self.sourceBadgeLabel.text = (source == 2) ? @"CurseForge" : @"Modrinth";

    // 下载量（ZL2 中文量级：⬇ 1.9万）
    UIImage *downloadsSymbol = ZL2AssetSystemImage(@"arrow.down", @"arrow.down");
    self.downloadsIconView.image = [downloadsSymbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.downloadsIconView.tintColor = [ZL2Theme onSurfaceVariant];
    self.downloadsLabel.text = ZL2AssetFormatDownloadCount(data[@"downloads"]);

    // 图标异步加载（IconLoader 72pt 对齐 ZL2 72dp 卡图；取消旧请求 → 占位 →
    // 双层缓存 → 降采样 → CDN 镜像 → 兜底；旧页 cell loadIconFromURL 同款二次校验）
    NSString *iconUrl = data[@"imageUrl"];
    if (![iconUrl isKindOfClass:[NSString class]] || iconUrl.length == 0) iconUrl = data[@"icon_url"];
    __weak typeof(self) weakSelf = self;
    [IconLoader loadIconForImageView:self.iconView
                                 URL:iconUrl
                         placeholder:placeholder
                            fallback:placeholder
                          targetSize:CGSizeMake(72, 72)
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

// 游戏版本选择弹层的数据源/委托（独立小类：主页面已是结果列表的
// dataSource/delegate，二表共存时按指针分流会让每个回调都长出 if 分叉，
// 内聚到 handler 更贴近 ZL2 版本筛选对话框的独立语义）
@interface ZL2VersionSheetHandler : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *allVersions;   // 全量版本号（去重去 latest-*）
@property (nonatomic, copy) NSString *filterText;                 // 弹层内搜索词
@property (nonatomic, weak) UITableView *table;
@property (nonatomic, copy) void (^onPick)(NSString *versionId);
- (void)reloadFilterWithText:(NSString *)text;
@end

@implementation ZL2VersionSheetHandler

- (NSArray<NSString *> *)ame_visibleVersions {
    NSString *needle = [self.filterText stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (needle.length == 0) return self.allVersions;
    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    for (NSString *version in self.allVersions) {
        if (!version) continue;
        if ([version localizedCaseInsensitiveContainsString:needle]) {
            [visible addObject:version];
        }
    }
    return visible;
}

- (void)reloadFilterWithText:(NSString *)text {
    self.filterText = text;
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self ame_visibleVersions].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2VersionSheetCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"ZL2VersionSheetCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.font = [ZL2Theme fontBodyLarge];
        cell.textLabel.textColor = [ZL2Theme onSurface];
    }
    NSArray<NSString *> *visible = [self ame_visibleVersions];
    if (indexPath.row < (NSInteger)visible.count) {
        cell.textLabel.text = visible[indexPath.row];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSArray<NSString *> *visible = [self ame_visibleVersions];
    if (indexPath.row >= (NSInteger)visible.count) return;
    if (self.onPick) self.onPick(visible[indexPath.row]);
}

@end

#pragma mark - 主页面

@interface ZL2AssetSearchViewController () <
    UITableViewDataSource, UITableViewDelegate,
    ModVersionViewControllerDelegate, ShaderVersionViewControllerDelegate,
    AssetVersionViewControllerDelegate>

// 构造入参（init 注入后只读）
@property (nonatomic, assign, readwrite) ZL2AssetSearchType assetType;
@property (nonatomic, copy, readwrite) NSString *pageTitle;

// 结果列表与空态
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyContainer;
@property (nonatomic, strong) UIImageView *emptyIconView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// 右侧筛选面板（7.0-UI-16：ZL2 SearchAssetsScreen 右栏真机对齐——
// 搜索名称 / 游戏版本 / 导入整合包 / 目标平台 / 排序方式）
@property (nonatomic, strong) UIView *filterPanel;
@property (nonatomic, strong) NSLayoutConstraint *panelWidthConstraint;   // 宽态 300
@property (nonatomic, strong) NSLayoutConstraint *tableToPanelConstraint; // 列表随面板收窄
@property (nonatomic, strong) ZL2M3SearchBar *nameSearchBar;
@property (nonatomic, strong) UIControl *versionFieldControl;
@property (nonatomic, strong) UILabel *versionFieldValueLabel;
@property (nonatomic, strong) UIButton *importButton;      // 整合包类型独有
@property (nonatomic, strong) UIControl *platformControl;
@property (nonatomic, strong) UIView *platformChipView;
@property (nonatomic, strong) UILabel *platformChipLabel;
@property (nonatomic, strong) UIControl *sortControl;
@property (nonatomic, strong) UIView *sortChipView;
@property (nonatomic, strong) UILabel *sortChipLabel;

// 页码控制器（ZL2 PageController：1 / 500 + 前后翻页，真机截图口径）
@property (nonatomic, strong) UIView *paginationBar;
@property (nonatomic, strong) UIButton *prevPageButton;
@property (nonatomic, strong) UIButton *nextPageButton;
@property (nonatomic, strong) UILabel *pageInfoLabel;

// 搜索状态
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, copy) NSString *sortField;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@property (nonatomic, assign) NSInteger currentOffset;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) BOOL hasSearched;
@property (nonatomic, assign) NSInteger requestGeneration;   // 过期响应防护（搜索词/排序变更即失效）
@property (nonatomic, assign) NSInteger inputGeneration;     // 0.5s 防抖代际
@property (nonatomic, assign) BOOL pendingSearchAfterFlight; // 请求期间到达的新搜索（latest-wins）

// 页码与筛选状态（7.0-UI-16）
@property (nonatomic, assign) NSInteger currentPage;         // 1-based 页码
@property (nonatomic, assign) NSUInteger knownTotalCount;    // 搜索响应 total；0 = 总数未知
@property (nonatomic, copy) NSString *gameVersionFilter;     // nil/空 = 不限版本
@property (nonatomic, assign) NSInteger platformOverride;    // 0=按下载源偏好 1=Modrinth 2=CurseForge
@property (nonatomic, strong) UIView *versionSheetContent;   // 版本选择弹层内容（展示期持有）
@property (nonatomic, strong) NSObject *sheetHandler;        // ZL2VersionSheetHandler（弹层期持有）
@property (nonatomic, copy) NSString *categoryFilter;         // Task316：分类 slug；nil/空 = 不限分类
@property (nonatomic, strong) UIControl *categoryFieldControl;// Task316：分类字段（ZL2 右栏同位）
@property (nonatomic, strong) UILabel *categoryFieldValueLabel;
@property (nonatomic, strong) UIView *categorySheetContent;   // 分类弹层内容（展示期持有）

// 排序值域（ZL2 PlatformSortField 真实值域 + 旧页既有 i18n 文案键）
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
        _searchQuery = @"";
        _sortField = @"relevance";   // ZL2 PlatformSearchFilter 缺省 RELEVANCE
        _hasMore = YES;
        _hasSearched = NO;
        _currentOffset = 0;
        _requestGeneration = 0;
        _inputGeneration = 0;
        _currentPage = 1;
        _knownTotalCount = 0;
        _platformOverride = 0;
        _gameVersionFilter = nil;
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
        _searchQuery = @"";
        _sortField = @"relevance";
        _hasMore = NO;
        _hasSearched = YES;   // 收藏直出，不走网络搜索态
        _currentOffset = 0;
        _requestGeneration = 0;
        _inputGeneration = 0;
        _currentPage = 1;
        _knownTotalCount = 0;
        _platformOverride = 0;
        _gameVersionFilter = nil;
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
    [self ame_applyFilterPanelAppearance];
    [self ame_refreshEmptyAndLoading];

    if (self.favoritesMode) {
        [self ame_reloadFavorites];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame_favoritesDidChange:)
                                                     name:ZL2FavoritesDidChangeNotification
                                                   object:nil];
        return;
    }

    // 7.0-UI-16 进门即搜（ZL2 语义：SearchXXXScreen 初始即拉第 1 页浏览列表，
    // 无需先输入关键词——空关键词 + relevance 排序 = 热门浏览态；旧实现的
    // "搜索你感兴趣的X" 引导空态即用户实测"模组什么都不显示"的直接来源）
    [self ame_triggerSearchWithQuery:@""];
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
    if (self.platformOverride != 0) return self.platformOverride;
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
    BOOL isSearchMode = !self.favoritesMode;

    // ① 右侧筛选面板（ZL2 SearchAssetsScreen 右栏真机对齐：搜索名称 /
    //    游戏版本 / 导入整合包 / 目标平台 / 排序方式；收藏页与窄屏整体隐藏）
    _filterPanel = [[UIView alloc] init];
    _filterPanel.backgroundColor = [UIColor clearColor];
    _filterPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_filterPanel];

    UIStackView *panelStack = [[UIStackView alloc] init];
    panelStack.axis = UILayoutConstraintAxisVertical;
    panelStack.alignment = UIStackViewAlignmentFill;
    panelStack.spacing = 10;
    panelStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_filterPanel addSubview:panelStack];

    // 搜索名称（ZL2M3SearchBar 组件复用：0.5s 防抖 + return 立即搜）
    _nameSearchBar = [[ZL2M3SearchBar alloc] init];
    _nameSearchBar.placeholder = localize(@"dl.asset.filter.name", nil);
    _nameSearchBar.accessibilityLabel = localize(@"dl.asset.filter.name", nil);
    [panelStack addArrangedSubview:_nameSearchBar];

    // 游戏版本字段（点开版本选择弹层；筛选生效时显示已选版本号）
    UIImage *magnifier = ZL2AssetSystemImage(@"magnifyingglass", @"search");
    UILabel *versionValueLabel = nil;
    _versionFieldControl = [self ame_panelFieldControlWithIcon:magnifier
                                                    valueLabel:&versionValueLabel];
    _versionFieldValueLabel = versionValueLabel;
    _versionFieldControl.isAccessibilityElement = YES;
    _versionFieldControl.accessibilityLabel = localize(@"dl.asset.filter.version", nil);
    _versionFieldControl.accessibilityTraits = UIAccessibilityTraitButton;
    [_versionFieldControl addTarget:self
                             action:@selector(ame_versionFieldTapped)
                   forControlEvents:UIControlEventTouchUpInside];
    [panelStack addArrangedSubview:_versionFieldControl];

    // 分类字段（Task316 ZL2 筛选同步：SearchModScreen 分类同位；slug 表见
    // ame_categoryTableForType，Modrinth categories facet / CurseForge categories=id）
    if (!self.favoritesMode) {
        UIImage *tagIcon = ZL2AssetSystemImage(@"tag", @"tag");
        UILabel *categoryValueLabel = nil;
        _categoryFieldControl = [self ame_panelFieldControlWithIcon:tagIcon
                                                         valueLabel:&categoryValueLabel];
        _categoryFieldValueLabel = categoryValueLabel;
        _categoryFieldControl.isAccessibilityElement = YES;
        _categoryFieldControl.accessibilityLabel = localize(@"dl.asset.filter.category", nil);
        _categoryFieldControl.accessibilityTraits = UIAccessibilityTraitButton;
        [_categoryFieldControl addTarget:self
                                  action:@selector(ame_categoryFieldTapped)
                        forControlEvents:UIControlEventTouchUpInside];
        [panelStack addArrangedSubview:_categoryFieldControl];
    }

    // 导入整合包（仅整合包类别展示，ZL2 SearchModPackScreen 同位按钮；
    // 1:1 复用旧页导入流：push ModpackImportViewController → 自带文件选择）
    if (self.assetType == ZL2AssetSearchTypeModpack) {
        _importButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _importButton.backgroundColor = [ZL2Theme surfaceContainer];
        _importButton.layer.cornerRadius = [ZL2Theme radiusM];
        _importButton.layer.masksToBounds = YES;
        _importButton.titleLabel.font = [ZL2Theme fontLabelLarge];
        [_importButton setTitle:localize(@"dl.asset.import", nil) forState:UIControlStateNormal];
        [_importButton setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
        _importButton.translatesAutoresizingMaskIntoConstraints = NO;
        _importButton.accessibilityLabel = localize(@"dl.asset.import", nil);
        [_importButton addTarget:self
                          action:@selector(ame_importTapped)
                forControlEvents:UIControlEventTouchUpInside];
        [panelStack addArrangedSubview:_importButton];
    }

    // 目标平台双行下拉（label + 平台品牌色 chip + chevron；存档强制 CurseForge 禁用）
    UIView *platformChipView = nil;
    UILabel *platformChipLabel = nil;
    _platformControl = [self ame_panelDropdownControlWithLabelText:localize(@"dl.asset.filter.platform", nil)
                                                          chipView:&platformChipView
                                                         chipLabel:&platformChipLabel];
    _platformChipView = platformChipView;
    _platformChipLabel = platformChipLabel;
    _platformControl.accessibilityLabel = localize(@"dl.asset.filter.platform", nil);
    [_platformControl addTarget:self
                         action:@selector(ame_platformTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [panelStack addArrangedSubview:_platformControl];
    if (self.assetType == ZL2AssetSearchTypeWorld) {
        _platformControl.userInteractionEnabled = NO;   // Modrinth 无 world facet（旧页口径）
        _platformControl.alpha = 0.5;
    }

    // 排序方式双行下拉（五档 PlatformSortField 与旧 chips 同值域）
    UIView *sortChipView = nil;
    UILabel *sortChipLabel = nil;
    _sortControl = [self ame_panelDropdownControlWithLabelText:localize(@"i18n_str_161", nil)
                                                      chipView:&sortChipView
                                                     chipLabel:&sortChipLabel];
    _sortChipView = sortChipView;
    _sortChipLabel = sortChipLabel;
    _sortControl.accessibilityLabel = localize(@"i18n_str_161", nil);
    [_sortControl addTarget:self
                     action:@selector(ame_sortTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [panelStack addArrangedSubview:_sortControl];

    // ② 页码控制器（ZL2 PageController："1 / 500" + 前后翻页；列表列顶部居中）
    _paginationBar = [[UIView alloc] init];
    _paginationBar.backgroundColor = [ZL2Theme surfaceContainer];
    _paginationBar.layer.cornerRadius = [ZL2Theme radiusS];
    _paginationBar.layer.masksToBounds = YES;
    _paginationBar.translatesAutoresizingMaskIntoConstraints = NO;
    _paginationBar.hidden = !isSearchMode;
    [self.view addSubview:_paginationBar];

    UIStackView *pageStack = [[UIStackView alloc] init];
    pageStack.axis = UILayoutConstraintAxisHorizontal;
    pageStack.alignment = UIStackViewAlignmentCenter;
    pageStack.spacing = 10;
    pageStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_paginationBar addSubview:pageStack];

    _prevPageButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *prevIcon = ZL2AssetSystemImage(@"chevron.left", @"chevron.left");
    [_prevPageButton setImage:[prevIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                     forState:UIControlStateNormal];
    _prevPageButton.tintColor = [ZL2Theme onSurface];
    _prevPageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _prevPageButton.accessibilityLabel = @"上一页";
    [_prevPageButton addTarget:self
                        action:@selector(ame_prevPageTapped)
              forControlEvents:UIControlEventTouchUpInside];
    [pageStack addArrangedSubview:_prevPageButton];
    [_prevPageButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [_prevPageButton.heightAnchor constraintEqualToConstant:32].active = YES;

    _pageInfoLabel = [[UILabel alloc] init];
    _pageInfoLabel.font = [ZL2Theme fontLabelLarge];
    _pageInfoLabel.textColor = [ZL2Theme onSurface];
    _pageInfoLabel.numberOfLines = 1;
    _pageInfoLabel.textAlignment = NSTextAlignmentCenter;
    _pageInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pageInfoLabel.text = @"第 1 页";
    [pageStack addArrangedSubview:_pageInfoLabel];

    _nextPageButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *nextIcon = ZL2AssetSystemImage(@"chevron.right", @"chevron.right");
    [_nextPageButton setImage:[nextIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                     forState:UIControlStateNormal];
    _nextPageButton.tintColor = [ZL2Theme onSurface];
    _nextPageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _nextPageButton.accessibilityLabel = @"下一页";
    [_nextPageButton addTarget:self
                        action:@selector(ame_nextPageTapped)
              forControlEvents:UIControlEventTouchUpInside];
    [pageStack addArrangedSubview:_nextPageButton];
    [_nextPageButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [_nextPageButton.heightAnchor constraintEqualToConstant:32].active = YES;

    // ③ 结果列表（UITableView + ZL2 真机卡 cell；页码语义整页替换，无滚动续载）
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 128;
    _tableView.estimatedRowHeight = 0;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.accessibilityLabel = @"搜索结果";
    [self.view addSubview:_tableView];
    [_tableView registerClass:[ZL2AssetResultCell class] forCellReuseIdentifier:@"ZL2AssetResultCell"];

    // ④ 空态（无结果 / 源不可用；进门即搜后不再有引导态）
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

    // ⑤ 加载指示（首页拉取期列表中心 spinner）
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.color = [ZL2Theme primary];
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingIndicator];

    // ⑥ 约束：列表列（左）+ 筛选面板（右 300pt，窄屏/收藏页整体让位）
    _panelWidthConstraint = [_filterPanel.widthAnchor constraintEqualToConstant:300];
    _tableToPanelConstraint = [_tableView.trailingAnchor constraintEqualToAnchor:_filterPanel.leadingAnchor constant:-4];
    _panelWidthConstraint.active = NO;
    _tableToPanelConstraint.active = NO;
    // 窄屏/收藏页的等宽兑底（面板隐藏时列表仍需确定 trailing；与
    // tableToPanel 不同时满足，低优先级自动让位不冲突）
    NSLayoutConstraint *tableTrailingFallback =
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8];
    tableTrailingFallback.priority = 500;

    UILayoutGuide *panelLG = _filterPanel.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_filterPanel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_filterPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_filterPanel.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor],

        [panelStack.topAnchor constraintEqualToAnchor:_filterPanel.topAnchor constant:4],
        [panelStack.leadingAnchor constraintEqualToAnchor:_filterPanel.leadingAnchor constant:6],
        [_filterPanel.trailingAnchor constraintEqualToAnchor:panelStack.trailingAnchor constant:6],
        [panelStack.bottomAnchor constraintLessThanOrEqualToAnchor:_filterPanel.bottomAnchor constant:-4],

        [_paginationBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_paginationBar.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_paginationBar.heightAnchor constraintEqualToConstant:40],

        [pageStack.topAnchor constraintEqualToAnchor:_paginationBar.topAnchor],
        [pageStack.bottomAnchor constraintEqualToAnchor:_paginationBar.bottomAnchor],
        [pageStack.leadingAnchor constraintEqualToAnchor:_paginationBar.leadingAnchor constant:12],
        [_paginationBar.trailingAnchor constraintEqualToAnchor:pageStack.trailingAnchor constant:12],

        [_tableView.topAnchor constraintEqualToAnchor:_paginationBar.bottomAnchor constant:6],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        _tableToPanelConstraint,
        tableTrailingFallback,
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

    // panelLG 未消费（字段内边距由 panelStack 四边钉定承担）；声明防未用告警
    (void)panelLG;

    // 面板可见性随容器宽度收敛（收藏页恒隐藏；窄屏让位全宽列表）
    [self ame_setFilterPanelVisible:(isSearchMode && self.view.bounds.size.width >= 560.0)];

    // 搜索名称回调（0.5s 防抖 + return 立即）
    __weak typeof(self) weakSelf = self;
    self.nameSearchBar.onTextChanged = ^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf ame_debouncedSearchText:(text ?: @"")];
    };
    self.nameSearchBar.onReturn = ^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf ame_triggerSearchWithQuery:(text ?: @"")];
    };
}

// 通用面板单行字段（图标右置 + 值文本，ZL2 右栏字段形态；高度 48）
- (UIControl *)ame_panelFieldControlWithIcon:(UIImage *)icon
                                  valueLabel:(UILabel **)outValue {
    UIControl *control = [[UIControl alloc] init];
    control.backgroundColor = [ZL2Theme surfaceContainerHigh];
    control.layer.cornerRadius = [ZL2Theme radiusM];
    control.layer.masksToBounds = YES;
    control.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [control addSubview:iconView];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font = [ZL2Theme fontBodyLarge];
    valueLabel.textColor = [ZL2Theme onSurfaceVariant];
    valueLabel.numberOfLines = 1;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.userInteractionEnabled = NO;
    [control addSubview:valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [control.heightAnchor constraintEqualToConstant:48],
        [iconView.trailingAnchor constraintEqualToAnchor:control.trailingAnchor constant:-14],
        [iconView.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18],
        [iconView.heightAnchor constraintEqualToConstant:18],
        [valueLabel.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:14],
        [valueLabel.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:iconView.leadingAnchor constant:-8],
    ]];
    if (outValue) *outValue = valueLabel;
    return control;
}

// 双行下拉字段（上行小标签 + 下行当前值 chip + 右缘 chevron，ZL2 目标平台/
// 排序方式字段真机形态；高度 64）
- (UIControl *)ame_panelDropdownControlWithLabelText:(NSString *)labelText
                                            chipView:(UIView **)outChipView
                                           chipLabel:(UILabel **)outChipLabel {
    UIControl *control = [[UIControl alloc] init];
    control.backgroundColor = [ZL2Theme surfaceContainerHigh];
    control.layer.cornerRadius = [ZL2Theme radiusM];
    control.layer.masksToBounds = YES;
    control.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.userInteractionEnabled = NO;
    [control addSubview:label];

    UIView *chipView = [[UIView alloc] init];
    chipView.layer.cornerRadius = 8;
    chipView.layer.masksToBounds = YES;
    chipView.translatesAutoresizingMaskIntoConstraints = NO;
    chipView.userInteractionEnabled = NO;
    [control addSubview:chipView];

    UILabel *chipLabel = [[UILabel alloc] init];
    chipLabel.font = [ZL2Theme fontLabelMedium];
    chipLabel.numberOfLines = 1;
    chipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    chipLabel.userInteractionEnabled = NO;
    [chipView addSubview:chipLabel];

    UIImage *chevron = ZL2AssetSystemImage(@"chevron.down", @"chevron.down");
    UIImageView *chevronView = [[UIImageView alloc] initWithImage:[chevron imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    chevronView.tintColor = [ZL2Theme onSurfaceVariant];
    chevronView.contentMode = UIViewContentModeScaleAspectFit;
    chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    chevronView.userInteractionEnabled = NO;
    [control addSubview:chevronView];

    [NSLayoutConstraint activateConstraints:@[
        [control.heightAnchor constraintEqualToConstant:64],
        [label.topAnchor constraintEqualToAnchor:control.topAnchor constant:9],
        [label.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:14],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:chevronView.leadingAnchor constant:-8],

        [chipView.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:6],
        [chipView.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:14],
        [chipView.heightAnchor constraintEqualToConstant:22],
        [chipView.bottomAnchor constraintEqualToAnchor:control.bottomAnchor constant:-9],

        [chipLabel.leadingAnchor constraintEqualToAnchor:chipView.leadingAnchor constant:8],
        [chipLabel.trailingAnchor constraintEqualToAnchor:chipView.trailingAnchor constant:-8],
        [chipLabel.centerYAnchor constraintEqualToAnchor:chipView.centerYAnchor],

        [chevronView.trailingAnchor constraintEqualToAnchor:control.trailingAnchor constant:-14],
        [chevronView.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [chevronView.widthAnchor constraintEqualToConstant:14],
        [chevronView.heightAnchor constraintEqualToConstant:14],
    ]];
    if (outChipView) *outChipView = chipView;
    if (outChipLabel) *outChipLabel = chipLabel;
    return control;
}

// 面板值外观同步（平台品牌色 chip / 排序当前值 / 已选版本号）
- (void)ame_applyFilterPanelAppearance {
    if (!self.platformChipLabel) return;   // buildViews 前/收藏页无面板
    NSInteger source = [self ame_apiSourceForType];
    self.platformChipLabel.text = (source == 2) ? @"CurseForge" : @"Modrinth";
    self.platformChipView.backgroundColor = ZL2AssetSourceBadgeColor(source);
    self.platformChipLabel.textColor = [UIColor whiteColor];

    NSInteger sortIndex = [self.sortValues indexOfObject:(self.sortField ?: @"")];
    NSString *sortTitle = @"相关性";
    if (sortIndex >= 0 && sortIndex < (NSInteger)self.sortTitleKeys.count) {
        NSString *localized = localize(self.sortTitleKeys[sortIndex], nil);
        if (localized.length > 0) sortTitle = localized;
    }
    self.sortChipLabel.text = sortTitle;
    self.sortChipView.backgroundColor = [ZL2Theme surfaceBright];
    self.sortChipLabel.textColor = [ZL2Theme onSurface];

    NSString *versionText = self.gameVersionFilter;
    if (![versionText isKindOfClass:[NSString class]]) versionText = @"";
    if (versionText.length > 0) {
        self.versionFieldValueLabel.text = versionText;
        self.versionFieldValueLabel.textColor = [ZL2Theme onSurface];
    } else {
        self.versionFieldValueLabel.text = localize(@"dl.asset.filter.version", nil);
        self.versionFieldValueLabel.textColor = [ZL2Theme onSurfaceVariant];
    }

    // 分类字段态（Task316：选中 slug 显示中文名，未选显示占位）
    if (self.categoryFieldValueLabel) {
        NSString *categoryText = [self ame_categoryDisplayNameForSlug:self.categoryFilter];
        if (categoryText.length > 0) {
            self.categoryFieldValueLabel.text = categoryText;
            self.categoryFieldValueLabel.textColor = [ZL2Theme onSurface];
        } else {
            self.categoryFieldValueLabel.text = localize(@"dl.asset.filter.category", nil);
            self.categoryFieldValueLabel.textColor = [ZL2Theme onSurfaceVariant];
        }
    }
}

// 面板显隐收敛（宽态 ≥560pt 展示右栏；窄屏/收藏页列表全宽，ZL2 横屏语义）
- (void)ame_setFilterPanelVisible:(BOOL)visible {
    if (self.filterPanel.hidden != !visible) {
        self.filterPanel.hidden = !visible;
    }
    if (self.panelWidthConstraint.isActive != visible) {
        self.panelWidthConstraint.active = visible;
    }
    if (self.tableToPanelConstraint.isActive != visible) {
        self.tableToPanelConstraint.active = visible;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.favoritesMode) {
        [self ame_setFilterPanelVisible:NO];
        return;
    }
    BOOL wide = (self.view.bounds.size.width >= 560.0);
    [self ame_setFilterPanelVisible:wide];
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

#pragma mark - 搜索触发（0.5s 防抖文本变化 / 平台 / 排序）

- (void)ame_debouncedSearchText:(NSString *)text {
    // 0.5s 防抖（任务规格）：代际号失效旧回调，停止输入 0.5s 后自动触发
    NSString *value = text ?: @"";
    self.inputGeneration += 1;
    NSInteger gen = self.inputGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen != self.inputGeneration) return;   // 0.5s 内又有输入
        if ([value isEqualToString:self.searchQuery ?: @""]) return;   // 内容未变不重搜
        [self ame_triggerSearchWithQuery:value];
    });
}

// 目标平台下拉（Modrinth / CurseForge；选择持久化进下载源偏好并整页重搜；
// 存档类别 Modrinth 无 world facet，入口已禁用不达此处）
- (void)ame_platformTapped {
    __weak typeof(self) weakSelf = self;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"dl.asset.filter.platform", nil)
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Modrinth"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf ame_applyPlatform:1];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"CurseForge"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf ame_applyPlatform:2];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_84", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.sourceView = self.platformControl;
    sheet.popoverPresentationController.sourceRect = self.platformControl.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)ame_applyPlatform:(NSInteger)platform {
    if (platform != 1 && platform != 2) return;
    if (platform == self.platformOverride) return;
    self.platformOverride = platform;
    [PLPreferences setDownloadSource:(platform == 2 ? @"curseforge" : @"modrinth")
                            forType:[self ame_typeToken]];
    [self ame_applyFilterPanelAppearance];
    [self ame_triggerSearchWithQuery:(self.searchQuery ?: @"")];
}

// 排序方式下拉（五档 PlatformSortField；ZL2 下拉菜单语义的 iOS 等价物）
- (void)ame_sortTapped {
    __weak typeof(self) weakSelf = self;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_161", nil)
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i = 0; i < self.sortValues.count; i++) {
        NSString *value = self.sortValues[i];
        NSString *title = localize(self.sortTitleKeys[i], nil);
        if (title.length == 0) title = value;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if ([value isEqualToString:strongSelf.sortField ?: @""]) return;
            strongSelf.sortField = value;
            [strongSelf ame_applyFilterPanelAppearance];
            [strongSelf ame_triggerSearchWithQuery:(strongSelf.searchQuery ?: @"")];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_84", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.sourceView = self.sortControl;
    sheet.popoverPresentationController.sourceRect = self.sortControl.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)ame_triggerSearchWithQuery:(NSString *)query {
    self.searchQuery = query ?: @"";
    self.hasSearched = YES;
    self.currentPage = 1;
    self.knownTotalCount = 0;
    self.requestGeneration += 1;   // 新搜索使在途响应过期
    [self ame_loadListWithReset:YES];
}

#pragma mark - 数据加载（旧页 loadXxxList 语义等价移植）

#pragma mark - 数据加载（7.0-UI-16：ZL2 PageController 页码语义整页替换）

- (void)ame_loadListWithReset:(BOOL)reset {
    if (reset) {
        self.currentOffset = (self.currentPage - 1) * ZL2AssetSearchPageSize;
        self.hasMore = YES;
        [self.results removeAllObjects];
        [self.tableView reloadData];
        [self ame_refreshEmptyAndLoading];
        [self ame_updatePaginationUI];
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
    // 游戏版本筛选（右栏版本选择弹层；两平台 API 均消费 mcVersion 键：
    // Modrinth facets versions:X / CurseForge gameVersion 参数）
    if (self.gameVersionFilter.length > 0) {
        filters[@"mcVersion"] = self.gameVersionFilter;
    }

    // 分类筛选（Task316：两平台 API 均消费 category 键——Modrinth facets
    // categories:<slug> / CurseForge categories=<id>）
    if (self.categoryFilter.length > 0) {
        filters[@"category"] = self.categoryFilter;
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

            // 过期响应防护：发起后搜索词/排序/页码已变更（generation 已递增）直接丢弃；
            // 若期间有新搜索排队（latest-wins）则补发
            if (gen != strongSelf.requestGeneration) {
                if (strongSelf.pendingSearchAfterFlight) {
                    strongSelf.pendingSearchAfterFlight = NO;
                    [strongSelf ame_loadListWithReset:YES];
                }
                return;
            }

            if (results) {
                // 页码语义：整页替换（ZL2 PageController 翻页口径，非滚动追加）
                [strongSelf.results removeAllObjects];
                [strongSelf.results addObjectsFromArray:results];
                strongSelf.hasMore = ((NSInteger)results.count >= ZL2AssetSearchPageSize);
                // 总页数来源：两平台搜索响应 total（桩/异常路径 0 = 未知，页码
                // 退化为"第 N 页"；CurseForge pagination.totalCount / Modrinth total_hits）
                if ([api isKindOfClass:[CurseForgeAPI class]]) {
                    strongSelf.knownTotalCount = [(CurseForgeAPI *)api lastSearchTotalCount];
                } else if ([api isKindOfClass:[ModrinthAPI class]]) {
                    strongSelf.knownTotalCount = [(ModrinthAPI *)api lastSearchTotalCount];
                }
                [strongSelf.tableView reloadData];
            } else if (error) {
                [strongSelf ame_showError:error.localizedDescription];
            }
            [strongSelf ame_refreshEmptyAndLoading];
            [strongSelf ame_updatePaginationUI];

            if (strongSelf.pendingSearchAfterFlight) {
                strongSelf.pendingSearchAfterFlight = NO;
                [strongSelf ame_loadListWithReset:YES];
            }
        });
    }];
}

#pragma mark - 页码控制器（ZL2 PageController）

- (void)ame_updatePaginationUI {
    if (self.favoritesMode) {
        self.paginationBar.hidden = YES;
        return;
    }
    self.paginationBar.hidden = NO;
    BOOL hasTotal = (self.knownTotalCount > 0);
    NSInteger totalPages = 0;
    if (hasTotal) {
        totalPages = (NSInteger)((self.knownTotalCount + (NSUInteger)ZL2AssetSearchPageSize - 1)
                                 / (NSUInteger)ZL2AssetSearchPageSize);
        if (totalPages < 1) totalPages = 1;
    }
    if (hasTotal) {
        self.pageInfoLabel.text = [NSString stringWithFormat:@"%ld / %ld",
                                   (long)self.currentPage, (long)totalPages];
    } else {
        self.pageInfoLabel.text = [NSString stringWithFormat:localize(@"dl.asset.page", nil), (long)self.currentPage];
    }
    BOOL prevEnabled = (self.currentPage > 1);
    BOOL nextEnabled = hasTotal ? (self.currentPage < totalPages) : self.hasMore;
    self.prevPageButton.enabled = prevEnabled;
    self.nextPageButton.enabled = nextEnabled;
    self.prevPageButton.alpha = prevEnabled ? 1.0 : 0.35;
    self.nextPageButton.alpha = nextEnabled ? 1.0 : 0.35;
}

- (void)ame_prevPageTapped {
    if (self.inFlight || self.currentPage <= 1) return;
    self.currentPage -= 1;
    self.requestGeneration += 1;
    [self ame_loadListWithReset:YES];
}

- (void)ame_nextPageTapped {
    if (self.inFlight) return;
    if (self.knownTotalCount > 0) {
        NSInteger totalPages = (NSInteger)((self.knownTotalCount + (NSUInteger)ZL2AssetSearchPageSize - 1)
                                           / (NSUInteger)ZL2AssetSearchPageSize);
        if (self.currentPage >= totalPages) return;
    } else if (!self.hasMore) {
        return;
    }
    self.currentPage += 1;
    self.requestGeneration += 1;
    [self ame_loadListWithReset:YES];
}

#pragma mark - 游戏版本选择弹层（ZL2 版本筛选对话框语义，M3 底部弹层承载）

- (void)ame_versionFieldTapped {
    if (self.versionSheetContent) return;   // 弹层已在展示中

    CGFloat contentWidth = MIN(560.0, self.view.bounds.size.width - 48.0);
    if (contentWidth < 280.0) contentWidth = 280.0;

    UIView *content = [[UIView alloc] init];
    content.backgroundColor = [ZL2Theme surfaceContainerLow];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.layer.cornerRadius = [ZL2Theme radiusXL];
    content.layer.masksToBounds = YES;
    self.versionSheetContent = content;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = localize(@"i18n_str_188", nil);
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 1;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleLabel];

    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    clearButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [clearButton setTitle:localize(@"dl.asset.version.any", nil) forState:UIControlStateNormal];
    [clearButton setTitleColor:[ZL2Theme primary] forState:UIControlStateNormal];
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    clearButton.accessibilityLabel = localize(@"dl.asset.version.any", nil);
    [clearButton addTarget:self
                    action:@selector(ame_versionCleared)
          forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:clearButton];

    // 弹层内搜索（版本清单 900+ 条，内筛快速定位）
    UIView *sheetSearchCapsule = [[UIView alloc] init];
    sheetSearchCapsule.backgroundColor = [ZL2Theme surfaceContainerHigh];
    sheetSearchCapsule.layer.cornerRadius = [ZL2Theme radiusS];
    sheetSearchCapsule.layer.masksToBounds = YES;
    sheetSearchCapsule.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:sheetSearchCapsule];

    UIImageView *sheetSearchIcon = [[UIImageView alloc] initWithImage:[ZL2AssetSystemImage(@"magnifyingglass", @"search") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    sheetSearchIcon.tintColor = [ZL2Theme onSurfaceVariant];
    sheetSearchIcon.contentMode = UIViewContentModeScaleAspectFit;
    sheetSearchIcon.translatesAutoresizingMaskIntoConstraints = NO;
    sheetSearchIcon.userInteractionEnabled = NO;
    [sheetSearchCapsule addSubview:sheetSearchIcon];

    UITextField *sheetSearchField = [[UITextField alloc] init];
    sheetSearchField.placeholder = localize(@"i18n_str_155", nil);
    sheetSearchField.font = [ZL2Theme fontBodyLarge];
    sheetSearchField.textColor = [ZL2Theme onSurface];
    sheetSearchField.autocorrectionType = UITextAutocorrectionTypeNo;
    sheetSearchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    sheetSearchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    sheetSearchField.returnKeyType = UIReturnKeySearch;
    sheetSearchField.translatesAutoresizingMaskIntoConstraints = NO;
    sheetSearchField.accessibilityLabel = localize(@"i18n_str_155", nil);
    [sheetSearchCapsule addSubview:sheetSearchField];
    [sheetSearchField addTarget:self
                         action:@selector(ame_sheetSearchChanged:)
               forControlEvents:UIControlEventEditingChanged];

    UITableView *sheetTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    sheetTable.backgroundColor = [UIColor clearColor];
    sheetTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    sheetTable.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    sheetTable.translatesAutoresizingMaskIntoConstraints = NO;
    sheetTable.accessibilityLabel = @"版本列表";
    [content addSubview:sheetTable];
    [sheetTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ZL2VersionSheetCell"];

    ZL2VersionSheetHandler *handler = [[ZL2VersionSheetHandler alloc] init];
    handler.table = sheetTable;
    self.sheetHandler = handler;
    sheetTable.dataSource = handler;
    sheetTable.delegate = handler;

    __weak typeof(self) weakSelf = self;
    __weak typeof(content) weakContent = content;
    handler.onPick = ^(NSString *versionId) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [ZL2M3BottomSheet dismissWithContentView:content];
        strongSelf.gameVersionFilter = versionId;
        [strongSelf ame_applyFilterPanelAppearance];
        [strongSelf ame_triggerSearchWithQuery:(strongSelf.searchQuery ?: @"")];
    };

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:contentWidth],
        [content.heightAnchor constraintEqualToConstant:480],

        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

        [clearButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [sheetSearchCapsule.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [sheetSearchCapsule.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [sheetSearchCapsule.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [sheetSearchCapsule.heightAnchor constraintEqualToConstant:40],

        [sheetSearchIcon.leadingAnchor constraintEqualToAnchor:sheetSearchCapsule.leadingAnchor constant:12],
        [sheetSearchIcon.centerYAnchor constraintEqualToAnchor:sheetSearchCapsule.centerYAnchor],
        [sheetSearchIcon.widthAnchor constraintEqualToConstant:16],
        [sheetSearchIcon.heightAnchor constraintEqualToConstant:16],

        [sheetSearchField.leadingAnchor constraintEqualToAnchor:sheetSearchIcon.trailingAnchor constant:8],
        [sheetSearchField.trailingAnchor constraintEqualToAnchor:sheetSearchCapsule.trailingAnchor constant:-10],
        [sheetSearchField.topAnchor constraintEqualToAnchor:sheetSearchCapsule.topAnchor],
        [sheetSearchField.bottomAnchor constraintEqualToAnchor:sheetSearchCapsule.bottomAnchor],

        [sheetTable.topAnchor constraintEqualToAnchor:sheetSearchCapsule.bottomAnchor constant:8],
        [sheetTable.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [sheetTable.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [sheetTable.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
    ]];

    // 版本清单加载（ZL2VersionIndex 单例：未落定时限时等待，回调恒主线程；
    // latest-* 种子别名不是真实版本号，滤除；弹层已收时静默丢弃）
    [ZL2VersionIndex.sharedIndex remoteVersionsWithCompletion:^(NSArray<NSDictionary<NSString *, id> *> *versions, BOOL loaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.versionSheetContent != weakContent) return;
            NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
            for (NSDictionary *entry in versions) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                NSString *versionId = entry[@"id"];
                if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) continue;
                if ([versionId hasPrefix:@"latest-"]) continue;
                [ids addObject:versionId];
            }
            ZL2VersionSheetHandler *sheetHandler = (ZL2VersionSheetHandler *)strongSelf.sheetHandler;
            sheetHandler.allVersions = [ids array];
            [sheetHandler reloadFilterWithText:sheetSearchField.text ?: @""];
        });
    }];

    [ZL2M3BottomSheet presentWithContentView:content
                                  onDismiss:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.versionSheetContent = nil;
        strongSelf.sheetHandler = nil;
    }];
}

- (void)ame_sheetSearchChanged:(UITextField *)field {
    ZL2VersionSheetHandler *handler = (ZL2VersionSheetHandler *)self.sheetHandler;
    if (!handler) return;
    [handler reloadFilterWithText:(field.text ?: @"")];
}

- (void)ame_versionCleared {
    UIView *content = self.versionSheetContent;
    if (content) {
        [ZL2M3BottomSheet dismissWithContentView:content];
    }
    self.gameVersionFilter = nil;
    [self ame_applyFilterPanelAppearance];
    [self ame_triggerSearchWithQuery:(self.searchQuery ?: @"")];
}

#pragma mark - 分类筛选（Task316 ZL2 筛选同步：分类 slug 表 + 弹层选择器）

/// 分类 slug 表（Modrinth 官方 tag 值域；ZL2 ScreenCategories 同源）。
/// 展示名走属性赋值（task248 闸2 仅查 selector 写入点，ZL2SettingPages 先例）；
/// CurseForge 侧按 name/slug 归一匹配（见 CurseForgeAPI ame316 解析）。
- (NSArray<NSDictionary *> *)ame_categoryTableForType {
    NSString *type = nil;
    switch (self.assetType) {
        case ZL2AssetSearchTypeMod:         type = @"mod"; break;
        case ZL2AssetSearchTypeModpack:     type = @"modpack"; break;
        case ZL2AssetSearchTypeResourcePack: type = @"resourcepack"; break;
        case ZL2AssetSearchTypeShader:      type = @"shader"; break;
        case ZL2AssetSearchTypeWorld:       type = @"world"; break;
    }
    NSDictionary *tables = @{
        @"mod": @[
            @[@"adventure", @"冒险"], @[@"technology", @"科技"], @[@"magic", @"魔法"],
            @[@"utility", @"实用"], @[@"optimization", @"性能优化"], @[@"decoration", @"装饰"],
            @[@"equipment", @"装备"], @[@"combat", @"战斗"], @[@"food", @"食物"],
            @[@"storage", @"存储"], @[@"transportation", @"运输"], @[@"worldgen", @"世界生成"],
            @[@"library", @"前置库"], @[@"social", @"社交"], @[@"education", @"教育"],
            @[@"economy", @"经济"], @[@"game-mechanics", @"游戏机制"], @[@"mobs", @"生物"],
        ],
        @"modpack": @[
            @[@"adventure", @"冒险"], @[@"technology", @"科技"], @[@"magic", @"魔法"],
            @[@"multiplayer", @"多人"], @[@"quests", @"任务"], @[@"hardcore", @"硬核"],
            @[@"vanilla+", @"原版增强"], @[@"map-based", @"基于地图"], @[@"horror", @"恐怖"],
            @[@"exploration", @"探索"], @[@"extra-large", @"超大型"], @[@"lightweight", @"轻量"],
        ],
        @"resourcepack": @[
            @[@"16x", @"16x"], @[@"32x", @"32x"], @[@"64x", @"64x"],
            @[@"128x", @"128x"], @[@"256x", @"256x"], @[@"512x", @"512x"],
            @[@"vanilla-like", @"原版风"], @[@"simplistic", @"简约"], @[@"realistic", @"写实"],
            @[@"fantasy", @"奇幻"], @[@"animated", @"动态"], @[@"parchment", @"羊皮纸"],
        ],
        @"shader": @[
            @[@"fantasy", @"奇幻"], @[@"realistic", @"写实"], @[@"cartoon", @"卡通"],
            @[@"vanilla", @"原版风"], @[@"performance", @"性能"], @[@"potent", @"强力"],
            @[@"colored", @"彩色"], @[@"screenshot", @"截图"], @[@"semi-realistic", @"半写实"],
        ],
        @"world": @[
            @[@"adventure", @"冒险"], @[@"survival", @"生存"], @[@"creation", @"创造"],
            @[@"parkour", @"跑酷"], @[@"puzzle", @"解谜"], @[@"game-map", @"游戏地图"],
        ],
    };
    return tables[type] ?: @[];
}

- (NSString *)ame_categoryDisplayNameForSlug:(NSString *)slug {
    if (slug.length == 0) return @"";
    for (NSDictionary *entry in [self ame_categoryTableForType]) {
        if ([entry[@"slug"] isEqualToString:slug]) return entry[@"name"];
    }
    return slug;  // 未知 slug 兜底原样展示
}

- (void)ame_categoryFieldTapped {
    if (self.categorySheetContent) {
        [ZL2M3BottomSheet dismissWithContentView:self.categorySheetContent];
        return;
    }
    NSArray<NSDictionary *> *table = [self ame_categoryTableForType];
    if (table.count == 0) return;

    CGFloat contentWidth = 500.0;
    UIView *content = [[UIView alloc] init];
    content.backgroundColor = [ZL2Theme surfaceContainerLow];
    self.categorySheetContent = content;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = localize(@"dl.asset.filter.category", nil);
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleLabel];

    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    clearButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [clearButton setTitle:localize(@"dl.asset.version.any", nil) forState:UIControlStateNormal];
    clearButton.tintColor = [ZL2Theme primary];
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:clearButton];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.backgroundColor = [UIColor clearColor];
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    __weak typeof(self) weakSelf = self;
    __weak typeof(content) weakContent = content;
    NSString *selected = self.categoryFilter ?: @"";
    for (NSDictionary *entry in table) {
        NSString *slug = entry[@"slug"];
        UIButton *option = [UIButton buttonWithType:UIButtonTypeCustom];
        option.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        option.titleEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        option.titleLabel.font = [ZL2Theme fontBodyLarge];
        [option setTitle:entry[@"name"] forState:UIControlStateNormal];
        [option setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
        option.backgroundColor = [slug isEqualToString:selected]
            ? [ZL2Theme primaryContainer] : [ZL2Theme surfaceContainer];
        option.layer.cornerRadius = [ZL2Theme radiusS];
        option.layer.masksToBounds = YES;
        option.translatesAutoresizingMaskIntoConstraints = NO;
        [option.heightAnchor constraintEqualToConstant:44].active = YES;
        [option addTarget:self action:@selector(ame_categoryOptionTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(option, @selector(ame_categoryOptionTapped:), slug, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stack addArrangedSubview:option];
    }
    [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor].active = YES;
    [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8].active = YES;
    [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-8].active = YES;

    [clearButton addTarget:self action:@selector(ame_categoryCleared) forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:contentWidth],
        [content.heightAnchor constraintEqualToConstant:420],
        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [clearButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
    ]];

    [ZL2M3BottomSheet presentWithContentView:content
                                  onDismiss:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.categorySheetContent = nil;
    }];
}

- (void)ame_categoryOptionTapped:(UIButton *)sender {
    NSString *slug = objc_getAssociatedObject(sender, @selector(ame_categoryOptionTapped:));
    UIView *content = self.categorySheetContent;
    if (content) [ZL2M3BottomSheet dismissWithContentView:content];
    self.categoryFilter = slug;
    [self ame_applyFilterPanelAppearance];
    [self ame_triggerSearchWithQuery:(self.searchQuery ?: @"")];
}

- (void)ame_categoryCleared {
    UIView *content = self.categorySheetContent;
    if (content) {
        [ZL2M3BottomSheet dismissWithContentView:content];
    }
    self.categoryFilter = nil;
    [self ame_applyFilterPanelAppearance];
    [self ame_triggerSearchWithQuery:(self.searchQuery ?: @"")];
}

#pragma mark - 导入整合包（ZL2 SearchModPackScreen 右栏同位按钮；旧页导入流 1:1）

- (void)ame_importTapped {
    // 旧页 openImportModpackView（DownloadViewController.m L4701-4705）同款：
    // push ModpackImportViewController，文件选择/解析/导入全链由该页承载
    ModpackImportViewController *importVC = [[ModpackImportViewController alloc] init];
    [self ame_pushViewController:importVC];
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
    // 7.0-UI-16：卡面独立下载钮退役（ZL2 真机卡无此件），点卡进版本页由
    // didSelectRow 承担；收藏心形保留（搜索卡与收藏页共用 toggle）
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
    // 图标预取（旧页 prefetchIconsForTableView 同款：后续 5 个 cell 图标进缓存；
    // 7.0-UI-16 起分页走页码控制器，滚动续载判定移除，预取保留）
    for (NSInteger row = indexPath.row + 1; row <= indexPath.row + 5; row++) {
        if (row >= (NSInteger)self.results.count) break;
        NSDictionary *item = self.results[row];
        NSString *iconUrl = item[@"imageUrl"];
        if (![iconUrl isKindOfClass:[NSString class]] || iconUrl.length == 0) iconUrl = item[@"icon_url"];
        if ([iconUrl isKindOfClass:[NSString class]] && iconUrl.length > 0) {
            [IconLoader prefetchIconWithURL:iconUrl targetSize:CGSizeMake(72, 72)];
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
    // ★ Task318：预装语义键——本链是整合包触发的自动预装（下方 ensureParentVersionExists
    //   刚写出 versions/<id>/<id>.json json-only 半成品），同版本复用续传禁弹改名窗
    //   （ame300_preinstall 门禁放行，见 MinecraftResourceDownloadTask downloadVersion:）
    NSMutableDictionary *ame318_preinstallVersion = [version mutableCopy];
    ame318_preinstallVersion[@"ame300_preinstall"] = @YES;
    version = ame318_preinstallVersion;
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
    self.emptyContainer.hidden = hasResults;
    if (!hasResults) {
        // 进门即搜后 hasSearched 恒 YES（收藏模式构造即 YES）；
        // 空态只剩"暂无 X"（含收藏页空仓库）
        NSString *key = nil;
        if (self.favoritesMode) {
            [self ame_showEmptyStateWithIcon:@"heart" fallback:@"heart.fill"
                                        text:localize(@"dl.asset.favorites.empty", nil)];
        } else {
            switch (self.assetType) {
                case ZL2AssetSearchTypeMod:          key = @"i18n_str_180"; break;   // 暂无模组
                case ZL2AssetSearchTypeModpack:      key = @"i18n_str_182"; break;   // 暂无整合包
                case ZL2AssetSearchTypeResourcePack: key = @"i18n_str_183"; break;   // 暂无资源包
                case ZL2AssetSearchTypeWorld:        key = @"i18n_str_186"; break;   // 暂无世界
                case ZL2AssetSearchTypeShader:       key = @"i18n_str_181"; break;   // 暂无光影
            }
            [self ame_showEmptyStateWithIcon:@"magnifyingglass" fallback:@"search"
                                        text:localize(key ?: @"i18n_str_180", nil)];
        }
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

