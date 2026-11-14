#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import "GyroInput.h"
#import "../SurfaceViewController.h"
#import "../utils.h"
#import "../LauncherPreferences.h"   // ★Task428：getPrefBool/getPrefObject（陀螺仪新参数偏好读取）

// ★Task428（6.4，ZL2 GyroscopeReader 平滑质量对标）：新参数常量。
//   AME428_GYRO_MAX_WINDOW：滑动均值窗口上限——smoothing 0-100 映射
//     窗口 = 1 + smoothing/10，即 1（平滑关）..11（最大平滑）。
//   AME428_GYRO_DEADZONE：微增量阈值——单轴每 tick 增量绝对值低于该值
//     视为抖动丢弃（置 0），对齐 ZL2 GyroscopeReader 的阈值语义，
//     抑制持机静止时的视角漂移。
#define AME428_GYRO_MAX_WINDOW 11
#define AME428_GYRO_DEADZONE 0.02

@implementation GyroInput

static CGFloat lastXValue, lastYValue, lastFrameTime;
static CGFloat gyroSensitivity;
static int gyroInvertX;
static BOOL gyroInvertAxis, gyroSwapAxis;
static CMMotionManager* cmInstance;

// ★Task428：Y 轴反转乘子（general.gyro_invert_y，默认 NO → +1；反转 → -1）；
//   滑动均值环形缓冲（X/Y 各一轴，窗口内算术平均作为本 tick 输出）。
static int gyroInvertY;
static CGFloat gyroSmoothBufX[AME428_GYRO_MAX_WINDOW];
static CGFloat gyroSmoothBufY[AME428_GYRO_MAX_WINDOW];
static int gyroSmoothWindow = 1;   // 1 = 平滑关闭（直通，等价旧行为）
static int gyroSmoothIndex = 0;

+ (void)updateOrientation {
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.windows[0].windowScene.interfaceOrientation;
    gyroInvertAxis =
        orientation==UIInterfaceOrientationPortraitUpsideDown ||
        orientation==UIInterfaceOrientationLandscapeLeft;
    gyroSwapAxis = UIInterfaceOrientationIsPortrait(orientation);
    // FIXME: camera jumps upon rotating screen
}

// ★Task428（6.4）：旧签名兼容垫片——转发到全参数入口，新参数（Y 反转 /
//   采样率 / 平滑）从偏好读取，键缺失按契约默认（invert_y=NO、20Hz、
//   smoothing=30），越界值夹取到合法域。现有调用方（SurfaceViewController
//   applyInGamePreferenceChanges）零改动即让新键生效。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX {
    CGFloat ame428_rate = 20.0;   // general.gyro_sample_rate 契约默认（Hz）
    id ame428_rateObj = getPrefObject(@"general.gyro_sample_rate");
    if (ame428_rateObj != nil) {
        ame428_rate = [ame428_rateObj floatValue];
        if (ame428_rate < 5.0) ame428_rate = 5.0;
        if (ame428_rate > 50.0) ame428_rate = 50.0;
    }
    int ame428_smoothing = 30;    // general.gyro_smoothing 契约默认（0=关）
    id ame428_smoothObj = getPrefObject(@"general.gyro_smoothing");
    if (ame428_smoothObj != nil) {
        ame428_smoothing = [ame428_smoothObj intValue];
        if (ame428_smoothing < 0) ame428_smoothing = 0;
        if (ame428_smoothing > 100) ame428_smoothing = 100;
    }
    [self updateSensitivity:sensitivity
                 invertXAxis:invertX
                 invertYAxis:getPrefBool(@"general.gyro_invert_y")
                  sampleRate:ame428_rate
                   smoothing:ame428_smoothing];
}

// ★Task428（6.4）：全参数配置入口——灵敏度 / X 反转语义与旧入口完全一致，
//   新增：invertY（Y 轴反转）、sampleRate（DeviceMotion 采样率 Hz →
//   deviceMotionUpdateInterval = 1.0/rate，启动前设置）、smoothing（0-100 →
//   滑动均值窗口 1+smoothing/10，缓冲随之复位）。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX invertYAxis:(BOOL)invertY sampleRate:(CGFloat)sampleRate smoothing:(int)smoothing {
    if (cmInstance == nil) {
        cmInstance = [[CMMotionManager alloc] init];
    }
    gyroSensitivity = sensitivity / 100.0;
    if (sensitivity > 0) {
        gyroInvertX = invertX ? 1 : -1;
        // ★Task428：Y 反转与 X 反转同构（±1 乘子，tick 发送处生效）
        gyroInvertY = invertY ? -1 : 1;
        // ★Task428：采样率 → 更新间隔（契约 5-50Hz；越界/非法值回退默认 20Hz）。
        //   必须在 startDeviceMotionUpdates 之前设置。
        if (sampleRate < 5.0 || sampleRate > 50.0) {
            sampleRate = 20.0;
        }
        cmInstance.deviceMotionUpdateInterval = 1.0 / sampleRate;
        // ★Task428：平滑窗口映射（0-100 → 1..11）+ 环形缓冲复位
        if (smoothing < 0) smoothing = 0;
        if (smoothing > 100) smoothing = 100;
        gyroSmoothWindow = 1 + smoothing / 10;
        gyroSmoothIndex = 0;
        for (int ame428_i = 0; ame428_i < AME428_GYRO_MAX_WINDOW; ame428_i++) {
            gyroSmoothBufX[ame428_i] = 0;
            gyroSmoothBufY[ame428_i] = 0;
        }
        [self updateOrientation];
        [cmInstance startDeviceMotionUpdates];
    } else {
        lastXValue = lastYValue = lastFrameTime = 0;
        [cmInstance stopDeviceMotionUpdates];
    }
}

+ (void)tick {
    if (!isGrabbing || gyroSensitivity == 0) {
        // ★Task428：活动→静止沿——清平滑缓冲，重新抓起时不把陈旧样本
        //   （最长 11 tick 前的增量）平均进新视角输出。
        if (lastFrameTime != 0) {
            gyroSmoothIndex = 0;
            for (int ame428_i = 0; ame428_i < AME428_GYRO_MAX_WINDOW; ame428_i++) {
                gyroSmoothBufX[ame428_i] = 0;
                gyroSmoothBufY[ame428_i] = 0;
            }
        }
        lastFrameTime = 0;
        return;
    }

    // Compute delta since last tick time
    CGFloat frameTime = CACurrentMediaTime();
    CGFloat factor = gyroSensitivity;
    if (lastFrameTime != 0) {
        CGFloat deltaTimeScale = (frameTime - lastFrameTime) / (1.0/60.0); // Scale of 1 = 60Hz
        factor *= deltaTimeScale;
    }

    // 100% sensitivity -> 1:1 ratio between real world and ingame camera
    if (gyroInvertAxis) {
        factor *= -1;
    }
    CGFloat ame428_rawX, ame428_rawY;
    if (gyroSwapAxis) {
        ame428_rawX = cmInstance.deviceMotion.rotationRate.y / (M_PI*90) * windowWidth * factor * gyroInvertX;
        ame428_rawY = -cmInstance.deviceMotion.rotationRate.x / (M_PI*180) * windowHeight * factor;
    } else {
        ame428_rawX = cmInstance.deviceMotion.rotationRate.x / (M_PI*180) * windowWidth * factor * gyroInvertX;
        ame428_rawY = cmInstance.deviceMotion.rotationRate.y / (M_PI*90) * windowHeight * factor;
    }
    // ★Task428（6.4）：Y 轴反转（general.gyro_invert_y）——视角增量发送前取反。
    ame428_rawY *= gyroInvertY;

    // ★Task428（6.4）：阈值过滤——单轴增量绝对值 < 0.02 丢弃（置 0），
    //   对齐 ZL2 GyroscopeReader 的微抖抑制语义（单位：本 tick 视角增量）。
    if (fabs(ame428_rawX) < AME428_GYRO_DEADZONE) {
        ame428_rawX = 0;
    }
    if (fabs(ame428_rawY) < AME428_GYRO_DEADZONE) {
        ame428_rawY = 0;
    }

    // ★Task428（6.4）：滑动均值平滑——窗口 1 直通（smoothing=0 等价旧行为）；
    //   窗口 > 1 时输出为最近 N 个（阈值过滤后）增量的算术平均。
    if (gyroSmoothWindow > 1) {
        gyroSmoothBufX[gyroSmoothIndex] = ame428_rawX;
        gyroSmoothBufY[gyroSmoothIndex] = ame428_rawY;
        gyroSmoothIndex = (gyroSmoothIndex + 1) % gyroSmoothWindow;
        CGFloat ame428_sumX = 0, ame428_sumY = 0;
        for (int ame428_i = 0; ame428_i < gyroSmoothWindow; ame428_i++) {
            ame428_sumX += gyroSmoothBufX[ame428_i];
            ame428_sumY += gyroSmoothBufY[ame428_i];
        }
        lastXValue = ame428_sumX / gyroSmoothWindow;
        lastYValue = ame428_sumY / gyroSmoothWindow;
    } else {
        lastXValue = ame428_rawX;
        lastYValue = ame428_rawY;
    }

    SurfaceViewController *vc = [SurfaceViewController currentInstance];
    if (vc) {
        [vc sendTouchPoint:CGPointMake(lastXValue, lastYValue) withEvent:ACTION_MOVE_MOTION];
    }

    lastFrameTime = frameTime;
}

@end
