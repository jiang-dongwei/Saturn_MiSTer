"""Characterize a digital delay model; mixed outcomes are measurements, not acceptance."""
import hashlib
import itertools
import json
import subprocess
from pathlib import Path

out=Path('.ci/receive-window')
out.mkdir(parents=True,exist_ok=True)
binary=Path('.ci/receive-window.vvp')
rows=[]

def measure(name,args,control=False):
    result=subprocess.run(['vvp',str(binary),*args],capture_output=True,text=True,timeout=120)
    log=out/(name+'.log')
    log.write_text(result.stdout+result.stderr,encoding='utf-8')
    passed=result.returncode==0 and 'RAMH APS6408 PASS:' in result.stdout
    assert 'MODEL INJECTION ERROR' not in result.stdout, 'Mode override was not applied'
    rows.append(dict(name=name,args=args,control=control,passed=passed,
                     returncode=result.returncode,log=log.name,
                     log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
                     failure=[v for v in result.stdout.splitlines() if 'FATAL:' in v]))
    if control and not passed:
        raise AssertionError(f'Unskewed production control failed: {name}\n{result.stdout}')

for speed in ('8','16','33','50'):
    args=[] if speed=='33' else ['+speed'+speed]
    measure('control_'+speed,args,control=True)

for delay,mode,skew in itertools.product((2.0,10.0,13.0),range(4),(-1,0,1,2,3,4,5,6,7,8,10,12,14,16,18,20,24)):
    name=f'delay{delay:g}_mode{mode}_skew{skew}'.replace('-','neg')
    measure(name,[f'+dq_delay={delay}',f'+model_d1={mode}',f'+dq7_skew_ns={skew}'])

rtl=['rtl/aps6408_diag_core.sv','rtl/aps6408_diag_rx.sv','rtl/aps6408_diag_ddio_input.sv','rtl/ramh_aps6408_adapter.sv']
assert not subprocess.check_output(['git','diff','7183387','--',*rtl]),'Production RTL changed'
summary=dict(production_rtl_revision='7183387',scope='Digital model of fixed DQ7 skew relative to DQS/DQ0-6; no analog noise, ringing, FPGA fit delays or measured PCB margins',
    overrides='Second-byte mode forced at receiver input only in testbench; full core currently exposes no such setting',
    completed_cases=len(rows),controls_passed=all(v['passed'] for v in rows if v['control']),
    rtl_sha256={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in rtl},rows=rows)
(out/'window-summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k!='rows'},indent=2))
for delay,mode in itertools.product((2.0,10.0,13.0),range(4)):
    selected=[v for v in rows if not v['control'] and f'+dq_delay={delay}' in v['args'] and f'+model_d1={mode}' in v['args']]
    passing=[v['args'][-1].split('=')[1] for v in selected if v['passed']]
    print(f'MODEL DQS delay={delay:g}ns mode={mode} passing DQ7 skews={passing}')
