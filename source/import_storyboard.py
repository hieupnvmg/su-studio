"""Read cached XLSX cell values; never execute spreadsheet formulas or instructions."""
import sys, zipfile, xml.etree.ElementTree as ET, json, re, unicodedata, posixpath, uuid
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def normal(value):
    value = unicodedata.normalize('NFD', value.lower().replace('đ', 'd'))
    return re.sub(r'[^a-z0-9]+', ' ', ''.join(c for c in value if not unicodedata.combining(c))).strip()

def field(value):
    text = normal(value)
    if text in ('canh', 'scene', 'scene id', 'scene no', 'stt', 'so thu tu'): return 'scene'
    if text in ('thoi gian', 'time', 'timestamp', 'timecode', 'moc thoi gian'): return 'time'
    if text in ('muc chuong', 'chuong', 'ten canh', 'muc', 'chapter', 'title', 'noi dung canh'): return 'chapter'
    if text in ('voice over', 'voiceover', 'voice', 'loi doc', 'loi thuyet minh', 'thuyet minh', 'narration'): return 'voice'
    if ('prompt' in text and any(w in text.split() for w in ('anh', 'image', 'hinh'))) or text in ('image', 'hinh anh'): return 'image'
    if ('prompt' in text and 'video' in text) or text in ('video', 'chi dan tao video'): return 'video'
    if text in ('am thanh dung', 'am thanh ghi chu dung', 'ghi chu', 'notes', 'am thanh', 'sound editing'): return 'notes'
    return None

def clock(value):
    match = re.fullmatch(r'\s*(\d+):(\d{2})(?::(\d{2}))?\s*[–—-]\s*(\d+):(\d{2})(?::(\d{2}))?\s*', value)
    if not match: return None
    a,b,c,d,e,f = match.groups()
    start = int(a)*60+int(b) if c is None else int(a)*3600+int(b)*60+int(c)
    end = int(d)*60+int(e) if f is None else int(d)*3600+int(e)*60+int(f)
    return (start,end) if end>start else None

def read(path):
    with zipfile.ZipFile(path) as z:
        if sum(i.file_size for i in z.infolist()) > 100_000_000: raise ValueError('File Excel quá lớn để nhập storyboard.')
        shared = []
        if 'xl/sharedStrings.xml' in z.namelist():
            shared = [''.join(e.itertext()) for e in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        sheets = []
        wb = ET.fromstring(z.read('xl/workbook.xml'))
        rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
        targets = {r.attrib['Id']: r.attrib['Target'] for r in rels if r.attrib.get('TargetMode') != 'External'}
        for sheet in wb.findall('s:sheets/s:sheet', NS):
            target = targets.get(sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'])
            if not target: continue
            target = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
            rows = []
            for row in ET.fromstring(z.read(target)).findall('s:sheetData/s:row', NS):
                cells = {}
                for c in row:
                    col = re.sub(r'\d', '', c.attrib.get('r', ''))
                    if not col: continue
                    v = c.find('s:v', NS)
                    text = (v.text or '') if v is not None else ''.join(t.text or '' for t in c.findall('.//s:t', NS))
                    cells[col] = shared[int(text)] if c.attrib.get('t') == 's' and text else text
                rows.append({'number':int(row.attrib.get('r', len(rows)+1)), 'cells':cells})
            sheets.append({'name': sheet.attrib['name'], 'data': rows})
        candidates = []
        for si,sheet in enumerate(sheets):
            for ri,row in enumerate(sheet['data'][:50]):
                mapping = {}
                for col,value in row['cells'].items():
                    key = field(value)
                    if key and key not in mapping: mapping[key] = col
                if 'voice' in mapping and 'time' in mapping and ('image' in mapping or 'video' in mapping):
                    candidates.append((len(mapping),si,ri,mapping))
        if not candidates: raise ValueError('Không tìm thấy hàng tiêu đề. Cần cột Thời gian, Voice-over (hoặc Lời thuyết minh) và Prompt ảnh / Prompt video.')
        _,si,hi,mapping = max(candidates, key=lambda c:(c[0],-c[1],-c[2]))
        sheet = sheets[si];scenes=[];warnings=[];last_end=None
        for row in sheet['data'][hi+1:]:
            cells=row['cells'];get=lambda key: cells.get(mapping.get(key,''),'')
            # A content row needs a voice or a scene/time marker plus media prompts.
            if not get('voice').strip() and not ((get('scene').strip() or clock(get('time'))) and (get('image').strip() or get('video').strip())): continue
            scene={key:get(key) for key in ('time','chapter','voice','image','video','notes')}
            scene.update(id=str(uuid.uuid4()), approvals={}, assets={}, sourceRow=row['number'])
            if not scene['chapter'].strip(): scene['chapter']='Cảnh '+str(len(scenes)+1)
            missing=[label for key,label in [('time','thời gian'),('voice','lời đọc'),('image','prompt ảnh'),('video','prompt video')] if not scene[key].strip()]
            if missing: warnings.append('Dòng '+str(row['number'])+': thiếu '+', '.join(missing)+'.')
            timing=clock(scene['time'])
            if not timing: warnings.append('Dòng '+str(row['number'])+': kiểm tra thời gian, dùng dạng 00:00–00:25.')
            else:
                if last_end is not None and timing[0]!=last_end: warnings.append('Dòng '+str(row['number'])+': mốc thời gian chưa nối tiếp cảnh trước.')
                last_end=timing[1]
            scenes.append(scene)
            if len(scenes)>500: raise ValueError('Mỗi lần nhập tối đa 500 cảnh.')
        if not scenes: raise ValueError('Đã tìm thấy tiêu đề nhưng không có cảnh chứa nội dung.')
        title=next((v for row in sheet['data'][:hi] for v in row['cells'].values() if len(v.strip())>15), 'Storyboard đã nhập')
        refs=[{'name':s['name'],'rows':[r['cells'] for r in s['data']]} for i,s in enumerate(sheets) if i!=si]
        duration=max((clock(s['time'])[1] for s in scenes if clock(s['time'])),default=0)
        return dict(title=title,scenes=scenes,references=refs,importInfo={'sheet':sheet['name'],'headerRow':sheet['data'][hi]['number'],'columns':mapping,'warnings':warnings,'durationSeconds':duration})

if __name__ == '__main__':
    try: print(json.dumps(read(sys.argv[1]), ensure_ascii=False))
    except Exception as error:
        print(json.dumps({'error':str(error) if isinstance(error, ValueError) else 'File không phải Excel .xlsx hợp lệ hoặc bị hỏng.'},ensure_ascii=False))
        sys.exit(1)
