"""Independent positive scene, admitted integer model, fixed board geometry."""
from pathlib import Path
import sys,json,hashlib,struct,argparse,shutil
import numpy as np,cv2,threadpoolctl
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description='Prepare a new source-bound natural-face integer-reference fixture; no RTL claim')
parser.add_argument('--image',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
image=args.image.read_bytes()
if hashlib.sha256(image).hexdigest()!='7de7ed51a1594fff247f4cae2301eceacf5313d6011e37b4a4c8733f7bb72c07':raise ValueError('unexpected OpenCV 4.10.0 lena.jpg bytes')
(out/'lena.jpg').write_bytes(image)
frozen=root/'build/npu/b03_assets_20261030/frozen_upstream'
sys.path.insert(0,str(root/'scripts/npu'))
from prepare_b03_assets import verify_frozen,BASE_MANIFEST,OLD,NUMERICS
plan=json.loads((frozen.parent/'recovery_plan.json').read_text(encoding='utf-8'));verify_frozen(frozen,plan['frozen_sources_sha256'])
sys.path.insert(0,str(frozen/'yunet/python'))
import program_abi,compile_b03_runtime as compiler
from b03_post_reference import DecodeTable,run
mapping=json.loads((frozen/BASE_MANIFEST).read_bytes());program=program_abi.unpack((frozen/OLD/'program.bin').read_bytes());program_abi.validate(program)
params=program_abi.parameter_arrays(program,(frozen/OLD/'parameter_image.bin').read_bytes(),mapping['parameter_image_model_offset'])
source=cv2.imread(str(out/'lena.jpg'));assert source is not None
frame=np.zeros((600,800,3),np.uint8);frame[:,100:700]=cv2.resize(source,(600,600))
small=cv2.resize(frame,(320,240),interpolation=cv2.INTER_LINEAR);padded=np.zeros((320,320,3),np.uint8);padded[40:280]=small
tensor=padded.transpose(2,0,1)[None].copy()
with threadpoolctl.threadpool_limits(limits=2,user_api='blas'):values=program_abi.reference_from_wire(program,params,tensor)
golden={mapping['tensor_names'][row['id']]:values[row['id']].astype(compiler.DTYPE[row['dtype']]) for row in program['tensors']}
manifest=json.loads((root/'model/yunet/upstream/b03_558280b/package_manifest.json').read_bytes())
heads=bytearray((root/'build/npu/b03_assets_20261030/assets/heads_init.bin').read_bytes());qheads={}
for row in manifest['head_slot_map']:
 raw=golden[row['name']].tobytes();assert len(raw)==row['bytes'];heads[row['slot_offset']:row['slot_offset']+len(raw)]=raw;qheads[row['name']]=golden[row['name']]
geom=dict(source_width=800,source_height=600,resized_width=320,resized_height=240,pad_left=0,pad_top=40)
post=run(qheads,DecodeTable(json.loads((frozen/NUMERICS).read_bytes())),geom,.6)
for name,data in [('input.bin',tensor.tobytes()),('frame_rgb.bin',frame[:,:,::-1].tobytes()),('heads.bin',heads),('records.bin',b''.join(struct.pack('<8I',*r['roi'],r['score_bits'],r['candidate_id'],r['stride'],0) for r in post['records']))]:(out/name).write_bytes(data)
report=dict(generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),numpy_version=np.__version__,opencv_version=cv2.__version__,frozen_reference_sha256=plan['frozen_sources_sha256'],status='PASS_HOST_REFERENCE',scope='New natural-face fixture through frozen integer reference; no RTL proof',faces=len(post['records']),records=post['records'],preselected=post['preselected'],geometry=geom,files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()})
(out/'reference.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');verify_frozen(frozen,plan['frozen_sources_sha256']);print(json.dumps(report))
