//
// ZL2DownloadViewController.h — ZL2 风格下载页（7.0-UI-9-a 分类 M3 重写；
// 7.0-UI-10-a 六类语义纠错：ZL2 下载页六类全部为远程搜索下载，本地管理器
// 在 ZL2 属版本管理域，错配已撤除）
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
// 六类目标 VC（7.0-UI-10-a 真语义）：
//   游戏 DownloadViewController（旧远程游戏版本页，M3 化留下一轮）/
//   整合包·模组·资源包·存档·光影包 → ZL2AssetSearchViewController
//   （通用 M3 远程搜索列表，五型参数化；版本/安装流 1:1 复用旧
//   DownloadViewController 远程下载链：ModVersion/ShaderVersion/
//   AssetVersion 三版本页 + 五 Item 在线数据模型）
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
