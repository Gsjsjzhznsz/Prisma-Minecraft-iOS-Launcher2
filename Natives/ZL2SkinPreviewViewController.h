//
// ZL2SkinPreviewViewController.h — ★ Task412 账户页皮肤 3D 预览（第 20 轮复诉⑥
// 「在账号页面添加皮肤3d预览等功能」）
//
// 形态：模态页（黑底 + 顶部标题栏 + 3D 模型区 + 提示行）。
// 渲染：**纯 CALayer CATransform3D 盒体**（头 8×8×8 / 身 8×12×4 / 臂·腿
//       4×12×4，单位高度 32），六面 UV 裁贴自完整皮肤纹理（64×64 新版 /
//       64×32 旧版双格式；旧版左臂左腿镜像右臂右腿区域），CADisplayLink
//       驱动自转 + 拖轨/捏合交互。
//       ★ 为何不用 SceneKit：iPhoneOS 26.2 SDK 头分叉（SCNMaterial.lightingModel
//       → lightingModelName / SCNBox boxWithWidth: / SCNAction
//       rotateByAngle:duration:aroundAxis: 均不识别，run 42487051782 实锤）
//       —— iOS 26 SceneKit 软弃用风暴规避判例：UIKit/CALayer 面零 SDK
//       分叉风险，iOS 14.0+ 全版本可编译。
// 皮肤源（AvatarManager ame185 三层回退链同源判例）：
//       ①crafatar 按 profileId（正版账号真皮肤）→ ②minotar 按 username
//       → ③全空 = 占位灰模型 + 不可用提示（零假数据诚实边界）。
//       磁盘缓存 Library/Caches/skins/<safe>.png（跨会话秒开）。
// 交互：单指水平拖 = 水平轨道旋转（叠加自转），竖直拖 = 俯仰（钳制），
//       双指捏合 = 缩放。
// 红线：iOS 14.0+；颜色/字体/圆角一律 ZL2Theme 动态令牌；模态黑底 =
//       沉浸观影面（截图查看器黑底判例）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2SkinPreviewViewController : UIViewController

/// username = 展示名与 minotar 回退键；profileId = 正版 UUID（crafatar 键，
/// 可为 nil）。二者皆空的账户仍可打开（占位模型 + 不可用提示）。
- (instancetype)initWithUsername:(nullable NSString *)username
                       profileId:(nullable NSString *)profileId;

@end

NS_ASSUME_NONNULL_END
