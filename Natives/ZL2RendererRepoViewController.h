//
//  ZL2RendererRepoViewController.h
//  Amethyst
//
//  ★Task475 在线渲染器仓库（渲染器真插件化后的唯一获取面）：装机零预置，
//  MobileGlues 等渲染器插件包由本页在线下载 → sha256 校验 → 安装启用
//  （PLRendererPluginService installRendererPluginFromZip 消费链）。
//  目录源 = 仓内 renderer-repo/index.json（raw / jsdelivr / ghfast 三镜像，
//  粘性记忆 ame475.renderer.repo.mirror；插件仓库页 ame333 同族范式）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2RendererRepoViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
