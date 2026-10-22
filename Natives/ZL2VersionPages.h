//
// ZL2VersionPages.h — ZL2 版本详情八子页集合（7.0-UI-13-V）
//
// 对标 ZalithLauncher2 NormalNavKey.Versions.* 八页（VersionSettingsScreen
// NavigationUI 装载面），iOS 能力映射见各页 .m 头注释：
//
//   ZL2VersionOverviewPage        概览（信息卡 + 管理按钮组：重命名/编辑摘要/
//                                 删除版本/打开游戏目录）
//   ZL2VersionModsPage            模组管理（mods/ 枚举 + 启用禁用 .disabled 语义）
//   ZL2VersionSavesPage           存档管理（saves/ 枚举 + level.dat 解析）
//   ZL2VersionResourcePacksPage   资源包（resourcepacks/ 目录+zip）
//   ZL2VersionShadersPage         光影（shaderpacks/ 仅 zip）
//   ZL2VersionScreenshotsPage     截图（screenshots/ 3 列网格 + 大图查看器）
//   ZL2VersionServersPage         服务器列表（servers.dat 读 + 全量回写）
//   ZL2VersionConfigPage          配置（内存/JVM/渲染器覆写/服务器 IP）
//
// 通用契约：initWithProfileName:gameDir:（gameDir 由容器经
// ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName: 解析）；
// 文件枚举后台队列 / UI 主线程；改动影响实例表时 post @"ReloadProfileList"。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 公共基类

@interface ZL2VersionPageBase : UIViewController

/// PLProfiles 注册表字典键（身份；ZL2Versions 卡片同源）
@property (nonatomic, copy, readonly) NSString *ameV13_profileName;
/// 已解析的游戏目录绝对路径（容器解析链产物，子页全部枚举走它）
@property (nonatomic, copy, readonly) NSString *ameV13_gameDir;

- (instancetype)initWithProfileName:(NSString *)profileName
                            gameDir:(NSString *)gameDir;

/// 概览页重命名后由容器广播同步（ZL2VersionDetailProfileRenamed 消费侧）
- (void)ameV13_updateProfileName:(NSString *)newName;

/// 子页内容刷新（进入视图/数据变更后调用；子类覆写）
- (void)ameV13_reloadContent;

@end

#pragma mark - 八子页

@interface ZL2VersionOverviewPage : ZL2VersionPageBase
@end

@interface ZL2VersionModsPage : ZL2VersionPageBase
@end

@interface ZL2VersionSavesPage : ZL2VersionPageBase
@end

/// 资源包/光影共用基类（目录枚举口径/导入内容类型由子类给参；不直接实例化）
@interface ZL2VersionPacksPageBase : ZL2VersionPageBase
@end

@interface ZL2VersionResourcePacksPage : ZL2VersionPacksPageBase
@end

@interface ZL2VersionShadersPage : ZL2VersionPacksPageBase
@end

@interface ZL2VersionScreenshotsPage : ZL2VersionPageBase
@end

@interface ZL2VersionServersPage : ZL2VersionPageBase
@end

@interface ZL2VersionConfigPage : ZL2VersionPageBase
@end

NS_ASSUME_NONNULL_END
