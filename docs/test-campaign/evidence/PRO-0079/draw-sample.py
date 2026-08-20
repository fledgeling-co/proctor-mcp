import random, collections, json
rows=[]
for line in open('/tmp/pro79-findings.tsv'):
    verb,name,path=line.rstrip('\n').split('\t')
    rows.append({'verb':verb,'name':name,'file':path})
by=collections.defaultdict(list)
for r in rows: by[r['verb']].append(r)
LARGE=['act','unlock','release','set','claim']   # >=5 findings
rnd=random.Random(20260821)
sample=[]
for v in LARGE:
    pool=sorted(by[v],key=lambda r:(r['file'],r['name']))
    sample += rnd.sample(pool,5)
tails=[v for v in by if v not in LARGE]
for v in sorted(tails):
    sample += sorted(by[v],key=lambda r:(r['file'],r['name']))
print(f"population=78 large-strata={sum(len(by[v]) for v in LARGE)} tail-census={sum(len(by[v]) for v in tails)} sampled={len(sample)}")
json.dump(sample,open('/tmp/pro79-sample.json','w'),indent=1)
for r in sample: print(r['verb'],r['name'],r['file'].split('/')[-1])
