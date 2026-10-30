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
from word_material import additions, validate_material, load_offline_cards
from common_senses import load_common_senses

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
    material=json.loads((ROOT/'data/fce_enrichment.json').read_text())
    corrections=json.loads((ROOT/'data/lexical_corrections.json').read_text())['words']
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
        content={**curated.get(key,{}),**corrections.get(key,{}),**audio.get('ngsl12:'+key,{})}
        alternatives=us_ipa.get(word.lower(),'').split(', ')
        if alternatives != ['']:
            generated=normalized(content.get('usIpa',ipa))
            content['usIpa']=max(alternatives,key=lambda x:difflib.SequenceMatcher(None,normalized(x),generated).ratio())
        words.append(dict(id='ngsl12:'+key,word=word,rank=rank[key],pos=pos,chinese=translations[word.lower()],english=definition,referenceIpa=ipa,forms=forms.get(key,[word]),content=content))
    words.sort(key=lambda w:w['rank'])
    assert len(words)==2809 and len({w['id'] for w in words})==2809
    assert {w['rank'] for w in words}==set(range(1,2810))
    assert all(w['chinese'] and w['english'] and w['referenceIpa'] for w in words)
    validate_material(material, words)
    offline_cards = load_offline_cards(ROOT/'data/offline_batches', words)
    common_senses = load_common_senses(ROOT/'data/common_senses', words)
    sense_audio_path = ROOT / 'data/sense_audio.json'
    sense_audio = json.loads(sense_audio_path.read_text()) if sense_audio_path.exists() else {}
    for word_id, card in common_senses.items():
        for sense in [*card['senses'], *card['phrases']]:
            entry_id = sense.get('id') or 'phrase:' + sense['phrase']
            clip = sense_audio.get(word_id, {}).get(entry_id)
            if clip and clip['exampleSha256'] == hashlib.sha256(sense['exampleEnglish'].encode()).hexdigest():
                for accent in ['uk', 'us']:
                    assert (ROOT / 'app' / clip[accent + 'Audio']).is_file()
                    sense[accent + 'Audio'] = clip[accent + 'Audio']
    for word in words:
        # Offline material is bundled first; existing authored examples and
        # pronunciation assets retain priority over the new teaching additions.
        word['content']={**additions(word, material),**word['content'],**offline_cards[word['id']],
          **common_senses[word['id']], 'offlineCardVersion': 'original-b1-b2-v2'}
    target=ROOT/'app/assets/content/ngsl.json'
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(dict(version='NGSL 1.2',count=len(words),words=words),ensure_ascii=False,separators=(',',':'))+'\n')
    (ROOT/'data/provenance.json').write_text(json.dumps({
      'version':'NGSL 1.2','count':len(words),'license':'CC BY-SA 4.0',
      'authors':['Charles Browne','Brent Culligan','Joseph Phillips'],
      'source':'https://www.newgeneralservicelist.com/new-general-service-list',
      'learningDictionary':'https://www.linguaeruditio.com/Glossary/NGSL/NGSL_gloss.html',
      'modifications':'Normalized to JSON, joined by headword, added separately identified original learning material and offline B2 First word-family/inflection notes.',
      'offlineLearningMaterial':{
        'source':'data/fce_enrichment.json',
        'sha256':hashlib.sha256((ROOT/'data/fce_enrichment.json').read_bytes()).hexdigest(),
        'license':'CC BY-SA 4.0',
        'examReference':material['examReference'],
        'note':material['note'],
      },
      'completeOfflineCards': {
        'source': 'data/offline_batches/cards_*.json',
        'count': len(offline_cards),
        'license': 'CC BY-SA 4.0',
        'method': 'Original model-authored B1-B2 contextual examples and bilingual collocations, generated once and validated before bundling. No Tatoeba or dictionary example sentences are used.',
        'scope': 'One 14-32 word English sentence, Chinese translation, and two distinct bilingual collocations per official NGSL ID. Optional corrected Chinese gloss is kept separate from the original source gloss.',
        'hashes': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'data/offline_batches').glob('cards_*.json'))},
      },
      'lexicalCorrections': {
        'source': 'data/lexical_corrections.json',
        'sha256': hashlib.sha256((ROOT/'data/lexical_corrections.json').read_bytes()).hexdigest(),
        'note': 'Corrected display POS/English definition where the original gloss and label disagree. The original fields and word IDs are preserved.',
      },
      'commonMeanings': {
        'source': 'data/common_senses/senses_*.json',
        'words': len(common_senses),
        'senses': sum(len(card['senses']) for card in common_senses.values()),
        'phrases': sum(len(card['phrases']) for card in common_senses.values()),
        'note': 'Original learner-focused common meanings, grouped by part of speech, and independently explained fixed phrases. Each meaning has a bilingual B1-B2 example and usage pattern. This is not an exhaustive historical dictionary.',
        'license': 'CC BY-SA 4.0',
        'hashes': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'data/common_senses').glob('senses_*.json'))},
      },
      'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in source.iterdir() if p.is_file()},
    },ensure_ascii=False,indent=2)+'\n')
    print('Imported',len(words),'words;',sum(bool(w['content'].get('exampleEnglish')) for w in words),'offline example cards;',sum(bool(w['content'].get('inflections')) for w in words),'inflection cards;',sum(bool(w['content'].get('wordFamily')) for w in words),'word-family cards')

if __name__=='__main__': main()
