import importlib.util, pathlib, tempfile, unittest, zipfile
from xml.sax.saxutils import escape
spec=importlib.util.spec_from_file_location('importer',pathlib.Path(__file__).resolve().parents[1]/'source/import_storyboard.py')
importer=importlib.util.module_from_spec(spec);spec.loader.exec_module(importer)

def fixture(path,rows):
    cells=[]
    for i,row in enumerate(rows,1):
        cells.append('<row r="%d">'%i+''.join('<c r="%s%d" t="inlineStr"><is><t>%s</t></is></c>'%(chr(65+j),i,escape(v)) for j,v in enumerate(row))+'</row>')
    with zipfile.ZipFile(path,'w') as z:
        z.writestr('xl/workbook.xml','<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Storyboard" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml','<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'+''.join(cells)+'</sheetData></worksheet>')

class ImportTests(unittest.TestCase):
    def test_reordered_columns_preserve_exact_text(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'sample.xlsx';voice='Lời nguyên văn.\nKhông sửa & không gọi AI.'
            fixture(path,[['Tiêu đề dự án kiểm tra'],['Prompt video OmniFlash','Voice-over','Cảnh','Thời gian','Prompt tạo ảnh AI','Mục / chương','Âm thanh / dựng'],['SHOT 1 @IMAGE_2',voice,'1','00:00–00:25','Ảnh thứ nhất','Mở đầu','Nhạc nhẹ']])
            result=importer.read(path);self.assertEqual(result['scenes'][0]['voice'],voice);self.assertEqual(result['scenes'][0]['video'],'SHOT 1 @IMAGE_2');self.assertEqual(result['importInfo']['durationSeconds'],25);self.assertEqual(result['importInfo']['warnings'],[])
    def test_missing_prompt_warns_and_keeps_scene(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'sample.xlsx';fixture(path,[['Thời gian','Lời thuyết minh','Prompt ảnh','Prompt video'],['00:00–00:10','Nội dung','Ảnh','']]);result=importer.read(path)
            self.assertEqual(len(result['scenes']),1);self.assertIn('prompt video',result['importInfo']['warnings'][0])
    def test_bad_format_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'sample.xlsx';fixture(path,[['Không phải storyboard'],['Một ghi chú']])
            with self.assertRaises(ValueError):importer.read(path)

if __name__=='__main__':unittest.main()
