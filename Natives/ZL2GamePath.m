// ZL2GamePath.m —— ★Task473: ZL2 版本隔离系统移植（上游 b6310dd 同构）

#import "ZL2GamePath.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"

@implementation ZL2GamePath

+ (NSString *)gameHome {
    const char *ame473_gd = getenv("POJAV_GAME_DIR");
    if (ame473_gd && *ame473_gd) return [NSString stringWithUTF8String:ame473_gd];
    const char *ame473_home = getenv("POJAV_HOME");
    if (ame473_home && *ame473_home) return [NSString stringWithUTF8String:ame473_home];
    return NSHomeDirectory();
}

+ (NSString *)versionPathForVersion:(NSString *)vid {
    NSString *ame473_root = [self gameHome];
    if (vid.length == 0 || ame473_root.length == 0) return ame473_root;
    return [[ame473_root stringByAppendingPathComponent:@"versions"]
        stringByAppendingPathComponent:vid];
}

+ (nullable NSString *)configPathForVersion:(NSString *)vid {
    if (vid.length == 0) return nil;
    return [[[self versionPathForVersion:vid] stringByAppendingPathComponent:@"prisma"]
        stringByAppendingPathComponent:@"version.config"];
}

+ (ZL2IsolationType)isolationTypeForVersion:(NSString *)vid {
    if (vid.length == 0) return ZL2IsolationFollowGlobal;
    NSString *ame473_path = [self configPathForVersion:vid];
    NSData *ame473_data = ame473_path.length > 0 ? [NSData dataWithContentsOfFile:ame473_path] : nil;
    if (!ame473_data) return ZL2IsolationFollowGlobal;
    id ame473_json = [NSJSONSerialization JSONObjectWithData:ame473_data options:0 error:nil];
    if (![ame473_json isKindOfClass:[NSDictionary class]]) return ZL2IsolationFollowGlobal;
    id ame473_raw = ame473_json[@"isolationType"];
    if ([ame473_raw isKindOfClass:[NSString class]]) {
        // ZL2 上游 Gson @SerializedName 字符串形态
        if ([ame473_raw isEqualToString:@"ENABLE"]) return ZL2IsolationEnable;
        if ([ame473_raw isEqualToString:@"DISABLE"]) return ZL2IsolationDisable;
        return ZL2IsolationFollowGlobal;
    }
    if ([ame473_raw isKindOfClass:[NSNumber class]]) {
        NSInteger ame473_v = [ame473_raw integerValue];
        if (ame473_v == 1) return ZL2IsolationEnable;
        if (ame473_v == 2) return ZL2IsolationDisable;
        return ZL2IsolationFollowGlobal;
    }
    return ZL2IsolationFollowGlobal;
}

+ (void)ame473_setIsolationType:(ZL2IsolationType)type forVersion:(NSString *)vid {
    if (vid.length == 0) return;
    NSString *ame473_path = [self configPathForVersion:vid];
    if (ame473_path.length == 0) return;
    NSMutableDictionary *ame473_json = [NSMutableDictionary dictionary];
    NSData *ame473_data = [NSData dataWithContentsOfFile:ame473_path];
    if (ame473_data) {
        id ame473_old = [NSJSONSerialization JSONObjectWithData:ame473_data options:0 error:nil];
        if ([ame473_old isKindOfClass:[NSDictionary class]]) {
            [ame473_json addEntriesFromDictionary:ame473_old];
        }
    }
    NSString *ame473_name = (type == ZL2IsolationEnable) ? @"ENABLE"
                          : (type == ZL2IsolationDisable) ? @"DISABLE" : @"FOLLOW_GLOBAL";
    ame473_json[@"isolationType"] = ame473_name;
    ame473_json[@"schema"] = @"prisma.zl2-isolation/1";
    NSString *ame473_dir = [ame473_path stringByDeletingLastPathComponent];
    NSFileManager *ame473_fm = [NSFileManager defaultManager];
    if (![ame473_fm fileExistsAtPath:ame473_dir]) {
        [ame473_fm createDirectoryAtPath:ame473_dir withIntermediateDirectories:YES
                              attributes:nil error:nil];
    }
    NSData *ame473_out = [NSJSONSerialization dataWithJSONObject:ame473_json
                                                         options:NSJSONWritingPrettyPrinted error:nil];
    if (ame473_out) [ame473_out writeToFile:ame473_path atomically:YES];
}

+ (BOOL)globalIsolationDefault {
    return getPrefBool(@"versionIsolation");
}

+ (BOOL)isIsolationForVersion:(NSString *)vid {
    switch ([self isolationTypeForVersion:vid]) {
        case ZL2IsolationEnable:
            return YES;
        case ZL2IsolationDisable:
            return NO;
        default:
            return [self globalIsolationDefault];
    }
}

+ (NSString *)gameDirForVersion:(NSString *)vid {
    if (vid.length > 0 && [self isIsolationForVersion:vid]) {
        return [self versionPathForVersion:vid];
    }
    return [self gameHome];
}

+ (BOOL)isIsolationFormGameDir:(NSString *)gameDir {
    if (![gameDir isKindOfClass:[NSString class]] || gameDir.length == 0) return NO;
    NSString *ame473_clean = [gameDir hasPrefix:@"./"] ? [gameDir substringFromIndex:2] : gameDir;
    if ([ame473_clean isEqualToString:@"."] || [ame473_clean isEqualToString:@"./"]) return NO;
    NSArray<NSString *> *ame473_comps = ame473_clean.pathComponents;
    // 形态：versions/<vid> 或 versions/<vid>/game（Task472 前历史隔离写入——惰性不读）
    return ame473_comps.count >= 2 && [ame473_comps[0] isEqualToString:@"versions"];
}

+ (NSString *)gameDirForProfile:(NSString *)profileName {
    if (!profileName.length) {
        profileName = PLProfiles.current.selectedProfileName ?: @"(Default)";
    }
    NSDictionary *ame473_prof = nil;
    id ame473_candidate = PLProfiles.current.profiles[profileName];
    if ([ame473_candidate isKindOfClass:[NSDictionary class]]) ame473_prof = ame473_candidate;
    if (![ame473_prof isKindOfClass:[NSDictionary class]]) ame473_prof = @{};
    NSString *ame473_vid = [ame473_prof[@"lastVersionId"] isKindOfClass:[NSString class]]
        ? ame473_prof[@"lastVersionId"] : @"";
    // ① 版本级隔离三态（上游分支一：isolation → 版本目录）
    if (ame473_vid.length > 0 && [self isIsolationForVersion:ame473_vid]) {
        return [self versionPathForVersion:ame473_vid];
    }
    // ② 实例自定义路径（上游 customPath 分支同构；历史隔离形态值惰性不读）
    NSString *ame473_gd = [ame473_prof[@"gameDir"] isKindOfClass:[NSString class]]
        ? ame473_prof[@"gameDir"] : @"";
    if (ame473_gd.length > 0 && ![ame473_gd isEqualToString:@"."]
        && ![ame473_gd isEqualToString:@"./"]
        && ![self isIsolationFormGameDir:ame473_gd]) {
        if ([ame473_gd isAbsolutePath]) return ame473_gd;
        NSString *ame473_clean = [ame473_gd hasPrefix:@"./"] ? [ame473_gd substringFromIndex:2] : ame473_gd;
        return [[self gameHome] stringByAppendingPathComponent:ame473_clean];
    }
    // ③ 主游戏根（共享根）
    return [self gameHome];
}

+ (void)applyIsolationForModPackVersion:(NSString *)vid {
    if (vid.length == 0) return;
    if ([self isolationTypeForVersion:vid] == ZL2IsolationEnable) return; // 幂等
    [self ame473_setIsolationType:ZL2IsolationEnable forVersion:vid];
}

@end
