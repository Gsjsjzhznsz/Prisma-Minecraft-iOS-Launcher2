//
// ZL2AssetSearchViewController.h — ZL2 风格通用远程资产搜索列表页（7.0-UI-10-a）
//
// 语义纠错（Task 7.0-UI-10-a）：ZL2 下载页六类全部是远程搜索下载
//   （DownloadModPack/Mod/ResourcePack/Saves/ShadersScreen.kt 均 route 到
//   assets/search/SearchXXXScreen.kt），上一轮误把五类挂到本地管理器 VC
//   （ModsManager/WorldsManager 等——本地管理在 ZL2 属版本管理域）。
//   本页 = 六类中五类（整合包/模组/资源包/存档/光影包）的通用 M3 远程搜索
//   列表页；「游戏」类仍为旧 DownloadViewController（远程游戏版本页，M3 化
//   留下一轮）。
//
// 对标 ZL2 SearchAssetsScreen.kt + _Search.Result.kt + _Search.Filter.kt
// （搜索框 / SortField 排序 / 结果卡 / 空态），iOS 14 能力等价移植：
//   排序=ZL2 PlatformSortField（relevance/downloads/follows/newest/updated），
//   分页=旧页 hasMoreXxx/loadXxxList 语义（滚到底自动加载下一页），
//   结果卡点击 → 1:1 复刻旧 DownloadViewController.m 各类型版本页配置
//   （锚点行号见 .m 文件头映射表）。
//
// 类型（枚举驱动，构造时注入，禁止事后可变）：
//   ZL2AssetSearchTypeMod          模组   → ModVersionViewController
//   ZL2AssetSearchTypeModpack      整合包 → ModVersionViewController（安装流）
//   ZL2AssetSearchTypeResourcePack 资源包 → AssetVersionViewController
//   ZL2AssetSearchTypeWorld        存档   → AssetVersionViewController（强制 CurseForge）
//   ZL2AssetSearchTypeShader       光影包 → ShaderVersionViewController
//
// 由 ZL2DownloadViewController 六类接线消费（ame_childForIndex:）；
// 预览 harness 无 nav 宿主时 push 自动降级为 present 包 nav。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 资产类型（ZL2 下载页远程搜索资产；顺序即结果页默认排序无关，仅枚举）
typedef NS_ENUM(NSInteger, ZL2AssetSearchType) {
    ZL2AssetSearchTypeMod = 0,          // 模组
    ZL2AssetSearchTypeModpack = 1,      // 整合包
    ZL2AssetSearchTypeResourcePack = 2, // 资源包
    ZL2AssetSearchTypeWorld = 3,        // 存档（世界）
    ZL2AssetSearchTypeShader = 4,       // 光影包
    ZL2AssetSearchTypeDataPack = 5,     // 数据包（Task323：Prisma1 八类对齐；
                                        //  CF classId 映射既有 / Modrinth
                                        //  project_type:datapack 直通）
};

@interface ZL2AssetSearchViewController : UIViewController

// ★ Task324：下载目标实例透传（管理器改道 ZL2 下载中心时保留 Task265 语义）。
//   设置后 viewDidLoad 快照优先取本值（nil/空 = 沿旧口径快照当前选中实例），
//   防下载写入目标与管理页绑定实例不一致。
@property (nonatomic, copy, nullable) NSString *targetProfileName;

// 指定初始化器：类型 + 预置标题（标题仅用于 a11y；页面视觉标题由宿主
// ZL2DownloadViewController 的类别 chips 承担）。类型注入后不可变。
- (instancetype)initWithType:(ZL2AssetSearchType)type
                       title:(NSString *)title NS_DESIGNATED_INITIALIZER;

// 收藏模式（7.0-UI-14 下载域第 7 项）：数据源切换 ZL2FavoritesStore，
// 结果/详情/安装全链与搜索模式同构复用（点击行为/openResult 1:1）
- (instancetype)initWithFavorites;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
