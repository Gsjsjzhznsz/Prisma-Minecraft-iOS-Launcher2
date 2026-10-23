#import "AmePluginManager.h"
#import "AmePluginPermissions.h"

#import <UIKit/UIKit.h>
#include <stdlib.h>

#import "UnzipKit.h" // external/UnzipKit（ModpackImportService 同源）

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 管理器实现（Task 317）
// 口径注释：
//  · 安装=校验先行（manifest → entry 路径逃逸检查 → 权限 id 白名单），
//    校验全过才落位，失败不产生半成品目录
//  · 同 id 重装=覆盖，grants/enabled 原样保留（升级不丢授权）
//  · 解压使用 UnzipKit（与整合包导入同源依赖，零新增链接）
//  · 所有路径拼接经 ame317_safeJoin 防目录穿越（.. / 绝对路径拒收）
// ═══════════════════════════════════════════════════════════════════

@implementation AmePluginManifest
@end

// 私有方法前向声明（ObjC 方法需先声明后使用）
@interface AmePluginManager ()
+ (NSString *)pluginsRoot;
+ (NSString *)safeJoin:(NSString *)base component:(NSString *)component;
+ (NSString *)trimmedString:(id)raw;
@end

@implementation AmePluginManager

+ (NSInteger)apiVersion {
    return 1;
}

+ (NSString *)pluginsRoot {
    return ame317_pluginsRootDir();
}

+ (NSString *)pluginDir:(NSString *)pluginId {
    return [[self pluginsRoot] stringByAppendingPathComponent:pluginId];
}

#pragma mark - 发现

+ (NSArray<NSString *> *)installedPluginIds {
    NSString *root = [self pluginsRoot];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:root]) return @[];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSError *err = nil;
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:root error:&err];
    for (NSString *name in children) {
        if ([name hasPrefix:@"."]) continue;          // 隐藏文件/临时目录
        if ([name isEqualToString:@"state.json"]) continue;
        NSString *dir = [root stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        if (![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"manifest.json"]]) continue;
        [ids addObject:name];
    }
    return [ids sortedArrayUsingSelector:@selector(compare:)];
}

+ (AmePluginManifest *)manifestForPlugin:(NSString *)pluginId {
    NSString *path = [[self pluginDir:pluginId]
                      stringByAppendingPathComponent:@"manifest.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    return [self validateManifestDictionary:json errCode:nil];
}

+ (NSString *)entryPathForPlugin:(NSString *)pluginId {
    AmePluginManifest *m = [self manifestForPlugin:pluginId];
    if (!m) return nil;
    NSString *safe = [self safeJoin:[self pluginDir:pluginId] component:m.entry];
    if (!safe) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:safe] ? safe : nil;
}

/// 路径防逃逸拼接：component 含 ".." 段 / 以 / 开头 → nil
+ (NSString *)safeJoin:(NSString *)base component:(NSString *)component {
    if (component.length == 0) return nil;
    if ([component hasPrefix:@"/"]) return nil;
    NSArray<NSString *> *parts = [component componentsSeparatedByString:@"/"];
    for (NSString *p in parts) {
        if ([p isEqualToString:@".."] || [p isEqualToString:@""]) {
            if ([p isEqualToString:@".."]) return nil;
        }
    }
    return [base stringByAppendingPathComponent:component];
}

#pragma mark - manifest 校验

+ (AmePluginManifest *)validateManifestDictionary:(NSDictionary *)dict
                                         errCode:(AmePluginInstallResult *)errCode {
    AmePluginInstallResult fail = AmePluginInstallErrBadSchema;
    AmePluginManifest *m = nil;

    if (![dict isKindOfClass:[NSDictionary class]]) { fail = AmePluginInstallErrBadJSON; goto out; }

    NSString *pid = [self trimmedString:dict[@"id"]];
    if (pid.length < 3 || pid.length > 64) goto out;
    // id 白名单：首字符字母数字，整体 [a-z0-9._-]
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    {
        unichar c0 = [pid characterAtIndex:0];
        if (![[NSCharacterSet characterSetWithCharactersInString:
               @"abcdefghijklmnopqrstuvwxyz0123456789"] characterIsMember:c0]) goto out;
    }
    for (NSUInteger i = 0; i < pid.length; i++) {
        unichar c = [pid characterAtIndex:i];
        if (![ok characterIsMember:c]) goto out;
    }

    m = [[AmePluginManifest alloc] init];
    m.pluginId = pid;
    m.name = [self trimmedString:dict[@"name"]];
    if (m.name.length == 0 || m.name.length > 64) goto fail;
    m.version = [self trimmedString:dict[@"version"]];
    if (m.version.length == 0 || m.version.length > 32) goto fail;
    m.author = [self trimmedString:dict[@"author"]] ?: @"";
    m.summary = [self trimmedString:dict[@"description"]] ?: @"";
    if (m.summary.length > 512) m.summary = [m.summary substringToIndex:512];

    m.entry = [self trimmedString:dict[@"entry"]] ?: @"main.js";
    if (m.entry.length == 0 || ![m.entry hasSuffix:@".js"]) goto fail;

    // 权限白名单 ⊆ 注册表（未知权限 = 拒装，fail-closed）
    {
        id permsRaw = dict[@"permissions"];
        NSMutableArray<NSString *> *perms = [NSMutableArray array];
        if (permsRaw != nil) {
            if (![permsRaw isKindOfClass:[NSArray class]]) goto fail;
            for (id p in permsRaw) {
                if (![p isKindOfClass:[NSString class]]) goto fail;
                if (![AmePluginPermissions isValidPermissionId:p]) goto fail;
                if (![perms containsObject:p]) [perms addObject:p];
            }
        }
        m.permissions = perms;
    }

    // API 版本门
    {
        id apiRaw = dict[@"minApi"];
        NSInteger minApi = 1;
        if (apiRaw != nil && [apiRaw respondsToSelector:@selector(integerValue)]) {
            minApi = [apiRaw integerValue];
        }
        if (minApi < 1) minApi = 1;
        m.minApi = minApi;
        if (minApi > [self apiVersion]) { fail = AmePluginInstallErrAPITooNew; goto fail; }
    }

    return m;

fail:
    m = nil;
out:
    if (errCode) *errCode = fail;
    return nil;
}

+ (NSString *)trimmedString:(id)raw {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length ? s : nil;
}

#pragma mark - 安装

+ (AmePluginInstallResult)installFromZip:(NSString *)zipPath
                            outManifest:(AmePluginManifest **)outManifest {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSError *aErr = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&aErr];
    if (!archive) return AmePluginInstallErrReadZip;

    // ① 根部 manifest.json（兼容单层子目录包裹）
    NSData *manifestData = [archive extractDataFromFile:@"manifest.json" error:nil];
    NSString *stripPrefix = @"";
    if (!manifestData) {
        // 探测唯一顶层目录
        NSString *singleDir = nil;
        __block BOOL ambiguous = NO;
        [archive performOnFilesInArchive:^(UZKFileInfo *info, BOOL *stop) {
            NSString *name = info.filename; // 相对路径（UZKFileInfo.filename）
            if (name.length == 0) return;
            NSArray<NSString *> *segs = [name pathComponents];
            if (segs.count < 2) return;
            NSString *top = segs[0]; // filename 为相对路径，首段即顶层目录
            if ([top hasPrefix:@"."]) return;
            if (singleDir == nil) { singleDir = top; }
            else if (![singleDir isEqualToString:top]) { ambiguous = YES; *stop = YES; }
        }];
        if (singleDir && !ambiguous) {
            stripPrefix = [singleDir stringByAppendingString:@"/"];
            manifestData = [archive extractDataFromFile:
                            [stripPrefix stringByAppendingString:@"manifest.json"] error:nil];
        }
    }
    if (!manifestData) return AmePluginInstallErrNoManifest;

    // ② schema 校验
    NSError *jErr = nil;
    id json = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&jErr];
    AmePluginInstallResult code = AmePluginInstallOK;
    AmePluginManifest *m = [self validateManifestDictionary:json errCode:&code];
    if (!m) return code;
    if (m.minApi > [self apiVersion]) return AmePluginInstallErrAPITooNew;

    // ③ 解压到暂存目录
    NSString *tmpRoot = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"ame317-install-%@", [NSUUID UUID].UUIDString]];
    if (![fm createDirectoryAtPath:tmpRoot withIntermediateDirectories:YES attributes:nil error:nil]) {
        return AmePluginInstallErrMove;
    }
    NSError *xErr = nil;
    BOOL extracted = [archive extractFilesTo:tmpRoot overwrite:YES error:&xErr];
    if (!extracted) {
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrReadZip;
    }

    // ④ 校验入口脚本存在 + 无逃逸（单层包裹目录归一）
    NSString *stagedDir = tmpRoot;
    if (stripPrefix.length) {
        stagedDir = [tmpRoot stringByAppendingPathComponent:
                     [stripPrefix substringToIndex:stripPrefix.length - 1]];
    }
    NSString *entryAbs = [self safeJoin:stagedDir component:m.entry];
    if (!entryAbs || ![fm fileExistsAtPath:entryAbs]) {
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrBadEntry;
    }
    // 校验通过后再读 manifest 目录下的 manifest.json 终稿（同 stagedDir）
    NSString *finalManifestPath = [stagedDir stringByAppendingPathComponent:@"manifest.json"];
    NSData *finalManifestData = [NSData dataWithContentsOfFile:finalManifestPath];
    if (!finalManifestData) {
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrNoManifest;
    }

    // ⑤ 落位：同 id 覆盖（旧目录先改名防半删），授权/启用态保留
    NSString *destDir = [self pluginDir:m.pluginId];
    NSString *rootDir = [self pluginsRoot];
    if (![fm fileExistsAtPath:rootDir]) {
        [fm createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *backup = [rootDir stringByAppendingPathComponent:
                        [NSString stringWithFormat:@".ame317-old-%@", [NSUUID UUID].UUIDString]];
    if ([fm fileExistsAtPath:destDir]) {
        [fm moveItemAtPath:destDir toPath:backup error:nil];
    }
    BOOL moved = [fm moveItemAtPath:stagedDir toPath:destDir error:nil];
    if (!moved) {
        if ([fm fileExistsAtPath:backup]) [fm moveItemAtPath:backup toPath:destDir error:nil];
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrMove;
    }
    [fm removeItemAtPath:backup error:nil];
    [fm removeItemAtPath:tmpRoot error:nil];

    // ⑥ 首装默认授权：普通权限授予、高危权限拒绝（用户详情页可改）
    if (![AmePluginPermissions pluginEnabled:m.pluginId] &&
        [AmePluginPermissions grantsForPlugin:m.pluginId].count == 0) {
        NSMutableDictionary<NSString *, NSNumber *> *grants = [NSMutableDictionary dictionary];
        for (NSString *p in m.permissions) {
            grants[p] = @([AmePluginPermissions isDangerous:p] ? 0 : 1);
        }
        [AmePluginPermissions replaceGrants:grants forPlugin:m.pluginId];
        [AmePluginPermissions setPluginEnabled:YES pluginId:m.pluginId];
    }

    if (outManifest) *outManifest = m;
    return AmePluginInstallOK;
}

#pragma mark - 卸载

+ (BOOL)uninstallPlugin:(NSString *)pluginId {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self pluginDir:pluginId];
    BOOL ok = YES;
    if ([fm fileExistsAtPath:dir]) {
        ok = [fm removeItemAtPath:dir error:nil];
    }
    [AmePluginPermissions purgePluginState:pluginId];
    return ok;
}

@end
