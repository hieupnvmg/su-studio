import sys, zipfile, xml.etree.ElementTree as ET, json, re

NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def read(path):
    with zipfile.ZipFile(path) as z:
        shared = []
        if 'xl/sharedStrings.xml' in z.namelist():
            shared = [''.join(e.itertext()) for e in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        sheets = []
        wb = ET.fromstring(z.read('xl/workbook.xml'))
        rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
        targets = {r.attrib['Id']: r.attrib['Target'] for r in rels}
        for sheet in wb.findall('s:sheets/s:sheet', NS):
            target = targets[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            rows = []
            for row in ET.fromstring(z.read(target)).findall('s:sheetData/s:row', NS):
                cells = {}
                for c in row:
                    col = re.sub(r'\d', '', c.attrib.get('r', ''))
                    v = c.find('s:v', NS)
                    text = v.text if v is not None else ''.join(t.text or '' for t in c.findall('.//s:t', NS))
                    cells[col] = shared[int(text)] if c.attrib.get('t') == 's' and text else text or ''
                rows.append(cells)
            sheets.append({'name': sheet.attrib['name'], 'rows': rows})
        scenes = []
        for row in sheets[0]['rows']:
            if str(row.get('A', '')).isdigit() and row.get('D'):
                scenes.append(dict(id='scene-' + row['A'], time=row.get('B', ''), chapter=row.get('C', ''), voice=row.get('D', ''), image=row.get('E', ''), video=row.get('F', ''), notes=row.get('G', ''), approvals={}, assets={}))
        if not scenes:
            raise ValueError('No scenes')
        title = next((r['A'] for r in sheets[0]['rows'] if r.get('A') and not r.get('D') and len(r['A']) > 20), 'Storyboard đã nhập')
        return dict(title=title, scenes=scenes, references=sheets[1:])

if __name__ == '__main__':
    print(json.dumps(read(sys.argv[1]), ensure_ascii=False))
