//
// ZL2GameDownloadViewController.h — 游戏 M3 下载页（7.0-UI-12）
//
// 移植对象：ZalithLauncher2 DownloadGameScreen.kt → SelectGameVersionScreen.kt
//   （GNU GPL 参考副本，只读）。ZL2 游戏下载 = 版本选择列表（类型筛选 +
//   搜索）→ 选中即装；本页同语义：M3 搜索框 + 类型筛选 chips + 版本卡
//   列表（分页）→ 点卡弹 M3 底部弹层（版本详情 + 安装钮）→ M3 对话框
//   确认 → 旧管线安装（PLProfiles 建版本隔离 profile + MinecraftResource
//   DownloadTask downloadVersion:，六阶段统一进度页自动弹出）。
//
// 取代：旧 DownloadViewController（6080 行下载中心）被嵌入 ZL2 下载页
//   "游戏"签的最后残留（用户连报"旧页面残留"的实锤之一）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2GameDownloadViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
