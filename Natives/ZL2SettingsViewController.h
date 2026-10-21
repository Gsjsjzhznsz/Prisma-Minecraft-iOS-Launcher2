//
// ZL2SettingsViewController.h — ZL2 风格设置枢纽页（7.0-UI-9-d：四功能页 M3 重写）
//
// 对标：ZalithLauncher2 ui/screens/content/SettingsScreen.kt（左轨 8 类 +
// 右侧 SettingsCardColumn 拼接圆角组卡）。本仓设置子页未按 ZL2 八类拆分
//（无八轨可指），禁止造假双轨——本页做成 ZL2 视觉的「分组枢纽列表」：
// M3 组卡（surfaceContainer 底 / radiusM 圆角 / 行连续拼圆角 / 0.5pt
// outlineVariant 分隔线），组名不显示文本，每行 push 到既有真实子页。
//
// 导航约定：根页隐藏系统栏（viewWillAppear 隐藏 / viewWillDisappear 恢复），
// 行点击 push 到 self.navigationController（push 后系统栏随子页显示）。
// 集成方需把本页包在 UINavigationController 内作为设置页根。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2SettingsViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
