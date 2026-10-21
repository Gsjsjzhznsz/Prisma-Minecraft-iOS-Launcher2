//
// ZL2ShellViewController.h — ZL2 风格导航壳（7.0-UI-8：全面对标 ZalithLauncher 2）
//
// 取代旧 LauncherCardLayoutViewController / LauncherRootViewController 成为
// 新默认根壳（SceneDelegate：general.ui_layout 未写盘用户默认进本壳；
// 显式写盘 card/vs 的存量设备保留旧路径兼容，旧类不删——游戏域桥接仍引用）。
//
// 结构：左侧 M3 NavigationRail（iPhone 88pt / iPad 104pt，active 胶囊
// primaryContainer + 12pt 标签）+ 右侧内容区（child VC 切换）。
// 页面序：0 主页(ZL2Home) / 1 下载(Download) / 2 版本管理(VersionManager)
//         / 3 账户(AccountList) / 4 设置(LauncherPreferences)
//
// 通知契约（消费方）：
//   @"ShowHomePage"        → 切主页（旧启动链既有通知，直接兼容）
//   @"ShowAccountManager"  → 切账户页（旧 FCL 风格契约，直接兼容）
//   @"ZL2ShellNavigate"    → 切页（userInfo[@"index"] = @(0...4)）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ZL2ShellNavigateNotification;

@interface ZL2ShellViewController : UIViewController

// 程序化切页（0...4，越界忽略）
- (void)showPageAtIndex:(NSInteger)index;

// NavigationRail 宽度（iPhone 88 / iPad 104，供 harness/测试断言）
+ (CGFloat)railWidthForSizeClass:(UIUserInterfaceIdiom)idiom;

@end

NS_ASSUME_NONNULL_END
