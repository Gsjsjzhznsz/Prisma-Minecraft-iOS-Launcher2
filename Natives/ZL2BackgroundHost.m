//
// ZL2BackgroundHost.m — ★Task429（PDF 第五版 §8.3）ZL2 页背景层实现
//
// 层级（自下而上）：
//   ① 壁纸底图层（UIImageView）：图源 = BackgroundManager ame223_currentWallpaperImage
//      （Task223 CGImageSource 降采样直取——宿主不自行解码，直吃既有降采样
//      管线）；alpha = uiOpacity（既有透明度令牌）；AspectFill。
//   ② 毛玻璃层（UIVisualEffectView + UIBlurEffect——非逐帧 blur）：毛玻璃档
//      按既有 blurIntensity 映射 effectView alpha（Task252 frostAlpha 同族：
//      0.3 + blur×0.7）；半透明档整层移除（Task289「壁纸无法不模糊」让步
//      口径对齐：锐利档零模糊）。
//   ③ 压暗层（UIView）：blurIntensity × 0.2（Task161 既有压暗语义）。
//
// 通知刷新：Ame223WallpaperChanged + BackgroundUIEffectChanged → 主线程重建；
// 无壁纸：宿主整体 alpha=0 隐藏 + owner 树基色还原（[ZL2Theme surface]）。
//

#import "ZL2BackgroundHost.h"

#import "BackgroundManager.h"
#import "ZL2Theme.h"

#pragma mark - 常量实名表（★Task429）

// 毛玻璃强度映射（Task252 frostAlpha 同族：0.3 + blur×0.7）
static const CGFloat Ame429FrostAlphaBase = 0.30;
static const CGFloat Ame429FrostAlphaSpan = 0.70;

// 压暗层强度（Task161 既有语义：blurIntensity × 0.2）
static const CGFloat Ame429DimSpan = 0.20;

@interface ZL2BackgroundHost ()
@property (nonatomic, strong) UIImageView *wallpaperView;      // ① 底图
@property (nonatomic, strong) UIVisualEffectView *frostView;   // ② 毛玻璃
@property (nonatomic, strong) UIView *dimView;                 // ③ 压暗
@end

@implementation ZL2BackgroundHost

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = NO;   // 装饰层不参与命中测试（Task161 判例）
        self.backgroundColor = [UIColor clearColor];
        self.alpha = 0.0;                  // 无壁纸默认全隐（刷新面接管显隐）
        self.wallpaperView = [[UIImageView alloc] init];
        self.wallpaperView.translatesAutoresizingMaskIntoConstraints = NO;
        self.wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
        self.wallpaperView.clipsToBounds = YES;
        self.wallpaperView.userInteractionEnabled = NO;
        [self addSubview:self.wallpaperView];

        self.frostView = [[UIVisualEffectView alloc]
                          initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        self.frostView.translatesAutoresizingMaskIntoConstraints = NO;
        self.frostView.userInteractionEnabled = NO;
        [self addSubview:self.frostView];

        self.dimView = [[UIView alloc] init];
        self.dimView.translatesAutoresizingMaskIntoConstraints = NO;
        self.dimView.backgroundColor = [UIColor blackColor];
        self.dimView.userInteractionEnabled = NO;
        [self addSubview:self.dimView];

        [NSLayoutConstraint activateConstraints:@[
            [self.wallpaperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.wallpaperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.wallpaperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.wallpaperView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.frostView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.frostView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.frostView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.frostView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.dimView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.dimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.dimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.dimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        // 双通知刷新（壁纸变化 + 效果滑条）；reentrant 安全（主线程收敛）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame429_onBackgroundChanged)
                                                     name:Ame223WallpaperChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame429_onBackgroundChanged)
                                                     name:@"BackgroundUIEffectChanged"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 刷新（挂载方幂等入口）

- (void)ame429_refreshWithOwnerViewController:(UIViewController *)ownerVC {
    void (^apply)(void) = ^{
        // ★Task452（「打开即闪退」判读轮）：壁纸层重建 @try 收敛（Task450-r1
        //   P0 设置闪退装饰面判例同型）——宿主为纯装饰层，重建异常降级为
        //   签名日志 + alpha 恒 0（无壁纸观感），壳/主页存活零阻断。
        @try {
            [self ame429_rebuildLayers];
        } @catch (NSException *ame452_ex) {
            self.alpha = 0.0;
            NSLog(@"[Task452] open: background-host rebuild EXCEPTION signature: %@ (%@) -- wallpaper layer degraded", ame452_ex.name, ame452_ex.reason);
        }
        // 可见性机制（既有管线，不新增广播）：有壁纸 = Task111 透明化管线
        // 透出壳层树基色（hasBackground 守卫幂等）；无壁纸 = 对称还原
        //（owner 树基色回 [ZL2Theme surface]，宿主已隐藏）。
        BOOL ame429_hasWall = [BackgroundManager sharedManager].hasBackground;
        if (ownerVC == nil) return;
        if (ame429_hasWall) {
            [[BackgroundManager sharedManager] makeViewControllerTransparent:ownerVC];
        } else {
            [self ame429_restoreOwnerBases:ownerVC];
        }
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

#pragma mark - 通知回调

- (void)ame429_onBackgroundChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame429_rebuildLayers];
    });
}

#pragma mark - 图层重建

- (void)ame429_rebuildLayers {
    BackgroundManager *bg = [BackgroundManager sharedManager];
    if (![bg hasImageBackground]) {
        // 无图片壁纸（无背景/视频/纯色）：宿主整体隐藏（旧壳全局容器照旧
        // 服务其它页面，宿主与它互不干扰）
        self.alpha = 0.0;
        return;
    }
    // Task223 降采样直取（不自行解码原图——宿主直吃降采样管线）
    UIImage *wallpaper = [bg ame223_currentWallpaperImage];
    if (wallpaper == nil) {
        self.alpha = 0.0;
        return;
    }
    self.wallpaperView.image = wallpaper;
    self.wallpaperView.alpha = bg.uiOpacity;   // 底图 alpha = 既有透明度令牌

    if (bg.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃档：UIVisualEffectView 整层安装（非逐帧 blur），强度 =
        // blurIntensity 映射（frostAlpha 同族；Task256 语义 0 = 用户真实意图
        // 全透，effectView alpha 随 0）
        self.frostView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        self.frostView.alpha = Ame429FrostAlphaBase + bg.blurIntensity * Ame429FrostAlphaSpan;
    } else {
        // 半透明档：整层不装（Task289/256 锐利档口径对齐）
        self.frostView.effect = nil;
        self.frostView.alpha = 0.0;
    }
    self.dimView.alpha = bg.blurIntensity * Ame429DimSpan;   // 压暗层（Task161 语义）
    self.alpha = 1.0;
}

// 无壁纸还原：owner 树基色回 [ZL2Theme surface]（透明化管线的对称面；
// 仅还原 VC 根视图——页内卡片/列表色由页面自身动态令牌自愈）
- (void)ame429_restoreOwnerBases:(UIViewController *)ownerVC {
    if (ownerVC == nil) return;
    ownerVC.view.backgroundColor = [ZL2Theme surface];
    for (UIViewController *child in ownerVC.childViewControllers) {
        child.view.backgroundColor = [ZL2Theme surface];
    }
    // ★Task449：chrome/卡面标记面对称还原（壳层顶栏/设置左轨等标记面回
    // ZL2Theme surface，卡面回基色——透明化管线的无壁纸侧收口）
    [[BackgroundManager sharedManager] ame449_applyWallpaperTransparencyToViewTree:ownerVC.view];
}

@end
