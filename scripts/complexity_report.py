"""Heuristic complexity report and gate for the Dart code.

Run from the repo root:
    python3 scripts/complexity_report.py           # the worst functions, classes, files
    python3 scripts/complexity_report.py --check   # exit 1 past the limits

The limits are a ratchet (docs/spec/security-and-complexity-plan.md, phase B):
lower them as the code improves. Code that is already over a limit is listed in
scripts/complexity_allowlist.txt with its current size; the gate fails when new
code goes over a limit, when an allowlisted item gets bigger, and (so the list
shrinks) it reports allowlisted items that are now under the limit.

Branches are a rough count of if/for/while/case/catch/&&/||/?: tokens.
The generated script prelude (JavaScript inside a Dart string) is skipped.
"""
import glob
import os
import re
import sys

MAX_FUNCTION_LINES = 90
MAX_FUNCTION_BRANCHES = 40
MAX_CLASS_LINES = 700
MAX_FILE_LINES = 800

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
SKIP = ('prelude.dart',)

files = [
    f
    for f in glob.glob('**/lib/**/*.dart', recursive=True)
    if not f.startswith('build')
    and 'l10n' not in f
    and '.dart_tool' not in f
    and not f.endswith(SKIP)
]
sig = re.compile(
    r'^(\s*)(?:static\s+|Future<[^>]*>\s+|Future\s+|[\w<>?,\[\] ]+\s+)?(?:get\s+)?(\w+)\s*\([^;{]*\)\s*(?:async\*?\s*)?\{\s*$'
)
cls_re = re.compile(r'^(?:abstract |sealed |final |base )*class (\w+)')

funcs, classes, file_sizes = [], [], []
for f in files:
    lines = open(f).read().split('\n')
    file_sizes.append((len(lines), f))
    i = 0
    while i < len(lines):
        l = lines[i]
        c = cls_re.match(l)
        if c:
            j = i + 1
            while j < len(lines) and not lines[j].startswith('}'):
                j += 1
            classes.append((j - i + 1, f, c.group(1)))
        m = sig.match(l)
        if m is None:
            # A signature split over lines (trailing commas): `name(` ... `) async {`.
            close = re.match(r'^(\s*)\)\s*(?:async\*?\s*)?\{\s*$', l)
            if close:
                k = i - 1
                while k >= 0 and not (
                    lines[k].startswith(close.group(1))
                    and len(lines[k]) - len(lines[k].lstrip()) == len(close.group(1))
                ):
                    k -= 1
                head = lines[k] if k >= 0 else ''
                # A declaration has a return type before the name; a call does not.
                name = re.search(r'^\s*(?:static\s+)?[\w<>?,\[\]() ]+\s(\w+)\s*\($', head.rstrip())
                if name and name.group(1) not in ('if', 'for', 'while', 'switch', 'catch'):
                    m = re.match(r'^(\s*)', l)
                    m = type('M', (), {'group': lambda self, n, _i=m.group(1), _n=name.group(1): _i if n == 1 else _n})()
        if (
            m
            and m.group(2) not in ('if', 'for', 'while', 'switch', 'catch', 'else')
            and not l.strip().startswith(('if', 'for', 'while', 'switch', 'return', '}'))
        ):
            ind = len(m.group(1))
            j = i + 1
            while j < len(lines) and not (
                lines[j].startswith(' ' * ind + '}')
                and len(lines[j]) - len(lines[j].lstrip()) == ind
            ):
                j += 1
            body = lines[i:j]
            br = sum(
                len(re.findall(r'\b(if|for|while|case|catch)\b|&&|\|\||\?[^?.]', x))
                for x in body
            )
            funcs.append((j - i + 1, br, f, i + 1, m.group(2)))
        i += 1

if '--check' not in sys.argv:
    print('LONGEST FUNCTIONS')
    for r in sorted(funcs, reverse=True)[:20]:
        print(r)
    print('BRANCHIEST FUNCTIONS')
    for r in sorted(funcs, key=lambda r: -r[1])[:15]:
        print(r)
    print('LARGEST CLASSES')
    for r in sorted(classes, reverse=True)[:12]:
        print(r)
    print('LARGEST FILES')
    for r in sorted(file_sizes, reverse=True)[:12]:
        print(r)
    over = {n: sum(1 for r in funcs if r[0] > n) for n in (60, 80, 100)}
    print('functions over 60/80/100 lines:', over)

# --- the gate ---------------------------------------------------------------
allow = {}
path = os.path.join(ROOT, 'scripts', 'complexity_allowlist.txt')
if os.path.exists(path):
    for line in open(path):
        line = line.split('#')[0].strip()
        if line:
            key, size = line.rsplit(' ', 1)
            allow[key] = int(size)

# Every measured item, keyed `kind path::name`, with its size and its limit.
items = {}
# Several functions in a file can share a name (every `build`), so a key is the
# name plus its order among the same name in that file: `build#2`.
seen = {}
for n, br, f, ln, name in sorted(funcs, key=lambda r: (r[2], r[3])):
    k = seen[(f, name)] = seen.get((f, name), 0) + 1
    suffix = '' if k == 1 else f'#{k}'
    items[f'function {f}::{name}{suffix}'] = (max(n, br * 2), n > MAX_FUNCTION_LINES or br > MAX_FUNCTION_BRANCHES, f'{n} lines, {br} branches')
for n, f, name in classes:
    items[f'class {f}::{name}'] = (n, n > MAX_CLASS_LINES, f'{n} lines')
for n, f in file_sizes:
    items[f'file {f}'] = (n, n > MAX_FILE_LINES, f'{n} lines')

if '--check' in sys.argv:
    bad = []
    for key, (size, over_limit, what) in sorted(items.items()):
        if over_limit and key not in allow:
            bad.append(f'TOO COMPLEX (new): {key} ({what})')
        elif key in allow and size > allow[key]:
            bad.append(f'GREW: {key} ({what}); the allowlist says {allow[key]}')
    stale = [k for k in allow if k not in items or not items[k][1]]
    for b in bad:
        print(b)
    for k in stale:
        print(f'note: {k} is now within the limits; remove it from the allowlist')
    print(
        f'{len(funcs)} functions, {len(classes)} classes, {len(files)} files; '
        f'{len(allow)} allowlisted; limits {MAX_FUNCTION_LINES} lines / '
        f'{MAX_FUNCTION_BRANCHES} branches per function, {MAX_CLASS_LINES} per class, '
        f'{MAX_FILE_LINES} per file'
    )
    sys.exit(1 if bad else 0)

if '--write-allowlist' in sys.argv:
    with open(path, 'w') as out:
        out.write('# Known over-limit code (see scripts/complexity_report.py). Each entry is\n')
        out.write('# `kind path::name size`; shrink the code, then delete the line.\n')
        for key, (size, over_limit, what) in sorted(items.items()):
            if over_limit:
                out.write(f'{key} {size}  # {what}\n')
