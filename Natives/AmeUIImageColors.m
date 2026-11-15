//
// AmeUIImageColors.m — ★Task429（PDF 第五版 §8.1）UIImage 主色提取实现
//
// 经典 UIImageColors（jathu/UIImageColors，MIT）纯 ObjC 移植。上游算法：
//   1. 降采样绘制进 RGBA8 缓冲（原实现取 25% 尺寸；本移植对已降采样的
//      壁纸输入再聚拢到 maxPixel 上限，默认 128——聚类语义分辨率）；
//   2. 逐像素统计：亮度 <0.12 / >0.88 或饱和度 <0.15 归入「不可区分桶」，
//      其余按 (亮度×255)×256+(饱和度×255) 桶号聚类计数；
//   3. 两桶各自按计数降序；背景 = 显著桶中最暗者；主 = 最高计数桶；
//      次/细节 = 顺位查找色相差 >0.3 或亮度差 >0.1 的下一桶（桶不足时
//      对主/次色做对比度兜底 ensureContrast——不可区分桶不参与显著面）；
//   4. 可行性 = 至少一个显著桶存在；深色底 = 背景色亮度 < 0.5。
//
// 对原实现的三处工程化调整（视觉语义不变）：
//   ① 亮度口径统一 Rec.709 加权（原实现同式）；
//   ② 像素过滤新增 alpha<15 跳过（原实现同款）；
//   ③ 输入内部二次降采样经 UIGraphicsImageRenderer（原实现 CGContext 直绘
//      等价；RGBA8/设备色域一致）。
//

#import "AmeUIImageColors.h"

#pragma mark - 内部聚类桶

// 聚类语义分辨率默认值（maxPixel <= 0 时的类内默认；原实现 25% 缩放同族）
static const NSInteger Ame429ExtractDefaultMaxPixel = 128;

@interface Ame429ColorBucket : NSObject
@property (nonatomic, assign) NSInteger count;   // 落桶像素计数
@property (nonatomic, strong) UIColor *color;    // 桶代表色（最后一次落桶像素）
@property (nonatomic, assign) CGFloat brightness; // 桶代表色亮度（0..1）
@property (nonatomic, assign) CGFloat saturation; // 桶代表色饱和度（0..1）
@end
@implementation Ame429ColorBucket
@end

#pragma mark - 私有数学

// HSB 三元组（UIColor getHue 系在灰色上 hue 无意义，独立换算）
typedef struct {
    CGFloat h;   // 0..1
    CGFloat s;   // 0..1
    CGFloat b;   // 0..1
} Ame429HSB;

static Ame429HSB Ame429HSBFromColor(UIColor *color) {
    Ame429HSB out = {0.0, 0.0, 0.0};
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return out;
    CGFloat maxC = MAX(MAX(r, g), b);
    CGFloat minC = MIN(MIN(r, g), b);
    CGFloat delta = maxC - minC;
    out.b = maxC;
    out.s = (maxC > 0.0) ? (delta / maxC) : 0.0;
    if (delta <= 0.0) {
        out.h = 0.0;
        return out;
    }
    if (maxC == r) {
        out.h = (g - b) / delta;
        out.h = out.h + (out.h < 0 ? 6.0 : 0.0);
    } else if (maxC == g) {
        out.h = (b - r) / delta + 2.0;
    } else {
        out.h = (r - g) / delta + 4.0;
    }
    out.h /= 6.0;
    return out;
}

// 对比度兜底（原实现 ensureContrast 同式）：深色提亮 / 浅色压暗
static UIColor *Ame429EnsureContrast(UIColor *color) {
    Ame429HSB hsb = Ame429HSBFromColor(color);
    BOOL dark = (hsb.b < 0.5);
    if (dark) {
        return [UIColor colorWithHue:hsb.h saturation:hsb.s
                          brightness:MIN(hsb.b * 1.7, 1.0) alpha:1.0];
    }
    return [UIColor colorWithHue:hsb.h saturation:hsb.s
                      brightness:MAX(hsb.b * 0.7, 0.0) alpha:1.0];
}

#pragma mark - 实现

@implementation AmeUIImageColors

- (instancetype)init {
    self = [super init];
    if (self) {
        _feasible = NO;
        _isDarkBackground = NO;
    }
    return self;
}

+ (void)ame429_extractFromImage:(UIImage *)image
                       maxPixel:(NSInteger)maxPixel
                     completion:(AmeUIImageColorsResultBlock)completion {
    if (!completion) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AmeUIImageColors *worker = [[AmeUIImageColors alloc] init];
        BOOL ok = [worker ame429_extractFromImage:image maxPixel:maxPixel];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(ok ? worker.background : nil,
                       ok ? worker.primary : nil,
                       ok ? worker.secondary : nil,
                       ok ? worker.detail : nil,
                       ok && worker.feasible,
                       worker.isDarkBackground);
        });
    });
}

- (BOOL)ame429_extractFromImage:(UIImage *)image maxPixel:(NSInteger)maxPixel {
    if (!image) return NO;
    if (maxPixel <= 0) maxPixel = Ame429ExtractDefaultMaxPixel;   // 0 = 类内默认

    // ── ① 降采样绘制（RGBA8，聚类语义分辨率）──
    CGFloat scale = 1.0;
    CGSize srcSize = image.size;
    if (srcSize.width <= 0 || srcSize.height <= 0) return NO;
    CGFloat srcMax = MAX(srcSize.width, srcSize.height);
    CGFloat targetMax = (CGFloat)maxPixel;
    CGSize dstSize = (srcMax <= targetMax)
        ? CGSizeMake(floor(srcSize.width), floor(srcSize.height))
        : CGSizeMake(floor(srcSize.width * targetMax / srcMax),
                     floor(srcSize.height * targetMax / srcMax));
    if (dstSize.width < 1.0 || dstSize.height < 1.0) return NO;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = scale;   // 1x 语义分辨率（像素级统计，不做设备倍率放大）
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:dstSize format:fmt];
    UIImage *small = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, dstSize.width, dstSize.height)];
    }];
    CGImageRef cg = small.CGImage;
    if (cg == NULL) return NO;

    size_t w = (size_t)CGImageGetWidth(cg);
    size_t h = (size_t)CGImageGetHeight(cg);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (space == NULL) return NO;
    // RGBA8：bytesPerRow 固定 4*w（Apple 实名 CGContextDrawImage 拉平缓冲）
    NSUInteger bufLen = w * h * 4;
    NSMutableData *buffer = [NSMutableData dataWithLength:bufLen];
    CGContextRef ctx = CGBitmapContextCreate(buffer.mutableBytes, w, h, 8, w * 4,
                                             space, kCGImageAlphaPremultipliedLast |
                                             kCGBitmapByteOrder32Big);
    BOOL ok = NO;
    if (ctx != NULL) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
        ok = YES;
    }
    CGColorSpaceRelease(space);
    if (ctx != NULL) CGContextRelease(ctx);
    if (!ok) return NO;

    // ── ② 逐像素分桶计数（原实现口径：亮度/饱和度阈值两桶族）──
    NSMutableDictionary<NSNumber *, Ame429ColorBucket *> *distinguishable = [NSMutableDictionary dictionary];
    NSMutableArray<Ame429ColorBucket *> *indistinguishable = [NSMutableArray array];
    const UInt8 *px = buffer.bytes;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            const UInt8 *p = px + (y * w + x) * 4;
            CGFloat alpha = p[3] / 255.0;
            if (alpha < 0.06) continue;   // 原实现同款：近透明像素跳过
            CGFloat r = p[0] / 255.0;
            CGFloat g = p[1] / 255.0;
            CGFloat b = p[2] / 255.0;
            // 预乘还原（drawImage 输出为预乘 alpha 缓冲）
            if (alpha < 1.0) {
                r = MIN(r / alpha, 1.0);
                g = MIN(g / alpha, 1.0);
                b = MIN(b / alpha, 1.0);
            }
            // Rec.709 亮度（原实现同式）
            CGFloat brightness = (r * 0.2126) + (g * 0.7152) + (b * 0.0722);
            CGFloat maxC = MAX(MAX(r, g), b);
            CGFloat minC = MIN(MIN(r, g), b);
            CGFloat saturation = (maxC > 0.0) ? ((maxC - minC) / maxC) : 0.0;

            Ame429ColorBucket *bucket = nil;
            BOOL prominent = (brightness >= 0.12 && brightness <= 0.88 && saturation >= 0.15);
            if (prominent) {
                // 原实现同式桶号：亮度×255 高位 + 饱和度×255 低位
                NSInteger bucketKey = (NSInteger)(saturation * 255.0)
                                    + (NSInteger)(brightness * 255.0) * 256;
                NSNumber *key = @(bucketKey);
                bucket = distinguishable[key];
                if (bucket == nil) {
                    bucket = [[Ame429ColorBucket alloc] init];
                    bucket.color = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
                    distinguishable[key] = bucket;
                }
            } else {
                bucket = [[Ame429ColorBucket alloc] init];
                bucket.color = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
                [indistinguishable addObject:bucket];
            }
            bucket.count++;
            bucket.brightness = brightness;
            bucket.saturation = saturation;
        }
    }

    // ── ③ 桶序取色（原实现语义：计数降序 → 背景/主/次/细节顺位查找）──
    NSArray<Ame429ColorBucket *> *prominentSorted = [distinguishable.allValues sortedArrayUsingComparator:^NSComparisonResult(Ame429ColorBucket *a, Ame429ColorBucket *b) {
        if (a.count != b.count) return (a.count > b.count) ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (prominentSorted.count == 0) {
        // 全图无显著桶：不可行（调用方回落 embermire/默认种子）
        self.feasible = NO;
        return NO;
    }

    // 背景 = 显著桶中最暗者（原实现同款：顺计数序找最暗）
    Ame429ColorBucket *bgBucket = nil;
    for (Ame429ColorBucket *bucket in prominentSorted) {
        if (bgBucket == nil || bucket.brightness < bgBucket.brightness) bgBucket = bucket;
    }
    self.background = bgBucket.color;
    self.isDarkBackground = (bgBucket.brightness < 0.5);

    // 主色 = 最高计数桶（背景桶除外）
    Ame429ColorBucket *primaryBucket = nil;
    for (Ame429ColorBucket *bucket in prominentSorted) {
        if (bucket == bgBucket) continue;
        if (primaryBucket == nil) {
            primaryBucket = bucket;
            break;
        }
    }
    if (primaryBucket == nil) {
        // 显著桶唯一（背景即主）：主色取对比度兜底版
        self.primary = Ame429EnsureContrast(self.background);
    } else {
        self.primary = primaryBucket.color;
    }

    // 次/细节 = 色相差 >0.3 或亮度差 >0.1 的下一桶（原实现同款阈值；
    // 不足时从其余桶补位 + 对比度兜底）
    Ame429HSB primaryHSB = Ame429HSBFromColor(self.primary);
    Ame429ColorBucket *secondaryBucket = nil;
    for (Ame429ColorBucket *bucket in prominentSorted) {
        if (bucket == bgBucket || bucket == primaryBucket) continue;
        Ame429HSB hsb = Ame429HSBFromColor(bucket.color);
        CGFloat hueDiff = fabs(hsb.h - primaryHSB.h);
        if (hueDiff > 0.5) hueDiff = 1.0 - hueDiff;   // 色环最短弧
        if (hueDiff > 0.3 || fabs(hsb.b - primaryHSB.b) > 0.1) {
            secondaryBucket = bucket;
            break;
        }
    }
    self.secondary = (secondaryBucket != nil) ? secondaryBucket.color
                                              : Ame429EnsureContrast(self.primary);

    Ame429HSB secondaryHSB = Ame429HSBFromColor(self.secondary);
    Ame429ColorBucket *detailBucket = nil;
    for (Ame429ColorBucket *bucket in prominentSorted) {
        if (bucket == bgBucket || bucket == primaryBucket || bucket == secondaryBucket) continue;
        Ame429HSB hsb = Ame429HSBFromColor(bucket.color);
        CGFloat hueDiffP = fabs(hsb.h - primaryHSB.h);
        if (hueDiffP > 0.5) hueDiffP = 1.0 - hueDiffP;
        CGFloat hueDiffS = fabs(hsb.h - secondaryHSB.h);
        if (hueDiffS > 0.5) hueDiffS = 1.0 - hueDiffS;
        if ((hueDiffP > 0.3 || fabs(hsb.b - primaryHSB.b) > 0.1) &&
            (hueDiffS > 0.3 || fabs(hsb.b - secondaryHSB.b) > 0.1)) {
            detailBucket = bucket;
            break;
        }
    }
    self.detail = (detailBucket != nil) ? detailBucket.color
                                        : Ame429EnsureContrast(self.secondary);

    self.feasible = YES;
    return YES;
}

@end
