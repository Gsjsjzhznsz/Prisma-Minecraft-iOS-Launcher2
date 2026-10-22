//
// ZL2SettingsViewController.h — ZL2 设置「左轨八屏 + 右内容」枢纽页（7.0-UI-13-S）
//
// 对标：ZalithLauncher2 ui/screens/content/SettingsScreen.kt——左轨 8 项分
// 3 组（渲染器/游戏/控制/手柄/启动器｜Java 管理/控制管理｜关于，组间
// 0.4 alpha onSurface 分隔线）+ 右侧内容区（子页切换非 push，0.18s
// crossDissolve）。8 个子页 VC 在 ZL2SettingPages.h（ZL2SettingPage 基类
// + 八个子类），ZL2 风格设置行卡组件在 ZL2SettingCards.h（SettingsCard
// 连体拼接组 + Switch/Slider/List/Input/Action/Enum 六种行卡）。
//
// 导航约定：根页隐藏系统栏（viewWillAppear 隐藏 / viewWillDisappear 恢复），
// 子页 push 旧页到 self.navigationController（push 后系统栏随子页显示，
// 返回本页再隐藏）。集成方需把本页包在 UINavigationController 内作为
// 设置页根（ZL2Shell page 4 现行做法，零改动）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2SettingsViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
