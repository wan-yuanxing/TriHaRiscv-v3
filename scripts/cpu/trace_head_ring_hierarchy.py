"""ADS hierarchy-specific support diagnostic. Rejects unknown/malformed cones; not STA."""
from pathlib import Path
import re,json,sys,hashlib
from collections import defaultdict,Counter
p=Path(sys.argv[1]);text=p.read_text(encoding='utf-8');text=re.sub(r'/\*.*?\*/|//[^\n]*|\(\*.*?\*\)','',text,flags=re.S)
mods={n:b for n,b in re.findall(r'(?ms)^module\s+(\w+)\b(.*?)^\s*endmodule',text)}
parent={};edges=[];term=set();roots=[];targets=[];unknown_outputs={};census=Counter();fifo_path=None
norm=lambda s:re.sub(r'\s+','',s).replace('\\','')
def find(x):
 parent.setdefault(x,x)
 trail=[]
 while parent[x]!=x:
  trail.append(x);x=parent[x]
 for y in trail:parent[y]=x
 return x
def union(a,b):
 a=find(a);b=find(b)
 if a!=b:parent[a]=b
cache={};lut_inits={}
def parse(name):
 if name in cache:return cache[name]
 b=mods[name];decl={};ports={}
 for kind,hi,lo,n in re.findall(r'\b(input|output|wire)\s+(?:\[(\d+):(\d+)\]\s+)?(\\[^\s,;()]+|[\w$]+)',b):
  n=norm(n);decl[n]=list(range(int(hi),int(lo)-1,-1)) if hi else None
  if kind!='wire':ports[n]=kind
 cells=[]
 for kind,params,inst,body in re.findall(r'(?m)^\s*(\w+)\s*(?:#\s*\((.*?)\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);',b,re.S):
  if kind not in mods and not kind.startswith('GTP_'):continue
  connections={norm(k):v for k,v in re.findall(r'\.(\\[^\s]+|\w+)\s*\(([^()]*)\)',body)}
  cells.append((kind,norm(inst),connections))
  init=re.search(r"\.INIT\s*\(\s*64'([bh])([0-9a-f_]+)\s*\)",params,re.I)
  if kind=='GTP_LUT6D' and init:
   digits=init[2].replace('_','')
   if re.fullmatch('[01]+' if init[1].lower()=='b' else '[0-9a-fA-F]+',digits):
    value=int(digits,2 if init[1].lower()=='b' else 16)
    if value < 2**64:lut_inits[(name,norm(inst))]=value
 cache[name]=(decl,ports,cells,re.findall(r'\bassign\s+([^=;]+)=([^;]+);',b));return cache[name]
def expand(expr,decl,path):
 expr=norm(expr)
 if not expr:return []
 if expr.startswith('{'):
  assert expr.endswith('}'),expr
  items=[];level=0;start=1
  for i,c in enumerate(expr[1:-1],1):
   if c=='{':level+=1
   elif c=='}':level-=1
   elif c==',' and level==0:items.extend(expand(expr[start:i],decl,path));start=i+1
  return items+expand(expr[start:-1],decl,path)
 m=re.fullmatch(r"(\d+)'([bhd])([0-9a-fxz]+)",expr,re.I)
 if m:
  w=int(m[1]);digits=m[3]
  if 'x' in digits.lower() or 'z' in digits.lower():bits='x'*w
  else:bits=format(int(digits,{'b':2,'h':16,'d':10}[m[2].lower()]),'b').zfill(w)[-w:]
  return ["CONST:"+x for x in bits]
 if expr in decl:
  return [path+'/'+expr] if decl[expr] is None else [path+'/'+expr+'['+str(i)+']' for i in decl[expr]]
 m=re.fullmatch(r'(.*)\[(\d+)(?::(\d+))?\]',expr)
 if m and m[1] in decl:
  hi=int(m[2]);lo=int(m[3] or m[2]);return [path+'/'+m[1]+'['+str(i)+']' for i in range(hi,lo-1,-1)]
 raise ValueError('undeclared expression '+path+' '+expr)
def walk(module,path):
 global fifo_path
 decl,ports,cells,assigns=parse(module)
 if module=='triha_fetch_fifo':
  assert fifo_path is None;fifo_path=path;targets.extend(expand('pop0_i',decl,path)+expand('pop1_i',decl,path))
 if path=='top':
  for n,d in ports.items():
   if d=='input':term.update(expand(n,decl,path))
 for l,r in assigns:
  left=expand(l,decl,path);right=expand(r,decl,path);assert len(left)==len(right),(path,l,r)
  for a,b in zip(left,right):union(a,b)
 for kind,inst,conns in cells:
  census[kind]+=1
  if kind in mods:
   cd,cp,_,_=parse(kind);child=path+'/'+inst
   for n,v in conns.items():
    actual=expand(v,decl,path);formal=expand(n,cd,child)
    if not actual:continue
    assert len(actual)==len(formal),(child,n,len(actual),len(formal))
    for a,b in zip(actual,formal):union(a,b)
   walk(kind,child);continue
  pins={k:expand(v,decl,path) for k,v in conns.items()}
  if kind.startswith('GTP_DFF'):
   assert len(pins['Q'])==1;term.update(pins['Q'])
   if module=='triha_fetch_fifo' and 'ring_q[' in inst:
    for pin in ['D','CE']:
     if pins.get(pin):roots.append((path+'/'+inst,pin,pins[pin][0]))
  elif kind.startswith(('GTP_LUT','GTP_MUX2LUT')):
   outpins={'Z','Z5','COUT'};incoming=[x for k,vs in pins.items() if k not in outpins for x in vs]
   for k in outpins:
    relevant=incoming
    if kind=='GTP_LUT6D' and (module,inst) in lut_inits and k in ('Z','Z5'):
     # Vendor GTP_LUT6D: Z uses all 64 INIT bits; Z5 only the lower 32.
     # Retain each input iff toggling it can change this output truth table.
     # Unknown/missing INIT keeps the conservative all-input graph above.
     table=lut_inits[(module,inst)];width=5 if k=='Z5' else 6
     # Cofactor only literal binary inputs. With I5 tied high, Z cannot
     # observe the lower table used by Z5; including it creates false loops.
     # Unconnected, unknown or aliased inputs remain conservative.
     fixed={i:int(pins['I'+str(i)][0][-1]) for i in range(width)
            if pins.get('I'+str(i)) in (['CONST:0'],['CONST:1'])}
     reachable=[a for a in range(1<<width)
                if all(((a>>i)&1)==v for i,v in fixed.items())]
     support=[i for i in range(width) if i not in fixed and
              any(((table>>a)^(table>>(a^(1<<i))))&1 for a in reachable)]
     relevant=[v for i in support for v in pins.get('I'+str(i),[])]
    for o in pins.get(k,[]):edges.append((o,relevant))
  elif kind in ['GTP_DRM18K_E1','GTP_DRM36K_E1']:
   # Installed vendor models update a_out/b_out only on clock/reset events.
   # Keep asynchronous reset and 36K cascade paths in the support graph.
   for port in ['A','B']:
    state=path+'/'+inst+'/clocked_state_'+port;term.add(state)
    incoming=[state]+pins.get('RST'+port,[])+pins.get('CIN'+port,[])
    for o in pins.get('DO'+port,[]):edges.append((o,incoming))
  elif kind in ['GTP_INBUF','GTP_OUTBUF','GTP_CLKBUFG']:
   for o in pins.get('O',[]):edges.append((o,pins.get('I',[])))
  else:
   # Record other primitive output candidates, never assume sequential behavior.
   for k in ['Q','O','DO','DOA','DOB','P','Z']:
    for o in pins.get(k,[]):unknown_outputs[o]=kind
walk('triha_minimal_soc','top')
assert roots and len(targets)==2, 'Missing backend or late-control boundary'
graph={}
for o,ins in edges:
 o=find(o);ins=[find(x) for x in ins]
 if o in graph:assert graph[o]==ins,('multiple drivers',o)
 graph[o]=ins
term={find(x) for x in term}|{find('CONST:'+x) for x in '01xz'}
targetset={find(x) for x in targets};unk={find(x):k for x,k in unknown_outputs.items()};unknown=set();visited=set();hits=set();stack=[find(n) for _,_,n in roots]
while stack:
 n=stack.pop()
 if n in visited:continue
 visited.add(n)
 if n in targetset:hits.add(n)
 if n in term:continue
 if n in graph:stack.extend(graph[n])
 else:unknown.add((n,unk.get(n,'missing_driver')))
r={'status':'UNKNOWN' if unknown else ('FAIL' if hits else 'PASS'),'scope':'Full hierarchy alias-unified bit connectivity, FF/top inputs terminate; unknown primitives never silently terminate','netlist':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'backend_pins':len(roots),'visited':len(visited),'late_hits':sorted(hits),'unknown':sorted(unknown),'fifo_path':fifo_path,'targets':targets,'target_canonical':sorted(targetset),'primitive_census':dict(census)}
out=Path(sys.argv[2]);out.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in r.items() if k!='primitive_census'},indent=2));sys.exit(0 if r['status']=='PASS' else 1)
