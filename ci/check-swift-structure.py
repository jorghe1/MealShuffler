"""Cheap static checks for a Swift tree that cannot be compiled here.

Catches the mistakes that actually happen when patching blind: unbalanced braces,
references to symbols renamed away, and duplicate type declarations.
"""
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = [os.path.join(dp, f)
       for base in ('MealShuffler', 'MealShufflerTests')
       for dp, _, fs in os.walk(os.path.join(ROOT, base))
       for f in fs if f.endswith('.swift')]

def strip(src):
    """Remove string literals, comments and escapes so brace counting is honest."""
    src = re.sub(r'\\.', '', src)
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"[^"\n]*"', '""', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

problems = []

def lineno(text, index):
    return text[:index].count(chr(10)) + 1

# 1. brace / paren balance
for path in SRC:
    body = strip(io.open(path, encoding='utf-8').read())
    for opener, closer, name in (('{', '}', 'braces'), ('(', ')', 'parens'), ('[', ']', 'brackets')):
        delta = body.count(opener) - body.count(closer)
        if delta:
            problems.append("%s: %s unbalanced by %+d" % (os.path.relpath(path, ROOT), name, delta))

# 2. symbols renamed away this session (app sources only; tests inspect internals on purpose)
RENAMED = {
    r'\bplanningCostNOK\b': 'renamed to planningCost',
    r'\bweightedChoice\b': 'renamed to chooseMeal',
}
for path in SRC:
    text = io.open(path, encoding='utf-8').read()
    rel = os.path.relpath(path, ROOT)
    for pattern, why in RENAMED.items():
        for m in re.finditer(pattern, text):
            problems.append("%s:%d %s" % (rel, lineno(text, m.start()), why))
    # estimatedCostNOK survives only as a decode-only legacy key
    for m in re.finditer(r'\bestimatedCostNOK\b', text):
        line = lineno(text, m.start())
        ctx = text.splitlines()[line - 1].strip()
        allowed = (ctx.startswith('///') or 'case estimatedCostNOK' in ctx
                   or 'forKey: .estimatedCostNOK' in ctx
                   or 'estimatedCostNOK: Int' in ctx or 'estimatedCostNOK: 180' in ctx)
        if not allowed:
            problems.append("%s:%d stale estimatedCostNOK: %s" % (rel, line, ctx[:60]))
    # views must not reach past the tombstone filter
    if os.sep + 'Views' + os.sep in path:
        for m in re.finditer(r'store\.customMeals', text):
            problems.append("%s:%d view uses customMeals; want activeCustomMeals"
                            % (rel, lineno(text, m.start())))

# 3. duplicate top-level type declarations across files
decls = {}
for path in SRC:
    text = io.open(path, encoding='utf-8').read()
    for m in re.finditer(r'^(?:public |private |internal |final )*(struct|class|enum|actor|protocol)\s+(\w+)',
                         text, re.MULTILINE):
        decls.setdefault(m.group(2), []).append(os.path.relpath(path, ROOT))
for name, paths in sorted(decls.items()):
    if len(set(paths)) > 1:
        problems.append("duplicate type %s in %s" % (name, ', '.join(sorted(set(paths)))))

# 4. every generate(...) call uses the current label set
def argument_list(text, open_index):
    """Text between the matching parentheses starting at open_index."""
    depth, i = 0, open_index
    while i < len(text):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[open_index + 1:i]
        i += 1
    return ''

for path in SRC:
    text = io.open(path, encoding='utf-8').read()
    for m in re.finditer(r'\.generate\(', text):
        args = argument_list(text, m.end() - 1)
        for bad in ('favoriteMealIDs:', 'learnedScores:', 'recentlyCookedMealIDs:'):
            if bad in args:
                problems.append("%s:%d generate() still passes %s"
                                % (os.path.relpath(path, ROOT), lineno(text, m.start()), bad))

print("checked %d Swift files" % len(SRC))
if problems:
    print()
    print("%d problem(s):" % len(problems))
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("no structural problems found")
