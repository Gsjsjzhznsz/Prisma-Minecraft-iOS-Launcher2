#import <Foundation/Foundation.h>

// 下载源偏好键（按资源类型独立）
extern NSString *const PREF_DOWNLOAD_SOURCE_MOD;
extern NSString *const PREF_DOWNLOAD_SOURCE_SHADER;
extern NSString *const PREF_DOWNLOAD_SOURCE_RESOURCEPACK;
extern NSString *const PREF_DOWNLOAD_SOURCE_DATAPACK;
extern NSString *const PREF_DOWNLOAD_SOURCE_MODPACK;
extern NSString *const PREF_DOWNLOAD_SOURCE_WORLD;
extern NSString *const PREF_DOWNLOAD_SOURCE_SERVER;
// CurseForge API Key 偏好键
extern NSString *const PREF_CURSEFORGE_API_KEY;
// Mod 更新时是否保留旧文件
extern NSString *const PREF_MOD_UPDATE_KEEP_OLD;
// 模组镜像源（official / mcim）
extern NSString *const PREF_MOD_MIRROR;

@interface PLPreferences : NSObject

@property(nonatomic) NSString *globalPath, *instancePath;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *globalPref, *instancePref;

- (id)initWithGlobalPath:(NSString *)path;
- (id)initWithAutomaticMigrator;

// ★ Task366：注册键路径枚举（桥面 ame.settings.keys 消费；"section.leaf"
// 递归拼接，global+instance 注册面并集去重）
- (NSArray<NSString *> *)ame366_registeredDottedKeys;

- (void)toggleIsolationForced:(BOOL)forced;
- (id)getObject:(NSString *)key;
- (BOOL)setObject:(NSString *)key value:(id)value;
- (void)reset;
// Task346：全局偏好内存态 -> launcher_preferences_v2.plist 强制落盘
//（备份导出前脉柱保险；LauncherPreferences ame346_flushGlobalPrefsToDisk 消费）。
- (void)saveGlobalPref;

// â Task347ï¼zip å¯¼å¥"æ°æ®ä¸è¡"ç¬¬å­è½® Â· ä¸ä»£å¤ä»½è®¾ç½®ææ´ï¼ï¼v1 æ§å¸å±åå¥½å­å¸ -> v2 å¨å±åå¥½å­å¸
//ï¼defaults ä¸ºéª¨æ¶ + æ§å¼æé®åå¡«ï¼ä¸ initWithAutomaticMigrator è¿ç§»åæ¯åè¯­ä¹ï¼ãæ¶è´¹æ¹ï¼
//   DataTransferService å¯¼å¥ä¾§ââå¤ä»½åå v2 èæ±ç©º/åæ¶ç¨åå v1
//   launcher_preferences.plist è¿ç§»æ¢å¤ï¼èå¤ä»½çè®¾ç½®ä¸åäºæ¬¡ä¸¢å¤±ã
+ (NSMutableDictionary<NSString *, NSMutableDictionary *> *)ame347_migratedGlobalPrefsFromV1:(NSDictionary *)oldPref;

// 下载源管理（按类型独立）
+ (NSString *)currentDownloadSourceForType:(NSString *)type;
+ (void)setDownloadSource:(NSString *)source forType:(NSString *)type;
// CurseForge API Key
+ (NSString *)curseForgeAPIKey;
+ (void)setCurseForgeAPIKey:(NSString *)key;
// Mod 更新旧文件保留
+ (BOOL)modUpdateKeepOld;
+ (void)setModUpdateKeepOld:(BOOL)keepOld;

@end
