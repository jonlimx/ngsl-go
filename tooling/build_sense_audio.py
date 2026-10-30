"""Pre-render context-correct readings for common stress-changing homographs.

The general in-app engine stays offline. These small, fixed clips remove its
static-lexicon ambiguity for present/record/object/use/close word-card examples.
Run in the existing Kokoro/Misaki Python environment with a local model path.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', required=True, type=Path)
    parser.add_argument('--words-only', action='store_true')
    args = parser.parse_args()
    import numpy as np
    import onnxruntime as ort
    import soundfile as sf
    from kokoro import KPipeline
    from huggingface_hub import hf_hub_download
    variants = json.loads((ROOT / 'data/kokoro_pronunciations.json').read_text())
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(str(args.model / 'model.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
    speakers = dict(item.split('->') for item in session.get_modelmeta().custom_metadata_map['speaker2id'].split(','))
    voices = np.fromfile(args.model / 'voices.bin', dtype=np.float32).reshape(-1, 510, 256)
    vocabulary = json.loads(Path(hf_hub_download('hexgrad/Kokoro-82M', 'config.json', local_files_only=True)).read_text())['vocab']
    output = ROOT / 'app/assets/audio'
    output.mkdir(exist_ok=True)
    cards = {}
    if not args.words_only:
        for number in range(1, 7):
            cards.update(json.loads((ROOT / f'data/common_senses/senses_{number}.json').read_text()))
    audio = {}
    for accent, language, voice in [('uk', 'b', 'bf_emma'), ('us', 'a', 'af_heart')]:
        pipeline = KPipeline(lang_code=language, model=False, repo_id='hexgrad/Kokoro-82M')

        def render(text, phones):
            if set(phones) - set(vocabulary):
                raise ValueError('Unsupported phonemes: ' + text)
            tokens = [0] + [vocabulary[c] for c in phones] + [0]
            if len(tokens) > 510:
                raise ValueError('Sense audio sentence is too long: ' + text)
            identity = f'sense-kokoro1|misaki|{voice}|{text}|{phones}'
            name = accent + '-' + hashlib.sha256(identity.encode()).hexdigest()[:24] + '.mp3'
            target = output / name
            if not target.exists() or target.stat().st_size <= 512:
                samples = session.run(None, {'tokens': np.array([tokens], dtype=np.int64),
                    'style': voices[int(speakers[voice])][len(tokens) - 2][None, :],
                    'speed': np.array([1.0], dtype=np.float32)})[0].squeeze()
                if not np.isfinite(samples).all() or len(samples) < 1200:
                    raise ValueError('Invalid sense audio: ' + text)
                with tempfile.TemporaryDirectory(prefix='ngsl_sense_audio_') as temporary:
                    wav = Path(temporary) / 'speech.wav'
                    sf.write(wav, samples, 24000)
                    pending = target.with_suffix('.pending.mp3')
                    subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-i', str(wav),
                        '-ac', '1', '-ar', '24000', '-codec:a', 'libmp3lame', '-b:a', '64k', str(pending)], check=True)
                    pending.replace(target)
            return 'assets/audio/' + name

        for variant in variants.values():
            variant[accent + 'Audio'] = render(variant['word'] + ':' + variant['pos'], variant[accent + 'Phones'])
        for word_id, card in cards.items():
            head = word_id.removeprefix('ngsl12:')
            for sense in [*card['senses'], *[p for p in card['phrases'] if p.get('pronunciationKey')]]:
                key = sense.get('pronunciationKey', head + '.' + sense.get('pos', ''))
                if key not in variants:
                    continue
                text = sense['exampleEnglish']
                phones, tokens = pipeline.g2p(text)
                # Context tagging alone confuses e.g. lead (metal) and minute
                # (tiny). Apply the checked meaning-specific pronunciation to
                # the target token; keep the rest of the sentence contextual.
                targets = [token for token in tokens if token.text.lower() == head]
                # Inflected tokens (e.g. leading, recorded) retain Misaki's
                # contextual inflected pronunciation rather than losing the
                # ending by replacing them with the bare headword.
                for token in targets:
                    token.phonemes = variants[key][accent + 'Phones']
                phones = ''.join((token.phonemes or '') + token.whitespace for token in tokens).strip()
                entry_id = sense.get('id') or 'phrase:' + sense['phrase']
                audio.setdefault(word_id, {}).setdefault(entry_id, {
                    'exampleSha256': hashlib.sha256(text.encode()).hexdigest(),
                })[accent + 'Audio'] = render(text, phones)
        print('Rendered/verified homograph clips', accent, flush=True)
    (ROOT / 'data/kokoro_pronunciations.json').write_text(json.dumps(variants, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'app/lib/kokoro_pronunciation.dart').write_text(
        '// Generated from data/kokoro_pronunciations.json; Kokoro/Misaki context checks.\n'
        'const kokoroPronunciations = <String, Map<String, String>>' +
        json.dumps(variants, ensure_ascii=False, indent=2) + ';\n')
    if not args.words_only:
        (ROOT / 'data/sense_audio.json').write_text(json.dumps(audio, ensure_ascii=False, indent=2) + '\n')
    print('Verified POS variants:', len(variants), 'example senses:', sum(len(row) for row in audio.values()), flush=True)


if __name__ == '__main__':
    main()
