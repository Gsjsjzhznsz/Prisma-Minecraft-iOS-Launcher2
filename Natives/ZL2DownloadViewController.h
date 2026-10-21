//
// ZL2DownloadViewController.h — ZL2 风格下载页（7.0-UI-9-a：下载页分类 M3 重写）
//
// 对标 ZalithLauncher2 DownloadScreen.kt（左类别轨+内容区，本页适配为
// 「大标题 + 横向类别 chips + 内容容器」，chips 为主页 TextRailItem 同款
// 模式的横排变体，iPhone/iPad 双 idiome 通用）。
//
// 结构（自上而下）：
//   ① 页头行 —— 大标题「下载」（fontTitleLarge / onSurface）居左；右侧
//     任务胶囊（仅 DownloadTaskManager.hasActiveTasks 时显示：高 32 胶囊内含
//     60×3 进度条 + assignment 类 SF 图标 + 任务数；点按第一个活动任务调
//     [PLTaskProgressViewController presentForTaskId:]）
//   ② 类别 chips 横向滚动行（高 40，六类，默认选中第 0 项）
//   ③ 内容容器（占满余下空间；目标 VC 按类别懒建缓存，四边钉入 +
//     hidden 切换 0.18s crossDissolve，与 ZL2ShellViewController 同款手法）
//
// 六类目标 VC（存量页原样嵌入，本页只负责 ZL2 结构壳）：
//   游戏 DownloadViewController / 整合包 ModpackImportViewController /
//   模组 ModsManagerViewController / 资源包 ResourcePacksManagerViewController /
//   存档 WorldsManagerViewController / 光影包 ShadersManagerViewController
//
// 导航：本页由壳包在 UINavigationController 里，根页 viewWillAppear 隐藏
// 系统栏、viewWillDisappear 恢复（push 出去的旧子页才有返回栏，pop 回自动隐藏）。
//
// 通知面：只监听（DownloadTaskManager 两枚通知刷新任务胶囊），零发送。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2DownloadViewController : UIViewController

// 指定初始化器（默认选中类别 0 = 游戏；任务胶囊态随 viewWillAppear 与
// DownloadTaskManager 通知自动刷新）
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
