#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface FabricInstallViewController : PLPrefTableViewController

@property (nonatomic, copy) NSString *gameVersion;
@property (nonatomic, assign) BOOL shouldInstallAPI;
@property (nonatomic, copy) void (^completionHandler)(BOOL success, NSString *profileName, NSError *error);

// ★ Task335：ZL2 Addons 页直装预设（可选）。presetVendor 直入 vendor 段
// （Fabric / Legacy Fabric / Quilt），presetLoaderVersion 直填加载器版本；
// nil = 保持旧行为（自选页首项）。
@property (nonatomic, copy, nullable) NSString *presetVendor;
@property (nonatomic, copy, nullable) NSString *presetLoaderVersion;

@end
