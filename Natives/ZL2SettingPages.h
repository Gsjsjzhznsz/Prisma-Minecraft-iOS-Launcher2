//
// ZL2SettingPages.h — ZL2 设置八屏子页（7.0-UI-13-S）
//
// 对标：ZalithLauncher2 SettingsScreen.kt 的 8 个 SettingsScreen 子页——
//   Renderer / Game / Control / Gamepad / Launcher / JavaManager /
//   ControlManager / AboutInfo。每个子页 = 垂直滚动 + 分组「连体卡片」
//   （ZL2SettingCards 家族），底部以「更多设置」Action 行 push 对应旧页，
//   保留旧页长尾功能全部可达（全逻辑兜底契约）。
//
// 集成形态：本文件 8 个子页由 ZL2SettingsViewController（左轨八屏枢纽）
//   以 addChildViewController + 四边钉入 + 0.18s crossDissolve 承载，
//   不各自包 nav；子页 push 旧页走枢纽所在 UINavigationController
//   （枢纽根页负责系统栏隐藏/恢复，子页不碰导航栏）。
//
// 偏好键契约：全部读写走既有真键（getPref/setPref 与对应旧页同一口径），
//   写后按旧页先例 post 对应刷新通知；真实键名清单见各页 .m 文件头与
//   worklog 7.0-UI-13-S 档案段。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 子页基类（滚动骨架 + 组卡装配 + push 助手）

@interface ZL2SettingPage : UIViewController

/// 内容栈（组间 2pt 间距，宽 ≤520 居中 / iPhone 占满减边距）
@property (nonatomic, strong, readonly) UIStackView *groupsStack;

/// 追加一个连体组卡到内容栈
- (void)ame_addGroup:(UIView *)group;

/// push 统一入口：子页未自设标题时以 fallbackTitle 兜底（旧页大多在自身
/// viewDidLoad 设 self.title，后于本赋值执行，自动覆盖兜底值）
- (void)ame_push:(UIViewController *)vc titled:(NSString *)fallbackTitle;

/// 切轨选中回调（子页覆写：把外部可变的偏好/文件状态刷进行卡；
/// 基类默认空实现）
- (void)ame_refreshState;

/// 内容重建钩子（子页覆写 ame_buildGroups 装配组卡；viewDidLoad 首建）
- (void)ame_buildGroups;

/// 清空并重建内容（ame_refreshState 需要全量重建的页面调用）
- (void)ame_rebuildGroups;

@end

#pragma mark - ① 渲染器屏

@interface ZL2RendererSettingsPage : ZL2SettingPage
@end

#pragma mark - ② 游戏屏

@interface ZL2GameSettingsPage : ZL2SettingPage
@end

#pragma mark - ③ 控制屏

@interface ZL2ControlSettingsPage : ZL2SettingPage
@end

#pragma mark - ④ 手柄屏

@interface ZL2GamepadSettingsPage : ZL2SettingPage
@end

#pragma mark - ⑤ 启动器屏

@interface ZL2LauncherSettingsPage : ZL2SettingPage
@end

#pragma mark - ⑥ Java 管理屏

@interface ZL2JavaManagerSettingsPage : ZL2SettingPage
@end

#pragma mark - ⑦ 控制管理屏

@interface ZL2ControlManagerSettingsPage : ZL2SettingPage
@end

#pragma mark - ⑧ 关于屏

@interface ZL2AboutSettingsPage : ZL2SettingPage
@end

NS_ASSUME_NONNULL_END
