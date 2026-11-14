//
//  LauncherPrefContCfgViewController.h
//  ★Task428（428-G）：手柄映射编辑页原地重做——基类由裸 UITableViewController
//   换为 ZL2 设置页基类 ZL2SettingPage（滚动骨架 + 页首大标题 + 连体组卡装配），
//   入口 ZL2SettingPages.m 仍以 [[…alloc] init] + ame_push:titled: 消费，零改动。
//
#import "ZL2SettingPages.h"

NS_ASSUME_NONNULL_BEGIN

@interface LauncherPrefContCfgViewController : ZL2SettingPage
@end

NS_ASSUME_NONNULL_END
