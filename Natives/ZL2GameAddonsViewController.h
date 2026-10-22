//
// ZL2GameAddonsViewController.h — ZL2 Addons 加载器选择屏（7.0-UI-14 全页面全逻辑移植第三轮）
//
// 移植对象：ZalithLauncher2 DownloadGameWithAddonScreen.kt（GNU GPL 参考副本，只读）。
// ZL2 语义：选版屏点版本卡 → 导航至 Addons 屏（游戏版本固定，选择可选加载器，
//   组合出最终安装描述）→ 安装。本页 1:1 对齐：
//   ① 顶部 ScreenHeader：游戏版本大字 + 自定义版本名输入框 + 安装按钮
//   ② 加载器选择卡（AddonListLayout 同构，可展开收起）：
//      OptiFine / Forge / NeoForge / Fabric / Fabric API
//      - 头部 = 图标 + 标题 + 当前选中值 + 清除钮 + 刷新钮 + 展开箭头
//      - 展开 = 版本单选列表（收起动画 0.18s）
//   ③ 互斥语义（ZL2 ModLoader 家族 + 旧 ModLoaderInstallViewController 判例同口径）：
//      - forge 与 fabric/neoforge 互斥（四加载器互斥族）
//      - optifine 仅可与 forge 共存（与 fabric/neoforge 互斥）
//      - fabric API 依赖 fabric；选中 fabric 自动跟随最新 Fabric API
//      - 互斥冲突时清除既有选择（ZL2 incompatibleSet.clear() 语义）
//   ④ 安装分发（iOS 侧沿用久经考验的 legacy 链，UI 全 ZL2）：
//      - 纯原版 → MRDT downloadVersion（ZL2GameDownloadViewController 同款五键
//        版本隔离 profile + 六阶段任务）
//      - Forge → ForgeInstallViewController（preset 直入方案选择）
//      - NeoForge → ForgeInstallViewController(isNeoForge)
//      - Fabric(+API) → FabricInstallViewController
//      - OptiFine（单独或 forge 组合）→ installOptiFineAsPatch 1:1 移植
//        （BMCLAPI 优先 + 官方兜底 + launchwrapper tweaker 版本 JSON + PLProfiles）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2GameAddonsViewController : UIViewController

/// 目标 Minecraft 版本 id（选版屏传入，只读锚）
@property (nonatomic, copy, readonly) NSString *gameVersion;

- (instancetype)initWithGameVersion:(NSString *)gameVersion;

@end

NS_ASSUME_NONNULL_END
