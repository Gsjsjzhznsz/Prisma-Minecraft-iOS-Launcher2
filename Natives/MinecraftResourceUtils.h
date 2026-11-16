#import <UIKit/UIKit.h>

// Task432：版本注册表全局收编 —— 原 LauncherNavigationController.h:3 的
//   tentative 定义（NSMutableArray<NSDictionary *> *localVersionList,
//   *remoteVersionList; 无 extern，-fcommon 下多 TU 合并为单一 common 符号）
//   随该类退役迁至此处。旧壳退役后两表运行时恒空（ZL2 域清单自扫，
//   见 ZL2VersionIndex.h Task335 病历）；安装器家族（FabricUtils /
//   FabricInstallViewController / PLComponentService）仍向 localVersionList
//   注册 custom profile，消费侧沿用既有的 nil 安全（?: @[]）口径。
NSMutableArray<NSDictionary *> *localVersionList, *remoteVersionList;

#define TYPE_INSTALLED 0
#define TYPE_RELEASE 1
#define TYPE_SNAPSHOT 2
#define TYPE_OLDBETA 3
#define TYPE_OLDALPHA 4

@interface MinecraftResourceUtils : NSObject

+ (void)processVersion:(NSMutableDictionary *)json inheritsFrom:(NSMutableDictionary *)inheritsFrom;
+ (void)tweakVersionJson:(NSMutableDictionary *)json;

+ (NSObject *)findVersion:(NSString *)version inList:(NSArray *)list;
+ (NSObject *)findNearestVersion:(NSObject *)version expectedType:(int)type;

// 评估 Mojang 版本 JSON 中的 OS 规则（iOS 视作 osx）
+ (BOOL)evaluateRules:(NSArray *)rules;
// 将规则化的 JVM 参数项展开为字符串数组
+ (NSArray<NSString *> *)flattenJvmArg:(id)arg;

@end
