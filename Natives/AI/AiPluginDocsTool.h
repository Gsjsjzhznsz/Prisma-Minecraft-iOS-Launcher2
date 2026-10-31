//
//  AiPluginDocsTool.h
//  Prisma
//
//  ★ Task365：插件提示词独立化（用户拍板"单独开个插件提示词，用户说要生成
//  插件 AI 才会看另一个提示词，避免太消耗 token"）。get_plugin_docs = 按需
//  加载的插件全量 API 参考载体：基础系统提示词只留 create_plugin 参数契约
//  与"写插件必先拉本文档"铁律（v6 起瘦身），全量 ame.* API / 权限表 /
//  JIT·游戏启动·日志自修复三件套 / 标准写法与示例全部收拢在本工具的返回
//  文本里——只有对话真的进入插件编写场景时，这份大文档才进入上下文。
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiPluginDocsTool : NSObject <AiTool>
/// 插件全量 API 参考文档全文（docs 工具返回值与自检共用单一事实源）
+ (NSString *)pluginApiDocs;
@end

NS_ASSUME_NONNULL_END
