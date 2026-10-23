#!/usr/bin/env python3
# Task317 热修：AmePluginManager.m 单层包裹探测两处错
# ① info.name → info.filename（UZKFileInfo 无 name 属性，编译雷）
# ② segs[1] → segs[0]（filename=相对路径 "dir/file"，pathComponents[0] 才是顶层目录）
p = 'Natives/AmePluginManager.m'
s = open(p, encoding='utf-8').read()

old1 = 'NSString *name = info.name; // 相对路径'
new1 = 'NSString *name = info.filename; // 相对路径（UZKFileInfo.filename）'
assert s.count(old1) == 1, 'anchor1 %d' % s.count(old1)
s = s.replace(old1, new1)

old2 = '''            NSArray<NSString *> *segs = [name pathComponents];
            if (segs.count < 2) return;
            NSString *top = segs[1]; // segs[0] 为 "/"
'''
new2 = '''            NSArray<NSString *> *segs = [name pathComponents];
            if (segs.count < 2) return;
            NSString *top = segs[0]; // filename 为相对路径，首段即顶层目录
'''
assert s.count(old2) == 1, 'anchor2 %d' % s.count(old2)
s = s.replace(old2, new2)

open(p, 'w', encoding='utf-8').write(s)
print('fixed 2 anchors')
