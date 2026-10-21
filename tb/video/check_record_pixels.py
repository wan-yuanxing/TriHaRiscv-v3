"""Independent full-record -> pixel/provider numerical and identity oracle."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import overlay_reference as math

def rgba(x,y,asset):
    return ((37*x+13*y+17+17*asset)%256,(x^(y*7)^asset)%256,
            (255-x+11*y+29*asset)%256,(x+3*y+asset*5)%256)

def decode_record(words,mode):
    def xy(value):
        values=[value&65535,value>>16]
        return [v-65536 if v>=32768 else v for v in values]
    flags=words[9]
    c=dict(mode=mode,valid=int(bool(flags&1)),has_face=int(not flags&2),result_frame=words[10],
           primary_valid=int(bool(flags&16)),primary=words[13],points_enable=int(bool(flags&4)),
           avatar_enable=int(bool(flags&8)),target=xy(words[21])+xy(words[22]),boxes=[],points=[])
    for i in range(16):
        row=words[32+i*8:40+i*8]
        c['boxes'].append(xy(row[0])+xy(row[1]) if words[12]&(1<<i) else None)
        c['points'].append([xy(row[3+j]) if row[2]&(1<<j) else None for j in range(5)])
    return c

def generate(w,h,directory,profile='dense'):
    directory.mkdir(parents=True,exist_ok=True)
    records=[];configs=[];modes=[0,0,1,2,0,2,2,1,0]
    for n in range(9):
        frame=1 if n<5 else n-3 if n<8 else 4
        slot=(frame-1)%3;gen=frame+9;asset=7 if n<5 else 8 if n<7 else 9
        words=[0]*160;words[:14]=[65536,640,slot,frame,gen,0x82000000+slot*0x200000,2400,800,600,29,frame,gen,65535,15]
        words[14:23]=[asset,asset*10+1,0x82600000,262144,256,256,1024,0,(h<<16)|w]
        c=math.base_config();c.update(mode=modes[n],result_frame=frame,points_enable=1,primary=15,target=[0,0,w,h])
        for i in range(16):
            left=i%4*(w//4)-1;top=i//4*(h//4)-1;right=left+max(2,w//4-1);bottom=top+max(2,h//4-1)
            box=[left,top,right,bottom];points=[[left,top],[right-1,top],[(left+right)//2,(top+bottom)//2],[left,bottom-1],[right-1,bottom-1]]
            xy=lambda x,y:((y&65535)<<16)|(x&65535)
            words[32+i*8:40+i*8]=[xy(left,top),xy(right,bottom),31,*[xy(*p) for p in points]]
            c['boxes'][i]=box;c['points'][i]=points
        if profile=='sparse':
            words[9]=25;words[12]=0x8021
            for i in range(16):
                off=32+i*8
                if not words[12]&(1<<i):words[off:off+8]=[0]*8
                else:
                    words[off+2]=5
                    for j in (1,3,4):words[off+3+j]=0
        elif profile=='no_primary':
            words[9]=5;words[12]=0x4211;words[13]=0;words[14:23]=[0]*9
            for i in range(16):
                off=32+i*8
                if not words[12]&(1<<i):words[off:off+8]=[0]*8
                else:
                    words[off+2]=4
                    for j in (0,1,3,4):words[off+3+j]=0
        if profile=='same_frame_generation' and n==5:
            words[2:6]=[0,1,11,0x82000000];words[10:12]=[1,11]
        records.append(words);configs.append(decode_record(words,modes[n]))
    (directory/'records.hex').write_text(''.join(f'{sum(v<<(32*i) for i,v in enumerate(row)):01280x}\n' for row in records),encoding='ascii')
    (directory/'reference.json').write_text(json.dumps(dict(w=w,h=h,records=records,configs=configs,modes=modes),indent=2)+'\n',encoding='utf-8')

def check(directory):
    info=json.loads((directory/'reference.json').read_text());inputs={};next_i=next_p=next_q=0;counts=dict(pixels=0,requests=0,box=0,point=0,avatar=0,fault=0)
    original=math.texture
    try:
        for line in (directory/'pixels.log').read_text().splitlines():
            p=line.split();kind=p.pop(0);values=[int(v,16) for v in p]
            if kind=='I':
                i,cid,frame,gen,slot,seq,x,y,rgb,de,hs,vs,sof,behavior=values
                assert i==next_i;next_i+=1;inputs[i]=values[1:]
            elif kind=='Z':
                assert values==[next_i];inputs.clear();next_p=next_q=next_i
            elif kind in ('Q','P'):
                i=values.pop(0);cid,frame,gen,slot,seq,x,y,rgb,de,hs,vs,sof,behavior=inputs[i]
                c=info['configs'][cid].copy() if cid else math.base_config()
                key=info['records'][cid]
                c['valid']=int(cid!=0 and c['valid'] and (frame,gen,slot)==(key[3],key[4],key[2]))
                asset=info['records'][cid][14] if cid else 0
                math.texture=lambda sx,sy:rgba(sx,sy,asset)
                event=(0,0,frame,x,y,rgb,de,hs,vs,sof,behavior)
                wanted,flags,address=math.reference(c,event)
                if kind=='Q':
                    assert i==next_q,(i,'request slot gap',next_q);next_q+=1
                    present,addr,aid,agen=values
                    assert present==int(address is not None),(i,'request presence',values,address)
                    if address is not None:
                        assert (addr,aid,agen)==(address,asset,asset*10+1),(i,'material key/address',values,address,asset)
                        counts['requests']+=1
                else:
                    assert i==next_p,(i,'output slot gap',next_p);next_p+=1
                    got_frame,got_gen,got_slot,got_mode,got_seq,ox,oy,ode,ohs,ovs,osof,got_rgb,*got_flags=values
                    assert (got_frame,got_gen,got_slot,got_mode,got_seq,ox,oy,ode,ohs,ovs,osof)==(frame,gen,slot,c['mode'] if cid else 0,seq,x,y,de,hs,vs,sof),(i,'metadata',values)
                    assert (got_rgb,got_flags)==(wanted,flags),(i,cid,'pixel',hex(got_rgb),got_flags,hex(wanted),flags)
                    counts['pixels']+=1
                    for key,hit in zip(('box','point','avatar','fault'),flags):counts[key]+=hit
                    del inputs[i]
            else:raise AssertionError('Unexpected pixel log '+kind)
        assert counts['pixels']>100 and next_q>=next_p and len(inputs)<=14,counts
    finally:math.texture=original
    (directory/'checked.json').write_text(json.dumps(dict(status='pass',counts=counts),indent=2)+'\n',encoding='utf-8')
    print('RECORD_PIXELS_ORACLE_PASS',counts)
    return counts

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('action',choices=['generate','check']);p.add_argument('--directory',type=Path,required=True);p.add_argument('--width',type=int,default=40);p.add_argument('--height',type=int,default=24);p.add_argument('--profile',choices=['dense','sparse','no_primary','same_frame_generation'],default='dense');a=p.parse_args()
    if a.action=='generate':generate(a.width,a.height,a.directory,a.profile)
    else:check(a.directory)
