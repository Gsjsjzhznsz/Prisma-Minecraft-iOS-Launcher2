//
// ZL2SkinPreviewView.m — ★ Task413 账户页内嵌皮肤 3D 预览实现（契约见 .h）
//
// ★Task413 根修三件（对照 412f）：
//   ① Y 轴翻转：CALayer 坐标 Y 向下（+Y = 屏幕下），模型空间 Y 向上
//     （0 足底 → 32 头顶）。412f 直摆 = 头钻屏底腿悬顶（IMG_0596 实锤）。
//     本版盒心 y_l = −(y_m − 16) 翻转，顶/底面 offY/rotX 同步换向；
//   ② 盒体左右面贴图换位：Minecraft 展开图（0,8)=角色右脸、(16,8)=角色
//     左脸；412f 面 表序把 左 区块摆在 −X（角色右）侧 = 左右互换。
//     本版 −X 侧贴右区块、+X 侧贴左区块（含横轴向：右脸区右缘 = 前缘，
//     左脸区左缘 = 前缘，与 rotY ±90° 旋转后的局部 +X/−X 指向逐一核对）；
//   ③ 皮肤链账户类型分流（Alex 根因）：第三方走 yggdrasil 真皮链，
//     Mojang/微软走 crafatar→minotar，本地盘 skinfull 优先 = 离线真皮。
//

#import "ZL2SkinPreviewView.h"
#import "ZL2Theme.h"
#import "utils.h"   // localize()
#import "authenticator/ThirdPartyAuthenticator.h"   // ★Task413 全皮落盘路径（ame133 链同步持久化）

#import <math.h>

#pragma mark - 缓存路径

// 皮肤缓存目录（Library/Caches/skins，412f 同款）
static NSString *ZL2SkinViewCacheDir(void) {
    static NSString *ame413_dir;
    static dispatch_once_t ame413_once;
    dispatch_once(&ame413_once, ^{
        NSArray *ame413_paths = [[NSFileManager defaultManager]
            URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
        ame413_dir = [[ame413_paths.firstObject path]
            stringByAppendingPathComponent:@"skins"];
        [[NSFileManager defaultManager] createDirectoryAtPath:ame413_dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return ame413_dir;
}

// 全皮落盘（Documents/avatars/skinfull-<accountId>.png；ame133 链同步持久化
// 判例——skin- 前缀 = 渲染头像，skinfull- 前缀 = 原始全皮，两键空间互不冲突）
static NSString *ZL2SkinViewFullSkinPath(NSString *accountId) {
    return [ThirdPartyAuthenticator ame413_fullSkinPathForAccountId:accountId];
}

// 账户名转安全文件名（AvatarManager 判例同款：防路径穿越）
static NSString *ZL2SkinViewSafeName(NSString *name) {
    if (name.length == 0) return @"anonymous";
    NSCharacterSet *ame413_invalid =
        [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *ame413_parts = [name componentsSeparatedByCharactersInSet:ame413_invalid];
    NSString *ame413_cleaned = [ame413_parts componentsJoinedByString:@"_"];
    return (ame413_cleaned.length > 0) ? ame413_cleaned : @"anonymous";
}

#pragma mark - 皮肤 UV 区块表

typedef struct {
    CGFloat x, y, w, h;
} ZL2SkinViewRect;

// 面表序 = [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]（与 buildBox 六面
// 构建序一致）。★Task413 换位：旧表第 3/4 位 = 左/右区块直摆，但 −X 侧
// 是角色右 = 右区块该摆 −X 位（IMG_0596 倒置之外的侧脸互换修正）。
// 64×64 标准布局（原点左上）：
//   头 8³：前(8,8) 后(24,8) 右(0,8) 左(16,8) 上(8,0) 下(16,0)
//   身 8×12×4：前(20,20) 后(32,20) 右(16,20) 左(28,20) 上(20,16) 下(28,16)
//   右臂 4×12×4：前(44,20) 后(52,20) 右(40,20) 左(48,20) 上(44,16) 下(48,16)
//   左臂 4×12×4：前(36,52) 后(44,52) 右(32,52) 左(40,52) 上(36,48) 下(40,48)
//   右腿 4×12×4：前(4,20) 后(12,20) 右(0,20) 左(8,20) 上(4,16) 下(8,16)
//   左腿 4×12×4：前(20,52) 后(28,52) 右(16,52) 左(24,52) 上(20,48) 下(24,48)
// 64×32 旧版：左臂/左腿整组镜像右臂/右腿区块（legacy 分支）。
static const ZL2SkinViewRect ZL2SkinViewHeadFaces[6] = {
    {8, 8, 8, 8}, {24, 8, 8, 8}, {0, 8, 8, 8}, {16, 8, 8, 8}, {8, 0, 8, 8}, {16, 0, 8, 8}};
static const ZL2SkinViewRect ZL2SkinViewBodyFaces[6] = {
    {20, 20, 8, 12}, {32, 20, 8, 12}, {16, 20, 4, 12}, {28, 20, 4, 12}, {20, 16, 8, 4}, {28, 16, 8, 4}};
// 经典臂（4 宽）
static const ZL2SkinViewRect ZL2SkinViewRArmFaces[6] = {
    {44, 20, 4, 12}, {52, 20, 4, 12}, {40, 20, 4, 12}, {48, 20, 4, 12}, {44, 16, 4, 4}, {48, 16, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewLArmFaces[6] = {
    {36, 52, 4, 12}, {44, 52, 4, 12}, {32, 52, 4, 12}, {40, 52, 4, 12}, {36, 48, 4, 4}, {40, 48, 4, 4}};
// slim 臂（3 宽：前/后/上/下 3pt，左右侧 4pt——slim 展开图官方口径）
static const ZL2SkinViewRect ZL2SkinViewRArmSlimFaces[6] = {
    {44, 20, 3, 12}, {51, 20, 3, 12}, {40, 20, 4, 12}, {48, 20, 4, 12}, {44, 16, 3, 4}, {47, 16, 3, 4}};
static const ZL2SkinViewRect ZL2SkinViewLArmSlimFaces[6] = {
    {36, 52, 3, 12}, {43, 52, 3, 12}, {32, 52, 4, 12}, {40, 52, 4, 12}, {36, 48, 3, 4}, {39, 48, 3, 4}};
static const ZL2SkinViewRect ZL2SkinViewRLegFaces[6] = {
    {4, 20, 4, 12}, {12, 20, 4, 12}, {0, 20, 4, 12}, {8, 20, 4, 12}, {4, 16, 4, 4}, {8, 16, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewLLegFaces[6] = {
    {20, 52, 4, 12}, {28, 52, 4, 12}, {16, 52, 4, 12}, {24, 52, 4, 12}, {20, 48, 4, 4}, {24, 48, 4, 4}};

// 区块裁贴子图（皮肤为 64×64 / 64×32 / HD 等比；裁剪矩形越界自动求交防炸）
static UIImage *ZL2SkinViewFaceImage(UIImage *skin, ZL2SkinViewRect r) {
    if (!skin.CGImage) return nil;
    CGFloat ame413_scaleX = skin.size.width / 64.0;
    CGFloat ame413_scaleY = skin.size.height / 64.0;
    CGRect ame413_crop = CGRectMake(r.x * ame413_scaleX, r.y * ame413_scaleY,
                                    r.w * ame413_scaleX, r.h * ame413_scaleY);
    CGRect ame413_bounds = CGRectMake(0, 0,
                                      CGImageGetWidth(skin.CGImage),
                                      CGImageGetHeight(skin.CGImage));
    ame413_crop = CGRectIntersection(ame413_crop, ame413_bounds);
    if (CGRectIsEmpty(ame413_crop)) return nil;
    CGImageRef ame413_sub = CGImageCreateWithImageInRect(skin.CGImage, ame413_crop);
    if (!ame413_sub) return nil;
    UIImage *ame413_face = [UIImage imageWithCGImage:ame413_sub];
    CGImageRelease(ame413_sub);
    return ame413_face;
}

#pragma mark - 盒体几何

// 盒体参数（模型空间；Y 自足底 0 起算、+Y 向上，角色面朝 +Z、角色右 = −X）
typedef struct {
    CGFloat cx, cy, cz;   // 盒心
    CGFloat w, h, d;      // 尺寸
    const ZL2SkinViewRect *faces;   // 六面区块表 [前 后 右 左 上 下]
} ZL2SkinViewBox;

#pragma mark - 实现

@implementation ZL2SkinPreviewView {
    UIView *_ame413_stageView;                       // 3D 舞台（透视 sublayerTransform 宿主）
    NSMutableArray<CALayer *> *_ame413_faceLayers;   // 36 面子层
    UILabel *_ame413_hintLabel;
    UILabel *_ame413_statusLabel;
    UIActivityIndicatorView *_ame413_spinner;
    NSDictionary *_ame413_authData;
    NSString *_ame413_accountKey;                    // 已装载账户键（幂等闸）
    UIImage *_ame413_currentSkin;
    BOOL _ame413_slimModel;                          // slim 细臂（yggdrasil metadata.model）
    CGFloat _ame413_yaw;
    CGFloat _ame413_pitch;
    CGFloat _ame413_userScale;
    CGFloat _ame413_baseUnit;
    CADisplayLink *_ame413_ticker;
    CFTimeInterval _ame413_lastTick;
}

#pragma mark 生命周期

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _ame413_yaw = 0.0;
        _ame413_pitch = 0.0;
        _ame413_userScale = 1.0;
        _ame413_slimModel = NO;
        _ame413_faceLayers = [NSMutableArray array];
        self.backgroundColor = [ZL2Theme surfaceContainer];
        self.layer.cornerRadius = [ZL2Theme radiusM];
        self.layer.masksToBounds = YES;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = localize(@"ame412.skin.preview.title", @"皮肤 3D 预览");
        [self ame413_buildStage];
        [self ame413_buildChrome];
    }
    return self;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow == nil) {
        [_ame413_ticker invalidate];
        _ame413_ticker = nil;
    } else if (_ame413_ticker == nil) {
        _ame413_ticker = [CADisplayLink displayLinkWithTarget:self selector:@selector(ame413_tick)];
        _ame413_lastTick = CACurrentMediaTime();
        [_ame413_ticker addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)dealloc {
    [_ame413_ticker invalidate];
}

#pragma mark 骨架

- (void)ame413_buildStage {
    _ame413_stageView = [[UIView alloc] initWithFrame:CGRectZero];
    _ame413_stageView.backgroundColor = [UIColor clearColor];
    _ame413_stageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame413_stageView];
    [NSLayoutConstraint activateConstraints:@[
        [_ame413_stageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
        [_ame413_stageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_ame413_stageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    // 透视宿主：sublayerTransform 持 m34（CA 经典 3D 盒体技法，412f 判例）
    CATransform3D ame413_persp = CATransform3DIdentity;
    ame413_persp.m34 = -1.0 / 700.0;
    _ame413_stageView.layer.sublayerTransform = ame413_persp;

    // 手势：拖轨（水平 = yaw、竖直 = pitch）+ 捏合缩放
    UIPanGestureRecognizer *ame413_pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ame413_handlePan:)];
    [_ame413_stageView addGestureRecognizer:ame413_pan];
    UIPinchGestureRecognizer *ame413_pinch =
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(ame413_handlePinch:)];
    [_ame413_stageView addGestureRecognizer:ame413_pinch];

    // 占位灰模型先建（皮肤到位即整组拆建；零空白等待）
    [self ame413_applySkin:nil];
}

- (void)ame413_buildChrome {
    _ame413_hintLabel = [[UILabel alloc] init];
    _ame413_hintLabel.text = localize(@"ame412.skin.preview.hint", @"拖动旋转 · 捏合缩放");
    _ame413_hintLabel.font = [ZL2Theme fontLabelMedium];   // 12 medium（内嵌卡小字提示）
    _ame413_hintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ame413_hintLabel.textAlignment = NSTextAlignmentCenter;
    _ame413_hintLabel.numberOfLines = 1;
    _ame413_hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _ame413_hintLabel.userInteractionEnabled = NO;
    [self addSubview:_ame413_hintLabel];

    _ame413_statusLabel = [[UILabel alloc] init];
    _ame413_statusLabel.font = [ZL2Theme fontBodyMedium];
    _ame413_statusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ame413_statusLabel.textAlignment = NSTextAlignmentCenter;
    _ame413_statusLabel.numberOfLines = 2;
    _ame413_statusLabel.hidden = YES;
    _ame413_statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _ame413_statusLabel.userInteractionEnabled = NO;
    [self addSubview:_ame413_statusLabel];

    _ame413_spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _ame413_spinner.color = [ZL2Theme onSurfaceVariant];
    _ame413_spinner.hidesWhenStopped = YES;
    _ame413_spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame413_spinner];

    [NSLayoutConstraint activateConstraints:@[
        // 舞台底 = 提示行顶（提示行钉视图底 6pt）
        [_ame413_stageView.bottomAnchor constraintEqualToAnchor:_ame413_hintLabel.topAnchor constant:-4.0],
        [_ame413_hintLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_ame413_hintLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6.0],
        [_ame413_statusLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_ame413_statusLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_ame413_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:12.0],
        [_ame413_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12.0],
        [_ame413_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_ame413_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

#pragma mark 账户配置与皮肤链

// 同一账户幂等跳过（rebuildIdentityCard 每次 reload 重入）；换肤自愈链
// 落盘后由下次冷启动/重建生效（低频语义，Task133 口径）
- (void)ame413_configureWithAuthData:(NSDictionary *)authData {
    NSString *ame413_name = nil;
    NSString *ame413_pid = nil;
    NSString *ame413_accountId = nil;
    NSString *ame413_server = nil;
    if ([authData isKindOfClass:[NSDictionary class]]) {
        NSString *ame413_u = authData[@"username"];
        if ([ame413_u isKindOfClass:[NSString class]] && ame413_u.length > 0) {
            ame413_name = ([ame413_u hasPrefix:@"Demo."]) ? [ame413_u substringFromIndex:5] : ame413_u;
        }
        NSString *ame413_p = authData[@"profileId"] ?: authData[@"uuid"] ?: authData[@"id"];
        if ([ame413_p isKindOfClass:[NSString class]] && ame413_p.length > 0) ame413_pid = ame413_p;
        NSString *ame413_a = authData[@"accountId"];
        if ([ame413_a isKindOfClass:[NSString class]] && ame413_a.length > 0) ame413_accountId = ame413_a;
        NSString *ame413_s = authData[@"authserver"];
        if ([ame413_s isKindOfClass:[NSString class]] && ame413_s.length > 0) ame413_server = ame413_s;
    }
    NSString *ame413_key = [NSString stringWithFormat:@"%@|%@|%@|%@",
                            ame413_accountId ?: @"-", ame413_pid ?: @"-",
                            ame413_name ?: @"-", ame413_server ?: @"-"];
    if ([ame413_key isEqualToString:_ame413_accountKey]) return;   // 幂等闸
    _ame413_accountKey = [ame413_key copy];
    _ame413_authData = [authData isKindOfClass:[NSDictionary class]] ? authData : nil;
    _ame413_slimModel = NO;
    _ame413_statusLabel.hidden = YES;
    [self ame413_loadSkinWithAccountId:ame413_accountId
                              profileId:ame413_pid
                               username:ame413_name
                              authserver:ame413_server];
}

// ① 本盘缓存 → ② skinfull 全皮 → ③ 网络（账户类型分流）→ ④ 占位
- (void)ame413_loadSkinWithAccountId:(NSString *)accountId
                            profileId:(NSString *)profileId
                             username:(NSString *)username
                            authserver:(NSString *)authserver {
    NSString *ame413_key = (accountId.length > 0) ? accountId
                            : (profileId.length > 0 ? profileId : username);
    NSString *ame413_cachePath = [[ZL2SkinViewCacheDir()
        stringByAppendingPathComponent:ZL2SkinViewSafeName(ame413_key ?: @"anonymous")]
        stringByAppendingPathExtension:@"png"];

    // ① 预览缓存（本视图历史命中）
    UIImage *ame413_cached = [UIImage imageWithContentsOfFile:ame413_cachePath];
    if (ame413_cached) {
        [self ame413_applySkin:ame413_cached];
        return;
    }
    // ② skinfull 全皮（ame133 链落盘的原始皮肤 = 离线真皮）
    NSString *ame413_fullPath = ZL2SkinViewFullSkinPath(accountId);
    if (ame413_fullPath) {
        UIImage *ame413_full = [UIImage imageWithContentsOfFile:ame413_fullPath];
        if (ame413_full.size.width >= 64) {
            [self ame413_applySkin:ame413_full];
            return;
        }
    }

    // ③ 网络链：authserver 在场 = 第三方（authlib-injector）→ yggdrasil 真皮链
    //   （crafatar/minotar 只认 Mojang，第三方 username 恒回默认 Alex =
    //   IMG_0596「为什么是alex的皮肤」根因，第三方路径禁入）；否则 Mojang/
    //   微软/本地 → crafatar(profileId) → minotar(username)。
    if (authserver.length > 0 && profileId.length > 0) {
        [self ame413_fetchYggdrasilSkinWithServer:authserver
                                        profileId:profileId
                                        accountId:accountId
                                        cachePath:ame413_cachePath];
        return;
    }

    NSMutableArray<NSString *> *ame413_urls = [NSMutableArray array];
    if (profileId.length == 36 && ![profileId isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
        [ame413_urls addObject:[NSString stringWithFormat:@"https://crafatar.com/skins/%@", profileId]];
    }
    if (username.length > 0) {
        [ame413_urls addObject:[NSString stringWithFormat:@"https://minotar.net/skin/%@", username]];
    }
    if (ame413_urls.count == 0) {
        [self ame413_showUnavailable];
        return;
    }
    _ame413_spinner.hidden = NO;
    [_ame413_spinner startAnimating];
    [self ame413_tryURLAtIndex:0 urls:ame413_urls cachePath:ame413_cachePath];
}

// 第三方真皮链：<server>sessionserver/session/minecraft/profile/<无连字符UUID>
// → properties[textures].value（base64）→ textures.SKIN.url（一次性签名 URL
// 立即下载，Task133 判例）+ metadata.model = slim 细臂模型；
// 全皮落盘 skinfull-<accountId>.png + 预览缓存双写。
- (void)ame413_fetchYggdrasilSkinWithServer:(NSString *)server
                                   profileId:(NSString *)profileId
                                   accountId:(NSString *)accountId
                                   cachePath:(NSString *)cachePath {
    NSString *ame413_root = [server copy];
    NSRange ame413_api = [ame413_root rangeOfString:@"/api/yggdrasil"];
    if (ame413_api.location != NSNotFound) {
        ame413_root = [ame413_root substringToIndex:ame413_api.location];   // API Root → 站点根（Task224 判例）
    }
    if (![ame413_root hasSuffix:@"/"]) ame413_root = [ame413_root stringByAppendingString:@"/"];
    NSString *ame413_undashed = [profileId stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *ame413_profileURL = [NSString stringWithFormat:@"%@sessionserver/session/minecraft/profile/%@",
                                   ame413_root, ame413_undashed];

    _ame413_spinner.hidden = NO;
    [_ame413_spinner startAnimating];
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *ame413_task =
        [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:ame413_profileURL]
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(wself) strongSelf = wself;
        if (!strongSelf) return;
        NSString *ame413_skinURL = nil;
        NSString *ame413_model = nil;
        if (data.length > 0 && !error) {
            NSDictionary *ame413_json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([ame413_json isKindOfClass:[NSDictionary class]]) {
                for (NSDictionary *ame413_prop in ame413_json[@"properties"]) {
                    if (![ame413_prop isKindOfClass:[NSDictionary class]]) continue;
                    if (![ame413_prop[@"name"] isEqualToString:@"textures"]) continue;
                    NSData *ame413_decoded = [[NSData alloc]
                        initWithBase64EncodedString:ame413_prop[@"value"] options:0];
                    if (!ame413_decoded) continue;
                    NSDictionary *ame413_tex = [NSJSONSerialization
                        JSONObjectWithData:ame413_decoded options:kNilOptions error:nil];
                    if ([ame413_tex isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *ame413_skin = ame413_tex[@"textures"][@"SKIN"];
                        if ([ame413_skin isKindOfClass:[NSDictionary class]] &&
                            [ame413_skin[@"url"] isKindOfClass:[NSString class]]) {
                            ame413_skinURL = ame413_skin[@"url"];
                            NSString *ame413_m = ame413_skin[@"metadata"][@"model"];
                            if ([ame413_m isKindOfClass:[NSString class]]) ame413_model = ame413_m;
                        }
                        break;
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) inner = wself;
            if (!inner) return;
            if (ame413_skinURL.length == 0) {
                [inner->_ame413_spinner stopAnimating];
                [inner ame413_showUnavailable];
                return;
            }
            [inner ame413_downloadSkinAtURL:ame413_skinURL
                                   accountId:accountId
                                   slim:(ame413_model.length > 0 && [ame413_model isEqualToString:@"slim"])
                                   cachePath:cachePath];
        });
    }];
    [ame413_task resume];
}

// 签名 URL 立即下载（延迟即 404，Task133 判例）→ 全皮 + 缓存双写 → 建模
- (void)ame413_downloadSkinAtURL:(NSString *)skinURL
                        accountId:(NSString *)accountId
                             slim:(BOOL)slim
                        cachePath:(NSString *)cachePath {
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *ame413_task =
        [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:skinURL]
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(wself) strongSelf = wself;
        if (!strongSelf) return;
        UIImage *ame413_skin = (data.length > 0 && !error) ? [UIImage imageWithData:data] : nil;
        BOOL ame413_valid = ame413_skin.size.width >= 64 &&
            (ame413_skin.size.height == ame413_skin.size.width ||
             ame413_skin.size.height * 2 == ame413_skin.size.width);   // ame133 合法性同口径
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) inner = wself;
            if (!inner) return;
            [inner->_ame413_spinner stopAnimating];
            if (ame413_valid) {
                [data writeToFile:cachePath atomically:YES];   // 预览缓存
                NSString *ame413_fullPath = ZL2SkinViewFullSkinPath(accountId);
                if (ame413_fullPath) [data writeToFile:ame413_fullPath atomically:YES];   // 全皮落盘（离线真皮）
                inner->_ame413_slimModel = slim;
                [inner ame413_applySkin:ame413_skin];
            } else {
                [inner ame413_showUnavailable];
            }
        });
    }];
    [ame413_task resume];
}

// Mojang 链逐级回退（方法递归回退 = run 42487051782 保留环判例规避）
- (void)ame413_tryURLAtIndex:(NSUInteger)ame413_idx
                        urls:(NSArray<NSString *> *)ame413_urls
                   cachePath:(NSString *)ame413_cachePath {
    if (ame413_idx >= ame413_urls.count) {
        [_ame413_spinner stopAnimating];
        [self ame413_applySkin:nil];
        [self ame413_showUnavailable];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *ame413_task =
        [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:ame413_urls[ame413_idx]]
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *ame413_image = (data.length > 0 && !error) ? [UIImage imageWithData:data] : nil;
        BOOL ame413_valid = ame413_image.size.width >= 64 &&
            (ame413_image.size.height == ame413_image.size.width ||
             ame413_image.size.height * 2 == ame413_image.size.width);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) strongSelf = wself;
            if (!strongSelf) return;
            if (ame413_image && ame413_valid) {
                [data writeToFile:ame413_cachePath atomically:YES];
                [strongSelf->_ame413_spinner stopAnimating];
                [strongSelf ame413_applySkin:ame413_image];
            } else {
                [strongSelf ame413_tryURLAtIndex:ame413_idx + 1 urls:ame413_urls cachePath:ame413_cachePath];
            }
        });
    }];
    [ame413_task resume];
}

- (void)ame413_showUnavailable {
    _ame413_statusLabel.hidden = NO;
    _ame413_statusLabel.text = localize(@"ame412.skin.preview.unavailable", @"皮肤加载失败，显示占位模型");
}

#pragma mark 手势与帧驱动

- (void)ame413_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint ame413_t = [pan translationInView:_ame413_stageView];
    [pan setTranslation:CGPointZero inView:_ame413_stageView];
    _ame413_yaw += ame413_t.x * 0.008;
    _ame413_pitch += ame413_t.y * 0.008;
    if (_ame413_pitch > 0.9) _ame413_pitch = 0.9;
    if (_ame413_pitch < -0.9) _ame413_pitch = -0.9;
    [self ame413_updateModelTransform];
}

- (void)ame413_handlePinch:(UIPinchGestureRecognizer *)pinch {
    _ame413_userScale *= pinch.scale;
    if (_ame413_userScale < 0.5) _ame413_userScale = 0.5;
    if (_ame413_userScale > 2.5) _ame413_userScale = 2.5;
    [pinch setScale:1.0];
    [self ame413_updateModelTransform];
}

- (void)ame413_tick {
    CFTimeInterval ame413_now = CACurrentMediaTime();
    CGFloat ame413_dt = (CGFloat)(ame413_now - _ame413_lastTick);
    _ame413_lastTick = ame413_now;
    if (ame413_dt > 0.1) ame413_dt = 0.1;
    _ame413_yaw += ame413_dt * 0.35;   // 慢速自转（rad/s）
    [self ame413_updateModelTransform];
}

// 模型层每帧 transform = RotX(pitch)·RotY(yaw)·Scale(user)
- (void)ame413_updateModelTransform {
    CGFloat ame413_s = _ame413_userScale;
    CATransform3D ame413_t = CATransform3DMakeRotation(_ame413_pitch, 1.0, 0.0, 0.0);
    ame413_t = CATransform3DRotate(ame413_t, _ame413_yaw, 0.0, 1.0, 0.0);
    ame413_t = CATransform3DScale(ame413_t, ame413_s, ame413_s, ame413_s);
    _ame413_stageView.layer.transform = ame413_t;
}

// 视口自适应比例（模型高 32 单位 → 舞台高的 0.78；内嵌卡幅面小，占满些）
- (void)ame413_recomputeBaseUnit {
    CGFloat ame413_h = _ame413_stageView.bounds.size.height;
    CGFloat ame413_w = _ame413_stageView.bounds.size.width;
    CGFloat ame413_fit = fmin(ame413_h * 0.78 / 32.0, ame413_w * 0.55 / 16.0);
    if (ame413_fit < 2.0) ame413_fit = 2.0;
    _ame413_baseUnit = ame413_fit;
    [self ame413_updateModelTransform];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat ame413_h = _ame413_stageView.bounds.size.height;
    CGFloat ame413_w = _ame413_stageView.bounds.size.width;
    CGFloat ame413_fit = fmin(ame413_h * 0.78 / 32.0, ame413_w * 0.55 / 16.0);
    if (ame413_fit < 2.0) ame413_fit = 2.0;
    if (fabs(ame413_fit - _ame413_baseUnit) > 0.5) {
        _ame413_baseUnit = ame413_fit;
        [self ame413_applySkin:_ame413_currentSkin];   // unit 变化整组重建
        return;
    }
    CGPoint ame413_center = CGPointMake(CGRectGetMidX(_ame413_stageView.bounds),
                                        CGRectGetMidY(_ame413_stageView.bounds));
    for (CALayer *ame413_face in _ame413_faceLayers) {
        ame413_face.position = ame413_center;
    }
}

#pragma mark 盒体组装（36 面静态子层）

// 单盒六面（面序 [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]）。
// ★Task413 坐标翻转核心：层空间 +Y 向下（屏幕），模型空间 +Y 向上——
// 盒心 y_l = −(y_m − 16)；顶面（模型 +Y）offY = −h/2、rotX = +π/2（法线
// (0,0,1)→(0,−1,0) = 朝屏上），底面反号。横向不变（+X 右、+Z 朝观者）。
// 逐面横轴向（与展开图接缝核对）：前=恒等、后=rotY(π)（纹理左右镜像 =
// 背视正确）、右(−X)=rotY(−π/2)（局部 +X→+Z 前缘 = 右脸区右缘 ✓）、
// 左(+X)=rotY(+π/2)（局部 −X→+Z 前缘 = 左脸区左缘 ✓）。
static void ZL2SkinViewBuildBox(CALayer *ame413_parent,
                                CGPoint ame413_center,
                                ZL2SkinViewBox ame413_box,
                                CGFloat ame413_unit,
                                UIImage *ame413_skin) {
    CGFloat ame413_x = ame413_box.cx;
    CGFloat ame413_y = -(ame413_box.cy - 16.0);   // ★Task413 Y 翻转（模型 0..32 → 层 −16..16 头朝上）
    CGFloat ame413_z = ame413_box.cz;
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        CGFloat ame413_offX = 0, ame413_offY = 0, ame413_offZ = 0;
        CGFloat ame413_rotY = 0, ame413_rotX = 0;
        CGFloat ame413_fw = 0, ame413_fh = 0;
        switch (ame413_i) {
            case 0:   // 前：面朝 +Z，z + d/2
                ame413_offZ = ame413_box.d / 2.0; ame413_fw = ame413_box.w; ame413_fh = ame413_box.h;
                break;
            case 1: { // 后：RotY(π)，z − d/2
                ame413_offZ = -ame413_box.d / 2.0; ame413_rotY = (CGFloat)M_PI;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.h;
                break;
            }
            case 2: { // 右（角色右 = −X 侧）：x − w/2
                ame413_offX = -ame413_box.w / 2.0; ame413_rotY = -(CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.d; ame413_fh = ame413_box.h;
                break;
            }
            case 3: { // 左（角色左 = +X 侧）：x + w/2
                ame413_offX = ame413_box.w / 2.0; ame413_rotY = (CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.d; ame413_fh = ame413_box.h;
                break;
            }
            case 4: { // 上（模型 +Y = 屏上）：y − h/2，rotX(+π/2)
                ame413_offY = -ame413_box.h / 2.0; ame413_rotX = (CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.d;
                break;
            }
            default: { // 下（模型 −Y = 屏下）：y + h/2，rotX(−π/2)
                ame413_offY = ame413_box.h / 2.0; ame413_rotX = -(CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.d;
                break;
            }
        }

        CALayer *ame413_face = [CALayer layer];
        ame413_face.bounds = CGRectMake(0, 0, ame413_fw * ame413_unit, ame413_fh * ame413_unit);
        ame413_face.position = ame413_center;
        ame413_face.doubleSided = NO;   // 背面剔除（CALayer 属性名无 is 前缀）
        UIImage *ame413_img = ame413_skin ? ZL2SkinViewFaceImage(ame413_skin, ame413_box.faces[ame413_i]) : nil;
        if (ame413_img) {
            ame413_face.contents = (id)ame413_img.CGImage;
            ame413_face.contentsGravity = kCAGravityResize;
        } else {
            ame413_face.backgroundColor = [UIColor colorWithWhite:0.32 alpha:1.0].CGColor;   // 占位灰面
        }
        CATransform3D ame413_t = CATransform3DMakeTranslation((ame413_x + ame413_offX) * ame413_unit,
                                                              (ame413_y + ame413_offY) * ame413_unit,
                                                              (ame413_z + ame413_offZ) * ame413_unit);
        if (ame413_rotY != 0.0) ame413_t = CATransform3DRotate(ame413_t, ame413_rotY, 0.0, 1.0, 0.0);
        if (ame413_rotX != 0.0) ame413_t = CATransform3DRotate(ame413_t, ame413_rotX, 1.0, 0.0, 0.0);
        ame413_face.transform = ame413_t;
        [ame413_parent addSublayer:ame413_face];
    }
}

// 用皮肤整组建模（skin = nil 时灰盒占位；每次整组拆建零残留）
- (void)ame413_applySkin:(UIImage *)skin {
    _ame413_currentSkin = skin;
    CALayer *ame413_stage = _ame413_stageView.layer;
    for (CALayer *ame413_sub in [ame413_stage.sublayers copy]) {
        [ame413_sub removeFromSuperlayer];
    }
    [_ame413_faceLayers removeAllObjects];

    CGPoint ame413_center = CGPointMake(CGRectGetMidX(_ame413_stageView.bounds),
                                        CGRectGetMidY(_ame413_stageView.bounds));
    CGFloat ame413_unit = _ame413_baseUnit;
    if (ame413_unit < 2.0) {
        [self ame413_recomputeBaseUnit];
        ame413_unit = _ame413_baseUnit;
    }

    if (skin.size.width < 1.0 || skin.size.height < 1.0) {
        // 占位灰模型（皮肤缺席诚实降级，零假纹理）
        ZL2SkinViewRect ame413_dummy[6] = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0},
                                           {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}};
        ZL2SkinViewBox ame413_box = {0, 16, 0, 10, 32, 6, ame413_dummy};
        ZL2SkinViewBuildBox(ame413_stage, ame413_center, ame413_box, ame413_unit, nil);
        [_ame413_faceLayers addObjectsFromArray:ame413_stage.sublayers];
        return;
    }

    BOOL ame413_legacy = (skin.size.height < skin.size.width);   // 64×32 旧版 = 左臂左腿镜像右区
    const ZL2SkinViewRect *ame413_rArmF = _ame413_slimModel ? ZL2SkinViewRArmSlimFaces : ZL2SkinViewRArmFaces;
    const ZL2SkinViewRect *ame413_lArmF = ame413_legacy ? ame413_rArmF
                                        : (_ame413_slimModel ? ZL2SkinViewLArmSlimFaces : ZL2SkinViewLArmFaces);
    const ZL2SkinViewRect *ame413_lLegF = ame413_legacy ? ZL2SkinViewRLegFaces : ZL2SkinViewLLegFaces;
    CGFloat ame413_armW = _ame413_slimModel ? 3.0 : 4.0;
    CGFloat ame413_armCx = 4.0 + ame413_armW / 2.0;   // 臂贴身侧：身半宽 4 + 臂半宽

    ZL2SkinViewBox ame413_boxes[6] = {
        {0, 28, 0, 8, 8, 8, ZL2SkinViewHeadFaces},          // 头（足底 24..32）
        {0, 18, 0, 8, 12, 4, ZL2SkinViewBodyFaces},         // 身（12..24）
        {-ame413_armCx, 18, 0, ame413_armW, 12, 4, ame413_rArmF},   // 右臂（角色右 = −X）
        {ame413_armCx, 18, 0, ame413_armW, 12, 4, ame413_lArmF},    // 左臂
        {-2, 6, 0, 4, 12, 4, ZL2SkinViewRLegFaces},         // 右腿（0..12）
        {2, 6, 0, 4, 12, 4, ame413_lLegF},                  // 左腿
    };
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        ZL2SkinViewBuildBox(ame413_stage, ame413_center, ame413_boxes[ame413_i], ame413_unit, skin);
    }
    [_ame413_faceLayers addObjectsFromArray:ame413_stage.sublayers];
    [self ame413_updateModelTransform];
}

@end
