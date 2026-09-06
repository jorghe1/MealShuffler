# -*- coding: utf-8 -*-
"""Every `store.<member>` a view references must exist on AppStore."""
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
store_src = io.open(os.path.join(ROOT, 'MealShuffler', 'Store', 'AppStore.swift'), encoding='utf-8').read()

declared = set()
declared |= set(re.findall(r'(?:@Published\s+)?(?:private\s+|static\s+)*(?:var|let)\s+(\w+)', store_src))
declared |= set(re.findall(r'func\s+(\w+)\s*[(<]', store_src))

used = {}
for dirpath, _, files in os.walk(os.path.join(ROOT, 'MealShuffler', 'Views')):
    for f in files:
        if not f.endswith('.swift'):
            continue
        path = os.path.join(dirpath, f)
        text = io.open(path, encoding='utf-8').read()
        for m in re.finditer(r'\bstore\.(\w+)', text):
            used.setdefault(m.group(1), set()).add(
                "%s:%d" % (os.path.relpath(path, ROOT), text[:m.start()].count(chr(10)) + 1))

missing = {k: v for k, v in used.items() if k not in declared}
print("AppStore declares %d members; views reference %d" % (len(declared), len(used)))
if missing:
    print()
    print("MISSING:")
    for name, sites in sorted(missing.items()):
        print("  store.%s  <- %s" % (name, ', '.join(sorted(sites))))
    sys.exit(1)
print("every referenced member exists")
