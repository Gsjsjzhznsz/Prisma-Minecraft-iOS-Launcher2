//
// ZL2VersionDetailViewController.h — ZL2 版本详情容器（7.0-UI-13-V）
//
// 对标 ZalithLauncher2 NestedNavKey.VersionSettings（VersionSettingsScreen.kt）：
//   Row { TabMenu(左子导航轨) + NavigationUI(内容) }。iOS 对应：
//   顶部版本信息头卡（surfaceContainer/radiusM：34pt 加载器图标 + 版本名 +
//   描述 + MC版本/加载器标签行 + 头部右侧「完成」钮）→ 左子导航轨（160pt，
//   ZL2RailItem 视觉同款：32pt 胶囊 + 标签，概览/模组/存档/资源包/光影/
//   截图/服务器/配置 八项，ZL2 的 division 分隔线同位移植：模组前/服务器前）
//   → 右内容区 = 子页 addChild + 0.18s crossDissolve（ZL2ShellViewController
//   手法）。子页集合见 ZL2VersionPages.h（八页 1:1 ZL2 逻辑映射）。
//
// 数据契约：
//   - 实例字典 = PLProfiles.current.profiles[profileName]（键名即字典键，
//     Task162 口径）；版本号 = profile[@"lastVersionId"]，加载器识别与
//     MC 版本反解 = ZL2VersionsViewController 同款双契约
//     （ModLoaderIconHelper detectLoaderFromVersionId / ModpackExportService
//     parseVersionId）。
//   - 实例名→游戏目录解析链：+ameV13_resolvedGameDirForProfileName:
//     （ModService.m resolveAbsoluteGameDirForProfile: 同契约，Task225
//     隔离嗅探走 ModService 公共类方法，解析链永不漂移）。
//
// 导航约定：由 ZL2VersionsViewController push 进入（viewWillDisappear 已恢复
//   系统导航栏）；「完成」= pop（无 nav 时 dismiss 兜底）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2VersionDetailViewController : UIViewController

/// profileName = PLProfiles 注册表字典键（ZL2VersionsViewController 卡片同源）
- (instancetype)initWithProfileName:(NSString *)profileName;

/// 实例名→游戏目录绝对路径解析链（ModService.m resolveAbsoluteGameDirForProfile:
/// 同契约：显式 gameDir 优先 → Task225 隔离嗅探 → POJAV_GAME_DIR 兜底）。
/// 全部子页文件枚举走此口径。
+ (NSString *)ameV13_resolvedGameDirForProfileName:(NSString *)profileName;

@end

NS_ASSUME_NONNULL_END
