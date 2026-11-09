//
// ZL2SkinPreviewView.m — ★ Task414 账户页皮肤工作室 v3（契约见 .h）
//
// ★Task414 第 23 轮复诉三线（「3d渲染依旧纸片」「我们要写和皮肤站差不多的
//   功能」「为什么有这么多空间还要挤在一起，直接往右边挪不行吗」）：
//   ① 真 3D 四件套（纸片感四根因）：
//     · 深度排序——CALayer 兄弟层按声明序合成（413 的 36 面静态序），旋转
//       时远面盖近面/近面穿远面 = 纸片实感之一；本版逐帧按「面中心经肢体
//       摆动 + 模型旋转后的 z」写 zPosition，遮挡永远正确；
//     · 逐面光影——六面恒等亮度（413 零光照）= 纸片实感之二；本版每面
//       叠黑色罩层，opacity = 1 − shade，shade 由「面法线 × 固定光向」点积
//       逐帧求值（左上前主光），转动时明暗随动 = 体积感；
//     · 透视加强——m34 −1/700 → −1/480（内嵌卡幅面小，弱透视几乎不可辨）；
//     · 跑步动画——四肢绕肩/髋枢轴 RotX 正弦摆动（对相位），静止模型 = 纸片
//       实感之三，摆动瞬间「模型」可辨（皮肤站 IMG_0607 跑步键同语义）。
//   ② 皮肤站控件组（IMG_0607 口径落地）：顶行 提示语 + 跑步/暂停/刷新；
//     底行 背景色板三枚（黑/深灰/浅灰）+ 左右旋转箭头；动作行 添加至衣柜/
//     设为头像/下载。本机无服务端 → 皮肤站「举报/点赞」无对端语义诚实不做。
//   ③ 衣柜：Documents/skinwardrobe/<uuid>.png + index.plist（本机持久），
//     缩略条点按即穿、长按移除；
//   ④ 设为头像：头部前脸 8×8 裁贴放大 → AvatarManager saveAvatarForAccount
//     （Documents/avatars/<account>.png 既有链首位命中）；
//   ⑤ 下载：皮肤 PNG 系统分享面板（存文件/照片两落点，iPad 锚定按钮防崩）。
// （413 基线全量保留：Y 轴翻转 y_l = −(y_m−16) / 左右面换位 / slim 模型 /
//   yggdrasil 真皮链 / skinfull 全皮落盘 / 缓存四段回退——ame378 C19 锚点
//   字节级不动，S-C19 反向探针持续有效。）
//

#import "ZL2SkinPreviewView.h"
#import "ZL2Theme.h"
#import "utils.h"   // localize()
#import "AvatarManager.h"   // ★Task414 设为头像落点（Documents/avatars 既有链）
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

#pragma mark - 衣柜（★Task414 皮肤站功能：本机持久，无服务端）

// 衣柜目录 Documents/skinwardrobe/ + 索引 index.plist（文件名数组）
static NSString *ZL2SkinWardrobeDir(void) {
    static NSString *ame414_dir;
    static dispatch_once_t ame414_once;
    dispatch_once(&ame414_once, ^{
        NSArray *ame414_paths = [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        ame414_dir = [[ame414_paths.firstObject path]
            stringByAppendingPathComponent:@"skinwardrobe"];
        [[NSFileManager defaultManager] createDirectoryAtPath:ame414_dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return ame414_dir;
}

static NSString *ZL2SkinWardrobeIndexPath(void) {
    return [[ZL2SkinWardrobeDir() stringByAppendingPathComponent:@"index"]
        stringByAppendingPathExtension:@"plist"];
}

static NSMutableArray<NSString *> *ZL2SkinWardrobeLoad(void) {
    NSArray *ame414_stored = [NSArray arrayWithContentsOfFile:ZL2SkinWardrobeIndexPath()];
    NSMutableArray<NSString *> *ame414_out = [NSMutableArray array];
    for (NSString *ame414_name in ame414_stored) {
        if ([ame414_name isKindOfClass:[NSString class]] && ame414_name.length > 0) {
            [ame414_out addObject:ame414_name];
        }
    }
    return ame414_out;
}

static void ZL2SkinWardrobeSave(NSArray<NSString *> *entries) {
    [(NSArray *)entries writeToFile:ZL2SkinWardrobeIndexPath() atomically:YES];
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

// ★Task414 设为头像：头部前脸 8×8 原生裁贴（nearest 邻域放大到 ≥256px，
// 像-素风头像像素锐利）
static UIImage *ZL2SkinViewHeadAvatarImage(UIImage *skin) {
    UIImage *ame414_face = ZL2SkinViewFaceImage(skin, ZL2SkinViewHeadFaces[0]);
    if (!ame414_face) return nil;
    CGFloat ame414_target = 256.0;
    CGFloat ame414_scale = ame414_target / ame414_face.size.width;
    CGSize ame414_size = CGSizeMake(ame414_target, ame414_face.size.height * ame414_scale);
    UIGraphicsBeginImageContextWithOptions(ame414_size, NO, 1.0);
    CGContextRef ame414_ctx = UIGraphicsGetCurrentContext();
    if (ame414_ctx) {
        CGContextSetInterpolationQuality(ame414_ctx, kCGInterpolationNone);   // 像素风：零插值
        [ame414_face drawInRect:CGRectMake(0, 0, ame414_size.width, ame414_size.height)];
    }
    UIImage *ame414_out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return ame414_out;
}

#pragma mark - 盒体几何

// 盒体参数（模型空间；Y 自足底 0 起算、+Y 向上，角色面朝 +Z、角色右 = −X）
typedef struct {
    CGFloat cx, cy, cz;   // 盒心
    CGFloat w, h, d;      // 尺寸
    const ZL2SkinViewRect *faces;   // 六面区块表 [前 后 右 左 上 下]
} ZL2SkinViewBox;

// ★Task414 面记录：静态基准（层空间中心/法线/朝向/枢轴）+ 面层/光影罩层
@interface ZL2SkinViewFace : NSObject
@property (nonatomic, strong) CALayer *layer;    // 贴图面（shade 为其子层随动）
@property (nonatomic, strong) CALayer *shade;    // 黑色光影罩（opacity = 1−shade 逐帧）
@property (nonatomic, assign) CATransform3D ame_baseT;   // 静态基准变换 T(center)·R_face（结构体 = assign 语义）
@property (nonatomic, assign) CGFloat cx, cy, cz;        // 面中心（层空间 pt，已乘 unit）
@property (nonatomic, assign) CGFloat nx, ny, nz;        // 面法线（层空间，Y 向下系）
@property (nonatomic, assign) CGFloat px, py, pz;        // 肢体枢轴（层空间 pt；非肢体 = center）
@property (nonatomic, assign) CGFloat swingSign;         // 摆动方向（0 = 非肢体）
@end
@implementation ZL2SkinViewFace
@end

// ★Task414 点按载荷钮（ame_action block 判例同款：零 viewWithTag、零 a11y 载荷挪用）
@interface ZL2SkinViewTapControl : UIControl
@property (nonatomic, copy) void (^ame414_onTap)(void);
@property (nonatomic, copy) void (^ame414_onLongPress)(void);
@end
@implementation ZL2SkinViewTapControl
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addTarget:self action:@selector(ame414_fireTap) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *ame414_long =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ame414_fireLong:)];
        [self addGestureRecognizer:ame414_long];
    }
    return self;
}
- (void)ame414_fireTap { if (_ame414_onTap) _ame414_onTap(); }
- (void)ame414_fireLong:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan && _ame414_onLongPress) _ame414_onLongPress();
}
@end

// ★Task414 光向（层空间 +Y 向下 → 光来自左上前方）
static const CGFloat AME414_LIGHT_X = -0.45;
static const CGFloat AME414_LIGHT_Y = -0.62;
static const CGFloat AME414_LIGHT_Z =  0.65;

#pragma mark - 实现

@implementation ZL2SkinPreviewView {
    UIView *_ame413_stageView;                       // 3D 舞台（透视 sublayerTransform 宿主）
    NSMutableArray<ZL2SkinViewFace *> *_ame413_faceLayers;   // 36 面记录
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
    // ——皮肤链重刷参数（刷新键复走链路）——
    NSString *_ame414_lastAccountId;
    NSString *_ame414_lastProfileId;
    NSString *_ame414_lastUsername;
    NSString *_ame414_lastAuthserver;
    BOOL _ame414_refreshBypass;                      // 刷新：绕过两级磁盘缓存直取网络
    // ——★Task414 皮肤站控件与动画态——
    UIControl *_ame414_runButton;
    UIControl *_ame414_pauseButton;
    UIControl *_ame414_refreshButton;
    UIControl *_ame414_spinLeftButton;
    UIControl *_ame414_spinRightButton;
    UIControl *_ame414_wardrobeAddButton;
    UIControl *_ame414_avatarButton;
    UIControl *_ame414_downloadButton;
    NSMutableArray<UIControl *> *_ame414_swatchButtons;      // 背景色板三枚
    NSMutableArray<UIView *> *_ame414_swatchDots;            // 色板圆点（选中描边切换）
    UIScrollView *_ame414_wardrobeStrip;                     // 衣柜缩略条
    UIStackView *_ame414_wardrobeStack;                      // 缩略条内容
    NSMutableArray<NSString *> *_ame414_wardrobeEntries;     // 衣柜文件名序
    NSLayoutConstraint *_ame414_wardrobeHeight;              // 衣柜条高（空柜塔缩 38↔0）
    NSTimer *_ame414_toastTimer;
    BOOL _ame414_walkOn;                                     // 跑步动画开（默认开）
    BOOL _ame414_autoSpin;                                   // 自转开（暂停时停）
    BOOL _ame414_spinLeft;                                   // ← 箭头步进中（顺滑收束）
    CGFloat _ame414_spinTarget;                              // 箭头目标 yaw
    CGFloat _ame414_walkPhase;                               // 摆动相位
    BOOL _ame414_controlsBuilt;
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
        _ame414_walkOn = YES;
        _ame414_autoSpin = YES;
        _ame414_walkPhase = 0.0;
        _ame414_wardrobeEntries = ZL2SkinWardrobeLoad();
        _ame414_swatchButtons = [NSMutableArray array];
        _ame414_swatchDots = [NSMutableArray array];
        self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];   // ★Task414 皮肤站黑场基线（色板可切）
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
        [_ame414_toastTimer invalidate];
        _ame414_toastTimer = nil;
    } else if (_ame413_ticker == nil) {
        _ame413_ticker = [CADisplayLink displayLinkWithTarget:self selector:@selector(ame413_tick)];
        _ame413_lastTick = CACurrentMediaTime();
        [_ame413_ticker addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)dealloc {
    [_ame413_ticker invalidate];
    [_ame414_toastTimer invalidate];
}

#pragma mark 骨架

- (void)ame413_buildStage {
    _ame413_stageView = [[UIView alloc] initWithFrame:CGRectZero];
    _ame413_stageView.backgroundColor = [UIColor clearColor];
    _ame413_stageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame413_stageView];
    [NSLayoutConstraint activateConstraints:@[
        [_ame413_stageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_ame413_stageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
    // 顶锚在 buildChrome 接入顶行（buildStage 先于控件构建，顶行不存在）

    // 透视宿主：sublayerTransform 持 m34（CA 经典 3D 盒体技法，412f 判例）
    //   ★Task414 −1/700 → −1/480：内嵌卡幅面小、弱透视几乎不可辨 = 纸片感
    CATransform3D ame413_persp = CATransform3DIdentity;
    ame413_persp.m34 = -1.0 / 480.0;
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

// ★Task414 皮肤站控件组（顶行 提示+跑步/暂停/刷新；底行 色板+箭头；
//   动作行 衣柜/设为头像/下载；衣柜缩略条）
- (void)ame413_buildChrome {
    _ame413_hintLabel = [[UILabel alloc] init];
    _ame413_hintLabel.text = localize(@"ame412.skin.preview.hint", @"拖动旋转 · 捏合缩放");
    _ame413_hintLabel.font = [ZL2Theme fontLabelMedium];   // 12 medium（内嵌卡小字提示）
    _ame413_hintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ame413_hintLabel.textAlignment = NSTextAlignmentLeft;
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

    // ——顶行动作钮（28pt 槽位 20pt 字形，iOS14 零 configuration 判例）——
    _ame414_runButton = [self ame414_iconButtonWithSymbol:@"figure.run" fallback:nil
                                                    label:@"ame414.skin.run"
                                                   block:^{ [self ame414_runTapped]; }];
    _ame414_pauseButton = [self ame414_iconButtonWithSymbol:@"pause.fill" fallback:nil
                                                      label:@"ame414.skin.pause"
                                                     block:^{ [self ame414_pauseTapped]; }];
    _ame414_refreshButton = [self ame414_iconButtonWithSymbol:@"arrow.clockwise" fallback:nil
                                                        label:@"ame414.skin.refresh"
                                                       block:^{ [self ame414_refreshTapped]; }];

    // ——底行：背景色板三枚 + 左右旋转箭头——
    NSArray *ame414_swatchColors = @[
        [UIColor colorWithWhite:0.0 alpha:1.0],
        [UIColor colorWithWhite:0.16 alpha:1.0],
        [UIColor colorWithWhite:0.55 alpha:1.0],
    ];
    for (NSUInteger ame414_i = 0; ame414_i < ame414_swatchColors.count; ame414_i++) {
        ZL2SkinViewTapControl *ame414_swatch = [[ZL2SkinViewTapControl alloc] init];
        ame414_swatch.translatesAutoresizingMaskIntoConstraints = NO;
        ame414_swatch.isAccessibilityElement = YES;
        ame414_swatch.accessibilityLabel = localize(@"ame414.skin.bg", @"预览背景");
        ame414_swatch.layer.cornerRadius = 9.0;
        ame414_swatch.layer.borderWidth = 1.5;
        ame414_swatch.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        ame414_swatch.backgroundColor = ame414_swatchColors[ame414_i];
        UIView *ame414_dot = [[UIView alloc] init];
        ame414_dot.translatesAutoresizingMaskIntoConstraints = NO;
        ame414_dot.userInteractionEnabled = NO;
        ame414_dot.layer.cornerRadius = 3.0;
        ame414_dot.backgroundColor = [ZL2Theme primary];
        ame414_dot.hidden = (ame414_i != 0);   // 默认黑场选中
        [ame414_swatch addSubview:ame414_dot];
        UIColor *ame414_picked = ame414_swatchColors[ame414_i];
        __weak typeof(self) wself = self;
        ame414_swatch.ame414_onTap = ^{ [wself ame414_applySwatch:ame414_picked index:ame414_i]; };
        [self addSubview:ame414_swatch];
        [_ame414_swatchButtons addObject:ame414_swatch];
        [_ame414_swatchDots addObject:ame414_dot];
    }
    _ame414_spinLeftButton = [self ame414_iconButtonWithSymbol:@"chevron.left" fallback:nil
                                                         label:@"ame414.skin.spin.left"
                                                        block:^{ [self ame414_spinLeftTapped]; }];
    _ame414_spinRightButton = [self ame414_iconButtonWithSymbol:@"chevron.right" fallback:nil
                                                          label:@"ame414.skin.spin.right"
                                                         block:^{ [self ame414_spinRightTapped]; }];

    // ——动作行：衣柜 / 设为头像 / 下载——
    _ame414_wardrobeAddButton = [self ame414_iconButtonWithSymbol:@"tshirt" fallback:@"plus.square"
                                                            label:@"ame414.skin.wardrobe.add"
                                                           block:^{ [self ame414_wardrobeAddTapped]; }];
    _ame414_avatarButton = [self ame414_iconButtonWithSymbol:@"person.crop.circle" fallback:@"person.circle"
                                                       label:@"ame414.skin.avatar.set"
                                                      block:^{ [self ame414_avatarTapped]; }];
    _ame414_downloadButton = [self ame414_iconButtonWithSymbol:@"square.and.arrow.down" fallback:@"arrow.down.circle"
                                                         label:@"ame414.skin.download"
                                                        block:^{ [self ame414_downloadTapped]; }];

    // ——衣柜缩略条（横向滚动；点按即穿 / 长按移除）——
    _ame414_wardrobeStrip = [[UIScrollView alloc] init];
    _ame414_wardrobeStrip.showsHorizontalScrollIndicator = NO;
    _ame414_wardrobeStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame414_wardrobeStrip];
    _ame414_wardrobeHeight = [_ame414_wardrobeStrip.heightAnchor constraintEqualToConstant:38.0];
    _ame414_wardrobeHeight.active = YES;
    _ame414_wardrobeStack = [[UIStackView alloc] init];
    _ame414_wardrobeStack.axis = UILayoutConstraintAxisHorizontal;
    _ame414_wardrobeStack.spacing = 6.0;
    _ame414_wardrobeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame414_wardrobeStrip addSubview:_ame414_wardrobeStack];
    [NSLayoutConstraint activateConstraints:@[
        [_ame414_wardrobeStack.topAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.topAnchor],
        [_ame414_wardrobeStack.bottomAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.bottomAnchor],
        [_ame414_wardrobeStack.leadingAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.leadingAnchor],
        [_ame414_wardrobeStrip.contentLayoutGuide.trailingAnchor constraintEqualToAnchor:_ame414_wardrobeStack.trailingAnchor],
        [_ame414_wardrobeStack.heightAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.heightAnchor],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        // 顶行：提示语左 / 三动作钮右
        [_ame413_hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame413_hintLabel.centerYAnchor constraintEqualToAnchor:_ame414_refreshButton.centerYAnchor],
        [_ame413_hintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_ame414_runButton.leadingAnchor constant:-4.0],
        [_ame414_refreshButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [_ame414_pauseButton.trailingAnchor constraintEqualToAnchor:_ame414_refreshButton.leadingAnchor constant:-4.0],
        [_ame414_runButton.trailingAnchor constraintEqualToAnchor:_ame414_pauseButton.leadingAnchor constant:-4.0],
        [_ame414_runButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:6.0],

        // 舞台：顶行之下 / 衣柜条之上（顶锚在此接入顶行）
        [_ame413_stageView.topAnchor constraintEqualToAnchor:_ame414_runButton.bottomAnchor constant:2.0],
        [_ame413_stageView.bottomAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.topAnchor constant:-4.0],

        // 衣柜条（空柜塌缩零占位：高度常量持引用 38↔0）
        [_ame414_wardrobeStrip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame414_wardrobeStrip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],

        // 底行：色板左 / 箭头右
        [_ame414_spinRightButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [_ame414_spinLeftButton.trailingAnchor constraintEqualToAnchor:_ame414_spinRightButton.leadingAnchor constant:-4.0],
        [_ame414_spinLeftButton.topAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.bottomAnchor constant:4.0],
        [_ame414_swatchButtons[2].trailingAnchor constraintEqualToAnchor:_ame414_spinLeftButton.leadingAnchor constant:-8.0],
        [_ame414_swatchButtons[1].trailingAnchor constraintEqualToAnchor:_ame414_swatchButtons[2].leadingAnchor constant:-6.0],
        [_ame414_swatchButtons[0].trailingAnchor constraintEqualToAnchor:_ame414_swatchButtons[1].leadingAnchor constant:-6.0],
        [_ame414_swatchButtons[0].leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:10.0],

        // 动作行：衣柜/头像/下载 左对齐排布，贴底
        [_ame414_downloadButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame414_avatarButton.leadingAnchor constraintEqualToAnchor:_ame414_downloadButton.trailingAnchor constant:14.0],
        [_ame414_wardrobeAddButton.leadingAnchor constraintEqualToAnchor:_ame414_avatarButton.trailingAnchor constant:14.0],
        [_ame414_wardrobeAddButton.topAnchor constraintEqualToAnchor:_ame414_spinLeftButton.bottomAnchor constant:4.0],
        [_ame414_wardrobeAddButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6.0],
        [_ame414_spinRightButton.centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[0].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[1].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[2].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],

        // 状态/加载指示居中于舞台
        [_ame413_statusLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_ame413_statusLabel.centerYAnchor constraintEqualToAnchor:_ame413_stageView.centerYAnchor],
        [_ame413_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:12.0],
        [_ame413_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12.0],
        [_ame413_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_ame413_spinner.centerYAnchor constraintEqualToAnchor:_ame413_stageView.centerYAnchor],
    ]];
    // 色板圆点居中 + 尺寸（构建期一次性）
    for (NSUInteger ame414_i = 0; ame414_i < _ame414_swatchButtons.count; ame414_i++) {
        UIControl *ame414_swatch = _ame414_swatchButtons[ame414_i];
        UIView *ame414_dot = _ame414_swatchDots[ame414_i];
        [NSLayoutConstraint activateConstraints:@[
            [ame414_swatch.widthAnchor constraintEqualToConstant:18.0],
            [ame414_swatch.heightAnchor constraintEqualToConstant:18.0],
            [ame414_dot.centerXAnchor constraintEqualToAnchor:ame414_swatch.centerXAnchor],
            [ame414_dot.centerYAnchor constraintEqualToAnchor:ame414_swatch.centerYAnchor],
            [ame414_dot.widthAnchor constraintEqualToConstant:6.0],
            [ame414_dot.heightAnchor constraintEqualToConstant:6.0],
        ]];
    }
    _ame414_controlsBuilt = YES;
    [self ame414_syncWalkButtons];
    [self ame414_rebuildWardrobeStrip];
}

// 28pt 槽位图标钮（ZL2ShellIconButton 同款形态：UIImageView 模板渲染 +
// ZL2SkinViewTapControl block 载荷，零 UIButton.Configuration——iOS 14 红线）
- (UIControl *)ame414_iconButtonWithSymbol:(NSString *)symbol
                                  fallback:(NSString *)fallback
                                     label:(NSString *)labelKey
                                     block:(void (^)(void))block {
    ZL2SkinViewTapControl *ame414_btn = [[ZL2SkinViewTapControl alloc] init];
    ame414_btn.translatesAutoresizingMaskIntoConstraints = NO;
    ame414_btn.isAccessibilityElement = YES;
    ame414_btn.accessibilityTraits = UIAccessibilityTraitButton;
    ame414_btn.accessibilityLabel = localize(labelKey, @"");
    ame414_btn.ame414_onTap = block;
    UIImage *ame414_img = [UIImage systemImageNamed:symbol];
    if (!ame414_img && fallback.length > 0) ame414_img = [UIImage systemImageNamed:fallback];
    if (ame414_img) {
        ame414_img = [ame414_img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *ame414_icon = [[UIImageView alloc] initWithImage:ame414_img];
        ame414_icon.tintColor = [ZL2Theme onSurfaceVariant];
        ame414_icon.contentMode = UIViewContentModeScaleAspectFit;
        ame414_icon.translatesAutoresizingMaskIntoConstraints = NO;
        ame414_icon.userInteractionEnabled = NO;
        [ame414_btn addSubview:ame414_icon];
        [NSLayoutConstraint activateConstraints:@[
            [ame414_icon.centerXAnchor constraintEqualToAnchor:ame414_btn.centerXAnchor],
            [ame414_icon.centerYAnchor constraintEqualToAnchor:ame414_btn.centerYAnchor],
            [ame414_icon.widthAnchor constraintEqualToConstant:20.0],
            [ame414_icon.heightAnchor constraintEqualToConstant:20.0],
        ]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [ame414_btn.widthAnchor constraintEqualToConstant:28.0],
        [ame414_btn.heightAnchor constraintEqualToConstant:28.0],
    ]];
    [self addSubview:ame414_btn];
    return ame414_btn;
}

// 跑步/暂停按钮选中态着色（run 开 = primary 字形；pause 开 = primary 字形）
- (void)ame414_syncWalkButtons {
    if (!_ame414_controlsBuilt) return;
    [_ame414_runButton.subviews enumerateObjectsUsingBlock:^(__kindof UIView *obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[UIImageView class]]) obj.tintColor = _ame414_walkOn ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    }];
    [_ame414_pauseButton.subviews enumerateObjectsUsingBlock:^(__kindof UIView *obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[UIImageView class]]) obj.tintColor = _ame414_walkOn ? [ZL2Theme onSurfaceVariant] : [ZL2Theme primary];
    }];
}

// 操作回执（statusLabel 2 秒自熄，零新增弹层依赖）
- (void)ame414_toast:(NSString *)message {
    _ame413_statusLabel.text = message;
    _ame413_statusLabel.hidden = NO;
    [_ame414_toastTimer invalidate];
    __weak typeof(self) wself = self;
    _ame414_toastTimer = [NSTimer timerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *timer) {
        [wself ame414_toastFade];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_ame414_toastTimer forMode:NSRunLoopCommonModes];
}

- (void)ame414_toastFade {
    _ame413_statusLabel.hidden = YES;
    _ame413_statusLabel.text = nil;
}

#pragma mark 皮肤站动作（★Task414）

- (void)ame414_runTapped {
    _ame414_walkOn = YES;
    _ame414_autoSpin = YES;
    [self ame414_syncWalkButtons];
}

- (void)ame414_pauseTapped {
    _ame414_walkOn = NO;
    _ame414_autoSpin = NO;
    [self ame414_syncWalkButtons];
}

// 刷新 = 绕过两级磁盘缓存直取网络重拉（yggdrasil 签名 URL / crafatar / minotar）
- (void)ame414_refreshTapped {
    _ame414_refreshBypass = YES;
    NSString *ame414_cachePath = [[ZL2SkinViewCacheDir()
        stringByAppendingPathComponent:ZL2SkinViewSafeName(_ame414_lastAccountId ?: _ame414_lastUsername ?: @"anonymous")]
        stringByAppendingPathExtension:@"png"];
    [[NSFileManager defaultManager] removeItemAtPath:ame414_cachePath error:nil];
    [self ame413_loadSkinWithAccountId:_ame414_lastAccountId
                              profileId:_ame414_lastProfileId
                               username:_ame414_lastUsername
                             authserver:_ame414_lastAuthserver];
}

- (void)ame414_spinLeftTapped {
    _ame414_spinTarget -= M_PI / 6.0;   // 30° 步进
    _ame414_spinLeft = YES;
}

- (void)ame414_spinRightTapped {
    _ame414_spinTarget += M_PI / 6.0;
    _ame414_spinLeft = NO;
}

- (void)ame414_applySwatch:(UIColor *)color index:(NSUInteger)idx {
    self.backgroundColor = color;
    [_ame414_swatchDots enumerateObjectsUsingBlock:^(UIView *obj, NSUInteger i, BOOL *stop) {
        obj.hidden = (i != idx);
    }];
}

// 添加至衣柜：当前皮肤 PNG 落柜 + 缩略条刷新
- (void)ame414_wardrobeAddTapped {
    if (!_ame413_currentSkin) {
        [self ame414_toast:localize(@"ame414.skin.download.none", @"还没有可保存的皮肤")];
        return;
    }
    NSData *ame414_png = UIImagePNGRepresentation(_ame413_currentSkin);
    if (ame414_png.length == 0) return;
    NSString *ame414_file = [[NSUUID UUID] UUIDString];
    NSString *ame414_path = [[ZL2SkinWardrobeDir() stringByAppendingPathComponent:ame414_file]
        stringByAppendingPathExtension:@"png"];
    [ame414_png writeToFile:ame414_path atomically:YES];
    [_ame414_wardrobeEntries addObject:ame414_file];
    ZL2SkinWardrobeSave(_ame414_wardrobeEntries);
    [self ame414_rebuildWardrobeStrip];
    [self ame414_toast:localize(@"ame414.skin.wardrobe.added", @"已加入衣柜")];
}

// 设为头像：头部前脸 8×8 → AvatarManager 既有链首位（Documents/avatars/<account>.png）
- (void)ame414_avatarTapped {
    if (!_ame413_currentSkin) {
        [self ame414_toast:localize(@"ame414.skin.download.none", @"还没有可保存的皮肤")];
        return;
    }
    UIImage *ame414_avatar = ZL2SkinViewHeadAvatarImage(_ame413_currentSkin);
    NSString *ame414_name = _ame414_lastUsername;
    if (!ame414_avatar || ame414_name.length == 0) return;
    __weak typeof(self) wself = self;
    [[AvatarManager sharedManager] saveAvatarForAccount:ame414_name
                                                  image:ame414_avatar
                                         withCompletion:^(BOOL ok, NSError *error) {
        // 回调线程不定 → 主线程回执（弱捕获在外层，块内强提升）
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) strongSelf = wself;
            if (!strongSelf) return;
            [strongSelf ame414_toast:localize(@"ame414.skin.avatar.done", @"头像已更新")];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2AccountsReloadAvatar" object:nil];
        });
    }];
}

// 下载：皮肤 PNG 系统分享面板（iPad 锚定按钮防 popover 崩）
- (void)ame414_downloadTapped {
    NSString *ame414_src = [[ZL2SkinViewCacheDir()
        stringByAppendingPathComponent:ZL2SkinViewSafeName(_ame414_lastAccountId ?: _ame414_lastUsername ?: @"anonymous")]
        stringByAppendingPathExtension:@"png"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ame414_src] || !_ame413_currentSkin) {
        [self ame414_toast:localize(@"ame414.skin.download.none", @"还没有可保存的皮肤")];
        return;
    }
    NSURL *ame414_url = [NSURL fileURLWithPath:ame414_src];
    UIActivityViewController *ame414_sheet =
        [[UIActivityViewController alloc] initWithActivityItems:@[ame414_url]
                                          applicationActivities:nil];
    UIViewController *ame414_anchor = self;
    while (ame414_anchor.parentViewController) ame414_anchor = ame414_anchor.parentViewController;
    ame414_sheet.modalPresentationStyle = UIModalPresentationPopover;
    ame414_sheet.popoverPresentationController.sourceView = _ame414_downloadButton;
    ame414_sheet.popoverPresentationController.sourceRect = _ame414_downloadButton.bounds;
    [ame414_anchor presentViewController:ame414_sheet animated:YES completion:nil];
}

// 衣柜缩略条重建（点按即穿 / 长按移除；block 载荷零 viewWithTag 判例）
- (void)ame414_rebuildWardrobeStrip {
    for (UIView *ame414_sub in [_ame414_wardrobeStack.arrangedSubviews copy]) {
        [_ame414_wardrobeStack removeArrangedSubview:ame414_sub];
        [ame414_sub removeFromSuperview];
    }
    __weak typeof(self) wself = self;
    for (NSString *ame414_file in _ame414_wardrobeEntries) {
        NSString *ame414_path = [[ZL2SkinWardrobeDir() stringByAppendingPathComponent:ame414_file]
            stringByAppendingPathExtension:@"png"];
        UIImage *ame414_thumb = [UIImage imageWithContentsOfFile:ame414_path];
        if (!ame414_thumb) continue;
        ZL2SkinViewTapControl *ame414_btn = [[ZL2SkinViewTapControl alloc] init];
        ame414_btn.translatesAutoresizingMaskIntoConstraints = NO;
        ame414_btn.isAccessibilityElement = YES;
        ame414_btn.accessibilityLabel = localize(@"ame414.skin.wardrobe", @"衣柜");
        ame414_btn.layer.cornerRadius = 4.0;
        ame414_btn.layer.borderWidth = 1.0;
        ame414_btn.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        ame414_btn.layer.masksToBounds = YES;
        UIImageView *ame414_iv = [[UIImageView alloc] initWithImage:ame414_thumb];
        ame414_iv.contentMode = UIViewContentModeScaleAspectFit;
        ame414_iv.translatesAutoresizingMaskIntoConstraints = NO;
        ame414_iv.userInteractionEnabled = NO;
        [ame414_btn addSubview:ame414_iv];
        [NSLayoutConstraint activateConstraints:@[
            [ame414_btn.widthAnchor constraintEqualToConstant:30.0],
            [ame414_btn.heightAnchor constraintEqualToConstant:30.0],
            [ame414_iv.topAnchor constraintEqualToAnchor:ame414_btn.topAnchor constant:2.0],
            [ame414_iv.bottomAnchor constraintEqualToAnchor:ame414_btn.bottomAnchor constant:-2.0],
            [ame414_iv.leadingAnchor constraintEqualToAnchor:ame414_btn.leadingAnchor constant:2.0],
            [ame414_iv.trailingAnchor constraintEqualToAnchor:ame414_btn.trailingAnchor constant:-2.0],
        ]];
        NSString *ame414_captured = [ame414_file copy];
        ame414_btn.ame414_onTap = ^{
            __strong typeof(wself) strongSelf = wself;
            [strongSelf ame414_wearWardrobeFile:ame414_captured];
        };
        ame414_btn.ame414_onLongPress = ^{
            __strong typeof(wself) strongSelf = wself;
            [strongSelf ame414_removeWardrobeFile:ame414_captured];
        };
        [_ame414_wardrobeStack addArrangedSubview:ame414_btn];
    }
    BOOL ame414_empty = (_ame414_wardrobeStack.arrangedSubviews.count == 0);
    _ame414_wardrobeStrip.hidden = ame414_empty;
    _ame414_wardrobeHeight.constant = ame414_empty ? 0.0 : 38.0;
}

// 衣柜缩略条点按 = 即穿（应用该皮肤重建模型）
- (void)ame414_wearWardrobeFile:(NSString *)ame414_file {
    if (ame414_file.length == 0) return;
    NSString *ame414_path = [[ZL2SkinWardrobeDir() stringByAppendingPathComponent:ame414_file]
        stringByAppendingPathExtension:@"png"];
    UIImage *ame414_skin = [UIImage imageWithContentsOfFile:ame414_path];
    if (ame414_skin.size.width >= 64) [self ame413_applySkin:ame414_skin];
}

// 衣柜缩略条长按 = 移除（零确认弹层：衣柜本机可随时重加）
- (void)ame414_removeWardrobeFile:(NSString *)ame414_file {
    if (ame414_file.length == 0) return;
    [_ame414_wardrobeEntries removeObject:ame414_file];
    ZL2SkinWardrobeSave(_ame414_wardrobeEntries);
    NSString *ame414_path = [[ZL2SkinWardrobeDir() stringByAppendingPathComponent:ame414_file]
        stringByAppendingPathExtension:@"png"];
    [[NSFileManager defaultManager] removeItemAtPath:ame414_path error:nil];
    [self ame414_rebuildWardrobeStrip];
    [self ame414_toast:localize(@"ame414.skin.wardrobe.removed", @"已移出衣柜")];
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
    if ([ame413_key isEqualToString:_ame413_accountKey] && !_ame414_refreshBypass) return;   // 幂等闸
    _ame413_accountKey = [ame413_key copy];
    _ame413_authData = [authData isKindOfClass:[NSDictionary class]] ? authData : nil;
    _ame413_slimModel = NO;
    _ame414_lastAccountId = ame413_accountId;
    _ame414_lastProfileId = ame413_pid;
    _ame414_lastUsername = ame413_name;
    _ame414_lastAuthserver = ame413_server;
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

    // ① 预览缓存（本视图历史命中；刷新键 bypass）
    if (!_ame414_refreshBypass) {
        UIImage *ame413_cached = [UIImage imageWithContentsOfFile:ame413_cachePath];
        if (ame413_cached) {
            _ame414_refreshBypass = NO;
            [self ame413_applySkin:ame413_cached];
            return;
        }
        // ② skinfull 全皮（ame133 链落盘的原始皮肤 = 离线真皮）
        NSString *ame413_fullPath = ZL2SkinViewFullSkinPath(accountId);
        if (ame413_fullPath) {
            UIImage *ame413_full = [UIImage imageWithContentsOfFile:ame413_fullPath];
            if (ame413_full.size.width >= 64) {
                _ame414_refreshBypass = NO;
                [self ame413_applySkin:ame413_full];
                return;
            }
        }
    }
    _ame414_refreshBypass = NO;

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
    _ame414_spinTarget = _ame413_yaw;   // 手拖即接管箭头目标
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
    BOOL ame414_dirty = NO;
    // ★Task414 跑步相位（暂停时冻结）
    if (_ame414_walkOn) {
        _ame414_walkPhase += ame413_dt * 4.8;   // rad/s（跑步节奏）
        ame414_dirty = YES;
    }
    // ★Task414 箭头步进收束（左/右 30°，0.12 收敛系数）+ 自转
    CGFloat ame414_delta = _ame414_spinTarget - _ame413_yaw;
    if (fabs(ame414_delta) > 0.002) {
        _ame413_yaw += ame414_delta * fmin(1.0, ame413_dt * 12.0);
        ame414_dirty = YES;
    } else if (_ame414_autoSpin) {
        _ame413_yaw += ame413_dt * 0.35;   // 慢速自转（rad/s）
        _ame414_spinTarget = _ame413_yaw;
        ame414_dirty = YES;
    }
    if (ame414_dirty) [self ame413_updateModelTransform];
}

// 模型层每帧 transform = RotX(pitch)·RotY(yaw)·Scale(user)；
// ★Task414 逐帧面级三更新：肢体摆动重摆（枢轴 RotX）+ zPosition 深度排序
// （兄弟层声明序合成 → 深度序 = 纸片穿模根修）+ 光影罩（法线×光向点积）
- (void)ame413_updateModelTransform {
    CGFloat ame413_s = _ame413_userScale;
    CATransform3D ame413_t = CATransform3DMakeRotation(_ame413_pitch, 1.0, 0.0, 0.0);
    ame413_t = CATransform3DRotate(ame413_t, _ame413_yaw, 0.0, 1.0, 0.0);
    ame413_t = CATransform3DScale(ame413_t, ame413_s, ame413_s, ame413_s);
    _ame413_stageView.layer.transform = ame413_t;

    CGFloat ame414_cp = cos(_ame413_pitch), ame414_sp = sin(_ame413_pitch);
    CGFloat ame414_cw = cos(_ame413_yaw), ame414_sw = sin(_ame413_yaw);
    CGFloat ame414_swing = _ame414_walkOn ? (0.55 * sin(_ame414_walkPhase)) : 0.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (ZL2SkinViewFace *ame414_f in _ame413_faceLayers) {
        CGFloat ame414_th = ame414_swing * ame414_f.swingSign;
        CATransform3D ame414_ft = ame414_f.ame_baseT;
        // ——肢体摆动：枢轴 RotX（层空间 X 轴）——
        CGFloat ame414_x = ame414_f.cx, ame414_y = ame414_f.cy, ame414_z = ame414_f.cz;
        CGFloat ame414_ct = 1.0, ame414_st = 0.0;
        if (ame414_th != 0.0) {
            ame414_ct = cos(ame414_th); ame414_st = sin(ame414_th);
            CATransform3D ame414_rot = CATransform3DMakeRotation(ame414_th, 1.0, 0.0, 0.0);
            CATransform3D ame414_tp = CATransform3DMakeTranslation(ame414_f.px, ame414_f.py, ame414_f.pz);
            CATransform3D ame414_tn = CATransform3DMakeTranslation(-ame414_f.px, -ame414_f.py, -ame414_f.pz);
            ame414_ft = CATransform3DConcat(ame414_tp, ame414_rot);
            ame414_ft = CATransform3DConcat(ame414_ft, ame414_tn);
            ame414_ft = CATransform3DConcat(ame414_ft, ame414_f.ame_baseT);
            // 面中心随摆（RotX：y/z 旋 x 不动）
            CGFloat ame414_dy = ame414_y - ame414_f.py;
            CGFloat ame414_dz = ame414_z - ame414_f.pz;
            ame414_y = ame414_f.py + ame414_dy * ame414_ct - ame414_dz * ame414_st;
            ame414_z = ame414_f.pz + ame414_dy * ame414_st + ame414_dz * ame414_ct;
        }
        ame414_f.layer.transform = ame414_ft;
        // ——深度：yaw 先（M = RotX·RotY）→ pitch → z（兄弟层遮挡序）——
        CGFloat ame414_x1 = ame414_x * ame414_cw + ame414_z * ame414_sw;
        CGFloat ame414_z1 = -ame414_x * ame414_sw + ame414_z * ame414_cw;
        CGFloat ame414_y2 = ame414_y * ame414_cp - ame414_z1 * ame414_sp;
        CGFloat ame414_z2 = ame414_y * ame414_sp + ame414_z1 * ame414_cp;
        ame414_f.layer.zPosition = ame414_z2 + (CGFloat)ame414_f.swingSign * 0.5 + 100.0;
        // ——光影：法线随摆随旋 → 光向点积 → 罩透明度——
        CGFloat ame414_nx = ame414_f.nx, ame414_ny = ame414_f.ny, ame414_nz = ame414_f.nz;
        if (ame414_th != 0.0) {
            CGFloat ame414_ny1 = ame414_ny * ame414_ct - ame414_nz * ame414_st;
            ame414_nz = ame414_ny * ame414_st + ame414_nz * ame414_ct;
            ame414_ny = ame414_ny1;
        }
        CGFloat ame414_nx1 = ame414_nx * ame414_cw + ame414_nz * ame414_sw;
        CGFloat ame414_nz1 = -ame414_nx * ame414_sw + ame414_nz * ame414_cw;
        CGFloat ame414_ny2 = ame414_ny * ame414_cp - ame414_nz1 * ame414_sp;
        CGFloat ame414_nz2 = ame414_ny * ame414_sp + ame414_nz1 * ame414_cp;
        CGFloat ame414_len = sqrt(ame414_nx1 * ame414_nx1 + ame414_ny2 * ame414_ny2 + ame414_nz2 * ame414_nz2);
        if (ame414_len < 0.0001) ame414_len = 1.0;
        CGFloat ame414_dot = (ame414_nx1 * AME414_LIGHT_X + ame414_ny2 * AME414_LIGHT_Y + ame414_nz2 * AME414_LIGHT_Z) / ame414_len;
        CGFloat ame414_shade = 0.44 + 0.58 * fmax(0.0, ame414_dot);
        if (ame414_shade > 1.0) ame414_shade = 1.0;
        ame414_f.shade.opacity = (1.0 - ame414_shade) * 0.85;
    }
    [CATransaction commit];
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
        ame413_face.layer.position = ame413_center;
    }
}

#pragma mark 盒体组装（36 面 + 逐面记录/光影罩）

// 单盒六面（面序 [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]）。
// ★Task413 坐标翻转核心：层空间 +Y 向下（屏幕），模型空间 +Y 向上——
// 盒心 y_l = −(y_m − 16)；顶面（模型 +Y）offY = −h/2、rotX = +π/2（法线
// (0,0,1)→(0,−1,0) = 朝屏上），底面反号。横向不变（+X 右、+Z 朝观者）。
// 逐面横轴向（与展开图接缝核对）：前=恒等、后=rotY(π)（纹理左右镜像 =
// 背视正确）、右(−X)=rotY(−π/2)（局部 +X→+Z 前缘 = 右脸区右缘 ✓）、
// 左(+X)=rotY(+π/2)（局部 −X→+Z 前缘 = 左脸区左缘 ✓）。
// ★Task414 追加：每面记录（层空间中心/法线/枢轴/基准变换）+ 黑色光影罩
// 子层，供逐帧深度排序 / 光影 / 肢体摆动复算。
static void ZL2SkinViewBuildBox(CALayer *ame413_parent,
                                CGPoint ame413_center,
                                ZL2SkinViewBox ame413_box,
                                CGFloat ame413_unit,
                                UIImage *ame413_skin,
                                NSInteger ame414_partIndex,
                                CGFloat ame414_pivotYModel,
                                CGFloat ame414_swingSign,
                                NSMutableArray<ZL2SkinViewFace *> *ame414_out) {
    CGFloat ame413_x = ame413_box.cx;
    CGFloat ame413_y = -(ame413_box.cy - 16.0);   // ★Task413 Y 翻转（模型 0..32 → 层 −16..16 头朝上）
    CGFloat ame413_z = ame413_box.cz;
    // ★Task414 肢体枢轴（层空间 pt）：肩/髋模型 Y → 层 Y
    CGFloat ame414_pivotX = (ame413_box.cx) * ame413_unit;
    CGFloat ame414_pivotY = -(ame414_pivotYModel - 16.0) * ame413_unit;
    CGFloat ame414_pivotZ = (ame413_box.cz) * ame413_unit;
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        CGFloat ame413_offX = 0, ame413_offY = 0, ame413_offZ = 0;
        CGFloat ame413_rotY = 0, ame413_rotX = 0;
        CGFloat ame413_fw = 0, ame413_fh = 0;
        CGFloat ame413_nx = 0, ame413_ny = 0, ame413_nz = 0;   // ★Task414 层空间法线
        switch (ame413_i) {
            case 0:   // 前：面朝 +Z，z + d/2
                ame413_offZ = ame413_box.d / 2.0; ame413_fw = ame413_box.w; ame413_fh = ame413_box.h;
                ame413_nx = 0; ame413_ny = 0; ame413_nz = 1;
                break;
            case 1: { // 后：RotY(π)，z − d/2
                ame413_offZ = -ame413_box.d / 2.0; ame413_rotY = (CGFloat)M_PI;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.h;
                ame413_nx = 0; ame413_ny = 0; ame413_nz = -1;
                break;
            }
            case 2: { // 右（角色右 = −X 侧）：x − w/2
                ame413_offX = -ame413_box.w / 2.0; ame413_rotY = -(CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.d; ame413_fh = ame413_box.h;
                ame413_nx = -1; ame413_ny = 0; ame413_nz = 0;
                break;
            }
            case 3: { // 左（角色左 = +X 侧）：x + w/2
                ame413_offX = ame413_box.w / 2.0; ame413_rotY = (CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.d; ame413_fh = ame413_box.h;
                ame413_nx = 1; ame413_ny = 0; ame413_nz = 0;
                break;
            }
            case 4: { // 上（模型 +Y = 屏上）：y − h/2，rotX(+π/2)
                ame413_offY = -ame413_box.h / 2.0; ame413_rotX = (CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.d;
                ame413_nx = 0; ame413_ny = -1; ame413_nz = 0;
                break;
            }
            default: { // 下（模型 −Y = 屏下）：y + h/2，rotX(−π/2)
                ame413_offY = ame413_box.h / 2.0; ame413_rotX = -(CGFloat)M_PI / 2.0;
                ame413_fw = ame413_box.w; ame413_fh = ame413_box.d;
                ame413_nx = 0; ame413_ny = 1; ame413_nz = 0;
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
        // ★Task414 光影罩（面内容之上，opacity 逐帧 = 1−shade）
        CALayer *ame414_shade = [CALayer layer];
        ame414_shade.frame = ame413_face.bounds;
        ame414_shade.backgroundColor = [UIColor blackColor].CGColor;
        ame414_shade.opacity = 0.0;
        ame414_shade.userInteractionEnabled = NO;
        [ame413_face addSublayer:ame414_shade];

        CATransform3D ame413_t = CATransform3DMakeTranslation((ame413_x + ame413_offX) * ame413_unit,
                                                              (ame413_y + ame413_offY) * ame413_unit,
                                                              (ame413_z + ame413_offZ) * ame413_unit);
        if (ame413_rotY != 0.0) ame413_t = CATransform3DRotate(ame413_t, ame413_rotY, 0.0, 1.0, 0.0);
        if (ame413_rotX != 0.0) ame413_t = CATransform3DRotate(ame413_t, ame413_rotX, 1.0, 0.0, 0.0);
        ame413_face.transform = ame413_t;
        [ame413_parent addSublayer:ame413_face];

        // ★Task414 面记录（层空间静态基准；枢轴 = 肢体肩/髋，非肢体 = 面自身中心）
        ZL2SkinViewFace *ame414_rec = [[ZL2SkinViewFace alloc] init];
        ame414_rec.layer = ame413_face;
        ame414_rec.shade = ame414_shade;
        ame414_rec.ame_baseT = ame413_t;
        ame414_rec.cx = (ame413_x + ame413_offX) * ame413_unit;
        ame414_rec.cy = (ame413_y + ame413_offY) * ame413_unit;
        ame414_rec.cz = (ame413_z + ame413_offZ) * ame413_unit;
        ame414_rec.nx = ame413_nx;
        ame414_rec.ny = ame413_ny;
        ame414_rec.nz = ame413_nz;
        if (ame414_swingSign != 0.0) {
            ame414_rec.px = ame414_pivotX;
            ame414_rec.py = ame414_pivotY;
            ame414_rec.pz = ame414_pivotZ;
        } else {
            ame414_rec.px = ame414_rec.cx;
            ame414_rec.py = ame414_rec.cy;
            ame414_rec.pz = ame414_rec.cz;
        }
        ame414_rec.swingSign = ame414_swingSign;
        [ame414_out addObject:ame414_rec];
    }
}

// 用皮肤整组建模（skin = nil 时灰盒占位；每次整组拆建零残留）
// ★Task414 部件枢轴：臂枢轴 = 肩（模型 y=22）、腿枢轴 = 髋（模型 y=12）；
// 摆动方向 = 右臂 +1 / 左臂 −1 / 右腿 −1 / 左腿 +1（同侧臂腿反相）。
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
        ZL2SkinViewBuildBox(ame413_stage, ame413_center, ame413_box, ame413_unit, nil,
                            0, 16.0, 0.0, _ame413_faceLayers);
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
    CGFloat ame414_pivots[6] = {22.0, 18.0, 22.0, 22.0, 12.0, 12.0};   // 肩/髋枢轴模型 Y
    CGFloat ame414_signs[6] = {0.0, 0.0, 1.0, -1.0, -1.0, 1.0};        // 摆动方向（同侧臂腿反相）
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        ZL2SkinViewBuildBox(ame413_stage, ame413_center, ame413_boxes[ame413_i], ame413_unit, skin,
                            ame413_i, ame414_pivots[ame413_i], ame414_signs[ame413_i], _ame413_faceLayers);
    }
    [self ame413_updateModelTransform];
}

@end
