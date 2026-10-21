//
// ZL2VersionsViewController.h — ZL2 风格版本管理页（7.0-UI-9-b：对标
// ZalithLauncher 2 VersionsManageScreen）
//
// 信息架构对标 ZL2 版本管理页（本仓单游戏目录，不做左侧目录栏）：
//   页头行（大标题「版本」+ 刷新/安装新游戏两枚图标按钮）
//   → 分类 chips（全部 / 原版 (n) / 可安装模组 (n)，计数由加载器识别推导）
//   → 版本卡列表（单选圈 + 加载器图标 + 名称/描述/标签行 + 设置/更多按钮）
//   → 空态（archivebox + 「没有安装版本」）
//
// 交互契约（与旧 VersionManagerViewController 1:1）：
//   点卡片        = 选用该实例（PLProfiles 持久化 + @"SelectedProfileChanged"）
//   设置按钮      = push ProfileSettingsViewController（旧 VC editProfile: 同款）
//   更多按钮      = actionSheet 删除（旧 VC deleteProfile: 全链 1:1 移植）
//   刷新按钮/通知 = @"ReloadProfileList" / @"SelectedProfileChanged" 重拉重建
//   安装新游戏    = @"ZL2ShellNavigate" index=1 切下载页（壳契约）
//
// 导航约定：根页 viewWillAppear 隐藏系统导航栏，viewWillDisappear 恢复
// （push 出去的 ProfileSettingsViewController 自带返回栏）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2VersionsViewController : UIViewController

// 全量刷新：[PLProfiles updateCurrent] 重拉注册表 + 重建分类计数与卡片列表。
// viewWillAppear 与 @"ReloadProfileList" / @"SelectedProfileChanged" 通知均会
// 自动触发；壳侧也可手动调。
- (void)reloadVersions;

@end

NS_ASSUME_NONNULL_END
