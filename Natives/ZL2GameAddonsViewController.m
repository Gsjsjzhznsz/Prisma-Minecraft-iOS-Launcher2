//
// ZL2GameAddonsViewController.m — ZL2 Addons 加载器选择屏（7.0-UI-14）
// 结构契约见 .h 头注。安装分发走 legacy 链；本页 UI/选择/互斥全 ZL2 语义。
//
// 红线：颜色/字体/圆角一律 ZL2Theme；iOS 14.0 API 上限（无
// button.configuration/UIMenu 挂钮/UISheetPresentationController）；SF 符号
// SF1.0 级；新建视图 translatesAutoresizingMaskIntoConstraints = NO；
// 零 viewWithTag 存状态（tag 仅作事件载荷）。
//

#import "ZL2GameAddonsViewController.h"
#import "ModService.h"          // ★ Task324：安装成功后隔离骨架即时补齐（六目录 FCL parity）
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "PLProfiles.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLMirrorCenter.h"
#import "PLTaskStages.h"

#include <stdlib.h>

#pragma mark - 安装分发目标 VC 本地最小类声明（import 手术判例：真实头链
#pragma mark ForgeInstallSchemeViewController/PLPrefTableViewController 在
#pragma mark 预览 TU 与桩实现撞符号；消费方自含声明，消息按选择器运行时解析）

@interface ForgeInstallViewController : UIViewController
@property (nonatomic, copy) NSString *gameVersion;
@property (nonatomic, assign) BOOL isNeoForge;
@property (nonatomic, assign) NSInteger selectedScheme;
@property (nonatomic, copy) void (^completionHandler)(BOOL success, NSString *profileName, id resultOrError);
@property (nonatomic, copy) NSString *presetVersionString;
@end

@interface FabricInstallViewController : UIViewController
@property (nonatomic, copy) NSString *gameVersion;
@property (nonatomic, assign) BOOL shouldInstallAPI;
@property (nonatomic, copy) void (^completionHandler)(BOOL success, NSString *profileName, NSError *error);
@end

#pragma mark - 加载器选择卡（ZL2 AddonListLayout 同构）

@class ZL2AddonCard;

@protocol ZL2AddonCardDelegate <NSObject>
- (void)addonCardDidChangeSelection:(ZL2AddonCard *)card;
@optional
- (void)addonCardDidRequestReload:(ZL2AddonCard *)card;
@end

/// 单张加载器卡：头部（图标+标题+选中值+清除+刷新+箭头）+ 可展开版本列表
@interface ZL2AddonCard : UIView
@property (nonatomic, copy) NSString *identifier;           // optifine/forge/neoforge/fabric/fabricapi
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *iconBundleName; // ModLoaderIcons 品牌图（浅色档）
@property (nonatomic, copy) NSString *fallbackSymbol;
@property (nonatomic, copy, nullable) NSArray<NSString *> *items;       // 版本清单
@property (nonatomic, copy, nullable) NSString *selectedItem;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL listFailed;
@property (nonatomic, weak, nullable) id<ZL2AddonCardDelegate> delegate;

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                    iconBundleName:(nullable NSString *)iconBundleName
                   fallbackSymbol:(NSString *)fallbackSymbol;

/// 外部驱动刷新外观（选中值/展开态/失败态）
- (void)ame_refreshAppearance;
/// 布局锚：内容固有高度由内部约束自洽；外部只需钉水平边
@end

#pragma mark - 页面本体

@interface ZL2GameAddonsViewController () <ZL2AddonCardDelegate, UITextFieldDelegate>
// 头部
@property (nonatomic, strong) UILabel *gameVersionLabel;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIControl *installButton;
@property (nonatomic, strong) UILabel *installLabel;

// 加载器卡（ZL2 顺序：OptiFine / Forge / NeoForge / Fabric / Fabric API /
// Legacy Fabric / Legacy Fabric API / Quilt / Quilted Fabric API —— Task335 与
// ZL2 AddonList 全家族对齐）
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *cardsStack;
@property (nonatomic, strong) ZL2AddonCard *optifineCard;
@property (nonatomic, strong) ZL2AddonCard *forgeCard;
@property (nonatomic, strong) ZL2AddonCard *neoforgeCard;
@property (nonatomic, strong) ZL2AddonCard *fabricCard;
@property (nonatomic, strong) ZL2AddonCard *fabricAPICard;
@property (nonatomic, strong) ZL2AddonCard *legacyFabricCard;
@property (nonatomic, strong) ZL2AddonCard *legacyFabricAPICard;
@property (nonatomic, strong) ZL2AddonCard *quiltCard;
@property (nonatomic, strong) ZL2AddonCard *quiltAPICard;
@property (nonatomic, strong) UILabel *noLoaderNote;

// 版本清单在途刷新（防抖：同卡刷新去重）
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingIdentifiers;

// 安装域（OptiFine 补丁流 + MRDT 原版流）
@property (nonatomic, strong, nullable) MinecraftResourceDownloadTask *activeTask;
@property (nonatomic, copy) NSString *pendingOptiFineAfterForge;   // forge 完成后补装的 OptiFine 载荷
@property (nonatomic, copy) NSString *pendingOptiFineGameVersion;

@end

@implementation ZL2GameAddonsViewController

- (instancetype)initWithGameVersion:(NSString *)gameVersion {
    self = [super init];
    if (self) {
        _gameVersion = [gameVersion copy] ?: @"";
        _loadingIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    [self ame_buildViews];
    [self ame_refreshInstallButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

#pragma mark - 布局

- (void)ame_buildViews {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.showsVerticalScrollIndicator = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    _scroll = scroll;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    _cardsStack = stack;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // ① ScreenHeader：游戏版本大字 + 自定义版本名输入框 + 安装钮（ZL2 顶行同构）
    _gameVersionLabel = [[UILabel alloc] init];
    _gameVersionLabel.text = [NSString stringWithFormat:@"安装 - %@", self.gameVersion];
    _gameVersionLabel.font = [ZL2Theme fontTitleLarge];
    _gameVersionLabel.textColor = [ZL2Theme onSurface];
    _gameVersionLabel.numberOfLines = 1;
    _gameVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_gameVersionLabel];

    _nameField = [[UITextField alloc] init];
    _nameField.placeholder = [NSString stringWithFormat:@"版本名（默认 %@）", self.gameVersion];
    _nameField.text = self.gameVersion;
    _nameField.font = [ZL2Theme fontBodyMedium];
    _nameField.textColor = [ZL2Theme onSurface];
    _nameField.backgroundColor = [ZL2Theme surfaceContainer];
    _nameField.layer.cornerRadius = [ZL2Theme radiusS];
    _nameField.delegate = self;
    // 左右留白（iOS 14 无 UITextField 样式 configuration 路线，用边界视图）
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _nameField.leftView = leftPad;
    _nameField.leftViewMode = UITextFieldViewModeAlways;
    _nameField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _nameField.rightViewMode = UITextFieldViewModeAlways;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField.isAccessibilityElement = YES;
    _nameField.accessibilityLabel = @"自定义版本名";
    [self.view addSubview:_nameField];

    _installButton = [[UIControl alloc] init];
    _installButton.layer.cornerRadius = [ZL2Theme radiusS];
    _installButton.translatesAutoresizingMaskIntoConstraints = NO;
    _installButton.isAccessibilityElement = YES;
    _installButton.accessibilityLabel = @"安装";
    [_installButton addTarget:self
                       action:@selector(ame_installTapped)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_installButton];

    _installLabel = [[UILabel alloc] init];
    _installLabel.font = [ZL2Theme fontLabelLarge];
    _installLabel.textAlignment = NSTextAlignmentCenter;
    _installLabel.userInteractionEnabled = NO;
    _installLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_installButton addSubview:_installLabel];

    // ② 加载器卡（ZL2 顺序：OptiFine → Forge → NeoForge → Fabric → Fabric API
    //    → Legacy Fabric → Legacy Fabric API → Quilt → Quilted Fabric API）
    _optifineCard = [self ame_cardWithIdentifier:@"optifine"
                                           title:@"OptiFine"
                                  iconBundleName:@"optifine"
                                 fallbackSymbol:@"sparkles"];
    _forgeCard = [self ame_cardWithIdentifier:@"forge"
                                        title:@"Forge"
                               iconBundleName:@"forge" // Task335: 标准单文件 key（旧 *_light 命名不在 resources 拷贝面=永久 SF 兜底死引用）
                              fallbackSymbol:@"hammer"];
    _neoforgeCard = [self ame_cardWithIdentifier:@"neoforge"
                                           title:@"NeoForge"
                                  iconBundleName:@"neoforge" // Task335: 同上死引用修正，ZL2 img_loader_neoforge 同源
                                 fallbackSymbol:@"hammer.fill"];
    _fabricCard = [self ame_cardWithIdentifier:@"fabric"
                                         title:@"Fabric"
                                iconBundleName:@"fabric" // Task335: 同上死引用修正，ZL2 img_loader_fabric 同源
                               fallbackSymbol:@"link"];
    _fabricAPICard = [self ame_cardWithIdentifier:@"fabricapi"
                                            title:@"Fabric API"
                                   iconBundleName:nil
                                  fallbackSymbol:@"shippingbox"];
    _legacyFabricCard = [self ame_cardWithIdentifier:@"legacyfabric"
                                               title:@"Legacy Fabric"
                                      iconBundleName:@"legacyfabric"
                                     fallbackSymbol:@"link"];
    _legacyFabricAPICard = [self ame_cardWithIdentifier:@"legacyfabricapi"
                                                  title:@"Legacy Fabric API"
                                         iconBundleName:nil
                                        fallbackSymbol:@"shippingbox"];
    _quiltCard = [self ame_cardWithIdentifier:@"quilt"
                                        title:@"Quilt"
                               iconBundleName:@"quilt"
                              fallbackSymbol:@"bird"];
    _quiltAPICard = [self ame_cardWithIdentifier:@"quiltapi"
                                           title:@"Quilted Fabric API"
                                  iconBundleName:nil
                                 fallbackSymbol:@"shippingbox"];
    for (ZL2AddonCard *card in @[_optifineCard, _forgeCard, _neoforgeCard,
                                 _fabricCard, _fabricAPICard,
                                 _legacyFabricCard, _legacyFabricAPICard,
                                 _quiltCard, _quiltAPICard]) {
        [stack addArrangedSubview:card];
        [card.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [card.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }

    // ★ Task335：无可用加载器版本（rd-*/a1.*/b1.* 等远古系全隐藏后）的引导文案
    // —— 用户装机原话「在没有加载器支持的版本打开…显示清单加载失败，导致无法
    // 点击安装原版」：与其出五张注定失败的红字卡，不如明示「无加载器可用，
    // 可直接安装原版」，安装钮永不误导。
    _noLoaderNote = [[UILabel alloc] init];
    _noLoaderNote.text = @"该版本暂无可用模组加载器，可直接安装原版。";
    _noLoaderNote.font = [ZL2Theme fontBodyMedium];
    _noLoaderNote.textColor = [ZL2Theme onSurfaceVariant];
    _noLoaderNote.textAlignment = NSTextAlignmentCenter;
    _noLoaderNote.numberOfLines = 0;
    _noLoaderNote.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:_noLoaderNote];

    // Task324：头部弹性链两枚降优先级约束（视图建好后创建，先赋优先级再入激活数组）
    NSLayoutConstraint *ame324_fieldLead =
        [_nameField.leadingAnchor constraintGreaterThanOrEqualToAnchor:_gameVersionLabel.trailingAnchor
                                                              constant:16];
    ame324_fieldLead.priority = 999;   // 窄宽让位钮最小宽（必醒）
    NSLayoutConstraint *ame324_fieldPref =
        [_nameField.widthAnchor constraintEqualToConstant:220];
    ame324_fieldPref.priority = 900;   // 首选宽，让位给 120 下限与钮最小宽

    [NSLayoutConstraint activateConstraints:@[
        [_gameVersionLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_gameVersionLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],

        [_nameField.centerYAnchor constraintEqualToAnchor:_gameVersionLabel.centerYAnchor],
        // ★ Task324（IMG_0485 三病根根修·按钮截断）：旧版 nameField 固定 220 +
        //   安装钮派生宽（leading 链定）+ 钮上标签无内边距锚，窄宽容器（iPhone/
        //   分屏）下必炸：约束不可满足 → AL 破坏 → 钮被压缩到负空间（标签溢出
        //   截断）。改弹性链：field 首选 220@900 可压缩至 >=120；钮最小宽 96；
        //   标签四边内边距钳制永不溢出；field 头部不等式降 999 让位钮最小宽。
        //   （优先级赋值须先落局部变量再入数组——r1 CI 实锤：数组字面量内
        //   .priority 赋值表达式非对象元素非法）
        ame324_fieldLead,
        [_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        ame324_fieldPref,
        [_nameField.heightAnchor constraintEqualToConstant:40],

        [_installButton.centerYAnchor constraintEqualToAnchor:_gameVersionLabel.centerYAnchor],
        [_installButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_installButton.leadingAnchor constraintEqualToAnchor:_nameField.trailingAnchor constant:12],
        [_installButton.heightAnchor constraintEqualToConstant:40],
        // Task324：钮最小宽（压缩下限）+ 标签内边距钳制（被压时省略号而非溢出截断）
        [_installButton.widthAnchor constraintGreaterThanOrEqualToConstant:96],
        [_installLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_installButton.leadingAnchor constant:14],
        [_installLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_installButton.trailingAnchor constant:-14],

        [_installLabel.centerXAnchor constraintEqualToAnchor:_installButton.centerXAnchor],
        [_installLabel.centerYAnchor constraintEqualToAnchor:_installButton.centerYAnchor],

        [scroll.topAnchor constraintEqualToAnchor:_gameVersionLabel.bottomAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        // ★ Task324（IMG_0485 三病根根修·挤左1/4+右侧死空间）：旧版滚动内容
        //   宽度无锚定（只钉 contentLayoutGuide 四边不钉宽）= 经典歧义布局，
        //   AL 取内容最小固有宽 → 卡片塌缩到左 1/4、右侧全死空间。补宽度锚
        //   （frame 宽 -32 = 左右 16 边距）后内容恒满幅，与 ZL2GameDownload
        //   全宽卡片同观感。
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];
    // Task324：标题压缩阻力 950 —— 窄宽让位次序 = field 缩宽(900) → 标题省略(950)
    // → 钮最小宽(必醒)永不破，安装钮在任意宽度下不再截断
    [_gameVersionLabel setContentCompressionResistancePriority:950
                                                      forAxis:UILayoutConstraintAxisHorizontal];

    // ★ Task335：加载器版本支持门控统一套用（ZL2 LoaderVerSupports 同口径）。
    // 不支持门 = 隐藏卡（UIStackView 折叠），替代旧行为「呈现注定失败的红字卡」。
    _neoforgeCard.hidden = ![self ame_neoforgeSupported];
    _fabricCard.hidden = ![self ame_fabricLikeSupported];
    _fabricAPICard.hidden = _fabricCard.hidden;
    _legacyFabricCard.hidden = ![self ame_legacyFabricSupported];
    _legacyFabricAPICard.hidden = _legacyFabricCard.hidden;
    _quiltCard.hidden = ![self ame_fabricLikeSupported];
    _quiltAPICard.hidden = _quiltCard.hidden;
    _forgeCard.hidden = ![self ame_forgeFamilySupported];
    _optifineCard.hidden = ![self ame_forgeFamilySupported];
    BOOL ame335_anyCard = !(_neoforgeCard.hidden && _fabricCard.hidden &&
                            _legacyFabricCard.hidden && _quiltCard.hidden &&
                            _forgeCard.hidden && _optifineCard.hidden);
    _noLoaderNote.hidden = ame335_anyCard;
    // Fabric API 清单依赖游戏版本（Modrinth facets），卡可见时首屏即拉；
    // 隐藏版本不再发起注定失败的拉取
    if (!_fabricAPICard.hidden) {
        [self ame_loadListForCard:_fabricAPICard];
    }
}

- (ZL2AddonCard *)ame_cardWithIdentifier:(NSString *)identifier
                                   title:(NSString *)title
                          iconBundleName:(NSString *)iconBundleName
                         fallbackSymbol:(NSString *)fallbackSymbol {
    ZL2AddonCard *card = [[ZL2AddonCard alloc] initWithIdentifier:identifier
                                                             title:title
                                                    iconBundleName:iconBundleName
                                                   fallbackSymbol:fallbackSymbol];
    card.delegate = self;
    return card;
}

#pragma mark - 加载器版本支持门控（Task335：ZL2 LoaderVerSupports 同口径）

// ZL2 DownloadGameModLoaderLists.kt rememberLoaderVerSupports：
//   fabricLike = isBiggerVer("1.13.2") → Fabric/Quilt 仅 1.14+；
//   LegacyFabric = !fabricLike（≤1.13.2，实测 meta 支持 1.3–1.13）；
//   NeoForge = isBiggerVer("1.20")（1.20.1 起步，与既有 ame_neoforgeSupported 同判）。
// iOS 侧加固：rd-*/a1.*/b1.*/c0.* 等远古系对 Forge/OptiFine 也无版本线（BMCLAPI
// 实测空），隐藏而非呈现注定失败的清单卡（“清单加载失败”红字 = 装机投诉点）。

/// "1.x[.z]" 形态判定（现代版号线；快照 25w14a 等不入）
- (BOOL)ame_isModernOneDotX {
    return [self.gameVersion hasPrefix:@"1."];
}

/// 1.<minor>[.<patch>] → minor（非 1.x 形态返回 -1）
- (NSInteger)ame_oneDotMinor {
    if (![self ame_isModernOneDotX]) return -1;
    NSArray<NSString *> *parts = [self.gameVersion componentsSeparatedByString:@"."];
    if (parts.count < 2) return -1;
    return [parts[1] integerValue];
}

/// Forge/OptiFine 家族：1.x 全系（Forge 自 1.1、OptiFine 自 Beta 线；
/// 远古非 1.x 形态两源均无版本线）
- (BOOL)ame_forgeFamilySupported {
    return [self ame_isModernOneDotX];
}

/// Fabric/Quilt：>1.13.2（ZL2 fabricLike 同口径）
- (BOOL)ame_fabricLikeSupported {
    NSInteger minor = [self ame_oneDotMinor];
    return minor >= 14;
}

/// Legacy Fabric：1.3–1.13（meta.legacyfabric.net 实测支持域；
/// 1.14+ 归 Fabric/Quilt，1.2 及以前无支持）
- (BOOL)ame_legacyFabricSupported {
    NSInteger minor = [self ame_oneDotMinor];
    return minor >= 3 && minor <= 13;
}

- (BOOL)ame_neoforgeSupported {
    // "1.20.1" 起 NeoForge 有版本线；1.x 快照/远古全不支持
    NSArray<NSString *> *parts = [self.gameVersion componentsSeparatedByString:@"."];
    if (parts.count < 2) return NO;
    if (![parts[0] isEqualToString:@"1"]) return NO;
    NSInteger minor = [parts[1] integerValue];
    if (minor > 20) return YES;
    if (minor < 20) return NO;
    // 1.20.x：x>=1 有线（1.20.1 起步）
    if (parts.count < 3) return NO;
    return [parts[2] integerValue] >= 1;
}

#pragma mark - ZL2AddonCardDelegate（选择变更 → 互斥 + API 跟随）

// Task335：API 卡 ↔ 主加载器卡映射（ZL2 apiToPrimary 同语义）
- (ZL2AddonCard *)ame_apiCardForLoaderIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"fabric"]) return self.fabricAPICard;
    if ([identifier isEqualToString:@"legacyfabric"]) return self.legacyFabricAPICard;
    if ([identifier isEqualToString:@"quilt"]) return self.quiltAPICard;
    return nil;
}

- (void)addonCardDidChangeSelection:(ZL2AddonCard *)card {
    NSString *sel = card.selectedItem;
    if (sel.length == 0) {
        // 清除选择：所属 API 卡跟随清除（iOS 侧保持一致性：loader 没了 API 无意义）
        ZL2AddonCard *apiCard = [self ame_apiCardForLoaderIdentifier:card.identifier];
        if (apiCard) {
            apiCard.selectedItem = nil;
            [apiCard ame_refreshAppearance];
        }
    } else {
        [self ame_applyExclusionForSelected:card.identifier];
        // 主加载器选中 → 自动跟随最新 API（ZL2 DownloadGameWithAddonScreen
        // 同语义：lastAPIVersion = *APIList.firstOrNull）
        ZL2AddonCard *apiCard = [self ame_apiCardForLoaderIdentifier:card.identifier];
        if (apiCard) {
            [self ame_loadListForCard:apiCard];
        }
    }
    [self ame_refreshInstallButton];
}

/// 互斥（Task335：ZL2 ModLoader 家族语义全家族化）
/// 规则：optifine 仅可与 forge 共存；forge/neoforge/fabric/legacyfabric/quilt
/// 五主加载器互斥（forge⇄optifine 组合除外）；API 卡不参与互斥。
- (void)ame_applyExclusionForSelected:(NSString *)identifier {
    NSDictionary<NSString *, NSArray<NSString *> *> *exclusions = @{
        @"forge":       @[@"neoforge", @"fabric", @"legacyfabric", @"quilt"],
        @"neoforge":    @[@"forge", @"fabric", @"legacyfabric", @"quilt", @"optifine"],
        @"fabric":      @[@"forge", @"neoforge", @"legacyfabric", @"quilt", @"optifine"],
        @"legacyfabric": @[@"forge", @"neoforge", @"fabric", @"quilt", @"optifine"],
        @"quilt":       @[@"forge", @"neoforge", @"fabric", @"legacyfabric", @"optifine"],
        @"optifine":    @[@"neoforge", @"fabric", @"legacyfabric", @"quilt"],
    };
    for (NSString *other in exclusions[identifier] ?: @[]) {
        ZL2AddonCard *otherCard = [self ame_cardForIdentifier:other];
        if (otherCard && otherCard.selectedItem.length > 0) {
            otherCard.selectedItem = nil;
            // 被清除的主加载器，其 API 卡跟随清除
            ZL2AddonCard *otherAPI = [self ame_apiCardForLoaderIdentifier:other];
            if (otherAPI) {
                otherAPI.selectedItem = nil;
                [otherAPI ame_refreshAppearance];
            }
            [otherCard ame_refreshAppearance];
        }
    }
}

- (ZL2AddonCard *)ame_cardForIdentifier:(NSString *)identifier {
    NSDictionary<NSString *, ZL2AddonCard *> *map = @{
        @"optifine": self.optifineCard,
        @"forge": self.forgeCard,
        @"neoforge": self.neoforgeCard,
        @"fabric": self.fabricCard,
        @"fabricapi": self.fabricAPICard,
        @"legacyfabric": self.legacyFabricCard,
        @"legacyfabricapi": self.legacyFabricAPICard,
        @"quilt": self.quiltCard,
        @"quiltapi": self.quiltAPICard,
    };
    return map[identifier];
}

#pragma mark - 清单加载（按需拉取，latest-wins 代际防护）

- (void)addonCardDidRequestReload:(ZL2AddonCard *)card {
    [self ame_loadListForCard:card];
}

- (void)ame_loadListForCard:(ZL2AddonCard *)card {
    NSString *ident = card.identifier;
    if ([self.loadingIdentifiers containsObject:ident]) return;
    [self.loadingIdentifiers addObject:ident];
    card.loading = YES;
    card.listFailed = NO;
    [card ame_refreshAppearance];

    NSString *gameVersion = self.gameVersion;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *items = [self ame_fetchListForIdentifier:ident
                                                          gameVersion:gameVersion];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIdentifiers removeObject:ident];
            card.loading = NO;
            if (items.count == 0) {
                card.listFailed = YES;
                card.items = nil;
            } else {
                card.listFailed = NO;
                card.items = items;
                // API 卡自动跟随（Task335 泛化：fabricapi/legacyfabricapi/quiltapi
                // 同语义 —— 清单落定且所属主加载器已选而 API 未选 → 选最新，
                // ZL2 lastAPIVersion = *APIList.firstOrNull 同口径）
                NSString *ame335_loaderIdent = nil;
                if ([ident isEqualToString:@"fabricapi"]) ame335_loaderIdent = @"fabric";
                else if ([ident isEqualToString:@"legacyfabricapi"]) ame335_loaderIdent = @"legacyfabric";
                else if ([ident isEqualToString:@"quiltapi"]) ame335_loaderIdent = @"quilt";
                if (ame335_loaderIdent.length > 0) {
                    ZL2AddonCard *loaderCard = [self ame_cardForIdentifier:ame335_loaderIdent];
                    if (loaderCard.selectedItem.length > 0 && card.selectedItem.length == 0) {
                        card.selectedItem = items.firstObject;
                    }
                }
            }
            [card ame_refreshAppearance];
            [self ame_refreshInstallButton];
        });
    });
}

/// 各加载器清单端点（Task325：接入 PLMirrorCenter 候选链 —— 策略感知官方/镜像
/// 排序；Forge 死兜底 XML 解析补齐；OptiFine 官方 HTML 兑底）
- (nullable NSArray<NSString *> *)ame_fetchListForIdentifier:(NSString *)identifier
                                                 gameVersion:(NSString *)gameVersion {
    NSData *data = nil;
    if ([identifier isEqualToString:@"forge"]) {
        // BMCLAPI forge/minecraft/{v}：[{version:"xx.yy.z"}]（含 build 号）
        // ★ Task325：原代码 maven-metadata.xml 兑底拿到数据后仍走 JSON 解析 =
        //   死兑底（XML 永远解析不出）；BMCLAPI DNS 故障（-1003 判例）时官方
        //   源彻底不可用。改为：BMCLAPI JSON 主源 → 官方 metadata.xml 正则提取。
        data = [self ame_syncFetch:
            [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/forge/minecraft/%@", gameVersion]];
        if (data) {
            id json = [self ame_parseJSON:data];
            if ([json isKindOfClass:[NSArray class]]) {
                NSMutableArray *out_ = [NSMutableArray array];
                for (NSDictionary *entry in json) {
                    NSString *version = entry[@"version"];
                    if (version.length > 0) [out_ addObject:version];
                }
                if (out_.count > 0) return out_;
            }
        }
        NSLog(@"[ZL2Addons] forge bmclapi list failed -- falling back to official maven-metadata.xml");
        NSData *meta = [self ame_syncFetch:
            @"https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"];
        if (meta) {
            NSString *xml = [[NSString alloc] initWithData:meta encoding:NSUTF8StringEncoding];
            if (xml.length > 0) {
                NSRegularExpression *rx = [NSRegularExpression
                    regularExpressionWithPattern:@"<version>([^<]+)</version>" options:0 error:nil];
                NSMutableArray *out_ = [NSMutableArray array];
                [rx enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length)
                                  usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                    NSString *v = [xml substringWithRange:[m rangeAtIndex:1]];
                    // 形如 1.21.1-52.0.24：按游戏版本前缀过滤
                    if ([v hasPrefix:gameVersion] && [v rangeOfString:@"-"].location != NSNotFound) {
                        [out_ addObject:v];
                    }
                }];
                // metadata 倒序 = 新版在前（文件内旧版在前）
                if (out_.count > 0) return [[out_ reverseObjectEnumerator] allObjects];
            }
        }
        return nil;
    }
    if ([identifier isEqualToString:@"neoforge"]) {
        // Task325：maven.neoforged.net 单源 → 候选链（官方 + BMCLAPI /maven 镜像，策略感知）
        NSURL *official = [NSURL URLWithString:
            @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"];
        NSArray<NSURL *> *cands = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                                 resourceType:PLMirrorResourceTypeModLoader];
        if (cands.count == 0) cands = @[official];
        for (NSURL *u in cands) {
            data = [self ame_syncFetch:u.absoluteString];
            if (data) break;
        }
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        NSArray<NSString *> *all = json[@"versions"];
        if (!all) return nil;
        // 过滤当前游戏版本前缀（"1.21.1-beta"/"1.21.1"），新线在前
        NSString *prefix = [NSString stringWithFormat:@"%@-", gameVersion];
        NSMutableArray *out_ = [NSMutableArray array];
        for (NSString *version in all) {
            if ([version hasPrefix:prefix]) [out_ addObject:version];
        }
        return [[out_ reverseObjectEnumerator] allObjects];
    }
    if ([identifier isEqualToString:@"fabric"]) {
        // Fabric meta v2：[{loader:{version:"x.y.z"}}]（Task325：候选链替换硬编码双源，
        // meta.fabricmc.net → BMCLAPI /fabric-meta 映射已在 PLMirrorCenter）
        NSURL *official = [NSURL URLWithString:
            [NSString stringWithFormat:@"https://meta.fabricmc.net/v2/versions/loader/%@", gameVersion]];
        NSArray<NSURL *> *cands = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                                 resourceType:PLMirrorResourceTypeModLoader];
        if (cands.count == 0) cands = @[official];
        for (NSURL *u in cands) {
            data = [self ame_syncFetch:u.absoluteString];
            if (data) break;
        }
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        if (![json isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray *out_ = [NSMutableArray array];
        for (NSDictionary *entry in json) {
            NSString *version = entry[@"loader"][@"version"];
            if (version.length > 0) [out_ addObject:version];
        }
        return out_;
    }
    if ([identifier isEqualToString:@"fabricapi"]) {
        return [self ame_fetchModrinthVersionsForProject:@"fabric-api"
                                              loaderTag:@"fabric"
                                            gameVersion:gameVersion];
    }
    // ★ Task335：Legacy Fabric 加载器清单（meta.legacyfabric.net v2 —— 与 Fabric
    // meta v2 同构 [{loader:{version}}]；ZL2 LegacyFabricVersions 同源，2026-10
    // 实测 1.3–1.13 域内正常出列表）。BMCLAPI 无 legacy-fabric-meta 映射 →
    // 候选链仅官方源（PLMirrorCenter 未识别主机原样返回）。
    if ([identifier isEqualToString:@"legacyfabric"]) {
        NSURL *official = [NSURL URLWithString:
            [NSString stringWithFormat:@"https://meta.legacyfabric.net/v2/versions/loader/%@", gameVersion]];
        NSArray<NSURL *> *cands = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                                 resourceType:PLMirrorResourceTypeModLoader];
        if (cands.count == 0) cands = @[official];
        for (NSURL *u in cands) {
            data = [self ame_syncFetch:u.absoluteString];
            if (data) break;
        }
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        if (![json isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray *out_ = [NSMutableArray array];
        for (NSDictionary *entry in json) {
            NSString *version = entry[@"loader"][@"version"];
            if (version.length > 0) [out_ addObject:version];
        }
        return out_;
    }
    // ★ Task335：Legacy Fabric API（Modrinth 项目 legacy-fabric-api，ZL2
    // LegacyFabricAPIVersions 项目 9CJED7xi 同源）。注意该项目真实 loader 标签是
    // ["legacy-fabric"]（["fabric"] 查询恒空，2026-10 实测）。
    if ([identifier isEqualToString:@"legacyfabricapi"]) {
        return [self ame_fetchModrinthVersionsForProject:@"legacy-fabric-api"
                                              loaderTag:@"legacy-fabric"
                                            gameVersion:gameVersion];
    }
    // ★ Task335：Quilt 加载器清单（meta.quiltmc.org v3 —— 与 Fabric meta 同构；
    // ZL2 QuiltVersions 同源；BMCLAPI /quilt-meta 映射经 PLMirrorCenter 候选链）
    if ([identifier isEqualToString:@"quilt"]) {
        NSURL *official = [NSURL URLWithString:
            [NSString stringWithFormat:@"https://meta.quiltmc.org/v3/versions/loader/%@", gameVersion]];
        NSArray<NSURL *> *cands = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                                 resourceType:PLMirrorResourceTypeModLoader];
        if (cands.count == 0) cands = @[official];
        for (NSURL *u in cands) {
            data = [self ame_syncFetch:u.absoluteString];
            if (data) break;
        }
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        if (![json isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray *out_ = [NSMutableArray array];
        for (NSDictionary *entry in json) {
            NSString *version = entry[@"loader"][@"version"];
            if (version.length > 0) [out_ addObject:version];
        }
        return out_;
    }
    // ★ Task335：Quilted Fabric API（Modrinth 项目 qsl，ZL2 QuiltAPIVersions 同源）
    if ([identifier isEqualToString:@"quiltapi"]) {
        return [self ame_fetchModrinthVersionsForProject:@"qsl"
                                              loaderTag:@"quilt"
                                            gameVersion:gameVersion];
    }
    if ([identifier isEqualToString:@"optifine"]) {
        // BMCLAPI OptiFine 清单：[{type:"HD_U",patch:"H1",mcversion:"1.20.4"}]
        // ★ Task325：bmclapi2 单源是 OptiFine“清单加载失败”的唯一定时炸弹（用户
        //   日志 DNS -1003 实弹）；兑底 = 官方 optifine.net/downloads 页 HTML 提取
        //   （OptiFine_<mc>_<type>_<patch>.jar 文件名正则，构造同款载荷）。
        data = [self ame_syncFetch:@"https://bmclapi2.bangbang93.com/optifine/versionList"];
        if (data) {
            id json = [self ame_parseJSON:data];
            if ([json isKindOfClass:[NSArray class]]) {
                NSMutableArray *out_ = [NSMutableArray array];
                for (NSDictionary *entry in json) {
                    if (![entry[@"mcversion"] isEqualToString:gameVersion]) continue;
                    NSString *type = entry[@"type"] ?: @"";
                    NSString *patch = entry[@"patch"] ?: @"";
                    if (type.length == 0) continue;
                    [out_ addObject:[NSString stringWithFormat:@"%@\x1f%@\x1f%@", type, patch, entry[@"filename"] ?: @""]];
                }
                if (out_.count > 0) return out_;
            }
        }
        NSLog(@"[ZL2Addons] optifine bmclapi list failed -- falling back to optifine.net/downloads HTML");
        NSData *htmlData = [self ame_syncFetch:@"https://optifine.net/downloads"];
        if (htmlData) {
            NSString *html = [[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding];
            if (html.length > 0) {
                // 文件名形态：OptiFine_1.21.4_HD_U_I7.jar（末段=patch，中段=type）
                NSRegularExpression *rx = [NSRegularExpression
                    regularExpressionWithPattern:@"OptiFine_([0-9][0-9._]*)_(.+?)\\.jar"
                    options:0 error:nil];
                NSMutableArray *out_ = [NSMutableArray array];
                NSMutableSet *seen = [NSMutableSet set];
                [rx enumerateMatchesInString:html options:0 range:NSMakeRange(0, html.length)
                                  usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                    if ([m numberOfRanges] < 3) return;
                    NSString *mc = [html substringWithRange:[m rangeAtIndex:1]];
                    NSString *tp = [html substringWithRange:[m rangeAtIndex:2]];
                    if (![mc isEqualToString:gameVersion]) return;
                    NSArray *segs = [tp componentsSeparatedByString:@"_"];
                    if (segs.count < 2) return;
                    NSString *patch = segs.lastObject;
                    NSString *type = [[segs subarrayWithRange:NSMakeRange(0, segs.count - 1)]
                        componentsJoinedByString:@"_"];
                    if (type.length == 0 || patch.length == 0) return;
                    NSString *payload = [NSString stringWithFormat:@"%@\x1f%@\x1fOptiFine_%@_%@.jar", type, patch, mc, tp];
                    if (![seen containsObject:payload]) {
                        [seen addObject:payload];
                        [out_ addObject:payload];
                    }
                }];
                if (out_.count > 0) return out_;
            }
        }
        return nil;
    }
    return nil;
}

/// ★ Task335：Modrinth API 工程版本列表通用端点（原 fabricapi 分支逻辑上提）。
/// 返回 version_number 列表（新版在前），经 PLMirrorCenter AssetSearch 候选链。
- (nullable NSArray<NSString *> *)ame_fetchModrinthVersionsForProject:(NSString *)project
                                                            loaderTag:(NSString *)loaderTag
                                                          gameVersion:(NSString *)gameVersion {
    NSData *data = nil;
    NSString *gv = [gameVersion stringByAddingPercentEncodingWithAllowedCharacters:
                    [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *official = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://api.modrinth.com/v2/project/%@/version?game_versions=[%%22%@%%22]&loaders=[%%22%@%%22]",
        project, gv, loaderTag]];
    NSArray<NSURL *> *cands = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                             resourceType:PLMirrorResourceTypeAssetSearch];
    if (cands.count == 0) cands = @[official];
    for (NSURL *u in cands) {
        data = [self ame_syncFetch:u.absoluteString];
        if (data) break;
    }
    if (!data) return nil;
    id json = [self ame_parseJSON:data];
    if (![json isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *out_ = [NSMutableArray array];
    for (NSDictionary *entry in json) {
        NSString *versionNumber = entry[@"version_number"];
        if (versionNumber.length > 0) [out_ addObject:versionNumber];
    }
    return out_;
}

- (nullable NSData *)ame_syncFetch:(NSString *)urlString {
    if (urlString.length == 0) return nil;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 20;
    cfg.timeoutIntervalForResource = 40;
    // 浏览器 UA（BMCLAPI/Cloudflare 家族判例：默认 UA 403）
    cfg.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        @"Accept": @"*/*"
    };
    __block NSData *result = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sessionWithConfiguration:cfg]
        dataTaskWithURL:url
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) result = data;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 40LL * NSEC_PER_SEC));
    return result;
}

- (nullable id)ame_parseJSON:(NSData *)data {
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

#pragma mark - 安装按钮（三态：可安装 / 清单加载中 / 无选择也可装原版）

- (NSString *)ame_effectiveVersionName {
    NSString *name = self.nameField.text ?: @"";
    name = [name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) return self.gameVersion;
    return name;
}

- (void)ame_refreshInstallButton {
    BOOL hasSelection = self.forgeCard.selectedItem.length > 0 ||
                        self.neoforgeCard.selectedItem.length > 0 ||
                        self.fabricCard.selectedItem.length > 0 ||
                        self.legacyFabricCard.selectedItem.length > 0 ||
                        self.quiltCard.selectedItem.length > 0 ||
                        self.optifineCard.selectedItem.length > 0;
    self.installButton.userInteractionEnabled = YES;
    self.installButton.backgroundColor = [ZL2Theme primary];
    self.installLabel.textColor = [ZL2Theme onPrimary];
    // ★ Task335：busy 态不再改安装钮文案 —— 旧版 busy 时按钮长期显示“清单加载中…”
    // （慢源 40s+ 兑底链期间），用户感知“卡在清单加载中”且不敢点（装机投诉原话）。
    // 加载态由各卡自带 spinner 表达；安装钮文案只反映语义（装什么），恒可点。
    self.installLabel.text = hasSelection ? @"安装"
                            : @"安装（原版）";
    self.installButton.accessibilityLabel = self.installLabel.text;
}

- (void)ame_installTapped {
    [self.nameField resignFirstResponder];
    NSString *versionId = [self ame_effectiveVersionName];
    if (versionId.length == 0) return;

    NSString *forge = self.forgeCard.selectedItem;
    NSString *neoforge = self.neoforgeCard.selectedItem;
    NSString *fabric = self.fabricCard.selectedItem;
    NSString *fabricAPIOn = self.fabricAPICard.selectedItem;   // 布尔语义（依赖 fabric）
    NSString *legacyFabric = self.legacyFabricCard.selectedItem;         // ★ Task335
    NSString *legacyFabricAPIOn = self.legacyFabricAPICard.selectedItem; // ★ Task335
    NSString *quilt = self.quiltCard.selectedItem;                       // ★ Task335
    NSString *quiltAPIOn = self.quiltAPICard.selectedItem;               // ★ Task335
    NSString *optifine = self.optifineCard.selectedItem;

    // ★ Task335：Fabric-like 家族（Fabric / Legacy Fabric / Quilt）统一分发到
    // FabricInstallViewController（其 vendor 段原生支持三厂；preset 直入对应
    // 厂商 + 卡片所选加载器版本直通，API 卡选择 → shouldInstallAPI）
    if (fabric.length > 0 || legacyFabric.length > 0 || quilt.length > 0) {
        FabricInstallViewController *vc = [[FabricInstallViewController alloc] init];
        vc.gameVersion = self.gameVersion;
        if (legacyFabric.length > 0) {
            vc.presetVendor = @"Legacy Fabric";
            vc.presetLoaderVersion = legacyFabric;
            vc.shouldInstallAPI = (legacyFabricAPIOn.length > 0);
        } else if (quilt.length > 0) {
            vc.presetVendor = @"Quilt";
            vc.presetLoaderVersion = quilt;
            vc.shouldInstallAPI = (quiltAPIOn.length > 0);
        } else {
            vc.presetVendor = @"Fabric";
            vc.presetLoaderVersion = fabric;
            vc.shouldInstallAPI = (fabricAPIOn.length > 0);
        }
        __weak typeof(self) weakSelf = self;
        vc.completionHandler = ^(BOOL success, NSString *profileName, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (!s) return;
                if (success) {
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"ReloadProfileList" object:nil];
                    // Task324：安装成功即时补齐隔离骨架（注册表已隔离 → 六目录可见可即用）
                    [ModService ame324_ensureIsolationSkeletonsAll];
                    [ZL2M3Dialog showTitle:@"安装完成"
                                      body:profileName ?: versionId
                              confirmTitle:@"知道了"
                                destructive:NO
                                 onConfirm:nil onCancel:nil];
                } else if (error) {
                    [ZL2M3Dialog showTitle:@"安装失败"
                                      body:error.localizedDescription ?: @"网络异常，可重试。"
                              confirmTitle:@"知道了"
                                destructive:NO
                                 onConfirm:nil onCancel:nil];
                }
            });
        };
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if (neoforge.length > 0 || forge.length > 0) {
        // Forge/NeoForge：legacy ForgeInstallViewController（preset 直入方案选择，
        // 跳过清单重拉）；完成后若有 OptiFine 组合则补装补丁
        ForgeInstallViewController *vc = [[ForgeInstallViewController alloc] init];
        vc.gameVersion = self.gameVersion;
        vc.isNeoForge = (neoforge.length > 0);
        vc.presetVersionString = neoforge.length > 0 ? neoforge : forge;
        __weak typeof(self) weakSelf = self;
        NSString *optiPayload = (optifine.length > 0 && neoforge.length == 0) ? optifine : nil;
        vc.completionHandler = ^(BOOL success, NSString *profileName, id resultOrError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (!s) return;
                if (!success) {
                    NSString *msg = [resultOrError isKindOfClass:NSError.class]
                        ? ((NSError *)resultOrError).localizedDescription
                        : @"安装流程中断，可重试。";
                    [ZL2M3Dialog showTitle:@"安装失败" body:msg
                              confirmTitle:@"知道了" destructive:NO
                               onConfirm:nil onCancel:nil];
                    return;
                }
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"ReloadProfileList" object:nil];
                // Task324：forge/neoforge 安装成功即时补齐隔离骨架（版本 id 映射免查，全量扫描幂等）
                [ModService ame324_ensureIsolationSkeletonsAll];
                if (optiPayload.length > 0) {
                    // forge 完成后补装 OptiFine 补丁（继承链：optifine 继承 forge 版本）
                    s.pendingOptiFineAfterForge = optiPayload;
                    s.pendingOptiFineGameVersion = profileName ?: versionId;
                    [s ame_installOptiFinePatch];
                } else {
                    [ZL2M3Dialog showTitle:@"安装完成"
                                      body:profileName ?: versionId
                              confirmTitle:@"知道了"
                                destructive:NO
                                 onConfirm:nil onCancel:nil];
                }
            });
        };
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if (optifine.length > 0) {
        // 仅 OptiFine：父版本必须已存在（原版或已装 forge）；不阻断——BMCLAPI
        // 补丁流尾部有父版本检查（同 legacy installOptiFineAsPatch）
        self.pendingOptiFineGameVersion = self.gameVersion;
        [self ame_installOptiFinePatch];
        return;
    }

    // 纯原版：MRDT downloadVersion（ZL2GameDownloadViewController 同款五键隔离）
    [self ame_installVanilla:versionId];
}

#pragma mark - 原版安装（MRDT，ZL2GameDownloadViewController 同款）

- (void)ame_installVanilla:(NSString *)versionId {
    if (self.activeTask) {
        [ZL2M3Dialog showTitle:@"任务进行中"
                          body:@"有安装任务正在进行，请稍候。"
                  confirmTitle:@"知道了"
                    destructive:NO
                     onConfirm:nil onCancel:nil];
        return;
    }

    // 版本隔离 profile（Task242 口径五键）
    // ★ Task335：lastVersionId 必须指向【实际下载的版本】（self.gameVersion），
    // profile 名才是用户自定义名 —— 旧实现两者都写自定义名，自定义名 ≠ 版本号时
    // 启动必报「未能打开文件 <名>.json」（启动链按 lastVersionId 找版本 JSON）。
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"name"] = versionId;
    profile[@"lastVersionId"] = self.gameVersion;
    // ★ Task322：game/ 分居层退役 —— versions/<id> 混居通例（Task242 口径五键）
    profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@", versionId];
    profile[@"type"] = @"custom";
    profile[@"created"] = [NSDate date].description;
    [PLProfiles.current saveProfile:profile withName:versionId];
    PLProfiles.current.selectedProfileName = versionId;

    __weak typeof(self) weakSelf = self;
    MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
    task.maxRetryCount = 3;
    task.handleError = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            [s ame_vanillaInstallDidFinish:NO];
        });
    };
    self.activeTask = task;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task downloadVersion:@{@"id": self.gameVersion ?: @""}];

        // 完成判定：轮询 progress.finished（30 分钟封顶，ZL2GameDownloadVC 同款）
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
        BOOL succeeded = NO;
        while ([deadline timeIntervalSinceNow] > 0) {
            NSProgress *progress = task.progress;
            if (progress && progress.finished) {
                succeeded = !progress.cancelled;
                break;
            }
            [NSThread sleepForTimeInterval:0.5];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s2 = weakSelf;
            [s2 ame_vanillaInstallDidFinish:succeeded];
        });
    });
}

- (void)ame_vanillaInstallDidFinish:(BOOL)success {
    self.activeTask = nil;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"ReloadProfileList" object:nil];
    if (success) {
        // Task324：原版安装成功即时补齐隔离骨架（上方 profile 已写 gameDir=versions/<id>）
        [ModService ame324_ensureIsolationSkeletonsAll];
        [ZL2M3Dialog showTitle:@"安装完成"
                          body:self.gameVersion
                  confirmTitle:@"知道了"
                    destructive:NO
                     onConfirm:nil onCancel:nil];
    } else {
        [ZL2M3Dialog showTitle:@"安装失败"
                          body:@"下载中断或网络异常，可重试安装。"
                  confirmTitle:@"知道了"
                    destructive:NO
                     onConfirm:nil onCancel:nil];
    }
}

#pragma mark - OptiFine 补丁安装（legacy installOptiFineAsPatch 1:1）

- (void)ame_installOptiFinePatch {
    // pendingOptiFineAfterForge = "type\x1fpatch\x1ffilename"（BMCLAPI 清单载荷）
    NSString *packed = self.pendingOptiFineAfterForge;
    NSString *gameVersion = self.pendingOptiFineGameVersion ?: self.gameVersion;
    if (packed.length == 0) {
        // 非组合路径：从当前 OptiFine 选择重新拼载荷
        packed = self.optifineCard.selectedItem;
        if (packed.length == 0) return;
    }
    NSArray *parts = [packed componentsSeparatedByString:@"\x1f"];
    if (parts.count < 2) {
        [ZL2M3Dialog showTitle:@"OptiFine 载荷异常"
                          body:@"请刷新 OptiFine 清单后重试。"
                  confirmTitle:@"知道了"
                    destructive:NO
                     onConfirm:nil onCancel:nil];
        return;
    }
    NSString *optiType = parts[0];
    NSString *optiPatch = parts[1];
    NSString *filename = (parts.count >= 3) ? parts[2] : @"";
    NSString *versionId = [NSString stringWithFormat:@"%@-OptiFine_%@_%@", gameVersion, optiType, optiPatch];

    static const NSUInteger kStageInstaller = 0;
    static const NSUInteger kStageResolve = 1;
    static const NSUInteger kStageInstall = 2;

    NSString *taskName = [NSString stringWithFormat:@"optifine-%@-%@-%@", gameVersion, optiType, optiPatch];
    NSString *source = [PLMirrorCenter legacySourceTokenForType:PLMirrorResourceTypeModLoader];
    DownloadTaskItem *item = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeModloader
                        resourceName:taskName
                         displayName:[NSString stringWithFormat:@"OptiFine %@_%@ (%@)", optiType, optiPatch, gameVersion]
                      downloadSource:source
                             rawTask:nil
                      supportsResume:NO
                             iconURL:nil];
    if (!item) return;
    NSString *taskId = item.taskId;
    [[DownloadTaskManager sharedManager] setTaskWithId:taskId stages:PLTaskStagesForgeExtra()];
    item.autoPresentDetail = YES;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstaller status:PLTaskStageStatusRunning];
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId currentStageIndex:kStageInstaller];

    __weak typeof(self) weakSelf = self;
    NSString *currentVersionId = versionId;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. 下载 OptiFine jar（BMCLAPI 优先 + 官方兜底；浏览器 UA 判例）
        NSString *bmclURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/optifine/%@/%@/%@", gameVersion, optiType, optiPatch];
        NSData *jarData = [self ame_syncFetch:bmclURL];
        if (!jarData && filename.length > 0) {
            jarData = [self ame_syncFetch:
                [NSString stringWithFormat:@"https://optifine.net/downloadx?f=%@", filename]];
        }
        if (!jarData) {
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstaller status:PLTaskStageStatusFailed];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:
                [NSError errorWithDomain:@"OptiFineInstall" code:1 userInfo:@{NSLocalizedDescriptionKey: @"下载失败"}]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [ZL2M3Dialog showTitle:@"安装失败" body:@"OptiFine 下载失败，请检查网络后重试。"
                          confirmTitle:@"知道了" destructive:NO onConfirm:nil onCancel:nil];
            });
            return;
        }

        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstaller status:PLTaskStageStatusCompleted];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageResolve status:PLTaskStageStatusSkipped];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusRunning];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId currentStageIndex:kStageInstall];

        // 2. 版本目录
        const char *env = getenv("POJAV_GAME_DIR");
        NSString *gameDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
        NSString *versionDir = [gameDir stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"versions/%@", currentVersionId]];
        [[NSFileManager defaultManager] createDirectoryAtPath:versionDir
                                  withIntermediateDirectories:YES attributes:nil error:nil];

        // 3. jar 入 libraries（launchwrapper tweaker 语义，legacy 同款）
        NSString *optifineJarPath = [NSString stringWithFormat:@"optifine/OptiFine/%@/%@.jar", gameVersion, currentVersionId];
        NSString *optifineJarAbsPath = [NSString stringWithFormat:@"%s/libraries/%@", getenv("POJAV_GAME_DIR"), optifineJarPath];
        [[NSFileManager defaultManager] createDirectoryAtPath:
            [optifineJarAbsPath stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:nil];
        [jarData writeToFile:optifineJarAbsPath options:NSDataWritingAtomic error:nil];

        // 4. version.json（launchwrapper + OptiFineTweaker）
        NSDictionary *versionJson = @{
            @"id": currentVersionId,
            @"inheritsFrom": gameVersion,
            @"type": @"release",
            @"mainClass": @"net.minecraft.launchwrapper.Launcher",
            @"minecraftArguments": @"--username ${auth_player_name} --version ${version_name} --gameDir ${game_directory} --assetsDir ${assets_root} --assetIndex ${assets_index_name} --uuid ${auth_uuid} --accessToken ${auth_access_token} --userType ${user_type} --versionType ${version_type} --tweakClass optifine.OptiFineTweaker",
            @"libraries": @[@{
                @"name": [NSString stringWithFormat:@"optifine:OptiFine:%@", gameVersion],
                @"downloads": @{@"artifact": @{
                    @"path": optifineJarPath,
                    @"url": @"",
                    @"size": @(jarData.length),
                    @"sha1": @""
                }}
            }],
            @"jar": gameVersion,
            @"minimumLauncherVersion": @21
        };
        NSString *jsonPath = [versionDir stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"%@.json", currentVersionId]];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:versionJson
                                                           options:NSJSONWritingPrettyPrinted error:nil];
        [jsonData writeToFile:jsonPath options:NSDataWritingAtomic error:nil];

        // 4.1 父版本 JSON 存在性检查（legacy 同款）
        NSString *parentJsonPath = [gameDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"versions/%@/%@.json", gameVersion, gameVersion]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:parentJsonPath]) {
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusFailed];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:
                [NSError errorWithDomain:@"OptiFineInstall" code:3 userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"父版本 %@ 不存在，请先安装原版。", gameVersion]}]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [ZL2M3Dialog showTitle:@"安装失败"
                                  body:[NSString stringWithFormat:@"父版本 %@ 不存在，请先安装原版。", gameVersion]
                          confirmTitle:@"知道了" destructive:NO
                           onConfirm:nil onCancel:nil];
            });
            return;
        }

        // 5. 注册 profile
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *profile = [NSMutableDictionary dictionary];
            profile[@"name"] = currentVersionId;
            profile[@"lastVersionId"] = currentVersionId;
            profile[@"gameDir"] = @".";
            profile[@"type"] = @"custom";
            profile[@"created"] = [NSDate date].description;
            [PLProfiles.current saveProfile:profile withName:currentVersionId];
            PLProfiles.current.selectedProfileName = currentVersionId;

            [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusCompleted];
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskId stageAtIndex:kStageInstall progress:1 message:nil];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:nil];
            __strong typeof(weakSelf) s = weakSelf;
            s.pendingOptiFineAfterForge = nil;
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"ReloadProfileList" object:nil];
            [ZL2M3Dialog showTitle:@"安装完成"
                              body:currentVersionId
                      confirmTitle:@"知道了"
                        destructive:NO
                         onConfirm:nil onCancel:nil];
        });
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

#pragma mark - ZL2AddonCard 实现

@interface ZL2AddonCard () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIControl *clearButton;
@property (nonatomic, strong) UIControl *reloadButton;
@property (nonatomic, strong) UILabel *chevronLabel;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) UITableView *listView;
@property (nonatomic, strong) NSLayoutConstraint *listHeight;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *failedLabel;
@end

@implementation ZL2AddonCard

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                    iconBundleName:(NSString *)iconBundleName
                   fallbackSymbol:(NSString *)fallbackSymbol {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _identifier = [identifier copy];
        _title = [title copy];
        _iconBundleName = [iconBundleName copy];
        _fallbackSymbol = [fallbackSymbol copy];
        _expanded = NO;
        [self ame_buildViews];
    }
    return self;
}

- (void)ame_buildViews {
    _cardView = [[UIView alloc] init];
    _cardView.backgroundColor = [ZL2Theme surfaceContainer];
    _cardView.layer.cornerRadius = [ZL2Theme radiusM];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_cardView];

    // 品牌图标（ModLoaderIcons bundle）→ SF 兜底 → 首字母档
    UIImage *brandImage = nil;
    if (self.iconBundleName.length > 0) {
        NSString *iconsPath = [[NSBundle mainBundle].resourcePath
            stringByAppendingPathComponent:@"ModLoaderIcons"];
        NSString *iconPath = [iconsPath stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"%@.png", self.iconBundleName]];
        brandImage = [UIImage imageWithContentsOfFile:iconPath];
    }
    if (!brandImage) {
        brandImage = [UIImage systemImageNamed:self.fallbackSymbol];
    }
    _iconView = [[UIImageView alloc] initWithImage:brandImage];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [ZL2Theme onSurface];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = self.title;
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_titleLabel];

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [ZL2Theme fontBodyMedium];
    _valueLabel.textColor = [ZL2Theme onSurfaceVariant];
    _valueLabel.numberOfLines = 1;
    _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_valueLabel];

    _clearButton = [[UIControl alloc] init];
    _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    _clearButton.isAccessibilityElement = YES;
    _clearButton.accessibilityLabel = [NSString stringWithFormat:@"清除%@选择", self.title];
    [_clearButton addTarget:self
                     action:@selector(ame_clearTapped)
           forControlEvents:UIControlEventTouchUpInside];
    UIImageView *clearIcon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"xmark.circle"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    clearIcon.tintColor = [ZL2Theme onSurfaceVariant];
    clearIcon.contentMode = UIViewContentModeScaleAspectFit;
    clearIcon.translatesAutoresizingMaskIntoConstraints = NO;
    clearIcon.userInteractionEnabled = NO;
    [_clearButton addSubview:clearIcon];
    [_cardView addSubview:_clearButton];

    _reloadButton = [[UIControl alloc] init];
    _reloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    _reloadButton.isAccessibilityElement = YES;
    _reloadButton.accessibilityLabel = [NSString stringWithFormat:@"刷新%@清单", self.title];
    [_reloadButton addTarget:self
                      action:@selector(ame_reloadTapped)
            forControlEvents:UIControlEventTouchUpInside];
    UIImageView *reloadIcon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"arrow.clockwise"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    reloadIcon.tintColor = [ZL2Theme onSurfaceVariant];
    reloadIcon.contentMode = UIViewContentModeScaleAspectFit;
    reloadIcon.translatesAutoresizingMaskIntoConstraints = NO;
    reloadIcon.userInteractionEnabled = NO;
    [_reloadButton addSubview:reloadIcon];
    [_cardView addSubview:_reloadButton];

    _chevronLabel = [[UILabel alloc] init];
    _chevronLabel.text = @"▼";
    _chevronLabel.font = [UIFont systemFontOfSize:10];
    _chevronLabel.textColor = [ZL2Theme onSurfaceVariant];
    _chevronLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronLabel.userInteractionEnabled = NO;
    [_cardView addSubview:_chevronLabel];

    // 点头部整行 = 展开/收起
    UIControl *headerTap = [[UIControl alloc] init];
    headerTap.translatesAutoresizingMaskIntoConstraints = NO;
    [headerTap addTarget:self
                  action:@selector(ame_headerTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [_cardView addSubview:headerTap];

    _divider = [[UIView alloc] init];
    _divider.backgroundColor = [ZL2Theme outlineVariant];
    _divider.translatesAutoresizingMaskIntoConstraints = NO;
    _divider.hidden = YES;
    [_cardView addSubview:_divider];

    _listView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _listView.backgroundColor = [UIColor clearColor];
    _listView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _listView.rowHeight = 40.0;
    _listView.delegate = self;
    _listView.dataSource = self;
    // Task325：清单拉取成功也渲染 0 行的隐形雷修复面（reloadData 补齐）之外，
    // 长清单（Fabric loader 100+ 行）在 260pt 钳高内可滚动（scrollEnabled=YES）
    _listView.scrollEnabled = YES;
    _listView.translatesAutoresizingMaskIntoConstraints = NO;
    _listView.hidden = YES;
    [_listView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ZL2AddonItem"];
    [_cardView addSubview:_listView];

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [ZL2Theme onSurfaceVariant];
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_spinner];

    _failedLabel = [[UILabel alloc] init];
    _failedLabel.text = @"清单加载失败，点刷新重试";
    _failedLabel.font = [ZL2Theme fontBodyMedium];
    _failedLabel.textColor = [ZL2Theme error];
    _failedLabel.numberOfLines = 1;
    _failedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _failedLabel.hidden = YES;
    [_cardView addSubview:_failedLabel];

    _listHeight = [_listView.heightAnchor constraintEqualToConstant:0];
    _listHeight.active = YES;

    UILayoutGuide *cardLG = _cardView.layoutMarginsGuide;
    _cardView.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 12);
    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_iconView.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_cardView.topAnchor constant:28],
        [_iconView.widthAnchor constraintEqualToConstant:24],
        [_iconView.heightAnchor constraintEqualToConstant:24],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],

        [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
        [_valueLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],

        [_clearButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_valueLabel.trailingAnchor constant:8],
        [_clearButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_clearButton.widthAnchor constraintEqualToConstant:28],
        [_clearButton.heightAnchor constraintEqualToConstant:28],
        [clearIcon.centerXAnchor constraintEqualToAnchor:_clearButton.centerXAnchor],
        [clearIcon.centerYAnchor constraintEqualToAnchor:_clearButton.centerYAnchor],
        [clearIcon.widthAnchor constraintEqualToConstant:18],
        [clearIcon.heightAnchor constraintEqualToConstant:18],

        [_reloadButton.leadingAnchor constraintEqualToAnchor:_clearButton.trailingAnchor constant:2],
        [_reloadButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_reloadButton.widthAnchor constraintEqualToConstant:28],
        [_reloadButton.heightAnchor constraintEqualToConstant:28],
        [reloadIcon.centerXAnchor constraintEqualToAnchor:_reloadButton.centerXAnchor],
        [reloadIcon.centerYAnchor constraintEqualToAnchor:_reloadButton.centerYAnchor],
        [reloadIcon.widthAnchor constraintEqualToConstant:16],
        [reloadIcon.heightAnchor constraintEqualToConstant:16],

        [_chevronLabel.leadingAnchor constraintEqualToAnchor:_reloadButton.trailingAnchor constant:2],
        [_chevronLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_chevronLabel.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],

        [headerTap.topAnchor constraintEqualToAnchor:_cardView.topAnchor],
        [headerTap.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
        [headerTap.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
        [headerTap.heightAnchor constraintEqualToConstant:56],

        [_divider.topAnchor constraintEqualToAnchor:headerTap.bottomAnchor],
        [_divider.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
        [_divider.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
        [_divider.heightAnchor constraintEqualToConstant:0.5],

        [_listView.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:2],
        [_listView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
        [_listView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
        [_listView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-4],

        [_spinner.centerXAnchor constraintEqualToAnchor:_cardView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_listView.centerYAnchor],

        [_failedLabel.centerXAnchor constraintEqualToAnchor:_cardView.centerXAnchor],
        [_failedLabel.centerYAnchor constraintEqualToAnchor:_listView.centerYAnchor],
    ]];
}

- (void)ame_refreshAppearance {
    _valueLabel.text = self.selectedItem.length > 0 ? self.selectedItem : @"未选择";

    BOOL hasItems = self.items.count > 0;
    _clearButton.hidden = (self.selectedItem.length == 0);
    _reloadButton.hidden = self.loading;
    _chevronLabel.hidden = self.loading || self.listFailed;
    _chevronLabel.text = self.expanded ? @"▲" : @"▼";

    _divider.hidden = !self.expanded;
    _listView.hidden = !self.expanded;
    // Task325：加载/失败态给列表区最小高度 48 —— spinner 与失败文案均锚在
    // listView.centerY，历史版 0 高列表时两者都不可见（“什么都不显示”观感
    // 死角之二）；items 到达后恢复数据高度。失败文案常驻可点（见 headerTapped）。
    CGFloat ame325_min = (self.loading || self.listFailed) ? 48.0 : 0.0;
    CGFloat ame325_data = MIN((CGFloat)(MAX(self.items.count, 1)) * 40.0 + 8.0, 260.0);
    _listHeight.constant = self.expanded ? MAX(ame325_min, ame325_data) : 0.0;

    if (self.loading) {
        [_spinner startAnimating];
        _failedLabel.hidden = YES;
    } else {
        [_spinner stopAnimating];
        _failedLabel.hidden = !self.listFailed;
    }
    // ★ Task325 核心雷：items 到达后从不 reloadData —— UITableView 首次 layout
    //   时 items 还是 nil 已缓存 0 行，后续展开/拉取成功都不触发行数重查，
    //   清单拉取成功也渲染 0 行（IMG_0486 “Fabric 展开为空”直接根因）。
    //   全文件原唯一 reloadData 在 didSelectRow（选中回写场景），补齐此处。
    [self.listView reloadData];
    [UIView animateWithDuration:0.18 animations:^{
        [self layoutIfNeeded];
    }];
}

- (void)ame_headerTapped {
    if (self.loading) return;
    // Task325：失败态点卡头 = 重新拉取（历史版 no-op，恢复仅靠 28x28 刷新小钮
    // —— “什么都不显示”观感死角之三）；有数据时维持展开/收起切换。
    if (self.listFailed || self.items.count == 0) {
        self.expanded = YES;
        [self ame_reloadTapped];
        return;
    }
    self.expanded = !self.expanded;
    [self ame_refreshAppearance];
}

- (void)ame_clearTapped {
    self.selectedItem = nil;
    self.expanded = NO;
    [self ame_refreshAppearance];
    if ([self.delegate respondsToSelector:@selector(addonCardDidChangeSelection:)]) {
        [self.delegate addonCardDidChangeSelection:self];
    }
}

- (void)ame_reloadTapped {
    if ([self.delegate respondsToSelector:@selector(addonCardDidRequestReload:)]) {
        [self.delegate addonCardDidRequestReload:self];
    }
}

#pragma mark - 版本单选列表

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(self.items.count > 0 ? self.items.count : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2AddonItem"
                                                           forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *item = self.items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item;
    cell.textLabel.font = [ZL2Theme fontBodyMedium];
    cell.textLabel.textColor = [item isEqualToString:self.selectedItem]
        ? [ZL2Theme primary] : [ZL2Theme onSurface];
    // 选中态右侧对勾（M3 单选语义）
    cell.accessoryView = ([item isEqualToString:self.selectedItem])
        ? [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"checkmark"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]
        : nil;
    cell.accessoryView.tintColor = [ZL2Theme primary];
    // OptiFine 载荷显示友好名（type\x1fpatch\x1ffilename → OptiFine HD_U H1）
    if ([self.identifier isEqualToString:@"optifine"]) {
        NSArray *parts = [item componentsSeparatedByString:@"\x1f"];
        if (parts.count >= 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"OptiFine %@ %@", parts[0], parts[1]];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *item = self.items[(NSUInteger)indexPath.row];
    BOOL changed = ![item isEqualToString:self.selectedItem];
    self.selectedItem = changed ? item : nil;   // 再点已选项 = 清除（M3 语义）
    self.expanded = NO;
    [self ame_refreshAppearance];
    [tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(addonCardDidChangeSelection:)]) {
        [self.delegate addonCardDidChangeSelection:self];
    }
}

@end
