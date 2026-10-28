"""Build a versioned offline word library from the official NGSL downloads.

Raw upstream files stay in data/source for reproducibility. Never infer that a
learner knows a word from its frequency rank.
"""
import csv
import hashlib
import json
import difflib
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class Table(HTMLParser):
    def __init__(self):
        super().__init__(); self.rows=[]; self.row=[]; self.cell=None
    def handle_starttag(self, tag, attrs):
        if tag == 'tr': self.row=[]
        if tag == 'td': self.cell=''
    def handle_data(self, value):
        if self.cell is not None: self.cell += value
    def handle_endtag(self, tag):
        if tag == 'td': self.row.append(self.cell.strip()); self.cell=None
        if tag == 'tr' and self.row: self.rows.append(self.row)

def main():
    source=ROOT/'data/source'
    english=Table(); english.feed((source/'NGSL_gloss.html').read_text())
    chinese=Table(); chinese.feed((source/'NGSL_ch_gloss.html').read_text())
    translations={r[1].lower():r[4].split(' - ',1)[0].strip() for r in chinese.rows}
    forms={r[0].lower():[v for v in r if v] for r in csv.reader((source/'NGSL_12_lemmatized_for_teaching.csv').read_text().splitlines()) if r and not r[0].startswith('##')}
    rank={r['Lemma'].lower():int(r['SFI Rank']) for r in csv.DictReader((source/'NGSL_12_stats.csv').read_text(encoding='utf-8-sig').splitlines())}
    curated_path=ROOT/'data/curated.json'
    curated=json.loads(curated_path.read_text()) if curated_path.exists() else {}
    audio_path=ROOT/'data/pronunciations.json'
    audio=json.loads(audio_path.read_text()) if audio_path.exists() else {}
    us_ipa={}
    us_path=source/'ipa_en_US.txt'
    if us_path.exists():
        for line in us_path.read_text().splitlines():
            if '\t' in line:
                word,value=line.split('\t',1);us_ipa[word.lower()]=value
    def normalized(ipa):
        return re.sub(r'[ˈˌ/ː\s]','',ipa).replace('ɝ','əɹ').replace('ɜɹ','əɹ').replace('ɫ','l').replace('ᵊ','ə').replace('ɾ','t')
    words=[]
    for r in english.rows:
        _,word,ipa,pos,definition=r
        key=word.lower().replace('e-mail','email')
        content={**curated.get(key,{}),**audio.get('ngsl12:'+key,{})}
        alternatives=us_ipa.get(word.lower(),'').split(', ')
        if alternatives != ['']:
            generated=normalized(content.get('usIpa',ipa))
            content['usIpa']=max(alternatives,key=lambda x:difflib.SequenceMatcher(None,normalized(x),generated).ratio())
        words.append(dict(id='ngsl12:'+key,word=word,rank=rank[key],pos=pos,chinese=translations[word.lower()],english=definition,referenceIpa=ipa,forms=forms.get(key,[word]),content=content))
    words.sort(key=lambda w:w['rank'])
    assert len(words)==2809 and len({w['id'] for w in words})==2809
    assert {w['rank'] for w in words}==set(range(1,2810))
    assert all(w['chinese'] and w['english'] and w['referenceIpa'] for w in words)
    target=ROOT/'app/assets/content/ngsl.json'
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(dict(version='NGSL 1.2',count=len(words),words=words),ensure_ascii=False,separators=(',',':'))+'\n')
    (ROOT/'data/provenance.json').write_text(json.dumps({
      'version':'NGSL 1.2','count':len(words),'license':'CC BY-SA 4.0',
      'authors':['Charles Browne','Brent Culligan','Joseph Phillips'],
      'source':'https://www.newgeneralservicelist.com/new-general-service-list',
      'learningDictionary':'https://www.linguaeruditio.com/Glossary/NGSL/NGSL_gloss.html',
      'modifications':'Normalized to JSON, joined by headword, added separately identified original learning material.',
      'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in source.iterdir() if p.is_file()},
    },ensure_ascii=False,indent=2)+'\n')
    print('Imported',len(words),'words;',len(curated),'original enriched cards')

if __name__=='__main__': main()
