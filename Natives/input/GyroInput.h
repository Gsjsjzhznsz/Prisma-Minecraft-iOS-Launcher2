#import <Foundation/Foundation.h>

@interface GyroInput : NSObject

+ (void)updateOrientation;
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX;
// ★Task428（6.4 陀螺仪参数补齐，ZL2 GyroscopeReader 平滑质量对标）：全参数配置入口。
//   invertY：Y 轴反转（general.gyro_invert_y，BOOL 默认 NO）；
//   sampleRate：DeviceMotion 采样率 Hz（general.gyro_sample_rate，5-50，
//     默认 20.0 → deviceMotionUpdateInterval = 1.0/rate，须在启动前设置）；
//   smoothing：平滑强度 0-100（general.gyro_smoothing，默认 30，0=关）→
//     滑动均值窗口 = 1 + smoothing/10（即 1-11 样本）+ 0.02 阈值过滤。
//   既有灵敏度 / X 反转语义不变；旧 updateSensitivity:invertXAxis: 保持
//   兼容（内部读上述新键补齐参数后转发到本入口，现有调用方零改动）。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX invertYAxis:(BOOL)invertY sampleRate:(CGFloat)sampleRate smoothing:(int)smoothing;
+ (void)tick;

@end
