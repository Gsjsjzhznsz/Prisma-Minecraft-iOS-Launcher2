#!/usr/bin/env python3
# ame_bracket_audit.py — ObjC 括号平衡状态机扫描器（7.0-UI 门禁标准件）
#
# 为什么不用正则：URL 中的 "//" 会被当行注释吞掉后续代码造成误报。
# 本扫描器按字符状态机处理，优先级顺序：先行注释(//) → 块注释(/* */)
# → @"..." → "..." → '...' → 其余计 {} 与 () 深度。
#
# 用法: python3 ame_bracket_audit.py file1.m [file2.m ...]
# 退出码: 0 全部平衡 / 1 存在失衡 / 2 参数错误

import sys

def audit(path: str) -> bool:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()
    i, n = 0, len(text)
    depth_curly = 0
    depth_paren = 0
    line = 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        # 1) 先行注释 //
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            i += 2
            while i < n and text[i] != '\n':
                i += 1
            continue
        # 2) 块注释 /* */
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 2
            continue
        # 3) @"..." ObjC 字符串字面量
        if c == '@' and i + 1 < n and text[i + 1] == '"':
            i += 2
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '"':
                    break
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 1
            continue
        # 4) "..." C 字符串
        if c == '"':
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '"':
                    break
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 1
            continue
        # 5) '...' C 字符（ObjC 中罕见，防御性处理）
        if c == "'":
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == "'":
                    break
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 1
            continue
        # 6) 括号深度
        if c == '{':
            depth_curly += 1
        elif c == '}':
            depth_curly -= 1
            if depth_curly < 0:
                print(f"{path}: line {line}:多余的 '}}'")
                return False
        elif c == '(':
            depth_paren += 1
        elif c == ')':
            depth_paren -= 1
            if depth_paren < 0:
                print(f"{path}: line {line}:多余的 ')'")
                return False
        i += 1
    if depth_curly != 0 or depth_paren != 0:
        print(f"{path}: 失衡 {{}}={depth_curly:+d} ()={depth_paren:+d}")
        return False
    print(f"{path}: {{}}:+{depth_curly} ():+{depth_paren}，ALL BALANCED")
    return True

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ok = True
    for path in sys.argv[1:]:
        try:
            if not audit(path):
                ok = False
        except OSError as e:
            print(f"{path}: 读取失败 {e}")
            ok = False
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
