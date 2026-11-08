//
// ZL2SkinPreviewViewController.h — ★ Task412 账户页皮肤 3D 预览（第 20 轮复诉⑥
// 「在账号页面添加皮肤3d预览等功能」）
//
// 形态：模态页（黑底 + 顶部标题栏 + SceneKit 视图 + 提示行）。
// 模型：Minecraft 经典比例盒体（头 8×8×8 / 身 8×12×4 / 臂·腿 4×12×4，
//       单位高度 32），六面 UV 裁贴自完整皮肤纹理（64×64 新版 / 64×32 旧版
//       双格式；旧版左臂左腿镜像右臂右腿区域）。
// 皮肤源（AvatarManager ame185 三层回退链同源判例）：
//       ①crafatar 按 profileId（正版账号真皮肤）→ ②minotar 按 username
//       → ③全空 = 占位灰模型 + 不可用提示（零假数据诚实边界）。
//       磁盘缓存 Library/Caches/skins/<safe>.png（跨会话秒开）。
// 交互：SCNView allowsCameraControl（单指轨道旋转 / 双指捏合缩放）+
//       模型自动匀速旋转（SCNAction 无限循环）。
// 红线：iOS 14.0+（SceneKit SF 级 API）；颜色/字体/圆角一律 ZL2Theme 动态
//       令牌；无 viewWithTag；无 HardCode 颜色分支（模态底 black = 沉浸
//       观影面对齐截图查看器黑底判例）。
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
