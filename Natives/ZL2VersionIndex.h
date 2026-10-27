//
// ZL2VersionIndex.h — 版本索引服务（7.0-UI-11：ZL2 壳启动链修复）
//
// 【为什么存在】启动链契约 @"FindVersionInRemoteList" 的监听者原本只在旧壳
// LauncherRootViewController（远程清单 + 内存本地快照 + Task72 磁盘兜底）。
// 7.0-UI-8 起根壳一律 ZL2ShellViewController，旧壳不再实例化 → ZL2Home 的
// 启动按钮把通知发进虚空，回调永不触发 = 启动按钮坏死（用户"入口功能配错"
// 的直接来源）。本服务把这段查找逻辑从旧壳 VC 抽成 ZL2 域单例，监听同一
// 契约通知，ZL2HomeViewController 零改动。
//
// 查找语义与旧壳逐条对齐（LauncherRootViewController findVersionInRemoteList:）：
//   ① 远程清单命中 → 原始 manifest 条目（type/URL 全字段，未安装版本走
//      MinecraftResourceDownloadTask 全新下载流）
//   ② 本地 versions/ 目录扫描命中（POJAV_GAME_DIR 优先、POJAV_HOME 兜底，
//      ZL2VersionsViewController 无效版本判定同口径）→ @{id, type=custom}
//      （已安装版本启动路径）
//   ③ <id>.json 直查磁盘兜底（Task72 语义：列表快照过期不误杀已装版本）
//   ④ 全空 → callback(nil)（ZL2Home 弹"找不到版本信息"并恢复交互）
//
// 与旧实现的一处强化：远程清单拉取改为"启动预热 + 查找期在途等待"——
// 旧实现壳 viewDidLoad 异步拉一次，用户秒点启动且目标版本未安装时清单
// 可能尚未落袋，误弹"找不到版本"；本服务 warmUp() 在壳 viewDidLoad 预热，
// 查找未命中且清单在途时限时等待（10s 封顶），消除该竞态。已装版本路径
// 永不依赖网络（②③纯磁盘）。
//
// 线程契约：查找全程在私有串行队列执行（磁盘 IO + 网络等待不占主线程）；
// callback 一律回主线程调用（ZL2Home 的回调体操作 self.task 等 UI 域状态，
// 旧壳在主线程通知回调里同步调用，本服务必须保持主线程语义）。
//
// 通知面（只观察，不发送）：
//   @"FindVersionInRemoteList" — 启动链查找（userInfo: versionId + callback）
//   @"ReloadProfileList"       — 远程清单重取（旧 reloadVersionLists 语义的
//                                远程半边；本地半边本服务逐次即时扫描，
//                                无快照无过期）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2VersionIndex : NSObject

+ (instancetype)sharedIndex;

/// 启动预热：幂等触发远程版本清单拉取（ZL2ShellViewController viewDidLoad 调）。
- (void)warmUp;

/// 远程清单快照读取（7.0-UI-12：ZL2GameDownloadViewController 游戏列表用）。
/// 未落定时限时等待（复用查找期预算），回调一律主线程；
/// versions 为清单条目数组（含 latest-* 种子条目——无 url 字段，消费方自滤）；
/// loaded=YES 仅代表候选链已落定（失败也算落定），消费方以"含 url 条目数"
/// 判定成败。
- (void)remoteVersionsWithCompletion:
    (void (^)(NSArray<NSDictionary<NSString *, id> *> *versions, BOOL loaded))completion;

/// 强制重取远程清单（幂等去重在途；重试按钮用）。
- (void)refresh;

/// ★ Task335：远端清单条目同步查找（MRDT 原版下载链专用）。
/// 病历：旧壳 7.0-UI-8 退役后全局 remoteVersionList 恒空，MRDT
/// downloadVersionMetadata: 的 findVersion:inList: 必 nil → 误入本地
/// 版本分支报「未能打开文件 <id>.json」= ZL2 壳下原版安装全量秒败
/// （装机 207353e latestlog：1.20.1/a1.2.6/rd-161348 弹错误对话框 ×150+）。
/// 语义：后台线程调用时限时等待清单落定（复用查找期预算 10s）后锁内
/// 匹配；只返回可下载的远端条目（有 url 字段，latest-* 种子被滤）。
/// 主线程调用不等待（防主线死锁）：仅查已落定快照，未落定返回 nil。
- (nullable NSDictionary<NSString *, id> *)remoteVersionEntryForIdSync:(NSString *)versionId;

@end

NS_ASSUME_NONNULL_END
