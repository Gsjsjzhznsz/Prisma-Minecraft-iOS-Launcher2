//
// ZL2DownloadViewController.h — ZL2 下载页（7.0-UI-14：左轨 8 项真机对齐版）
//
// 对标 ZalithLauncher2 DownloadScreen.kt TabMenu（GNU GPL 参考副本，只读；
// 真机截图 4-12 交叉验证）：左竖轨 + 右内容区双栏。
//
// 结构：
//   ① 左竖轨 8 项 2 分隔线（ZL2 TabMenu downloadsList 顺序 1:1）：
//     游戏 / 整合包 ── 模组 / 资源包 / 存档 / 光影包 ── 按ID搜索 / 收藏
//     （M3 NavigationRailItem 语义：图标 22 + label 11；选中 = primaryContainer
//     圆角胶囊 + onPrimaryContainer；分隔线 = onSurface 0.4 alpha 宽 40%）
//   ② 内容容器（懒建缓存 + addChild + 四边钉入 + 0.18s crossDissolve）：
//     0 游戏 ZL2GameDownloadViewController（7.0-UI-14 截图对齐重写）
//     1-5 ZL2AssetSearchViewController（整合包/模组/资源包/存档/光影包）
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
//   selectedIndex = 左轨预选项（0 游戏/1 整合包/2 模组/3 资源包/4 存档/
//   5 光影包/6 数据包/7 按ID/8 收藏/9-11 仓库三件；必须在 view 加载前置定，
//   viewDidLoad 首选即用；未设 = 0 游戏页）。
//   targetProfileName = 下载目标实例透传（Task265 语义保留：管理页绑定实例
//   ≠ 当前选中实例时，下载写入目标仍随管理页；nil = 沿当前选中快照）。
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) NSString *targetProfileName;

@end

NS_ASSUME_NONNULL_END
