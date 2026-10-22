//
// ZL2HomeViewController.h — ZL2 真布局主页（7.0-UI-13-H：LauncherScreen 7:3 双栏）
//
// 信息架构对标 ZalithLauncher2 LauncherScreen 真结构（告别单列堆叠）：
//   整体 Row = 左内容区（weight 7）+ 右 ActionMenu（宽 = 容器 3/10，
//   clamp[240, 320]）；ActionMenu 停靠左/右持久化
//   （NSUserDefaults "zl2.home.actionMenuSide"，长按菜单卡切换停靠边）。
//   · ActionMenu（自上而下）：账号卡（48 圆头像 + 用户名 + 类型小字，
//     点击 → @"ShowAccountManager"；未登录 = 加号占位）→ 版本选择卡
//     （当前实例名 + 加载器小标签 + 刷新/设置小图标 → @"ZL2ShellNavigate"
//     index=2）→ 大启动按钮（ScalingActionButton 语义：primary 底 /
//     onPrimary 字 / 28 圆角 / 高 48 / 图标+三态文案，锚点
//     accessibilityIdentifier "zl2_home_launch"）。
//   · 内容区：实例卡网格（UICollectionView 2 列 iPhone / 3 列 iPad，
//     间距 6；卡 = surfaceContainer/radiusM + 实例图标 + 实例名 +
//     MC 版本/加载器信息行 + 右下小启动钮。点卡 = 选实例；卡上播放键 =
//     切该实例为选中并直接走启动链；长按卡 = M3 底部菜单：设为当前
//     实例 / 打开版本详情（发 @"ZL2OpenVersionDetail" userInfo
//     @{@"profile": 实例名}，容器由壳接线）/ 删除）。空态 = 「没有安装
//     版本」+「去下载」（ZL2ShellNavigate index=1）。问候区已砍（ZL2 无）。
//
// 启动链复用全局契约（BaseAuthenticator / PLProfiles /
// FindVersionInRemoteList 回调通知 / MinecraftResourceDownloadTask 统一
// 注册进度页），三态（账号态/版本态/下载任务）逻辑与旧版 1:1。
//
// 导航协议：本页不直接 push 任何页面——切页需求一律经壳的通知契约：
//   @"ShowAccountManager"  → 壳切到账户页
//   @"ZL2ShellNavigate"    → 壳切页（userInfo[@"index"] = @(pageIndex)）
//   @"ShowHomePage"        → 壳切回主页（启动链既有契约，兼容旧监听方）
//   @"ZL2OpenVersionDetail"→ 版本详情容器（壳接线；userInfo[@"profile"]）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2HomeViewController : UIViewController

// 启动按钮态刷新（账号/profile/下载任务三态：启动游戏 / 登录并启动 / 下载中）。
// viewWillAppear 与 @"UpdateAccountInfo" 通知均会自动触发；壳侧也可手动调。
// 同时重建实例网格（@"SelectedProfileChanged"/@"ReloadProfileList" 同链）。
- (void)refreshLaunchState;

@end

NS_ASSUME_NONNULL_END
