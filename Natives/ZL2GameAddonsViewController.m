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

// 加载器卡（ZL2 顺序：OptiFine / Forge / NeoForge / Fabric / Fabric API）
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *cardsStack;
@property (nonatomic, strong) ZL2AddonCard *optifineCard;
@property (nonatomic, strong) ZL2AddonCard *forgeCard;
@property (nonatomic, strong) ZL2AddonCard *neoforgeCard;
@property (nonatomic, strong) ZL2AddonCard *fabricCard;
@property (nonatomic, strong) ZL2AddonCard *fabricAPICard;

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

    // ② 加载器卡（ZL2 顺序：OptiFine → Forge → NeoForge → Fabric → Fabric API）
    _optifineCard = [self ame_cardWithIdentifier:@"optifine"
                                           title:@"OptiFine"
                                  iconBundleName:nil
                                 fallbackSymbol:@"sparkles"];
    _forgeCard = [self ame_cardWithIdentifier:@"forge"
                                        title:@"Forge"
                               iconBundleName:@"forge_light"
                              fallbackSymbol:@"hammer"];
    _neoforgeCard = [self ame_cardWithIdentifier:@"neoforge"
                                           title:@"NeoForge"
                                  iconBundleName:@"neoforge_light"
                                 fallbackSymbol:@"hammer.fill"];
    _fabricCard = [self ame_cardWithIdentifier:@"fabric"
                                         title:@"Fabric"
                                iconBundleName:@"fabric_light"
                               fallbackSymbol:@"link"];
    _fabricAPICard = [self ame_cardWithIdentifier:@"fabricapi"
                                            title:@"Fabric API"
                                   iconBundleName:nil
                                  fallbackSymbol:@"shippingbox"];
    for (ZL2AddonCard *card in @[_optifineCard, _forgeCard, _neoforgeCard,
                                 _fabricCard, _fabricAPICard]) {
        [stack addArrangedSubview:card];
        [card.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [card.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [_gameVersionLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_gameVersionLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],

        [_nameField.centerYAnchor constraintEqualToAnchor:_gameVersionLabel.centerYAnchor],
        [_nameField.leadingAnchor constraintGreaterThanOrEqualToAnchor:_gameVersionLabel.trailingAnchor constant:16],
        [_nameField.widthAnchor constraintEqualToConstant:220],
        [_nameField.heightAnchor constraintEqualToConstant:40],

        [_installButton.centerYAnchor constraintEqualToAnchor:_gameVersionLabel.centerYAnchor],
        [_installButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_installButton.leadingAnchor constraintEqualToAnchor:_nameField.trailingAnchor constant:12],
        [_installButton.heightAnchor constraintEqualToConstant:40],

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
    ]];

    // NeoForge 支持门控：MC <1.20.1 系无 NeoForge（ZL2 rememberLoaderVerSupports
    // 同口径——NeoForge 自 1.20.1 起才有版本线）
    if (![self ame_neoforgeSupported]) {
        _neoforgeCard.hidden = YES;
    }
    // Fabric API 清单依赖游戏版本（Modrinth facets），首屏即拉
    [self ame_loadListForCard:_fabricAPICard];
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

#pragma mark - NeoForge 支持门控

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

- (void)addonCardDidChangeSelection:(ZL2AddonCard *)card {
    NSString *sel = card.selectedItem;
    if (sel.length == 0) {
        // 清除选择：Fabric API 跟随清除（ZL2 fabric 清除时 API 语义不清除，但
        // iOS 侧保持一致性：fabric 没了 API 无意义 → 清）
        if ([card.identifier isEqualToString:@"fabric"]) {
            self.fabricAPICard.selectedItem = nil;
            [self.fabricAPICard ame_refreshAppearance];
        }
    } else {
        [self ame_applyExclusionForSelected:card.identifier];
        // Fabric 选中 → 自动跟随最新 Fabric API（ZL2 DownloadGameWithAddonScreen
        // 同语义：lastAPIVersion = fabricAPIList.firstOrNull）
        if ([card.identifier isEqualToString:@"fabric"]) {
            [self ame_loadListForCard:self.fabricAPICard];
        }
    }
    [self ame_refreshInstallButton];
}

/// 互斥（ZL2 ModLoader 家族语义 + 旧 ModLoaderInstallViewController 判例同口径）
- (void)ame_applyExclusionForSelected:(NSString *)identifier {
    // forge 与 fabric/neoforge 互斥（四加载器互斥族）
    if ([identifier isEqualToString:@"forge"]) {
        self.fabricCard.selectedItem = nil;
        self.neoforgeCard.selectedItem = nil;
        [self.fabricCard ame_refreshAppearance];
        [self.neoforgeCard ame_refreshAppearance];
    } else if ([identifier isEqualToString:@"fabric"]) {
        self.forgeCard.selectedItem = nil;
        self.neoforgeCard.selectedItem = nil;
        self.optifineCard.selectedItem = nil;
        [self.forgeCard ame_refreshAppearance];
        [self.neoforgeCard ame_refreshAppearance];
        [self.optifineCard ame_refreshAppearance];
    } else if ([identifier isEqualToString:@"neoforge"]) {
        self.forgeCard.selectedItem = nil;
        self.fabricCard.selectedItem = nil;
        self.optifineCard.selectedItem = nil;
        [self.forgeCard ame_refreshAppearance];
        [self.fabricCard ame_refreshAppearance];
        [self.optifineCard ame_refreshAppearance];
    } else if ([identifier isEqualToString:@"optifine"]) {
        // optifine 仅可与 forge 共存（fabric/neoforge 互斥）
        self.fabricCard.selectedItem = nil;
        self.neoforgeCard.selectedItem = nil;
        [self.fabricCard ame_refreshAppearance];
        [self.neoforgeCard ame_refreshAppearance];
    }
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
                // Fabric API 自动跟随：清单落定且 fabric 已选而 API 未选 → 选最新
                if ([ident isEqualToString:@"fabricapi"] &&
                    self.fabricCard.selectedItem.length > 0 &&
                    card.selectedItem.length == 0) {
                    card.selectedItem = items.firstObject;
                }
            }
            [card ame_refreshAppearance];
            [self ame_refreshInstallButton];
        });
    });
}

/// 各加载器清单端点（镜像策略沿用旧链：BMCLAPI/官方候选顺序由端点决定，
/// 此处取主源 + 简短超时；失败态由 UI 呈现，用户可点刷新钮重拉）
- (nullable NSArray<NSString *> *)ame_fetchListForIdentifier:(NSString *)identifier
                                                 gameVersion:(NSString *)gameVersion {
    NSData *data = nil;
    if ([identifier isEqualToString:@"forge"]) {
        // BMCLAPI forge/minecraft/{v}：[{version:"xx.yy.z"}]（含 build 号）
        data = [self ame_syncFetch:
            [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/forge/minecraft/%@", gameVersion]];
        if (!data) {
            data = [self ame_syncFetch:
                [NSString stringWithFormat:@"https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"]];
        }
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        if ([json isKindOfClass:[NSArray class]]) {
            NSMutableArray *out_ = [NSMutableArray array];
            for (NSDictionary *entry in json) {
                NSString *version = entry[@"version"];
                if (version.length > 0) [out_ addObject:version];
            }
            return out_;
        }
        return nil;
    }
    if ([identifier isEqualToString:@"neoforge"]) {
        data = [self ame_syncFetch:
            @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"];
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
        // Fabric meta v2：[{loader:{version:"x.y.z"}}]（官方 + BMCLAPI 双源）
        NSString *official = [NSString stringWithFormat:@"https://meta.fabricmc.net/v2/versions/loader/%@", gameVersion];
        NSString *mirror = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/%@", gameVersion];
        data = [self ame_syncFetch:official] ?: [self ame_syncFetch:mirror];
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
        // Modrinth：fabric-api 项目按游戏版本过滤（facets 同步端点同构）
        NSString *gv = [gameVersion stringByAddingPercentEncodingWithAllowedCharacters:
                        [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *url = [NSString stringWithFormat:
            @"https://api.modrinth.com/v2/project/fabric-api/version?game_versions=[%%22%@%%22]&loaders=[%%22fabric%%22]", gv];
        data = [self ame_syncFetch:url];
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
    if ([identifier isEqualToString:@"optifine"]) {
        // BMCLAPI OptiFine 清单：[{type:"HD_U",patch:"H1",mcversion:"1.20.4"}]
        data = [self ame_syncFetch:@"https://bmclapi2.bangbang93.com/optifine/versionList"];
        if (!data) return nil;
        id json = [self ame_parseJSON:data];
        if (![json isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray *out_ = [NSMutableArray array];
        for (NSDictionary *entry in json) {
            if (![entry[@"mcversion"] isEqualToString:gameVersion]) continue;
            NSString *type = entry[@"type"] ?: @"";
            NSString *patch = entry[@"patch"] ?: @"";
            if (type.length == 0) continue;
            [out_ addObject:[NSString stringWithFormat:@"%@\x1f%@\x1f%@", type, patch, entry[@"filename"] ?: @""]];
        }
        return out_;
    }
    return nil;
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
    BOOL busy = self.loadingIdentifiers.count > 0;
    BOOL hasSelection = self.forgeCard.selectedItem.length > 0 ||
                        self.neoforgeCard.selectedItem.length > 0 ||
                        self.fabricCard.selectedItem.length > 0 ||
                        self.optifineCard.selectedItem.length > 0;
    self.installButton.userInteractionEnabled = YES;
    self.installButton.backgroundColor = [ZL2Theme primary];
    self.installLabel.textColor = [ZL2Theme onPrimary];
    self.installLabel.text = busy ? @"清单加载中…"
                            : hasSelection ? @"安装"
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
    NSString *optifine = self.optifineCard.selectedItem;

    if (fabric.length > 0) {
        // Fabric(+API)：legacy FabricInstallViewController（自带版本选择页）
        FabricInstallViewController *vc = [[FabricInstallViewController alloc] init];
        vc.gameVersion = self.gameVersion;
        vc.shouldInstallAPI = (fabricAPIOn.length > 0);
        __weak typeof(self) weakSelf = self;
        vc.completionHandler = ^(BOOL success, NSString *profileName, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (!s) return;
                if (success) {
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"ReloadProfileList" object:nil];
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
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"name"] = versionId;
    profile[@"lastVersionId"] = versionId;
    profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@/game", versionId];
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
    _listView.scrollEnabled = NO;
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
    _listHeight.constant = self.expanded ? MIN((CGFloat)(MAX(self.items.count, 1)) * 40.0 + 8.0, 260.0) : 0.0;

    if (self.loading) {
        [_spinner startAnimating];
        _failedLabel.hidden = YES;
    } else {
        [_spinner stopAnimating];
        _failedLabel.hidden = !self.listFailed;
    }
    [UIView animateWithDuration:0.18 animations:^{
        [self layoutIfNeeded];
    }];
}

- (void)ame_headerTapped {
    if (self.loading || self.listFailed) return;
    if (self.items.count == 0) {
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
