//
//  BuildTag.h
//  Amethyst
//
//  ★Task421 构建代际单一事实源（header 化）：Task407 立常量于 AboutViewController.m
//  私有 static，Task420 装机验锚 = 设置→关于版本行——但用户从不导航，四轮
//  「还是旧观感」复诉（IMG_0655/0661 = 416+ 共享角点几何数学不可能的手臂离位
//  缝 30~40px，Task415 代引擎签名）实锚失效。本轮：常量 header 化，关于页版本
//  行与预览卡代际角标（ZL2SkinPreviewView ame421_buildChip）同源同一字面量 =
//  双面恒等零漂移；用户任何一张预览截图即可判代际（无角标 = 旧构建）。
//
//  static NSString *const 于头文件 = 各 TU 自持指针指向同一常量字符串节，
//  零重复符号链接风险（冒烟固定清单无需加编任何 TU——Task416-r1/418-r1/
//  420-r1「新代码面首上 CI 才暴露」判例的预防式规避）。纯构建标识非用户文案，
//  零 i18n 键（同 [Ame406] 日志锚纪律）。
//

#ifndef BUILD_TAG_H
#define BUILD_TAG_H

#import <Foundation/Foundation.h>

static NSString *const ame415_buildTag = @"Task425 · 2026-11-14";   // 常量名留档 415 判例，值随轮次推进

#endif /* BUILD_TAG_H */
