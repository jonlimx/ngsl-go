"""Check bundled teaching data and reject mismatched generated material."""

import copy
import csv
import json
from pathlib import Path
import unittest

from word_material import additions, validate_material, validate_offline_cards, load_offline_cards
from common_senses import load_common_senses, validate_common_senses

ROOT = Path(__file__).resolve().parents[1]


class WordMaterialTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.material = json.loads((ROOT / 'data/fce_enrichment.json').read_text())
        cls.words = json.loads((ROOT / 'app/assets/content/ngsl.json').read_text())['words']
        cls.catalog = {word['word']: word for word in cls.words}

    def test_entire_library_keeps_official_ids_and_offline_english_definitions(self):
        validate_material(self.material, self.words)
        source = ROOT / 'data/source/NGSL_12_stats.csv'
        with source.open(encoding='utf-8-sig') as stream:
            expected = {'ngsl12:' + row['Lemma'].lower().replace('e-mail', 'email') for row in csv.DictReader(stream)}
        self.assertEqual({word['id'] for word in self.words}, expected)
        self.assertEqual(len(self.words), 2809)
        corrections = json.loads((ROOT / 'data/lexical_corrections.json').read_text())['words']
        self.assertTrue(all(word['content']['english'] == corrections.get(word['word'], {}).get('english', word['english']) and word['english'].strip() for word in self.words))

    def forms(self, head, label):
        return next(item['forms'] for item in additions(self.catalog[head], self.material)['inflections'] if item['label'] == label)

    def test_irregular_forms_and_homographs_keep_the_target_sense(self):
        self.assertEqual(self.forms('go', '过去式'), ['went'])
        self.assertEqual(self.forms('go', '过去分词'), ['gone'])
        self.assertEqual(self.forms('find', '过去分词'), ['found'])
        self.assertEqual(self.forms('found', '过去分词'), ['founded'])
        self.assertEqual(self.forms('lie', '过去分词'), ['lied'])
        self.assertNotIn('inflections', additions(self.catalog['bear'], self.material))

    def test_adjective_forms_do_not_use_unrelated_verbal_inflections(self):
        self.assertEqual(self.forms('light', '比较级'), ['lighter'])
        self.assertEqual(self.forms('light', '最高级'), ['lightest'])
        light = additions(self.catalog['light'], self.material)['inflections']
        self.assertFalse(any(item['label'] == '过去式' for item in light))
        self.assertEqual(self.forms('good', '比较级'), ['better'])

    def test_word_families_antonyms_and_usage_are_separate(self):
        happy = additions(self.catalog['happy'], self.material)
        family = {item['word'] for item in happy['wordFamily']}
        self.assertTrue({'happiness', 'happily', 'unhappy'} <= family)
        self.assertIn('unhappy', {item['word'] for item in happy['antonyms']})
        self.assertTrue(all(item['note'] for item in happy['antonyms']))
        valuable = additions(self.catalog['valuable'], self.material)
        self.assertIn('invaluable', {item['word'] for item in valuable['wordFamily']})
        self.assertNotIn('invaluable', {item['word'] for item in valuable.get('antonyms', [])})

    def test_formation_examples_require_changed_stems_and_real_family_members(self):
        self.assertGreaterEqual(len(self.material['exercises']), 30)
        for item in self.material['exercises']:
            self.assertNotEqual(item['stem'], item['answer'])
        bad = copy.deepcopy(self.material)
        bad['exercises'][0]['answer'] = 'inventedword'
        with self.assertRaises(AssertionError):
            validate_material(bad, self.words)

    def test_wrong_target_example_and_missing_translation_are_rejected(self):
        for replacement in [{'exampleEnglish': 'She read a book.'}, {'exampleChinese': ''}]:
            bad = copy.deepcopy(self.material)
            bad['usage']['decide'].update(replacement)
            with self.assertRaises(AssertionError):
                validate_material(bad, self.words)

    def test_all_words_have_contextual_bilingual_examples_and_two_translated_patterns(self):
        cards = load_offline_cards(ROOT / 'data/offline_batches', self.words)
        self.assertEqual(len(cards), 2809)
        for word in self.words:
            card = cards[word['id']]
            for key in ['exampleEnglish', 'exampleChinese', 'collocations']:
                self.assertEqual(word['content'][key], card[key], (word['id'], key))

    def test_common_meanings_and_phrases_are_complete_and_imported(self):
        cards = load_common_senses(ROOT / 'data/common_senses', self.words)
        self.assertEqual(len(cards), 2809)
        for word in self.words:
            source = cards[word['id']]
            for section in ['senses', 'phrases']:
                for actual, expected in zip(word['content'][section], source[section]):
                    for key, value in expected.items():
                        self.assertEqual(actual[key], value, (word['id'], key))
                self.assertEqual(len(word['content'][section]), len(source[section]))

    def test_present_and_homographs_keep_meanings_patterns_and_pronunciation_separate(self):
        present = self.catalog['present']['content']
        self.assertEqual({s['pos'] for s in present['senses']}, {'noun', 'adj', 'verb'})
        self.assertIn('at present', {p['phrase'] for p in present['phrases']})
        self.assertEqual(next(s for s in present['senses'] if s['id'] == 'show')['ukIpa'], '/prɪˈzent/')
        self.assertEqual(next(s for s in present['senses'] if s['pos'] == 'noun')['ukIpa'], '/ˈprezənt/')
        variants = json.loads((ROOT / 'data/kokoro_pronunciations.json').read_text())
        clips = json.loads((ROOT / 'data/sense_audio.json').read_text())
        import hashlib
        for word in self.words:
            for sense in word['content']['senses']:
                key = sense.get('pronunciationKey', word['word'].lower() + '.' + sense['pos'])
                if key not in variants:
                    continue
                clip = clips[word['id']][sense['id']]
                self.assertEqual(clip['exampleSha256'], hashlib.sha256(sense['exampleEnglish'].encode()).hexdigest())
                for accent in ['uk', 'us']:
                    self.assertTrue((ROOT / 'app' / variants[key][accent + 'Audio']).is_file())
                    self.assertEqual(sense[accent + 'Audio'], clip[accent + 'Audio'])
                    self.assertTrue((ROOT / 'app' / clip[accent + 'Audio']).is_file())

    def test_invalid_meanings_are_rejected_before_import(self):
        word = self.catalog['present']
        card = {'senses': copy.deepcopy(word['content']['senses']), 'phrases': copy.deepcopy(word['content']['phrases'])}
        for mutate in [
            lambda c: c['senses'].clear(),
            lambda c: c['senses'][0].update(pos='invented'),
            lambda c: c['senses'][0].update(exampleChinese=''),
            lambda c: c['senses'][0].update(exampleEnglish='This example does not contain any form of the required target vocabulary word at all.'),
            lambda c: c['senses'].append(copy.deepcopy(c['senses'][0])),
            lambda c: c['phrases'][0].update(phrase='a different phrase'),
        ]:
            bad = copy.deepcopy(card)
            mutate(bad)
            with self.assertRaises(AssertionError):
                validate_common_senses({word['id']: bad}, [word])

    def test_offline_import_rejects_incomplete_coverage_trivial_sentences_and_bad_patterns(self):
        words = self.words[:1]
        cards = {words[0]['id']: {
            'exampleEnglish': 'Although the museum was crowded, we waited patiently until the guide showed us a quieter room.',
            'exampleChinese': '虽然博物馆人很多，我们还是耐心等待，直到导游带我们去了一个更安静的房间。',
            'collocations': [{'english': 'the museum', 'chinese': '这家博物馆'}, {'english': 'the guide', 'chinese': '这位导游'}],
        }}
        validate_offline_cards(cards, words)
        for mutate in [
            lambda c: c.clear(),
            lambda c: c[words[0]['id']].update(exampleEnglish='The room is big.'),
            lambda c: c[words[0]['id']]['collocations'][0].update(english='a museum'),
            lambda c: c[words[0]['id']]['collocations'][0].update(chinese=''),
        ]:
            bad = copy.deepcopy(cards)
            mutate(bad)
            with self.assertRaises(AssertionError):
                validate_offline_cards(bad, words)


if __name__ == '__main__':
    unittest.main(verbosity=2)
