#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import "GyroInput.h"
#import "../SurfaceViewController.h"
#import "../utils.h"
#import "../LauncherPreferences.h"   // ★Task428：getPrefBool/getPrefObject（陀螺仪新参数偏好读取）

// ★Task428（6.4，ZL2 GyroscopeReader 平滑质量对标）：新参数常量。
//   AME428_GYRO_MAX_WINDOW：滑动均值窗口上限——★Task436 起平滑为
//     「开关 + 窗口」双控件，窗口即样本数（2-10），本常量仅作内部缓冲
//     上界（11 ≥ 窗口上限 10）。
//   AME428_GYRO_DEADZONE：微增量阈值——单轴每 tick 增量绝对值低于该值
//     视为抖动丢弃（置 0），对齐 ZL2 GyroscopeReader 的阈值语义，
//     抑制持机静止时的视角漂移。
#define AME428_GYRO_MAX_WINDOW 11
#define AME428_GYRO_DEADZONE 0.02

// ★Task432（键族单族化）：新旧键名 + 迁移哨兵（与 PLPreferences.m 注册逐字一致）。
//   旧族 control.gyroscope_*（历史三键，注册保留防迁移读不到，迁移后不再写）；
//   新族 general.gyro_*（本版本起唯一读写族）。
static NSString * const Ame432GyroLegacyEnableKey      = @"control.gyroscope_enable";
static NSString * const Ame432GyroLegacyInvertXKey     = @"control.gyroscope_invert_x_axis";
static NSString * const Ame432GyroLegacySensitivityKey = @"control.gyroscope_sensitivity";
static NSString * const Ame432GyroNewEnableKey         = @"general.gyro_enable";
static NSString * const Ame432GyroNewInvertXKey        = @"general.gyro_invert_x";
static NSString * const Ame432GyroNewSensitivityKey    = @"general.gyro_sensitivity";
static NSString * const Ame432GyroMigratedSentinelKey  = @"general.gyro_family_migrated";

// ★Task436（平滑双控件化 + 灵敏度下限对齐）：新二键 + 参数域常量。
//   平滑旧键 general.gyro_smoothing（0-100 单滑杆）退役读写（注册保留），
//   改「开关 + 窗口」双控件：开关 bool + 窗口 2-10 整数（滑动均值样本数）。
//   契约默认（开 + 窗口 4）与旧默认 smoothing=30 映射窗口 4 逐位等价，
//   未动过平滑的设备升级后手感零漂移。灵敏度域 25-300（★Task436 下限
//   50→25 对齐 ZL2 GyroscopeReader）。
static NSString * const Ame436GyroSmoothEnableKey      = @"general.gyro_smooth_enable";
static NSString * const Ame436GyroSmoothWindowKey      = @"general.gyro_smooth_window";
static const int AME436_GYRO_SENS_MIN = 25;
static const int AME436_GYRO_SENS_MAX = 300;
static const int AME436_GYRO_WINDOW_MIN = 2;
static const int AME436_GYRO_WINDOW_MAX = 10;
static const int AME436_GYRO_WINDOW_DEFAULT = 4;

// 迁移哨兵进程内快路径（持久哨兵见上；两者任一为真即跳过）
static BOOL ame432_gyroFamilyMigrated = NO;

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

// ★Task432（键族单族化）：旧族 → 新族一次性迁移（幂等）。实现要点：
//   · 哨兵双闸：进程内 static（同会话零开销）+ 持久键
//     general.gyro_family_migrated（跨启动幂等）。
//   · 拷贝语义：PLPreferences setDefaultsForPref 会把已注册键播种进内存
//     （读侧恒非 nil），"旧键有值/新键未写"无法以 nil 判别——本迁移器以
//     哨兵实现"一次性"，哨兵为假时旧族三值无条件拷入新族（未动过的旧键
//     值 = 播种默认，拷贝后与默认逐位相等，幂等无害；用户改过的旧键值
//     得以真实接管）。
//   · 迁移完成后旧键不再写（本函数是旧键的最后一次读 + 唯一兜底写源）。
//   · 调用点：① ZL2SettingPages 控制屏陀螺仪行装载；② SurfaceViewController
//     applyInGamePreferenceChanges 陀螺仪读前；③ 本类旧签名兼容垫片入口
//     （三入口共用一份实现，无双族回写窗口）。
+ (void)ame432_migrateGyroKeyFamilyIfNeeded {
    if (ame432_gyroFamilyMigrated) return;
    if (getPrefBool(Ame432GyroMigratedSentinelKey)) {
        ame432_gyroFamilyMigrated = YES;
        return;
    }
    // 旧键有值 → 拷贝迁移后写新键（旧键读保留，新键写；旧键自此不再写）
    id ame432_enable = getPrefObject(Ame432GyroLegacyEnableKey);
    if (ame432_enable != nil) {
        setPrefObject(Ame432GyroNewEnableKey, @([ame432_enable boolValue]));
    }
    id ame432_invertX = getPrefObject(Ame432GyroLegacyInvertXKey);
    if (ame432_invertX != nil) {
        setPrefObject(Ame432GyroNewInvertXKey, @([ame432_invertX boolValue]));
    }
    id ame432_sens = getPrefObject(Ame432GyroLegacySensitivityKey);
    if (ame432_sens != nil) {
        setPrefObject(Ame432GyroNewSensitivityKey, @(roundf([ame432_sens floatValue])));
    }
    setPrefBool(Ame432GyroMigratedSentinelKey, YES);
    ame432_gyroFamilyMigrated = YES;
    NSLog(@"[Ame432] gyro key family migrated: control.gyroscope_* -> general.gyro_* (one-shot)");
}

// ★Task428（6.4）：旧签名兼容垫片——转发到全参数入口，新参数（Y 反转 /
//   采样率 / 平滑）从偏好读取，键缺失按契约默认（invert_y=NO、20Hz、
//   平滑开 + 窗口 4），越界值夹取到合法域。现有调用方（SurfaceViewController
//   applyInGamePreferenceChanges）零改动即让新键生效。
//   ★Task432：垫片入口先跑键族迁移器（若调用方漏跑，此处兜底一次）。
//   ★Task436：平滑读侧从旧 0-100 单键改双键（smooth_enable +
//   smooth_window），旧键 general.gyro_smoothing 不再读（注册保留）。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX {
    [self ame432_migrateGyroKeyFamilyIfNeeded];
    CGFloat ame428_rate = 20.0;   // general.gyro_sample_rate 契约默认（Hz）
    id ame428_rateObj = getPrefObject(@"general.gyro_sample_rate");
    if (ame428_rateObj != nil) {
        ame428_rate = [ame428_rateObj floatValue];
        if (ame428_rate < 5.0) ame428_rate = 5.0;
        if (ame428_rate > 50.0) ame428_rate = 50.0;
    }
    // ★Task436：平滑双键（开关 bool 默认 YES + 窗口 int 2-10 默认 4）
    BOOL ame436_smoothEnable = YES;
    id ame436_seObj = getPrefObject(Ame436GyroSmoothEnableKey);
    if (ame436_seObj != nil) {
        ame436_smoothEnable = [ame436_seObj boolValue];
    }
    int ame436_window = AME436_GYRO_WINDOW_DEFAULT;
    id ame436_wObj = getPrefObject(Ame436GyroSmoothWindowKey);
    if (ame436_wObj != nil) {
        ame436_window = [ame436_wObj intValue];
        if (ame436_window < AME436_GYRO_WINDOW_MIN) ame436_window = AME436_GYRO_WINDOW_MIN;
        if (ame436_window > AME436_GYRO_WINDOW_MAX) ame436_window = AME436_GYRO_WINDOW_MAX;
    }
    if (!ame436_smoothEnable) ame436_window = 1;   // 关 = 直通（全入口窗口 1 语义）
    [self updateSensitivity:sensitivity
                 invertXAxis:invertX
                 invertYAxis:getPrefBool(@"general.gyro_invert_y")
                  sampleRate:ame428_rate
                smoothEnable:ame436_smoothEnable
                smoothWindow:ame436_window];
}

// ★Task436（游戏内实时调参）：全键热应用——ZL2GyroTunerViewController
//   每次控件改动后调用（七键现读现配，改动即生效）；非游戏态只落盘不启
//   采样（进游戏由 applyInGamePreferenceChanges 常规装载），防游戏外空转
//   DeviceMotion 白耗电。
+ (void)ame436_applyCurrentPreferences {
    [self ame432_migrateGyroKeyFamilyIfNeeded];
    if ([SurfaceViewController currentInstance] == nil) return;   // 非游戏态：偏好已落盘，装载交常规链
    BOOL ame436_enable = getPrefBool(Ame432GyroNewEnableKey);
    int ame436_sens = (int)roundf(getPrefFloat(Ame432GyroNewSensitivityKey));
    if (ame436_sens < AME436_GYRO_SENS_MIN) ame436_sens = AME436_GYRO_SENS_MIN;
    if (ame436_sens > AME436_GYRO_SENS_MAX) ame436_sens = AME436_GYRO_SENS_MAX;
    CGFloat ame436_rate = 20.0;
    id ame436_rateObj = getPrefObject(@"general.gyro_sample_rate");
    if (ame436_rateObj != nil) {
        ame436_rate = [ame436_rateObj floatValue];
        if (ame436_rate < 5.0) ame436_rate = 5.0;
        if (ame436_rate > 50.0) ame436_rate = 50.0;
    }
    BOOL ame436_smoothEnable = YES;
    id ame436_seObj = getPrefObject(Ame436GyroSmoothEnableKey);
    if (ame436_seObj != nil) {
        ame436_smoothEnable = [ame436_seObj boolValue];
    }
    int ame436_window = AME436_GYRO_WINDOW_DEFAULT;
    id ame436_wObj = getPrefObject(Ame436GyroSmoothWindowKey);
    if (ame436_wObj != nil) {
        ame436_window = [ame436_wObj intValue];
        if (ame436_window < AME436_GYRO_WINDOW_MIN) ame436_window = AME436_GYRO_WINDOW_MIN;
        if (ame436_window > AME436_GYRO_WINDOW_MAX) ame436_window = AME436_GYRO_WINDOW_MAX;
    }
    [self updateSensitivity:ame436_enable ? ame436_sens : 0
                 invertXAxis:getPrefBool(Ame432GyroNewInvertXKey)
                 invertYAxis:getPrefBool(@"general.gyro_invert_y")
                  sampleRate:ame436_rate
                smoothEnable:ame436_smoothEnable
                smoothWindow:ame436_window];
}

// ★Task428（6.4）：全参数配置入口——灵敏度 / X 反转语义与旧入口完全一致，
//   新增：invertY（Y 轴反转）、sampleRate（DeviceMotion 采样率 Hz →
//   deviceMotionUpdateInterval = 1.0/rate，启动前设置）。
//   ★Task436：平滑参数改双控件（smoothEnable 开关 + smoothWindow 窗口
//   2-10 整数，滑动均值样本数；关 = 窗口 1 直通），缓冲随之复位。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX invertYAxis:(BOOL)invertY sampleRate:(CGFloat)sampleRate smoothEnable:(BOOL)smoothEnable smoothWindow:(int)smoothWindow {
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
        // ★Task436：平滑窗口（开关 + 窗口双控件；关/非法 → 1 直通）+
        //   环形缓冲复位
        gyroSmoothWindow = smoothEnable ? smoothWindow : 1;
        if (gyroSmoothWindow < 1) gyroSmoothWindow = 1;
        if (gyroSmoothWindow > AME428_GYRO_MAX_WINDOW) gyroSmoothWindow = AME428_GYRO_MAX_WINDOW;
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
