//
// ZL2AccountsViewController.m — ZL2 风格账户页实现（7.0-UI-9-c：对标 ZL2 AccountManageScreen）
//
// 布局（竖向滚动单列，内容最大宽 520pt，单侧边距 20，垂直间距 12）：
//   ① 账户视觉卡（surfaceContainerLow / radiusL，居中竖排：头像 64pt 圆形
//      （AvatarManager 取当前账号头像，无账号 person.crop.circle.fill）+
//      用户名 fontTitleMedium onSurface（无账号「未登录」，同主页口径）+
//      账号类型 fontBodyMedium onSurfaceVariant）
//   ② 「添加账户」大按钮（44 高，primary 底 onPrimary 前景 fontLabelLarge
//      radiusS）→ actionSheet 列出旧 AccountListViewController 实际支持的
//      四种登录方式，逐项进入对应流程（见 .h 头注释）
//   ③ 账号列表（★ Task393：iPod 式竖排封面流——用户规格 2026-11-03「把所有
//      账户排成一列，拖到哪里就选中哪里，选中的是正常大小（不要加什么
//      边框箭头什么乱七八糟的样式），未选中的越远越透明、变小，可以同时
//      显示五个」：AmeIpodFlowView 承载，条目 = 头像 40 + 用户名/类型横排卡
//      （surfaceContainer / radiusL，全条目同款零选中装饰）；原行视图
//      （单选圈/刷新钮/更多钮）退役，刷新/更多动作上收列表下方动作行）
//   空态卡：person.crop.circle 68pt onSurfaceVariant + 「未找到可用账号」
//
// 行为移植（1:1 旧 AccountListViewController）：
//   - 数据源扫描：POJAV_HOME/accounts/*.json，parseJSONFromFile 读取，
//     Task180 双保险（accountId 缺省退文件名去重 + NSErrorObject 坏文件过滤）
//   - 类型文案：Demo. 前缀 → 演示；accountType 显式优先（thirdparty/本地/
//     其余 Microsoft），旧文件回退 clientToken/xboxGamertag 嗅探（Task220 口径）
//   - 选中链：第三方 = loadSavedName + 会话校验（Task128 static set，避免
//     每次选择都打 refresh）→ 直选 / refreshTokenWithCallback → 成功选中 /
//     失败优雅降级（仍选中 + 过期 toast）；微软/本地 = loadSavedName +
//     refreshTokenWithCallback → callbackMicrosoftAuth 语义（成功 toast +
//     DEMO 警告弹窗，失败错误弹窗带 AFNetworking 响应体）
//   - 刷新钮：refreshTokenWithCallback 显式刷新；离线账号禁用（ZL2
//     AccountElements L350 `accountType != LOCAL` 规则 × 本仓类型判定口径）
//   - 删除链：xuid → MSA token 清理 → 删 accounts/<accountId>.json → 删的
//     是当前账号则清 selected_account + setCurrent:nil（Task190 收口语义；
//     ZL2 AccountOperation.Delete 同款先弹确认框）
//   - 更多菜单：只移植旧 VC 真实存在的操作（删除账号）；ZL2 的复制 UUID/
//     衣橱旧 VC 不存在，换肤/改名/角色切换属 Task224 高级项，留待后续轮次
//
// 通知契约：监听 @"UpdateAccountInfo"（主页同款名字）自动重建；登录成功/
//   选中成功/刷新成功/删除后发出 @"UpdateAccountInfo"（旧容器把
//   whenItemSelected/whenDelete 桥到该通知的等价契约，主页
//   pendingLaunchAfterLogin 据此自动续启动）。
//
// 红线遵守：iOS 14.0+（无 button.configuration/UIMenu/iOS15+ API；SF 符号全
//   为 SF1.0 级并带旧名 fallback）；颜色/字体/圆角一律取 ZL2Theme 动态令牌
//   （无 traitCollection 分支）；全部新建视图 translatesAutoresizingMaskIntoConstraints
//   = NO；视图身份直接属性/行对象持有（无 viewWithTag 状态存取）；alert 一律
//   present 到本 VC；宽度方案与 ZL2HomeViewController 同款 999 等式。
//

#import "ZL2AccountsViewController.h"
#import "ZL2Theme.h"
#import "authenticator/BaseAuthenticator.h"
#import "authenticator/ThirdPartyAuthenticator.h"
#import "AvatarManager.h"
#import "ThirdPartyLoginViewController.h"
#import "NMToast.h"
#import "LauncherPreferences.h"   // getPrefObject/setPrefObject/getPrefBool/setPrefBool
// AFNetworking 错误响应体键：仅消费一个 extern 常量（旧错误弹窗响应体 1:1），
// 不需要引入 AFNetworking.h 全量类声明（submodule 在 ui-smoke 检出中缺席，
// 引头链会让账户页/门禁无谓依赖 shim；定义由真实构建的 libAFNetworking 提供）
extern NSString * const AFNetworkingOperationFailingURLResponseDataErrorKey;
#import "utils.h"                 // localize() / parseJSONFromFile()
#import "AmeIpodFlowView.h"        // ★ Task393：iPod 式竖排封面流（账户列表改版）

#import <AuthenticationServices/AuthenticationServices.h>

// 内容列最大宽（与主页同款：iPad 横屏居中；iPhone 占满减边距）
static const CGFloat ZL2AccountsContentMaxWidth = 520;

// Task128 移植：本会话已通过服务端校验的第三方账户（loadKey 集合；
// zl2 isSessionValidated 同款语义，避免每次选择都打 refresh）
static NSMutableSet *ZL2AccountsValidatedSet(void) {
    static NSMutableSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}

// Task220 移植：第三方判别统一口径（accountType 显式优先，旧文件回退
// clientToken 嗅探）——类型文案 / 选中链 / 刷新禁用三处同源
static BOOL ZL2AccountsIsThirdParty(NSDictionary *accountData) {
    if (![accountData isKindOfClass:NSDictionary.class]) return NO;
    NSString *type = accountData[@"accountType"];
    if ([type isKindOfClass:NSString.class] && type.length > 0) {
        return [type isEqualToString:@"thirdparty"];
    }
    return (accountData[@"clientToken"] != nil);
}

// SF Symbols 取图兜底（本页符号全为 SF1.0 级，正常路径不会走 fallback；
// 保留兜底是历史判例纪律：符号名异常时降级到旧名而不是空白）
static UIImage *ZL2AccountsSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - Ame393FlowItem（★ Task393 封面流条目：头像 + 名字/类型横排卡）

// 用户规格（2026-11-03 bold plan ①）：选中的是正常大小，不加边框/箭头等
// 任何装饰——条目全部同款（surfaceContainer 卡 + radiusL），选中与未选中
// 零着色差异，仅由封面流的远近缩放/透明度区分。头像 40 + 名字/类型中列；
// 刷新/更多动作不再驻条目（小按钮与封面流连续缩放/透明动画冲突），由
// 列表下方动作行对居中（选中）账户统一承担（见 buildListArea）。
@interface Ame393FlowItem : UIView

@property (nonatomic, strong) UIImageView *avatarView;   // 头像 40 圆（异步取图落点）
@property (nonatomic, strong) UILabel *nameLabel;          // 用户名 fontLabelLarge
@property (nonatomic, strong) UILabel *typeLabel;           // 账号类型 fontBodyMedium

@end

@implementation Ame393FlowItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [ZL2Theme surfaceContainer];
        self.layer.cornerRadius = [ZL2Theme radiusL];
        self.layer.masksToBounds = YES;
        self.isAccessibilityElement = NO;   // 条目由封面流统一可达（adjustable）

        // —— 头像 40 圆（AvatarManager 异步取图，占位 person.crop.circle.fill）——
        UIImage *avatarPlaceholder = [ZL2AccountsSystemImage(@"person.crop.circle.fill", @"person.circle.fill")
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _avatarView = [[UIImageView alloc] initWithImage:avatarPlaceholder];
        _avatarView.tintColor = [ZL2Theme onSurfaceVariant];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.layer.cornerRadius = 20;   // 40 / 2
        _avatarView.layer.masksToBounds = YES;
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarView.userInteractionEnabled = NO;
        [self addSubview:_avatarView];

        // —— 中列：用户名 + 账号类型（原行视图同款字体/色令牌）——
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [ZL2Theme fontLabelLarge];
        _nameLabel.textColor = [ZL2Theme onSurface];
        _nameLabel.numberOfLines = 1;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _typeLabel = [[UILabel alloc] init];
        _typeLabel.font = [ZL2Theme fontBodyMedium];
        _typeLabel.textColor = [ZL2Theme onSurfaceVariant];
        _typeLabel.numberOfLines = 1;
        _typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _typeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *textStack = [[UIStackView alloc] init];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.alignment = UIStackViewAlignmentLeading;
        textStack.spacing = 2;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [textStack addArrangedSubview:_nameLabel];
        [textStack addArrangedSubview:_typeLabel];
        [self addSubview:textStack];

        // 条目高 58 由封面流统一钉（viewportHeight 口径）；内部为左右布局
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:40],
            [_avatarView.heightAnchor constraintEqualToConstant:40],
            [textStack.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        ]];
    }
    return self;
}

@end

#pragma mark - ZL2AccountsViewController

@interface ZL2AccountsViewController () <ASWebAuthenticationPresentationContextProviding>

// 布局
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;   // 竖排 spacing 12

// ① 账户视觉卡
@property (nonatomic, strong) UIView *identityCard;
@property (nonatomic, strong) UIStackView *identityStack;
@property (nonatomic, strong) UIImageView *identityAvatarView;
@property (nonatomic, strong) UILabel *identityNameLabel;
@property (nonatomic, strong) UILabel *identityTypeLabel;

// ② 添加账号大按钮
@property (nonatomic, strong) UIControl *addAccountButton;

// ③ 账号列表（★ Task393：iPod 式竖排封面流 + 居中账户动作行）+ 空态
@property (nonatomic, strong) AmeIpodFlowView *ame393_flowView;
@property (nonatomic, strong) UIView *ame393_actionsRow;              // 动作行容器（刷新/更多）
@property (nonatomic, strong) UIButton *ame393_refreshButton;          // 刷新钮 40×40（离线账号禁用）
@property (nonatomic, strong) UIButton *ame393_moreButton;             // 更多钮 40×40（删除菜单）
@property (nonatomic, strong) UIActivityIndicatorView *ame393_spinner; // 忙态占刷新钮槽位
@property (nonatomic, strong) UIView *emptyCard;
@property (nonatomic, strong) UIImageView *emptyIconView;
@property (nonatomic, strong) UILabel *emptyLabel;

// 数据源（每项 = accounts/<id>.json 的解析结果；行视图按数组下标索引）
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *accountList;

// 登录流程
@property (nonatomic, strong) ASWebAuthenticationSession *authSession;
// 第三方登录页呈现方式（push = pop 收尾；兜底 present = dismiss 收尾）
@property (nonatomic, assign) BOOL loginFlowPushed;

@end

@implementation ZL2AccountsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    self.accountList = [NSMutableArray array];

    [self buildViews];
    [self reloadAccounts];

    // 通知监听：账号信息变化（登录/删除/换肤等）→ 重建列表；dealloc 统一移除
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_accountsDidChange:)
                                                 name:@"UpdateAccountInfo"
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 根页隐藏系统导航栏（push 登录页时有返回栏，由 viewWillDisappear 恢复）
    if (self.navigationController) {
        [self.navigationController setNavigationBarHidden:YES animated:NO];
    }
    // pop 返回本页时重扫账号目录——添加账户流程（登录成功 pop 回来）后
    // 新账号立即可见（旧链 Task162 同款触发口）
    [self reloadAccounts];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)ame_accountsDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadAccounts];
    });
}

// 旧容器契约：AccountListViewController 的 whenItemSelected/whenDelete 由
// 容器桥接为 @"UpdateAccountInfo"（LauncherCardLayout/Root 同款）——本页
// 直接发出，主页 pendingLaunchAfterLogin 据此自动续启动
- (void)ame_postAccountInfoChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo"
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - Layout

- (void)buildViews {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.backgroundColor = [ZL2Theme surface];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.spacing = 12;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];

    [self buildIdentityCard];
    [self buildAddButton];
    [self buildListArea];

    UILayoutGuide *contentLG = _scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = _scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:16],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.bottomAnchor constant:24],
        // 两侧 inequality 边距：窄屏时被 999 宽度等式推到贴边（=20），宽屏时
        // 与 centerX/<=520 联立自动让位（列居中，不越界）——主页同款
        [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.trailingAnchor constant:20],
        [_contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        // 最大宽 520（spec：widthAnchor <= constant）
        [_contentStack.widthAnchor constraintLessThanOrEqualToConstant:ZL2AccountsContentMaxWidth],
        // 内容不钻状态栏/刘海底下（主页为无 nav 全屏宿主，此条保证观感）
        [_contentStack.topAnchor constraintGreaterThanOrEqualToAnchor:_scrollView.safeAreaLayoutGuide.topAnchor],
    ]];
    // 宽度正定（优先级 999）：窄屏占满可用宽（frame-40）；与 <=520 上限联立
    // 后宽屏（iPad 横屏）由求解器收敛到 520（999 误差最小解），centerX 居中
    NSLayoutConstraint *fillWidth = [_contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor
                                                                              constant:-40];
    fillWidth.priority = 999;
    fillWidth.active = YES;
}

// ① 账户视觉卡：surfaceContainerLow / radiusL，居中竖排（头像 64 + 名字 +
//    类型）；无账号时头像 person.crop.circle.fill、名字「未登录」、类型隐藏
- (void)buildIdentityCard {
    _identityCard = [[UIView alloc] init];
    _identityCard.backgroundColor = [ZL2Theme surfaceContainerLow];
    _identityCard.layer.cornerRadius = [ZL2Theme radiusL];
    _identityCard.translatesAutoresizingMaskIntoConstraints = NO;
    _identityCard.isAccessibilityElement = YES;

    _identityAvatarView = [[UIImageView alloc] init];
    _identityAvatarView.contentMode = UIViewContentModeScaleAspectFit;
    _identityAvatarView.layer.cornerRadius = 32;   // 64 / 2
    _identityAvatarView.layer.masksToBounds = YES;
    _identityAvatarView.translatesAutoresizingMaskIntoConstraints = NO;

    _identityNameLabel = [[UILabel alloc] init];
    _identityNameLabel.font = [ZL2Theme fontTitleMedium];
    _identityNameLabel.textColor = [ZL2Theme onSurface];
    _identityNameLabel.numberOfLines = 1;
    _identityNameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _identityTypeLabel = [[UILabel alloc] init];
    _identityTypeLabel.font = [ZL2Theme fontBodyMedium];
    _identityTypeLabel.textColor = [ZL2Theme onSurfaceVariant];
    _identityTypeLabel.numberOfLines = 1;
    _identityTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _identityStack = [[UIStackView alloc] init];
    _identityStack.axis = UILayoutConstraintAxisVertical;
    _identityStack.alignment = UIStackViewAlignmentCenter;
    _identityStack.spacing = 12;
    _identityStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_identityStack addArrangedSubview:_identityAvatarView];
    [_identityStack addArrangedSubview:_identityNameLabel];
    [_identityStack addArrangedSubview:_identityTypeLabel];
    // 名字与类型之间的次级间距（头像/名字之间保持 12）
    [_identityStack setCustomSpacing:2 afterView:_identityNameLabel];

    [_identityCard addSubview:_identityStack];
    [_contentStack addArrangedSubview:_identityCard];
    [NSLayoutConstraint activateConstraints:@[
        [_identityStack.topAnchor constraintEqualToAnchor:_identityCard.topAnchor constant:20],
        [_identityCard.bottomAnchor constraintEqualToAnchor:_identityStack.bottomAnchor constant:20],
        [_identityStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_identityCard.leadingAnchor constant:16],
        [_identityCard.trailingAnchor constraintGreaterThanOrEqualToAnchor:_identityStack.trailingAnchor constant:16],
        [_identityStack.centerXAnchor constraintEqualToAnchor:_identityCard.centerXAnchor],

        [_identityAvatarView.widthAnchor constraintEqualToConstant:64],
        [_identityAvatarView.heightAnchor constraintEqualToConstant:64],
    ]];
}

// ② 「添加账户」大按钮：44 高 filled 样式（primary 底 onPrimary 前景
//    fontLabelLarge radiusS）→ actionSheet 列出全部登录方式
- (void)buildAddButton {
    _addAccountButton = [[UIControl alloc] init];
    _addAccountButton.backgroundColor = [ZL2Theme primary];
    _addAccountButton.layer.cornerRadius = [ZL2Theme radiusS];
    _addAccountButton.translatesAutoresizingMaskIntoConstraints = NO;
    _addAccountButton.isAccessibilityElement = YES;
    _addAccountButton.accessibilityTraits = UIAccessibilityTraitButton;
    _addAccountButton.accessibilityLabel = localize(@"ame369.acct.add_account_a11y", @"添加账户");

    UILabel *label = [[UILabel alloc] init];
    label.text = localize(@"login.option.add", @"添加账户");
    label.font = [ZL2Theme fontLabelLarge];
    label.textColor = [ZL2Theme onPrimary];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.userInteractionEnabled = NO;
    [_addAccountButton addSubview:label];

    [_addAccountButton addTarget:self
                          action:@selector(showAddAccountSheet)
                forControlEvents:UIControlEventTouchUpInside];

    [_contentStack addArrangedSubview:_addAccountButton];
    [NSLayoutConstraint activateConstraints:@[
        [_addAccountButton.heightAnchor constraintEqualToConstant:44],
        [label.centerXAnchor constraintEqualToAnchor:_addAccountButton.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:_addAccountButton.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:_addAccountButton.leadingAnchor constant:16],
    ]];
}

// ③ 账号列表（★ Task393：iPod 式竖排封面流 + 居中账户动作行）+ 空态卡
//   用户规格：「把所有账户排成一列，拖到哪里就选中哪里，选中的是正常
//   大小（不要加什么边框箭头什么乱七八糟的样式），未选中的越远越透明、
//   变小，可以同时显示五个」——摆位/衰减/拖拽吸附见 AmeIpodFlowView；
//   动作行（刷新/更多）作用于居中（选中）账户，语义与原行内双钮同源。
- (void)buildListArea {
    __weak typeof(self) weakSelf = self;

    _ame393_flowView = [[AmeIpodFlowView alloc] init];
    _ame393_flowView.translatesAutoresizingMaskIntoConstraints = NO;
    _ame393_flowView.accessibilityLabel = localize(@"login.option.select", @"选择账户");
    // 拖到哪里就选中哪里：吸附落定且下标变化 → 走原选中链（原整行点击等价）
    _ame393_flowView.onSettle = ^(NSInteger ame393_index) {
        if (ame393_index >= 0) [weakSelf selectAccountAtIndex:(NSUInteger)ame393_index];
    };
    [_contentStack addArrangedSubview:_ame393_flowView];
    [NSLayoutConstraint activateConstraints:@[
        // 同时可见五枚所需视口高（条目 58 + 4 × 步距 68，见 AmeIpodFlowView）
        [_ame393_flowView.heightAnchor constraintEqualToConstant:_ame393_flowView.viewportHeight],
    ]];

    // —— 动作行：居中（选中）账户的刷新/更多（原行内双钮上收，40×40 触达面放宽）——
    _ame393_refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *ame393_refreshImage = ZL2AccountsSystemImage(@"arrow.clockwise", @"arrow.clockwise.circle");
    [_ame393_refreshButton setImage:ame393_refreshImage forState:UIControlStateNormal];
    _ame393_refreshButton.tintColor = [ZL2Theme primary];
    _ame393_refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    _ame393_refreshButton.accessibilityLabel = localize(@"ame369.acct.refresh_a11y", @"刷新账号");
    [_ame393_refreshButton addTarget:self
                              action:@selector(ame393_refreshCenteredAccount)
                    forControlEvents:UIControlEventTouchUpInside];

    _ame393_moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *ame393_moreImage = ZL2AccountsSystemImage(@"ellipsis", @"ellipsis.circle");
    [_ame393_moreButton setImage:ame393_moreImage forState:UIControlStateNormal];
    _ame393_moreButton.tintColor = [ZL2Theme onSurfaceVariant];
    _ame393_moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    _ame393_moreButton.accessibilityLabel = localize(@"ame369.common.more_actions", @"更多操作");
    [_ame393_moreButton addTarget:self
                           action:@selector(ame393_moreMenuForCenteredAccount)
                 forControlEvents:UIControlEventTouchUpInside];

    _ame393_actionsRow = [[UIView alloc] init];
    _ame393_actionsRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_ame393_actionsRow];

    UIStackView *ame393_buttonStack = [[UIStackView alloc] init];
    ame393_buttonStack.axis = UILayoutConstraintAxisHorizontal;
    ame393_buttonStack.alignment = UIStackViewAlignmentCenter;
    ame393_buttonStack.spacing = 36;
    ame393_buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [ame393_buttonStack addArrangedSubview:_ame393_refreshButton];
    [ame393_buttonStack addArrangedSubview:_ame393_moreButton];
    [_ame393_actionsRow addSubview:ame393_buttonStack];

    // 忙态指示器（选中/刷新链进行中占刷新钮槽位，原行内 spinner 语义上收）
    _ame393_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _ame393_spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _ame393_spinner.hidesWhenStopped = YES;
    _ame393_spinner.hidden = YES;
    [_ame393_actionsRow addSubview:_ame393_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [_ame393_refreshButton.widthAnchor constraintEqualToConstant:40],
        [_ame393_refreshButton.heightAnchor constraintEqualToConstant:40],
        [_ame393_moreButton.widthAnchor constraintEqualToConstant:40],
        [_ame393_moreButton.heightAnchor constraintEqualToConstant:40],
        [_ame393_spinner.centerXAnchor constraintEqualToAnchor:_ame393_refreshButton.centerXAnchor],
        [_ame393_spinner.centerYAnchor constraintEqualToAnchor:_ame393_refreshButton.centerYAnchor],
        [ame393_buttonStack.centerXAnchor constraintEqualToAnchor:_ame393_actionsRow.centerXAnchor],
        [ame393_buttonStack.centerYAnchor constraintEqualToAnchor:_ame393_actionsRow.centerYAnchor],
        [_ame393_actionsRow.heightAnchor constraintEqualToConstant:44],
    ]];

    _emptyCard = [[UIView alloc] init];
    _emptyCard.backgroundColor = [ZL2Theme surfaceContainer];
    _emptyCard.layer.cornerRadius = [ZL2Theme radiusL];
    _emptyCard.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *emptyImage = [UIImage systemImageNamed:@"person.crop.circle"];
    if (!emptyImage) emptyImage = [UIImage systemImageNamed:@"person.circle"];
    _emptyIconView = [[UIImageView alloc] initWithImage:emptyImage];
    _emptyIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _emptyIconView.contentMode = UIViewContentModeScaleAspectFit;
    _emptyIconView.translatesAutoresizingMaskIntoConstraints = NO;

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = localize(@"ame369.acct.empty", @"未找到可用账号");
    _emptyLabel.font = [ZL2Theme fontBodyMedium];
    _emptyLabel.textColor = [ZL2Theme onSurfaceVariant];
    _emptyLabel.numberOfLines = 1;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *emptyStack = [[UIStackView alloc] init];
    emptyStack.axis = UILayoutConstraintAxisVertical;
    emptyStack.alignment = UIStackViewAlignmentCenter;
    emptyStack.spacing = 12;
    emptyStack.translatesAutoresizingMaskIntoConstraints = NO;
    [emptyStack addArrangedSubview:_emptyIconView];
    [emptyStack addArrangedSubview:_emptyLabel];

    [_emptyCard addSubview:emptyStack];
    [_contentStack addArrangedSubview:_emptyCard];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyCard.heightAnchor constraintEqualToConstant:180],
        [emptyStack.centerXAnchor constraintEqualToAnchor:_emptyCard.centerXAnchor],
        [emptyStack.centerYAnchor constraintEqualToAnchor:_emptyCard.centerYAnchor],

        [_emptyIconView.widthAnchor constraintEqualToConstant:68],
        [_emptyIconView.heightAnchor constraintEqualToConstant:68],
    ]];
}

#pragma mark - State Refresh (public)

- (void)reloadAccounts {
    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }

    // —— 数据源扫描（1:1 旧 reloadAccountList，Task180 双保险原样保留）——
    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    // Task180：复制 bug 双保险②——读侧兜底。①按 accountId（缺省退文件名）
    // 去重：历史残留的重复 .json 只展示一份；②过滤解析失败文件
    //（parseJSONFromFile 失败时返回 @{@"NSErrorObject": ...}，照单全收会
    // 渲染成空白行）
    NSMutableSet *seenIds = [NSMutableSet set];
    for (NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if (!isDir && [file hasSuffix:@".json"]) {
            NSDictionary *data = parseJSONFromFile(path);
            if (data == nil || data[@"NSErrorObject"] != nil) {
                NSLog(@"[ZL2Accounts] skipping unreadable account file: %@", file);
                continue;
            }
            NSString *key = data[@"accountId"] ?: [file stringByDeletingPathExtension];
            if ([seenIds containsObject:key]) {
                NSLog(@"[ZL2Accounts] dedup account entry by id: %@", key);
                continue;
            }
            [seenIds addObject:key];
            [self.accountList addObject:data];
        }
    }

    [self rebuildIdentityCard];
    [self rebuildFlow];

    BOOL hasAccounts = (self.accountList.count > 0);
    self.emptyCard.hidden = hasAccounts;
    // ★ Task393：封面流 + 动作行随空态塌缩（原 rowsStack 同语义）
    self.ame393_flowView.hidden = !hasAccounts;
    self.ame393_actionsRow.hidden = !hasAccounts;
}

// —— ① 视觉卡：当前账号头像/名字/类型（无账号「未登录」，同主页口径）——
- (void)rebuildIdentityCard {
    BaseAuthenticator *auth = BaseAuthenticator.current;
    NSString *displayName = localize(@"ame369.acct.not_signed_in", @"未登录");
    NSDictionary *authData = nil;
    if (auth && auth.authData) {
        authData = auth.authData;
        NSString *username = authData[@"username"];
        if ([username isKindOfClass:[NSString class]] && username.length > 0) {
            if ([username hasPrefix:@"Demo."]) {
                username = [username substringFromIndex:5];
            }
            displayName = username;
        }
    }
    self.identityNameLabel.text = displayName;
    self.identityTypeLabel.hidden = (authData == nil);
    self.identityTypeLabel.text = authData ? [self typeTextForAccountData:authData] : @"";
    self.identityCard.accessibilityLabel =
        [NSString stringWithFormat:localize(@"ame369.acct.current_fmt", @"当前账户：%@"), displayName];

    if (authData) {
        // 头像：AvatarManager 三层回退链（profilePicURL → crafatar → minotar，
        // completion 恰好主线程回调一次，nil 时落回占位图标）
        __weak typeof(self) weakSelf = self;
        [[AvatarManager sharedManager] ame185_fetchAvatarForAuthData:authData
                                                          completion:^(UIImage *image) {
            [weakSelf ame_applyIdentityAvatarImage:image];
        }];
    } else {
        [self ame_applyIdentityAvatarImage:nil];
    }
}

- (void)ame_applyIdentityAvatarImage:(UIImage *)image {
    if (image) {
        self.identityAvatarView.image = image;   // 真头像（默认渲染，圆角裁切）
        self.identityAvatarView.tintColor = nil;
    } else {
        // 无账号/取图失败：person.crop.circle.fill 占位（60pt onSurfaceVariant）
        UIImage *placeholder = [UIImage systemImageNamed:@"person.crop.circle.fill"];
        if (!placeholder) placeholder = [UIImage systemImageNamed:@"person.circle.fill"];
        self.identityAvatarView.image = placeholder;
        self.identityAvatarView.tintColor = [ZL2Theme onSurfaceVariant];
        self.identityAvatarView.contentMode = UIViewContentModeScaleAspectFit;
    }
}

// —— ③ 封面流重建（★ Task393：条目 = 账户卡，全部同款零选中装饰；
//    初始落定 = 当前选中账户（accountId 精确比对，同名账户也能正确区分）；
//    头像异步取（AvatarManager 三层回退链；nil 保持占位图标）——
- (void)rebuildFlow {
    NSString *selectedId = [self currentSelectedAccountId];
    __block NSUInteger ame393_selectedIdx = 0;   // 枚举块内赋值（CI 实锤 r1：缺 __block 编译雷）
    NSMutableArray<Ame393FlowItem *> *ame393_items = [NSMutableArray array];

    [self.accountList enumerateObjectsUsingBlock:^(NSDictionary *accountData, NSUInteger idx, BOOL *stop) {
        Ame393FlowItem *ame393_item = [[Ame393FlowItem alloc] init];

        // 标题 = 账号名（Demo 账户去掉前缀展示，旧 cellForRow 同款）
        NSString *displayName = accountData[@"username"] ?: @"";
        if ([displayName hasPrefix:@"Demo."]) {
            displayName = [displayName substringFromIndex:5];
        }
        ame393_item.nameLabel.text = displayName;
        ame393_item.typeLabel.text = [self typeTextForAccountData:accountData];

        if (selectedId.length > 0 && [selectedId isEqualToString:accountData[@"accountId"]]) {
            ame393_selectedIdx = idx;
        }

        [ame393_items addObject:ame393_item];

        // 弱引用条目：取图回调晚到不吊命已拆条目
        __weak Ame393FlowItem *weakItem = ame393_item;
        [[AvatarManager sharedManager] ame185_fetchAvatarForAuthData:accountData completion:^(UIImage *image) {
            if (image && weakItem) {
                weakItem.avatarView.image = image;   // 默认渲染，圆角裁切
                weakItem.avatarView.tintColor = nil;
            }
        }];
    }];

    [self.ame393_flowView configureItems:ame393_items];
    [self.ame393_flowView setSelectedIndex:(NSInteger)ame393_selectedIdx animated:NO];
    [self ame393_refreshActionState];
}

// 当前选中账户的 accountId（BaseAuthenticator.current.authData，旧链同款）
- (NSString *)currentSelectedAccountId {
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    return currentAuth.authData[@"accountId"];
}

// 账号类型文字（1:1 旧 ame190_accountTypeTextForAccount：Task220 判别口径
// ——accountType 显式优先，旧文件回退键位嗅探）
- (NSString *)typeTextForAccountData:(NSDictionary *)accountData {
    NSString *username = accountData[@"username"] ?: @"";
    if ([username hasPrefix:@"Demo."]) {
        return localize(@"login.option.demo", @"演示");
    }
    NSString *type = accountData[@"accountType"];
    if ([type isKindOfClass:NSString.class] && type.length > 0) {
        if ([type isEqualToString:@"thirdparty"]) {
            return localize(@"login.option.3rdparty", @"第三方");
        } else if ([type isEqualToString:@"local"]) {
            return localize(@"login.option.local", @"本地");
        }
        return @"Microsoft";
    }
    // 旧文件回退（与 loadSavedName 同口径：clientToken 先于 xboxGamertag）
    if (accountData[@"clientToken"] != nil) {
        return localize(@"login.option.3rdparty", @"第三方");
    } else if (accountData[@"xboxGamertag"] == nil) {
        return localize(@"login.option.local", @"本地");
    }
    return @"Microsoft";
}

// 刷新钮可用性：离线账号禁用（ZL2 AccountElements L350
// `enabled = accountType != LOCAL` 规则 × 本仓旧 VC 类型判定口径）
- (BOOL)refreshEnabledForAccountData:(NSDictionary *)accountData {
    NSString *type = accountData[@"accountType"];
    if ([type isKindOfClass:NSString.class] && type.length > 0) {
        return ![type isEqualToString:@"local"];
    }
    if (ZL2AccountsIsThirdParty(accountData)) return YES;
    return (accountData[@"xuid"] != nil || accountData[@"xboxGamertag"] != nil);
}

#pragma mark - Interaction Lock

// 选中/登录/刷新链进行中锁交互（旧链 modalInPresentation + tableView 关闭
// 的等价物；恢复点 = 成功/失败收尾）
- (void)setInteractionLocked:(BOOL)locked {
    self.modalInPresentation = locked;
    self.view.userInteractionEnabled = !locked;
    // ★ Task393：封面流手势锁（拖拽/点按随锁冻结，原行内钮可达性等价）
    self.ame393_flowView.interactionLocked = locked;
    if (!locked) {
        [self ame393_setFlowBusy:NO];
    }
}

// ★ Task393：忙态占位上收动作行（原行内 spinner 槽位语义：选中/刷新链
//   进行中占刷新钮位；行视图退役后不再按下标定位——忙态恒属居中账户）
- (void)ame393_setFlowBusy:(BOOL)busy {
    if (busy) {
        [self.ame393_spinner startAnimating];
    } else {
        [self.ame393_spinner stopAnimating];
    }
    self.ame393_refreshButton.hidden = busy;
    self.ame393_moreButton.enabled = !busy;
}

// 动作行刷新钮可用性 = 居中（选中）账户是否在线账号（原行内规则上收：
// ZL2 AccountElements L350 `accountType != LOCAL` × 本仓判定口径）
- (void)ame393_refreshActionState {
    NSInteger ame393_idx = self.ame393_flowView.selectedIndex;
    BOOL ame393_can = NO;
    if (self.accountList.count > 0 && ame393_idx >= 0
        && (NSUInteger)ame393_idx < self.accountList.count) {
        ame393_can = [self refreshEnabledForAccountData:self.accountList[(NSUInteger)ame393_idx]];
    }
    self.ame393_refreshButton.enabled = ame393_can;
    self.ame393_refreshButton.tintColor = ame393_can ? [ZL2Theme primary] : [ZL2Theme outlineVariant];
}

// —— 动作行：居中（选中）账户的刷新 / 更多（原行内双钮语义上收）——
- (void)ame393_refreshCenteredAccount {
    if (self.ame393_flowView.interactionLocked) return;
    NSInteger ame393_idx = self.ame393_flowView.selectedIndex;
    if (ame393_idx < 0 || (NSUInteger)ame393_idx >= self.accountList.count) return;
    [self refreshAccountAtIndex:(NSUInteger)ame393_idx];
}

- (void)ame393_moreMenuForCenteredAccount {
    if (self.ame393_flowView.interactionLocked) return;
    NSInteger ame393_idx = self.ame393_flowView.selectedIndex;
    if (ame393_idx < 0 || (NSUInteger)ame393_idx >= self.accountList.count) return;
    [self ame393_showAccountMenuAtIndex:(NSUInteger)ame393_idx];
}

// 选中/登录/刷新成功收尾：恢复交互 + 重建列表 + 发 @"UpdateAccountInfo"
//（旧 ame128_finishSelectionForCell + whenItemSelected 桥接的等价物）
- (void)finishSelection {
    [self setInteractionLocked:NO];
    [self reloadAccounts];
    [self ame_postAccountInfoChanged];
}

#pragma mark - Row Actions

// —— 选中链（1:1 旧 ame190_selectAccountAtIndexPath）——
- (void)selectAccountAtIndex:(NSUInteger)index {
    if (index >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[index];

    // 优先用 accountId 加载；若 accountId 缺失（旧格式账户未迁移），回退
    // 到 username 触发迁移（旧链同款）
    NSString *loadKey = accountData[@"accountId"];
    if (loadKey.length == 0) {
        loadKey = accountData[@"username"];
    }

    self.modalInPresentation = YES;
    self.view.userInteractionEnabled = NO;
    [self ame393_setFlowBusy:YES];

    if (ZL2AccountsIsThirdParty(accountData)) {
        // 第三方：Task128 zl2 同款 isSessionValidated——本会话已通过服务端
        // 校验直接选中；否则 refresh，成功选中、失败优雅降级（stale token
        // 仍选中 + toast 提示重新登录）
        ThirdPartyAuthenticator *auth = [ThirdPartyAuthenticator loadSavedName:loadKey];
        if ([self sessionValidated:loadKey]) {
            [self finishSelection];
        } else {
            __weak typeof(self) weakSelf = self;
            [auth refreshTokenWithCallback:^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [weakSelf markSessionValidated:loadKey];
                        [weakSelf handleAuthResult:status success:YES];
                    } else {
                        // Task 128（zl2 同款优雅回退）：refresh 失败不再硬阻断
                        // 选择——仍选中该账户（current 已由 loadSavedName 设置；
                        // selected_account 持久化），toast 提示重新登录
                        [weakSelf markSessionValidated:loadKey];
                        setPrefObject(@"internal.selected_account", loadKey);
                        [weakSelf finishSelection];
                        [NMToast showMessage:[NSString stringWithFormat:@"%@\n%@",
                            localize(@"login.3rdparty.stale.title", nil),
                            localize(@"login.3rdparty.stale.message", nil)]
                                      duration:6.0];
                    }
                });
            }];
        }
    } else {
        // 微软/本地：loadSavedName + refreshTokenWithCallback → 共用收尾
        __weak typeof(self) weakSelf = self;
        [[BaseAuthenticator loadSavedName:loadKey] refreshTokenWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleAuthResult:status success:success];
            });
        }];
    }
}

// —— 刷新链（显式刷新；离线账号按钮已禁用，此处按可用性再兜底一道）——
- (void)refreshAccountAtIndex:(NSUInteger)index {
    if (index >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[index];
    if (![self refreshEnabledForAccountData:accountData]) return;

    NSString *loadKey = accountData[@"accountId"];
    if (loadKey.length == 0) {
        loadKey = accountData[@"username"];
    }

    self.modalInPresentation = YES;
    self.view.userInteractionEnabled = NO;
    [self ame393_setFlowBusy:YES];

    __weak typeof(self) weakSelf = self;
    if (ZL2AccountsIsThirdParty(accountData)) {
        ThirdPartyAuthenticator *auth = [ThirdPartyAuthenticator loadSavedName:loadKey];
        [auth refreshTokenWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [weakSelf markSessionValidated:loadKey];
                    [weakSelf handleAuthResult:status success:YES];
                } else {
                    // 显式刷新失败 = 错误弹窗（区别于选中链的 stale 降级）
                    [weakSelf handleAuthFailure:status];
                }
            });
        }];
    } else {
        [[BaseAuthenticator loadSavedName:loadKey] refreshTokenWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleAuthResult:status success:success];
            });
        }];
    }
}

// —— 更多菜单（UIAlertController actionSheet；只移植旧 VC 真实存在的操作）——
- (void)ame393_showAccountMenuAtIndex:(NSUInteger)index {
    if (index >= self.accountList.count) return;
    __weak typeof(self) weakSelf = self;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"account.menu.delete", @"删除账号")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf confirmDeleteAccountAtIndex:index];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    // ★ Task393：popover 锚点改动作行更多钮（原行内 moreButton 同语义防御）
    sheet.popoverPresentationController.sourceView = self.ame393_moreButton;
    sheet.popoverPresentationController.sourceRect = self.ame393_moreButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// 删除确认（ZL2 AccountOperation.Delete 同款 SimpleAlertDialog 语义——
// 旧链菜单路径无确认，此为对标 ZL2 的安全性补强）
- (void)confirmDeleteAccountAtIndex:(NSUInteger)index {
    if (index >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[index];
    NSString *displayName = accountData[@"username"] ?: @"";
    if ([displayName hasPrefix:@"Demo."]) {
        displayName = [displayName substringFromIndex:5];
    }
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"account.menu.delete", @"删除账号")
                                                                   message:displayName
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"account.menu.delete", @"删除账号")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf deleteAccountAtIndex:index];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// —— 删除链（1:1 旧 ame190_deleteAccountAtIndexPath + 容器 whenDelete 桥接）——
- (void)deleteAccountAtIndex:(NSUInteger)index {
    if (index >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[index];

    // 用 accountId 作为文件名（唯一标识），同名账户删除互不影响；
    // 若 accountId 缺失（旧格式账户未迁移），回退到 username
    NSString *accountId = accountData[@"accountId"];
    if (accountId.length == 0) {
        accountId = accountData[@"username"];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
    NSString *xuid = accountData[@"xuid"];
    if (xuid) {
        [MicrosoftAuthenticator clearTokenDataOfProfile:xuid];
    }
    [fm removeItemAtPath:path error:nil];
    // 若删除的正是当前选中账户，清空 selected_account，避免下次启动尝试
    // 加载已删除的账户
    if ([getPrefObject(@"internal.selected_account") isEqualToString:accountId]) {
        setPrefObject(@"internal.selected_account", @"");
        [BaseAuthenticator setCurrent:nil];
    }
    // 重建列表 + 发 @"UpdateAccountInfo"（旧容器 whenDelete 契约等价物）
    [self reloadAccounts];
    [self ame_postAccountInfoChanged];
}

#pragma mark - Auth Result（1:1 旧 callbackMicrosoftAuth，cell 无关化）

- (void)handleAuthResult:(id)status success:(BOOL)success {
    if (status != nil) {
        if (success) {
            // 成功：状态提示走 NMToast（旧 Task126 语义：非侵入提示，点击
            // "查看"无动作需求）；错误分支仍走弹窗
            NSString *message = nil;
            if ([status isKindOfClass:NSError.class]) {
                message = [(NSError *)status localizedDescription];
            } else if ([status isKindOfClass:NSString.class]) {
                message = (NSString *)status;
            }
            if (message.length > 0) {
                [NMToast showMessage:[NSString stringWithFormat:@"%@：%@",
                    localize(@"login.title", @"账户"), message]
                              duration:6.0];
            }
            if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"]) {
                // 演示模式警告仍需用户知悉（影响后续离线体验预期），保留弹窗
                [self showDemoDialog];
            }
            [self finishSelection];
        } else {
            [self handleAuthFailure:status];
        }
    } else if (success) {
        // 成功登录，无消息
        [self finishSelection];
    }
}

- (void)handleAuthFailure:(id)status {
    // 认证失败：恢复交互并展示错误（1:1 旧 callbackMicrosoftAuth 失败分支，
    // 含 AFNetworking 响应体细节）
    [self setInteractionLocked:NO];
    if ([status isKindOfClass:[NSError class]]) {
        NSData *errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        if (errorData) {
            NSString *errorStr = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSLog(@"[MSA] Error: %@", errorStr);
            [self showErrorDialog:errorStr];
        } else {
            [self showErrorDialog:[status localizedDescription]];
        }
    } else if ([status isKindOfClass:[NSString class]]) {
        [self showErrorDialog:status];
    } else {
        [self showErrorDialog:localize(@"login.error.invalid_response", nil)];
    }
}

- (void)showDemoDialog {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"login.warn.title.demomode", nil)
                         message:localize(@"login.warn.message.demomode", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showErrorDialog:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"Error", nil)
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Task128 移植：本会话已通过服务端校验的账户集合
- (BOOL)sessionValidated:(NSString *)loadKey {
    if (loadKey.length == 0) return NO;
    return [ZL2AccountsValidatedSet() containsObject:loadKey];
}

- (void)markSessionValidated:(NSString *)loadKey {
    if (loadKey.length > 0) [ZL2AccountsValidatedSet() addObject:loadKey];
}

#pragma mark - Add Account（actionSheet → 四种登录方式）

- (void)showAddAccountSheet {
    __weak typeof(self) weakSelf = self;
    // 旧 AccountListViewController 实际支持的四种登录方式 1:1（文案与旧
    // AccountLoginViewController 卡片同源 i18n 键）
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_10", nil)   // 微软账户
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf actionLoginMicrosoft];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"LittleSkin"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf pushThirdPartyLoginWithMode:ThirdPartyLoginModeLittleSkin];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_13", nil)   // 自定义第三方
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf pushThirdPartyLoginWithMode:ThirdPartyLoginModeCustom];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_15", nil)   // 本地账户
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf actionLoginLocal];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    // iPad/LiveContainer popover 锚点（旧链 actionAddAccount sender 为 nil
    // 崩溃的防御，锚到添加按钮自身）
    sheet.popoverPresentationController.sourceView = self.addAccountButton;
    sheet.popoverPresentationController.sourceRect = self.addAccountButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// —— 微软账户：ASWebAuthenticationSession MSA 流程（1:1 旧 actionLoginMicrosoft）——
- (void)actionLoginMicrosoft {
    NSURL *url = [NSURL URLWithString:@"https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];

    __weak typeof(self) weakSelf = self;
    self.authSession =
        [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"ms-xal-00000000402b5328"
        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error)
    {
        if (callbackURL == nil) {
            if (error.code != ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                [weakSelf showErrorDialog:error.localizedDescription];
            }
            return;
        }

        NSDictionary *queryItems = [weakSelf parseQueryItems:callbackURL.absoluteString];
        if (queryItems[@"code"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.modalInPresentation = YES;
                weakSelf.view.userInteractionEnabled = NO;
            });
            id callback = ^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf handleAuthResult:status success:success];
                });
            };
            [[[MicrosoftAuthenticator alloc] initWithInput:queryItems[@"code"]] loginWithCallback:callback];
        } else {
            if ([queryItems[@"error"] hasPrefix:@"access_denied"]) {
                // Ignore access denial responses
                return;
            }
            [weakSelf showErrorDialog:queryItems[@"error_description"]];
        }
    }];

    self.authSession.prefersEphemeralWebBrowserSession = YES;
    self.authSession.presentationContextProvider = self;

    if ([self.authSession start] == NO) {
        [self showErrorDialog:@"Unable to open Safari"];
    }
}

// URL 回调 query 解析（1:1 旧 parseQueryItems）
- (NSDictionary *)parseQueryItems:(NSString *)url {
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithString:url].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value;
    }
    return result;
}

// —— 本地账户：警告门 + 输入框 + LocalAuthenticator（1:1 旧 actionLoginLocal）——
- (void)actionLoginLocal {
    if (getPrefBool(@"warnings.local_warn")) {
        setPrefBool(@"warnings.local_warn", NO);
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:localize(@"login.warn.title.localmode", nil)
                             message:localize(@"login.warn.message.localmode", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        // 防御：iPad/LiveContainer 等 popover 场景下必须提供 sourceView
        //（旧链同款，锚到本页视图中心）
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        alert.popoverPresentationController.permittedArrowDirections = 0;
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [weakSelf actionLoginLocal];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:localize(@"Sign in", nil)
                         message:localize(@"login.option.local", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"login.alert.field.username", nil);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *usernameField = textFields[0];
        if (usernameField.text.length < 3 || usernameField.text.length > 16) {
            // 旧链同款：原地改 message 重现（非法输入回到输入框）
            controller.message = localize(@"login.error.username.outOfRange", nil);
            [weakSelf presentViewController:controller animated:YES completion:nil];
        } else {
            id callback = ^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [weakSelf finishSelection];
                    } else {
                        // 旧链此处未处理失败（静默 dismiss）；补错误弹窗防静默
                        [weakSelf handleAuthFailure:status];
                    }
                });
            };
            [[[LocalAuthenticator alloc] initWithInput:usernameField.text] loginWithCallback:callback];
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

// —— LittleSkin / 自定义第三方：push 卡片式登录表单页（1:1 旧
//    actionLoginLittleSkin / actionLoginThirdParty，init 签名 = [[alloc] init]
//    + mode + onLoginComplete，.h 已确认）——
- (void)pushThirdPartyLoginWithMode:(ThirdPartyLoginMode)mode {
    ThirdPartyLoginViewController *vc = [[ThirdPartyLoginViewController alloc] init];
    vc.mode = mode;
    __weak typeof(self) weakSelf = self;
    vc.onLoginComplete = ^(BOOL success, NSString *errorMessage) {
        if (success) {
            [weakSelf closeLoginFlowVC];
            [weakSelf finishSelection];
        }
    };
    if (self.navigationController != nil) {
        self.loginFlowPushed = YES;
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // 兜底：无导航栈宿主（如独立预览）时包 nav 呈现，保证有返回路径
        self.loginFlowPushed = NO;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)closeLoginFlowVC {
    if (self.loginFlowPushed) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - ASWebAuthenticationPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
