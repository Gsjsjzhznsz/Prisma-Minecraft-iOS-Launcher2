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
@end

@implementation ZL2ControlLayoutEditorViewController

+ (void)ame429_presentFromViewController:(UIViewController *)host {
    [self ame429_presentFromViewController:host layoutFileName:nil];
}

+ (void)ame429_presentFromViewController:(UIViewController *)host
                          layoutFileName:(NSString *)fileName {
    ZL2ControlLayoutEditorViewController *editor =
        [[ZL2ControlLayoutEditorViewController alloc] init];
    editor.ame429_layoutFileNameOverride = fileName;
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
        // 坏 JSON / 缺文件：吐司后退出（不崩，不留白屏编辑器）
        [NMToast showMessage:localize(@"ame429.j.load.error", @"布局文件读取失败，请检查 controlmap 内的 JSON 文件")];
        [self dismissViewControllerAnimated:YES completion:nil];
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
        if (![nodeView isKindOfClass:[ControlButton class]]) continue;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(ame429_nodeTapped:)];
        [nodeView addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(ame429_nodePanned:)];
        pan.maximumNumberOfTouches = 1;
        [nodeView addGestureRecognizer:pan];
    }
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

    // 右侧簇：层 / 样式 / 更多 / 保存
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

    for (NSMutableDictionary *btnProps in btnList) {
        UIView *view = [self ame429_viewForProperties:btnProps];
        if (view != nil) [self.canvas addSubview:view];
    }
    for (NSMutableDictionary *drawerData in drawerList) {
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

    for (NSMutableDictionary *props in btnList) {
        ame429_applyStyleToProperties(props, params);
    }
    for (NSMutableDictionary *drawerData in drawerList) {
        ame429_applyStyleToProperties(drawerData[@"properties"], params);
        id subButtons = drawerData[@"buttonProperties"];
        if (![subButtons isKindOfClass:[NSArray class]]) continue;
        for (NSMutableDictionary *subProps in (NSArray *)subButtons) {
            if (![subProps isKindOfClass:[NSMutableDictionary class]]) continue;
            ame429_applyStyleToProperties(subProps, params);
        }
    }
    for (NSMutableDictionary *joyProps in joyList) {
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
                    [strongSelf dismissViewControllerAnimated:YES completion:nil];
                }
                 onCancel:nil];
}

- (void)ame429_discardAndExit {
    self.ame429_dirty = NO;
    [self dismissViewControllerAnimated:YES completion:nil];
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
