import json,re,sys
sample=json.load(open('/tmp/pro79-sample.json'))
camp=json.load(open('docs/test-campaign/campaign.json'))['blindVocabulary']
muts=tuple(camp['mutators'])+("stop_all","stop_runner","restart","clear_","cancel_","set_","delete_","create_","confirm_")
fn_re=re.compile(r"^\s*(?:async\s+)?(?:fn|def|func|function)\s+(\w+)\s*\(",re.M)
out=[]
for r in sample:
    src=open('Tests/'+r['file']).read()
    starts=[(m.start(),m.group(1)) for m in fn_re.finditer(src)]
    for i,(pos,name) in enumerate(starts):
        if name!=r['name']: continue
        end=starts[i+1][0] if i+1<len(starts) else len(src)
        body=src[pos:end]
        last,which=-1,None
        for v in muts:
            for m in re.finditer(r"(?<![A-Za-z0-9_])"+re.escape(v)+r"\w*\s*\(",body):
                if m.start()>last: last,which=m.start(),v
        lineno=src[:pos].count('\n')+1
        marked=body[:last]+f"\n>>>LAST-MUTATOR '{which}' FROM HERE>>>\n"+body[last:]
        out.append(f"===== {r['verb']} :: {r['name']} :: {r['file'].split('/')[-1]}:{lineno}\n{marked.rstrip()}\n")
        break
open('/tmp/pro79-bodies.txt','w').write("\n".join(out))
print(len(out),"bodies", sum(b.count('\n') for b in out),"lines")
