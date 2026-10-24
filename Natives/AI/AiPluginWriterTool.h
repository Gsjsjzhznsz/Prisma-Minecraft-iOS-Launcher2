//
//  AiPluginWriterTool.h
//  Prisma
//
//  create_plugin 工具（Task 327 "AI 写插件"）：LLM 在对话里产出完整的
//  AmePlugin 插件（manifest + main.js），本工具负责校验落盘 + 首装授权 +
//  即时装载。插件效果在 设置 → 插件功能 区可见（Task327 贡献行渲染）。
//  权限级别 ControlledWrite：Safe 模式拒绝，Ask 模式询问，YOLO 直写。
//

#import <Foundation/Foundation.h>
#import "AiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AiPluginWriterTool : NSObject <AiTool>
@end

NS_ASSUME_NONNULL_END
