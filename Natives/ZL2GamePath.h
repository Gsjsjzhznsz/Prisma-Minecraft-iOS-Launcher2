// ZL2GamePath.h —— ★Task473: ZL2（ZalithLauncher2 上游）版本隔离系统移植·单一入口
// 全部游戏内容操作（启动 chdir / mods / 存档 / 资源包 / 光影 / 备份恢复 /
// 导出 / 版本页文件操作）一律经本系统解析，禁止各自拼装（Task472 前复制管线判例）。
// 语义对齐上游 Version.getGameDir()（ZalithLauncher2 b6310dd）：
//   isolationType 三态存 versions/<vid>/prisma/version.config（JSON 键 isolationType）：
//     FOLLOW_GLOBAL → 折叠全局档 versionIsolation（PLPreferences，默认 NO）
//     ENABLE → 版本目录 versions/<vid>/（版本夹即 .minecraft——PCL2/HMCL/FCL 通例）
//     DISABLE → 主游戏根（共享根）
//   未隔离时实例自定义路径（profile.gameDir 非隔离形态值）优先于主根（上游 customPath 分支同构）；
//   历史隔离形态值（versions/<vid>[//game]）惰性不读（Task472 退役语义延续）；
//   整合包导入强制开启（上游 createIsolationForModPack 同构）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZL2IsolationType) {
    ZL2IsolationFollowGlobal = 0,
    ZL2IsolationEnable       = 1,
    ZL2IsolationDisable      = 2,
};

@interface ZL2GamePath : NSObject
/// 主游戏根（POJAV_GAME_DIR 优先 POJAV_HOME 兜底——共享 versions/assets/libraries 所在根）
+ (NSString *)gameHome;
/// versions/<vid>/（主根下；版本隔离开启时 = 游戏数据根）
+ (NSString *)versionPathForVersion:(NSString *)vid;
/// versions/<vid>/prisma/version.config（每版本配置，ZL2 同位同键）
+ (nullable NSString *)configPathForVersion:(NSString *)vid;
+ (ZL2IsolationType)isolationTypeForVersion:(NSString *)vid;
+ (void)ame473_setIsolationType:(ZL2IsolationType)type forVersion:(NSString *)vid;
/// 全局默认档（versionIsolation 偏好，默认 NO = 存量共享根用户零回归）
+ (BOOL)globalIsolationDefault;
/// 三态折叠：ENABLE=YES / DISABLE=NO / FOLLOW_GLOBAL=全局档
+ (BOOL)isIsolationForVersion:(NSString *)vid;
/// ★单一入口（版本轴）
+ (NSString *)gameDirForVersion:(NSString *)vid;
/// ★单一入口（实例轴：nil/空跟随选中实例——ame267 语义）
+ (NSString *)gameDirForProfile:(NSString *)profileName;
/// 整合包导入强制隔离（上游 createIsolationForModPack 同构；幂等）
+ (void)applyIsolationForModPackVersion:(NSString *)vid;
/// 历史隔离形态值判定（versions/<vid> / versions/<vid>/game ——惰性不读）
+ (BOOL)isIsolationFormGameDir:(NSString *)gameDir;
@end

NS_ASSUME_NONNULL_END
