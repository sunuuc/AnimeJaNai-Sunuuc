"""Render ASS into libass memory buffers; no desktop, windows or video streams."""
from pathlib import Path
import ctypes as C
import os
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
INSTALL=Path(os.environ.get('ANIMEJANAI_INSTALL',r'D:\Apps\mpv-AnimeJaNai'))
LIBRARY=Path(os.environ.get('ANIMEJANAI_LIBASS',INSTALL/'libass-9.dll'))
FACTORY=Path(os.environ.get('DANMAKU_FACTORY',INSTALL/'animejanai/danmaku/DanmakuFactory.exe'))

class Image(C.Structure):
    pass
Image._fields_=[('w',C.c_int),('h',C.c_int),('stride',C.c_int),('bitmap',C.c_void_p),
    ('color',C.c_uint32),('x',C.c_int),('y',C.c_int),('next',C.POINTER(Image)),('type',C.c_int)]

class Canvas(unittest.TestCase):
    def test_native_black_bar_rendering(self):
        directory=os.add_dll_directory(str(INSTALL))
        dll=C.CDLL(str(LIBRARY.resolve()))
        signatures={
            'ass_library_init':(C.c_void_p,[]),
            'ass_renderer_init':(C.c_void_p,[C.c_void_p]),
            'ass_set_frame_size':(None,[C.c_void_p,C.c_int,C.c_int]),
            'ass_set_storage_size':(None,[C.c_void_p,C.c_int,C.c_int]),
            'ass_set_margins':(None,[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_int]),
            'ass_set_fonts':(None,[C.c_void_p,C.c_char_p,C.c_char_p,C.c_int,C.c_char_p,C.c_int]),
            'ass_read_memory':(C.c_void_p,[C.c_void_p,C.c_char_p,C.c_size_t,C.c_char_p]),
            'ass_render_frame':(C.POINTER(Image),[C.c_void_p,C.c_void_p,C.c_int64,C.POINTER(C.c_int)]),
            'ass_free_track':(None,[C.c_void_p]),'ass_renderer_done':(None,[C.c_void_p]),
            'ass_library_done':(None,[C.c_void_p]),
        }
        for name,(result,args) in signatures.items():
            fn=getattr(dll,name);fn.restype=result;fn.argtypes=args
        library=dll.ass_library_init();renderer=dll.ass_renderer_init(library)
        self.assertTrue(library and renderer)
        dll.ass_set_frame_size(renderer,1920,1200)
        dll.ass_set_storage_size(renderer,1920,1080)
        dll.ass_set_margins(renderer,60,60,0,0)
        dll.ass_set_fonts(renderer,None,b'Microsoft YaHei',1,None,1)
        def load(text):
            data=text.encode('utf-8');track=dll.ass_read_memory(library,data,len(data),None)
            self.assertTrue(track)
            return track
        def render(track):
            changed=C.c_int();image=dll.ass_render_frame(renderer,track,6000,C.byref(changed))
            boxes=[]
            while image:
                item=image.contents
                if item.w and item.h:boxes.append((item.x,item.y,item.w,item.h))
                image=item.next
            return boxes
        try:
            with tempfile.TemporaryDirectory(prefix='danmaku-canvas-') as tmp:
                folder=Path(tmp);xml=folder/'input.xml';ass=folder/'output.ass'
                xml.write_text('<i><d p="0,1,25,16777215">Viewport text</d></i>',encoding='utf-8')
                result=subprocess.run([str(FACTORY),'-i',str(xml),'-o',str(ass),'--force','--ignore-warnings'],
                                      capture_output=True,timeout=15)
                self.assertEqual(result.returncode,0,result.stderr)
                text=ass.read_text(encoding='utf-8-sig')
                self.assertIn('RenderInMargins: yes',text)
                track=load(text);normal=load(text.replace('RenderInMargins: yes','RenderInMargins: no'))
                try:
                    # Reuse both tracks. The first native frame after each size change must be correct.
                    for w,h,margin in [(640,400,20),(2560,1600,80),(960,540,0),(640,400,20)]:
                        dll.ass_set_frame_size(renderer,w,h)
                        dll.ass_set_margins(renderer,margin,margin,0,0)
                        boxes=render(track)
                        self.assertTrue(boxes,'native resize must keep danmaku visible')
                        self.assertTrue(all(0<=y<max(6,margin) for x,y,bw,bh in boxes),boxes)
                        if margin:
                            self.assertTrue(all(y+bh<=margin for x,y,bw,bh in boxes),boxes)
                        ordinary=render(normal)
                        self.assertTrue(ordinary and all(y>=margin for x,y,bw,bh in ordinary),ordinary)
                        self.assertEqual(render(track),boxes,'switching tracks must not alter the danmaku canvas')
                        print(f'First native frame after resize: {w}x{h}, screen coordinates visible')
                finally:
                    dll.ass_free_track(track);dll.ass_free_track(normal)
        finally:
            dll.ass_renderer_done(renderer);dll.ass_library_done(library);directory.close()

if __name__=='__main__':
    unittest.main()
