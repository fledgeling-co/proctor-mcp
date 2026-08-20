import json,subprocess,shutil,tempfile,os,re,sys
base=json.load(open('docs/test-campaign/campaign.json'))
def run(extra):
    d=tempfile.mkdtemp()
    c=json.loads(json.dumps(base))
    c['blindVocabulary']['readers']=c['blindVocabulary']['readers']+extra
    json.dump(c,open(os.path.join(d,'campaign.json'),'w'))
    for f in ('inventory.json','cases.json'):
        p=os.path.join('docs/test-campaign',f)
        if os.path.exists(p): shutil.copy(p,d)
    out=subprocess.run(['python3','/tmp/pro79-vacuity-full.py',d,'--tests','Tests'],
                       capture_output=True,text=True).stdout
    m=re.search(r'blind:\s+examined=(\d+) mutating=(\d+) re-read-after=(\d+) blind=(\d+)',out)
    return m.group(4)
print("baseline blind =",run([]))
for cand in ['.contains','.stringValue','.intValue','.calls','.recorded','.inFlight',
             '.armCount','.drawing','.stepsAside','.recognisedPids','.observedInput','.outstandingCall']:
    print(f"  + {cand:<18} blind = {run([cand])}")
print("  + all spy-ledger (.calls,.recorded) blind =",run(['.calls','.recorded']))
