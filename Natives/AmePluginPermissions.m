#import "AmePluginPermissions.h"

#import <UIKit/UIKit.h>
#include <stdlib.h>

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 权限中心实现（Task 317）
// 口径注释：
//  · 进程内单份内存态（_state），所有 API 主线程调用（桥接/页面均主线程）
//  · state.json 原子写：writeToFile:atomically:YES（tmp+rename 语义）
//  · 损坏兜底：JSON 解析失败→空表重建，绝不因授权文件损坏阻塞启动器
//  · 本文件不 import 任何 JSContext/插件运行时——权限中心零依赖，可被
//    Bridge/Runtime/页面三方独立引用
// ═══════════════════════════════════════════════════════════════════

NSString *ame317_pluginsRootDir(void) {
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    if (home.length == 0) {
        home = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                    NSUserDomainMask, YES) firstObject] ?: NSTemporaryDirectory();
    }
    // ★ Task319/320（PCL 风格布局，用户拍板数据目录定名 Prisma2）：插件根 =
    //   Prisma2/plugins（启动器数据目录，与 .minecraft 游戏目录并列的顶层观感）。
    //   整体迁移由 main.m init_setupPCLLayout 在 pre-init 完成（Task319 窗口期
    //   PCL/ 自动改名 Prisma2/，旧位 plugins 留符号链接防断链）；此处保底自愈
    //   建目录，保证安装/扫描/state.json 三链在任何时序下不断。
    NSString *root = [[home stringByAppendingPathComponent:@"Prisma2"]
                      stringByAppendingPathComponent:@"plugins"];
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}

@implementation AmePluginPermissionItem
- (instancetype)initWithId:(NSString *)pid danger:(BOOL)danger {
    self = [super init];
    if (self) {
        _permissionId = [pid copy];
        _danger = danger;
        _nameKey = [NSString stringWithFormat:@"ame317.perm.%@.name", pid];
        _descKey = [NSString stringWithFormat:@"ame317.perm.%@.desc", pid];
    }
    return self;
}
@end

@implementation AmePluginPermissions

// ObjC @implementation 内方法定义顺序无关（clang 全 implementation 查找），
// itemForId: 定义于下方，无需前向声明。
+ (NSArray<AmePluginPermissionItem *> *)allPermissions {
    static NSArray<AmePluginPermissionItem *> *perms = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        perms = @[
            // ★ Task333：完全接管（最高级别权限，用户点题"启动器完全接管
            //   权限，一打开全部东西都可以改"）—— 元权限：已授权即对全部
            //   权限闸放行（执法点 AmePluginBridge ame317_requirePerm 首行）。
            //   刻意不要求 manifest 声明 = 用户侧主控开关（详情页恒可切）；
            //   开启后其余权限开关在详情页全部变灰禁用（语义：接管态下
            //   逐项开关已无执法意义）。首方自愈（ame326/heal）刻意【不】
            //   覆盖本权限：完全接管必须用户本人显式打开，绝不静默代授。
            [[AmePluginPermissionItem alloc] initWithId:@"ame.super"      danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"events"        danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"ui.dialog"     danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"ui.rows"       danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"ui.theme"      danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"settings.read" danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"settings.write" danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"renderer.read" danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"renderer.write" danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"profile.read"  danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"storage"       danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"net"           danger:YES],
            // ★ Task327：权限扩大三组（用户："最好整个启动器都可以修改"）
            //   ui.nav      = 启动器页面导航（home/download/.../ai 七页切换）
            //   profile.write = 实例档案增删（游戏目录/版本绑定）
            //   files.game  = 当前实例游戏目录文件沙盒读写删（路径守卫+限额）
            [[AmePluginPermissionItem alloc] initWithId:@"ui.nav"        danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"profile.write" danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"files.game"    danger:YES],
            // ★ Task364：视图操纵（用户："插件不是可以随便改启动器任何地方吗"；
            //   AI 写元素拖拽插件失败的根因 = 桥面无任何视图级 API）。查询并
            //   操纵启动器界面原生视图（移动/缩放/隐藏/改文字/挂手势），高危：
            //   越权触碰任意视图可致交互错乱，且游戏渲染面子树在内置禁改名单。
            [[AmePluginPermissionItem alloc] initWithId:@"ui.views"      danger:YES],
            // ★ Task365：自修复三件套（用户点题"整个启动器完全可以修改没有限制，
            //   特别是 JIT 和游戏启动部分，启动器崩溃用户直接找 AI 修"）——
            //   JIT 状态查询（安全）/ JIT 开启触发（高危）/ 游戏启动触发（高危）
            //   / 日志尾部读取（安全，崩溃自诊断的主输入）。
            [[AmePluginPermissionItem alloc] initWithId:@"jit.read"      danger:NO],
            [[AmePluginPermissionItem alloc] initWithId:@"jit.write"     danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"game.launch"   danger:YES],
            [[AmePluginPermissionItem alloc] initWithId:@"logs.read"     danger:NO],
        ];
    });
    return perms;
}

+ (BOOL)isValidPermissionId:(NSString *)permissionId {
    for (AmePluginPermissionItem *item in [self allPermissions]) {
        if ([item.permissionId isEqualToString:permissionId]) return YES;
    }
    return NO;
}

+ (BOOL)isDangerous:(NSString *)permissionId {
    return [self isValidPermissionId:permissionId]
        ? [self itemForId:permissionId].danger
        : YES; // 未知权限按高危处理（fail-closed）
}

+ (AmePluginPermissionItem *)itemForId:(NSString *)permissionId {
    for (AmePluginPermissionItem *item in [self allPermissions]) {
        if ([item.permissionId isEqualToString:permissionId]) return item;
    }
    return nil;
}

#pragma mark - 状态存取

+ (NSURL *)stateFileURL {
    return [NSURL fileURLWithPath:
        [ame317_pluginsRootDir() stringByAppendingPathComponent:@"state.json"]];
}

// 内存态：
// { "grants":  { "<pid>": { "<perm>": 0/1 } },
//   "enabled": { "<pid>": 0/1 } }
static NSMutableDictionary<NSString *, NSDictionary *> *ame317_state = nil;

+ (void)initialize {
    if (self != [AmePluginPermissions class]) return;
    ame317_state = [[NSMutableDictionary alloc] init];
    [self loadStateFromDisk];
}

+ (void)loadStateFromDisk {
    NSData *data = [NSData dataWithContentsOfURL:[self stateFileURL]];
    if (!data) return;
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![json isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[AmePlugin] state.json 损坏，重建空授权表（不阻塞启动）");
        return;
    }
    NSDictionary *dict = (NSDictionary *)json;
    id grants = dict[@"grants"];
    id enabled = dict[@"enabled"];
    if ([grants isKindOfClass:[NSDictionary class]]) {
        ame317_state[@"grants"] = [grants mutableCopy] ?: [NSMutableDictionary dictionary];
    }
    if ([enabled isKindOfClass:[NSDictionary class]]) {
        ame317_state[@"enabled"] = [enabled mutableCopy] ?: [NSMutableDictionary dictionary];
    }
}

+ (NSMutableDictionary *)grantsTable {
    NSMutableDictionary *t = ame317_state[@"grants"];
    if (!t) {
        t = [[NSMutableDictionary alloc] init];
        ame317_state[@"grants"] = t;
    }
    return t;
}

+ (NSMutableDictionary *)enabledTable {
    NSMutableDictionary *t = ame317_state[@"enabled"];
    if (!t) {
        t = [[NSMutableDictionary alloc] init];
        ame317_state[@"enabled"] = t;
    }
    return t;
}

+ (BOOL)pluginHasGrant:(NSString *)pluginId permission:(NSString *)permissionId {
    if (pluginId.length == 0 || permissionId.length == 0) return NO;
    NSDictionary *g = [self grantsTable][pluginId];
    if (![g isKindOfClass:[NSDictionary class]]) return NO;
    NSNumber *v = g[permissionId];
    return [v boolValue];
}

+ (void)setGrant:(BOOL)granted forPlugin:(NSString *)pluginId permission:(NSString *)permissionId {
    if (pluginId.length == 0 || permissionId.length == 0) return;
    NSMutableDictionary *g = [self grantsTable][pluginId];
    if (![g isKindOfClass:[NSMutableDictionary class]]) {
        g = [[NSMutableDictionary alloc] init];
        [self grantsTable][pluginId] = g;
    }
    g[permissionId] = @(granted ? 1 : 0);
    [self flushState];
}

+ (NSDictionary<NSString *, NSNumber *> *)grantsForPlugin:(NSString *)pluginId {
    NSDictionary *g = [self grantsTable][pluginId];
    return [g isKindOfClass:[NSDictionary class]] ? g : @{};
}

+ (void)replaceGrants:(NSDictionary<NSString *, NSNumber *> *)grants
             forPlugin:(NSString *)pluginId {
    if (pluginId.length == 0) return;
    [self grantsTable][pluginId] = [grants mutableCopy] ?: [NSMutableDictionary dictionary];
    [self flushState];
}

+ (void)purgePluginState:(NSString *)pluginId {
    if (pluginId.length == 0) return;
    [[self grantsTable] removeObjectForKey:pluginId];
    [[self enabledTable] removeObjectForKey:pluginId];
    [self flushState];
}

+ (BOOL)pluginEnabled:(NSString *)pluginId {
    if (pluginId.length == 0) return NO;
    NSNumber *v = [self enabledTable][pluginId];
    return [v boolValue];
}

+ (void)setPluginEnabled:(BOOL)enabled pluginId:(NSString *)pluginId {
    if (pluginId.length == 0) return;
    [self enabledTable][pluginId] = @(enabled ? 1 : 0);
    [self flushState];
}

+ (BOOL)flushState {
    NSDictionary *snapshot = @{
        @"grants": [self grantsTable] ?: @{},
        @"enabled": [self enabledTable] ?: @{},
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&err];
    if (err || !data) {
        NSLog(@"[AmePlugin] state.json 序列化失败: %@", err);
        return NO;
    }
    // 目录兜底（安装流已建，此处幂等防呆）
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = ame317_pluginsRootDir();
    if (![fm fileExistsAtPath:root]) {
        [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    }
    BOOL ok = [data writeToURL:[self stateFileURL] atomically:YES];
    if (!ok) NSLog(@"[AmePlugin] state.json 写盘失败");
    return ok;
}

@end
