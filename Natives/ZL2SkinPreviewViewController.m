//
// ZL2SkinPreviewViewController.m — ★ Task412 账户页皮肤 3D 预览实现（设计
// 契约见 .h 头注释；第 20 轮复诉⑥「在账号页面添加皮肤3d预览等功能」）
//

#import "ZL2SkinPreviewViewController.h"
#import "ZL2Theme.h"
#import "utils.h"   // localize()

#import <SceneKit/SceneKit.h>
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

// SCNGeometry(SCNBox) 材质序：0 前(+Z) 1 右(+X) 2 后(−Z) 3 左(−X) 4 上 5 下。
// 皮肤侧区块按「角色右/左」命名（观察者从角色右侧看 = 世界 −X = 盒体左面），
// 故盒体右面(+X)贴皮肤「左」区块、盒体左面(−X)贴皮肤「右」区块。
// 64×64 标准布局（原点左上）：
//   头 8³：前(8,8) 左(16,8) 后(24,8) 右(0,8) 上(8,0) 下(16,0)
//   身 8×12×4：前(20,20) 左(28,20) 后(32,20) 右(16,20) 上(20,16) 下(28,16)
//   右臂 4×12×4：前(44,20) 左(48,20) 后(52,20) 右(40,20) 上(44,16) 下(48,16)
//   左臂 4×12×4：前(36,52) 左(40,52) 后(44,52) 右(32,52) 上(36,48) 下(40,48)
//   右腿 4×12×4：前(4,20) 左(8,20) 后(12,20) 右(0,20) 上(4,16) 下(8,16)
//   左腿 4×12×4：前(20,52) 左(24,52) 后(28,52) 右(16,52) 上(20,48) 下(24,48)
// 64×32 旧版：左臂/左腿整组镜像右臂/右腿区块（ame412_legacy 分支）。
static const ZL2SkinPreviewRect ZL2SkinPreviewHeadFaces[6] = {
    {8, 8, 8, 8}, {16, 8, 8, 8}, {24, 8, 8, 8}, {0, 8, 8, 8}, {8, 0, 8, 8}, {16, 0, 8, 8}};
static const ZL2SkinPreviewRect ZL2SkinPreviewBodyFaces[6] = {
    {20, 20, 8, 12}, {28, 20, 4, 12}, {32, 20, 8, 12}, {16, 20, 4, 12}, {20, 16, 8, 4}, {28, 16, 8, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewRArmFaces[6] = {
    {44, 20, 4, 12}, {48, 20, 4, 12}, {52, 20, 4, 12}, {40, 20, 4, 12}, {44, 16, 4, 4}, {48, 16, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewLArmFaces[6] = {
    {36, 52, 4, 12}, {40, 52, 4, 12}, {44, 52, 4, 12}, {32, 52, 4, 12}, {36, 48, 4, 4}, {40, 48, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewRLegFaces[6] = {
    {4, 20, 4, 12}, {8, 20, 4, 12}, {12, 20, 4, 12}, {0, 20, 4, 12}, {4, 16, 4, 4}, {8, 16, 4, 4}};
static const ZL2SkinPreviewRect ZL2SkinPreviewLLegFaces[6] = {
    {20, 52, 4, 12}, {24, 52, 4, 12}, {28, 52, 4, 12}, {16, 52, 4, 12}, {20, 48, 4, 4}, {24, 48, 4, 4}};

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

// 盒体节点（六面独立裁贴材质；区块缺席面 = 整皮肤占位防黑面）
static SCNNode *ZL2SkinPreviewBoxNode(UIImage *skin,
                                      CGFloat ame412_w, CGFloat ame412_h, CGFloat ame412_d,
                                      const ZL2SkinPreviewRect *ame412_faces) {
    SCNBox *ame412_box = [SCNBox boxWithWidth:ame412_w height:ame412_h length:ame412_d cornerRadius:0];
    NSMutableArray<SCNMaterial *> *ame412_materials = [NSMutableArray array];
    for (NSInteger ame412_i = 0; ame412_i < 6; ame412_i++) {
        SCNMaterial *ame412_m = [SCNMaterial material];
        ame412_m.lightingModel = SCNLightingModelConstant;   // 平光 = 皮肤原色直出
        ame412_m.diffuse.contents = skin;                    // 占位（下行为真实裁贴）
        ame412_m.diffuse.wrapS = SCNWrapModeClamp;
        ame412_m.diffuse.wrapT = SCNWrapModeClamp;
        ame412_m.doubleSided = NO;
        UIImage *ame412_face = ZL2SkinPreviewFaceImage(skin, ame412_faces[ame412_i]);
        if (ame412_face) ame412_m.diffuse.contents = ame412_face;
        [ame412_materials addObject:ame412_m];
    }
    ame412_box.materials = ame412_materials;
    SCNNode *ame412_node = [SCNNode node];
    ame412_node.geometry = ame412_box;
    return ame412_node;
}

#pragma mark - 实现

@interface ZL2SkinPreviewViewController ()
@property (nonatomic, strong, nullable) SCNNode *ame412_modelHolder;   // 自转轴（皮肤重建不丢动作）
@end

@implementation ZL2SkinPreviewViewController {
    NSString *_ame412_username;
    NSString *_ame412_profileId;
    SCNView *_ame412_sceneView;
    UILabel *_ame412_hintLabel;
    UILabel *_ame412_statusLabel;
    UILabel *_ame412_titleLabel;
    UIControl *_ame412_closeButton;
    UIActivityIndicatorView *_ame412_spinner;
}

- (instancetype)initWithUsername:(NSString *)username profileId:(NSString *)profileId {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _ame412_username = [username copy];
        _ame412_profileId = [profileId copy];
        self.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self ame412_buildChrome];
    [self ame412_buildScene];
    [self ame412_loadSkin];
}

- (void)ame412_buildChrome {
    // 顶部标题行（黑底沉浸面：白字标题 + 关闭钮；截图查看器同款语言）
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

- (void)ame412_buildScene {
    _ame412_sceneView = [[SCNView alloc] init];
    _ame412_sceneView.translatesAutoresizingMaskIntoConstraints = NO;
    _ame412_sceneView.backgroundColor = [UIColor blackColor];
    _ame412_sceneView.allowsCameraControl = YES;   // 单指轨道旋转 / 双指捏合缩放
    _ame412_sceneView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    [self.view addSubview:_ame412_sceneView];
    [NSLayoutConstraint activateConstraints:@[
        [_ame412_sceneView.topAnchor constraintEqualToAnchor:_ame412_titleLabel.bottomAnchor constant:8.0],
        [_ame412_sceneView.bottomAnchor constraintEqualToAnchor:_ame412_hintLabel.topAnchor constant:-8.0],
        [_ame412_sceneView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ame412_sceneView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    SCNScene *ame412_scene = [SCNScene scene];
    ame412_scene.background.contents = [UIColor blackColor];
    _ame412_sceneView.scene = ame412_scene;

    SCNCamera *ame412_camera = [SCNCamera camera];
    ame412_camera.zNear = 0.1;
    ame412_camera.zFar = 500.0;
    SCNNode *ame412_cameraNode = [SCNNode node];
    ame412_cameraNode.camera = ame412_camera;
    ame412_cameraNode.position = SCNVector3Make(0, 24, 58);
    [ame412_scene.rootNode addChildNode:ame412_cameraNode];

    // 自转轴节点（皮肤异步到位重建内容，动作持在轴上不丢）
    SCNNode *ame412_holder = [SCNNode node];
    [ame412_scene.rootNode addChildNode:ame412_holder];
    self.ame412_modelHolder = ame412_holder;
    [ame412_holder runAction:[SCNAction repeatActionForever:
        [SCNAction rotateByAngle:M_PI * 2.0 duration:16.0 aroundAxis:SCNVector3Make(0, 1, 0)]]];

    // 占位模型先建（皮肤到位即重贴；零空白等待）
    [self ame412_applySkin:nil];
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

    _ame412_spinner.hidden = NO;
    [_ame412_spinner startAnimating];

    NSMutableArray<NSString *> *ame412_urls = [NSMutableArray array];
    if (_ame412_profileId.length > 0) {
        [ame412_urls addObject:[NSString stringWithFormat:@"https://crafatar.com/skins/%@", _ame412_profileId]];
    }
    if (_ame412_username.length > 0) {
        [ame412_urls addObject:[NSString stringWithFormat:@"https://minotar.net/skin/%@", _ame412_username]];
    }
    if (ame412_urls.count == 0) {
        [_ame412_spinner stopAnimating];
        [self ame412_applySkin:nil];
        [self ame412_showUnavailable];
        return;
    }

    __weak typeof(self) wself = self;
    __block void (^ame412_try)(NSUInteger) = nil;
    ame412_try = ^(NSUInteger ame412_idx) {
        if (ame412_idx >= ame412_urls.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(wself) strongSelf = wself;
                if (!strongSelf) return;
                [strongSelf->_ame412_spinner stopAnimating];
                [strongSelf ame412_applySkin:nil];
                [strongSelf ame412_showUnavailable];
            });
            return;
        }
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
                    ame412_try(ame412_idx + 1);   // 回退链下一层
                }
            });
        }];
        [ame412_task resume];
    };
    ame412_try(0);
}

- (void)ame412_showUnavailable {
    _ame412_statusLabel.hidden = NO;
    _ame412_statusLabel.text = localize(@"ame412.skin.preview.unavailable", @"皮肤加载失败，显示占位模型");
}

- (void)ame412_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 盒体模型组装

// 用皮肤贴六盒体（skin = nil 时灰色占位；Y 自足底 0 起算，角色面朝 +Z 相机）
- (void)ame412_applySkin:(UIImage *)skin {
    SCNNode *ame412_holder = self.ame412_modelHolder;
    if (!ame412_holder) return;

    for (SCNNode *ame412_child in [ame412_holder.childNodes copy]) {
        [ame412_child removeFromParentNode];
    }

    if (skin.size.width < 1.0 || skin.size.height < 1.0) {
        // 占位灰模型（皮肤缺席诚实降级，零假纹理）
        SCNBox *ame412_box = [SCNBox boxWithWidth:10 height:32 length:6 cornerRadius:0];
        SCNMaterial *ame412_m = [SCNMaterial material];
        ame412_m.lightingModel = SCNLightingModelConstant;
        ame412_m.diffuse.contents = [UIColor colorWithWhite:0.35 alpha:1.0];
        ame412_box.materials = @[ame412_m];
        SCNNode *ame412_placeholder = [SCNNode node];
        ame412_placeholder.geometry = ame412_box;
        ame412_placeholder.position = SCNVector3Make(0, 16, 0);
        [ame412_holder addChildNode:ame412_placeholder];
        return;
    }

    BOOL ame412_legacy = (skin.size.height < 64.0);   // 64×32 旧版 = 左臂左腿镜像右区
    const ZL2SkinPreviewRect *ame412_lArmF = ame412_legacy ? ZL2SkinPreviewRArmFaces : ZL2SkinPreviewLArmFaces;
    const ZL2SkinPreviewRect *ame412_lLegF = ame412_legacy ? ZL2SkinPreviewRLegFaces : ZL2SkinPreviewLLegFaces;

    SCNNode *ame412_model = [SCNNode node];
    ame412_model.name = @"ame412_playerModel";

    SCNNode *ame412_head = ZL2SkinPreviewBoxNode(skin, 8, 8, 8, ZL2SkinPreviewHeadFaces);
    ame412_head.position = SCNVector3Make(0, 28, 0);   // 腿12+身12 → 头底 24，头高 8
    [ame412_model addChildNode:ame412_head];

    SCNNode *ame412_body = ZL2SkinPreviewBoxNode(skin, 8, 12, 4, ZL2SkinPreviewBodyFaces);
    ame412_body.position = SCNVector3Make(0, 18, 0);
    [ame412_model addChildNode:ame412_body];

    // 臂与身同高（肩顶 24，臂长 12 → 中心 18）；角色右手 = 相机视角左侧（−X）
    SCNNode *ame412_rArm = ZL2SkinPreviewBoxNode(skin, 4, 12, 4, ZL2SkinPreviewRArmFaces);
    ame412_rArm.position = SCNVector3Make(-6, 18, 0);
    [ame412_model addChildNode:ame412_rArm];
    SCNNode *ame412_lArm = ZL2SkinPreviewBoxNode(skin, 4, 12, 4, ame412_lArmF);
    ame412_lArm.position = SCNVector3Make(6, 18, 0);
    [ame412_model addChildNode:ame412_lArm];

    // 腿（足底 0 → 中心 6）；内缘贴 x=0 → 中心 ±2
    SCNNode *ame412_rLeg = ZL2SkinPreviewBoxNode(skin, 4, 12, 4, ZL2SkinPreviewRLegFaces);
    ame412_rLeg.position = SCNVector3Make(-2, 6, 0);
    [ame412_model addChildNode:ame412_rLeg];
    SCNNode *ame412_lLeg = ZL2SkinPreviewBoxNode(skin, 4, 12, 4, ame412_lLegF);
    ame412_lLeg.position = SCNVector3Make(2, 6, 0);
    [ame412_model addChildNode:ame412_lLeg];

    [ame412_holder addChildNode:ame412_model];
}

@end
