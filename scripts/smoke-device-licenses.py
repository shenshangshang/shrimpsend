#!/usr/bin/env python3
"""Live, local-only license contract test. Uses the disposable purchaser from seed-local-license-qa.py."""
import concurrent.futures, json, pathlib, secrets, urllib.request, urllib.error, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
BASE='http://localhost:9000'
fixture=json.loads((ROOT/'.local/license-qa.json').read_text())
assert fixture['email']=='device-license-qa@local.invalid'
def request(path,token=None,method='GET',body=None):
    headers={'Content-Type':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    req=urllib.request.Request(BASE+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
    try:
        with urllib.request.urlopen(req,timeout=30) as r: status,raw=r.status,r.read()
    except urllib.error.HTTPError as e: status,raw=e.code,e.read()
    return status,json.loads(raw) if raw else None

def ok(path,token=None,method='GET',body=None,status=200):
    code,data=request(path,token,method,body)
    assert code==status,(path,code,data)
    return data
owner=ok('/api/auth/login',method='POST',body={**fixture,'deviceId':'qa-license-purchaser','platform':'web'})['accessToken']
dashboard=ok('/api/device-licenses',owner)
assert dashboard['available'] >= 3, 'This local contract test needs 3 free QA slots. Release the demo licenses in the QA membership page first.'
prefix='qa-license-'+uuid.uuid4().hex[:8]
devices=[]
for n in range(3):
    ident=prefix+'-'+str(n)
    session=ok('/api/realtime/device-session',method='POST',body={'deviceId':ident,'deviceSecret':secrets.token_urlsafe(32),'platform':'web'})
    devices.append((ident,session['deviceAccessToken']))
a,b,c=devices
base='/api/device-licenses'
def issue():return ok(base+'/codes',owner,'POST')
def activate(code,device,qr=False):return request(base+'/redeem',device[1],'POST',{('qrToken' if qr else 'code'):code['qrToken' if qr else 'code'],'name':'Local QA '+device[0][-1],'platform':'web'})
def release(device):ok(base+'/devices/'+device[0],owner,'DELETE',status=204)
issued=[]
try:
    assert ok(base+'/me',a[1])['authorized'] is False
    code=issue();issued.append(code)
    code['code']=code['code'][:3].lower()+' '+code['code'][3:].lower()
    status,claim=activate(code,a)
    assert status==200 and not claim['authorized'] and claim['pendingRequest']['status']=='CLAIMED'
    ok(base+'/requests/'+code['id']+'/approve',owner,'POST')
    assert ok(base+'/me',a[1])['authorized'] is True
    assert ok('/api/messages/device-quota',a[1])['unlimited'] is True
    assert ok('/api/devices/paired',a[1])==[]
    qr=issue();issued.append(qr)
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results=list(pool.map(lambda d:activate(qr,d,True),[b,c]))
    assert sorted(x[0] for x in results)==[200,409],results
    peer=b if results[0][0]==200 else c
    assert activate(qr,peer,True)[0]==200
    assert request(base,peer[1])[0]==403
    envelope={'type':'text','fromDeviceId':a[0],'toDeviceId':peer[0],'ts':1,'payload':{'text':'device-only delivery','localId':prefix}}
    assert request('/api/messages/send',owner,'POST',{'data':envelope})[0]==401
    assert request('/api/mailbox/pending?deviceId='+peer[0],owner)[0]==401
    assert request('/api/realtime/token?deviceId='+peer[0],owner)[0]==403
    assert request('/api/messages/device-send',a[1],'POST',{'data':envelope})[0]==403
    ok('/api/devices/pair',a[1],'POST',{'peerDeviceId':peer[0]},204)
    ok('/api/messages/device-send',a[1],'POST',{'data':envelope},204)
    inbox=ok('/api/mailbox/pending?deviceId='+peer[0],peer[1])
    assert any(x['data']['payload'].get('localId')==prefix for x in inbox)
    assert request('/api/mailbox/pending?deviceId='+peer[0],a[1])[0]==403
    ok('/api/devices/paired/'+peer[0],a[1],'DELETE',status=204)
    assert ok('/api/devices/paired',a[1])==[]
    assert ok(base+'/me',peer[1])['authorized'] is True
    release(a)
    assert ok('/api/messages/device-quota',a[1])['unlimited'] is False
    assert activate(code,a)[1]['authorized'] is False
    hold=issue();issued.append(hold)
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results=list(pool.map(lambda _:request(base+'/codes',owner,'POST'),range(2)))
    issued += [data for status,data in results if status==200]
    assert sorted(x[0] for x in results)==[200,409],[(s,d.get('error') if isinstance(d,dict) else None) for s,d in results]
    print(json.dumps({'manual_approval':True,'concurrent_qr_one_winner':True,'concurrent_last_slot_one_winner':True,'same_owner_not_paired':True,'device_only_mailbox':True,'billing_cannot_impersonate':True,'unpair_keeps_license':True,'revoke_updates_quota':True,'old_code_cannot_reactivate':True}))
finally:
    for code in issued:
        request(base+'/requests/'+code['id'],owner,'DELETE')
    for device in devices:
        state=request(base+'/me',device[1])[1]
        if state and state.get('authorized'):release(device)
