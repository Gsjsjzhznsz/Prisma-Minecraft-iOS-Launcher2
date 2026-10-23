#!/usr/bin/env python3
# Task317 CI 热修：ZL2Theme.m 游离类方法搬移
# + (BOOL)ame317_setPluginThemeTokens:... 写在了 @implementation 之外（L60-101），
# 编译器 "missing context for method declaration"。整体搬到 @implementation 行后。
p = 'Natives/ZL2Theme.m'
s = open(p, encoding='utf-8').read()
lines = s.split('\n')

# 方法体 = L60(0基59) 至 L101(0基100)，含尾随空行 L102(0基101)
start = None
for i, l in enumerate(lines):
    if l.startswith('+ (BOOL)ame317_setPluginThemeTokens:'):
        start = i
        break
assert start is not None, 'method start not found'
end = None  # 方法闭合 "}" 行
depth = 0
seen_open = False
for i in range(start, len(lines)):
    depth += lines[i].count('{') - lines[i].count('}')
    if '{' in lines[i]:
        seen_open = True
    if seen_open and depth == 0:
        end = i
        break
assert end is not None, 'method end not found'
block = lines[start:end + 1]
print(f'cutting lines {start+1}..{end+1} ({len(block)} lines)')

# 切除（含其后的一个空行若紧邻）
tail_start = end + 1
if tail_start < len(lines) and lines[tail_start].strip() == '':
    tail_start += 1
rest = lines[:start] + lines[tail_start:]

# 找 @implementation ZL2Theme 行，插到其下一行
impl_idx = rest.index('@implementation ZL2Theme')
new_lines = rest[:impl_idx + 1] + [''] + block + rest[impl_idx + 1:]
open(p, 'w', encoding='utf-8').write('\n'.join(new_lines))
print(f'inserted after @implementation line {impl_idx+1}; total {len(new_lines)} lines')
