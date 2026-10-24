//
// PLJITGate.h — 启动续链 JIT 门禁共享助手（Task323）
//
// 病历（用户装机 203d22b latestlog 实锤）：ZL2 新主页（ZL2HomeViewController）
// 的启动链是断头路——下载/校验 100% 后 KVO 分支仅收尾刷新（task=nil + 恢复
// 交互 + ReloadProfileList）即终止，整条 invokeAfterJITEnabled → JIT 深链 →
// SurfaceViewController → launchJVM → JLI_Launch 链路停留在退役旧壳三份私有
// 拷贝里（LauncherRightPanelViewController / LauncherNavigationController /
// DownloadViewController），新 UI 主路径从未可达 = 点启动后静默无后续
// （latestlog 无 [JIT]/[SurfaceSwap]/[JavaLauncher] 痕迹，与旧版 6.5.5 同
// LC 环境可正常起游戏形成对照——旧版活跃 UI 内嵌完整链路）。
//
// 本文件把 RightPanel 版 Task134 门禁状态机（汇聚 Task169/172/176/179/181/
// 182/185/223/226/267/281/294/295 全部病历修复）提取为无状态类方法，供
// ZL2 域启动链消费。退役旧壳三份拷贝保持原样（行为不变，后续轮次再收敛）。
//
// 语义入参：
//   handler    JIT 就绪后的启动续链（UIKit_launchMinecraftSurfaceVC ...）
//   hostVC     弹窗宿主（等待框 present / popover 锚点）
//   onAbandon  用户取消等待 → 弃启回调（调用方恢复交互态：task=nil 等）
//   onStage    阶段文案回调（调用方状态行展示，如"等待 JIT"；可为 nil）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLJITGate : NSObject

/// JIT 门禁主入口（LauncherRightPanelViewController invokeAfterJITEnabled:
/// 状态机 1:1 移植）：isJITEnabled 快路径 → TXM 存活性复查/重挂 →
/// TrollStore/深链分发（debug.jit_enabler 八选项）→ 等待环（120s+Task226
/// 静默自动重拉一轮）→ handler / onAbandon。
+ (void)invokeAfterJITEnabledWithHandler:(void(^)(void))handler
                                  hostVC:(UIViewController *)hostVC
                               onAbandon:(void(^)(void))onAbandon
                                 onStage:(void(^)(NSString *stageText))onStage;

@end

NS_ASSUME_NONNULL_END
