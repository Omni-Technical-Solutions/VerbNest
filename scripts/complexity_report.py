"""Heuristic complexity report: longest, branchiest and deepest Dart functions.

Run from the repo root: python3 scripts/complexity_report.py
Branches are a rough count of if/for/while/case/catch/&&/||/?: tokens.
"""
import re,sys,glob,os
files=[f for f in glob.glob('**/lib/**/*.dart',recursive=True) if not f.startswith('build') and 'l10n' not in f and '.dart_tool' not in f]
sig=re.compile(r'^(\s*)(?:static\s+|Future<[^>]*>\s+|Future\s+|[\w<>?,\[\] ]+\s+)?(?:get\s+)?(\w+)\s*\([^;{]*\)\s*(?:async\*?\s*)?\{\s*$')
res=[];
for f in files:
    L=open(f).read().split('\n')
    i=0
    while i<len(L):
        m=sig.match(L[i])
        if m and m.group(2) not in('if','for','while','switch','catch','else') and not L[i].strip().startswith(('if','for','while','switch','return','}')):
            ind=len(m.group(1)); j=i+1
            while j<len(L) and not (L[j].startswith(' '*ind+'}') and len(L[j])-len(L[j].lstrip())==ind): j+=1
            n=j-i+1
            body=L[i:j]
            br=sum(len(re.findall(r'\b(if|for|while|case|catch)\b|&&|\|\||\?[^?.]',l)) for l in body)
            depth=max((len(l)-len(l.lstrip())-ind)//2 for l in body if l.strip())
            res.append((n,br,depth,f,i+1,m.group(2)))
            i+=1
        else:i+=1
print("LONGEST"); [print(r) for r in sorted(res,reverse=True)[:25]]
print("BRANCHIEST"); [print(r) for r in sorted(res,key=lambda r:-r[1])[:20]]
print("DEEPEST"); [print(r) for r in sorted(res,key=lambda r:-r[2])[:12]]
