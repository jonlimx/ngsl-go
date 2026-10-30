"""Validate all authored common meanings before they can enter the word asset."""
import json
import re
from pathlib import Path
from word_material import contains_form

PARTS = {'noun', 'verb', 'adj', 'adv', 'pron', 'det', 'prep', 'conj', 'aux', 'number', 'interjection'}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def validate_common_senses(cards, words):
    catalog = {word['id']: word for word in words}
    assert set(cards) == set(catalog), ('common-sense IDs', set(catalog) - set(cards), set(cards) - set(catalog))
    for word_id, card in cards.items():
        word = catalog[word_id]
        forms = {word['word'], *word['forms']}
        senses = card['senses']
        assert isinstance(senses, list) and senses, (word_id, 'no common meaning')
        assert len({sense['id'] for sense in senses}) == len(senses), (word_id, 'duplicate sense IDs')
        assert len({(sense['pos'], sense['chinese'], sense['english']) for sense in senses}) == len(senses), (word_id, 'duplicate meanings')
        for sense in senses:
            assert re.fullmatch('[a-z0-9]+(?:[-_.][a-z0-9]+)*', sense['id']), (word_id, sense['id'])
            assert sense['pos'] in PARTS, (word_id, sense['pos'])
            sense_forms = forms | set(sense.get('forms', []))
            validate_entry(sense, sense_forms, word_id)
            assert sense['collocations'], (word_id, sense['id'], 'no pattern')
            for phrase in sense['collocations']:
                assert len(phrase['english'].split()) >= 2, (word_id, 'pattern is not a collocation')
                assert contains_form(phrase['english'], sense_forms), (word_id, sense['id'], phrase)
                assert re.search('[\u4e00-\u9fff]', phrase['chinese']), (word_id, 'pattern translation')
            for item in sense.get('inflections', []):
                assert item['label'].strip() and item['forms'], (word_id, 'inflection')
                assert all(re.fullmatch("[a-z]+(?:[-'][a-z]+)*", form) for form in item['forms']), (word_id, 'invalid form')
            assert all(isinstance(note, str) and note.strip() for note in sense.get('usageNotes', [])), (word_id, 'usage note')
        phrases = card['phrases']
        assert isinstance(phrases, list)
        assert len({(phrase['phrase'], phrase['chinese']) for phrase in phrases}) == len(phrases), (word_id, 'duplicate phrase meanings')
        for phrase in phrases:
            assert len(phrase['phrase'].split()) >= 2 and contains_form(phrase['phrase'], forms), (word_id, phrase)
            validate_entry(phrase, forms, word_id)


def validate_entry(entry, forms, word_id):
    for key in ['chinese', 'english', 'exampleEnglish', 'exampleChinese']:
        value = entry[key]
        assert isinstance(value, str) and value.strip() == value and value, (word_id, key)
        assert not re.search(r'[\x00-\x1f]|___|TODO|PLACEHOLDER|https?://', value, re.I), (word_id, key, 'placeholder')
    assert re.search('[\u4e00-\u9fff]', entry['chinese']) and re.search('[\u4e00-\u9fff]', entry['exampleChinese']), (word_id, 'Chinese translation')
    sentence = entry['exampleEnglish']
    assert 14 <= len(sentence.split()) <= 32, (word_id, 'example length', sentence)
    unquoted = sentence.strip('\"\'“”‘’')
    assert unquoted[0].isupper() and unquoted[-1] in '.?!', (word_id, 'sentence punctuation')
    assert contains_form(sentence, forms), (word_id, 'example misses target', sentence)


def load_common_senses(directory, words):
    result = {}
    for number in range(1, 7):
        batch = json.loads((Path(directory) / f'senses_{number}.json').read_text(), object_pairs_hook=unique_object)
        assert not (result.keys() & batch.keys()), 'Duplicate common-sense word ID'
        result.update(batch)
    validate_common_senses(result, words)
    return result
