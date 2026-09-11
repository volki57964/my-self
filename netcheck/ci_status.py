#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import base64, json, os, subprocess, sys, time
from pathlib import Path
repo=os.environ.get('GITHUB_REPOSITORY','')
branch=os.environ.get('GITHUB_REF_NAME','')
if not repo or not branch or not os.environ.get('GH_TOKEN'):sys.exit(0)
state=sys.argv[1] if len(sys.argv)>1 else 'unknown'
phase=sys.argv[2] if len(sys.argv)>2 else 'unknown'
root=Path(os.environ.get('GITHUB_WORKSPACE','.'))
log=root/'netcheck/output/build.log'
tail=log.read_text(errors='replace')[-18000:] if log.exists() else ''
smoke=root/'netcheck/output/smoke.log'
result={'state':state,'phase':phase,'run_id':os.environ.get('GITHUB_RUN_ID'),'head_sha':os.environ.get('GITHUB_SHA'),'updated_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'log_tail':tail,'smoke_tail':smoke.read_text(errors='replace')[-8000:] if smoke.exists() else None}
status=root/'netcheck/output/build-status.json';status.parent.mkdir(parents=True,exist_ok=True);status.write_text(json.dumps(result,ensure_ascii=False,indent=2))
path=f'repos/{repo}/contents/netcheck-ci-status.json'
for attempt in range(3):
    get=subprocess.run(['gh','api',path+'?ref='+branch],text=True,capture_output=True)
    data={'message':'Record NetCheck CI status [skip ci]','branch':branch,'content':base64.b64encode(status.read_bytes()).decode()}
    if get.returncode==0:
        try:data['sha']=json.loads(get.stdout)['sha']
        except Exception:pass
    put=subprocess.run(['gh','api','--method','PUT',path,'--input','-'],input=json.dumps(data),text=True,capture_output=True)
    if put.returncode==0:break
    time.sleep(1)
