//
//  ZL2ControlLayoutEditorViewController.h
//  Angel Aura Amethyst
//
//  ★ Task429（PDF 7.3 第三层）：触控布局拖拽编辑器 v1 —— LayerController 式
//    拖拽编辑在 iOS 落地（UIGestureRecognizer 驱动的拖拽 + 8pt 吸附网格 +
//    层管理 BottomSheet），样式库三套预设（默认/半透明/极简）。
//
//  与既有全功能画布编辑器（CustomControlsViewController，UIMenuController +
//  长按菜单 + 撤销 + 安全区编辑）的分工：
//    - 旧编辑器 = 全功能键位编辑（添加控件/键码映射/可见性/安全区）；
//    - 本编辑器 = 「摆」布局的快速通道：拖拽（8pt 吸附网格）、等比缩放、
//      层管理（置顶/置底/上移/下移）、整版样式预设、保存/另存副本。
//    - 数据面完全共用 customcontrols/ 运行时对象（ControlLayout/
//      ControlButton/ControlDrawer/ControlSubButton/ControlJoystick 直接
//      上屏作节点），properties 字典即 JSON 字典本体——拖拽/缩放/层序/
//      样式全部原位写回，保存= NSJSONSerialization 序列化同一棵字典，
//      与运行时（SurfaceViewController loadCustomControls →
//      ControlLayout loadControlFile → loadControlObject）逐位兼容：
//      不新增必填字段、不改任何旧字段语义。
//
//  入口：触控设置页（TouchControllerPreferencesViewController）新增
//  「拖拽编辑布局」按钮行；旧编辑器（CustomControlsViewController）长按
//  菜单同款新增同名入口——喂参走
//  +ame429_presentFromViewController:layoutFileName:（传当前正在编辑的
//  currentFileName，另存副本后与 control.default_ctrl 分叉时以它为准）。
//  呈现方式 = OverFullScreen 直接呈现（判例
//  Task62：全屏画布编辑器禁包 UINavigationController，pageSheet 画布缩水
//  + 容器转发闪退两条前科）。
//
//  红线：
//    - 运行时输入路径只读：SurfaceViewController.m / TouchController/ /
//      GameSurfaceView.m 零改动；本类只消费 customcontrols/ 公开接口。
//    - UI 全令牌（ZL2Theme M3 令牌层），弹层复用 ZL2M3Kit 现成组件
//      （ZL2M3BottomSheet / ZL2M3Dialog），不改动 ZL2M3Kit.m。
//    - JSON 读写容错：坏 JSON / 非字典 / 写盘失败一律吐司报错，不崩。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2ControlLayoutEditorViewController : UIViewController

/// 以 OverFullScreen 直接呈现编辑器（判例 Task62：画布编辑器不包导航容器）。
/// 布局文件解析自 control.default_ctrl 偏好（缺省回落 default.json）。
+ (void)ame429_presentFromViewController:(UIViewController *)host;

/// 同上，但显式指定布局文件名（不含 .json 后缀；nil/空 = 按偏好回落）。
/// 供旧编辑器（CustomControlsViewController）喂「当前正在编辑的文件」：
/// 另存副本后 currentFileName 与 control.default_ctrl 偏好可能分叉，
/// 此时拖拽编辑器须跟随 currentFileName。
+ (void)ame429_presentFromViewController:(UIViewController *)host
                          layoutFileName:(nullable NSString *)fileName;

/// ★ Task436（批次三④ 游戏内入口 + 最小闭环）：同上，但显式带「编辑器退出
/// 回调」——游戏内 SurfaceViewController 呈现本编辑器实时编辑当前布局，
/// 退出（保存并退出 / 放弃退出 / 读取失败退出，三条路径统一走
/// ame436_exitEditor）后回调 onDismiss，宿主按 Task64 既有热重载链
/// （removeAllButtons + loadCustomControls）重载控件，无需重启游戏。
/// nil = 不回调（启动器内既有入口行为零变化）。
+ (void)ame436_presentFromViewController:(UIViewController *)host
                          layoutFileName:(nullable NSString *)fileName
                               onDismiss:(nullable void (^)(void))onDismiss;

/// 当前编辑的布局文件名（不含 .json 后缀；诊断/测试观察用）
@property(nonatomic, copy, readonly) NSString *ame429_layoutFileName;

@end

NS_ASSUME_NONNULL_END
