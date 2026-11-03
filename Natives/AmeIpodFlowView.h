//
// AmeIpodFlowView.h — ★ Task393：iPod 式竖排封面流（用户规格 2026-11-03）
//
// 用户指令（bold plan 第 1/2 条）：
//   「本地账户界面改成iPod式：把所有账户排成一列，拖到哪里就选中哪里，
//    选中的是正常大小（不要加什么边框箭头什么乱七八糟的样式），
//    未选中的越远越透明、变小，可以同时显示五个」
//   「版本选择也是一样，竖排式的」
//
// 落地口径：
//   - 所有条目排成一列：条目视图由调用方构建（账户页/版本选择共用本组件），
//     本组件只负责摆位/缩放/透明度/拖拽/回弹吸附；
//   - 拖到哪里就选中哪里：拖动途中只预览（条目随手势连续滑动），手指
//     抬起后弹簧吸附到最近条目，落定下标与上次不同才回调 onSettle
//     （= 选中提交点；拖过头再拖回来不会误选）；
//   - 选中（居中）= 正常大小：零装饰——不加边框/箭头/对勾/描边，着色
//     与未选中完全同款，仅尺寸与位置区分（iPod 封面流语义）；
//   - 未选中越远越透明、越小：scale = 1 − 0.15×|d|，alpha = 1 − 0.32×|d|
//     （d = 条目位相离居中的步数，连续插值，无跳变）；
//   - 同时可见五枚：|d| ≤ 2.4 可见（居中 1 + 上下各 2），|d| > 2.6 隐藏；
//   - 条目间隙参照既有口径（用户规格「每个项目参考的间隙都要参考原有的
//     间隙，例如竖排每个实例的间隙为实例图标距离实例名称的间隙」）：
//     interItemGap 默认 10 = 实例卡「图标→名称」间隙同值。
//
// 红线遵守（ZL2 域同款）：iOS 14.0+；零 viewWithTag 状态存取（条目身份 =
// 数组下标，onSettle 回传）；条目视图由调用方按 ZL2Theme 动态令牌构建
// （本组件不落任何颜色）；translatesAutoresizingMaskIntoConstraints
// 纪律：本组件自身 NO（宿主 AutoLayout 挂接），条目视图按手动摆位口径
// 由本组件直接管理 frame（封面流连续动画的帧驱动摆位，AutoLayout 逐帧
// 更新约束不可行；条目内部子视图仍由调用方 AutoLayout 布局）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmeIpodFlowView : UIView

/// 条目高（默认 58：账户条目 = 头像 40 + 上下留白；版本条目 = 图标 40 + 双行文）
/// 调用方在 configureItems: 之前设定（帧驱动摆位在布局期读取）。
@property (nonatomic, assign) CGFloat itemHeight;

/// 条目间隙（默认 10 = 实例卡「图标→名称」间隙口径，用户规格参照间隙）
@property (nonatomic, assign) CGFloat interItemGap;

/// 当前居中条目下标（吸附落定值；拖动途中即 round(offset) 实时可读）
@property (nonatomic, assign, readonly) NSInteger selectedIndex;

/// 落定回调（吸附完成且下标与上次落定不同时回调一次 = 选中提交点；
/// setSelectedIndex: 程序化滚动不回调，防重建环）
@property (nonatomic, copy, nullable) void (^onSettle)(NSInteger index);

/// 交互锁（选中/刷新链进行中锁手势；语义同旧链 modalInPresentation，
/// 锁 = 拖拽/点按不响应，摆位只读）
@property (nonatomic, assign) BOOL interactionLocked;

/// 重建条目（全量拆建；条目视图由调用方构建，本组件接管摆位与生命周期）
- (void)configureItems:(NSArray<UIView *> *)items;

/// 程序化滚动到下标（不触发 onSettle，防重建环）
- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated;

/// 视口高度（同时可见五枚所需的容器高 = itemHeight + 4 × 步距；
/// 步距 = itemHeight + interItemGap。宿主据此钉高度约束）
- (CGFloat)viewportHeight;

@end

NS_ASSUME_NONNULL_END
