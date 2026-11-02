#!/bin/bash
# Builds the site and turns dist/client into a preview with relative links (for the Claude artifact).
set -e
# Usage: ./make-preview.sh   (OUT=folder to change the output folder, default artifact/)
OUT=${OUT:-artifact}
cd /home/claude/beand/site && npx astro build > /tmp/astro-build.log 2>&1 || { tail -30 /tmp/astro-build.log; exit 1; }
rm -rf /home/claude/beand/$OUT && cp -r dist/client /home/claude/beand/$OUT && cd /home/claude/beand/$OUT
rm -f robots.txt
mv _astro assets
python3 - <<'P'
import re, pathlib
root=pathlib.Path('.')
def rel(target, depth):
    path, _, frag = target.partition('#')
    if path=='' or path.endswith('/'): path=path+'index.html'
    out='../'*depth + path.lstrip('/')
    return out + ('#'+frag if frag else '')
for f in root.rglob('*.html'):
    depth=len(f.relative_to(root).parts)-1
    s=f.read_text()
    s=re.sub(r'(href|src)="(/[^"/][^"]*|/)"', lambda m: f'{m.group(1)}="{rel(m.group(2), depth)}"', s)
    s=s.replace('_astro/','assets/')
    if depth==0 and f.name=='index.html': s=s.replace('href="index.html#','href="#')
    f.write_text(s)
for f in root.rglob('*.css'):
    s=f.read_text(); s=re.sub(r'url\(/_astro/', 'url(./', s); f.write_text(s)
import json
fs=sorted(str(p) for p in root.rglob('*') if p.is_file())
fs.sort(key=lambda x: x!='index.html')
import os
out=os.getcwd()
json.dump([{'as':f,'path':out+'/'+f} for f in fs], open('/tmp/files.json','w'))
print(len(fs),'files')
P
