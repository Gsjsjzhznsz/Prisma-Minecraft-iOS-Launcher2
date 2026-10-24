#!/usr/bin/env python3
# Task324：ModService.h 补 ame324 两声明（CRLF 文件家法 = python 字节级手术，
# 禁用 Edit 工具防行尾展开；短锚点唯一性校验 + 字节级回读验尸）
import sys

PATH = "Natives/ModService.h"
with open(PATH, "rb") as f:
    data = f.read()

anchor = b"+ (void)ame271_selfHealStrandedIsolation;"
if data.count(anchor) != 1:
    print(f"FATAL: anchor count = {data.count(anchor)} (expect 1)"); sys.exit(1)

# CRLF 文件：插入行一律 \r\n 收尾，与宿主行尾一致
insert = (
    b"\r\n"
    b"// \xe2\x98\x85 Task324\xef\xbc\x9a\xe9\x9a\x94\xe7\xa6\xbb\xe5\xae\x9e\xe4\xbe\x8b\xe9\xaa\xa8\xe6\x9e\xb6\xe8\xa1\xa5\xe9\xbd\x90\xef\xbc\x88FCL/HMCL/PCL parity\xef\xbc\x9b\xe4\xbb\x85\xe9\x9a\x94\xe7\xa6\xbb\xe6\x80\x81\xe5\x88\x9b\xe5\xbb\xba\xef\xbc\x8c\xe5\xb9\x82\xe7\xad\x89\xe9\x9b\xb6\xe5\x89\xaf\xe4\xbd\x9c\xe7\x94\xa8\xef\xbc\x89\r\n"
    b"// \xe5\x85\xad\xe7\x9b\xae\xe5\xbd\x95 = mods/saves/config/resourcepacks/shaderpacks/screenshots\xef\xbc\x9b\r\n"
    b"// \xe9\xbb\x98\xe8\xae\xa4\xe5\xae\x9e\xe4\xbe\x8b\xe4\xb8\x8e\xe9\x9d\x9e\xe9\x9a\x94\xe7\xa6\xbb\xe7\x89\x88\xe6\x9c\xac\xe7\xbb\x9d\xe4\xb8\x8d\xe5\x88\x9b\xe5\xbb\xba\xef\xbc\x88\xe9\x98\xb2\"\xe6\x94\xbe\xe4\xba\x86\xe6\xa8\xa1\xe7\xbb\x84\xe5\x8d\xb4\xe4\xb8\x8d\xe7\x94\x9f\xe6\x95\x88\"\xe8\xaf\xaf\xe5\xaf\xbc\xef\xbc\x89\r\n"
    b"+ (void)ame324_ensureIsolationSkeletonForVersionId:(NSString *)vid;\r\n"
    b"+ (void)ame324_ensureIsolationSkeletonsAll;\r\n"
)

idx = data.index(anchor) + len(anchor)
# 锚点行自身以 \r\n 结尾（校验）
if data[idx:idx+2] != b"\r\n":
    print("FATAL: anchor line not CRLF-terminated"); sys.exit(1)
out = data[:idx+2] + insert + data[idx+2:]

with open(PATH, "wb") as f:
    f.write(out)

# 验尸：字节级回读
with open(PATH, "rb") as f:
    check = f.read()
assert check.count(b"ame324_ensureIsolationSkeletonForVersionId:") == 1, "decl1 missing"
assert check.count(b"ame324_ensureIsolationSkeletonsAll;") == 1, "decl2 missing"
assert b"\r\n+ (void)ame324_ensureIsolationSkeletonsAll;\r\n" in check, "CRLF form broken"
assert check.count(b"\r\n") >= data.count(b"\r\n") + 6, "CRLF count regression"
print("OK: ModService.h ame324 declarations spliced (CRLF preserved)")
