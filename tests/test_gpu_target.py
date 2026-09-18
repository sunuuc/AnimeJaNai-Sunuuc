"""Check GPU selection and the exact native files in a staged or extracted package."""
from pathlib import Path
import ctypes
import json
import os
import struct
import sys
import tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/standalone'))
from gpu_target import TARGET, COMPONENTS, forbidden, pe_imports, prune, validate, sha

def unit_tests():
    for family in ('75','80','86','89','90','100','121'):
        assert forbidden(f'nvinfer_builder_resource_sm{family}_11.dll')
    assert forbidden('nvinfer_builder_resource_ptx_11.dll')
    assert forbidden('DirectML.dll') and forbidden('aji_harness_dml.exe')
    assert not forbidden('nvinfer_builder_resource_sm120_11.dll')
    assert not forbidden('cudart64_13.dll') and not forbidden('nvinfer_11.dll')
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp);binary=root/'pe.dll';b=bytearray(4096)
        b[:2]=b'MZ';struct.pack_into('<I',b,0x3c,0x80);b[0x80:0x84]=b'PE\0\0'
        struct.pack_into('<H',b,0x86,1);struct.pack_into('<H',b,0x94,240)
        opt=0x98;struct.pack_into('<H',b,opt,0x20b);struct.pack_into('<I',b,opt+60,512)
        struct.pack_into('<I',b,opt+108,16)
        struct.pack_into('<II',b,opt+120,0x1100,40)
        sec=opt+240;struct.pack_into('<III',b,sec+12,0x1000,3584,512)
        struct.pack_into('<I',b,512+256+12,0x1200)
        b[1024:1024+16]=b'cudart64_13.dll\0\0'
        binary.write_bytes(b);assert pe_imports(binary)==['cudart64_13.dll']
        inf=root/'app/animejanai/inference';inf.mkdir(parents=True)
        records=[]
        for id,name in [('trt-runtime','nvinfer_11.dll'),('trt-sm120','nvinfer_builder_resource_sm120_11.dll'),('rife','rife.onnx'),('trt-sm89','nvinfer_builder_resource_sm89_11.dll')]:
            p=inf/name;p.write_bytes(b'fixture')
            records.append({'name':id,'files':[{'path':p.relative_to(root/'app').as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}]})
        (inf/'aji_dml.dll').write_bytes(b'DML')
        (root/'app/animejanai/animejanai.conf').write_text('[global]\nbackend=TensorRT\n')
        result=prune(root/'app',records,root/'evidence')
        assert {r['name'] for r in result}==COMPONENTS
        assert not (inf/'aji_dml.dll').exists() and not (inf/'nvinfer_builder_resource_sm89_11.dll').exists()
        assert (inf/'nvinfer_builder_resource_sm120_11.dll').exists()
        result=prune(root/'app',result,root/'evidence')
        assert len(result)==3
    print('PASS GPU target unit tests')

if __name__=='__main__':
    unit_tests()
    if len(sys.argv)>1:
        app=Path(sys.argv[1]).resolve();evidence=Path(sys.argv[2]).resolve()
        result=validate(app,evidence)
        component=json.loads((app/'build-info/standalone/components.json').read_text(encoding='utf-8'))
        assert {r['name'] for r in component}==COMPONENTS
        assert json.loads((app/'manifest.json').read_text(encoding='utf-8'))['gpu_target']==TARGET
        if os.name=='nt':
            with os.add_dll_directory(str(app)),os.add_dll_directory(str(app/'animejanai/inference')):
                loaded=ctypes.WinDLL(str(app/'animejanai/inference/aji.dll'))
                assert loaded._handle
                result['native_dispatcher_loads_without_directml']=True
        (evidence/'gpu-target.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print('PASS GPU target package:',TARGET['gpu'])
