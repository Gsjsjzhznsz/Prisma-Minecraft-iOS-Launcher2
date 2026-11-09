//
// ZL2SkinPreviewView.h — ★ Task413 账户页内嵌皮肤 3D 预览视图（设计契约）
//
// 第 22 轮复诉⑥「皮肤 3D 预览有问题，为什么是alex的皮肤呀，还有不应该单独
// 一个界面，你看看账号页面有这么多留白，直接在那里实现不就行了」：
//   ① 独立弹窗 VC（ZL2SkinPreviewViewController）退役，本视图直接内嵌
//     账户页视觉卡右半区（留白利用，无独立界面）；
//   ② 渲染 Y 轴根修：CALayer 坐标系 Y 向下，412f 按模型 Y 向上直摆 =
//     头在下腿在上的上下倒置（IMG_0596 实锤），本版 y_l = −y_m 翻转 +
//     顶/底面 rotX 同步换向 + 盒体左右面贴图换位（角色右=−X 侧贴右脸
//     区块）= 六盒 36 面 Minecraft 展开图约定完整对齐；
//   ③ 皮肤链第三方账户根修：412f crafatar/minotar 只认 Mojang，第三方
//     （authlib-injector）账户 username 恒回默认 Alex（IMG_0596 实锤）。
//     本版按账户类型分流：authserver 在场 → yggdrasil
//     sessionserver profile → base64 textures → SKIN.url（一次性签名
//     URL 立即下载，Task133 判例）→ 本地渲染；否则 crafatar→minotar。
//     全皮 PNG 落盘 Documents/avatars/skinfull-<accountId>.png（ame133
//     下载链同步持久化）= 离线真实皮肤；
//   ④ slim（Alex 型细臂）模型：yggdrasil textures metadata.model == slim
//     时臂盒 3pt + slim UV 表，否则经典 4pt。
//
// 渲染管线（沿用 412f 纯 CALayer 零 SceneKit 判例）：场景层
// sublayerTransform 透视（m34 −1/480，★Task414 加强）；36 面静态子层 = 平移
// (盒心)·面向旋转·平移(半深)；CADisplayLink 自转 + 跑步摆动；拖轨 yaw/pitch +
// 捏合缩放。
//
// ★Task414 v3 真三件套（第 23 轮复诉「3d渲染依旧纸片」）：
//   ① 逐帧 zPosition 深度排序（兄弟层声明序合成 → 深度序 = 遮挡永远正确）；
//   ② 逐面光影罩（法线 × 左上前光向点积 → 黑罩 opacity 逐帧）；
//   ③ 跑步动画（四肢绕肩/髋枢轴 RotX 正弦摆动，同侧臂腿反相）。
// ★Task414 皮肤站控件组（IMG_0607 口径）：跑步/暂停/刷新 + 背景色板三枚 +
//   左右旋转箭头 + 衣柜（本机 Documents/skinwardrobe，点按即穿/长按移除）+
//   设为头像（AvatarManager 既有链）+ 下载（系统分享面板）。
//   本机无服务端 → 皮肤站「举报/点赞」无对端语义诚实不做。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2SkinPreviewView : UIView

/// 配置当前账户（账户页 rebuildIdentityCard 每次重建时调用；同一账户
/// 重复调用幂等跳过，账户切换时整组重取）。
/// authData 取值：accountId（skinfull 磁盘键）/ authserver（第三方判定 +
/// yggdrasil API 根）/ profileId（yggdrasil UUID 与 crafatar）/ username
/// （minotar 兜底；Demo. 前缀由调用方剥除）。
- (void)ame413_configureWithAuthData:(nullable NSDictionary *)authData;

@end

NS_ASSUME_NONNULL_END
