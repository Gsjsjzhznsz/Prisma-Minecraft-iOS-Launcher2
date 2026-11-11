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

// ★Task417 第二层 UV（skinview3d outerLayer 同源）：帽 = 头区块 x+32；
// 衣 = 身区块 y+16；右袖 = 右臂区块 y+16；左袖 = 左臂区块 x+16；
// 右裤 = 右腿区块 y+16；左裤 = (0,48) 独立区块；slim 前后/上下 3 宽同基础层。
// 64×32 旧版：帽/衣/右袖/右裤区块在（32..64,0..16）/（16..32,32..48）等带内存在；
// 左袖/左裤区块不存在 = 镜像右区（与基础层 legacy 分支同口径）。
static const ZL2SkinViewRect ZL2SkinViewHatFaces[6] = {
    {40, 8, 8, 8}, {56, 8, 8, 8}, {32, 8, 8, 8}, {48, 8, 8, 8}, {40, 0, 8, 8}, {48, 0, 8, 8}};
static const ZL2SkinViewRect ZL2SkinViewJacketFaces[6] = {
    {20, 36, 8, 12}, {32, 36, 8, 12}, {16, 36, 4, 12}, {28, 36, 4, 12}, {20, 32, 8, 4}, {28, 32, 8, 4}};
static const ZL2SkinViewRect ZL2SkinViewRSleeveFaces[6] = {
    {44, 36, 4, 12}, {52, 36, 4, 12}, {40, 36, 4, 12}, {48, 36, 4, 12}, {44, 32, 4, 4}, {48, 32, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewLSleeveFaces[6] = {
    {52, 52, 4, 12}, {60, 52, 4, 12}, {48, 52, 4, 12}, {56, 52, 4, 12}, {52, 48, 4, 4}, {56, 48, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewRPantFaces[6] = {
    {4, 36, 4, 12}, {12, 36, 4, 12}, {0, 36, 4, 12}, {8, 36, 4, 12}, {4, 32, 4, 4}, {8, 32, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewLPantFaces[6] = {
    {4, 52, 4, 12}, {12, 52, 4, 12}, {0, 52, 4, 12}, {8, 52, 4, 12}, {4, 48, 4, 4}, {8, 48, 4, 4}};
static const ZL2SkinViewRect ZL2SkinViewRSleeveSlimFaces[6] = {
    {44, 36, 3, 12}, {51, 36, 3, 12}, {40, 36, 4, 12}, {48, 36, 4, 12}, {44, 32, 3, 4}, {47, 32, 3, 4}};
static const ZL2SkinViewRect ZL2SkinViewLSleeveSlimFaces[6] = {
    {52, 52, 3, 12}, {59, 52, 3, 12}, {48, 52, 4, 12}, {56, 52, 4, 12}, {52, 48, 3, 4}, {55, 48, 3, 4}};

// 区块裁贴子图（皮肤为 64×64 / 64×32 / HD 等比；裁剪矩形越界自动求交防炸）
// ★Task418 y 标度根修：旧 scaleY = height/64 把 64×32 旧皮的整张展开图压进
//   上半带（scaleY=0.5）——所有区块读到错位像素：渐变皮看不出错位，但帽/衣/
//   袖/裤外层区块（y≥32）必然映射到基础层手臂/腿像素 = 每个部位一套 +1 膨胀
//   的「幽灵盒」= IMG_0619 真机实锤。正确口径：y 与 x 同标度（64×64→1.0 /
//   64×32→1.0（旧版布局区块全在 y<32）/ HD→等比 width/64）。
static UIImage *ZL2SkinViewFaceImage(UIImage *skin, ZL2SkinViewRect r) {
    if (!skin.CGImage) return nil;
    CGFloat ame413_scaleX = skin.size.width / 64.0;
    CGFloat ame413_scaleY = ame413_scaleX;   // ★Task418：y 同 x 标度（旧 height/64 退役）
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

// ★Task416 面记录（skinview3d 移植版）：CPU 逐面投影 + 画家算法。
//   corners[4] = 面四角（模型空间、已按 y=16 居中；序 = 纹理 TL/TR/BR/BL）；
//   pivot = 肢体枢轴（居中模型空间；skinview3d BodyPart 原点换算 y+24→0）；
//   normal = 面法线（模型空间轴向量）；rect = 皮肤 UV 区块（像素）。
//   旧 CATransform3D 拼接链（ame_baseT/cx/cy/cz/nx/ny/nz/px/py/pz）整体
//   退役——拼接序歧义正是 413/414/415 三轮「纸片/乱麻」复发的载体。
//   ★数组成员用 @public ivar（ObjC @property 不支持 C 数组类型 = CI 编译
//   必炸雷；C 工厂函数与 ObjC 方法均经 -> 直访，零拷贝语义）
@interface ZL2SkinViewFace : NSObject {
@public
    CGFloat corners[4][3];   // 模型空间四角（居中，TL/TR/BR/BL）
    CGFloat pivot[3];        // 肢体枢轴（居中模型空间）
    CGFloat normal[3];       // 面法线（模型空间）
}
@property (nonatomic, strong) CALayer *layer;    // 贴图面（shade 为其子层随动）
@property (nonatomic, strong) CALayer *shade;    // 黑色光影罩（opacity = 1−shade 逐帧）
@property (nonatomic, assign) CGFloat swingSign;       // 摆动方向（0 = 非肢体）
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

// ★Task416 光向（模型空间 +Y 向上 → 光来自左上前上方；与旧层空间向量
//   同一物理光源，Y 分量翻转适配模型空间直算）
static const CGFloat AME416_LIGHT_X = -0.45;
static const CGFloat AME416_LIGHT_Y =  0.62;
static const CGFloat AME416_LIGHT_Z =  0.65;
// ★Task416 CPU 透视视距（pt；模型对角最大 ~20unit×unit×userScale 远小于
//   此值，pf 恒有界；stage sublayerTransform m34 同帧退役 = 全链透视唯一源）
static const CGFloat AME416_CAMERA_D = 900.0;
// ★Task416 跑步摆幅（415 0.55 微收 = 皮肤站观感口径；walk 默认关 = 开屏
//   站姿立正，自转慢速展示，跑步钮点按才起摆）
static const CGFloat AME416_WALK_AMP = 0.50;

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
        // ★Task416-r3 皮肤站惯例机位：3/4 视角起步 + 轻微俯视（顶面可见 =
        //   任意自转相位都带纵深，正/纯侧棱边态不再成为默认首屏/截图相位）
        _ame413_yaw = -0.60;
        _ame414_spinTarget = -0.60;
        _ame413_pitch = -0.18;
        _ame413_userScale = 1.0;
        _ame413_slimModel = NO;
        _ame413_faceLayers = [NSMutableArray array];
        // ★Task416 跑步默认关（开屏站姿立正 + 慢速自转 = 皮肤站口径；415
        //   开屏即全幅摆动 = 截图任意相位都是四肢交叉乱麻的观感源之一）
        _ame414_walkOn = NO;
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

    // 透视宿主：★Task416 sublayerTransform m34 退役——透视改为 CPU 逐面
    //   投影（pf = D/(D−Z)，AME416_CAMERA_D 视距），stage 恒 identity；
    //   遮挡序 zPosition = 相机 z（大者在前），全链透视/深度唯一源 = 投影
    //   函数（旧 m34 与 CPU z 混用 = 两套透视口径互相污染的载体）
    _ame413_stageView.layer.sublayerTransform = CATransform3DIdentity;

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
    if (!isfinite(ame413_t.x) || !isfinite(ame413_t.y)) return;   // ★415a NaN 卫兵
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
    // ★Task415a NaN 卫兵：手势/时钟异常态（pinch.scale NaN、系统时钟回拨等）
    //   一旦污染旋转状态，模型整组消失且自恢复（isfinite 过滤 + 归零）
    if (!isfinite(_ame413_yaw)) { _ame413_yaw = 0.0; _ame414_spinTarget = 0.0; }
    if (!isfinite(_ame413_pitch)) _ame413_pitch = 0.0;
    if (!isfinite(_ame413_userScale) || _ame413_userScale < 0.05) _ame413_userScale = 1.0;
    if (!isfinite(_ame414_walkPhase)) _ame414_walkPhase = 0.0;
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

// ★Task416 旋转辅助（模型空间；与 scripts/task416_skin3d_preview.py
//   rot_y/rot_x 逐公式同源——Python 先行验证通过后落 ObjC）
static void Ame416RotY(CGFloat th, CGFloat *x, CGFloat *z) {
    CGFloat ame416_c = cos(th), ame416_s = sin(th);
    CGFloat ame416_nx = *x * ame416_c + *z * ame416_s;
    *z = -*x * ame416_s + *z * ame416_c;
    *x = ame416_nx;
}
static void Ame416RotX(CGFloat th, CGFloat *y, CGFloat *z) {
    CGFloat ame416_c = cos(th), ame416_s = sin(th);
    CGFloat ame416_ny = *y * ame416_c - *z * ame416_s;
    *z = *y * ame416_s + *z * ame416_c;
    *y = ame416_ny;
}

// 每帧 CPU 逐面投影（★Task416 skinview3d 移植：旧 CATransform3D 拼接链整体
// 退役）。管线：角点（居中模型空间）→ 肢体摆动（绕枢轴 RotX）→ 全局旋转
// （yaw 先 pitch 后）→ ×unit×userScale → CPU 透视（pf = D/(D−Z)）→ 屏幕四边
// 形 → 仿射贴面（position = 投影后面心，transform = 角点解出的仿射）+
// 画家序（zPosition = 相机 z，大者在前）+ 背面剔除（旋转后法线 nz≤0 隐藏）
// + 法线明暗罩。舞台恒 identity（sublayerTransform 已退役）= 透视/深度唯一
// 源在本函数；与 ZL2ShellIconButton 图标常量、装配 UV 表零耦合。
- (void)ame413_updateModelTransform {
    CGFloat ame416_unit = _ame413_baseUnit * _ame413_userScale;
    CGFloat ame416_swing = _ame414_walkOn ? (AME416_WALK_AMP * sin(_ame414_walkPhase)) : 0.0;
    CGPoint ame416_cen = CGPointMake(CGRectGetMidX(_ame413_stageView.bounds),
                                     CGRectGetMidY(_ame413_stageView.bounds));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (ZL2SkinViewFace *ame414_f in _ame413_faceLayers) {
        CGFloat ame416_th = ame416_swing * ame414_f.swingSign;
        CGFloat ame416_ct = cos(ame416_th), ame416_st = sin(ame416_th);
        // ——法线：随摆 → 随旋（剔除判定 + 明暗共用）——
        CGFloat ame416_nx = ame414_f->normal[0], ame416_ny = ame414_f->normal[1], ame416_nz = ame414_f->normal[2];
        if (ame416_th != 0.0) Ame416RotX(ame416_th, &ame416_ny, &ame416_nz);
        Ame416RotY(_ame413_yaw, &ame416_nx, &ame416_nz);
        Ame416RotX(_ame413_pitch, &ame416_ny, &ame416_nz);
        BOOL ame416_backface = (ame416_nz <= 0.0);
        // ——四角投影——
        CGFloat ame416_sx[4], ame416_sy[4], ame416_zsum = 0.0;
        BOOL ame416_ok = YES;
        for (NSInteger ame416_k = 0; ame416_k < 4; ame416_k++) {
            CGFloat ame416_vx = ame414_f->corners[ame416_k][0];
            CGFloat ame416_vy = ame414_f->corners[ame416_k][1];
            CGFloat ame416_vz = ame414_f->corners[ame416_k][2];
            if (ame416_th != 0.0) {   // 摆动绕枢轴（RotX）
                CGFloat ame416_dy = ame416_vy - ame414_f->pivot[1];
                CGFloat ame416_dz = ame416_vz - ame414_f->pivot[2];
                ame416_vy = ame414_f->pivot[1] + ame416_dy * ame416_ct - ame416_dz * ame416_st;
                ame416_vz = ame414_f->pivot[2] + ame416_dy * ame416_st + ame416_dz * ame416_ct;
            }
            Ame416RotY(_ame413_yaw, &ame416_vx, &ame416_vz);
            Ame416RotX(_ame413_pitch, &ame416_vy, &ame416_vz);
            ame416_vx *= ame416_unit; ame416_vy *= ame416_unit; ame416_vz *= ame416_unit;
            if (!isfinite(ame416_vx + ame416_vy + ame416_vz)) { ame416_ok = NO; break; }
            if (ame416_vz > AME416_CAMERA_D * 0.9) ame416_vz = AME416_CAMERA_D * 0.9;   // pf 有界卫兵
            CGFloat ame416_pf = AME416_CAMERA_D / (AME416_CAMERA_D - ame416_vz);
            ame416_sx[ame416_k] = ame416_vx * ame416_pf;
            ame416_sy[ame416_k] = -ame416_vy * ame416_pf;
            ame416_zsum += ame416_vz;
        }
        if (!ame416_ok) continue;
        ame414_f.layer.hidden = ame416_backface;   // 背面剔除（画家序前置）
        if (ame416_backface) continue;
        ame414_f.layer.zPosition = ame416_zsum / 4.0;   // 画家序：远先近后
        // ——仿射贴面：L0=(-W2,-H2) L1=(+W2,-H2) L3=(-W2,+H2) → P0/P1/P3——
        CGFloat ame416_w2 = ame414_f.layer.bounds.size.width / 2.0;
        CGFloat ame416_h2 = ame414_f.layer.bounds.size.height / 2.0;
        CGFloat ame416_a11 = (ame416_sx[1] - ame416_sx[0]) / (2.0 * ame416_w2);
        CGFloat ame416_a21 = (ame416_sy[1] - ame416_sy[0]) / (2.0 * ame416_w2);
        CGFloat ame416_a12 = (ame416_sx[3] - ame416_sx[0]) / (2.0 * ame416_h2);
        CGFloat ame416_a22 = (ame416_sy[3] - ame416_sy[0]) / (2.0 * ame416_h2);
        CGFloat ame416_det = ame416_a11 * ame416_a22 - ame416_a12 * ame416_a21;
        if (!isfinite(ame416_det) || fabs(ame416_det) < 1e-6) {
            ame414_f.layer.hidden = YES;   // 近棱边退化面隐藏（宽→0）
            continue;
        }
        CGAffineTransform ame416_aff = CGAffineTransformMake(ame416_a11, ame416_a21, ame416_a12, ame416_a22, 0.0, 0.0);
        ame414_f.layer.transform = CATransform3DMakeAffineTransform(ame416_aff);
        ame414_f.layer.position = CGPointMake(
            ame416_cen.x + ame416_sx[0] + ame416_a11 * ame416_w2 + ame416_a12 * ame416_h2,
            ame416_cen.y + ame416_sy[0] + ame416_a21 * ame416_w2 + ame416_a22 * ame416_h2);
        // ——明暗罩：法线 × 光向点积（左上前主光）——
        CGFloat ame416_len = sqrt(ame416_nx * ame416_nx + ame416_ny * ame416_ny + ame416_nz * ame416_nz);
        if (ame416_len < 0.0001) ame416_len = 1.0;
        CGFloat ame416_dot = (ame416_nx * AME416_LIGHT_X + ame416_ny * AME416_LIGHT_Y + ame416_nz * AME416_LIGHT_Z) / ame416_len;
        CGFloat ame416_shade = 0.44 + 0.58 * fmax(0.0, ame416_dot);
        if (ame416_shade > 1.0) ame416_shade = 1.0;
        ame414_f.shade.opacity = (1.0 - ame416_shade) * 0.85;
    }
    [CATransaction commit];
}

// 视口自适应比例（模型高 32 单位 → 舞台高的 0.74；宽含双臂 16 单位）
- (void)ame413_recomputeBaseUnit {
    CGFloat ame413_h = _ame413_stageView.bounds.size.height;
    CGFloat ame413_w = _ame413_stageView.bounds.size.width;
    CGFloat ame413_fit = fmin(ame413_h * 0.74 / 32.0, ame413_w * 0.58 / 17.0);
    if (ame413_fit < 2.0) ame413_fit = 2.0;
    _ame413_baseUnit = ame413_fit;
    [self ame413_updateModelTransform];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat ame413_h = _ame413_stageView.bounds.size.height;
    CGFloat ame413_w = _ame413_stageView.bounds.size.width;
    CGFloat ame413_fit = fmin(ame413_h * 0.74 / 32.0, ame413_w * 0.58 / 17.0);
    if (ame413_fit < 2.0) ame413_fit = 2.0;
    if (fabs(ame413_fit - _ame413_baseUnit) > 0.5) {
        _ame413_baseUnit = ame413_fit;
        [self ame413_applySkin:_ame413_currentSkin];   // unit 变化整组重建
        return;
    }
    [self ame413_updateModelTransform];   // ★Task416 舞台中心随布局重投影
}

#pragma mark 盒体组装（★Task416 skinview3d 装配表：36 面 + 枢轴 + UV）

// 单部件六面（面序 [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]，与 UV 表序
// 一致）。每面：面心 = 盒心 + 轴向半尺寸偏移；纹理 u/v 方向向量（模型空间）
// 与法线取 MC 展开图约定（前=恒等、后=横镜像、右脸 u→−Z、左脸 u→+Z、
// 上/下面 v→∓Z）；四角按纹理 TL/TR/BR/BL 序落模型空间并按 y=16 居中。
static void ZL2SkinViewBuildPart(CALayer *ame413_parent,
                                 CGFloat ame416_cx, CGFloat ame416_cy, CGFloat ame416_cz,
                                 CGFloat ame416_w, CGFloat ame416_h, CGFloat ame416_d,
                                 CGFloat ame416_pvx, CGFloat ame416_pvy, CGFloat ame416_pvz,
                                 CGFloat ame416_swingSign,
                                 const ZL2SkinViewRect *ame413_faces,
                                 CGFloat ame413_unit,
                                 UIImage *ame413_skin,
                                 NSMutableArray<ZL2SkinViewFace *> *ame414_out) {
    static const CGFloat AME416_UX[6][3] = {
        { 1, 0, 0}, {-1, 0, 0}, {0, 0, -1}, {0, 0, 1}, {1, 0, 0}, {1, 0, 0}};
    static const CGFloat AME416_VY[6][3] = {
        {0, -1, 0}, {0, -1, 0}, {0, -1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
    static const CGFloat AME416_NN[6][3] = {
        {0, 0, 1}, {0, 0, -1}, {-1, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}};
    static const CGFloat AME416_OFF[6][3] = {
        {0, 0, 1}, {0, 0, -1}, {-1, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}};
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        CGFloat ame416_fw = (ame413_i == 2 || ame413_i == 3) ? ame416_d : ame416_w;
        CGFloat ame416_fh = (ame413_i >= 4) ? ame416_d : ame416_h;
        CGFloat ame416_fcx = ame416_cx + AME416_OFF[ame413_i][0] * ame416_w / 2.0;
        CGFloat ame416_fcy = ame416_cy + AME416_OFF[ame413_i][1] * ame416_h / 2.0;
        CGFloat ame416_fcz = ame416_cz + AME416_OFF[ame413_i][2] * ame416_d / 2.0;

        CALayer *ame413_face = [CALayer layer];
        ame413_face.bounds = CGRectMake(0, 0, ame416_fw * ame413_unit, ame416_fh * ame413_unit);
        UIImage *ame413_img = ame413_skin ? ZL2SkinViewFaceImage(ame413_skin, ame413_faces[ame413_i]) : nil;
        if (ame413_img) {
            ame413_face.contents = (id)ame413_img.CGImage;
            ame413_face.contentsGravity = kCAGravityResize;
            // ★Task418 像素锐利：8×8 面纹理在真机 studio 幅面被放大 ~25×
            //   （unit≈13 → 头前脸 102pt ≈ 204 物理 px），CALayer 默认线性
            //   放大 = IMG_0619 雾化实锤；Nearest = skinview3d NearestFilter
            //   同源口径（马赛克像素锐利，MC 观感）
            ame413_face.magnificationFilter = kCAFilterNearest;
            ame413_face.minificationFilter = kCAFilterNearest;
        } else {
            ame413_face.backgroundColor = [UIColor colorWithWhite:0.32 alpha:1.0].CGColor;   // 占位灰面
        }
        // 光影罩（面内容之上，opacity 逐帧 = 1−shade；CALayer 无
        //   userInteractionEnabled 属性（UIView 专属）= run 42640992511 判例）
        //   ★Task418 罩层 alpha 掩膜：外层面纹理透明区不再被黑罩漏染
        //   （IMG_0619 每部位幽灵暗盒实锤之二：shade 是不透明黑子层，外层
        //   透明皮像素区照样被罩黑 = 半透明暗雾盒）。掩膜 = 面纹理自身
        //   alpha 通道；基础层（不透明皮）掩膜全不透 = 视觉零变化。
        CALayer *ame414_shade = [CALayer layer];
        ame414_shade.frame = ame413_face.bounds;
        ame414_shade.backgroundColor = [UIColor blackColor].CGColor;
        ame414_shade.opacity = 0.0;
        if (ame413_img) {
            CALayer *ame418_shadeMask = [CALayer layer];
            ame418_shadeMask.frame = ame414_shade.bounds;
            ame418_shadeMask.contents = (id)ame413_img.CGImage;
            ame414_shade.mask = ame418_shadeMask;
        }
        [ame413_face addSublayer:ame414_shade];
        [ame413_parent addSublayer:ame413_face];

        // 面记录（居中模型空间；投影/摆动/明暗逐帧复算的唯一静态源）
        ZL2SkinViewFace *ame414_rec = [[ZL2SkinViewFace alloc] init];
        ame414_rec.layer = ame413_face;
        ame414_rec.shade = ame414_shade;
        static const NSInteger AME416_SQ[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};   // TL TR BR BL
        for (NSInteger ame416_k = 0; ame416_k < 4; ame416_k++) {
            CGFloat ame416_s = (CGFloat)AME416_SQ[ame416_k][0];
            CGFloat ame416_t = (CGFloat)AME416_SQ[ame416_k][1];
            ame414_rec->corners[ame416_k][0] = ame416_fcx
                + AME416_UX[ame413_i][0] * (ame416_s * ame416_fw / 2.0)
                + AME416_VY[ame413_i][0] * (ame416_t * ame416_fh / 2.0);
            ame414_rec->corners[ame416_k][1] = (ame416_fcy
                + AME416_UX[ame413_i][1] * (ame416_s * ame416_fw / 2.0)
                + AME416_VY[ame413_i][1] * (ame416_t * ame416_fh / 2.0)) - 16.0;   // ★按 y=16 居中
            ame414_rec->corners[ame416_k][2] = ame416_fcz
                + AME416_UX[ame413_i][2] * (ame416_s * ame416_fw / 2.0)
                + AME416_VY[ame413_i][2] * (ame416_t * ame416_fh / 2.0);
        }
        ame414_rec->pivot[0] = ame416_pvx;
        ame414_rec->pivot[1] = ame416_pvy - 16.0;
        ame414_rec->pivot[2] = ame416_pvz;
        ame414_rec->normal[0] = AME416_NN[ame413_i][0];
        ame414_rec->normal[1] = AME416_NN[ame413_i][1];
        ame414_rec->normal[2] = AME416_NN[ame413_i][2];
        ame414_rec.swingSign = ame416_swingSign;
        [ame414_out addObject:ame414_rec];
    }
}

// 用皮肤整组建模（skin = nil 时灰盒占位；每次整组拆建零残留）
// ★Task416 装配表 = skinview3d model.ts 逐值换算（y_sv3d + 24 → 模型 y；
// y 再 −16 居中在投影侧统一处理）：头 (0,28) 8³ / 身 (0,18) 8×12×4 /
// 臂 (±armCx,18) pivot(±5,22) / 腿 (±1.9,6) pivot(±1.9,12)；摆动方向 =
// 右臂 +1 / 左臂 −1 / 右腿 −1 / 左腿 +1（同侧臂腿反相）。
- (void)ame413_applySkin:(UIImage *)skin {
    _ame413_currentSkin = skin;
    CALayer *ame413_stage = _ame413_stageView.layer;
    for (CALayer *ame413_sub in [ame413_stage.sublayers copy]) {
        [ame413_sub removeFromSuperlayer];
    }
    [_ame413_faceLayers removeAllObjects];

    CGFloat ame413_unit = _ame413_baseUnit;
    if (ame413_unit < 2.0) {
        [self ame413_recomputeBaseUnit];
        ame413_unit = _ame413_baseUnit;
    }

    if (skin.size.width < 1.0 || skin.size.height < 1.0) {
        // 占位灰模型（皮肤缺席诚实降级，零假纹理）
        ZL2SkinViewRect ame413_dummy[6] = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0},
                                           {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}};
        ZL2SkinViewBuildPart(ame413_stage, 0, 16, 0, 10, 32, 6, 0, 16, 0, 0.0,
                             ame413_dummy, ame413_unit, nil, _ame413_faceLayers);
        return;
    }

    BOOL ame413_legacy = (skin.size.height < skin.size.width);   // 64×32 旧版 = 左臂左腿镜像右区
    const ZL2SkinViewRect *ame413_rArmF = _ame413_slimModel ? ZL2SkinViewRArmSlimFaces : ZL2SkinViewRArmFaces;
    const ZL2SkinViewRect *ame413_lArmF = ame413_legacy ? ame413_rArmF
                                        : (_ame413_slimModel ? ZL2SkinViewLArmSlimFaces : ZL2SkinViewLArmFaces);
    const ZL2SkinViewRect *ame413_lLegF = ame413_legacy ? ZL2SkinViewRLegFaces : ZL2SkinViewLLegFaces;
    CGFloat ame413_armW = _ame413_slimModel ? 3.0 : 4.0;
    CGFloat ame413_armCx = 4.0 + ame413_armW / 2.0;   // 臂贴身侧：身半宽 4 + 臂半宽

    const ZL2SkinViewRect *ame416_faceTables[6] = {
        ZL2SkinViewHeadFaces, ZL2SkinViewBodyFaces,
        ame413_rArmF, ame413_lArmF,
        ZL2SkinViewRLegFaces, ame413_lLegF,
    };
    CGFloat ame416_parts[6][10] = {
        // cx, cy, cz, w, h, d, pivotX, pivotY, pivotZ, swingSign
        {0, 28, 0, 8, 8, 8, 0, 24, 0, 0.0},                     // 头（24..32；颈枢轴不摆）
        {0, 18, 0, 8, 12, 4, 0, 18, 0, 0.0},                    // 身（12..24）
        {-ame413_armCx, 18, 0, ame413_armW, 12, 4, -5.0, 22.0, 0, 1.0},    // 右臂（肩枢轴）
        { ame413_armCx, 18, 0, ame413_armW, 12, 4,  5.0, 22.0, 0, -1.0},   // 左臂
        {-1.9, 6, 0, 4, 12, 4, -1.9, 12.0, 0, -1.0},            // 右腿（髋枢轴）
        { 1.9, 6, 0, 4, 12, 4,  1.9, 12.0, 0, 1.0},             // 左腿
    };
    for (NSInteger ame413_i = 0; ame413_i < 6; ame413_i++) {
        CGFloat *ame416_p = ame416_parts[ame413_i];
        ZL2SkinViewBuildPart(ame413_stage,
                             ame416_p[0], ame416_p[1], ame416_p[2],
                             ame416_p[3], ame416_p[4], ame416_p[5],
                             ame416_p[6], ame416_p[7], ame416_p[8], ame416_p[9],
                             ame416_faceTables[ame413_i], ame413_unit, skin,
                             _ame413_faceLayers);
    }

    // ★Task417 第二层（skinview3d outerLayer 移植：帽/衣/袖/裤）：盒体每边
    //   +0.5 = 全维 +1.0（帽 9³/衣 9×13×5，skinview3d inflate 0.5 逐值同源）；
    //   同枢轴同摆动符号（袖随臂/裤随腿）；UV = 标准外层区块；发量/帽饰等
    //   镂空由皮肤纹理 alpha 通道经 CALayer 内容合成天然呈现；画家序 =
    //   相机 z（帽前 4.5 > 头前 4 / 帽后 −4.5 < 头后 −4，遮挡序自动正确）；
    //   legacy 64×32：左袖/左裤区块不存在 = 镜像右区（与基础层同口径）。
    const ZL2SkinViewRect *ame417_rSleeveF = _ame413_slimModel ? ZL2SkinViewRSleeveSlimFaces : ZL2SkinViewRSleeveFaces;
    const ZL2SkinViewRect *ame417_lSleeveF = ame413_legacy ? ame417_rSleeveF
                                         : (_ame413_slimModel ? ZL2SkinViewLSleeveSlimFaces : ZL2SkinViewLSleeveFaces);
    const ZL2SkinViewRect *ame417_lPantF = ame413_legacy ? ZL2SkinViewRPantFaces : ZL2SkinViewLPantFaces;
    const ZL2SkinViewRect *ame417_overlayTables[6] = {
        ZL2SkinViewHatFaces, ZL2SkinViewJacketFaces,
        ame417_rSleeveF, ame417_lSleeveF,
        ZL2SkinViewRPantFaces, ame417_lPantF,
    };
    // ★Task418 旧版诚实降级：64×32 只有帽外层区块（32..64,0..16）真实存在，
    //   衣/袖/裤外层区块不存在（读到必是基础层像素 = 幽灵盒）；现代 64×64
    //   六件全建（帽/衣/袖×2/裤×2）。
    NSInteger ame418_overlayParts = ame413_legacy ? 1 : 6;
    for (NSInteger ame413_i = 0; ame413_i < ame418_overlayParts; ame413_i++) {
        CGFloat *ame416_p = ame416_parts[ame413_i];
        ZL2SkinViewBuildPart(ame413_stage,
                             ame416_p[0], ame416_p[1], ame416_p[2],
                             ame416_p[3] + 1.0, ame416_p[4] + 1.0, ame416_p[5] + 1.0,
                             ame416_p[6], ame416_p[7], ame416_p[8], ame416_p[9],
                             ame417_overlayTables[ame413_i], ame413_unit, skin,
                             _ame413_faceLayers);
    }
    [self ame413_updateModelTransform];
    // ★Task418 装配诊断（冒烟 console/预览日志可视：现代皮面数应恒 72
    //   （36 基础 + 36 第二层）/ 旧版 42（36 + 帽 6）；unit/舞台尺寸异常 =
    //   布局面问题）
    NSLog(@"[ZL2SkinPreview] Task418: skin=%gx%g stage=%.0fx%.0f unit=%.2f faces=%lu slim=%d walk=%d overlayParts=%ld",
          skin.size.width, skin.size.height, _ame413_stageView.bounds.size.width,
          _ame413_stageView.bounds.size.height, ame413_unit,
          (unsigned long)_ame413_faceLayers.count, _ame413_slimModel, _ame414_walkOn,
          (long)ame418_overlayParts);
}

@end
