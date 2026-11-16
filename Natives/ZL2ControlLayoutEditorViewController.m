//
//  ZL2ControlLayoutEditorViewController.m
//  Angel Aura Amethyst
//
//  ★ Task429（PDF 7.3 第三层）：触控布局拖拽编辑器 v1 —— LayerController 式。
//
//  交互模型（UIGestureRecognizer 驱动）：
//    - 节点 = customcontrols/ 运行时对象原班上屏（ControlButton/
//      ControlDrawer/ControlSubButton/ControlJoystick 都是 ControlButton
//      子类，properties 即布局 JSON 的字典本体）。渲染走 loadControlLayout →
//      loadControlObject（与 SurfaceViewController loadCustomControls 同一条
//      代码路径），动态坐标表达式（${screen_width} 等）由运行时类自己解算，
//      编辑器不做第二套渲染实现 → 所见即进游戏所得。
//    - 拖拽：每节点挂 UIPanGestureRecognizer，自由拖拽 + 画布内钳制；拖拽
//      中显示 8pt 吸附网格与坐标微提示（显示的是松手将吸附落点的坐标），
//      松手按 8pt 网格取整吸附后经 generateDynamicX/Y 写回 dynamicX/dynamicY
//      （百分比表达式格式与运行时 generateDynamicX 输出逐位一致）。
//    - 缩放：选中节点出现四角柄，拖任一角柄 = 以对角为锚点等比缩放
//      （比例 = 指尖到锚点距离 / 起始距离），最小 24pt 守卫，松手写回
//      width/height/dynamicX/dynamicY。
//    - 层管理：ZL2M3BottomSheet 弹层，置顶/置底/上移一层/下移一层——同时
//      重排所属 JSON 数组（运行时重载后 z 序 = 数组序：mControlDataList →
//      mDrawerDataList（含 buttonProperties）→ mJoystickDataList 的装载序）
//      与画布 z 序（按运行时装载语义重铺，画布所见 = 重载后所得）。
//    - 样式库三套预设（默认/半透明/极简）：整版套用到全部节点的三个既有
//      schema 字段——opacity（按钮 alpha）/ bgColor（仅改 alpha 字节，保留
//      RGB）/ strokeWidth（描边宽度）。三个字段都是 v7 schema 既有字段，
//      无需新增 style 字段，旧读取完全兼容。
//    - 保存：NSJSONSerialization 序列化编辑中的同一棵 layoutDictionary
//      （NSJSONWritingPrettyPrinted，与既有编辑器保存完全同格式）写回
//      $POJAV_HOME/controlmap/<名>.json；另存副本走同一写出函数 + 文件名
//      输入框。新字段一律不加，旧字段零语义改动（scaledAt 归一化与既有
//      编辑器/运行时装载行为一致，见保存函数注释）。
//
//  互斥语义（第六版 §3.2.7 补充）：本编辑器只在启动器内呈现（非游戏内），
//  游戏侧手势三态/触觉反馈路径天然不在场，无「编辑态挂起」需求；入场置
//  isControlModifiable=YES（离场复位 NO）即接管 customcontrols 全族手势/
//  触觉分支，与游戏内手势零并发。
//
//  判例族对齐：id 变量消息语法 / block 赋值 __block / static C 函数定义
//  先于调用 / anchor multiplier 用三参 multiplier:constant: 形式 / 常量实名
//  （NSJSONWritingPrettyPrinted、NSDataWritingAtomic 均为系统实名）/ 禁
//  @(nullable) boxed（所有装箱前先取实值）/ 注释 ★Task429。
//

#import "ZL2ControlLayoutEditorViewController.h"

#import "customcontrols/ControlButton.h"
#import "customcontrols/ControlDrawer.h"
#import "customcontrols/ControlJoystick.h"
#import "customcontrols/ControlLayout.h"
#import "customcontrols/ControlSubButton.h"
#import "customcontrols/CustomControlsUtils.h"
#import "LauncherPreferences.h"
#import "NMToast.h"
#import "ZL2M3Kit.h"
#import "ZL2Theme.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#import <QuartzCore/QuartzCore.h>

// ============================================================================
// 常量（实名，全文件唯一定义点）
// ============================================================================
static const CGFloat ame429_gridStep = 8.0;          // 吸附网格步长（pt）
static const CGFloat ame429_minNodeSize = 24.0;      // 等比缩放最小边守卫（pt）
static const CGFloat ame429_topBarHeight = 52.0;     // 顶部 M3 工具条高
static const CGFloat ame429_topBarMargin = 12.0;     // 工具条左右缘距
static const CGFloat ame429_handleVisual = 14.0;     // 角柄可视边长
static const CGFloat ame429_handleTouch = 34.0;      // 角柄触控边长

// ============================================================================
// 枚举（定义先于任何使用点）
// ============================================================================

/// 节点类别（决定层管理的所属数组与显示名）
typedef NS_ENUM(NSInteger, Ame429NodeKind) {
    Ame429NodeKindButton = 0,     // mControlDataList 主按钮
    Ame429NodeKindDrawer,         // mDrawerDataList 抽屉（本体）
    Ame429NodeKindSubButton,      // 抽屉内子键（buttonProperties）
    Ame429NodeKindJoystick,       // mJoystickDataList 摇杆
};

/// 层管理操作方向
typedef NS_ENUM(NSInteger, Ame429LayerOp) {
    Ame429LayerOpToFront,
    Ame429LayerOpToBack,
    Ame429LayerOpForward,
    Ame429LayerOpBackward,
};

/// 样式预设三参数（按钮 alpha / 背景 alpha 字节 / 描边宽）
typedef struct {
    CGFloat buttonAlpha;
    NSInteger bgAlphaByte;
    CGFloat strokeWidth;
} Ame429StyleParams;

// ============================================================================
// static C 工具函数（定义先于调用；★Task429）
// ============================================================================

/// controlmap 目录（与 ControlLayout loadControlFile 的 getenv("POJAV_HOME")
/// 同源路径，唯一差别是本函数不带文件名段）
static NSString *ame429_controlmapDir(void) {
    return [NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")];
}

/// 布局文件绝对路径（fileName 不含 .json 后缀）
static NSString *ame429_layoutFilePath(NSString *fileName) {
    return [NSString stringWithFormat:@"%@/%@.json", ame429_controlmapDir(), fileName];
}

/// 当前默认布局名：control.default_ctrl 偏好（缺省/空回落 default，即
/// default.json——本文件 fileName 契约不含 .json 后缀；与 ControlLayout
/// Task64 回落语义一致）
static NSString *ame429_defaultLayoutFileName(void) {
    NSString *stored = getPrefObject(@"control.default_ctrl");
    if (![stored isKindOfClass:[NSString class]] || stored.length == 0) {
        return @"default";
    }
    if ([stored hasSuffix:@".json"]) {
        stored = [stored substringToIndex:stored.length - 5];
    }
    if (stored.length == 0) return @"default";   // 异形偏好（恰为 ".json"）回落
    return stored;
}

/// 文件名净化：去首尾空白、剥 .json 后缀；空串/含路径分隔符 = 非法返回 nil。
/// 返回 nil 由调用方吐司（保存用名不合法不落盘）。
static NSString *ame429_sanitizedFileName(NSString *raw) {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    if ([trimmed hasSuffix:@".json"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 5];
    }
    if (trimmed.length == 0) return nil;
    if ([trimmed containsString:@"/"] || [trimmed containsString:@"\\"]) return nil;
    return trimmed;
}

/// JSON 数值 → ARGB 长整（strokeColor 历史文件里存过 -1 = 0xFFFFFFFF；
/// 负值按 32 位补码还原，避免 alpha 字节算术移位踩符号位）
static long long ame429_argbFromNumber(NSNumber *num) {
    long long v = num.longLongValue;
    if (v < 0) v &= 0xFFFFFFFFLL;
    return v;
}

/// 样式预设参数表（0=默认 / 1=半透明 / 2=极简）
static Ame429StyleParams ame429_paramsForPreset(NSInteger preset) {
    Ame429StyleParams p;
    if (preset == 1) {          // 半透明
        p.buttonAlpha = 0.55; p.bgAlphaByte = 0x1E; p.strokeWidth = 0.5;
    } else if (preset == 2) {   // 极简
        p.buttonAlpha = 0.85; p.bgAlphaByte = 0x12; p.strokeWidth = 0.0;
    } else {                    // 默认（出厂档：0x4d000000 + 全不透明）
        p.buttonAlpha = 1.0; p.bgAlphaByte = 0x4D; p.strokeWidth = 1.0;
    }
    return p;
}

/// 对单个节点字典套用样式预设（只动 opacity/bgColor-alpha/strokeWidth 三个
/// 既有字段；bgColor 仅在字段以 NSNumber 在场时重写 alpha 字节、保留 RGB）。
static void ame429_applyStyleToProperties(NSMutableDictionary *props,
                                          Ame429StyleParams params) {
    if (![props isKindOfClass:[NSMutableDictionary class]]) {
        // fail-loud（第六版 N1/N2 判例：守卫不得把异常藏成静默失效）
        NSLog(@"[Task429] style preset: properties not mutable dict, skipped (anomalous data shape)");
        return;
    }
    props[@"opacity"] = @(params.buttonAlpha);
    props[@"strokeWidth"] = @(params.strokeWidth);
    NSNumber *bg = props[@"bgColor"];
    if ([bg isKindOfClass:[NSNumber class]]) {
        long long rgb = ame429_argbFromNumber(bg) & 0x00FFFFFFLL;
        props[@"bgColor"] = @(rgb | ((long long)params.bgAlphaByte << 24));
    }
}

/// 节点视图 → 类别（ControlButton 子类按最派生类判别）
static Ame429NodeKind ame429_kindOfNode(UIView *node) {
    if ([node isKindOfClass:[ControlSubButton class]]) return Ame429NodeKindSubButton;
    if ([node isKindOfClass:[ControlJoystick class]]) return Ame429NodeKindJoystick;
    if ([node isKindOfClass:[ControlDrawer class]]) return Ame429NodeKindDrawer;
    if ([node isKindOfClass:[ControlButton class]]) return Ame429NodeKindButton;
    return Ame429NodeKindButton;
}

/// 节点所属 JSON 列表（mutable，供层管理重排）：
///   Button → mControlDataList / Drawer → mDrawerDataList（以 drawerData 为
///   元素）/ SubButton → 父抽屉 buttonProperties / Joystick → mJoystickDataList。
/// 找不到所属列表（异常数据形态）返回 nil，层操作原地跳过。
static NSMutableArray *ame429_owningListForNode(UIView *node,
                                                NSMutableDictionary *layoutDict) {
    Ame429NodeKind kind = ame429_kindOfNode(node);
    if (kind == Ame429NodeKindSubButton) {
        ControlDrawer *parent = ((ControlSubButton *)node).parentDrawer;
        if (parent == nil) {
            // fail-loud（第六版 N1/N2 判例：守卫不得把实现缺失藏成静默失效）
            NSLog(@"[Task429] layer op: subbutton parentDrawer missing (anomalous data shape)");
            return nil;
        }
        id list = parent.drawerData[@"buttonProperties"];
        if ([list isKindOfClass:[NSMutableArray class]]) return list;
        NSLog(@"[Task429] layer op: drawer buttonProperties not NSMutableArray (anomalous data shape)");
        return nil;
    }
    NSString *key = nil;
    id element = nil;
    if (kind == Ame429NodeKindDrawer) {
        key = @"mDrawerDataList";
        element = ((ControlDrawer *)node).drawerData;
    } else if (kind == Ame429NodeKindJoystick) {
        key = @"mJoystickDataList";
        element = ((ControlButton *)node).properties;
    } else {
        key = @"mControlDataList";
        element = ((ControlButton *)node).properties;
    }
    id list = layoutDict[key];
    if ([list isKindOfClass:[NSMutableArray class]] && element != nil) return list;
    NSLog(@"[Task429] layer op: owning list %@ missing/not mutable (anomalous data shape)", key);
    return nil;
}

/// 节点在所属列表里的元素（层管理以元素身份查 index）
static id ame429_listElementForNode(UIView *node) {
    Ame429NodeKind kind = ame429_kindOfNode(node);
    if (kind == Ame429NodeKindDrawer) return ((ControlDrawer *)node).drawerData;
    return ((ControlButton *)node).properties;
}

// ============================================================================
// 弹层行（M3 行件：标题 + 副标题 + 点击回调；本文件私有，不动 ZL2M3Kit）
// ============================================================================
@interface Ame429SheetRowView : UIControl
@property(nonatomic, copy) void (^ame429_onTap)(void);
- (instancetype)initWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                         destructive:(BOOL)destructive;
@end

@implementation Ame429SheetRowView

- (instancetype)initWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                         destructive:(BOOL)destructive {
    self = [super initWithFrame:CGRectZero];
    if (!self) return self;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [ZL2Theme surfaceContainer];
    self.layer.cornerRadius = [ZL2Theme radiusM];
    self.layer.masksToBounds = YES;

    UILabel *titleLab = [[UILabel alloc] init];
    titleLab.translatesAutoresizingMaskIntoConstraints = NO;
    titleLab.font = [ZL2Theme fontTitleMedium];
    titleLab.textColor = destructive ? [ZL2Theme error] : [ZL2Theme onSurface];
    titleLab.text = title;
    [self addSubview:titleLab];

    UILabel *subLab = nil;
    if (subtitle.length > 0) {
        subLab = [[UILabel alloc] init];
        subLab.translatesAutoresizingMaskIntoConstraints = NO;
        subLab.font = [ZL2Theme fontBodyMedium];
        subLab.textColor = [ZL2Theme onSurfaceVariant];
        subLab.numberOfLines = 2;
        subLab.text = subtitle;
        [self addSubview:subLab];
    }

    [self addTarget:self action:@selector(ame429_rowTapped) forControlEvents:UIControlEventTouchUpInside];
    // 按压反馈（M3 state layer 语义：onSurface 6% 蒙层）
    [self addTarget:self action:@selector(ame429_rowPressed) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(ame429_rowNormal)
   forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    UILayoutGuide *safe = self.layoutMarginsGuide;
    if (subLab != nil) {
        [NSLayoutConstraint activateConstraints:@[
            [titleLab.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [titleLab.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [titleLab.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [subLab.topAnchor constraintEqualToAnchor:titleLab.bottomAnchor constant:2],
            [subLab.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [subLab.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [subLab.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    } else {
        // 单行版：标题垂直居中（锚点用三参 multiplier:constant: 形式——判例族）
        [NSLayoutConstraint activateConstraints:@[
            [titleLab.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [titleLab.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [titleLab.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [titleLab.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                 multiplier:0.5 constant:-10],
        ]];
    }
    return self;
}

- (void)ame429_rowTapped {
    void (^tap)(void) = self.ame429_onTap;
    self.backgroundColor = [ZL2Theme surfaceContainer];
    if (tap) tap();
}

- (void)ame429_rowPressed {
    self.backgroundColor = [[ZL2Theme onSurface] colorWithAlphaComponent:0.06];
}

- (void)ame429_rowNormal {
    self.backgroundColor = [ZL2Theme surfaceContainer];
}

@end

// ============================================================================
// 编辑器本体
// ============================================================================
@interface ZL2ControlLayoutEditorViewController () <UIGestureRecognizerDelegate>

@property(nonatomic, strong) ControlLayout *canvas;
@property(nonatomic, strong) NSMutableDictionary *layoutDict;
@property(nonatomic, copy, readwrite) NSString *ame429_layoutFileName;
@property(nonatomic, assign) BOOL ame429_dirty;

// 顶部 M3 工具条
@property(nonatomic, strong) UIView *topBar;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *layerButton;
@property(nonatomic, strong) UIButton *styleButton;
@property(nonatomic, strong) UIButton *moreButton;
@property(nonatomic, strong) UIButton *saveButton;

// 选择态：描边框 + 四角柄 + 坐标微提示
@property(nonatomic, strong) UIView *selectionFrame;
@property(nonatomic, strong) NSMutableArray<UIView *> *cornerHandles;
@property(nonatomic, strong) UILabel *coordHint;

// 8pt 吸附网格（拖拽/缩放过程显示）
@property(nonatomic, strong) UIView *gridView;

// 手势状态
@property(nonatomic, weak) ControlButton *selectedNode;   // 当前选中节点
@property(nonatomic, weak) ControlButton *activeNode;     // 正在拖拽/缩放的节点
@property(nonatomic, assign) CGRect ame429_resizeStartFrame;
@property(nonatomic, assign) CGPoint ame429_resizeAnchor; // 对角锚点（画布坐标）

// 层管理弹层打开期间的信息行（onDismiss 置 nil 结束引用）
@property(nonatomic, strong, nullable) UILabel *layerSheetInfoLabel;

// 入口喂参（工位 3-d）：宿主编辑器当前正在编辑的布局名（不含 .json；
// nil/空 = 按 control.default_ctrl 偏好回落，见 ame429_loadLayout）
@property(nonatomic, copy, nullable) NSString *ame429_layoutFileNameOverride;

// ★ Task436（批次三·编辑器最小闭环）：新建/属性两工具钮 + 退出回调 +
//   新建计数（居中放置漂移防精确重叠）
@property(nonatomic, strong) UIButton *addButton;      // 新建控件（三类）
@property(nonatomic, strong) UIButton *propsButton;    // 控件属性面板
@property(nonatomic, copy, nullable) void (^ame436_onDismiss)(void);
@property(nonatomic, assign) NSInteger ame436_createdCount;
@end

// ============================================================================
// ★Task436 私有面板件——类声明前置（★Task436-r3）：主实现方法体
// （ame436_showPropsSheet :1916 起引用 Ame436BlockTextField/Ame436SpecialKeyGrid
// 等）要求类先声明——ObjC 方法体内类引用必须先见 @interface，@class 前置
// 声明不足以访问 property（borderStyle/font/ame436_onChange 等）。声明在上、
// 实现在下（文件尾）的标准私有类布局；本文件私有，不新增 TU、不动 ZL2M3Kit。
// ============================================================================

/// 块回调滑条（UIControl 系统族只收 selector，面板行内联回调走块属性）
@interface Ame436BlockSlider : UISlider
@property(nonatomic, copy) void (^ame436_onChange)(CGFloat value);
@end

/// 块回调开关
@interface Ame436BlockSwitch : UISwitch
@property(nonatomic, copy) void (^ame436_onChange)(BOOL on);
@end

/// 块回调分段
@interface Ame436BlockSegment : UISegmentedControl
@property(nonatomic, copy) void (^ame436_onChange)(NSInteger idx);
@end

/// 块回调文本框（EditingChanged 逐字符回调）
@interface Ame436BlockTextField : UITextField
@property(nonatomic, copy) void (^ame436_onChange)(NSString *text);
@end

/// 启动器动作（特殊键）单选网格：3 列 × 4 行 chip（10 项）。值域 = 本运行时
/// 特殊键族（utils.h SPECIALBTN_*，0 = 无）——与 SurfaceViewController
/// executebtn 特殊键分发表（case SPECIALBTN_*）一一对应，即 iOS 侧「启动器
/// 事件」既有面（ZL2 基准 launch.ui 动作枚举在本仓无对应运行时面，不硬造）。
@interface Ame436SpecialKeyGrid : UIView
- (instancetype)initWithCurrentValue:(NSInteger)current
                            onChange:(void (^)(NSInteger value))onChange;
@end

@implementation ZL2ControlLayoutEditorViewController

+ (void)ame429_presentFromViewController:(UIViewController *)host {
    [self ame429_presentFromViewController:host layoutFileName:nil];
}

+ (void)ame429_presentFromViewController:(UIViewController *)host
                          layoutFileName:(NSString *)fileName {
    // ★ Task436：既有入口委托到带退出回调的新入口（nil = 不回调，行为零变化）
    [self ame436_presentFromViewController:host layoutFileName:fileName onDismiss:nil];
}

+ (void)ame436_presentFromViewController:(UIViewController *)host
                          layoutFileName:(NSString *)fileName
                               onDismiss:(void (^)(void))onDismiss {
    ZL2ControlLayoutEditorViewController *editor =
        [[ZL2ControlLayoutEditorViewController alloc] init];
    editor.ame429_layoutFileNameOverride = fileName;
    // ★ Task436（批次三④ 游戏内入口）：退出回调（宿主热重载控件用）
    editor.ame436_onDismiss = onDismiss;
    // 判例 Task62：全屏画布编辑器 OverFullScreen 直接呈现，不包导航容器
    editor.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [host presentViewController:editor animated:YES completion:nil];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    // ★ 编辑态总闸（customcontrols/ 全族手势/穿透/可见性都读这个全局）。
    //   与 CustomControlsViewController 同约定：入场 YES、离场 NO。
    isControlModifiable = YES;

    self.view.backgroundColor = [ZL2Theme surface];

    // 画布 = 控件安全区矩形（与运行时 ControlLayout 渲染域、既有编辑器同源）
    self.canvas = [[ControlLayout alloc] initWithFrame:getSafeArea(self.view.frame)];
    self.canvas.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    self.canvas.layer.borderWidth = 1.0;
    self.canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.canvas];

    // 画布空白处点按 = 取消选中（delegate 过滤：只收画布本体的触摸）
    UITapGestureRecognizer *canvasTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(ame429_canvasTapped:)];
    canvasTap.delegate = self;
    [self.canvas addGestureRecognizer:canvasTap];

    [self ame429_setupChrome];
    [self ame429_setupOverlay];

    if (![self ame429_loadLayout]) {
        // 坏 JSON / 缺文件：吐司后退出（不崩，不留白屏编辑器）。
        // ★ Task436：退出统一走 ame436_exitEditor（onDismiss 回调链）
        [NMToast showMessage:localize(@"ame429.j.load.error", @"布局文件读取失败，请检查 controlmap 内的 JSON 文件")];
        [self ame436_exitEditor];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // 画布 = 控件安全区（getSafeArea 含用户自配 control_safe_area，与运行时一致）
    self.canvas.frame = getSafeArea(self.view.frame);
    self.gridView.frame = self.view.bounds;

    // 动态坐标重解算（表达式含 ${screen_width} 系，转屏/布局变化后必须重算；
    // 与既有编辑器 viewDidLayoutSubviews 同款）
    for (UIView *nodeView in self.canvas.subviews) {
        if ([nodeView isKindOfClass:[ControlButton class]]) {
            [(ControlButton *)nodeView update];
        }
    }

    [self ame429_layoutChrome];
    [self ame429_rebuildGridPath];
    [self ame429_layoutSelectionOverlay];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // ★ 编辑态总闸还原（全局变量，离场必复位——否则运行时控件停留在可编辑态）
    isControlModifiable = NO;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return getPrefBool(@"debug.debug_hide_home_indicator");
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - 布局装载

/// 装载当前默认布局。返回 NO = 坏 JSON / 非字典（调用方吐司退出）。
/// parseJSONFromFile 失败时返回带 NSErrorObject 的字典（Task64 同款容错约定）。
- (BOOL)ame429_loadLayout {
    // 入口喂参优先：宿主编辑器显式喂的 currentFileName（工位 3-d，另存副本
    // 后与 control.default_ctrl 分叉时以它为准）> 偏好回落。净化剥 .json/
    // 空白，非法（nil）= 回落默认布局。
    NSString *fileName = ame429_sanitizedFileName(self.ame429_layoutFileNameOverride)
                             ?: ame429_defaultLayoutFileName();
    NSMutableDictionary *dict = parseJSONFromFile(ame429_layoutFilePath(fileName));
    if (dict == nil || ![dict isKindOfClass:[NSMutableDictionary class]] || dict[@"NSErrorObject"] != nil) {
        NSLog(@"[Task429] layout parse failed: %@ (NSErrorObject present)", fileName);
        return NO;
    }

    self.ame429_layoutFileName = fileName;
    self.layoutDict = dict;

    // 列表键缺省补空数组（异形布局容错：空布局也允许进编辑器摆新东西）
    if (![dict[@"mControlDataList"] isKindOfClass:[NSMutableArray class]]) {
        dict[@"mControlDataList"] = [NSMutableArray array];
    }
    if (![dict[@"mDrawerDataList"] isKindOfClass:[NSMutableArray class]]) {
        dict[@"mDrawerDataList"] = [NSMutableArray array];
    }
    if (![dict[@"mJoystickDataList"] isKindOfClass:[NSMutableArray class]]) {
        dict[@"mJoystickDataList"] = [NSMutableArray array];
    }

    // ★Task434 P0-1: 守卫下沉到实际被消费的深层键（读到哪层护到哪层）——
    //   三列表元素须为字典，异形剔除留痕（Favorites 家法）；抽屉元素
    //   buttonProperties 须为数组（非数组跳过该键补空）、其元素须为字典
    //   （异形剔除）。失败语义沿用上方键级容错（补空/剔除 + 留痕，不整体
    //   拒载——整体拒载仅留给坏 JSON/非字典）；运行时 loadControlObject 对
    //   三列表与 buttonProperties 的快枚举无 @try 兜底，须先净化再喂。
    for (NSString *listKey in @[@"mControlDataList", @"mDrawerDataList", @"mJoystickDataList"]) {
        NSMutableArray *list = dict[listKey];
        NSMutableIndexSet *alienIdx = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < list.count; i++) {
            if (![list[i] isKindOfClass:[NSDictionary class]]) [alienIdx addIndex:i];
        }
        if (alienIdx.count > 0) {
            NSLog(@"[Task429][Task434] %@ 异形元素 %lu 条已剔除",
                  listKey, (unsigned long)alienIdx.count);
            [list removeObjectsAtIndexes:alienIdx];
        }
    }
    for (NSMutableDictionary *drawerData in dict[@"mDrawerDataList"]) {
        id subButtons = drawerData[@"buttonProperties"];
        if (subButtons == nil) continue;   // 缺省 = 无子按钮，放行
        if (![subButtons isKindOfClass:[NSArray class]]) {
            NSLog(@"[Task429][Task434] drawer.buttonProperties 异形(非数组)已补空");
            drawerData[@"buttonProperties"] = [NSMutableArray array];
            continue;
        }
        // MutableContainers 解析保证数组可变，可直接按索引剔除异形子按钮
        NSMutableArray *subList = subButtons;
        NSMutableIndexSet *alienSub = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < subList.count; i++) {
            if (![subList[i] isKindOfClass:[NSDictionary class]]) [alienSub addIndex:i];
        }
        if (alienSub.count > 0) {
            NSLog(@"[Task429][Task434] buttonProperties 异形子按钮 %lu 条已剔除",
                  (unsigned long)alienSub.count);
            [subList removeObjectsAtIndexes:alienSub];
        }
    }

    // 运行时同款装载（loadControlObject 内含 convertLayoutIfNecessary 旧版
    // 迁移 + scaledAt 归一化；isControlModifiable=YES 已让抽屉子键展开可见）
    [self.canvas loadControlLayout:dict];

    // 节点挂手势：点按选中 / 拖拽移动
    [self ame429_attachGestures];

    self.ame429_dirty = NO;
    [self ame429_refreshTitle];
    return YES;
}

- (void)ame429_attachGestures {
    for (UIView *nodeView in [self.canvas.subviews copy]) {
        [self ame429_attachGesturesToNode:nodeView];
    }
}

/// ★ Task436：单节点手势挂接（点按选中 / 拖拽移动）——装载批量挂接与本轮
///   新建/克隆的单节点挂接共用，避免重复挂手势（老实现整画布循环只跑一次，
///   新建/克隆路径若复用整循环会重复叠手势）。
- (void)ame429_attachGesturesToNode:(UIView *)nodeView {
    if (![nodeView isKindOfClass:[ControlButton class]]) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(ame429_nodeTapped:)];
    [nodeView addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(ame429_nodePanned:)];
    pan.maximumNumberOfTouches = 1;
    [nodeView addGestureRecognizer:pan];
}

#pragma mark - 顶部工具条（M3）

- (void)ame429_setupChrome {
    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [ZL2Theme surfaceContainer];
    self.topBar.layer.cornerRadius = [ZL2Theme radiusL];
    self.topBar.layer.masksToBounds = YES;
    [self.view addSubview:self.topBar];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.closeButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.closeButton addTarget:self action:@selector(ame429_closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [ZL2Theme fontTitleMedium];
    self.titleLabel.textColor = [ZL2Theme onSurface];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.topBar addSubview:self.titleLabel];

    self.layerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.layerButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.layerButton setImage:[UIImage systemImageNamed:@"square.stack.3d.up"] forState:UIControlStateNormal];
    self.layerButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.layerButton addTarget:self action:@selector(ame429_layerButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.layerButton];

    self.styleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.styleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.styleButton setImage:[UIImage systemImageNamed:@"paintpalette"] forState:UIControlStateNormal];
    self.styleButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.styleButton addTarget:self action:@selector(ame429_styleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.styleButton];

    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreButton setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    self.moreButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.moreButton addTarget:self action:@selector(ame429_moreButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.moreButton];

    // ★ Task436（批次三①②）：新建控件（按键/文本框/摇杆三类）与控件属性
    self.addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    self.addButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.addButton addTarget:self action:@selector(ame436_addButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.addButton];

    self.propsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.propsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.propsButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    self.propsButton.tintColor = [ZL2Theme onSurfaceVariant];
    [self.propsButton addTarget:self action:@selector(ame436_propsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.propsButton];

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveButton.backgroundColor = [ZL2Theme primary];
    self.saveButton.layer.cornerRadius = [ZL2Theme radiusM];
    self.saveButton.tintColor = [ZL2Theme onPrimary];
    [self.saveButton setTitle:localize(@"ame429.j.toolbar.save", @"保存") forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [self.saveButton addTarget:self action:@selector(ame429_saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.saveButton];
}

- (void)ame429_layoutChrome {
    CGFloat viewW = self.view.frame.size.width;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    self.topBar.frame = CGRectMake(ame429_topBarMargin, safeTop + 8.0,
                                   viewW - ame429_topBarMargin * 2.0, ame429_topBarHeight);

    CGFloat barH = self.topBar.frame.size.height;
    CGFloat centerY = barH / 2.0;
    CGFloat x = 8.0;

    self.closeButton.frame = CGRectMake(x, centerY - 18.0, 36.0, 36.0);
    x += 36.0 + 6.0;

    // 右侧簇：新建 / 属性 / 层 / 样式 / 更多 / 保存（★Task436 右簇增两钮）
    CGFloat saveW = 76.0;
    CGFloat iconW = 38.0;
    CGFloat gap = 2.0;
    CGFloat rightX = self.topBar.frame.size.width - 8.0;
    self.saveButton.frame = CGRectMake(rightX - saveW, centerY - 16.0, saveW, 32.0);
    rightX -= saveW + gap;
    self.moreButton.frame = CGRectMake(rightX - iconW, centerY - 18.0, iconW, 36.0);
    rightX -= iconW + gap;
    self.styleButton.frame = CGRectMake(rightX - iconW, centerY - 18.0, iconW, 36.0);
    rightX -= iconW + gap;
    self.layerButton.frame = CGRectMake(rightX - iconW, centerY - 18.0, iconW, 36.0);
    rightX -= iconW + gap;
    self.propsButton.frame = CGRectMake(rightX - iconW, centerY - 18.0, iconW, 36.0);
    rightX -= iconW + gap;
    self.addButton.frame = CGRectMake(rightX - iconW, centerY - 18.0, iconW, 36.0);

    // 标题居中于左右簇之间
    CGFloat titleX = x;
    CGFloat titleW = rightX - 4.0 - titleX;
    if (titleW < 24.0) titleW = 24.0;
    self.titleLabel.frame = CGRectMake(titleX, centerY - 10.0, titleW, 20.0);
}

#pragma mark - 覆盖层（选择框/角柄/网格/微提示）

- (void)ame429_setupOverlay {
    // 8pt 吸附网格（拖拽/缩放过程显示；不拦截触摸）
    self.gridView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.gridView.userInteractionEnabled = NO;
    self.gridView.hidden = YES;
    self.gridView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.gridView];

    self.selectionFrame = [[UIView alloc] init];
    self.selectionFrame.userInteractionEnabled = NO;
    self.selectionFrame.layer.borderColor = [ZL2Theme primary].CGColor;
    self.selectionFrame.layer.borderWidth = 1.5;
    self.selectionFrame.layer.cornerRadius = 2.0;
    self.selectionFrame.hidden = YES;
    [self.view addSubview:self.selectionFrame];

    self.cornerHandles = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        // 触控热区 34×34，可视点 14×14 居中（角柄拖 = 等比缩放）
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ame429_handleTouch, ame429_handleTouch)];
        handle.backgroundColor = [UIColor clearColor];
        handle.tag = i;   // 0=左上 1=右上 2=左下 3=右下

        UIView *knob = [[UIView alloc] initWithFrame:
            CGRectMake((ame429_handleTouch - ame429_handleVisual) / 2.0,
                       (ame429_handleTouch - ame429_handleVisual) / 2.0,
                       ame429_handleVisual, ame429_handleVisual)];
        knob.backgroundColor = [ZL2Theme primary];
        knob.layer.cornerRadius = 3.0;
        knob.layer.borderWidth = 1.0;
        knob.layer.borderColor = [ZL2Theme surface].CGColor;
        knob.userInteractionEnabled = NO;
        knob.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [handle addSubview:knob];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(ame429_handlePanned:)];
        [handle addGestureRecognizer:pan];

        handle.hidden = YES;
        [self.view addSubview:handle];
        [self.cornerHandles addObject:handle];
    }

    self.coordHint = [[UILabel alloc] init];
    self.coordHint.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordHint.font = [ZL2Theme fontLabelMedium];
    self.coordHint.textColor = [ZL2Theme onPrimaryContainer];
    self.coordHint.backgroundColor = [ZL2Theme primaryContainer];
    self.coordHint.textAlignment = NSTextAlignmentCenter;
    self.coordHint.layer.cornerRadius = [ZL2Theme radiusS];
    self.coordHint.layer.masksToBounds = YES;
    self.coordHint.hidden = YES;
    [self.view addSubview:self.coordHint];

    // 微提示定位：画布顶缘下方居中（固定点，不跟手指——不挡拖拽落点）
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.coordHint.topAnchor constraintEqualToAnchor:safe.topAnchor
                                                 constant:ame429_topBarHeight + 20.0],
        [self.coordHint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.coordHint.widthAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [self.coordHint.heightAnchor constraintEqualToConstant:26.0],
    ]];
}

- (void)ame429_rebuildGridPath {
    CAShapeLayer *gridLayer = nil;
    for (CALayer *sub in self.gridView.layer.sublayers) {
        if ([sub isKindOfClass:[CAShapeLayer class]]) { gridLayer = (CAShapeLayer *)sub; break; }
    }
    if (gridLayer == nil) {
        gridLayer = [[CAShapeLayer alloc] init];
        gridLayer.strokeColor = [ZL2Theme outlineVariant].CGColor;
        gridLayer.fillColor = NULL;
        gridLayer.lineWidth = 1.0 / UIScreen.mainScreen.scale;
        gridLayer.opacity = 0.35;
        [self.gridView.layer addSublayer:gridLayer];
    }
    gridLayer.frame = self.gridView.bounds;

    CGRect rect = self.gridView.bounds;
    if (rect.size.width <= 0 || rect.size.height <= 0) return;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (CGFloat gx = ame429_gridStep; gx < rect.size.width; gx += ame429_gridStep) {
        [path moveToPoint:CGPointMake(gx, 0)];
        [path addLineToPoint:CGPointMake(gx, rect.size.height)];
    }
    for (CGFloat gy = ame429_gridStep; gy < rect.size.height; gy += ame429_gridStep) {
        [path moveToPoint:CGPointMake(0, gy)];
        [path addLineToPoint:CGPointMake(rect.size.width, gy)];
    }
    gridLayer.path = path.CGPath;
}

/// 节点 frame（画布坐标）→ 选择框/角柄 frame（本视图坐标）
- (CGRect)ame429_overlayRectForNodeFrame:(CGRect)nodeFrame {
    CGPoint off = self.canvas.frame.origin;
    return CGRectMake(off.x + nodeFrame.origin.x, off.y + nodeFrame.origin.y,
                      nodeFrame.size.width, nodeFrame.size.height);
}

- (void)ame429_layoutSelectionOverlay {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) {
        self.selectionFrame.hidden = YES;
        for (UIView *handle in self.cornerHandles) handle.hidden = YES;
        return;
    }
    CGRect rect = [self ame429_overlayRectForNodeFrame:node.frame];

    self.selectionFrame.frame = CGRectMake(rect.origin.x - 2.0, rect.origin.y - 2.0,
                                           rect.size.width + 4.0, rect.size.height + 4.0);
    self.selectionFrame.hidden = NO;

    CGFloat cx = rect.origin.x + rect.size.width / 2.0;
    CGFloat cy = rect.origin.y + rect.size.height / 2.0;
    CGFloat half = ame429_handleTouch / 2.0;
    CGRect handleRects[4] = {
        CGRectMake(rect.origin.x - half, rect.origin.y - half, ame429_handleTouch, ame429_handleTouch), // 左上
        CGRectMake(cx - half, rect.origin.y - half, ame429_handleTouch, ame429_handleTouch),            // 右上
        CGRectMake(rect.origin.x - half, cy - half, ame429_handleTouch, ame429_handleTouch),            // 左下
        CGRectMake(cx - half, cy - half, ame429_handleTouch, ame429_handleTouch),                       // 右下
    };
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = self.cornerHandles[i];
        handle.frame = handleRects[i];
        handle.hidden = NO;
    }
}

#pragma mark - 选择 / 取消选中

- (void)ame429_nodeTapped:(UITapGestureRecognizer *)sender {
    UIView *nodeView = sender.view;
    if (![nodeView isKindOfClass:[ControlButton class]]) return;
    self.selectedNode = (ControlButton *)nodeView;
    [self ame429_layoutSelectionOverlay];
}

- (void)ame429_canvasTapped:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    self.selectedNode = nil;
    [self ame429_layoutSelectionOverlay];
}

// 只收画布本体（非节点）的触摸进"取消选中"路径——节点自身的 tap 已另行接管
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldReceiveTouch:(UITouch *)touch {
    return touch.view == self.canvas;
}

#pragma mark - 拖拽（UIGestureRecognizer 驱动 + 8pt 吸附）

- (void)ame429_nodePanned:(UIPanGestureRecognizer *)sender {
    UIView *nodeView = sender.view;
    if (![nodeView isKindOfClass:[ControlButton class]]) return;
    ControlButton *node = (ControlButton *)nodeView;

    // 非 FREE 抽屉的子键位置由抽屉排列规则推导，禁拖（与既有编辑器同口径）
    if ([node isKindOfClass:[ControlSubButton class]]) {
        NSString *orientation = ((ControlSubButton *)node).parentDrawer.drawerData[@"orientation"];
        if (![orientation isKindOfClass:[NSString class]] || ![orientation isEqualToString:@"FREE"]) return;
    }

    CGPoint translation = [sender translationInView:self.view];
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.activeNode = node;
        self.selectedNode = node;
        [self ame429_layoutSelectionOverlay];
        self.gridView.hidden = NO;
        self.coordHint.hidden = NO;
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        // 节点 frame 是画布坐标；位移 delta 跨同层视图坐标不变，直接累加
        CGRect frame = node.frame;
        CGFloat maxOriginX = MAX(0.0, self.canvas.frame.size.width - frame.size.width);
        CGFloat maxOriginY = MAX(0.0, self.canvas.frame.size.height - frame.size.height);
        CGFloat nx = MAX(0.0, MIN(frame.origin.x + translation.x, maxOriginX));
        CGFloat ny = MAX(0.0, MIN(frame.origin.y + translation.y, maxOriginY));
        frame.origin = CGPointMake(nx, ny);
        node.frame = frame;
        [self ame429_layoutSelectionOverlay];

        // 微提示显示松手将吸附的落点（8pt 取整 + 钳制后坐标）
        CGPoint snapped = [self ame429_snappedOriginForFrame:frame];
        self.coordHint.text = [NSString stringWithFormat:@"x %.0f · y %.0f", snapped.x, snapped.y];
    } else if (sender.state == UIGestureRecognizerStateEnded ||
               sender.state == UIGestureRecognizerStateCancelled) {
        [self ame429_commitNodeFrame:node];
        self.activeNode = nil;
        self.gridView.hidden = YES;
        self.coordHint.hidden = YES;
    }
}

/// 8pt 吸附落点（画布坐标；越界钳制在画布内）
- (CGPoint)ame429_snappedOriginForFrame:(CGRect)frame {
    CGFloat maxOriginX = MAX(0.0, self.canvas.frame.size.width - frame.size.width);
    CGFloat maxOriginY = MAX(0.0, self.canvas.frame.size.height - frame.size.height);
    CGFloat sx = round(frame.origin.x / ame429_gridStep) * ame429_gridStep;
    CGFloat sy = round(frame.origin.y / ame429_gridStep) * ame429_gridStep;
    return CGPointMake(MAX(0.0, MIN(sx, maxOriginX)), MAX(0.0, MIN(sy, maxOriginY)));
}

/// 松手落账：吸附 → 写回 dynamicX/dynamicY（运行时同款百分比表达式）→
/// update 重解算（抽屉 update 链内含 syncButtons 重排子键）→ 记脏。
- (void)ame429_commitNodeFrame:(ControlButton *)node {
    CGPoint snapped = [self ame429_snappedOriginForFrame:node.frame];
    node.properties[@"dynamicX"] = [node generateDynamicX:snapped.x];
    node.properties[@"dynamicY"] = [node generateDynamicY:snapped.y];
    [node update];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
}

#pragma mark - 等比缩放（四角柄）

- (void)ame429_handlePanned:(UIPanGestureRecognizer *)sender {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;

    NSInteger handleTag = sender.view.tag;
    CGPoint pointer = [sender locationInView:self.canvas];

    if (sender.state == UIGestureRecognizerStateBegan) {
        self.activeNode = node;
        self.ame429_resizeStartFrame = node.frame;
        // 锚点 = 被拖角的对角（画布坐标）；被拖角 = 起始时指尖最近的角
        CGRect f = node.frame;
        BOOL dragLeft = (handleTag == 0 || handleTag == 2);
        BOOL dragTop = (handleTag == 0 || handleTag == 1);
        self.ame429_resizeAnchor = CGPointMake(
            dragLeft ? f.origin.x + f.size.width : f.origin.x,
            dragTop ? f.origin.y + f.size.height : f.origin.y);
        self.gridView.hidden = NO;
        self.coordHint.hidden = NO;
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        CGRect start = self.ame429_resizeStartFrame;
        CGPoint anchor = self.ame429_resizeAnchor;
        BOOL dragLeft = (handleTag == 0 || handleTag == 2);
        BOOL dragTop = (handleTag == 0 || handleTag == 1);

        // 等比：比例 = 指尖到对角锚点的距离 / 起始被拖角到锚点的距离
        CGPoint startCorner = CGPointMake(
            dragLeft ? start.origin.x : start.origin.x + start.size.width,
            dragTop ? start.origin.y : start.origin.y + start.size.height);
        CGFloat startDist = MathUtils_dist(startCorner.x, startCorner.y, anchor.x, anchor.y);
        if (startDist < 1.0) startDist = 1.0;
        CGFloat nowDist = MathUtils_dist(pointer.x, pointer.y, anchor.x, anchor.y);
        CGFloat scale = nowDist / startDist;

        CGFloat newW = start.size.width * scale;
        CGFloat newH = start.size.height * scale;
        // 最小尺寸守卫（等比回拉到两维都 ≥ 24pt）+ 画布上限守卫
        CGFloat canvasW = self.canvas.frame.size.width;
        CGFloat canvasH = self.canvas.frame.size.height;
        if (newW < ame429_minNodeSize || newH < ame429_minNodeSize) {
            CGFloat guardScale = MAX(ame429_minNodeSize / MAX(start.size.width, 1.0),
                                     ame429_minNodeSize / MAX(start.size.height, 1.0));
            newW = start.size.width * guardScale;
            newH = start.size.height * guardScale;
        }
        if (newW > canvasW) { newW = canvasW; newH = start.size.height * (newW / MAX(start.size.width, 1.0)); }
        if (newH > canvasH) { newH = canvasH; newW = start.size.width * (newH / MAX(start.size.height, 1.0)); }
        newW = MAX(ame429_minNodeSize, newW);
        newH = MAX(ame429_minNodeSize, newH);

        // 被拖角指向指针，对角锚点不动（全程画布坐标，无跨系换算）
        CGFloat ox = dragLeft ? anchor.x - newW : anchor.x;
        CGFloat oy = dragTop ? anchor.y - newH : anchor.y;
        CGFloat maxOriginX = MAX(0.0, canvasW - newW);
        CGFloat maxOriginY = MAX(0.0, canvasH - newH);
        ox = MAX(0.0, MIN(ox, maxOriginX));
        oy = MAX(0.0, MIN(oy, maxOriginY));

        node.frame = CGRectMake(ox, oy, newW, newH);
        [self ame429_layoutSelectionOverlay];
        self.coordHint.text = [NSString stringWithFormat:@"w %.0f · h %.0f", newW, newH];
    } else if (sender.state == UIGestureRecognizerStateEnded ||
               sender.state == UIGestureRecognizerStateCancelled) {
        [self ame429_commitNodeFrame:node];
        self.activeNode = nil;
        self.gridView.hidden = YES;
        self.coordHint.hidden = YES;
    }
}

#pragma mark - 层管理（ZL2M3BottomSheet）

- (void)ame429_layerButtonTapped {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) {
        [NMToast showMessage:localize(@"ame429.j.layer.none", @"请先点选一个控件节点")];
        return;
    }
    [self ame429_showLayerSheet];
}

- (NSString *)ame429_layerInfoText {
    ControlButton *node = self.selectedNode;
    if (node == nil) return @"";
    NSMutableArray *list = ame429_owningListForNode(node, self.layoutDict);
    if (list == nil) return @"";
    NSUInteger idx = [list indexOfObject:ame429_listElementForNode(node)];
    if (idx == NSNotFound) return @"";
    NSString *kindName = nil;
    Ame429NodeKind kind = ame429_kindOfNode(node);
    if (kind == Ame429NodeKindDrawer) {
        kindName = localize(@"ame429.j.kind.drawer", @"抽屉");
    } else if (kind == Ame429NodeKindSubButton) {
        kindName = localize(@"ame429.j.kind.subbutton", @"子键");
    } else if (kind == Ame429NodeKindJoystick) {
        kindName = localize(@"ame429.j.kind.joystick", @"摇杆");
    } else {
        kindName = localize(@"ame429.j.kind.button", @"按钮");
    }
    NSString *name = node.properties[@"name"];
    if (![name isKindOfClass:[NSString class]] || name.length == 0) {
        name = kindName;
    }
    return [NSString stringWithFormat:@"%@ · %@ %lu/%lu",
            name, kindName, (unsigned long)(idx + 1), (unsigned long)list.count];
}

- (void)ame429_showLayerSheet {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [ZL2Theme fontTitleLarge];
    header.textColor = [ZL2Theme onSurface];
    header.text = localize(@"ame429.j.layer.title", @"层管理");
    [content addSubview:header];

    UILabel *info = [[UILabel alloc] init];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    info.font = [ZL2Theme fontBodyMedium];
    info.textColor = [ZL2Theme onSurfaceVariant];
    info.text = [self ame429_layerInfoText];
    [content addSubview:info];
    self.layerSheetInfoLabel = info;

    Ame429SheetRowView *frontRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.layer.to_front", @"置顶") subtitle:nil destructive:NO];
    // ★Task432（P2 强捕 self）：弹层行 onTap 强捕 self → __weak weakSelf 断链
    __weak typeof(self) weakSelf = self;
    frontRow.ame429_onTap = ^{
        [weakSelf ame429_layerOp:Ame429LayerOpToFront];
    };
    Ame429SheetRowView *backRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.layer.to_back", @"置底") subtitle:nil destructive:NO];
    backRow.ame429_onTap = ^{
        [weakSelf ame429_layerOp:Ame429LayerOpToBack];
    };
    Ame429SheetRowView *forwardRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.layer.forward", @"上移一层") subtitle:nil destructive:NO];
    forwardRow.ame429_onTap = ^{
        [weakSelf ame429_layerOp:Ame429LayerOpForward];
    };
    Ame429SheetRowView *backwardRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.layer.backward", @"下移一层") subtitle:nil destructive:NO];
    backwardRow.ame429_onTap = ^{
        [weakSelf ame429_layerOp:Ame429LayerOpBackward];
    };

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[frontRow, backRow, forwardRow, backwardRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UILabel *foot = [[UILabel alloc] init];
    foot.translatesAutoresizingMaskIntoConstraints = NO;
    foot.font = [ZL2Theme fontBodyMedium];
    foot.textColor = [ZL2Theme onSurfaceVariant];
    foot.numberOfLines = 0;
    foot.text = localize(@"ame429.j.layer.foot", @"层序同时写回布局 JSON 的数组顺序，进游戏后生效一致。");
    [content addSubview:foot];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [info.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [info.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.topAnchor constraintEqualToAnchor:info.bottomAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [foot.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [foot.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    for (Ame429SheetRowView *row in stack.arrangedSubviews) {
        [row.heightAnchor constraintEqualToConstant:52.0].active = YES;
    }

    [ZL2M3BottomSheet presentWithContentView:content onDismiss:^{
        weakSelf.layerSheetInfoLabel = nil;   // ★Task432：weakSelf 断链
    }];
}

- (void)ame429_refreshLayerSheetInfo {
    UILabel *info = self.layerSheetInfoLabel;
    if (info != nil) {
        info.text = [self ame429_layerInfoText];
    }
}

/// 层操作（JSON 数组序 + 画布 z 序双写）
- (void)ame429_layerOp:(Ame429LayerOp)op {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    NSMutableArray *list = ame429_owningListForNode(node, self.layoutDict);
    if (list == nil) return;
    id element = ame429_listElementForNode(node);
    NSUInteger idx = [list indexOfObject:element];
    if (idx == NSNotFound) return;

    BOOL changed = NO;
    switch (op) {
        case Ame429LayerOpToFront:
            if (idx != list.count - 1) {
                [list removeObjectAtIndex:idx];
                [list addObject:element];
                changed = YES;
            }
            break;
        case Ame429LayerOpToBack:
            if (idx != 0) {
                [list removeObjectAtIndex:idx];
                [list insertObject:element atIndex:0];
                changed = YES;
            }
            break;
        case Ame429LayerOpForward:
            if (idx + 1 < list.count) {
                [list removeObjectAtIndex:idx];
                [list insertObject:element atIndex:idx + 1];
                changed = YES;
            }
            break;
        case Ame429LayerOpBackward:
            if (idx > 0) {
                [list removeObjectAtIndex:idx];
                [list insertObject:element atIndex:idx - 1];
                changed = YES;
            }
            break;
    }
    if (!changed) return;

    [self ame429_resyncCanvasZOrder];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
    [self ame429_refreshLayerSheetInfo];
}

/// 画布 z 序按运行时装载语义重铺：mControlDataList（数组序）→ 抽屉
/// （数组序，各抽屉子键按 buttonProperties 序跟随其后）→ mJoystickDataList。
/// 重载后 z 序与画布所见恒一致（编辑器不说谎原则）。
- (void)ame429_resyncCanvasZOrder {
    NSMutableArray *btnList = self.layoutDict[@"mControlDataList"];
    NSMutableArray *drawerList = self.layoutDict[@"mDrawerDataList"];
    NSMutableArray *joyList = self.layoutDict[@"mJoystickDataList"];

    // ★Task434 P0-1: 元素级守卫——三组枚举非字典异形元素跳过并留痕
    //（Favorites 家法）；drawerData 守卫后 :buttonProperties 下标方为安全读。
    for (NSMutableDictionary *btnProps in btnList) {
        if (![btnProps isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mControlDataList 异形元素(%@)已跳过", [btnProps class]);
            continue;
        }
        UIView *view = [self ame429_viewForProperties:btnProps];
        if (view != nil) [self.canvas addSubview:view];
    }
    for (NSMutableDictionary *drawerData in drawerList) {
        if (![drawerData isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mDrawerDataList 异形元素(%@)已跳过", [drawerData class]);
            continue;
        }
        UIView *drawerView = [self ame429_viewForDrawerData:drawerData];
        if (drawerView != nil) [self.canvas addSubview:drawerView];
        id subButtons = drawerData[@"buttonProperties"];
        if (![subButtons isKindOfClass:[NSArray class]]) continue;
        for (NSMutableDictionary *subProps in (NSArray *)subButtons) {
            if (![subProps isKindOfClass:[NSMutableDictionary class]]) continue;
            UIView *subView = [self ame429_viewForProperties:subProps];
            if (subView != nil) [self.canvas addSubview:subView];
        }
    }
    for (NSMutableDictionary *joyProps in joyList) {
        if (![joyProps isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mJoystickDataList 异形元素(%@)已跳过", [joyProps class]);
            continue;
        }
        UIView *view = [self ame429_viewForProperties:joyProps];
        if (view != nil) [self.canvas addSubview:view];
    }
}

/// properties 字典 → 画布上的节点视图（指针同一性匹配）
- (UIView *)ame429_viewForProperties:(NSMutableDictionary *)props {
    for (UIView *view in self.canvas.subviews) {
        if ([view isKindOfClass:[ControlButton class]] &&
            ((ControlButton *)view).properties == props) {
            return view;
        }
    }
    return nil;
}

/// drawerData 字典 → 抽屉视图
- (UIView *)ame429_viewForDrawerData:(NSMutableDictionary *)drawerData {
    for (UIView *view in self.canvas.subviews) {
        if ([view isKindOfClass:[ControlDrawer class]] &&
            ((ControlDrawer *)view).drawerData == drawerData) {
            return view;
        }
    }
    return nil;
}

#pragma mark - 样式库（三套预设，整版套用）

- (void)ame429_styleButtonTapped {
    [self ame429_showStyleSheet];
}

- (void)ame429_showStyleSheet {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [ZL2Theme fontTitleLarge];
    header.textColor = [ZL2Theme onSurface];
    header.text = localize(@"ame429.j.style.title", @"样式预设");
    [content addSubview:header];

    Ame429SheetRowView *defaultRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.style.default", @"默认")
        subtitle:localize(@"ame429.j.style.default.sub", @"不透明按钮 · 30% 深底 · 1pt 描边")
        destructive:NO];
    // ★Task432（P2 强捕 self）：样式表三行 onTap 强捕 self（弹层持有期间跨
    //   页面存活）→ __weak weakSelf 断链（同族：层序表/更多表行同批改齐）
    __weak typeof(self) weakSelf = self;
    defaultRow.ame429_onTap = ^{
        [weakSelf ame429_applyStylePreset:0];
    };
    Ame429SheetRowView *translucentRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.style.translucent", @"半透明")
        subtitle:localize(@"ame429.j.style.translucent.sub", @"55% 按钮 · 12% 浅底 · 0.5pt 描边")
        destructive:NO];
    translucentRow.ame429_onTap = ^{
        [weakSelf ame429_applyStylePreset:1];
    };
    Ame429SheetRowView *minimalRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.style.minimal", @"极简")
        subtitle:localize(@"ame429.j.style.minimal.sub", @"85% 按钮 · 7% 浅底 · 无描边")
        destructive:NO];
    minimalRow.ame429_onTap = ^{
        [weakSelf ame429_applyStylePreset:2];
    };

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[defaultRow, translucentRow, minimalRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UILabel *foot = [[UILabel alloc] init];
    foot.translatesAutoresizingMaskIntoConstraints = NO;
    foot.font = [ZL2Theme fontBodyMedium];
    foot.textColor = [ZL2Theme onSurfaceVariant];
    foot.numberOfLines = 0;
    foot.text = localize(@"ame429.j.style.foot", @"整版套用：写回每个控件的透明度/背景透明度/描边三个样式字段，颜色本身不变。");
    [content addSubview:foot];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [foot.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [foot.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    for (Ame429SheetRowView *row in stack.arrangedSubviews) {
        [row.heightAnchor constraintEqualToConstant:64.0].active = YES;
    }

    // 弹层保持打开便于连续试预设（scrim 点按关闭）
    [ZL2M3BottomSheet presentWithContentView:content onDismiss:nil];
}

- (void)ame429_applyStylePreset:(NSInteger)preset {
    Ame429StyleParams params = ame429_paramsForPreset(preset);
    NSMutableArray *btnList = self.layoutDict[@"mControlDataList"];
    NSMutableArray *drawerList = self.layoutDict[@"mDrawerDataList"];
    NSMutableArray *joyList = self.layoutDict[@"mJoystickDataList"];

    // ★Task434 P0-1: 元素级守卫——三组枚举非字典异形元素跳过并留痕
    //（Favorites 家法）；drawerData 守卫后 :properties/:buttonProperties
    // 下标方为安全读（properties 值级异常由 applyStyleToProperties 内守卫留痕）。
    for (NSMutableDictionary *props in btnList) {
        if (![props isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mControlDataList 异形元素(%@)已跳过", [props class]);
            continue;
        }
        ame429_applyStyleToProperties(props, params);
    }
    for (NSMutableDictionary *drawerData in drawerList) {
        if (![drawerData isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mDrawerDataList 异形元素(%@)已跳过", [drawerData class]);
            continue;
        }
        ame429_applyStyleToProperties(drawerData[@"properties"], params);
        id subButtons = drawerData[@"buttonProperties"];
        if (![subButtons isKindOfClass:[NSArray class]]) continue;
        for (NSMutableDictionary *subProps in (NSArray *)subButtons) {
            if (![subProps isKindOfClass:[NSMutableDictionary class]]) continue;
            ame429_applyStyleToProperties(subProps, params);
        }
    }
    for (NSMutableDictionary *joyProps in joyList) {
        if (![joyProps isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Task429][Task434] mJoystickDataList 异形元素(%@)已跳过", [joyProps class]);
            continue;
        }
        ame429_applyStyleToProperties(joyProps, params);
    }

    // 全节点热刷新（update 链含抽屉 syncButtons）
    for (UIView *nodeView in self.canvas.subviews) {
        if ([nodeView isKindOfClass:[ControlButton class]]) {
            [(ControlButton *)nodeView update];
        }
    }

    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
    [NMToast showMessage:localize(@"ame429.j.toast.style_applied", @"样式已整版套用")];
}

#pragma mark - 更多弹层（保存副本 / 放弃 / 说明）

- (void)ame429_moreButtonTapped {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [ZL2Theme fontTitleLarge];
    header.textColor = [ZL2Theme onSurface];
    header.text = localize(@"ame429.j.more.title", @"更多");
    [content addSubview:header];

    Ame429SheetRowView *saveRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.toolbar.save", @"保存") subtitle:nil destructive:NO];
    // ★Task432（P2 强捕 self）：更多表三行 onTap 强捕 self → __weak weakSelf 断链
    __weak typeof(self) weakSelf = self;
    saveRow.ame429_onTap = ^{
        [weakSelf ame429_saveTapped];
    };
    Ame429SheetRowView *copyRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.toolbar.saveas", @"另存副本") subtitle:nil destructive:NO];
    copyRow.ame429_onTap = ^{
        [weakSelf ame429_saveAsCopyTapped];
    };
    Ame429SheetRowView *discardRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame429.j.more.discard", @"放弃更改并退出") subtitle:nil destructive:YES];
    discardRow.ame429_onTap = ^{
        [weakSelf ame429_discardAndExit];
    };

    NSMutableArray *rows = [NSMutableArray arrayWithObjects:saveRow, copyRow, nil];
    if (self.ame429_dirty) {
        [rows addObject:discardRow];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UILabel *foot = [[UILabel alloc] init];
    foot.translatesAutoresizingMaskIntoConstraints = NO;
    foot.font = [ZL2Theme fontBodyMedium];
    foot.textColor = [ZL2Theme onSurfaceVariant];
    foot.numberOfLines = 0;
    foot.text = localize(@"ame429.j.more.hint",
        @"拖动节点移动，松手自动吸附 8pt 网格；选中后拖角柄等比缩放；工具条「层」调整叠放次序，「样式」整版换肤。");
    [content addSubview:foot];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [foot.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [foot.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    for (Ame429SheetRowView *row in stack.arrangedSubviews) {
        [row.heightAnchor constraintEqualToConstant:52.0].active = YES;
    }

    [ZL2M3BottomSheet presentWithContentView:content onDismiss:nil];
}

#pragma mark - 保存 / 另存副本 / 退出

- (void)ame429_saveTapped {
    [self ame429_promptSaveWithCopy:NO];
}

- (void)ame429_saveAsCopyTapped {
    [self ame429_promptSaveWithCopy:YES];
}

/// 保存输入框（与既有编辑器 actionMenuSaveWithExit 同款 UIAlertController
/// + 文本框形态；copy=YES 时默认名加 _copy 后缀，另存不改当前编辑目标）。
- (void)ame429_promptSaveWithCopy:(BOOL)isCopy {
    NSString *title = isCopy
        ? localize(@"ame429.j.toolbar.saveas", @"另存副本")
        : localize(@"ame429.j.toolbar.save", @"保存");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Name";
        if (isCopy) {
            textField.text = [NSString stringWithFormat:@"%@_copy", self.ame429_layoutFileName];
        } else {
            textField.text = self.ame429_layoutFileName;
        }
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UITextField *field = alert.textFields.firstObject;
            NSString *name = ame429_sanitizedFileName(field.text);
            if (name == nil) {
                [NMToast showMessage:localize(@"ame429.j.save.error.name", @"文件名不合法（不能为空或包含路径分隔符）")];
                return;
            }
            [self ame429_writeLayoutNamed:name asCopy:isCopy];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 写盘主路径（保存/副本共用）：
///   1. NSJSONSerialization 序列化编辑中的同一棵 layoutDictionary（Pretty
///      Printed，与既有编辑器保存逐格式一致）；
///   2. 原子写 controlmap/<名>.json；
///   3. 成功吐司；主保存同时更新当前编辑目标名与脏标记，副本不动。
///   注：scaledAt/width/height 若与 control.button_scale 偏好不一致，装载时
///   已按运行时规则归一化（loadControlLayout → preProcessProperties），此处
///   只是如实落盘——与运行时重载结果逐位一致，属既有格式语义而非新改动。
- (void)ame429_writeLayoutNamed:(NSString *)fileName asCopy:(BOOL)isCopy {
    if (self.layoutDict == nil) return;
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.layoutDict
        options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (jsonData == nil) {
        NSLog(@"[Task429] JSON serialize failed: %@", jsonError.localizedDescription);
        showDialog(localize(@"ame429.j.save.error.json_title", @"保存失败"),
                   localize(@"ame429.j.save.error.json", @"布局数据无法序列化为 JSON，未写入文件。"));
        return;
    }
    NSError *writeError = nil;
    BOOL ok = [jsonData writeToFile:ame429_layoutFilePath(fileName)
                            options:NSDataWritingAtomic error:&writeError];
    if (!ok) {
        NSLog(@"[Task429] write failed: %@ (%@)", fileName, writeError.localizedDescription);
        showDialog(localize(@"ame429.j.save.error.write_title", @"写入失败"),
                   writeError.localizedDescription ?: @"");
        return;
    }
    if (isCopy) {
        [NMToast showMessage:[NSString stringWithFormat:
            localize(@"ame429.j.toast.copy_ok", @"副本已保存：%@.json"), fileName]];
    } else {
        self.ame429_layoutFileName = fileName;
        self.ame429_dirty = NO;
        [self ame429_refreshTitle];
        [NMToast showMessage:[NSString stringWithFormat:
            localize(@"ame429.j.toast.save_ok", @"已保存：%@.json"), fileName]];
    }
}

- (void)ame429_closeTapped {
    if (!self.ame429_dirty) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    // ★Task432（P2 强捕 self）：确认回调断链所需 weakSelf
    __weak typeof(self) weakSelf = self;
    [ZL2M3Dialog showTitle:localize(@"ame429.j.close.title", @"退出编辑器")
                      body:localize(@"ame429.j.close.body", @"当前布局有未保存的更改。确认后将以原文件名保存并退出。")
              confirmTitle:localize(@"ame429.j.close.save_exit", @"保存并退出")
               destructive:NO
                onConfirm:^{
                    // ★Task432（P2 强捕 self）：确认回调强捕 self → weakSelf 断链
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf ame429_writeLayoutNamed:strongSelf.ame429_layoutFileName asCopy:NO];
                    // ★ Task436：退出统一走 ame436_exitEditor（onDismiss 回调链）
                    [strongSelf ame436_exitEditor];
                }
                 onCancel:nil];
}

- (void)ame429_discardAndExit {
    self.ame429_dirty = NO;
    // ★ Task436：退出统一走 ame436_exitEditor（onDismiss 回调链）
    [self ame436_exitEditor];
}


// ============================================================================
// ★Task436 批次三·编辑器最小闭环（①新建控件 ②属性面板 ③删除/克隆 ④退出
// 回调链供游戏内入口热重载）。基准：ZL2 main/control_editor/ ControlEditor.kt
// 新建三类 + edit_widget/EditWidgetDialog 属性族 + GameScreen.kt「运行中实时
// 编辑」。属性面板按「量力而行」取核心字段闭环；键型同构红线：所有写回
// 只动 v7 schema 既有键（name/keycodes/isToggle/passThruEnabled/opacity/
// bgColor/strokeWidth/forwardLock/dynamicX/dynamicY），零新增键。
// ============================================================================

/// 新建类别（决定所属 JSON 列表与默认字典形态）
typedef NS_ENUM(NSInteger, Ame436NewKind) {
    Ame436NewKindButton = 0,     // 按键 → mControlDataList
    Ame436NewKindTextbox,        // 文本框（虚拟键盘开关）→ mControlDataList
    Ame436NewKindJoystick,       // 摇杆 → mJoystickDataList
};

#pragma mark - ★Task436 退出回调链（游戏内入口热重载）

/// 统一退出点（保存并退出 / 放弃退出 / 读取失败退出三路径共用）：
/// dismiss 完成后回调 ame436_onDismiss——游戏内宿主（SurfaceViewController）
/// 据此走 Task64 既有热重载链（removeAllButtons + loadCustomControls），
/// 启动器内既有入口（onDismiss = nil）行为零变化。
- (void)ame436_exitEditor {
    __weak typeof(self) weakSelf = self;
    [self dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        void (^ame436_notify)(void) = strongSelf.ame436_onDismiss;
        if (ame436_notify) ame436_notify();
    }];
}

#pragma mark - ★Task436 新建控件（三类）

- (void)ame436_addButtonTapped {
    [self ame436_showAddSheet];
}

/// 新建控件弹层（三类行件：按键 / 文本框 / 摇杆）
- (void)ame436_showAddSheet {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [ZL2Theme fontTitleLarge];
    header.textColor = [ZL2Theme onSurface];
    header.text = localize(@"ame436.editor.add.title", @"新建控件");
    [content addSubview:header];

    // ★Task432（P2 强捕 self）判例：弹层行 onTap 强捕 self → weakSelf 断链
    __weak typeof(self) weakSelf = self;
    Ame429SheetRowView *buttonRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame436.editor.add.button", @"按键")
        subtitle:localize(@"ame436.editor.add.button.sub", @"功能按键（默认无绑定，选中后可改键值）")
        destructive:NO];
    buttonRow.ame429_onTap = ^{
        [weakSelf ame436_createNodeOfKind:Ame436NewKindButton];
    };
    Ame429SheetRowView *textboxRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame436.editor.add.textbox", @"文本框")
        subtitle:localize(@"ame436.editor.add.textbox.sub", @"虚拟键盘开关（游戏内文字输入入口）")
        destructive:NO];
    textboxRow.ame429_onTap = ^{
        [weakSelf ame436_createNodeOfKind:Ame436NewKindTextbox];
    };
    Ame429SheetRowView *joystickRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame436.editor.add.joystick", @"摇杆")
        subtitle:localize(@"ame436.editor.add.joystick.sub", @"虚拟摇杆（WASD 方向控制）")
        destructive:NO];
    joystickRow.ame429_onTap = ^{
        [weakSelf ame436_createNodeOfKind:Ame436NewKindJoystick];
    };

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[buttonRow, textboxRow, joystickRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UILabel *foot = [[UILabel alloc] init];
    foot.translatesAutoresizingMaskIntoConstraints = NO;
    foot.font = [ZL2Theme fontBodyMedium];
    foot.textColor = [ZL2Theme onSurfaceVariant];
    foot.numberOfLines = 0;
    foot.text = localize(@"ame436.editor.add.foot",
        @"新控件出现在画布中心，拖到目标位置后保存。");
    [content addSubview:foot];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [foot.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [foot.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [foot.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    for (Ame429SheetRowView *row in stack.arrangedSubviews) {
        [row.heightAnchor constraintEqualToConstant:64.0].active = YES;
    }

    [ZL2M3BottomSheet presentWithContentView:content onDismiss:nil];
}

/// 三类新建的默认布局参数（控件字典键型与既有 loadLayout/saveLayout 完全
/// 同构证明）：
///   按键 = CustomControlsUtils createButton / 旧编辑器
///   actionMenuAddButtonWithDrawer 同键集——name / keycodes[4] / dynamicX /
///   dynamicY / width / height / opacity / cornerRadius / bgColor /
///   displayInGame / displayInMenu；
///   摇杆 = 旧编辑器 actionMenuAddJoystick 同键集——上述键集 + strokeColor /
///   forwardLock（出厂 custom.json 摇杆条目同键域）；
///   文本框 = 按键键集 + keycodes[0]=SPECIALBTN_KEYBOARD——本运行时无独立
///   textbox 节点（ControlButton/ControlDrawer/ControlSubButton/
///   ControlJoystick 四族而已），ZL2 基准的 textbox 按 iOS 既有语义映射为
///   虚拟键盘开关键（SurfaceViewController executebtn 分发表
///   case SPECIALBTN_KEYBOARD = 弹出/收起内置文字输入框；出厂 default.json
///   "Keyboard" 键同款）。零新增 schema 字段。
- (NSMutableDictionary *)ame436_defaultPropsForKind:(Ame436NewKind)kind {
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    if (kind == Ame436NewKindTextbox) {
        props[@"name"] = localize(@"ame436.editor.add.textbox", @"文本框");
        props[@"keycodes"] = [NSMutableArray arrayWithArray:
            @[@(SPECIALBTN_KEYBOARD), @0, @0, @0]];
    } else {
        props[@"name"] = @"New";
        props[@"keycodes"] = [NSMutableArray arrayWithArray:@[@0, @0, @0, @0]];
    }
    props[@"dynamicX"] = @"0";
    props[@"dynamicY"] = @"0";
    props[@"width"] = @(50.0);
    props[@"height"] = @(50.0);
    props[@"opacity"] = @(1);
    props[@"cornerRadius"] = @(0);
    props[@"bgColor"] = @(0x4d000000);
    props[@"displayInGame"] = @YES;
    props[@"displayInMenu"] = @YES;
    if (kind == Ame436NewKindJoystick) {
        props[@"name"] = @"";
        props[@"width"] = @(100.0);
        props[@"height"] = @(100.0);
        props[@"strokeColor"] = @(0xffffffff);
        props[@"forwardLock"] = @NO;
    }
    return props;
}

/// 新建落画布：所属 JSON 列表 append（列表序 = z 序尾部，与 addSubview 顶部
/// 语义一致）→ 运行时视图上屏 → 手势挂接 → 居中放置（8pt 吸附 + 钳制 +
/// 新建计数漂移防精确重叠）→ generateDynamicX/Y 写回（与拖拽落账同一表达式
/// 管线，逐位一致）→ 选中 + 记脏。
- (void)ame436_createNodeOfKind:(Ame436NewKind)kind {
    NSMutableDictionary *props = [self ame436_defaultPropsForKind:kind];
    BOOL isJoy = (kind == Ame436NewKindJoystick);
    NSMutableArray *list = self.layoutDict[isJoy ? @"mJoystickDataList"
                                                 : @"mControlDataList"];
    if (![list isKindOfClass:[NSMutableArray class]]) {
        // fail-loud（第六版 N1/N2 判例：守卫不得把异常藏成静默失效）
        NSLog(@"[Task436] create: owning list missing/not mutable (anomalous data shape)");
        return;
    }
    [list addObject:props];

    ControlButton *node = isJoy
        ? (ControlButton *)[ControlJoystick buttonWithProperties:props]
        : [ControlButton buttonWithProperties:props];
    [self.canvas addSubview:node];
    [self ame429_attachGesturesToNode:node];
    [node update];   // 先按占位 dynamicX/Y="0" 落位（generateDynamicX 依赖 superview）

    CGFloat w = [props[@"width"] floatValue];
    CGFloat h = [props[@"height"] floatValue];
    CGFloat canvasW = self.canvas.frame.size.width;
    CGFloat canvasH = self.canvas.frame.size.height;
    CGFloat drift = (self.ame436_createdCount % 6) * ame429_gridStep;
    CGFloat px = MAX(0.0, MIN((canvasW - w) / 2.0 + drift, MAX(0.0, canvasW - w)));
    CGFloat py = MAX(0.0, MIN((canvasH - h) / 2.0 + drift, MAX(0.0, canvasH - h)));
    px = roundf(px / ame429_gridStep) * ame429_gridStep;
    py = roundf(py / ame429_gridStep) * ame429_gridStep;
    node.properties[@"dynamicX"] = [node generateDynamicX:px];
    node.properties[@"dynamicY"] = [node generateDynamicY:py];
    [node update];

    self.ame436_createdCount++;
    self.selectedNode = node;
    [self ame429_layoutSelectionOverlay];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
    NSString *kindName = (kind == Ame436NewKindTextbox)
        ? localize(@"ame436.editor.add.textbox", @"文本框")
        : (kind == Ame436NewKindJoystick
            ? localize(@"ame436.editor.add.joystick", @"摇杆")
            : localize(@"ame436.editor.add.button", @"按键"));
    [NMToast showMessage:[NSString stringWithFormat:
        localize(@"ame436.editor.add.toast_fmt", @"已新建：%@"), kindName]];
}

#pragma mark - ★Task436 控件属性面板

- (void)ame436_propsButtonTapped {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) {
        [NMToast showMessage:localize(@"ame436.editor.props.none", @"请先点选一个控件节点")];
        return;
    }
    [self ame436_showPropsSheet];
}

/// 属性写回目标字典：Button/Joy/SubButton = properties 本体；Drawer =
/// drawerData[@"properties"]（抽屉本体是 button 形字典嵌在 drawerData）。
/// 返回 nil = 异形数据形态（调用方留痕跳过，fail-loud 判例）。
- (NSMutableDictionary *)ame436_propsTargetForNode:(ControlButton *)node {
    if ([node isKindOfClass:[ControlDrawer class]]) {
        NSMutableDictionary *p = ((ControlDrawer *)node).drawerData[@"properties"];
        if ([p isKindOfClass:[NSMutableDictionary class]]) return p;
        NSLog(@"[Task436] props: drawerData.properties missing/not mutable (anomalous data shape)");
        return nil;
    }
    return node.properties;
}

/// 属性面板统一写回落点（任一字段改动后调用）：节点 update 热刷新（抽屉
/// update 链含 syncButtons）→ 记脏。
- (void)ame436_commitSelectedNode {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    [node update];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
}

/// 主键键值（keycodes[0]）读取（异形布局兜底 0 = 无绑定）
- (NSInteger)ame436_readPrimaryKeycodeFromProps:(NSMutableDictionary *)props {
    NSArray *kcs = props[@"keycodes"];
    if ([kcs isKindOfClass:[NSArray class]] && kcs.count > 0 &&
        [kcs[0] isKindOfClass:[NSNumber class]]) {
        return ((NSNumber *)kcs[0]).integerValue;
    }
    return 0;
}

/// 主键键值写回（keycodes 数组缺失/短数组按既有编辑器口径补齐四槽）
- (void)ame436_writePrimaryKeycode:(NSInteger)value toProps:(NSMutableDictionary *)props {
    NSMutableArray *kcs = props[@"keycodes"];
    if (![kcs isKindOfClass:[NSMutableArray class]]) {
        kcs = [NSMutableArray arrayWithArray:@[@0, @0, @0, @0]];
        props[@"keycodes"] = kcs;
    }
    while (kcs.count < 4) [kcs addObject:@0];
    kcs[0] = @(value);
}

/// 背景透明度读取（bgColor alpha 字节 / 255；缺省 = 出厂 0x4d000000 档）
- (CGFloat)ame436_readBgAlphaFromProps:(NSMutableDictionary *)props {
    NSNumber *bg = props[@"bgColor"];
    if (![bg isKindOfClass:[NSNumber class]]) return 0x4d / 255.0;
    long long argb = ame429_argbFromNumber(bg);
    return ((argb >> 24) & 0xFF) / 255.0;
}

/// 背景透明度写回（仅改 alpha 字节保留 RGB——与样式预设
/// ame429_applyStyleToProperties 同一语义；缺 bgColor 时以黑色 RGB 建档）
- (void)ame436_writeBgAlpha:(CGFloat)alpha toProps:(NSMutableDictionary *)props {
    NSNumber *bg = props[@"bgColor"];
    long long rgb = 0;
    if ([bg isKindOfClass:[NSNumber class]]) {
        rgb = ame429_argbFromNumber(bg) & 0x00FFFFFFLL;
    }
    NSInteger byte = (NSInteger)roundf(MAX(0.0, MIN(alpha, 1.0)) * 255.0);
    props[@"bgColor"] = @(rgb | ((long long)byte << 24));
}

// —— 面板行小件 ——
- (UILabel *)ame436_propLabel:(NSString *)text {
    UILabel *lab = [[UILabel alloc] init];
    lab.font = [ZL2Theme fontBodyMedium];
    lab.textColor = [ZL2Theme onSurface];
    lab.text = text;
    lab.numberOfLines = 1;
    lab.adjustsFontSizeToFitWidth = YES;
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    return lab;
}

- (UILabel *)ame436_propHintLabel:(NSString *)text {
    UILabel *lab = [[UILabel alloc] init];
    lab.font = [ZL2Theme fontLabelMedium];
    lab.textColor = [ZL2Theme onSurfaceVariant];
    lab.numberOfLines = 0;
    lab.text = text;
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    return lab;
}

- (UILabel *)ame436_propSectionLabel:(NSString *)text {
    UILabel *lab = [[UILabel alloc] init];
    lab.font = [ZL2Theme fontLabelLarge];
    lab.textColor = [ZL2Theme onSurfaceVariant];
    lab.text = text;
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    return lab;
}

- (UILabel *)ame436_propValueLabel:(NSString *)text {
    UILabel *lab = [[UILabel alloc] init];
    lab.font = [ZL2Theme fontLabelMedium];
    lab.textColor = [ZL2Theme onSurfaceVariant];
    lab.textAlignment = NSTextAlignmentRight;
    lab.text = text;
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    return lab;
}

- (UIStackView *)ame436_rowWithLabel:(NSString *)title
                             control:(UIView *)control
                        controlWidth:(CGFloat)width {
    UILabel *lab = [self ame436_propLabel:title];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[lab, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12.0;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [lab.widthAnchor constraintEqualToConstant:104.0].active = YES;
    if (width > 0) [control.widthAnchor constraintEqualToConstant:width].active = YES;
    return row;
}

- (UIStackView *)ame436_sliderRowWithLabel:(NSString *)title
                                   slider:(UISlider *)slider
                                valueLabel:(UILabel *)valueLabel {
    UILabel *lab = [self ame436_propLabel:title];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:
        @[lab, slider, valueLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10.0;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [lab.widthAnchor constraintEqualToConstant:104.0].active = YES;
    [valueLabel.widthAnchor constraintEqualToConstant:44.0].active = YES;
    return row;
}

/// 属性面板（ZL2M3BottomSheet + 滚动区；字段按节点类别裁剪）：
///   按键/子键：名称 + 按键映射 + 启动器动作 + 点击事件 + 三样式字段 +
///             克隆 + 删除；
///   摇杆：名称 + 三样式字段 + 方向锁 + 克隆 + 删除（ZL2 基准的摇杆
///         id/半径/死区在 iOS v7 键型中无对应键——半径 = 控件尺寸（画布
///         等比缩放管），死区 = 运行时常量 0.35（ControlJoystick.m），
///         按键型同构红线不新增键，见报告登记）；
///   抽屉：名称 + 三样式字段 + 克隆 + 删除（抽屉 properties 子字典）。
- (void)ame436_showPropsSheet {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    NSMutableDictionary *props = [self ame436_propsTargetForNode:node];
    if (props == nil) return;   // 异形数据形态：propsTargetForNode 已留痕

    Ame429NodeKind kind = ame429_kindOfNode(node);
    BOOL hasKeycodes = (kind == Ame429NodeKindButton || kind == Ame429NodeKindSubButton);
    BOOL isJoystick = (kind == Ame429NodeKindJoystick);

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [ZL2Theme fontTitleLarge];
    header.textColor = [ZL2Theme onSurface];
    header.text = localize(@"ame436.editor.props.title", @"控件属性");
    [content addSubview:header];

    UILabel *info = [[UILabel alloc] init];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    info.font = [ZL2Theme fontBodyMedium];
    info.textColor = [ZL2Theme onSurfaceVariant];
    info.text = [self ame429_layerInfoText];
    [content addSubview:info];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    [content addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    __weak typeof(props) weakProps = props;

    // —— 名称（三类通用）——
    Ame436BlockTextField *nameField = [[Ame436BlockTextField alloc] initWithFrame:CGRectZero];
    nameField.borderStyle = UITextBorderStyleRoundedRect;
    nameField.font = [ZL2Theme fontBodyMedium];
    nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    nameField.text = ([props[@"name"] isKindOfClass:[NSString class]])
        ? props[@"name"] : @"";
    [nameField.heightAnchor constraintEqualToConstant:32.0].active = YES;
    nameField.ame436_onChange = ^(NSString *text) {
        weakProps[@"name"] = text ?: @"";
        [weakSelf ame436_commitSelectedNode];
    };
    [rows addObject:[self ame436_rowWithLabel:
        localize(@"ame436.editor.props.name", @"名称")
        control:nameField controlWidth:0]];

    if (hasKeycodes) {
        // —— 按键映射（键值输入；keycodes[0] 主键）——
        Ame436BlockTextField *kcField = [[Ame436BlockTextField alloc] initWithFrame:CGRectZero];
        kcField.borderStyle = UITextBorderStyleRoundedRect;
        kcField.keyboardType = UIKeyboardTypeNumberPad;
        kcField.font = [ZL2Theme fontBodyMedium];
        kcField.text = [NSString stringWithFormat:@"%ld",
            (long)[self ame436_readPrimaryKeycodeFromProps:props]];
        [kcField.heightAnchor constraintEqualToConstant:32.0].active = YES;
        kcField.ame436_onChange = ^(NSString *text) {
            [weakSelf ame436_writePrimaryKeycode:text.integerValue toProps:weakProps];
            [weakSelf ame436_commitSelectedNode];
        };
        [rows addObject:[self ame436_rowWithLabel:
            localize(@"ame436.editor.props.keycode", @"按键映射")
            control:kcField controlWidth:0]];
        [rows addObject:[self ame436_propHintLabel:
            localize(@"ame436.editor.props.keycode.hint",
                @"键值：0=无绑定；正数=GLFW 键码（87=W、256=Esc）；负数=特殊键")]];

        // —— 启动器动作（特殊键单选网格，iOS 既有面）——
        [rows addObject:[self ame436_propSectionLabel:
            localize(@"ame436.editor.props.special", @"启动器动作")]];
        Ame436SpecialKeyGrid *grid = [[Ame436SpecialKeyGrid alloc]
            initWithCurrentValue:[self ame436_readPrimaryKeycodeFromProps:props]
                        onChange:^(NSInteger value) {
                            [weakSelf ame436_writePrimaryKeycode:value toProps:weakProps];
                            [weakSelf ame436_commitSelectedNode];
                        }];
        [rows addObject:grid];

        // —— 点击事件（无/切换/穿透 → isToggle / passThruEnabled 既有字段；
        //   ZL2 基准「长按」在本运行时无分发面，按键型同构红线映射为既有
        //   两字段三态，不新增键）——
        Ame436BlockSegment *seg = [[Ame436BlockSegment alloc] initWithItems:@[
            localize(@"ame436.editor.props.event.normal", @"普通"),
            localize(@"ame436.editor.props.event.toggle", @"切换"),
            localize(@"ame436.editor.props.event.passthru", @"穿透"),
        ]];
        BOOL isToggle = [props[@"isToggle"] boolValue];
        BOOL passThru = [props[@"passThruEnabled"] boolValue];
        seg.selectedSegmentIndex = passThru ? 2 : (isToggle ? 1 : 0);
        seg.ame436_onChange = ^(NSInteger idx) {
            if (idx == 1) {
                weakProps[@"isToggle"] = @YES;
                weakProps[@"passThruEnabled"] = @NO;
            } else if (idx == 2) {
                weakProps[@"passThruEnabled"] = @YES;
                weakProps[@"isToggle"] = @NO;
            } else {
                weakProps[@"isToggle"] = @NO;
                weakProps[@"passThruEnabled"] = @NO;
            }
            [weakSelf ame436_commitSelectedNode];
        };
        [rows addObject:[self ame436_rowWithLabel:
            localize(@"ame436.editor.props.event", @"点击事件")
            control:seg controlWidth:168.0]];
    }

    // —— 三样式字段（与三套样式预设同一组既有键：opacity / bgColor-alpha /
    //   strokeWidth，整版预设与单控件属性联动）——
    UILabel *opacityValue = [self ame436_propValueLabel:@""];
    Ame436BlockSlider *opacity = [[Ame436BlockSlider alloc] initWithFrame:CGRectZero];
    opacity.minimumValue = 0.0;
    opacity.maximumValue = 1.0;
    opacity.value = MAX(0.0, MIN([props[@"opacity"] floatValue], 1.0));
    opacityValue.text = [NSString stringWithFormat:@"%d%%",
        (int)roundf(opacity.value * 100.0)];
    opacity.ame436_onChange = ^(CGFloat v) {
        weakProps[@"opacity"] = @(v);
        opacityValue.text = [NSString stringWithFormat:@"%d%%", (int)roundf(v * 100.0)];
        [weakSelf ame436_commitSelectedNode];
    };
    [rows addObject:[self ame436_sliderRowWithLabel:
        localize(@"ame436.editor.props.opacity", @"透明度")
        slider:opacity valueLabel:opacityValue]];

    UILabel *bgValue = [self ame436_propValueLabel:@""];
    Ame436BlockSlider *bgAlpha = [[Ame436BlockSlider alloc] initWithFrame:CGRectZero];
    bgAlpha.minimumValue = 0.0;
    bgAlpha.maximumValue = 1.0;
    bgAlpha.value = [self ame436_readBgAlphaFromProps:props];
    bgValue.text = [NSString stringWithFormat:@"%d%%",
        (int)roundf(bgAlpha.value * 100.0)];
    bgAlpha.ame436_onChange = ^(CGFloat v) {
        [weakSelf ame436_writeBgAlpha:v toProps:weakProps];
        bgValue.text = [NSString stringWithFormat:@"%d%%", (int)roundf(v * 100.0)];
        [weakSelf ame436_commitSelectedNode];
    };
    [rows addObject:[self ame436_sliderRowWithLabel:
        localize(@"ame436.editor.props.bgalpha", @"背景透明度")
        slider:bgAlpha valueLabel:bgValue]];

    UILabel *strokeValue = [self ame436_propValueLabel:@""];
    Ame436BlockSlider *stroke = [[Ame436BlockSlider alloc] initWithFrame:CGRectZero];
    stroke.minimumValue = 0.0;
    stroke.maximumValue = 5.0;
    stroke.value = MAX(0.0, MIN([props[@"strokeWidth"] floatValue], 5.0));
    strokeValue.text = [NSString stringWithFormat:@"%.1f", stroke.value];
    stroke.ame436_onChange = ^(CGFloat v) {
        CGFloat stepped = roundf(v * 2.0) / 2.0;   // 0.5 步进
        weakProps[@"strokeWidth"] = @(stepped);
        strokeValue.text = [NSString stringWithFormat:@"%.1f", stepped];
        [weakSelf ame436_commitSelectedNode];
    };
    [rows addObject:[self ame436_sliderRowWithLabel:
        localize(@"ame436.editor.props.stroke", @"描边宽度")
        slider:stroke valueLabel:strokeValue]];

    if (isJoystick) {
        // —— 摇杆配置：方向锁（iOS 键型既有键 forwardLock；ZL2 基准的
        //   id/半径/死区无对应键，见方法头注释）——
        Ame436BlockSwitch *fwd = [[Ame436BlockSwitch alloc] initWithFrame:CGRectZero];
        fwd.on = [props[@"forwardLock"] boolValue];
        fwd.ame436_onChange = ^(BOOL on) {
            weakProps[@"forwardLock"] = @(on);
            [weakSelf ame436_commitSelectedNode];
        };
        [rows addObject:[self ame436_rowWithLabel:
            localize(@"ame436.editor.props.forwardlock", @"方向锁")
            control:fwd controlWidth:0]];
    }

    // —— 克隆 / 删除（★Task436 批次三③）——
    Ame429SheetRowView *cloneRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame436.editor.props.clone", @"克隆控件（偏移 8pt）")
        subtitle:nil destructive:NO];
    cloneRow.ame429_onTap = ^{
        [ZL2M3BottomSheet dismissWithContentView:nil];
        [weakSelf ame436_cloneSelected];
    };
    Ame429SheetRowView *deleteRow = [[Ame429SheetRowView alloc] initWithTitle:
        localize(@"ame436.editor.props.delete", @"删除控件")
        subtitle:nil destructive:YES];
    deleteRow.ame429_onTap = ^{
        [weakSelf ame436_deleteSelected];
    };
    [rows addObject:cloneRow];
    [rows addObject:deleteRow];

    for (UIView *row in rows) [stack addArrangedSubview:row];
    for (UIView *row in rows) {
        if ([row isKindOfClass:[Ame429SheetRowView class]]) {
            [row.heightAnchor constraintEqualToConstant:52.0].active = YES;
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [info.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [info.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:info.bottomAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.heightAnchor constraintEqualToConstant:
            MAX(220.0, MIN(420.0, self.view.bounds.size.height - 200.0))],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];

    [ZL2M3BottomSheet presentWithContentView:content onDismiss:nil];
}

#pragma mark - ★Task436 克隆 / 删除

- (NSString *)ame436_selectedDisplayName {
    ControlButton *node = self.selectedNode;
    if (node == nil) return @"";
    NSString *name = node.properties[@"name"];
    if (![name isKindOfClass:[NSString class]] || name.length == 0) {
        return [self ame429_layerInfoText];
    }
    return name;
}

/// 深拷贝布局元素字典（克隆体与源体零共享可变状态：嵌套数组/字典逐层
/// mutable 重建——含抽屉 drawerData 的 buttonProperties 子列表）
- (NSMutableDictionary *)ame436_deepMutableCopyOfDict:(NSDictionary *)src {
    NSMutableDictionary *out = ([src isKindOfClass:[NSDictionary class]])
        ? [src mutableCopy] : [NSMutableDictionary dictionary];
    for (NSString *key in out.allKeys) {
        id v = out[key];
        if ([v isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [v mutableCopy];
            for (NSUInteger i = 0; i < arr.count; i++) {
                if ([arr[i] isKindOfClass:[NSDictionary class]]) {
                    arr[i] = [self ame436_deepMutableCopyOfDict:arr[i]];
                }
            }
            out[key] = arr;
        } else if ([v isKindOfClass:[NSDictionary class]]) {
            out[key] = [self ame436_deepMutableCopyOfDict:v];
        }
    }
    return out;
}

/// 「复制新 id」的 iOS 落点：v7 布局 JSON 键型无 id 字段（键型同构红线，
/// 零新增键），克隆体身份 = 新字典对象（指针身份）+ 名称后缀。空名不缀。
- (void)ame436_sanitizeCloneName:(NSMutableDictionary *)props {
    NSString *name = props[@"name"];
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return;
    props[@"name"] = [NSString stringWithFormat:@"%@ %@", name,
        localize(@"ame436.editor.clone.suffix", @"副本")];
}

/// 克隆体落位：源 frame 原点 +8pt（8pt 吸附网格语义）→ 吸附带内钳制 →
/// generateDynamicX/Y 写回（与拖拽落账同一表达式管线）。返回实际位移
/// delta（FREE 抽屉克隆时子键按同 delta 平移，非 FREE 由 syncButtons 重排）。
- (CGPoint)ame436_placeClone:(ControlButton *)cloneView
             relativeToFrame:(CGRect)srcFrame {
    CGFloat canvasW = self.canvas.frame.size.width;
    CGFloat canvasH = self.canvas.frame.size.height;
    CGFloat tx = roundf((srcFrame.origin.x + ame429_gridStep) / ame429_gridStep)
                 * ame429_gridStep;
    CGFloat ty = roundf((srcFrame.origin.y + ame429_gridStep) / ame429_gridStep)
                 * ame429_gridStep;
    CGFloat maxOX = MAX(0.0, canvasW - srcFrame.size.width);
    CGFloat maxOY = MAX(0.0, canvasH - srcFrame.size.height);
    tx = MAX(0.0, MIN(tx, maxOX));
    ty = MAX(0.0, MIN(ty, maxOY));
    cloneView.properties[@"dynamicX"] = [cloneView generateDynamicX:tx];
    cloneView.properties[@"dynamicY"] = [cloneView generateDynamicY:ty];
    [cloneView update];
    return CGPointMake(tx - srcFrame.origin.x, ty - srcFrame.origin.y);
}

/// 克隆选中控件（JSON 所属列表 insert idx+1 + 新视图上屏 + 手势挂接 +
/// 偏移 8pt + 画布 z 序按装载语义重铺 + 记脏）。
- (void)ame436_cloneSelected {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    CGRect srcFrame = node.frame;
    Ame429NodeKind kind = ame429_kindOfNode(node);
    ControlButton *cloneView = nil;

    if (kind == Ame429NodeKindSubButton) {
        ControlDrawer *parent = ((ControlSubButton *)node).parentDrawer;
        id subList = parent.drawerData[@"buttonProperties"];
        if (parent == nil || ![subList isKindOfClass:[NSMutableArray class]]) {
            NSLog(@"[Task436] clone: subbutton parent chain missing (anomalous data shape)");
            return;
        }
        NSUInteger idx = [subList indexOfObject:node.properties];
        if (idx == NSNotFound) return;
        NSMutableDictionary *copyProps =
            [self ame436_deepMutableCopyOfDict:node.properties];
        [self ame436_sanitizeCloneName:copyProps];
        [subList insertObject:copyProps atIndex:idx + 1];
        ControlSubButton *subView = [ControlSubButton buttonWithProperties:copyProps];
        [parent addButton:subView];
        [self.canvas addSubview:subView];
        [self ame429_attachGesturesToNode:subView];
        [subView update];
        [parent syncButtons];
        cloneView = subView;
    } else if (kind == Ame429NodeKindDrawer) {
        NSMutableArray *drawerList = self.layoutDict[@"mDrawerDataList"];
        if (![drawerList isKindOfClass:[NSMutableArray class]]) return;
        NSUInteger idx = [drawerList indexOfObject:((ControlDrawer *)node).drawerData];
        if (idx == NSNotFound) return;
        NSMutableDictionary *copyData =
            [self ame436_deepMutableCopyOfDict:((ControlDrawer *)node).drawerData];
        [self ame436_sanitizeCloneName:copyData[@"properties"]];
        [drawerList insertObject:copyData atIndex:idx + 1];
        ControlDrawer *drawerView = [ControlDrawer buttonWithData:copyData];
        id subButtons = copyData[@"buttonProperties"];
        if ([subButtons isKindOfClass:[NSArray class]]) {
            for (NSMutableDictionary *subProps in (NSArray *)subButtons) {
                if (![subProps isKindOfClass:[NSMutableDictionary class]]) continue;
                ControlSubButton *subView = [ControlSubButton buttonWithProperties:subProps];
                [drawerView addButton:subView];
                [self.canvas addSubview:subView];
                [self ame429_attachGesturesToNode:subView];
                [subView update];
            }
        }
        [self.canvas addSubview:drawerView];
        [self ame429_attachGesturesToNode:drawerView];
        [drawerView update];   // update 链含 syncButtons（非 FREE 子键重排）
        cloneView = drawerView;
    } else {
        NSString *listKey = (kind == Ame429NodeKindJoystick)
            ? @"mJoystickDataList" : @"mControlDataList";
        NSMutableArray *list = self.layoutDict[listKey];
        if (![list isKindOfClass:[NSMutableArray class]]) return;
        NSUInteger idx = [list indexOfObject:node.properties];
        if (idx == NSNotFound) return;
        NSMutableDictionary *copyProps =
            [self ame436_deepMutableCopyOfDict:node.properties];
        [self ame436_sanitizeCloneName:copyProps];
        [list insertObject:copyProps atIndex:idx + 1];
        cloneView = (kind == Ame429NodeKindJoystick)
            ? (ControlButton *)[ControlJoystick buttonWithProperties:copyProps]
            : [ControlButton buttonWithProperties:copyProps];
        [self.canvas addSubview:cloneView];
        [self ame429_attachGesturesToNode:cloneView];
        [cloneView update];
    }
    if (cloneView == nil) return;

    CGPoint delta = [self ame436_placeClone:cloneView relativeToFrame:srcFrame];
    if (kind == Ame429NodeKindDrawer) {
        // FREE 抽屉克隆：子键绝对坐标随抽屉同 delta 平移（非 FREE 已由
        // syncButtons 按抽屉排列规则重排，无需此步）
        NSString *orientation = ((ControlDrawer *)cloneView).drawerData[@"orientation"];
        if ([orientation isKindOfClass:[NSString class]]
            && [orientation isEqualToString:@"FREE"]) {
            for (ControlSubButton *subView in ((ControlDrawer *)cloneView).buttons) {
                CGRect f = subView.frame;
                CGFloat nx = MAX(0.0, f.origin.x + delta.x);
                CGFloat ny = MAX(0.0, f.origin.y + delta.y);
                subView.properties[@"dynamicX"] = [subView generateDynamicX:nx];
                subView.properties[@"dynamicY"] = [subView generateDynamicY:ny];
                [subView update];
            }
        }
    }

    // JSON 列表序 ↔ 画布 z 序重铺（装载语义一致性；克隆体入列非尾部时
    // addSubview 的顶部语义与列表序可能错位，统一重铺说谎防线）
    [self ame429_resyncCanvasZOrder];
    self.selectedNode = cloneView;
    [self ame429_layoutSelectionOverlay];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
    [NMToast showMessage:[NSString stringWithFormat:
        localize(@"ame436.editor.toast.cloned_fmt", @"已克隆：%@（偏移 8pt）"),
        cloneView.properties[@"name"] ?: @""]];
}

/// 删除选中控件（确认弹窗；与旧编辑器 doRemoveButton 同语义：JSON 所属
/// 列表移除 + 画布移除 + 抽屉运行时 buttons 数组同步，无 undo 栈——拖拽
/// 编辑器以「放弃更改」兜底回滚）。
- (void)ame436_deleteSelected {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    __weak typeof(self) weakSelf = self;
    NSString *name = [self ame436_selectedDisplayName];
    [ZL2M3Dialog showTitle:localize(@"ame436.editor.props.delete", @"删除控件")
                      body:[NSString stringWithFormat:
          localize(@"ame436.editor.delete.confirm.body_fmt",
              @"将删除「%@」。保存后写入布局文件；未保存前可用「放弃更改并退出」恢复。"), name]
              confirmTitle:localize(@"ame436.editor.props.delete", @"删除控件")
               destructive:YES
                onConfirm:^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    // 属性弹层先收（残留面板引用已删节点无意义）
                    [ZL2M3BottomSheet dismissWithContentView:nil];
                    [strongSelf ame436_performDeleteSelected];
                }
                 onCancel:nil];
}

- (void)ame436_performDeleteSelected {
    ControlButton *node = self.selectedNode;
    if (node == nil || node.superview == nil) return;
    Ame429NodeKind kind = ame429_kindOfNode(node);
    if (kind == Ame429NodeKindSubButton) {
        ControlDrawer *parent = ((ControlSubButton *)node).parentDrawer;
        if (parent != nil && [parent.drawerData isKindOfClass:[NSMutableDictionary class]]) {
            [parent.buttons removeObject:node];
            [parent.drawerData[@"buttonProperties"] removeObject:node.properties];
            [parent syncButtons];
        }
    } else if (kind == Ame429NodeKindDrawer) {
        ControlDrawer *drawer = (ControlDrawer *)node;
        [drawer.buttons makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [self.layoutDict[@"mDrawerDataList"] removeObject:drawer.drawerData];
    } else if (kind == Ame429NodeKindJoystick) {
        [self.layoutDict[@"mJoystickDataList"] removeObject:node.properties];
    } else {
        [self.layoutDict[@"mControlDataList"] removeObject:node.properties];
    }
    [node removeFromSuperview];
    self.selectedNode = nil;
    [self ame429_layoutSelectionOverlay];
    self.ame429_dirty = YES;
    [self ame429_refreshTitle];
    [NMToast showMessage:localize(@"ame436.editor.toast.deleted", @"控件已删除")];
}

#pragma mark - 杂项

- (void)ame429_refreshTitle {
    if (self.ame429_dirty) {
        self.titleLabel.text = [NSString stringWithFormat:@"%@ · %@",
            self.ame429_layoutFileName, localize(@"ame429.j.title.dirty", @"未保存")];
    } else {
        self.titleLabel.text = self.ame429_layoutFileName;
    }
}

@end


// ============================================================================
// ★Task436 私有面板件——实现块（类声明已前置至主 @implementation 之前，
// ★Task436-r3 判例：ObjC 方法体内类引用必须先见 @interface，声明+实现
// 连体沉尾会让主实现先用后声明 → undeclared identifier 轰炸）。本文件
// 私有，不新增 TU、不动 ZL2M3Kit——链接面零风险判例：冒烟清单外的类
// 一律做成既有 TU 内私有类；ZL2M3Kit 弹层族照旧复用。
// ============================================================================

@implementation Ame436BlockSlider
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tintColor = [ZL2Theme primary];
        [self addTarget:self action:@selector(ame436_fire)
     forControlEvents:UIControlEventValueChanged];
    }
    return self;
}
- (void)ame436_fire { if (self.ame436_onChange) self.ame436_onChange(self.value); }
@end

@implementation Ame436BlockSwitch
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.onTintColor = [ZL2Theme primary];
        [self addTarget:self action:@selector(ame436_fire)
     forControlEvents:UIControlEventValueChanged];
    }
    return self;
}
- (void)ame436_fire { if (self.ame436_onChange) self.ame436_onChange(self.on); }
@end

@implementation Ame436BlockSegment
- (instancetype)initWithItems:(NSArray *)items {
    self = [super initWithItems:items];
    if (self) {
        self.selectedSegmentTintColor = [ZL2Theme primary];
        [self addTarget:self action:@selector(ame436_fire)
     forControlEvents:UIControlEventValueChanged];
    }
    return self;
}
- (void)ame436_fire {
    if (self.ame436_onChange) self.ame436_onChange(self.selectedSegmentIndex);
}
@end

@implementation Ame436BlockTextField
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addTarget:self action:@selector(ame436_fire)
     forControlEvents:UIControlEventEditingChanged];
    }
    return self;
}
- (void)ame436_fire { if (self.ame436_onChange) self.ame436_onChange(self.text ?: @""); }
@end

@implementation Ame436SpecialKeyGrid {
    NSMutableArray<UIButton *> *_chips;
    NSInteger _current;
    void (^_onChange)(NSInteger);
}

+ (NSArray<NSArray *> *)ame436_options {
    // 元素 = @[键值, i18n 键, 缺省文案]（localize 第三参形参即注释）
    return @[
        @[@(0), @"ame436.editor.props.special.none", @"无"],
        @[@(SPECIALBTN_KEYBOARD), @"ame436.editor.props.special.keyboard", @"虚拟键盘"],
        @[@(SPECIALBTN_MENU), @"ame436.editor.props.special.menu", @"主菜单"],
        @[@(SPECIALBTN_TOGGLECTRL), @"ame436.editor.props.special.toglectrl", @"GUI 切换"],
        @[@(SPECIALBTN_VIRTUALMOUSE), @"ame436.editor.props.special.vmouse", @"虚拟鼠标"],
        @[@(SPECIALBTN_MOUSEPRI), @"ame436.editor.props.special.mousepri", @"左键"],
        @[@(SPECIALBTN_MOUSESEC), @"ame436.editor.props.special.mousesec", @"右键"],
        @[@(SPECIALBTN_MOUSEMID), @"ame436.editor.props.special.mousemid", @"中键"],
        @[@(SPECIALBTN_SCROLLUP), @"ame436.editor.props.special.scrollup", @"滚轮上"],
        @[@(SPECIALBTN_SCROLLDOWN), @"ame436.editor.props.special.scrolldown", @"滚轮下"],
    ];
}

- (instancetype)initWithCurrentValue:(NSInteger)current
                            onChange:(void (^)(NSInteger value))onChange {
    self = [super initWithFrame:CGRectZero];
    if (!self) return self;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _chips = [NSMutableArray array];
    _current = current;
    _onChange = onChange;

    UIStackView *vstack = [[UIStackView alloc] init];
    vstack.axis = UILayoutConstraintAxisVertical;
    vstack.spacing = 6.0;
    vstack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:vstack];

    NSArray *options = [Ame436SpecialKeyGrid ame436_options];
    NSUInteger rows = (options.count + 2) / 3;
    for (NSUInteger r = 0; r < rows; r++) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSUInteger c = 0; c < 3; c++) {
            NSUInteger idx = r * 3 + c;
            if (idx >= options.count) {
                // 补位空单元（FillEqually 对齐）
                UIView *spacer = [[UIView alloc] init];
                spacer.translatesAutoresizingMaskIntoConstraints = NO;
                [cells addObject:spacer];
                continue;
            }
            UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
            chip.translatesAutoresizingMaskIntoConstraints = NO;
            chip.layer.cornerRadius = [ZL2Theme radiusS];
            chip.layer.masksToBounds = YES;
            chip.titleLabel.font = [ZL2Theme fontLabelMedium];
            chip.contentEdgeInsets = UIEdgeInsetsMake(5, 8, 5, 8);
            chip.tag = [options[idx][0] integerValue];
            [chip setTitle:localize(options[idx][1], options[idx][2])
                  forState:UIControlStateNormal];
            [chip addTarget:self action:@selector(ame436_chipTapped:)
           forControlEvents:UIControlEventTouchUpInside];
            [self ame436_refreshChip:chip];
            [chip.heightAnchor constraintEqualToConstant:30.0].active = YES;
            [_chips addObject:chip];
            [cells addObject:chip];
        }
        UIStackView *hstack = [[UIStackView alloc] initWithArrangedSubviews:cells];
        hstack.axis = UILayoutConstraintAxisHorizontal;
        hstack.spacing = 6.0;
        hstack.distribution = UIStackViewDistributionFillEqually;
        hstack.translatesAutoresizingMaskIntoConstraints = NO;
        [vstack addArrangedSubview:hstack];
    }

    [NSLayoutConstraint activateConstraints:@[
        [vstack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [vstack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [vstack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [vstack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    return self;
}

- (void)ame436_refreshChip:(UIButton *)chip {
    BOOL selected = (chip.tag == _current);
    chip.backgroundColor = selected ? [ZL2Theme primaryContainer]
                                    : [ZL2Theme surfaceContainer];
    chip.tintColor = selected ? [ZL2Theme onPrimaryContainer]
                              : [ZL2Theme onSurfaceVariant];
}

- (void)ame436_chipTapped:(UIButton *)sender {
    _current = sender.tag;
    for (UIButton *chip in _chips) [self ame436_refreshChip:chip];
    if (_onChange) _onChange(_current);
}
@end
