//
// ZL2SearchIdViewController.h — ZL2 按项目 ID 直查页（7.0-UI-14 下载域第 6 项）
//
// 移植对象：ZalithLauncher2 SearchIdScreen.kt（GNU GPL 参考副本，只读）。
// ZL2 语义：输入项目 ID/别名 + 选平台 → 查询单项目 → 展示信息卡 → 跳对应
//   分类详情页。iOS v1 范围：查询 + 信息卡 + 收藏 + 浏览器打开。
// ★Task432 实锤三（查询→下载闭环）：
//   · 结果卡「前往下载」真按钮 = 按 projectType（Modrinth）/ classId（CurseForge）
//     路由到宿主下载壳对应轨（mod→模组/modpack→整合包/resourcepack→资源包/
//     shader→光影/world→存档），轨内打开本项目版本详情/安装页，版本页
//     delegate = 轨搜索页（ZL2AssetSearchViewController），下载/依赖解析/
//     安装分流全链复用（参照 SearchIdScreen.kt onView → swapToDownload →
//     swapToCategoryAddon 语义）；无对应轨的类型（datapack 等）不给按钮。
//   · 截图卡 = Modrinth 源拉 /project/{id} 响应自带 gallery 数组（ZL2
//     ModrinthSingleProject.gallery 同源字段，取前 3 张）；单图加载失败自撤、
//     行清空整段收起（不虚构占位图）；CurseForge 源无截图不显示。
//   · mcmod 中文资料卡 = search.mcmod.cn/s?key=<项目名> 外链（不虚构 API）。
//   · 轨定位跳过收藏轨（initWithFavorites 的 assetType=Mod 仅占位，防冒充
//     真轨）；轨页搜索框无公开预填属性——项目 id 经条目字典直进版本页。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2SearchIdViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
