#import <Foundation/Foundation.h>

@interface PLProfiles : NSObject

@property(nonatomic) NSString *profilePath;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *> *profileDict;

+ (PLProfiles *)current;
+ (void)updateCurrent;

+ (id)profile:(NSMutableDictionary *)profile resolveKey:(id)key;
+ (NSString *)resolveKeyForCurrentProfile:(id)key;

- (id)initWithCurrentInstance;
- (NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *)profiles;

- (NSMutableDictionary<NSString *, NSString *> *)selectedProfile;
- (NSString *)selectedProfileName;
- (void)setSelectedProfileName:(NSString *)name;
- (void)save;

// 新增：修复构建错误 - 添加缺失的方法声明
- (void)saveProfile:(NSMutableDictionary<NSString *, NSString *> *)profile withName:(NSString *)name;

/// Task275 F6：锁内批量变更 API——外部对 `profiles` 活字典的裸写（后台导入
/// 线程 vs 主线程写者）构成“枚举中变更”崩溃面与读改写丢更新；统一收口：
/// block 在实例锁内直接改活字典，出锁前自动 save（save 同锁可重入）。
- (void)applyChanges:(void (NS_NOESCAPE ^)(NSMutableDictionary<NSString *, id> *profiles))changes;

/// ★ Task349：孤儿实例目录收编——扫描 POJAV_HOME/instances/* 真实目录，凡
///   注册表（launcher_profiles.json）无对应条目者按目录名登记（gameDir 绝对
///   路径锚定，Task316 判例；lastVersionId 尽力从实例自带 launcher_profiles.json
///   回读），一并处理一代全局注册表（POJAV_HOME/launcher_profiles.json）在
///   现役注册表尚为出厂默认单条时的合并导入（成功后改名归档防复燃）。
///   幂等、只增不改：同名键 / gameDir 命中 / 当前游戏目录 / 隐藏与符号链接
///   与空目录一律跳过，绝不触碰既有条目与选中态。有新登记时主队列投递
///   ReloadProfileList。返回新登记条数（含一代合并）。tag 仅用于日志定位
///   （"import" = 导入收尾 / "startup" = 启动期）。
+ (NSUInteger)ame349_reconcileOrphanInstancesLogTag:(NSString *)tag;

/// ★ Task353：启动期版本根对齐——求该 profile 的版本根 R（满足
///   R/versions/<vid>/<vid>.json 真实存在），供启动链把 POJAV_GAME_DIR 对齐
///   到 profile 自洽根（ZL2VersionIndex 本地扫描 / MRDT versions/<id> 落位 /
///   Java DIR_HOME_VERSION 三段同根；病历与修法见 .m 实现注）。纯读零副作用；
///   latest-* 别名 / 未选版本 / 实体不在磁盘返回 nil（正常下载流不受影响）。
+ (NSString *)ame353_versionRootForProfileName:(NSString *)profileName;

// 服务器地址（FCL 风格：启动后自动加入服务器，留空则不加入）
- (NSString *)serverIpForCurrentProfile;
- (NSString *)serverIpForProfile:(NSString *)profileName;
- (void)setServerIp:(NSString *)serverIp forProfile:(NSString *)profileName;

@end
