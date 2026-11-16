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
// ★Task436（6.4 平滑双控件化，ZL2 开关+窗口口径对标）：全参数配置入口。
//   invertY：Y 轴反转（general.gyro_invert_y，BOOL 默认 NO）；
//   sampleRate：DeviceMotion 采样率 Hz（general.gyro_sample_rate，5-50，
//     默认 20.0 → deviceMotionUpdateInterval = 1.0/rate，须在启动前设置）；
//   smoothEnable：平滑开关（general.gyro_smooth_enable，BOOL 默认 YES；
//     NO = 直通等价旧行为 smoothing=0）；
//   smoothWindow：平滑窗口样本数（general.gyro_smooth_window，int 2-10，
//     默认 4；滑动均值窗口，样本不足时为直通）。★Task436 起平滑由旧
//     0-100 单滑杆（general.gyro_smoothing）改为「开关 + 窗口」双控件，
//     旧键注册保留但不再读写（报告登记）。
//   既有灵敏度 / X 反转语义不变（灵敏度域 25-300，★Task436 下限 50→25
//   对齐 ZL2；越界防御见 ame436_applyCurrentPreferences）；旧
//   updateSensitivity:invertXAxis: 保持兼容（内部读上述新键补齐参数后
//   转发到本入口，现有调用方零改动）。
//   ★Task432：enable/invert_x/sensitivity 自本版本起统一为 general.gyro_*
//   单族（旧 control.gyroscope_* 由 ame432_migrateGyroKeyFamilyIfNeeded
//   迁移，调用方 SurfaceViewController 已改读新族键）。
+ (void)updateSensitivity:(int)sensitivity invertXAxis:(BOOL)invertX invertYAxis:(BOOL)invertY sampleRate:(CGFloat)sampleRate smoothEnable:(BOOL)smoothEnable smoothWindow:(int)smoothWindow;
// ★Task436（游戏内实时调参）：全键热应用入口——从 general.gyro_* 七键
//   （enable/sensitivity/invert_x/invert_y/sample_rate/smooth_enable/
//   smooth_window）现读现配。ZL2GyroTunerViewController 每次控件改动后
//   调用（改动即写偏好 + 本入口即时生效）；非游戏态（无
//   SurfaceViewController 实例）只落盘不启动采样，进游戏时由
//   applyInGamePreferenceChanges 常规装载。灵敏度越界夹取 25-300
//   （★Task436 下限对齐设置页滑条 25）。
+ (void)ame436_applyCurrentPreferences;
+ (void)tick;

@end
