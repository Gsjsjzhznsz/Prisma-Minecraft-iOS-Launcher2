#!/usr/bin/env python3
# ame365_extract_v5.py -- 从 git HEAD 的 defaultSystemPrompt（v5）逐字节提取
# C 字符串拼接行，生成 ame365_v5DefaultSystemPrompt 留档方法体（迁移基线铁律
# 口径：同款拼接行 = 产出字符串逐字节一致）。输出写到 /tmp/ame365_v5_archive.txt
import subprocess, io, os, sys

REPO = "/home/z/my-project/repo-prisma2"
src = subprocess.run(
    ["git", "-C", REPO, "show", "HEAD:Natives/AI/AiSettings.m"],
    capture_output=True, text=True, check=True).stdout.replace("\r\n", "\n")

start = src.index("+ (NSString *)defaultSystemPrompt {")
marker = src.index("/// ★ Task364：v4 默认提示词全文")
zone = src[start:marker]
# 方法体 = 首个 { 后到闭合 } 行
close = zone.rindex("\n}")
body = zone[zone.index("{") + 1: close]  # 含 return ...;
# 归一化：去掉首尾空行，保留每行原样
lines = body.strip("\n").split("\n")
# 去掉首行 'return ' 前的空隙与结尾 ';'
while lines and lines[0].strip() == "":
    lines.pop(0)
while lines and lines[-1].strip() == "":
    lines.pop()

out = io.StringIO()
out.write("\n".join(lines))
text = out.getvalue()
with io.open("/tmp/ame365_v5_archive.txt", "w", encoding="utf-8") as f:
    f.write(text)
print("v5 body lines:", len(lines))
print("first line:", lines[0][:80])
print("last  line:", lines[-1][-80:])
# 产出字符串的粗校验：拼接所有 "...\"...\"" 片段长度
import re
joined = "".join(re.findall(r'@"((?:[^"\\]|\\.)*)"', text))
print("v5 produced string length:", len(joined))
print("contains 视图操纵:", "视图操纵" in joined, "| contains 共 15 项:", "共 15 项" in joined)
