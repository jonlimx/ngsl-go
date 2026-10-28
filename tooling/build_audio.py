"""Pre-generate NGSL word audio with the same Kokoro/Misaki pipeline as FCE Go.

Only MP3 clips and pronunciation metadata are shipped, never model weights.
Usage: python tooling/build_audio.py --model /path/to/kokoro-multi-lang-v1_0
"""
import argparse, concurrent.futures, hashlib, json, re, subprocess, tempfile, threading, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--model',type=Path,required=True);parser.add_argument('--workers',type=int,default=4);parser.add_argument('--limit',type=int)
    args=parser.parse_args()
    import numpy as np, onnxruntime as ort, soundfile as sf
    from kokoro import KPipeline
    words=json.loads((ROOT/'app/assets/content/ngsl.json').read_text())['words']
    if args.limit:words=words[:args.limit]
    options=ort.SessionOptions();options.intra_op_num_threads=2
    check=ort.InferenceSession(str(args.model/'model.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
    mapping=dict(item.split('->') for item in check.get_modelmeta().custom_metadata_map['speaker2id'].split(','))
    voices=np.fromfile(args.model/'voices.bin',dtype=np.float32).reshape(-1,510,256)
    from huggingface_hub import hf_hub_download
    vocab=json.loads(Path(hf_hub_download('hexgrad/Kokoro-82M','config.json',local_files_only=True)).read_text())['vocab']
    output=ROOT/'app/assets/audio';output.mkdir(exist_ok=True)
    metadata={};jobs=[]
    special={'read':'I read every day.','live':'They live here.','lead':'They lead the team.','wind':'The wind is strong.','close':'They stood close together.','use':'They use the room.','present':'It is present.','record':'The record is new.','minute':'Wait a minute.','object':'The object is small.'}
    started=time.time()
    for accent,lang,voice_name in [('uk','b','bf_emma'),('us','a','af_heart')]:
        pipeline=KPipeline(lang_code=lang,model=False,repo_id='hexgrad/Kokoro-82M')
        for w in words:
            word=w['word'];pos=w['pos'].split(',')[0]
            context=special.get(word.lower()) or (f'They {word} every day.' if pos=='verb' else f'It is {word}.' if pos=='adj' else f'The {word}.' if pos=='noun' else word)
            phonemes,tokens=pipeline.g2p(context)
            matched=[t.phonemes or '' for t in tokens if t.text.lower()==word.lower()]
            phone=''.join(matched) if matched else pipeline.g2p(word)[0]
            if word.lower()=='read':phone='ɹˈiːd' if accent=='uk' else 'ɹˈid'
            if not phone:raise ValueError('Missing pronunciation: '+word)
            # Misaki uses compact Kokoro symbols for diphthongs and flapped t.
            ipa=phone.translate(str.maketrans({'A':'eɪ','I':'aɪ','O':'əʊ' if accent=='uk' else 'oʊ','Q':'əʊ','Y':'ɔɪ','W':'aʊ','T':'ɾ','ᵻ':'ɪ'}))
            if re.search('[A-Z]',ipa):raise ValueError('Unmapped phoneme: '+word+' '+ipa)
            identity=f'kokoro1|misaki|{voice_name}|{word}|{phone}'
            name=f'{accent}-'+hashlib.sha256(identity.encode()).hexdigest()[:24]+'.mp3'
            metadata.setdefault(w['id'],{}).update({accent+'Ipa':'/'+ipa+'/',accent+'Audio':'assets/audio/'+name})
            missing=set(phone)-set(vocab)
            if missing:raise ValueError(f'Unsupported phonemes for {word}: {missing}')
            tokens=[0]+[vocab[c] for c in phone]+[0]
            jobs.append(dict(word=word,accent=accent,name=name,tokens=tokens,voice=int(mapping[voice_name])))
        print('Prepared phonemes',accent,len(words),flush=True)
    (ROOT/'data/pronunciations.json').write_text(json.dumps(metadata,ensure_ascii=False,separators=(',',':'))+'\n')
    local=threading.local()
    def render(job):
        path=output/job['name']
        if path.exists() and path.stat().st_size>512:return
        if not hasattr(local,'session'):local.session=ort.InferenceSession(str(args.model/'model.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
        samples=local.session.run(None,{'tokens':np.array([job['tokens']],dtype=np.int64),'style':voices[job['voice']][len(job['tokens'])-2][None,:],'speed':np.array([1.0],dtype=np.float32)})[0].squeeze()
        if not np.isfinite(samples).all() or len(samples)<1200:raise ValueError('Invalid audio: '+job['word'])
        with tempfile.TemporaryDirectory() as directory:
            wav=Path(directory)/'voice.wav';sf.write(wav,samples,24000)
            pending=path.with_suffix('.pending.mp3')
            subprocess.run(['/opt/homebrew/bin/ffmpeg','-nostdin','-loglevel','error','-y','-i',str(wav),'-ac','1','-ar','24000','-codec:a','libmp3lame','-b:a','64k',str(pending)],check=True)
            pending.replace(path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for index,_ in enumerate(pool.map(render,jobs),1):
            if index%100==0:print(f'{index}/{len(jobs)} clips; {time.time()-started:.1f}s',flush=True)
    (ROOT/'data/audio_manifest.json').write_text(json.dumps({'engine':'Kokoro 1.0','voices':{'uk':'bf_emma','us':'af_heart'},'count':len(jobs),'clips':[{k:v for k,v in j.items() if k!='tokens'} for j in jobs]},ensure_ascii=False,indent=2)+'\n')
    print('Completed',len(jobs),'clips',flush=True)

if __name__=='__main__':main()
