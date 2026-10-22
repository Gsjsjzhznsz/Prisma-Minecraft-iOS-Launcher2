//
// ZL2FavoritesStore.h — ZL2 收藏仓库（7.0-UI-14 下载域全逻辑移植）
//
// 移植对象：ZalithLauncher2 FavoriteProjectsRepository（GNU GPL 参考副本，只读）。
// ZL2 端按平台分两实例存 MMKV（FavoriteModrinthProject/FavoriteCurseForgeProject）；
// iOS 侧收敛为单 plist（Application Support/zl2_favorites.plist），键 = 平台:项目
// id，值为搜索卡片快照（离线可见，收藏页直出）。收藏心形 toggle 即写入/删除。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ZL2FavoritesDidChangeNotification;

@interface ZL2FavoritesStore : NSObject

+ (instancetype)sharedStore;

/// 全部收藏（每项 = 快照字典：platform/projectId/title/description/imageUrl/
/// author/downloads/projectType/followTime），按 followTime 新→旧
- (NSArray<NSDictionary *> *)allFavorites;

- (BOOL)isFavoritePlatform:(NSInteger)platform projectId:(NSString *)projectId;

/// toggle：收藏则写入快照，已收藏则移除；返回 toggle 后状态
- (BOOL)toggleFavoriteWithProject:(NSDictionary *)projectSnapshot;

@end

NS_ASSUME_NONNULL_END
