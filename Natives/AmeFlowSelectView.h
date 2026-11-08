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
//     宽 = 视口全宽（★Task409 恒定尺寸）；视口高 = viewportHeight（五枚口径）。
//   - 横轴：条目横向一行，拖动左右滑；当前项与相邻两项同时可见，
//     高 = 视口高（★Task409 恒定尺寸）；条目内容竖排（头像上/名称下，与原
//     头像卡同一呈现语言）。
//   - 拖到哪里就选中哪里：拖动途中只预览（条目随手势连续滑动），手指
//     抬起后弹簧吸附到最近条目，落定下标与上次不同才回调 onSettle
//     （= 选中提交点；拖过头再拖回来不会误选）；
//   - 选中（居中）= 正常大小：零装饰——不加边框/箭头/对勾/描边，着色
//     与未选中完全同款；
//   - ★Task409 恒定尺寸（第 17 轮复诉「左侧图标缩小依旧 + 实例转盘字体被
//     边边挤压成省略号」双根因根修）：旧判例 scale = 1 − 0.15×|d| 整体退役，
//     条目尺寸不随位相变化（图标不再缩小、标签不再变窄，截断面全列均匀）；
//     层级感由 alpha 渐退承接：alpha = 1 − 0.25×|d|（下限 0.25），另加
//     窗缘渐隐带（距可视窗缘 < 0.4 步距时 alpha 线性归零）——条目进出窗
//     零突现零突隐，循环衔接视觉无缝；
//   - 横轴同时可见三枚，竖轴同时可见五枚；首尾循环相连，可无限拖动；
//   - ★Task409 无缝循环槽位复制：逻辑条目数 ≤ 2×可视窗半宽时（小集合
//     接缝落在窗内 = 相位 remainder 跳变可见，第 17 轮「账号转盘没有无限
//     衔接」实体——双账号接缝 |d|=1 全窗可见），组件自动复制槽位把接缝
//     推到窗外（槽位数为逻辑数整倍数）；第 2+ 份槽位由宿主
//     ame_copyFactory 按逻辑下标现建像素同款副本； selectedIndex/
//     setSelectedIndex:/onSettle 全链映射回逻辑下标（宿主零感知）；
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

/// ★Task409 槽位复制工厂（小集合无缝循环）：逻辑下标 → 像素同款新条目。
/// configureItems: 判定需复制时逐逻辑下标调用；返回 nil（或未设置）则
/// 不复制该份及后续份（退回单份 = 旧口径，接缝窗内可见）。
/// 工厂内禁止强引宿主（用 weakSelf，防 组件→工厂→宿主 保留环）。
@property (nonatomic, copy, nullable) UIView *(^ame_copyFactory)(NSUInteger logicalIndex);

/// 交互锁（选中/刷新链进行中锁手势；语义同旧链 modalInPresentation，
/// 锁 = 拖拽/点按不响应，摆位只读）
@property (nonatomic, assign) BOOL interactionLocked;

/// ★Task412 镜像（第 20 轮复诉③「转盘方向不会镜像」）：面板停靠边切换后
/// 转盘随停靠面整体镜像——竖轴弧向外移方向翻转（弧面向屏幕外缘）+ 横轴
/// 排布/拖动/惯性甩动方向翻转（拖动手感与停靠侧同侧化）。NO = 旧口径
/// （停靠左）。置位后立即重摆位（无需重建条目；条目内容由宿主 406a
/// 镜像重建链负责，本属性只管几何与手势向）。
@property (nonatomic, assign) BOOL ame_mirrored;

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
