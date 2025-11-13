#!/usr/bin/env python3
import re
import os

def fix_http_file_completely(filepath):
    """完整修复HTTP文件中的null-aware语法"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到所有 // REMOVED 标记
    removed_pattern = r"^\s*// REMOVED: ('[^']+'|\"[^\"]+\"):\s*\?(\w+).*$"
    
    lines = content.split('\n')
    result = []
    in_map = False
    map_indent = ''
    removed_vars = []
    map_var_name = None
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # 检测 map 开始
        if re.search(r'\b(var|final)\s+(\w+)\s*=\s*\{', line) or re.search(r'queryParameters:\s*\{', line):
            in_map = True
            map_indent = len(line) - len(line.lstrip())
            removed_vars = []
            # 提取变量名
            match = re.search(r'\b(var|final)\s+(\w+)\s*=', line)
            if match:
                map_var_name = match.group(2)
            else:
                map_var_name = 'queryParams'
            result.append(line)
            i += 1
            continue
        
        # 检测 REMOVED 行
        match = re.match(removed_pattern, line, re.MULTILINE)
        if match and in_map:
            key = match.group(1)
            var_name = match.group(2)
            removed_vars.append((key, var_name))
            # 跳过这一行
            i += 1
            continue
        
        # 检测 map 结束
        if in_map and re.search(r'^\s*\}[;,]?\s*$', line):
            # 在 } 之前插入条件语句
            if removed_vars:
                indent_str = ' ' * (map_indent + 2)
                close_brace = line.strip()
                result.append(indent_str + close_brace)
                for key, var_name in removed_vars:
                    result.append(f"{indent_str}if ({var_name} != null) {map_var_name}[{key}] = {var_name};")
                in_map = False
                removed_vars = []
                i += 1
                continue
            else:
                in_map = False
        
        result.append(line)
        i += 1
    
    new_content = '\n'.join(result)
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True
    return False

# 处理所有HTTP文件
files = [
    'lib/http/live.dart',
    'lib/http/video.dart',
    'lib/http/msg.dart',
    'lib/http/dynamics.dart',
    'lib/http/fav.dart',
    'lib/http/user.dart',
    'lib/http/search.dart',
]

for f in files:
    if os.path.exists(f):
        if fix_http_file_completely(f):
            print(f"✓ Fixed {f}")
        else:
            print(f"- {f} already fixed or no changes")
    else:
        print(f"✗ File not found: {f}")

print("\nHTTP文件修复完成")
