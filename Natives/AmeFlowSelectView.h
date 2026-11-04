//
// AmeFlowSelectView.h — ★ Task401：封面流选择器（横/竖双轴；原 Task393 竖排
//   组件更名并扩展横轴——用户指令：样式形容词不作任何组件/文件的名称，
//   样式词不作组件名；更名零语义变化，横轴为纯新增能力）
//
// 交互契约（Task393 用户规格原文，2026-11-03）：
//   「把所有条目排成一列，拖到哪里就选中哪里，选中的是正常大小（不要加
//    什么边框箭头什么乱七八糟的样式），未选中的越远越透明、变小，可以
//    同时显示五个」
//
// 落地口径：
//   - 竖轴（默认）：条目纵向一列，拖动上下滑；条目高 = itemHeight，
//     宽随远近缩放（视口宽 × scale）；视口高 = viewportHeight（五枚口径）。
//   - 横轴（★ Task401 新增）：条目横向一行，拖动左右滑；条目宽 = 步距 −
//     条目间隙（步距 = 视口宽 ÷ 4.8，恒等五枚可见——不重叠、间隙均匀），
//     高随远近缩放（视口高 × scale）；条目内容竖排（头像上/名称下，与原
//     头像卡同一呈现语言）。
//   - 拖到哪里就选中哪里：拖动途中只预览（条目随手势连续滑动），手指
//     抬起后弹簧吸附到最近条目，落定下标与上次不同才回调 onSettle
//     （= 选中提交点；拖过头再拖回来不会误选）；
//   - 选中（居中）= 正常大小：零装饰——不加边框/箭头/对勾/描边，着色
//     与未选中完全同款，仅尺寸与位置区分（封面流语义）；
//   - 未选中越远越透明、越小：scale = 1 − 0.15×|d|，alpha = 1 − 0.32×|d|
//     （d = 条目位相离居中的步数，连续插值，无跳变）；
//   - 同时可见五枚：|d| ≤ 2.4 可见，|d| > 2.6 隐藏；
//   - 手势优先级（★ Task401 新增）：本组件平移手势对宿主 UIScrollView 的
//     平移手势具有优先权（shouldBeRequiredToFailBy 动态失败要求）——
//     滚轮上的拖动恒给滚轮，滚轮外的拖动照常滚动宿主；修复 Task400
//     版本滚轮「只能拖动再回弹」的手势竞争根因。
//   - 条目间隙：竖轴默认 10 = 实例卡「图标→名称」间隙同值；横轴默认 6
//     （五等分槽位下的均匀留白）。
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

/// 流向轴（★ Task401：竖排=默认；横排=账户选择行）
typedef NS_ENUM(NSInteger, AmeFlowSelectAxis) {
    AmeFlowSelectAxisVertical   = 0,   // 竖排：条目一列，纵向拖动
    AmeFlowSelectAxisHorizontal = 1,   // 横排：条目一行，横向拖动
};

@interface AmeFlowSelectView : UIView

/// 流向轴（默认竖排；configureItems: 之前设定）
@property (nonatomic, assign) AmeFlowSelectAxis axis;

/// 条目沿轴长度（竖轴 = 条目高，默认 58：头像 40 + 上下留白；横轴 = 条目
/// 宽，由布局期按视口宽五等分自动推导，此值仅作最小宽度下限）
/// 调用方在 configureItems: 之前设定（帧驱动摆位在布局期读取）。
@property (nonatomic, assign) CGFloat itemHeight;

/// 条目间隙（竖轴默认 10 = 实例卡「图标→名称」间隙口径；横轴默认 6）
@property (nonatomic, assign) CGFloat interItemGap;

/// 当前居中条目下标（吸附落定值；拖动途中即 round(offset) 实时可读）
@property (nonatomic, assign, readonly) NSInteger selectedIndex;

/// 当前条目数（宿主免重建守卫用：键序一致且条目数一致 → 只重定位）
@property (nonatomic, assign, readonly) NSUInteger ame_itemsCount;

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

/// 竖轴视口高度（同时可见五枚所需的容器高 = itemHeight + 4 × 步距；
/// 步距 = itemHeight + interItemGap。宿主据此钉高度约束）
- (CGFloat)viewportHeight;

/// 竖轴视口下条目步距（宿主口径参考）
- (CGFloat)pitch;

@end

NS_ASSUME_NONNULL_END
