//
// ZL2SkinPreviewViewController.m — ★ Task412 账户页皮肤 3D 预览实现（设计
// 契约见 .h 头注释；第 20 轮复诉⑥）
//
// ★ 渲染管线（纯 CALayer，零 SceneKit——iPhoneOS 26.2 SDK 头分叉规避判例）：
//   场景层（容器 layer）持 sublayerTransform = 透视矩阵（m34 = −1/700）；
//   模型层 transform 每帧 = RotX(pitch)·RotY(yaw)·Scale(s·S)；六盒体 36 面
//   为静态子层（transform = 平移(盒心·S)·面向旋转；position = 容器中心），
//   contents = 皮肤对应区块裁贴 CGImage（顶左原点），isDoubleSided = NO =
//   背面自动剔除。CADisplayLink 帧驱动自转；拖轨/捏合改 yaw/pitch/scale。
//

#import "ZL2SkinPreviewViewController.h"
#import "ZL2Theme.h"
#import "utils.h"   // localize()

#import <math.h>

// 皮肤缓存目录（Library/Caches/skins）
static NSString *ZL2SkinPreviewCacheDir(void) {
    static NSString *ame412_dir;
    static dispatch_once_t ame412_once;
    dispatch_once(&ame412_once, ^{
        NSArray *ame412_paths = [[NSFileManager defaultManager]
            URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
        ame412_dir = [[ame412_paths.firstObject path]
            stringByAppendingPathComponent:@"skins"];
        [[NSFileManager defaultManager] createDirectoryAtPath:ame412_dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return ame412_dir;
}

// 账户名转安全文件名（AvatarManager 判例同款：防路径穿越）
static NSString *ZL2SkinPreviewSafeName(NSString *name) {
    if (name.length == 0) return @"anonymous";
    NSCharacterSet *ame412_invalid =
        [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *ame412_parts = [name componentsSeparatedByCharactersInSet:ame412_invalid];
    NSString *ame412_cleaned = [ame412_parts componentsJoinedByString:@"_"];
    return (ame412_cleaned.length > 0) ? ame412_cleaned : @"anonymous";
}

#pragma mark - 皮肤 UV 区块表

typedef struct {
    CGFloat x, y, w, h;
} ZL2SkinPreviewRect;

// 皮肤侧区块按「角色右/左」命名；面表序 = [前 后 左 右 上 下]（与下方
// ZL2SkinPreviewBuildBox 的六面构建序一致）。64×64 标准布局（原点左上）：
//   头 8³：前(8,8,8,8) 后(24,8,8,8) 左(16,8,8,8) 右(0,8,8,8) 上(8,0,8,8) 下(16,0,8,8)
//   身 8×12×4：前(20,20,8,12) 后(32,20,8,12) 左(28,20,4,12) 右(16,20,4,12) 上(20,16,8,4) 下(28,16,8,4)
//   右臂 4×12×4：前(44,20) 后(52,20) 左(48,20) 右(40,20) 上(44,16) 下(48,16)
//   左臂 4×12×4：前(36,52) 后(44,52) 左(40,52) 右(32,52) 上(36,48) 下(40,48)
//   右腿 4×12×4：前(4,20) 后(12,20) 左(8,20) 右(0,20) 上(4,16) 下(8,16)
//   左腿 4×12×4：前(20,52) 后(28,52) 左(24,52) 右(16,52) 上(20,48) 下(24,48)
// 64×32 旧版：左臂/左腿整组镜像右臂/右腿区块（ame412_legacy 分支）。
static const ZL2SkinPreviewRect ZL2SkinPreviewHeadFaces[6] = {
    {8, 8, 8, 8}, {24, 8, 8, 8}, {16, 8, 8, 8}, {0, 8, 8, 8}, {8, 0, 8, 8}, {16, 0, 8, 8}};
static const ZL2SkinPreviewRect ZL2SkinPreviewBodyFaces[6] = {
    {20, 20, 8, 12}, {32, 20, 8, 12}, {28, 20, 4, 12}, {16, 20, 4, 12}, {20, 16, 8, 4}, {28, 16, 8, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewRArmFaces[6] = {
    {44, 20, 4, 12}, {52, 20, 4, 12}, {48, 20, 4, 12}, {40, 20, 4, 12}, {44, 16, 4, 4}, {48, 16, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewLArmFaces[6] = {
    {36, 52, 4, 12}, {44, 52, 4, 12}, {40, 52, 4, 12}, {32, 52, 4, 12}, {36, 48, 4, 4}, {40, 48, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewRLegFaces[6] = {
    {4, 20, 4, 12}, {12, 20, 4, 12}, {8, 20, 4, 12}, {0, 20, 4, 12}, {4, 16, 4, 4}, {8, 16, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewLLegFaces[6] = {
    {20, 52, 4, 12}, {28, 52, 4, 12}, {24, 52, 4, 12}, {16, 52, 4, 12}, {20, 48, 4, 4}, {24, 48, 4, 4}};

// 区块裁贴子图（皮肤为 64×64 或 64×32；裁剪矩形越界自动求交防炸）
static UIImage *ZL2SkinPreviewFaceImage(UIImage *skin, ZL2SkinPreviewRect r) {
    if (!skin.CGImage) return nil;
    CGFloat ame412_scaleX = skin.size.width / 64.0;
    CGFloat ame412_scaleY = skin.size.height / 64.0;
    CGRect ame412_crop = CGRectMake(r.x * ame412_scaleX, r.y * ame412_scaleY,
                                    r.w * ame412_scaleX, r.h * ame412_scaleY);
    CGRect ame412_bounds = CGRectMake(0, 0,
                                      CGImageGetWidth(skin.CGImage),
                                      CGImageGetHeight(skin.CGImage));
    ame412_crop = CGRectIntersection(ame412_crop, ame412_bounds);
    if (CGRectIsEmpty(ame412_crop)) return nil;
    CGImageRef ame412_sub = CGImageCreateWithImageInRect(skin.CGImage, ame412_crop);
    if (!ame412_sub) return nil;
    UIImage *ame412_face = [UIImage imageWithCGImage:ame412_sub];
    CGImageRelease(ame412_sub);
    return ame412_face;
}

#pragma mark - 实现

@interface ZL2SkinPreviewViewController ()
@property (nonatomic, strong) UIView *ame412_stageView;            // 3D 舞台（透视 sublayerTransform 宿主）
@property (nonatomic, strong) NSMutableArray<CALayer *> *ame412_faceLayers;   // 盒体面集合（贴图重建时整组拆建）
@property (nonatomic, strong, nullable) UIImage *ame412_currentSkin;          // 当前皮肤留档（视口变化整组重建）
@property (nonatomic, assign) CGFloat ame412_yaw;                  // 水平轨道角（rad）
@property (nonatomic, assign) CGFloat ame412_pitch;                // 俯仰角（rad，钳制 ±0.9）
@property (nonatomic, assign) CGFloat ame412_userScale;            // 捏合缩放（0.5~2.5）
@property (nonatomic, strong, nullable) CADisplayLink *ame412_ticker;
@property (nonatomic, assign) CFTimeInterval ame412_lastTick;
@end

// 盒体几何参数（单位空间；Y 自足底 0 起算，角色面朝 +Z）
typedef struct {
    CGFloat cx, cy, cz;   // 盒心
    CGFloat w, h, d;      // 尺寸
    const ZL2SkinPreviewRect *faces;   // 六面区块表
} ZL2SkinPreviewBox;

@implementation ZL2SkinPreviewViewController {
    NSString *_ame412_username;
    NSString *_ame412_profileId;
    UILabel *_ame412_hintLabel;
    UILabel *_ame412_statusLabel;
    UILabel *_ame412_titleLabel;
    UIControl *_ame412_closeButton;
    UIActivityIndicatorView *_ame412_spinner;
    CGFloat _ame412_baseUnit;        // 单位→pt 比例（视口自适应，build 时定）
}

- (instancetype)initWithUsername:(NSString *)username profileId:(NSString *)profileId {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _ame412_username = [username copy];
        _ame412_profileId = [profileId copy];
        _ame412_yaw = 0.0;
        _ame412_pitch = 0.0;
        _ame412_userScale = 1.0;
        self.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self ame412_buildChrome];
    [self ame412_buildStage];
    [self ame412_loadSkin];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ame412_layoutFaces];   // stage 已 AutoLayout 约束化，此处只管面重建/重摆
}

- (void)dealloc {
    [_ame412_ticker invalidate];
}

#pragma mark - 顶部骨架（标题/关闭/提示/状态/转圈）

- (void)ame412_buildChrome {
    _ame412_titleLabel = [[UILabel alloc] init];
    _ame412_titleLabel.text = localize(@"ame412.skin.preview.title", @"皮肤 3D 预览");
    _ame412_titleLabel.font = [ZL2Theme fontTitleMedium];
    _ame412_titleLabel.textColor = [UIColor whiteColor];
    _ame412_titleLabel.textAlignment = NSTextAlignmentCenter;
    _ame412_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame412_titleLabel];

    _ame412_closeButton = [[UIControl alloc] init];
    _ame412_closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _ame412_closeButton.isAccessibilityElement = YES;
    _ame412_closeButton.accessibilityTraits = UIAccessibilityTraitButton;
    _ame412_closeButton.accessibilityLabel = localize(@"resman.common.done", @"完成");
    [self.view addSubview:_ame412_closeButton];

    UILabel *ame412_closeLabel = [[UILabel alloc] init];
    ame412_closeLabel.text = localize(@"resman.common.done", @"完成");
    ame412_closeLabel.font = [ZL2Theme fontLabelLarge];
    ame412_closeLabel.textColor = [ZL2Theme primary];
    ame412_closeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame412_closeLabel.userInteractionEnabled = NO;
    [_ame412_closeButton addSubview:ame412_closeLabel];

    [_ame412_closeButton addTarget:self
                            action:@selector(ame412_close)
                  forControlEvents:UIControlEventTouchUpInside];

    _ame412_hintLabel = [[UILabel alloc] init];
    _ame412_hintLabel.text = localize(@"ame412.skin.preview.hint", @"拖动旋转 · 捏合缩放");
    _ame412_hintLabel.font = [ZL2Theme fontBodyMedium];
    _ame412_hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _ame412_hintLabel.textAlignment = NSTextAlignmentCenter;
    _ame412_hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame412_hintLabel];

    _ame412_statusLabel = [[UILabel alloc] init];
    _ame412_statusLabel.font = [ZL2Theme fontBodyMedium];
    _ame412_statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    _ame412_statusLabel.textAlignment = NSTextAlignmentCenter;
    _ame412_statusLabel.hidden = YES;
    _ame412_statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame412_statusLabel];

    _ame412_spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _ame412_spinner.color = [UIColor whiteColor];
    _ame412_spinner.hidesWhenStopped = YES;
    _ame412_spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame412_spinner];

    UILayoutGuide *ame412_safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_ame412_titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_ame412_titleLabel.centerYAnchor constraintEqualToAnchor:ame412_safe.topAnchor constant:26.0],
        [_ame412_closeButton.leadingAnchor constraintEqualToAnchor:ame412_safe.leadingAnchor constant:16.0],
        [_ame412_closeButton.centerYAnchor constraintEqualToAnchor:_ame412_titleLabel.centerYAnchor],
        [ame412_closeLabel.centerYAnchor constraintEqualToAnchor:_ame412_closeButton.centerYAnchor],
        [ame412_closeLabel.leadingAnchor constraintEqualToAnchor:_ame412_closeButton.leadingAnchor],
        [ame412_closeLabel.trailingAnchor constraintEqualToAnchor:_ame412_closeButton.trailingAnchor],
        [_ame412_hintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_ame412_hintLabel.bottomAnchor constraintEqualToAnchor:ame412_safe.bottomAnchor constant:-12.0],
        [_ame412_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_ame412_statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_ame412_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_ame412_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

#pragma mark - 3D 舞台与手势

- (void)ame412_buildStage {
    _ame412_stageView = [[UIView alloc] initWithFrame:self.view.bounds];
    _ame412_stageView.backgroundColor = [UIColor clearColor];
    _ame412_stageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame412_stageView];
    [NSLayoutConstraint activateConstraints:@[
        [_ame412_stageView.topAnchor constraintEqualToAnchor:_ame412_titleLabel.bottomAnchor constant:8.0],
        [_ame412_stageView.bottomAnchor constraintEqualToAnchor:_ame412_hintLabel.topAnchor constant:-8.0],
        [_ame412_stageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ame412_stageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // 透视宿主：sublayerTransform 持 m34（CA 经典 3D 盒体技法）
    CATransform3D ame412_persp = CATransform3DIdentity;
    ame412_persp.m34 = -1.0 / 700.0;
    _ame412_stageView.layer.sublayerTransform = ame412_persp;

    // 手势：拖轨（水平 = yaw、竖直 = pitch）+ 捏合缩放
    UIPanGestureRecognizer *ame412_pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ame412_handlePan:)];
    [_ame412_stageView addGestureRecognizer:ame412_pan];
    UIPinchGestureRecognizer *ame412_pinch =
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(ame412_handlePinch:)];
    [_ame412_stageView addGestureRecognizer:ame412_pinch];

    _ame412_faceLayers = [NSMutableArray array];

    // 占位灰模型先建（皮肤到位即整组拆建；零空白等待）
    [self ame412_applySkin:nil];

    // 自转帧驱动（CADisplayLink）
    _ame412_ticker = [CADisplayLink displayLinkWithTarget:self selector:@selector(ame412_tick)];
    _ame412_ticker.paused = NO;
    _ame412_lastTick = CACurrentMediaTime();
    [_ame412_ticker addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)ame412_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint ame412_t = [pan translationInView:_ame412_stageView];
    [pan setTranslation:CGPointZero inView:_ame412_stageView];
    _ame412_yaw += ame412_t.x * 0.008;
    _ame412_pitch += ame412_t.y * 0.008;
    if (_ame412_pitch > 0.9) _ame412_pitch = 0.9;
    if (_ame412_pitch < -0.9) _ame412_pitch = -0.9;
    [self ame412_updateModelTransform];
}

- (void)ame412_handlePinch:(UIPinchGestureRecognizer *)pinch {
    _ame412_userScale *= pinch.scale;
    if (_ame412_userScale < 0.5) _ame412_userScale = 0.5;
    if (_ame412_userScale > 2.5) _ame412_userScale = 2.5;
    [pinch setScale:1.0];
    [self ame412_updateModelTransform];
}

// 帧驱动：自转 + 重投影
- (void)ame412_tick {
    CFTimeInterval ame412_now = CACurrentMediaTime();
    CGFloat ame412_dt = (CGFloat)(ame412_now - _ame412_lastTick);
    _ame412_lastTick = ame412_now;
    if (ame412_dt > 0.1) ame412_dt = 0.1;
    _ame412_yaw += ame412_dt * 0.35;   // 慢速自转（rad/s）
    [self ame412_updateModelTransform];
}

// 模型层每帧 transform = RotX(pitch)·RotY(yaw)·Scale(user·base)
- (void)ame412_updateModelTransform {
    CGFloat ame412_s = _ame412_userScale;   // 面几何已按 baseUnit 构建 = 只乘捏合因子
    CATransform3D ame412_t = CATransform3DMakeRotation(_ame412_pitch, 1.0, 0.0, 0.0);
    ame412_t = CATransform3DRotate(ame412_t, _ame412_yaw, 0.0, 1.0, 0.0);
    ame412_t = CATransform3DScale(ame412_t, ame412_s, ame412_s, ame412_s);
    _ame412_stageView.layer.transform = ame412_t;
}

// 视口自适应比例（模型高 32 单位 → 视口高的 0.72）
- (void)ame412_recomputeBaseUnit {
    CGFloat ame412_h = _ame412_stageView.bounds.size.height;
    CGFloat ame412_w = _ame412_stageView.bounds.size.width;
    CGFloat ame412_fit = fmin(ame412_h * 0.72 / 32.0, ame412_w * 0.5 / 16.0);
    if (ame412_fit < 3.0) ame412_fit = 3.0;
    _ame412_baseUnit = ame412_fit;
    [self ame412_updateModelTransform];
}

#pragma mark - 盒体组装（36 面静态子层）

// 单盒六面：面序 [前(+Z) 后(−Z) 左(−X) 右(+X) 上(+Y) 下(−Y)]
// 每面：position = 舞台中心；transform = 平移(盒心)·面向旋转·平移(半深)。
static void ZL2SkinPreviewBuildBox(CALayer *ame412_parent,
                                   CGSize ame412_center,
                                   ZL2SkinPreviewBox ame412_box,
                                   CGFloat ame412_unit,
                                   UIImage *ame412_skin) {
    CGFloat ame412_x = ame412_box.cx;
    CGFloat ame412_y = ame412_box.cy - 16.0;   // 模型 Y 居中（0..32 → −16..16）
    CGFloat ame412_z = ame412_box.cz;
    for (NSInteger ame412_i = 0; ame412_i < 6; ame412_i++) {
        CGFloat ame412_offX = 0, ame412_offY = 0, ame412_offZ = 0;
        CGFloat ame412_rotY = 0, ame412_rotX = 0;
        CGFloat ame412_fw = 0, ame412_fh = 0;
        switch (ame412_i) {
            case 0:   // 前：面朝 +Z，z + d/2
                ame412_offZ = ame412_box.d / 2.0; ame412_fw = ame412_box.w; ame412_fh = ame412_box.h;
                break;
            case 1: { // 后：RotY(π)，z − d/2
                ame412_offZ = -ame412_box.d / 2.0; ame412_rotY = (CGFloat)M_PI;
                ame412_fw = ame412_box.w; ame412_fh = ame412_box.h;
                break;
            }
            case 2: { // 左：面朝 −X，x − w/2
                ame412_offX = -ame412_box.w / 2.0; ame412_rotY = -(CGFloat)M_PI / 2.0;
                ame412_fw = ame412_box.d; ame412_fh = ame412_box.h;
                break;
            }
            case 3: { // 右：面朝 +X，x + w/2
                ame412_offX = ame412_box.w / 2.0; ame412_rotY = (CGFloat)M_PI / 2.0;
                ame412_fw = ame412_box.d; ame412_fh = ame412_box.h;
                break;
            }
            case 4: { // 上：面朝 +Y，y + h/2
                ame412_offY = ame412_box.h / 2.0; ame412_rotX = -(CGFloat)M_PI / 2.0;
                ame412_fw = ame412_box.w; ame412_fh = ame412_box.d;
                break;
            }
            default: { // 下：面朝 −Y，y − h/2
                ame412_offY = -ame412_box.h / 2.0; ame412_rotX = (CGFloat)M_PI / 2.0;
                ame412_fw = ame412_box.w; ame412_fh = ame412_box.d;
                break;
            }
        }

        CALayer *ame412_face = [CALayer layer];
        ame412_face.bounds = CGRectMake(0, 0, ame412_fw * ame412_unit, ame412_fh * ame412_unit);
        ame412_face.position = ame412_center;
        ame412_face.isDoubleSided = NO;   // 背面剔除
        UIImage *ame412_img = ame412_skin ? ZL2SkinPreviewFaceImage(ame412_skin, ame412_box.faces[ame412_i]) : nil;
        if (ame412_img) {
            ame412_face.contents = (id)ame412_img.CGImage;
            ame412_face.contentsGravity = kCAGravityResize;
        } else {
            ame412_face.backgroundColor = [UIColor colorWithWhite:0.32 alpha:1.0];   // 占位灰面
        }
        CATransform3D ame412_t = CATransform3DMakeTranslation((ame412_x + ame412_offX) * ame412_unit,
                                                              (ame412_y + ame412_offY) * ame412_unit,
                                                              (ame412_z + ame412_offZ) * ame412_unit);
        if (ame412_rotY != 0.0) ame412_t = CATransform3DRotate(ame412_t, ame412_rotY, 0.0, 1.0, 0.0);
        if (ame412_rotX != 0.0) ame412_t = CATransform3DRotate(ame412_t, ame412_rotX, 1.0, 0.0, 0.0);
        ame412_face.transform = ame412_t;
        [ame412_parent addSublayer:ame412_face];
    }
}

// 用皮肤整组建模（skin = nil 时灰盒占位；每次整组拆建零残留）
- (void)ame412_applySkin:(UIImage *)skin {
    self.ame412_currentSkin = skin;
    CALayer *ame412_stage = _ame412_stageView.layer;
    for (CALayer *ame412_sub in [ame412_stage.sublayers copy]) {
        [ame412_sub removeFromSuperlayer];
    }
    [_ame412_faceLayers removeAllObjects];

    CGSize ame412_center = CGPointMake(CGRectGetMidX(_ame412_stageView.bounds),
                                       CGRectGetMidY(_ame412_stageView.bounds));
    CGFloat ame412_unit = _ame412_baseUnit;
    if (ame412_unit < 3.0) {
        [self ame412_recomputeBaseUnit];
        ame412_unit = _ame412_baseUnit;
    }

    if (skin.size.width < 1.0 || skin.size.height < 1.0) {
        // 占位灰模型（皮肤缺席诚实降级，零假纹理）
        ZL2SkinPreviewRect ame412_dummy[6] = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0},
                                              {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}};
        ZL2SkinPreviewBox ame412_box = {0, 16, 0, 10, 32, 6, ame412_dummy};
        ZL2SkinPreviewBuildBox(ame412_stage, ame412_center, ame412_box, ame412_unit, nil);
        [_ame412_faceLayers addObjectsFromArray:ame412_stage.sublayers];
        return;
    }

    BOOL ame412_legacy = (skin.size.height < 64.0);   // 64×32 旧版 = 左臂左腿镜像右区
    const ZL2SkinPreviewRect *ame412_lArmF = ame412_legacy ? ZL2SkinPreviewRArmFaces : ZL2SkinPreviewLArmFaces;
    const ZL2SkinPreviewRect *ame412_lLegF = ame412_legacy ? ZL2SkinPreviewRLegFaces : ZL2SkinPreviewLLegFaces;

    ZL2SkinPreviewBox ame412_boxes[6] = {
        {0, 28, 0, 8, 8, 8, ZL2SkinPreviewHeadFaces},    // 头（足底 24..32）
        {0, 18, 0, 8, 12, 4, ZL2SkinPreviewBodyFaces},   // 身（12..24）
        {-6, 18, 0, 4, 12, 4, ZL2SkinPreviewRArmFaces},  // 右臂（角色右 = −X）
        {6, 18, 0, 4, 12, 4, ame412_lArmF},              // 左臂
        {-2, 6, 0, 4, 12, 4, ZL2SkinPreviewRLegFaces},   // 右腿（0..12）
        {2, 6, 0, 4, 12, 4, ame412_lLegF},               // 左腿
    };
    for (NSInteger ame412_i = 0; ame412_i < 6; ame412_i++) {
        ZL2SkinPreviewBuildBox(ame412_stage, ame412_center, ame412_boxes[ame412_i], ame412_unit, skin);
    }
    [_ame412_faceLayers addObjectsFromArray:ame412_stage.sublayers];
    [self ame412_updateModelTransform];
}

// 视口变化：unit 随视口自适应 → 整组重建（面几何内含 unit，非纯位移可摆）
- (void)ame412_layoutFaces {
    CGFloat ame412_h = _ame412_stageView.bounds.size.height;
    CGFloat ame412_w = _ame412_stageView.bounds.size.width;
    CGFloat ame412_fit = fmin(ame412_h * 0.72 / 32.0, ame412_w * 0.5 / 16.0);
    if (ame412_fit < 3.0) ame412_fit = 3.0;
    if (fabs(ame412_fit - _ame412_baseUnit) > 0.5) {
        _ame412_baseUnit = ame412_fit;
        [self ame412_applySkin:self.ame412_currentSkin];   // 整组重建（unit 变化）
        return;
    }
    CGPoint ame412_center = CGPointMake(CGRectGetMidX(_ame412_stageView.bounds),
                                        CGRectGetMidY(_ame412_stageView.bounds));
    for (CALayer *ame412_face in _ame412_faceLayers) {
        ame412_face.position = ame412_center;
    }
}

#pragma mark - 皮肤加载链

// ①crafatar(profileId) → ②minotar(username) → ③磁盘缓存优先 → ④nil（占位）
- (void)ame412_loadSkin {
    NSString *ame412_key = (_ame412_profileId.length > 0) ? _ame412_profileId : _ame412_username;
    NSString *ame412_cachePath = [[ZL2SkinPreviewCacheDir()
        stringByAppendingPathComponent:ZL2SkinPreviewSafeName(ame412_key ?: @"anonymous")]
        stringByAppendingPathExtension:@"png"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:ame412_cachePath]) {
        UIImage *ame412_cached = [UIImage imageWithContentsOfFile:ame412_cachePath];
        if (ame412_cached) {
            [self ame412_applySkin:ame412_cached];
            return;
        }
    }

    NSMutableArray<NSString *> *ame412_urls = [NSMutableArray array];
    if (_ame412_profileId.length > 0) {
        [ame412_urls addObject:[NSString stringWithFormat:@"https://crafatar.com/skins/%@", _ame412_profileId]];
    }
    if (_ame412_username.length > 0) {
        [ame412_urls addObject:[NSString stringWithFormat:@"https://minotar.net/skin/%@", _ame412_username]];
    }
    if (ame412_urls.count == 0) {
        [self ame412_showUnavailable];
        return;
    }

    _ame412_spinner.hidden = NO;
    [_ame412_spinner startAnimating];
    [self ame412_tryURLAtIndex:0 urls:ame412_urls cachePath:ame412_cachePath];
}

// 方法递归回退（block 自捕获 = run 42487051782 保留环警告判例规避）
- (void)ame412_tryURLAtIndex:(NSUInteger)ame412_idx
                        urls:(NSArray<NSString *> *)ame412_urls
                   cachePath:(NSString *)ame412_cachePath {
    if (ame412_idx >= ame412_urls.count) {
        [_ame412_spinner stopAnimating];
        [self ame412_applySkin:nil];
        [self ame412_showUnavailable];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *ame412_task =
        [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:ame412_urls[ame412_idx]]
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *ame412_image = (data.length > 0 && !error) ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) strongSelf = wself;
            if (!strongSelf) return;
            if (ame412_image) {
                [data writeToFile:ame412_cachePath atomically:YES];   // 落盘缓存
                [strongSelf->_ame412_spinner stopAnimating];
                [strongSelf ame412_applySkin:ame412_image];
            } else {
                [strongSelf ame412_tryURLAtIndex:ame412_idx + 1 urls:ame412_urls cachePath:ame412_cachePath];
            }
        });
    }];
    [ame412_task resume];
}

- (void)ame412_showUnavailable {
    _ame412_statusLabel.hidden = NO;
    _ame412_statusLabel.text = localize(@"ame412.skin.preview.unavailable", @"皮肤加载失败，显示占位模型");
}

- (void)ame412_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
