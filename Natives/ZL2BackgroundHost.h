//
// ZL2BackgroundHost.h — ★Task429（PDF 第五版 §8.3）ZL2 系页面背景层
//
// ZL2 页背景层（统一挂载于壳层内容宿主最底层）：壁纸底图（alpha 跟随
// BackgroundManager.uiOpacity 既有设置令牌）+ UIVisualEffectView 毛玻璃层
//（强度跟随 blurIntensity 既有设置令牌；半透明档整层不装）——双层毛玻璃
// 组合读 BackgroundManager Task223/224 既有管线，透明度令牌不新增设置键。
//
// 可见性机制：宿主自身不透壁纸（页面底色不透明时壁纸被盖住属正常态）；
// 挂载方（ZL2ShellViewController 背景挂载区域）经 BackgroundManager 既有
// 透明化管线（makeViewControllerTransparent:，Task111 hasBackground 守卫
// 幂等）把壳层树基色透出，壁纸经宿主双层呈现。
//
// 刷新面：Ame223WallpaperChangedNotification（壁纸变化）+
// BackgroundUIEffectChanged（效果/透明度/模糊滑条）双通知重建。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2BackgroundHost : UIView

// 挂载后调用一次 + 挂载方在子页 attach 后重放（幂等）：读 BackgroundManager
// 现态刷新图层，并把透明化管线应用到 ownerVC（壳层）——ownerVC nil 时仅刷图层。
- (void)ame429_refreshWithOwnerViewController:(nullable UIViewController *)ownerVC;

@end

NS_ASSUME_NONNULL_END
