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
#import "BuildTag.h"   // ★Task421 代际角标同源常量（ame415_buildTag header 化单一事实源，与关于页版本行同一字面量）
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

// ★Task420 文件修改时间戳（本盘双源取新仲裁指纹；文件缺席 → "0"）
static NSString *ZL2SkinViewFileMTime(NSString *path) {
    if (path.length == 0) return @"0";
    NSDictionary *ame420_attr = [[NSFileManager defaultManager]
        attributesOfItemAtPath:path error:nil];
    NSDate *ame420_date = ame420_attr[NSFileModificationDate];
    return ame420_date
        ? [NSString stringWithFormat:@"%lld",
            (long long)([ame420_date timeIntervalSince1970] * 1000.0)]
        : @"0";
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
// ★Task421 内侧脸 x 修 1px：slim u 带内 [侧1 u..u+4][前 u+4..u+7][侧2 u+7..u+11]
//   [背 u+11..u+14]，skinview3d setUVs 同源（side2 = u+depth+width）——旧表
//   {48,20}/{40,52} 深入背区 1px（内侧脸左缘采到背区首列），四表同步修正。
static const ZL2SkinViewRect ZL2SkinViewRArmSlimFaces[6] = {
    {44, 20, 3, 12}, {51, 20, 3, 12}, {40, 20, 4, 12}, {47, 20, 4, 12}, {44, 16, 3, 4}, {47, 16, 3, 4}};
static const ZL2SkinViewRect ZL2SkinViewLArmSlimFaces[6] = {
    {36, 52, 3, 12}, {43, 52, 3, 12}, {32, 52, 4, 12}, {39, 52, 4, 12}, {36, 48, 3, 4}, {39, 48, 3, 4}};
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
    {44, 36, 3, 12}, {51, 36, 3, 12}, {40, 36, 4, 12}, {47, 36, 4, 12}, {44, 32, 3, 4}, {47, 32, 3, 4}};
static const ZL2SkinViewRect ZL2SkinViewLSleeveSlimFaces[6] = {
    {52, 52, 3, 12}, {59, 52, 3, 12}, {48, 52, 4, 12}, {55, 52, 4, 12}, {52, 48, 3, 4}, {55, 48, 3, 4}};

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

// ★Task419 基础层 alpha 裁切（skinview3d innerLayer transparent:false + alphaTest
//   与 MC entityCutout 同语义移植）：全息/虹彩皮肤基础层自带半透明像素，原样
//   透出 = 整模幽灵化（IMG_0627 真机实锤：身体透底见背景，与皮肤站观感相悖）。
//   基础层面重建位图：α ≥ 阈值 → 解预乘还原真色后强制不透明；α < 阈值 → 裁掉。
//   ★CG 位图 rgba 为预乘语义（rgb *= α/255），不解预乘则半透像素变暗斑。
static const CGFloat AME419_CUTOUT_MIN = 26.0;   // MC entityCutout 0.1 × 255

// ★Task422 外层暗罩不透明阈值（IMG_0667 定谳）：黑罩蒙在合成结果上 = 半透像素
//   区背景贡献被二次压暗（合成 ×(1−α·罩)），躯干两侧缝带 rgb19 < 舞台底 25
//   实证 = 「还是透明的」残存观感根源；skinview3d AmbientLight3 + 相机
//   PointLight0.6 无任何黑罩压背景机制 = 半透像素全亮透底。罩语义分级：
//   α≥180 近不透明像素照常罩（背景贡献 ≤0.29×罩 ≈ 灰阶 2.5 不可感），
//   α<180 半透区全亮 = sv3d Ambient3 观感；基础层裁切位图 0/255 掩膜不变。
static const CGFloat AME422_VEIL_MIN_ALPHA = 180.0;

static UIImage *ZL2SkinViewCutoutImage(UIImage *ame419_src) {
    if (!ame419_src.CGImage) return nil;
    size_t ame419_pw = (size_t)CGImageGetWidth(ame419_src.CGImage);
    size_t ame419_ph = (size_t)CGImageGetHeight(ame419_src.CGImage);
    if (ame419_pw < 1 || ame419_ph < 1) return nil;
    NSMutableData *ame419_buf = [NSMutableData dataWithLength:ame419_pw * ame419_ph * 4];
    CGColorSpaceRef ame419_cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ame419_ctx = CGBitmapContextCreate([ame419_buf mutableBytes],
        ame419_pw, ame419_ph, 8, ame419_pw * 4, ame419_cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(ame419_cs);
    if (!ame419_ctx) return nil;
    CGContextSetInterpolationQuality(ame419_ctx, kCGInterpolationNone);
    CGContextDrawImage(ame419_ctx, CGRectMake(0, 0, ame419_pw, ame419_ph), ame419_src.CGImage);
    UInt8 *ame419_px = [ame419_buf mutableBytes];
    for (size_t ame419_i = 0; ame419_i < ame419_pw * ame419_ph; ame419_i++) {
        UInt8 *ame419_p = ame419_px + ame419_i * 4;
        UInt8 ame419_a = ame419_p[3];
        if (ame419_a >= (UInt8)AME419_CUTOUT_MIN) {
            CGFloat ame419_k = 255.0 / (CGFloat)ame419_a;   // 解预乘还原真色
            CGFloat ame419_r = (CGFloat)ame419_p[0] * ame419_k;
            CGFloat ame419_g = (CGFloat)ame419_p[1] * ame419_k;
            CGFloat ame419_b = (CGFloat)ame419_p[2] * ame419_k;
            ame419_p[0] = (UInt8)(ame419_r > 255.0 ? 255.0 : ame419_r);
            ame419_p[1] = (UInt8)(ame419_g > 255.0 ? 255.0 : ame419_g);
            ame419_p[2] = (UInt8)(ame419_b > 255.0 ? 255.0 : ame419_b);
            ame419_p[3] = 255;
        } else {
            ame419_p[0] = ame419_p[1] = ame419_p[2] = ame419_p[3] = 0;
        }
    }
    CGImageRef ame419_out = CGBitmapContextCreateImage(ame419_ctx);
    CGContextRelease(ame419_ctx);
    if (!ame419_out) return nil;
    return [UIImage imageWithCGImage:ame419_out];
}

// ★Task422 外层罩掩膜位图（与 ZL2SkinViewCutoutImage 同管线）：α ≥
//   AME422_VEIL_MIN_ALPHA → 不透明；否则全透。掩膜层只用 alpha 通道，RGB
//   置白保证任意位图语义下掩膜可见性恒由 α 决定（kCAFilterNearest 无关，
//   掩膜 contentsGravity resize 拉伸到面幅面）。黑罩只压近不透明像素自身，
//   半透区背景贡献零损伤 = 暗带/暗环根修（scripts/task422_forensic_replica.py
//   修复前后对比图同公式先行验证）。
static UIImage *ZL2SkinViewOpaqueMaskImage(UIImage *ame422_src) {
    if (!ame422_src.CGImage) return nil;
    size_t ame422_pw = (size_t)CGImageGetWidth(ame422_src.CGImage);
    size_t ame422_ph = (size_t)CGImageGetHeight(ame422_src.CGImage);
    if (ame422_pw < 1 || ame422_ph < 1) return nil;
    NSMutableData *ame422_buf = [NSMutableData dataWithLength:ame422_pw * ame422_ph * 4];
    CGColorSpaceRef ame422_cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ame422_ctx = CGBitmapContextCreate([ame422_buf mutableBytes],
        ame422_pw, ame422_ph, 8, ame422_pw * 4, ame422_cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(ame422_cs);
    if (!ame422_ctx) return nil;
    CGContextSetInterpolationQuality(ame422_ctx, kCGInterpolationNone);
    CGContextDrawImage(ame422_ctx, CGRectMake(0, 0, ame422_pw, ame422_ph), ame422_src.CGImage);
    UInt8 *ame422_px = [ame422_buf mutableBytes];
    for (size_t ame422_i = 0; ame422_i < ame422_pw * ame422_ph; ame422_i++) {
        UInt8 *ame422_p = ame422_px + ame422_i * 4;
        if (ame422_p[3] >= (UInt8)AME422_VEIL_MIN_ALPHA) {
            ame422_p[0] = ame422_p[1] = ame422_p[2] = ame422_p[3] = 255;
        } else {
            ame422_p[0] = ame422_p[1] = ame422_p[2] = ame422_p[3] = 0;
        }
    }
    CGImageRef ame422_out = CGBitmapContextCreateImage(ame422_ctx);
    CGContextRelease(ame422_ctx);
    if (!ame422_out) return nil;
    return [UIImage imageWithCGImage:ame422_out];
}

// ★Task423 内容级模型判定（Alex/Steve 双态根修——419-d 落码面收口）：
//   yggdrasil metadata.model 只在第三方真皮链在场；crafatar/minotar/衣柜/
//   本盘缓存皮肤零 metadata = 恒 classic UV 表读 slim 内容贴图。IMG_0668
//   像素实锤（crafatar 默认 Alex 皮 fixture 同款）：slim 展开带背区只有
//   51..54 列有内容，经典背区 (52,20,4x12) 右半 54..56 = 废弃透明列，
//   α<26 裁切吃掉 = 背脸只剩 ~1.5~2 列细条（设备 30px/46px@unit≈20 复刻
//   15px/20px@unit=10 逐像素吻合）+ 臂躯 24~30px 纯背景缝。
//   判定探针 = 经典展开带专属列 alpha（右臂 x54..55 y20..32 / 左臂
//   x46..47 y52..64）：slim 展开图这两列恒废弃透明、classic 恒有内容
//   （minotar-Alex R/L opaque=0→slim；写实皮/Steve 填满→classic）。
//   64×32 旧版恒 classic（legacy 镜像口径不变）；渲染以内容为准
//   （UV 必须匹配内容展开带，metadata 仅作诊断日志参考）。
static BOOL ZL2SkinViewProbeRegionHasOpaque(UIImage *ame423_skin,
                                            CGFloat ame423_x, CGFloat ame423_y,
                                            CGFloat ame423_w, CGFloat ame423_h) {
    if (!ame423_skin.CGImage) return NO;
    size_t ame423_pw = (size_t)CGImageGetWidth(ame423_skin.CGImage);
    size_t ame423_ph = (size_t)CGImageGetHeight(ame423_skin.CGImage);
    if (ame423_pw < 1 || ame423_ph < 1) return NO;
    CGFloat ame423_s = ame423_pw / 64.0;
    NSInteger ame423_x0 = (NSInteger)(ame423_x * ame423_s);
    NSInteger ame423_y0 = (NSInteger)(ame423_y * ame423_s);
    NSInteger ame423_x1 = (NSInteger)((ame423_x + ame423_w) * ame423_s);
    NSInteger ame423_y1 = (NSInteger)((ame423_y + ame423_h) * ame423_s);
    if (ame423_x1 > (NSInteger)ame423_pw) ame423_x1 = (NSInteger)ame423_pw;
    if (ame423_y1 > (NSInteger)ame423_ph) ame423_y1 = (NSInteger)ame423_ph;
    if (ame423_x0 >= ame423_x1 || ame423_y0 >= ame423_y1) return NO;   // 64×32 左区越界 = 无探针
    NSMutableData *ame423_buf = [NSMutableData dataWithLength:ame423_pw * ame423_ph * 4];
    CGColorSpaceRef ame423_cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ame423_ctx = CGBitmapContextCreate([ame423_buf mutableBytes],
        ame423_pw, ame423_ph, 8, ame423_pw * 4, ame423_cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(ame423_cs);
    if (!ame423_ctx) return NO;
    CGContextSetInterpolationQuality(ame423_ctx, kCGInterpolationNone);
    CGContextDrawImage(ame423_ctx, CGRectMake(0, 0, ame423_pw, ame423_ph), ame423_skin.CGImage);
    UInt8 *ame423_px = [ame423_buf mutableBytes];
    BOOL ame423_found = NO;
    for (NSInteger ame423_y = ame423_y0; ame423_y < ame423_y1 && !ame423_found; ame423_y++) {
        for (NSInteger ame423_x = ame423_x0; ame423_x < ame423_x1; ame423_x++) {
            if (ame423_px[(ame423_y * (NSInteger)ame423_pw + ame423_x) * 4 + 3]
                >= (UInt8)AME419_CUTOUT_MIN) {
                ame423_found = YES;
                break;
            }
        }
    }
    CGContextRelease(ame423_ctx);
    return ame423_found;
}

// 返回 YES = slim（双探针区全透明）；YES 之外恒 classic。ame423_rHas/lHas
// 出参 = 探针命中标志（诊断日志用；-1 = 该区越界未探）。
static BOOL ZL2SkinViewDetectSlimModelFromContent(UIImage *ame423_skin,
                                                  NSInteger *ame423_rHas,
                                                  NSInteger *ame423_lHas) {
    if (ame423_rHas) *ame423_rHas = -1;
    if (ame423_lHas) *ame423_lHas = -1;
    if (!ame423_skin.CGImage) return NO;
    CGFloat ame423_w = ame423_skin.size.width;
    CGFloat ame423_h = ame423_skin.size.height;
    if (ame423_h < ame423_w) return NO;   // 64×32 旧版恒 classic
    if (ame423_w < 64.0) return NO;
    BOOL ame423_r = ZL2SkinViewProbeRegionHasOpaque(ame423_skin, 54.0, 20.0, 2.0, 12.0);
    BOOL ame423_l = ZL2SkinViewProbeRegionHasOpaque(ame423_skin, 46.0, 52.0, 2.0, 12.0);
    if (ame423_rHas) *ame423_rHas = ame423_r ? 1 : 0;
    if (ame423_lHas) *ame423_lHas = ame423_l ? 1 : 0;
    return (!ame423_r && !ame423_l);   // 双区全空 = slim（任一区有内容 = classic）
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
    CGFloat screenPts[4][2]; // ★Task424 上一帧屏幕四角（自定义关节命中拾取）
    NSInteger partIndex;     // ★Task424 所属部件（0 头/1 身/2 右臂/3 左臂/4 右腿/5 左腿）
}
@property (nonatomic, strong) CALayer *layer;    // 贴图面（shade 为其子层随动）
@property (nonatomic, strong) CALayer *shade;    // 黑色光影罩（opacity = 1−shade 逐帧）
@property (nonatomic, assign) CGFloat swingSign;       // 摆动方向（0 = 非肢体）
@property (nonatomic, assign) BOOL isOverlay;          // ★Task419 外层标志（DoubleSide 不剔除）
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

// ★Task416 光向基线（已参数化进 Task424 光影系统：az/el 反解自本向量
//   (−0.45,0.62,0.65)，|L|≈1.0047 → az=−0.606 / el=0.668，默认观感零跳变）
// ★Task424 光影系统（用户钦定：圆盘调光位 + 亮度拖条）：
//   · 光向 = 视空间方位角 az / 仰角 el（圆盘内拖动 dx→az、dy→el）；
//   · 亮度 b∈[0.5,1.5]：背光面下限 floor = clamp(0.44+(b−1)·0.55, 0.12, 0.80)，
//     罩增益 gain = clamp(2−b, 0.25, 1.8)，默认 1.15；
//   · 罩上限 0.85→0.60（IMG_0669 定谳：0.85 = 全模型 murk 主源，头侧面实测
//     ×0.524 → 新默认 ×0.756；scripts/task424_light_pose_replica.py 同公式
//     Python 先行验证：模型区均亮 150.2→166.1）。
static const CGFloat AME424_VEIL_CAP = 0.60;
static const CGFloat AME424_BRIGHT_DEFAULT = 1.15;
static const CGFloat AME424_BRIGHT_MIN = 0.5;
static const CGFloat AME424_BRIGHT_MAX = 1.5;
static const CGFloat AME424_DEF_AZ = -0.606;
static const CGFloat AME424_DEF_EL = 0.668;
// ★Task424 蹲下预置角（正 rotX = 肢端向后；Python 复刻 C 组图证）
static const CGFloat AME424_SNEAK_HEAD = -0.42;   // 头后仰补偿
static const CGFloat AME424_SNEAK_BODY = 0.30;    // 躯干前倾
static const CGFloat AME424_SNEAK_ARM = -0.15;    // 臂微前
static const CGFloat AME424_SNEAK_LEG = -0.35;    // 腿前伸下蹲
static const CGFloat AME424_SNEAK_SINK = -2.2;    // 整体下沉
// ★Task424 自定义关节拖拽限位（rad）
static const CGFloat AME424_JOINT_MAX_XZ = 1.4;
static const CGFloat AME424_JOINT_MAX_Y = 1.2;
static const CGFloat AME424_JOINT_GAIN = 0.010;
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
    UIControl *_ame414_refreshButton;
    UIControl *_ame414_spinLeftButton;
    UIControl *_ame414_spinRightButton;
    UIControl *_ame414_wardrobeAddButton;
    UIControl *_ame414_avatarButton;
    UIControl *_ame414_downloadButton;
    // ——★Task424 光影系统 + 姿态系统（用户钦定三件：圆盘调光位/亮度拖条/
    //   蹲下站立跑步+自定义关节拖拽；跑步/暂停二钮退役入四段姿态控件）——
    UISegmentedControl *_ame424_poseControl;         // 站立/蹲下/跑步/自定义
    NSInteger _ame424_poseIndex;                     // 0 站立 1 蹲下 2 跑步 3 自定义
    UIControl *_ame424_lightDial;                    // 光位圆盘（视空间 az/el）
    UIView *_ame424_dialKnob;                        // 盘内方向指示点
    UISlider *_ame424_brightSlider;                  // 亮度拖条
    UILabel *_ame424_brightLabel;                    // 亮度百分比
    CGFloat _ame424_lightAz;                         // 光向方位角（rad）
    CGFloat _ame424_lightEl;                         // 光向仰角（rad）
    CGFloat _ame424_brightness;                      // 亮度系数 [0.5,1.5]
    CGFloat _ame424_joint[6][3];                     // 自定义关节角 [rotX,rotZ,rotY]
    NSInteger _ame424_dragPart;                      // 关节拖拽命中部件（-1 = 无）
    NSLayoutConstraint *_ame424_knobLead;            // 盘内旋钮位置常量（同引用更新）
    NSLayoutConstraint *_ame424_knobTop;
    NSMutableArray<UIControl *> *_ame414_swatchButtons;      // 背景色板三枚
    NSMutableArray<UIView *> *_ame414_swatchDots;            // 色板圆点（选中描边切换）
    UIScrollView *_ame414_wardrobeStrip;                     // 衣柜缩略条
    UIStackView *_ame414_wardrobeStack;                      // 缩略条内容
    NSMutableArray<NSString *> *_ame414_wardrobeEntries;     // 衣柜文件名序
    NSLayoutConstraint *_ame414_wardrobeHeight;              // 衣柜条高（空柜塔缩 38↔0）
    NSTimer *_ame414_toastTimer;
    UILabel *_ame421_buildChip;                              // ★Task421 代际角标（预览卡右下角常驻 = 截图自带代际证据）
    BOOL _ame414_walkOn;                                     // 跑步动画开（默认开）
    NSString *_ame420_skinSource;                            // ★Task420 皮肤来源诊断（local-mtime-newer/yggdrasil-apiroot/yggdrasil-siteroot/fallback-skinfull/mojang-chain/…）
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
        // ★Task424 光影系统初值（az/el 反解自 AME416 光向基线，观感零跳变；
        //   亮度默认 1.15 = murk 降档不炸纸片感历史判据）
        _ame424_lightAz = AME424_DEF_AZ;
        _ame424_lightEl = AME424_DEF_EL;
        _ame424_brightness = AME424_BRIGHT_DEFAULT;
        _ame424_poseIndex = 0;   // 开屏站立（416 判例：站姿立正 + 慢速自转）
        _ame424_dragPart = -1;
        for (NSInteger ame424_i = 0; ame424_i < 6; ame424_i++) {
            _ame424_joint[ame424_i][0] = 0.0;
            _ame424_joint[ame424_i][1] = 0.0;
            _ame424_joint[ame424_i][2] = 0.0;
        }
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
    // ★Task424 自定义姿态长按复位（关节拖拽同一舞台；非自定义态零副作用）
    UILongPressGestureRecognizer *ame424_long =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(ame424_stageLongPressed:)];
    ame424_long.minimumPressDuration = 0.6;
    [_ame413_stageView addGestureRecognizer:ame424_long];

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

    // ★Task421 代际角标（旧构建滞留循环的结构性根修面）：Task417/419/420 三轮
    //   修复均已推送且 CI 双绿，用户实机截图连续复现旧代观感（IMG_0655/0661
    //   手臂离位+缝 30~40px = 416+ 共享角点几何数学不可能，Task420 已定谳
    //   Task415 代签名）——装机验锚设在「设置→关于」用户从不导航，代际证据
    //   必须长在截图面板自身。角标 = 预览舞台右下角常驻 10pt 半透标签，文本
    //   = ame415_buildTag（与关于页版本行同一 extern 常量，双面恒等零漂移）；
    //   用户任何一张预览截图都可判代际：无角标 = 旧构建（装新包），有角标 =
    //   本轮包在机。纯构建标识零 i18n 键（同关于页纪律），非交互不挡手势。
    _ame421_buildChip = [[UILabel alloc] init];
    _ame421_buildChip.text = ame415_buildTag;
    _ame421_buildChip.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
    _ame421_buildChip.textColor = [ZL2Theme onSurfaceVariant];
    _ame421_buildChip.alpha = 0.60;
    _ame421_buildChip.textAlignment = NSTextAlignmentRight;
    _ame421_buildChip.userInteractionEnabled = NO;
    _ame421_buildChip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame421_buildChip];
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

    // ——★Task424 姿态四段控件（站立/蹲下/跑步/自定义；跑步/暂停二钮退役入
    //   本控件 = 同屏四态直选 + 自定义关节拖拽入口；跑步语义 = 既有 walkOn
    //   正弦摆 AME416_WALK_AMP 链零改动）——
    _ame424_poseControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"ame424.skin.pose.stand", @"站立"),
        localize(@"ame424.skin.pose.sneak", @"蹲下"),
        localize(@"ame424.skin.pose.run", @"跑步"),
        localize(@"ame424.skin.pose.custom", @"自定义")]];
    _ame424_poseControl.selectedSegmentIndex = _ame424_poseIndex;
    _ame424_poseControl.translatesAutoresizingMaskIntoConstraints = NO;
    _ame424_poseControl.accessibilityLabel = localize(@"ame414.skin.run", @"跑步");
    [_ame424_poseControl addTarget:self
                            action:@selector(ame424_poseChanged:)
                  forControlEvents:UIControlEventValueChanged];
    [self addSubview:_ame424_poseControl];
    _ame414_refreshButton = [self ame414_iconButtonWithSymbol:@"arrow.clockwise" fallback:nil
                                                        label:@"ame414.skin.refresh"
                                                       block:^{ [self ame414_refreshTapped]; }];

    // ——★Task424 光影系统控件：光位圆盘 + 亮度拖条（底行左侧，色板/箭头右侧）——
    _ame424_lightDial = [[UIControl alloc] init];
    _ame424_lightDial.translatesAutoresizingMaskIntoConstraints = NO;
    _ame424_lightDial.isAccessibilityElement = YES;
    _ame424_lightDial.accessibilityLabel = localize(@"ame424.skin.light.dial", @"光位圆盘");
    _ame424_lightDial.layer.cornerRadius = 20.0;
    _ame424_lightDial.layer.borderWidth = 1.5;
    _ame424_lightDial.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    _ame424_lightDial.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.30];
    UIPanGestureRecognizer *ame424_dialPan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(ame424_dialPanned:)];
    [_ame424_lightDial addGestureRecognizer:ame424_dialPan];
    [self addSubview:_ame424_lightDial];
    _ame424_dialKnob = [[UIView alloc] init];
    _ame424_dialKnob.translatesAutoresizingMaskIntoConstraints = NO;
    _ame424_dialKnob.userInteractionEnabled = NO;
    _ame424_dialKnob.layer.cornerRadius = 5.0;
    _ame424_dialKnob.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
    [_ame424_lightDial addSubview:_ame424_dialKnob];
    [NSLayoutConstraint activateConstraints:@[
        [_ame424_dialKnob.widthAnchor constraintEqualToConstant:10.0],
        [_ame424_dialKnob.heightAnchor constraintEqualToConstant:10.0],
    ]];

    _ame424_brightSlider = [[UISlider alloc] init];
    _ame424_brightSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _ame424_brightSlider.minimumValue = AME424_BRIGHT_MIN;
    _ame424_brightSlider.maximumValue = AME424_BRIGHT_MAX;
    _ame424_brightSlider.value = _ame424_brightness;
    _ame424_brightSlider.accessibilityLabel = localize(@"ame424.skin.light.brightness", @"亮度");
    [_ame424_brightSlider addTarget:self
                             action:@selector(ame424_brightnessChanged:)
                   forControlEvents:UIControlEventValueChanged];
    [self addSubview:_ame424_brightSlider];

    _ame424_brightLabel = [[UILabel alloc] init];
    _ame424_brightLabel.font = [ZL2Theme fontLabelMedium];
    _ame424_brightLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ame424_brightLabel.textAlignment = NSTextAlignmentCenter;
    _ame424_brightLabel.numberOfLines = 1;
    _ame424_brightLabel.userInteractionEnabled = NO;
    _ame424_brightLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_ame424_brightLabel];

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
        // 顶行：提示语左 / 姿态四段 + 刷新右（★Task424 run/pause 退役入四段）
        [_ame413_hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame413_hintLabel.centerYAnchor constraintEqualToAnchor:_ame424_poseControl.centerYAnchor],
        [_ame413_hintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_ame424_poseControl.leadingAnchor constant:-4.0],
        [_ame414_refreshButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [_ame424_poseControl.trailingAnchor constraintEqualToAnchor:_ame414_refreshButton.leadingAnchor constant:-6.0],
        [_ame424_poseControl.topAnchor constraintEqualToAnchor:self.topAnchor constant:6.0],
        [_ame424_poseControl.heightAnchor constraintEqualToConstant:28.0],

        // 舞台：顶行之下 / 衣柜条之上（顶锚在此接入顶行）
        [_ame413_stageView.topAnchor constraintEqualToAnchor:_ame424_poseControl.bottomAnchor constant:2.0],
        [_ame413_stageView.bottomAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.topAnchor constant:-4.0],

        // 衣柜条（空柜塌缩零占位：高度常量持引用 38↔0）
        [_ame414_wardrobeStrip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame414_wardrobeStrip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],

        // 底行：★Task424 光位圆盘 + 亮度拖条左 / 色板右 / 箭头右
        [_ame424_lightDial.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame424_lightDial.centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame424_lightDial.widthAnchor constraintEqualToConstant:40.0],
        [_ame424_lightDial.heightAnchor constraintEqualToConstant:40.0],
        [_ame424_brightSlider.leadingAnchor constraintEqualToAnchor:_ame424_lightDial.trailingAnchor constant:8.0],
        [_ame424_brightSlider.centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame424_brightSlider.widthAnchor constraintEqualToConstant:110.0],
        [_ame424_brightLabel.leadingAnchor constraintEqualToAnchor:_ame424_brightSlider.trailingAnchor constant:6.0],
        [_ame424_brightLabel.centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame424_brightLabel.widthAnchor constraintEqualToConstant:40.0],
        [_ame414_spinRightButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [_ame414_spinLeftButton.trailingAnchor constraintEqualToAnchor:_ame414_spinRightButton.leadingAnchor constant:-4.0],
        [_ame414_spinLeftButton.topAnchor constraintEqualToAnchor:_ame414_wardrobeStrip.bottomAnchor constant:4.0],
        [_ame414_swatchButtons[2].trailingAnchor constraintEqualToAnchor:_ame414_spinLeftButton.leadingAnchor constant:-8.0],
        [_ame414_swatchButtons[1].trailingAnchor constraintEqualToAnchor:_ame414_swatchButtons[2].leadingAnchor constant:-6.0],
        [_ame414_swatchButtons[0].trailingAnchor constraintEqualToAnchor:_ame414_swatchButtons[1].leadingAnchor constant:-6.0],
        [_ame414_swatchButtons[0].leadingAnchor constraintGreaterThanOrEqualToAnchor:_ame424_brightLabel.trailingAnchor constant:8.0],

        // 动作行：衣柜/头像/下载 左对齐排布，贴底
        //   ★Task422 竖直补锚（IMG_0667 + harness 双截图定谳）：下载/头像两钮
        //   此前仅 leading 链无竖直锚 = 垂直欠定 Auto Layout 落 y=0 顶行叠在
        //   「拖动旋转·捏合缩放」提示上（📥/👤 与提示文字重叠实拍病灶）；
        //   同排基准 = 衣柜钮（top/bottom 双钉同 28pt 槽位）centerY。
        [_ame414_downloadButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_ame414_avatarButton.leadingAnchor constraintEqualToAnchor:_ame414_downloadButton.trailingAnchor constant:14.0],
        [_ame414_wardrobeAddButton.leadingAnchor constraintEqualToAnchor:_ame414_avatarButton.trailingAnchor constant:14.0],
        [_ame414_downloadButton.centerYAnchor constraintEqualToAnchor:_ame414_wardrobeAddButton.centerYAnchor],
        [_ame414_avatarButton.centerYAnchor constraintEqualToAnchor:_ame414_wardrobeAddButton.centerYAnchor],
        [_ame414_wardrobeAddButton.topAnchor constraintEqualToAnchor:_ame414_spinLeftButton.bottomAnchor constant:4.0],
        [_ame414_wardrobeAddButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6.0],
        [_ame414_spinRightButton.centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[0].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[1].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],
        [_ame414_swatchButtons[2].centerYAnchor constraintEqualToAnchor:_ame414_spinLeftButton.centerYAnchor],

        // 状态/加载指示居中于舞台
        // ★Task421 代际角标：舞台右下角常驻（stageView 底 = 衣柜条顶−4 上方，
        //   不与任何控件/手势重叠；alpha 0.60 半透不抢视觉）
        [_ame421_buildChip.trailingAnchor constraintEqualToAnchor:_ame413_stageView.trailingAnchor constant:-8.0],
        [_ame421_buildChip.bottomAnchor constraintEqualToAnchor:_ame413_stageView.bottomAnchor constant:-4.0],
        [_ame421_buildChip.leadingAnchor constraintGreaterThanOrEqualToAnchor:_ame413_stageView.leadingAnchor constant:8.0],
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
    [self ame424_syncPoseUI];
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

// ★Task424 姿态/光影 UI 同步（四段选中态 + 盘内旋钮位置 + 亮度百分比；
//   旋钮位置映射与 Python 复刻 B 组设计稿同源：r = R·(1−(el−5°)/75°)，
//   方位角 az 以盘心正上为 0 顺时针）
- (void)ame424_syncPoseUI {
    if (!_ame414_controlsBuilt) return;
    _ame424_poseControl.selectedSegmentIndex = _ame424_poseIndex;   // iOS14 无 animated 变体（CI 932 编译雷判例）
    CGFloat ame424_r = 12.0 * (1.0 - (_ame424_lightEl - 0.087) / 1.309);   // 5°..80° → 12..0（盘半径 20−旋钮 5−边 3 = 12 内）
    if (ame424_r < 0.0) ame424_r = 0.0;
    if (ame424_r > 12.0) ame424_r = 12.0;
    CGFloat ame424_kx = 15.0 + sin(_ame424_lightAz) * ame424_r - 5.0;
    CGFloat ame424_ky = 15.0 - cos(_ame424_lightAz) * ame424_r - 5.0;
    if (_ame424_knobLead.active) {   // ★同引用更新（每次重建约束会移除宽高链，判例式防抖）
        _ame424_knobLead.constant = ame424_kx;
        _ame424_knobTop.constant = ame424_ky;
    } else {
        _ame424_knobLead = [_ame424_dialKnob.leadingAnchor constraintEqualToAnchor:_ame424_lightDial.leadingAnchor constant:ame424_kx];
        _ame424_knobTop = [_ame424_dialKnob.topAnchor constraintEqualToAnchor:_ame424_lightDial.topAnchor constant:ame424_ky];
        _ame424_knobLead.priority = UILayoutPriorityRequired - 1;   // 防与宽高链偶发冲突
        _ame424_knobTop.priority = UILayoutPriorityRequired - 1;
        [_ame424_knobLead setActive:YES];
        [_ame424_knobTop setActive:YES];
    }
    _ame424_brightLabel.text = [NSString stringWithFormat:@"%ld%%",
        (long)round(_ame424_brightness * 100.0)];
}

// ★Task424 姿态切换（跑步/暂停二钮退役语义收编：站立 = 停摆保自转；
//   自定义 = 停自转 + 提示语换关节拖拽口径 + 长按复位）
- (void)ame424_poseChanged:(UISegmentedControl *)seg {
    _ame424_poseIndex = seg.selectedSegmentIndex;
    _ame414_walkOn = (_ame424_poseIndex == 2);   // 跑步 = 既有正弦摆链
    _ame414_autoSpin = (_ame424_poseIndex != 3); // 自定义停自转防拖拽干扰
    _ame413_hintLabel.text = (_ame424_poseIndex == 3)
        ? localize(@"ame424.skin.hint.custom", @"拖关节调姿态 · 长按复位")
        : localize(@"ame412.skin.preview.hint", @"拖动旋转 · 捏合缩放");
    [self ame424_syncPoseUI];
}

// ★Task424 亮度拖条（floor/gain 双通道公式见 AME424 常量区注释）
- (void)ame424_brightnessChanged:(UISlider *)slider {
    CGFloat ame424_v = slider.value;
    if (!isfinite(ame424_v)) return;   // 415a NaN 卫兵同族
    _ame424_brightness = fmin(AME424_BRIGHT_MAX, fmax(AME424_BRIGHT_MIN, ame424_v));
    [self ame424_syncPoseUI];
    [self ame413_updateModelTransform];
}

// ★Task424 光位圆盘拖动（dx→方位角、dy→仰角；盘内旋钮随动）
- (void)ame424_dialPanned:(UIPanGestureRecognizer *)pan {
    CGPoint ame424_t = [pan translationInView:_ame424_lightDial];
    [pan setTranslation:CGPointZero inView:_ame424_lightDial];
    if (!isfinite(ame424_t.x) || !isfinite(ame424_t.y)) return;
    _ame424_lightAz += ame424_t.x * 0.010;
    _ame424_lightEl -= ame424_t.y * 0.010;
    if (_ame424_lightEl > 1.396) _ame424_lightEl = 1.396;    // 80° 顶光上限
    if (_ame424_lightEl < 0.087) _ame424_lightEl = 0.087;    // 5° 掠射下限
    if (_ame424_lightAz > M_PI) _ame424_lightAz -= 2.0 * M_PI;
    if (_ame424_lightAz < -M_PI) _ame424_lightAz += 2.0 * M_PI;
    [self ame424_syncPoseUI];
    [self ame413_updateModelTransform];
}

// ★Task424 自定义关节命中拾取：上一帧屏幕四角 AABB（仅基础层面），
// 含点优先，否则取最近盒心（60pt 阈内）
- (NSInteger)ame424_partAtPoint:(CGPoint)ame424_p {
    // screenPts 存的是「舞台中心相对偏移」（与投影 sy=-vy 同系），拾取点先转同系
    CGPoint ame424_q = CGPointMake(ame424_p.x - CGRectGetMidX(_ame413_stageView.bounds),
                                   ame424_p.y - CGRectGetMidY(_ame413_stageView.bounds));
    NSInteger ame424_hit = -1;
    CGFloat ame424_best = 60.0 * 60.0;
    for (ZL2SkinViewFace *ame414_f in _ame413_faceLayers) {
        if (ame414_f.isOverlay || ame414_f.layer.hidden) continue;
        CGFloat ame424_x0 = ame414_f->screenPts[0][0], ame424_x1 = ame414_f->screenPts[0][0];
        CGFloat ame424_y0 = ame414_f->screenPts[0][1], ame424_y1 = ame414_f->screenPts[0][1];
        for (NSInteger ame424_k = 1; ame424_k < 4; ame424_k++) {
            ame424_x0 = fmin(ame424_x0, ame414_f->screenPts[ame424_k][0]);
            ame424_x1 = fmax(ame424_x1, ame414_f->screenPts[ame424_k][0]);
            ame424_y0 = fmin(ame424_y0, ame414_f->screenPts[ame424_k][1]);
            ame424_y1 = fmax(ame424_y1, ame414_f->screenPts[ame424_k][1]);
        }
        CGFloat ame424_cx = (ame424_x0 + ame424_x1) / 2.0;
        CGFloat ame424_cy = (ame424_y0 + ame424_y1) / 2.0;
        CGFloat ame424_d = (ame424_q.x - ame424_cx) * (ame424_q.x - ame424_cx)
                         + (ame424_q.y - ame424_cy) * (ame424_q.y - ame424_cy);
        BOOL ame424_inside = ame424_q.x >= ame424_x0 && ame424_q.x <= ame424_x1
                          && ame424_q.y >= ame424_y0 && ame424_q.y <= ame424_y1;
        if (ame424_inside || ame424_d < ame424_best) {
            ame424_best = ame424_inside ? 0.0 : ame424_d;
            ame424_hit = ame414_f->partIndex;
        }
    }
    return ame424_hit;
}

// ★Task424 自定义关节拖拽（竖直→rotX；水平→头 rotY / 其余 rotZ；
//   空白处拖动 = 旋转模型沿用既有轨道）
- (void)ame424_applyJointDrag:(UIPanGestureRecognizer *)pan {
    CGPoint ame424_t = [pan translationInView:_ame413_stageView];
    [pan setTranslation:CGPointZero inView:_ame413_stageView];
    if (!isfinite(ame424_t.x) || !isfinite(ame424_t.y)) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        _ame424_dragPart = [self ame424_partAtPoint:[pan locationInView:_ame413_stageView]];
    }
    if (_ame424_dragPart < 0 || pan.state == UIGestureRecognizerStateEnded
        || pan.state == UIGestureRecognizerStateCancelled) {
        if (_ame424_dragPart < 0) {
            _ame413_yaw += ame424_t.x * 0.008;
            _ame413_pitch += ame424_t.y * 0.008;
            if (_ame413_pitch > 0.9) _ame413_pitch = 0.9;
            if (_ame413_pitch < -0.9) _ame413_pitch = -0.9;
            _ame414_spinTarget = _ame413_yaw;
        }
        if (pan.state != UIGestureRecognizerStateChanged) _ame424_dragPart = -1;
        [self ame413_updateModelTransform];
        return;
    }
    CGFloat ame424_dx = fmax(-AME424_JOINT_MAX_XZ,
        fmin(AME424_JOINT_MAX_XZ, _ame424_joint[_ame424_dragPart][0] + ame424_t.y * AME424_JOINT_GAIN));
    CGFloat ame424_dz = fmax(-AME424_JOINT_MAX_Y,
        fmin(AME424_JOINT_MAX_Y, _ame424_joint[_ame424_dragPart][1] + ame424_t.x * AME424_JOINT_GAIN));
    CGFloat ame424_dy = fmax(-AME424_JOINT_MAX_Y,
        fmin(AME424_JOINT_MAX_Y, _ame424_joint[_ame424_dragPart][2] + ame424_t.x * AME424_JOINT_GAIN));
    _ame424_joint[_ame424_dragPart][0] = ame424_dx;
    _ame424_joint[_ame424_dragPart][1] = (_ame424_dragPart == 0) ? _ame424_joint[_ame424_dragPart][1] : ame424_dz;
    _ame424_joint[_ame424_dragPart][2] = (_ame424_dragPart == 0) ? ame424_dy : _ame424_joint[_ame424_dragPart][2];
    [self ame413_updateModelTransform];
}

// ★Task424 长按复位关节（自定义模式；其余姿态零副作用）
- (void)ame424_stageLongPressed:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan || _ame424_poseIndex != 3) return;
    for (NSInteger ame424_i = 0; ame424_i < 6; ame424_i++) {
        _ame424_joint[ame424_i][0] = 0.0;
        _ame424_joint[ame424_i][1] = 0.0;
        _ame424_joint[ame424_i][2] = 0.0;
    }
    [self ame413_updateModelTransform];
    [self ame414_toast:localize(@"ame424.skin.pose.reset", @"姿态已复位")];
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

#pragma mark 皮肤站动作（★Task414 + ★Task424 姿态/光影）

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
    // ★Task424 邻修（CI 1170 警告定谳 = Task414 存量类型混用潜在雷）：UIView
    //   赋 UIViewController* 且向 UIView 发 parentViewController/present 均为
    //   未实现选择器 = 点下载钮即崩风险；改走 nextResponder 响应链寻 VC。
    UIResponder *ame414_responder = self;
    while (ame414_responder && ![ame414_responder isKindOfClass:[UIViewController class]]) {
        ame414_responder = [ame414_responder nextResponder];
    }
    UIViewController *ame414_anchor = (UIViewController *)ame414_responder;
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
    // ★Task420 皮肤文件指纹入幂等闸：账户身份未变但 skinfull/缓存被登录链
    //   （行刷新 ame133）/预览刷新链改写时，预览自动跟随重载——杜绝「账户
    //   未换 → 闸门拦下 → 舞台残留他皮」（IMG_0655 头像猫娘/模型 Alex 同屏
    //   矛盾的闸门面成因）。
    NSString *ame420_stamp = [NSString stringWithFormat:@"%@|%@",
        ZL2SkinViewFileMTime(ZL2SkinViewFullSkinPath(ame413_accountId)),
        ZL2SkinViewFileMTime([[ZL2SkinViewCacheDir()
            stringByAppendingPathComponent:ZL2SkinViewSafeName(
                ame413_accountId ?: ame413_pid ?: ame413_name ?: @"anonymous")]
            stringByAppendingPathExtension:@"png"])];
    NSString *ame413_key = [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
                            ame413_accountId ?: @"-", ame413_pid ?: @"-",
                            ame413_name ?: @"-", ame413_server ?: @"-",
                            ame420_stamp];
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

    // ①★Task420 本盘双源取新（mtime 仲裁）：skinfull = 登录链最后成功认证
    //   落盘真皮（Documents/avatars/skinfull-<accountId>.png）；缓存 = 预览链
    //   最近网络刷新产物（Caches/skins/<key>.png）。旧版「先缓存后全皮」固定
    //   序在「切换角色/换皮后 skinfull 已更新」场景把陈旧缓存顶在真皮前面 =
    //   IMG_0655 头像猫娘/模型 Alex 同屏矛盾实锤（账户级缓存键 × 角色级内容）。
    //   mtime 取新 = 两源都是新近真数据的确定性仲裁；并列/仅一源在场 →
    //   skinfull 优先 = 登录链权威。
    NSString *ame413_fullPath = ZL2SkinViewFullSkinPath(accountId);
    if (!_ame414_refreshBypass) {
        UIImage *ame420_local = [self ame420_newerLocalSkinWithCachePath:ame413_cachePath
                                                               fullPath:ame413_fullPath];
        if (ame420_local) {
            _ame420_skinSource = @"local-mtime-newer";
            _ame414_refreshBypass = NO;
            [self ame413_applySkin:ame420_local];
            return;
        }
    }
    _ame414_refreshBypass = NO;

    // ③ 网络链：authserver 在场 = 第三方（authlib-injector）→ yggdrasil 真皮链
    //   （crafatar/minotar 只认 Mojang，第三方 username 恒回默认 Alex =
    //   IMG_0596「为什么是alex的皮肤」根因，第三方路径禁入）；否则 Mojang/
    //   微软/本地 → crafatar(profileId) → minotar(username)。
    //   ★Task423 两道禁入补严：①三方 authserver 在场但 profileId 缺失 →
    //   直接真皮回退（旧口径落进 mojang-chain = crafatar/minotar 恒回默认
    //   皮毒缓存，IMG_0668 毒源实链）；②alex 哨兵 ...001 与 steve 哨兵同款
    //   禁入 crafatar（离线默认皮哨兵不是真 UUID，crafatar 只会回默认皮）。
    if (authserver.length > 0 && profileId.length > 0) {
        [self ame413_fetchYggdrasilSkinWithServer:authserver
                                        profileId:profileId
                                        accountId:accountId
                                        cachePath:ame413_cachePath];
        return;
    }
    if (authserver.length > 0) {
        [_ame413_spinner stopAnimating];
        _ame420_skinSource = @"yggdrasil-no-profile-fallback";
        [self ame420_fallbackToLocalFullSkin:accountId];
        return;
    }

    NSMutableArray<NSString *> *ame413_urls = [NSMutableArray array];
    // ★Task423 哨兵双禁：steve ...000（既有）+ alex ...001（ame224 离线默认皮
    //   sentinel 同族禁入）——哨兵 UUID 送 crafatar 恒得默认皮毒缓存。
    if (profileId.length == 36
        && ![profileId isEqualToString:@"00000000-0000-0000-0000-000000000000"]
        && ![profileId isEqualToString:@"00000000-0000-0000-0000-000000000001"]) {
        [ame413_urls addObject:[NSString stringWithFormat:@"https://crafatar.com/skins/%@", profileId]];
    }
    if (username.length > 0) {
        [ame413_urls addObject:[NSString stringWithFormat:@"https://minotar.net/skin/%@", username]];
    }
    if (ame413_urls.count == 0) {
        [self ame420_fallbackToLocalFullSkin:accountId];
        return;
    }
    _ame413_spinner.hidden = NO;
    [_ame413_spinner startAnimating];
    [self ame413_tryURLAtIndex:0 urls:ame413_urls cachePath:ame413_cachePath];
}

// ★Task420 本盘双源取新（mtime 仲裁；并列/仅一源在场 → skinfull 优先 = 登录
//   链权威；1s 容差内并列视为同时写入 → skinfull）。skinfull 合法性同
//   ame133 口径（width ≥ 64 且 1:1 或 1:2）。
// ★Task423 缓存来源 sidecar 仲裁降毒：IMG_0668 毒源实锤——crafatar 对未知
//   UUID 恒回默认 Alex（fixture 取证 RArm-back avg α=127）只写账户级缓存
//   （不写 avatar/skinfull）→ 新鲜 mtime 压过登录链真皮 → 舞台锁死他皮 +
//   头像真皮同屏矛盾。降毒口径：缓存仅持 sidecar=yggdrasil（签名 URL 真
//   皮链）才有资格凭 mtime 胜过有效 skinfull；mojang-chain（crafatar/
//   minotar 用户名回退链）与历史无 sidecar 缓存一律输给有效 skinfull
//   （Task420 前 yggdrasil 缓存也写 skinfull 同刻 = 零真损）。
- (NSString *)ame423_cacheProvenanceAtPath:(NSString *)cachePath {
    if (cachePath.length == 0) return nil;
    NSString *ame423_srcPath = [cachePath stringByAppendingPathExtension:@"src"];
    NSData *ame423_d = [NSData dataWithContentsOfFile:ame423_srcPath];
    NSString *ame423_s = [[NSString alloc] initWithData:ame423_d encoding:NSUTF8StringEncoding];
    return [ame423_s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (UIImage *)ame420_newerLocalSkinWithCachePath:(NSString *)cachePath
                                        fullPath:(NSString *)fullPath {
    UIImage *ame420_cache = (cachePath.length > 0)
        ? [UIImage imageWithContentsOfFile:cachePath] : nil;
    UIImage *ame420_full = (fullPath.length > 0)
        ? [UIImage imageWithContentsOfFile:fullPath] : nil;
    if (ame420_full.size.width < 64 ||
        !(ame420_full.size.height == ame420_full.size.width ||
          ame420_full.size.height * 2 == ame420_full.size.width)) {
        ame420_full = nil;   // 全皮合法性同 ame133 口径，脏文件当缺席
    }
    if (!ame420_cache) return ame420_full;
    if (!ame420_full) return ame420_cache;
    // ★Task423 降毒闸：非 yggdrasil 来源缓存（mojang-chain/历史无 sidecar）
    //   永不压过有效 skinfull = 毒缓存失去 mtime 优势。
    NSString *ame423_prov = [self ame423_cacheProvenanceAtPath:cachePath];
    if (![ame423_prov isEqualToString:@"yggdrasil"]) return ame420_full;
    NSFileManager *ame420_fm = [NSFileManager defaultManager];
    NSDate *ame420_cd = [ame420_fm attributesOfItemAtPath:cachePath error:nil][NSFileModificationDate];
    NSDate *ame420_fd = [ame420_fm attributesOfItemAtPath:fullPath error:nil][NSFileModificationDate];
    if (ame420_fd && (!ame420_cd || [ame420_fd compare:ame420_cd] != NSOrderedAscending)) {
        return ame420_full;   // 全皮更新或并列 → 登录链权威
    }
    return ame420_cache;
}

// 第三方真皮链（★Task420 双根探测）：<apiRoot>sessionserver/session/minecraft/
// profile/<无连字符UUID>（authlib-injector 标准 = 登录链 ame133 同款拼法，
// 同站同资源）主查；skinURL 空 → 剥 /api/yggdrasil 站点根（Task224 判例兼容）
// 备查；两根全空 → skinfull 真皮回退。命中 → properties[textures].value
// （base64）→ textures.SKIN.url（一次性签名 URL 立即下载，Task133 判例）+
// metadata.model = slim 细臂模型；全皮落盘 + 预览缓存 + 头像随新三写。
- (void)ame413_fetchYggdrasilSkinWithServer:(NSString *)server
                                   profileId:(NSString *)profileId
                                   accountId:(NSString *)accountId
                                   cachePath:(NSString *)cachePath {
    NSString *ame420_apiRoot = [server copy];
    if (![ame420_apiRoot hasSuffix:@"/"]) {
        ame420_apiRoot = [ame420_apiRoot stringByAppendingString:@"/"];
    }
    NSString *ame420_siteRoot = [server copy];
    NSRange ame420_api = [ame420_siteRoot rangeOfString:@"/api/yggdrasil"];
    if (ame420_api.location != NSNotFound) {
        ame420_siteRoot = [ame420_siteRoot substringToIndex:ame420_api.location];
    }
    if (![ame420_siteRoot hasSuffix:@"/"]) {
        ame420_siteRoot = [ame420_siteRoot stringByAppendingString:@"/"];
    }
    NSString *ame420_undashed = [profileId stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *ame420_primary = [NSString stringWithFormat:
        @"%@sessionserver/session/minecraft/profile/%@", ame420_apiRoot, ame420_undashed];
    NSString *ame420_fallback = [NSString stringWithFormat:
        @"%@sessionserver/session/minecraft/profile/%@", ame420_siteRoot, ame420_undashed];
    [self ame420_fetchYggdrasilProfileAtIndex:0
                                         urls:@[ame420_primary, ame420_fallback]
                                    accountId:accountId
                                    cachePath:cachePath];
}

// ★Task420 yggdrasil profile 双根逐级回退（方法递归 = run 42487051782 保留环
//   判例规避；skinURL 空 = 该根 404/未挂载 → 下探；两根全空 = profile 缺席
//   /皮肤未设 → 真皮回退，舞台绝不残留他皮）。
- (void)ame420_fetchYggdrasilProfileAtIndex:(NSUInteger)ame420_idx
                                       urls:(NSArray<NSString *> *)ame420_urls
                                   accountId:(NSString *)accountId
                                   cachePath:(NSString *)cachePath {
    if (ame420_idx >= ame420_urls.count) {
        [_ame413_spinner stopAnimating];
        _ame420_skinSource = @"yggdrasil-both-roots-empty";
        [self ame420_fallbackToLocalFullSkin:accountId];
        return;
    }
    _ame413_spinner.hidden = NO;
    [_ame413_spinner startAnimating];
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *ame413_task =
        [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:ame420_urls[ame420_idx]]
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
                [inner ame420_fetchYggdrasilProfileAtIndex:ame420_idx + 1
                                                      urls:ame420_urls
                                                  accountId:accountId
                                                  cachePath:cachePath];
                return;
            }
            inner->_ame420_skinSource = (ame420_idx == 0)
                ? @"yggdrasil-apiroot" : @"yggdrasil-siteroot";
            [inner ame413_downloadSkinAtURL:ame413_skinURL
                                   accountId:accountId
                                   slim:(ame413_model.length > 0 && [ame413_model isEqualToString:@"slim"])
                                   cachePath:cachePath];
        });
    }];
    [ame413_task resume];
}

// ★Task420 失败回退真皮：网络链全败时舞台绝不残留他皮/陈旧内容——skinfull
//   在场即回退应用（登录链最后一次成功认证的真皮 = 本地最优真值）；真皮亦
//   缺席才落「加载失败」占位（灰模诚实降级口径不变）。
- (void)ame420_fallbackToLocalFullSkin:(NSString *)accountId {
    NSString *ame420_fullPath = ZL2SkinViewFullSkinPath(accountId);
    UIImage *ame420_full = (ame420_fullPath.length > 0)
        ? [UIImage imageWithContentsOfFile:ame420_fullPath] : nil;
    if (ame420_full.size.width >= 64) {
        _ame420_skinSource = @"fallback-skinfull";
        [self ame413_applySkin:ame420_full];
        return;
    }
    [self ame413_showUnavailable];
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
                // ★Task423 来源 sidecar：yggdrasil 签名 URL 真皮链 = 唯一
                //   可凭 mtime 与 skinfull 仲裁的缓存来源（降毒闸白名单）。
                [[NSString stringWithFormat:@"yggdrasil\n"]
                    writeToFile:[cachePath stringByAppendingPathExtension:@"src"]
                     atomically:YES encoding:NSUTF8StringEncoding error:nil];
                NSString *ame413_fullPath = ZL2SkinViewFullSkinPath(accountId);
                if (ame413_fullPath) [data writeToFile:ame413_fullPath atomically:YES];   // 全皮落盘（离线真皮）
                // ★Task420 头像随新：新皮脸部 8×8 落 ame133 skin- 键（
                //   profilePicURL 指向的本地文件内容更新；AvatarManager 对
                //   file:// 的后台静默刷新一拍内自愈）= 头像与模型同源一致，
                //   杜绝 IMG_0655「头像猫娘/模型 Alex」同屏矛盾。
                UIImage *ame420_face = ZL2SkinViewHeadAvatarImage(ame413_skin);
                NSString *ame420_avatarPath = [ThirdPartyAuthenticator
                    ame420_skinAvatarPathForAccountId:accountId];
                if (ame420_face && ame420_avatarPath.length > 0) {
                    NSData *ame420_facePNG = UIImagePNGRepresentation(ame420_face);
                    if (ame420_facePNG.length > 0) {
                        [ame420_facePNG writeToFile:ame420_avatarPath atomically:YES];
                    }
                }
                inner->_ame413_slimModel = slim;
                [inner ame413_applySkin:ame413_skin];
            } else {
                [inner ame420_fallbackToLocalFullSkin:accountId];
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
        _ame420_skinSource = @"mojang-chain-exhausted";
        [self ame420_fallbackToLocalFullSkin:_ame414_lastAccountId];
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
                // ★Task423 来源 sidecar：mojang-chain（crafatar/minotar 用户名
                //   回退链，未知名/未知 UUID 恒回默认皮 = 毒源族）——降毒闸凭
                //   此永不压过有效 skinfull（IMG_0668 锁死循环根断）。
                [[NSString stringWithFormat:@"mojang-chain\n"]
                    writeToFile:[ame413_cachePath stringByAppendingPathExtension:@"src"]
                     atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [strongSelf->_ame413_spinner stopAnimating];
                strongSelf->_ame420_skinSource = @"mojang-chain";
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
    // ★Task424 自定义模式 = 关节拖拽优先（命中部件）；空白处仍旋转模型
    if (_ame424_poseIndex == 3) {
        [self ame424_applyJointDrag:pan];
        return;
    }
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
    // ★Task424 姿态系统：每部件关节角（跑步 = 既有正弦摆链零改动；蹲下 =
    //   预置角 + 整体下沉；自定义 = _ame424_joint 直控）
    CGFloat ame424_rx[6] = {0, 0, 0, 0, 0, 0};
    CGFloat ame424_tz[6] = {0, 0, 0, 0, 0, 0};
    CGFloat ame424_ty[6] = {0, 0, 0, 0, 0, 0};
    CGFloat ame424_yoff[6] = {0, 0, 0, 0, 0, 0};
    if (_ame424_poseIndex == 1) {   // 蹲下（AME424_SNEAK_* 预置角）
        ame424_rx[0] = AME424_SNEAK_HEAD;
        ame424_rx[1] = AME424_SNEAK_BODY;
        ame424_rx[2] = AME424_SNEAK_ARM;
        ame424_rx[3] = AME424_SNEAK_ARM;
        ame424_rx[4] = AME424_SNEAK_LEG;
        ame424_rx[5] = AME424_SNEAK_LEG;
        for (NSInteger ame424_i = 0; ame424_i < 6; ame424_i++) ame424_yoff[ame424_i] = AME424_SNEAK_SINK;
    } else if (_ame424_poseIndex == 3) {   // 自定义关节
        for (NSInteger ame424_i = 0; ame424_i < 6; ame424_i++) {
            ame424_rx[ame424_i] = _ame424_joint[ame424_i][0];
            ame424_tz[ame424_i] = _ame424_joint[ame424_i][1];
            ame424_ty[ame424_i] = _ame424_joint[ame424_i][2];
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (ZL2SkinViewFace *ame414_f in _ame413_faceLayers) {
        NSInteger ame424_part = ame414_f->partIndex;
        CGFloat ame416_th = (_ame424_poseIndex == 1 || _ame424_poseIndex == 3)
            ? ame424_rx[ame424_part]                                   // 蹲下/自定义 = 关节角
            : ame416_swing * ame414_f.swingSign;                       // 站立/跑步 = 既有摆链
        CGFloat ame416_tz = ame424_tz[ame424_part];
        CGFloat ame416_ty = ame424_ty[ame424_part];
        CGFloat ame416_ct = cos(ame416_th), ame416_st = sin(ame416_th);
        CGFloat ame416_cz2 = cos(ame416_tz), ame416_sz2 = sin(ame416_tz);
        // ——法线：关节（rotY→rotX→rotZ）→ 随旋（剔除判定 + 明暗共用）——
        CGFloat ame416_nx = ame414_f->normal[0], ame416_ny = ame414_f->normal[1], ame416_nz = ame414_f->normal[2];
        if (ame416_ty != 0.0) Ame416RotY(ame416_ty, &ame416_nx, &ame416_nz);
        if (ame416_th != 0.0) Ame416RotX(ame416_th, &ame416_ny, &ame416_nz);
        if (ame416_tz != 0.0) {
            CGFloat ame424_tnx = ame416_nx * ame416_cz2 - ame416_ny * ame416_sz2;
            ame416_ny = ame416_nx * ame416_sz2 + ame416_ny * ame416_cz2;
            ame416_nx = ame424_tnx;
        }
        Ame416RotY(_ame413_yaw, &ame416_nx, &ame416_nz);
        Ame416RotX(_ame413_pitch, &ame416_ny, &ame416_nz);
        BOOL ame416_backface = (ame416_nz <= 0.0);
        // ★Task419 外层 DoubleSide（skinview3d outerLayer side:DoubleSide 同源）：
        //   半透明底（全息皮）下透出外层背面镜像渐变 = 真·全息观感；仿射映射
        //   对负 det 天然输出镜像 = 背面纹理正确；基础层恒 FrontSide 剔除不变
        BOOL ame419_cull = (ame416_backface && !ame414_f.isOverlay);
        // ——四角投影——
        CGFloat ame416_sx[4], ame416_sy[4], ame416_zsum = 0.0;
        BOOL ame416_ok = YES;
        for (NSInteger ame416_k = 0; ame416_k < 4; ame416_k++) {
            CGFloat ame416_vx = ame414_f->corners[ame416_k][0];
            CGFloat ame416_vy = ame414_f->corners[ame416_k][1];
            CGFloat ame416_vz = ame414_f->corners[ame416_k][2];
            if (ame416_ty != 0.0) {   // ★Task424 关节 rotY（头转）绕枢轴
                CGFloat ame424_dx = ame416_vx - ame414_f->pivot[0];
                CGFloat ame424_dz2 = ame416_vz - ame414_f->pivot[2];
                Ame416RotY(ame416_ty, &ame424_dx, &ame424_dz2);
                ame416_vx = ame414_f->pivot[0] + ame424_dx;
                ame416_vz = ame414_f->pivot[2] + ame424_dz2;
            }
            if (ame416_th != 0.0) {   // 摆动绕枢轴（RotX）
                CGFloat ame416_dy = ame416_vy - ame414_f->pivot[1];
                CGFloat ame416_dz = ame416_vz - ame414_f->pivot[2];
                ame416_vy = ame414_f->pivot[1] + ame416_dy * ame416_ct - ame416_dz * ame416_st;
                ame416_vz = ame414_f->pivot[2] + ame416_dy * ame416_st + ame416_dz * ame416_ct;
            }
            if (ame416_tz != 0.0) {   // ★Task424 关节 rotZ（臂侧展）绕枢轴
                CGFloat ame424_dx2 = ame416_vx - ame414_f->pivot[0];
                CGFloat ame424_dy2 = ame416_vy - ame414_f->pivot[1];
                ame416_vx = ame414_f->pivot[0] + ame424_dx2 * ame416_cz2 - ame424_dy2 * ame416_sz2;
                ame416_vy = ame414_f->pivot[1] + ame424_dx2 * ame416_sz2 + ame424_dy2 * ame416_cz2;
            }
            if (ame424_yoff[ame424_part] != 0.0) {   // ★Task424 蹲下整体下沉（位移不影响法线）
                ame416_vy += ame424_yoff[ame424_part];
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
        ame414_f.layer.hidden = ame419_cull;   // 背面剔除（画家序前置；外层双层不剔）
        if (ame419_cull) continue;
        ame414_f.layer.zPosition = ame416_zsum / 4.0;   // 画家序：远先近后
        // ★Task424 屏幕四角存档（自定义关节命中拾取用；忽略全模平移，
        //   舞台居中偏移拾取时补回）
        for (NSInteger ame424_k = 0; ame424_k < 4; ame424_k++) {
            ame414_f->screenPts[ame424_k][0] = ame416_sx[ame424_k];
            ame414_f->screenPts[ame424_k][1] = ame416_sy[ame424_k];
        }
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
        // ——明暗罩：法线 × 光向点积（★Task424 光影系统：视空间 az/el 光向 +
        //   亮度双通道 floor/gain + 双面受光）——
        //   ★Task424-a 双面受光（IMG_0669 定谳根修）：外层背面用未翻转法线算
        //   明暗 → dot≤0 → 罩顶格 → 黑暗带透过半透外层前面露出（设备实测头
        //   右侧 20×43px 等背景洞）；THREE.js DoubleSide 对背面自动翻法线
        //   （gl_FrontFacing）= 背面按正面受光 → 同源修正。
        CGFloat ame424_snx = ame416_nx, ame424_sny = ame416_ny, ame424_snz = ame416_nz;
        if (ame416_backface && ame414_f.isOverlay) {
            ame424_snx = -ame416_nx; ame424_sny = -ame416_ny; ame424_snz = -ame416_nz;
        }
        CGFloat ame424_Lx = cos(_ame424_lightEl) * sin(_ame424_lightAz);
        CGFloat ame424_Ly = sin(_ame424_lightEl);
        CGFloat ame424_Lz = cos(_ame424_lightEl) * cos(_ame424_lightAz);
        CGFloat ame416_len = sqrt(ame424_snx * ame424_snx + ame424_sny * ame424_sny + ame424_snz * ame424_snz);
        if (ame416_len < 0.0001) ame416_len = 1.0;
        CGFloat ame416_dot = (ame424_snx * ame424_Lx + ame424_sny * ame424_Ly + ame424_snz * ame424_Lz) / ame416_len;
        // ★Task424 亮度双通道：floor = clamp(0.44+(b−1)·0.55, 0.12, 0.80)，
        //   gain = clamp(2−b, 0.25, 1.8)；罩上限 0.85→AME424_VEIL_CAP=0.60
        CGFloat ame424_floor = 0.44 + (_ame424_brightness - 1.0) * 0.55;
        if (ame424_floor < 0.12) ame424_floor = 0.12;
        if (ame424_floor > 0.80) ame424_floor = 0.80;
        CGFloat ame424_gain = 2.0 - _ame424_brightness;
        if (ame424_gain < 0.25) ame424_gain = 0.25;
        if (ame424_gain > 1.8) ame424_gain = 1.8;
        CGFloat ame416_shade = ame424_floor + (1.0 - ame424_floor) * fmax(0.0, ame416_dot);
        if (ame416_shade > 1.0) ame416_shade = 1.0;
        ame414_f.shade.opacity = (1.0 - ame416_shade) * AME424_VEIL_CAP * ame424_gain;
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
                                 BOOL ame419_overlay,
                                 NSInteger ame424_partIndex,
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
        // ★Task419 基础层 α 裁切（内层不透明语义 = skinview3d transparent:false）；
        //   外层保持真 α（transparent:true 半透混合 = 全息彩虹层）
        if (ame413_img && !ame419_overlay) {
            ame413_img = ZL2SkinViewCutoutImage(ame413_img);
        }
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
            // ★Task422 罩掩膜分级：外层 = 近不透明像素（α≥180）才受罩（半透区
            //   全亮透底 = skinview3d Ambient3 语义，IMG_0667 缝带 rgb19<25 的
            //   黑罩压背景根修）；基础层 = 裁切位图（0/255 二值）语义不变。
            UIImage *ame422_maskImg = ame419_overlay
                ? ZL2SkinViewOpaqueMaskImage(ame413_img) : ame413_img;
            ame418_shadeMask.contents = (id)ame422_maskImg.CGImage;
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
        ame414_rec.isOverlay = ame419_overlay;
        ame414_rec->partIndex = ame424_partIndex;   // ★Task424 部件索引（姿态/拾取共用）
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
                             ame413_dummy, ame413_unit, nil, NO, 1, _ame413_faceLayers);
        return;
    }

    BOOL ame413_legacy = (skin.size.height < skin.size.width);   // 64×32 旧版 = 左臂左腿镜像右区
    // ★Task423 内容级模型判定（渲染以内容为准）：UV 表必须匹配贴图内容
    //   展开带——slim 内容皮（crafatar/minotar 默认 Alex、衣柜、缓存零
    //   metadata 场景）在 classic 表下背脸半列被 α 裁切吃掉 = IMG_0668
    //   臂细条+缝。metadata（yggdrasil 链）保留在诊断日志作对照。
    NSInteger ame423_rHas = -1, ame423_lHas = -1;
    BOOL ame423_metaSlim = _ame413_slimModel;
    _ame413_slimModel = ZL2SkinViewDetectSlimModelFromContent(skin, &ame423_rHas, &ame423_lHas);
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
                             ame416_faceTables[ame413_i], ame413_unit, skin, NO,
                             ame413_i, _ame413_faceLayers);
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
                             ame417_overlayTables[ame413_i], ame413_unit, skin, YES,
                             ame413_i, _ame413_faceLayers);
    }
    [self ame413_updateModelTransform];
    // ★Task418 装配诊断（冒烟 console/预览日志可视：现代皮面数应恒 72
    //   （36 基础 + 36 第二层）/ 旧版 42（36 + 帽 6）；unit/舞台尺寸异常 =
    //   布局面问题）
    // ★Task420 装配诊断重锚（cutout=基础层 α 裁切 / doubleside=外层双层 /
    //   source=皮肤来源链诊断：IMG_0655「为什么是原版皮肤」的 CI 仲裁面）
    // ★Task423 诊断重锚（model=内容判定结果 probe=经典专属列命中 meta=
    //   yggdrasil metadata 对照 prov=缓存来源 sidecar 仲裁口径）
    // ★Task424 诊断重锚（pose/light/bright = 本轮三新面 CI 仲裁字段；
    //   IMG_0669「还是有地方透明的」双面受光 + 亮度双通道 + 姿态四段）
    NSLog(@"[ZL2SkinPreview] Task424: skin=%gx%g stage=%.0fx%.0f unit=%.2f faces=%lu slim=%d pose=%ld walk=%d light=az%.2f/el%.2f/b%.2f overlayParts=%ld source=%@ model=content-slim%d(classic%d) probe=r%ld/l%ld meta=%d cutout=base-alpha>=26 veil=overlay-alpha>=180 capscale=veil-cap0.60 twoside=overlay-back-normal-flip doubleside=overlay chain=mtime-dualurl-fallback-prov prov=%@ chip=%@",
          skin.size.width, skin.size.height, _ame413_stageView.bounds.size.width,
          _ame413_stageView.bounds.size.height, ame413_unit,
          (unsigned long)_ame413_faceLayers.count, _ame413_slimModel,
          (long)_ame424_poseIndex, _ame414_walkOn ? 1 : 0,
          _ame424_lightAz, _ame424_lightEl, _ame424_brightness,
          (long)ame418_overlayParts, _ame420_skinSource ?: @"-",
          _ame413_slimModel ? 1 : 0, _ame413_slimModel ? 0 : 1,
          (long)ame423_rHas, (long)ame423_lHas, ame423_metaSlim ? 1 : 0,
          [self ame423_cacheProvenanceForDiag] ?: @"-", _ame421_buildChip.text ?: @"-");
}

// ★Task423 缓存来源 sidecar 读取（诊断 + 仲裁共用；缺省 = 无 sidecar 历史遗留）
- (NSString *)ame423_cacheProvenanceForDiag {
    NSString *ame423_key = _ame414_lastAccountId ?: _ame414_lastProfileId ?: _ame414_lastUsername;
    if (ame423_key.length == 0) return nil;
    NSString *ame423_cachePath = [[ZL2SkinViewCacheDir()
        stringByAppendingPathComponent:ZL2SkinViewSafeName(ame423_key)]
        stringByAppendingPathExtension:@"png"];
    NSString *ame423_srcPath = [ame423_cachePath stringByAppendingPathExtension:@"src"];
    NSData *ame423_d = [NSData dataWithContentsOfFile:ame423_srcPath];
    NSString *ame423_s = [[NSString alloc] initWithData:ame423_d encoding:NSUTF8StringEncoding];
    return [ame423_s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
