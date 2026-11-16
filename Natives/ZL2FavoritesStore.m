//
// ZL2FavoritesStore.m — ZL2 收藏仓库（结构契约见 .h）
//

#import "ZL2FavoritesStore.h"

NSString * const ZL2FavoritesDidChangeNotification = @"ZL2FavoritesDidChangeNotification";

static NSString *ZL2FavoritesPlistPath(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES) firstObject];
    if (!dir) return nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"zl2_favorites.plist"];
}

// ★Task432（P1 收藏仓异形档崩）：plist 值类型不可信（外部改写/旧版写入可能落
// 裸字符串、数组甚至 NSDate），followTime 取键后直接 doubleValue 遇非数字/非字
// 符串类型会 unrecognized selector——统一走此安全取值（非数值型回退 0.0）。
static NSTimeInterval ZL2FavSafeDouble(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [value doubleValue];
    return 0.0;
}

@implementation ZL2FavoritesStore

+ (instancetype)sharedStore {
    static ZL2FavoritesStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [[ZL2FavoritesStore alloc] init]; });
    return store;
}

- (NSMutableDictionary<NSString *, NSDictionary *> *)loadMap {
    NSString *path = ZL2FavoritesPlistPath();
    if (!path) return [NSMutableDictionary dictionary];
    id raw = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (![raw isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    // ★Task432（P1 收藏仓异形档崩）： dictionaryWithContentsOfFile: 在类簇边界
    // 可能落回不可变字典——统一可变拷贝，保证后续 toggle 的写入安全。
    if (![raw isKindOfClass:[NSMutableDictionary class]]) {
        raw = [(NSDictionary *)raw mutableCopy];
    }
    // ★Task432（P1 收藏仓异形档崩）：外部改写或旧版写入的条目值可能不是字典
    // （如裸字符串/数组），下游 allFavorites 对其取键会 unrecognized selector
    // 崩溃——装载后逐条 isKindOfClass 过滤，异形条目整体丢弃并计数留痕。
    NSMutableDictionary *map = raw;
    NSMutableArray<NSString *> *alienKeys = nil;
    for (NSString *key in map) {
        if (![map[key] isKindOfClass:[NSDictionary class]]) {
            if (!alienKeys) alienKeys = [NSMutableArray array];
            [alienKeys addObject:key];
        }
    }
    if (alienKeys.count > 0) {
        NSLog(@"[Favorites][Task432] 异形条目 %lu 条",
              (unsigned long)alienKeys.count);
        [map removeObjectsForKeys:alienKeys];
    }
    return map;
}

- (void)saveMap:(NSMutableDictionary<NSString *, NSDictionary *> *)map {
    NSString *path = ZL2FavoritesPlistPath();
    if (!path) return;
    [map writeToFile:path atomically:YES];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:ZL2FavoritesDidChangeNotification object:nil];
}

- (NSArray<NSDictionary *> *)allFavorites {
    NSMutableArray *out_ = [[self.loadMap allValues] mutableCopy];
    [out_ sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        // ★Task432（P1 收藏仓异形档崩）：followTime 走安全取值（loadMap 已滤异形
        // 条目，此处兜底防 NSDate 等非数值型残留触发 unrecognized selector）。
        NSTimeInterval ta = ZL2FavSafeDouble(a[@"followTime"]);
        NSTimeInterval tb = ZL2FavSafeDouble(b[@"followTime"]);
        return (ta > tb) ? NSOrderedAscending : (ta < tb) ? NSOrderedDescending : NSOrderedAscending;
    }];
    return out_;
}

- (BOOL)isFavoritePlatform:(NSInteger)platform projectId:(NSString *)projectId {
    if (projectId.length == 0) return NO;
    NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)platform, projectId];
    return [self.loadMap objectForKey:key] != nil;
}

- (BOOL)toggleFavoriteWithProject:(NSDictionary *)projectSnapshot {
    // ★Task432（P1 收藏仓异形档崩）：同族取键点兜底——入参快照非字典直接拒收。
    if (![projectSnapshot isKindOfClass:[NSDictionary class]]) return NO;
    NSInteger platform = [projectSnapshot[@"platform"] integerValue];
    NSString *projectId = projectSnapshot[@"projectId"] ?: @"";
    if (projectId.length == 0) return NO;
    NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)platform, projectId];

    NSMutableDictionary *map = self.loadMap;
    BOOL nowFavorite;
    if (map[key]) {
        [map removeObjectForKey:key];
        nowFavorite = NO;
    } else {
        NSMutableDictionary *snapshot = [projectSnapshot mutableCopy];
        snapshot[@"followTime"] = @([NSDate date].timeIntervalSince1970);
        map[key] = snapshot;
        nowFavorite = YES;
    }
    [self saveMap:map];
    return nowFavorite;
}

@end
