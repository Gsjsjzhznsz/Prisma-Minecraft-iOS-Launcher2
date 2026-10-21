//
// ZL2HomeViewController.h — ZL2 风格主页（7.0-UI-8：全面对标 ZalithLauncher 2）
//
// 信息架构对标 ZL2 主页：问候区 + 账户卡 + 版本选择卡 + 大圆形启动按钮 +
// 快捷入口 chips。启动链复用全局契约（BaseAuthenticator / PLProfiles /
// FindVersionInRemoteList 回调通知 / MinecraftResourceDownloadTask 统一
// 注册进度页），与旧右面板 UI 完全解耦。
//
// 导航协议：本页不直接 push 任何页面——切页需求一律经壳的通知契约：
//   @"ShowAccountManager"  → 壳切到账户页
//   @"ZL2ShellNavigate"    → 壳切页（userInfo[@"index"] = @(pageIndex)）
//   @"ShowHomePage"        → 壳切回主页（启动链既有契约，兼容旧监听方）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2HomeViewController : UIViewController

// 启动按钮态刷新（账号/profile/下载任务三态：启动游戏 / 登录并启动 / 下载中）。
// viewWillAppear 与 @"UpdateAccountInfo" 通知均会自动触发；壳侧也可手动调。
- (void)refreshLaunchState;

@end

NS_ASSUME_NONNULL_END
