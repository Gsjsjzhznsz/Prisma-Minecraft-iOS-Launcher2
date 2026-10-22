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
    if ([raw isKindOfClass:[NSMutableDictionary class]]) return raw;
    return [NSMutableDictionary dictionary];
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
        NSTimeInterval ta = [a[@"followTime"] doubleValue];
        NSTimeInterval tb = [b[@"followTime"] doubleValue];
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
