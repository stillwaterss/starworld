"""Externalize duplicate GLB textures and cap browser-only NPC textures at 1024px."""
from pathlib import Path
from PIL import Image
import struct,json

def optimize(root):
    r=Path(root)/'assets/characters/npc'
    before=sum(p.stat().st_size for p in r.iterdir() if p.is_file() and p.suffix in ('.glb','.png'))
    for p in r.glob('*.glb'):
        d=p.read_bytes();n=struct.unpack_from('<I',d,12)[0];j=json.loads(d[20:20+n])
        if not any('bufferView' in im for im in j['images']):continue
        off=20+n;bl=struct.unpack_from('<I',d,off)[0];binary=d[off+8:off+8+bl]
        ids={im['bufferView'] for im in j['images']};newbin=bytearray();views=[];mapping={}
        for i,v in enumerate(j['bufferViews']):
            if i in ids:continue
            mapping[i]=len(views);v=dict(v);start=v.get('byteOffset',0)
            data=binary[start:start+v['byteLength']];assert len(data)==v['byteLength']
            v['byteOffset']=len(newbin);newbin.extend(data);newbin.extend(b'\0'*((-len(newbin))%4));views.append(v)
        for im in j['images']:
            name=p.stem+'_'+im['name']+'.png';assert (p.parent/name).exists(),name
            im.pop('bufferView');im.pop('mimeType',None);im['uri']=name
        def remap(x):
            if isinstance(x,dict):
                for k,v in list(x.items()):
                    if k=='bufferView':x[k]=mapping[v]
                    else:remap(v)
            elif isinstance(x,list):
                for v in x:remap(v)
        remap(j);j['bufferViews']=views;j['buffers'][0]['byteLength']=len(newbin)
        js=json.dumps(j,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
        p.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(newbin))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(newbin),0x004e4942)+newbin)
    for p in r.glob('*.png'):
        im=Image.open(p)
        if max(im.size)>1024:
            im.thumbnail((1024,1024),Image.Resampling.LANCZOS);im.save(p,optimize=True)
    after=sum(p.stat().st_size for p in r.iterdir() if p.is_file() and p.suffix in ('.glb','.png'))
    return {'before_bytes':before,'after_bytes':after,'max_texture_edge':1024}

if __name__=='__main__':
    print(optimize(Path(__file__).resolve().parents[1]/'outputs/web_release_source/game'))
