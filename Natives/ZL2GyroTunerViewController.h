//
// ZL2GyroTunerViewController.h — ★Task436 陀螺仪游戏内实时调参浮层
//
// 七项参数即时调（开关 / 灵敏度 25-300 / 采样率 5-50 / 平滑开关 +
// 窗口 2-10 / 双轴反转 X / Y）：改动即写偏好（general.gyro_* 单族）
// 并经 GyroInput ame436_applyCurrentPreferences 即时生效——游戏进行中
// 拖完滑条/拨完开关体感立变，无需退出重进。
//
// 挂载口径：统一进度页式浮层家族（PLTaskProgressViewController 同款）
// ——独立 VC，不挂任何宿主页；iPhone PageSheet / iPad FormSheet 居中
// 卡片。游戏内入口（SurfaceViewController 菜单）由主控后续接，本浮层
// 只提供 +presentFrom: 类方法（任意 VC 均可拉起；nil = keyWindow 顶层）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2GyroTunerViewController : UIViewController

// 便捷呈现：沿 host 的 presented 链找最顶层后弹浮层（host 传 nil 时
// 回退 keyWindow 顶层，PLTaskProgress +presentForTaskId 同判例）。
+ (void)presentFrom:(nullable UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
