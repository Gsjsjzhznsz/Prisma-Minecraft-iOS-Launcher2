# Task440 退役收尾 · A7 功能清点清单（随删附档）

> 家法依据：第 10 期复核报告 7.1 表 9 批次二验收标准「功能清点清单随删附（A7 制度化）」。
> 本清单为 7 个退役页在删除时刻的功能底账：每个功能、最后的活路径、替代去处。
> 退役执行轮：Task440（第 11 期批次二收尾）；物理删除 14 文件（7 类 × .h/.m）。

## 一、批次④漏网旧三版本列表页

### ModVersionViewController（唯一活页——Task440 改道后退役）
| 功能 | 最后活路径 | 替代去处 |
| --- | --- | --- |
| 版本列表内跳（模组卡点按 → 拉版本 → 选中即装） | ZL2VersionPages.m ameV13_cardTapped: → ameV13_pushVersionListWithProjectId:source:path:（Task413 内跳轨） | **ZL2VersionListPage Mod 域**（Task440 改道：modItem/pageTitle/apiSource/preferred* 参数映射；下载流收口 zl2VersionListPage:didSelectVersion: → ModService.downloadMod 直下目标实例，Task265 锁定语义由宿主 ameV13_profileName 闭包保持） |
| 依赖行直跳（ame236_openDependencyDownload:） | ModVersionViewController.m :1310-1332（页内自推） | ZL2VersionListPage 自身版本列表 + ModService 下载链（依赖遍历入口由资产搜索域承接） |
| 「前往下载页」前置详情（ame235_openDownloadPage） | ModVersionViewController.m :1765-1786（页内自推） | ZL2VersionListPage 详情头 + 版本行直选 |
| Ame232DepDetailViewController 依赖详情内嵌类 | ModVersionViewController.m 文件内（:31 起） | 随宿主页退役；ZL2VersionListPage 无依赖详情子页（功能损失登记为「低频路径收编」） |

### AssetVersionViewController / ShaderVersionViewController（零 push 死页）
| 功能 | 最后活路径 | 替代去处 |
| --- | --- | --- |
| 资源包/数据包/存档版本列表 + 下载 | 全仓零 push（仅 import + delegate 残段） | **ZL2VersionListPage Asset 域**（Task436 已落，ame436_handleAssetDomainVersion 活链） |
| 光影版本列表 + 下载 | 全仓零 push | **ZL2VersionListPage Shader 域**（Task436 已落，ame436_handleShaderDomainVersion 活链） |

## 二、死代码六件

| 页 | 功能（删除时刻均运行时不可达） | 最后引用形态 | 替代去处 |
| --- | --- | --- | --- |
| AccountLoginViewController | 一代四选一登录卡 | 零 import/零实例化（Task436 批次②①断链后仅剩注释） | ZL2 账户页族（actionSheet 四类登录 :1265-1300） |
| ProfileSettingsViewController | 一代实例设置长页（渲染器行/内存滑条/完整性行等） | FabricInstall.m:284 死类内实例化 + ZL2Versions.m:57 死 import + Preview 桩 | ZL2VersionDetailViewController 容器（八子页：概览/模组/存档/资源包/光影/截图/服务器/配置）+ ZL2SettingPages 全局组 |
| FabricInstallViewController | 一代 Fabric 安装向导 | 全仓零实例化（ame336/ame335 门禁已断言） | ZL2 下载页 fabric 安装链 |
| WelcomeViewController | 一代首启三步向导（语言/下载源/数据导入） | presentIfNeeded 零 caller（Task436 A3 断链后成死代码） | **留白为有意取舍（本轮定案）**：新 UI 域暂不补向导——ZL2 语义由壳层默认即用 + 设置页可达；如后续用户复诉首启引导再立项 |
| AssetVersionViewController | 见上表（并入旧三页） | import + delegate 残段 | ZL2VersionListPage Asset 域 |
| ShaderVersionViewController | 见上表（并入旧三页） | import + delegate 残段 | ZL2VersionListPage Shader 域 |

## 三、随批同步项（③ 文档/腐烂族）

| 项 | 处置 |
| --- | --- |
| ZL2VersionsViewController.h:13/:19、.m:30-31/:61-62/:1060/:1203 失实「push ProfileSettingsViewController」注释 | 改写为 ZL2VersionDetailViewController 现实 + Task440 校正注记 |
| LauncherPreferences.m:854、utils.h:541、ForgeDirectInstaller.m:452、NeoForgeDirectInstaller.m:630、TouchControllerPreferencesViewController.m:286 现时态旧页引用注释 | 改写为 ZL2 实例页族现实 + 墓碑注记（★Task440） |
| CMakeLists.txt:660（原 ：660）「used by DownloadViewController」悬空注释 | 改为 Task440 注记（VersionCardCell.m 零活消费、暂留编译清单登记） |
| MinecraftResourceDownloadTask.m:1361 引用已删 DownloadViewController.m:5604 | 改为 ZL2AssetSearch 主线程 post 口径 + 引注校正 |
| AiPluginDocsTool.m news_url / announcement_preview_level / welcome_completed 三退役键文档行 + 计数链（106→103 键、212→206 操作、413→407 API） | 摘除 + 重锚（ame366 D1 同步） |
| PLPreferences.m announcement_preview_level / welcome_completed 注册条目 | 摘除 + 家法注释尾（存量 plist 残值自然失活） |
| verify_task189.py（检查已删文件单跑必红） | 重生为退役面验收门（R1-R5） |
| verify_task188.py F1 标签漂移 | 重锚 ZL2ControlRepoViewController |
| verify_task136/162/227/235/236/238（撰写轮早于两批退役，主体文件离场） | 退役容错壳（[RETIRED] 诚实降级，存留面断言继续生效）——同族腐烂后续轮收编 |
| ame369.vpage.full_instance_settings 孤儿 i18n 键（四表） | 按「旧键不删」家法登记不删（zh-CN:3787 / zh-Hant:3788 / zh-Hans:3790 / en:3791，全仓零代码消费） |

## 四、删除文件清单（14）

Natives/ModVersionViewController.{h,m}、Natives/AssetVersionViewController.{h,m}、
Natives/ShaderVersionViewController.{h,m}、Natives/AccountLoginViewController.{h,m}、
Natives/ProfileSettingsViewController.{h,m}、Natives/installer/FabricInstallViewController.{h,m}、
Natives/WelcomeViewController.{h,m}；CMakeLists 同步摘 7 条目；Preview/ZL2PagesStub.m
摘 ProfileSettings 桩 + 旧三版本页桩块。
