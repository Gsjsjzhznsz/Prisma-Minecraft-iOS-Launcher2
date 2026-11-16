#import "utils.h"
#import "ImageCropperViewController.h"
#import "BackgroundManager.h"

@interface ImageCropperViewController ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *cropOverlayView;
@property (nonatomic, assign) CGRect cropRect;
@property (nonatomic, assign) CGFloat scale;
@end

@implementation ImageCropperViewController

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        _sourceImage = image;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // 适配自定义启动器背景：将当前视图控制器透明化，使全局背景壁纸能够透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.title = localize(@"i18n_str_319", nil);
    self.view.backgroundColor = [UIColor blackColor];
    
    // 添加导航栏按钮
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem = doneButton;
    
    // 计算缩放比例和裁剪区域
    [self calculateCropRect];
    
    // 创建图片视图
    self.imageView = [[UIImageView alloc] init];
    self.imageView.image = self.sourceImage;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = self.cropRect;
    [self.view addSubview:self.imageView];
    
    // 创建裁剪覆盖层
    [self createCropOverlay];
    
    // 添加手势识别
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.imageView addGestureRecognizer:panGesture];
    self.imageView.userInteractionEnabled = YES;
    
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.imageView addGestureRecognizer:pinchGesture];

    // 监听背景 UI 效果变化通知，当用户切换背景效果（半透明/毛玻璃）时重新应用透明化
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// 背景效果改变时重新应用透明化（由 BackgroundUIEffectChanged 通知触发）
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)calculateCropRect {
    CGSize imageSize = self.sourceImage.size;
    CGSize viewSize = self.view.bounds.size;
    
    // 计算正方形裁剪区域
    CGFloat squareSize = MIN(viewSize.width, viewSize.height) * 0.8;
    CGFloat x = (viewSize.width - squareSize) / 2;
    CGFloat y = (viewSize.height - squareSize) / 2;
    self.cropRect = CGRectMake(x, y, squareSize, squareSize);
    
    // 计算初始缩放比例
    CGFloat scaleX = squareSize / imageSize.width;
    CGFloat scaleY = squareSize / imageSize.height;
    self.scale = MAX(scaleX, scaleY);
}

- (void)createCropOverlay {
    // 创建半透明覆盖层
    UIView *overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    overlayView.userInteractionEnabled = NO;
    [self.view insertSubview:overlayView atIndex:0];
    
    // 创建裁剪框
    self.cropOverlayView = [[UIView alloc] initWithFrame:self.cropRect];
    self.cropOverlayView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.cropOverlayView.layer.borderWidth = 2.0;
    self.cropOverlayView.backgroundColor = [UIColor clearColor];
    self.cropOverlayView.userInteractionEnabled = NO;
    [self.view addSubview:self.cropOverlayView];
    
    // 创建裁剪框内的透明区域
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.view.bounds];
    UIBezierPath *cropPath = [UIBezierPath bezierPathWithRect:self.cropRect];
    [path appendPath:cropPath];
    path.usesEvenOddFillRule = YES;
    maskLayer.path = path.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    overlayView.layer.mask = maskLayer;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.imageView];
    [gesture setTranslation:CGPointZero inView:self.imageView];
    
    CGPoint newCenter = CGPointMake(self.imageView.center.x + translation.x, self.imageView.center.y + translation.y);
    self.imageView.center = newCenter;
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        self.imageView.transform = CGAffineTransformScale(self.imageView.transform, gesture.scale, gesture.scale);
        gesture.scale = 1.0;
    }
}

- (void)cancelTapped {
    if (self.completionHandler) {
        self.completionHandler(nil);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)doneTapped {
    UIImage *croppedImage = [self cropImage];
    if (self.completionHandler) {
        self.completionHandler(croppedImage);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (UIImage *)cropImage {
    // 将裁剪框的坐标转换为图片坐标
    CGRect cropBounds = self.cropOverlayView.frame;
    CGRect imageFrame = self.imageView.frame;
    if (imageFrame.size.width < 1.0 || imageFrame.size.height < 1.0) return nil;

    CGFloat scaleX = self.sourceImage.size.width / imageFrame.size.width;
    CGFloat scaleY = self.sourceImage.size.height / imageFrame.size.height;

    CGRect cropRectInImage = CGRectMake(
        (cropBounds.origin.x - imageFrame.origin.x) * scaleX,
        (cropBounds.origin.y - imageFrame.origin.y) * scaleY,
        cropBounds.size.width * scaleX,
        cropBounds.size.height * scaleY
    );

    // 确保裁剪区域不超出图片边界
    CGRect imageBounds = CGRectMake(0, 0, self.sourceImage.size.width, self.sourceImage.size.height);
    cropRectInImage = CGRectIntersection(cropRectInImage, imageBounds);

    // ★Task434 A1：方形裁剪语义根修（应用图标导入链复用前置审计：旧实现
    //   drawInRect 把整图压入输出框 = 平移/双指缩放手势对产物零生效，输出
    //   还可能随交集钳制变非方）。三步收口：
    //   ① 方形化：区域居中收短边（应用图标恒方形；side ≤ MIN(imgW,imgH) 恒可行）；
    //   ② 子域绘制：按收口区域取源图对应像素，取景手势对产物真实生效；
    //   ③ 方向归一：先按 EXIF 转正再取像素域，保证 CGImage 空间与视图几何一致。
    CGFloat side = MIN(cropRectInImage.size.width, cropRectInImage.size.height);
    if (side < 1.0) return nil;
    cropRectInImage.origin.x += (cropRectInImage.size.width - side) / 2.0;
    cropRectInImage.origin.y += (cropRectInImage.size.height - side) / 2.0;
    // 居中收口后钳回图界（贴边取景防越界）
    cropRectInImage.origin.x = MIN(MAX(cropRectInImage.origin.x, 0), imageBounds.size.width - side);
    cropRectInImage.origin.y = MIN(MAX(cropRectInImage.origin.y, 0), imageBounds.size.height - side);
    cropRectInImage.size = CGSizeMake(side, side);

    // EXIF → Up 归一化（PHPicker 回图通常已 Up，历史选图链旋转图兜底）
    UIGraphicsBeginImageContextWithOptions(self.sourceImage.size, NO, self.sourceImage.scale);
    [self.sourceImage drawAtPoint:CGPointZero];
    UIImage *uprightImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!uprightImage.CGImage) return nil;

    // 点域 → CGImage 像素域取子图（入参须在图像界内，先钳制防取整越界）
    CGFloat pxScale = uprightImage.scale;
    CGRect pixelRect = CGRectMake(round(cropRectInImage.origin.x * pxScale),
                                  round(cropRectInImage.origin.y * pxScale),
                                  round(cropRectInImage.size.width * pxScale),
                                  round(cropRectInImage.size.height * pxScale));
    pixelRect = CGRectIntersection(pixelRect,
        CGRectMake(0, 0, uprightImage.size.width * pxScale, uprightImage.size.height * pxScale));
    if (CGRectIsNull(pixelRect) || pixelRect.size.width < 1.0 || pixelRect.size.height < 1.0) return nil;
    CGImageRef regionRef = CGImageCreateWithImageInRect(uprightImage.CGImage, pixelRect);
    if (!regionRef) return nil;
    UIImage *regionImage = [UIImage imageWithCGImage:regionRef
                                               scale:pxScale
                                         orientation:UIImageOrientationUp];
    CGImageRelease(regionRef);

    // 方形黑背衬输出（与旧版黑底语义一致；PNG 落盘无透明边）
    UIGraphicsBeginImageContextWithOptions(cropRectInImage.size, YES, pxScale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, cropRectInImage.size.width, cropRectInImage.size.height));
    [regionImage drawInRect:CGRectMake(0, 0, cropRectInImage.size.width, cropRectInImage.size.height)
                  blendMode:kCGBlendModeNormal
                    alpha:1.0];
    UIImage *croppedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return croppedImage;
}

@end