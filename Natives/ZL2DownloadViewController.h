//
// ZL2DownloadViewController.h — ZL2 下载页（7.0-UI-14：左轨 8 项真机对齐版；
//   Task432 八轨收敛对齐）
//
// 对标 ZalithLauncher2 DownloadScreen.kt TabMenu（GNU GPL 参考副本，只读；
// 真机截图 4-12 交叉验证）：左竖轨 + 右内容区双栏。
//
// 结构（★Task432 八轨收敛：轨序/divider 位 1:1 回归 ZL2 原版；摘除 Task323
//   自造超集——数据包轨→版本子页第九子页（SB 工位）、三仓库轨→设置·控制
//   管理域（SD 工位））：
//   ① 左竖轨 8 项 2 分隔线（ZL2 TabMenu downloadsList 顺序 1:1）：
//     游戏 / 整合包 ── 模组 / 资源包 / 存档 / 光影包 ── 按ID搜索 / 收藏
//     （M3 NavigationRailItem 语义：图标 22 + label 11；选中 = primaryContainer
//     圆角胶囊 + onPrimaryContainer；分隔线 = onSurface 0.4 alpha 宽 40%）
//   ② 内容容器（懒建缓存 + addChild + 四边钉入 + 0.18s crossDissolve）：
//     0 游戏 ZL2GameDownloadViewController（7.0-UI-14 截图对齐重写）
//     1-5 ZL2AssetSearchViewController（整合包/模组/资源包/存档/光影包；
//        存档轨 Task432 起 Modrinth+CurseForge 双源）
//     6 ZL2SearchIdViewController（按项目 ID 直查）
//     7 ZL2AssetSearchViewController initWithFavorites（收藏仓库直出）
//
// 任务胶囊删除（壳顶栏已有同款 taskPill）；导航栏约定与红线遵守同 7.0-UI-9
// 契约不变（颜色/字体/圆角一律 ZL2Theme、iOS 14 API 上限、SF 符号 SF1.0 级）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2DownloadViewController : UIViewController

// ★ Task324：管理器"去下载"改道入口（下载 UI 全面 ZL2 风格）。
//   selectedIndex = 左轨预选项（★Task432 八轨口径：0 游戏/1 整合包/2 模组/
//   3 资源包/4 存档/5 光影包/6 按ID搜索/7 收藏；必须在 view 加载前置定，
//   viewDidLoad 首选即用；未设 = 0 游戏页。既有调用方 0/2/3/4 语义不变）。
//   targetProfileName = 下载目标实例透传（Task265 语义保留：管理页绑定实例
//   ≠ 当前选中实例时，下载写入目标仍随管理页；nil = 沿当前选中快照）。
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) NSString *targetProfileName;

@end

NS_ASSUME_NONNULL_END
