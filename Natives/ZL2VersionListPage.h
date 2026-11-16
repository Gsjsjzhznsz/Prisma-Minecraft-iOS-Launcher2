//
// ZL2VersionListPage.h — ZL2 版本列表统一页（★Task436 批次二④）
//
// 三版本列表页（ModVersion / ShaderVersion / AssetVersion）的 ZL2 化统一承载：
//   一个参数化页面按 domainType 三域分流——
//     ZL2VersionListDomainAsset   资源包/数据包/存档（无加载器概念，下载源固定）
//     ZL2VersionListDomainMod     模组/整合包（加载器行 + 下载源切换 + Task247 跨源解析）
//     ZL2VersionListDomainShader  光影包（加载器行 + 下载源切换，无跨源解析）
//
// 功能面对齐旧页（逐项登记见 .m 文件头对表）：chips 筛选（来源/游戏版本/
//   加载器/排序）、版本行卡片（版本名+发布类型徽章+版本号+加载器徽章+日期/
//   文件大小/游戏版本）、项目详情头（图标/标题/作者/下载量/关注/描述/标签/
//   最近更新 + 收藏胶囊 ZL2FavoritesStore）、加载/空态、preferred 版本自动
//   选中与置顶。版本模型统一 ModVersion（旧 ShaderVersion 页同款动态派发
//   口径：两模型字段面完全一致，见 ShaderVersionViewController.m L620-631）。
//
// delegate 交付 ModVersion；下载/安装流由父页（ZL2AssetSearchViewController /
//   ZL2SearchIdViewController 轨页桥接）既有链路承担，本页零下载逻辑。
//
// 预览 harness 红线：本 TU 只 import Natives 根可达头 + 自含 API 最小声明
//   （ModrinthAPI/CurseForgeAPI 不 import 真头——UnzipKit.h 传递链在
//   ui_fluent_smoke COMMON -I 下不可达，ZL2AssetSearch 7.0-UI-10-f 判例同款）。
//

#import <UIKit/UIKit.h>
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

/// 版本列表域类型（构造注入后不可变；决定筛选行形态与拉取分支）
typedef NS_ENUM(NSInteger, ZL2VersionListDomain) {
    ZL2VersionListDomainAsset  = 0,   // 资源包/数据包/存档
    ZL2VersionListDomainMod    = 1,   // 模组/整合包
    ZL2VersionListDomainShader = 2,   // 光影包
};

@class ZL2VersionListPage;
@class ModItem;
@class ShaderItem;

@protocol ZL2VersionListPageDelegate <NSObject>
/// 选中版本（delegate 侧 pop 回本页后处理下载/安装流；ModVersion 统一承载，
/// ShaderVersion 同字段面动态派发兼容——见文件头注记）
- (void)zl2VersionListPage:(ZL2VersionListPage *)page didSelectVersion:(ModVersion *)version;
@end

@interface ZL2VersionListPage : UIViewController

/// 指定初始化器：域类型注入后不可变
- (instancetype)initWithDomain:(ZL2VersionListDomain)domain NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly) ZL2VersionListDomain domainType;

// 在线项目 id（Modrinth slug/uuid 或 CurseForge 数字 id；版本拉取与收藏键共用）
@property (nonatomic, copy, nullable) NSString *projectID;

// API 来源（旧页 apiSource 同语义：1=Modrinth 缺省 / 2=CurseForge；
// Mod/Shader 域的来源行可切换，Asset 域固定本值）
@property (nonatomic, assign) NSInteger apiSource;

// FCL 风格偏好（旧页同语义：自动选中匹配 chip 并把匹配版本置顶）
@property (nonatomic, copy, nullable) NSString *preferredGameVersion;
@property (nonatomic, copy, nullable) NSString *preferredLoader;

// 导航标题（= 项目名）
@property (nonatomic, copy, nullable) NSString *pageTitle;

// 收藏快照 projectType 令牌（mod/modpack/resourcepack/world/datapack/shader；
// 缺省按域推导 Mod→mod / Shader→shader / Asset→resourcepack——资产域请显式
// 传入，防存档/数据包收藏条目 projectType 错档）
@property (nonatomic, copy, nullable) NSString *snapshotProjectType;

// delegate 回填上下文（旧页 viewController.modItem / viewController.shaderItem
// 同语义：下载链在父页读回；Asset 域由父页 pending* 承载，无需回填）
@property (nonatomic, strong, nullable) ModItem *modItem;
@property (nonatomic, strong, nullable) ShaderItem *shaderItem;

// 详情头展示字段（旧页 AssetDetailHeaderView configureWith* 同语义）。
// Mod/Shader 域缺省从 modItem/shaderItem 派生；Asset 域由父页显式传入。
@property (nonatomic, copy, nullable) NSString *headerIconURL;
@property (nonatomic, copy, nullable) NSString *headerTitle;
@property (nonatomic, copy, nullable) NSString *headerAuthor;
@property (nonatomic, strong, nullable) NSNumber *headerDownloads;
@property (nonatomic, strong, nullable) NSNumber *headerLikes;
@property (nonatomic, copy, nullable) NSString *headerDescription;
@property (nonatomic, strong, nullable) NSArray<NSString *> *headerCategories;
@property (nonatomic, copy, nullable) NSString *headerLastUpdated;

@property (nonatomic, weak, nullable) id<ZL2VersionListPageDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
