#import <Foundation/Foundation.h>

@interface GyroInput : NSObject

// ★Task432（陀螺仪键族单族化）：control.gyroscope_*（旧三键 enable/
//   invert_x_axis/sensitivity）→ general.gyro_*（新三键 gyro_enable/
//   gyro_invert_x/gyro_sensitivity）一次性迁移器。UI 装载
//   （ZL2SettingPages 控制屏）与运行时读（SurfaceViewController
//   applyInGamePreferenceChanges）共同调用，幂等 + 进程内快路径 +
//   持久哨兵键 general.gyro_family_migrated（@YES 后跳过）。
//   迁移完成后旧键不再写（读侧兜底仅剩本迁移器一次拷贝）。
+ (void)ame432_migrateGyroKeyFamilyIfNeeded;

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
//   ★Task432：enable/invert_x/sensitivity 自本版本起统一为 general.gyro_*
//   单族（旧 control.gyroscope_* 由 ame432_migrateGyroKeyFamilyIfNeeded
//   迁移，调用方 SurfaceViewController 已改读新族键）。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX invertYAxis:(BOOL)invertY sampleRate:(CGFloat)sampleRate smoothing:(int)smoothing;
+ (void)tick;

@end
