//
//  MarkdownParser.h
//  Amethyst
//
//  轻量 Markdown → NSAttributedString 转换器
//  不依赖第三方库，纯 UIKit 实现。支持：h1-h3、粗体 **text**、斜体 *text*、
//  行内代码 `code`、无序列表 - item、有序列表 1. item、链接 [text](url)、
//  分隔线 ---、段落、引用块 > text。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MarkdownParser : NSObject

/// 将 Markdown 文本转换为 NSAttributedString（基础字体为系统 15pt）
/// @param markdown Markdown 原始文本
+ (NSAttributedString *)parseMarkdown:(NSString *)markdown;

/// 将 Markdown 文本转换为 NSAttributedString
/// @param markdown Markdown 原始文本
/// @param baseFont 基础字体（默认系统 15pt）
+ (NSAttributedString *)parseMarkdown:(NSString *)markdown baseFont:(UIFont *)baseFont;

/// ★ Ame362：指定正文色版本——气泡域（AIMessageCell）用系统自适应色
///   （labelColor）保证任何主题/插件覆盖状态下正文可见（旧版正文色走
///   AmeTheme→ZL2Theme→插件覆盖链，覆盖色与硬编码气泡底失配时正文
///   隐形——装机 IMG_0532 实锤 AI 回复全部不可见）。nil = 回退主题令牌。
///   内部代码块底/链接色/分隔线等仍取主题令牌。
/// @param textColor 正文/列表/标题基色（nil = AmeTheme textPrimary）
+ (NSAttributedString *)parseMarkdown:(NSString *)markdown
                              baseFont:(UIFont *)baseFont
                             textColor:(nullable UIColor *)textColor;

@end

NS_ASSUME_NONNULL_END
