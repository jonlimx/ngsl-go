"""Build deterministic offline teaching additions; no runtime AI requests."""

import re
import json
from pathlib import Path


def load_offline_cards(directory, words):
    cards = {}
    for number in range(1, 7):
        batch = json.loads((Path(directory) / f'cards_{number}.json').read_text())
        overlap = cards.keys() & batch.keys()
        assert not overlap, ('duplicate offline IDs', overlap)
        cards.update(batch)
    validate_offline_cards(cards, words)
    return cards


def validate_offline_cards(cards, words):
    catalog = {word['id']: word for word in words}
    assert set(cards) == set(catalog), ('offline coverage', set(catalog) - set(cards), set(cards) - set(catalog))
    sentences = set()
    for word_id, card in cards.items():
        word = catalog[word_id]
        forms = {word['word'], *word['forms']}
        sentence = card['exampleEnglish']
        assert isinstance(sentence, str) and 14 <= len(sentence.split()) <= 32, (word_id, 'sentence length', sentence)
        unquoted = sentence.strip('\"\'\u201c\u201d\u2018\u2019')
        assert unquoted[0].isupper() and unquoted[-1] in '.?!', (word_id, 'complete sentence')
        assert contains_form(sentence, forms), (word_id, 'example target')
        assert sentence.casefold() not in sentences, (word_id, 'duplicate example')
        sentences.add(sentence.casefold())
        assert re.search(r'[\u4e00-\u9fff]', card['exampleChinese']), (word_id, 'Chinese example')
        phrases = card['collocations']
        assert len(phrases) >= 2, (word_id, 'two collocations')
        assert len({p['english'].casefold() for p in phrases}) == len(phrases), (word_id, 'duplicate collocations')
        for phrase in phrases:
            assert len(phrase['english'].split()) >= 2, (word_id, phrase)
            assert contains_form(phrase['english'], forms), (word_id, 'collocation target', phrase)
            assert re.search(r'[\u4e00-\u9fff]', phrase['chinese']), (word_id, 'collocation translation')
        for text in [sentence, card['exampleChinese'], *(p[k] for p in phrases for k in ['english', 'chinese'])]:
            assert text.strip() == text and not re.search(r'[\x00-\x1f]|___|TODO|PLACEHOLDER|https?://', text, re.I), (word_id, 'placeholder/control character')


def contains_form(text, forms):
    return any(re.search(r"(?<![a-z])" + re.escape(form.lower()) + r"(?![a-z])", text.lower()) for form in forms)


def validate_material(material, words):
    catalog = {word["word"].lower(): word for word in words}
    family_index = {}
    for family in material["families"]:
        assert len(family) >= 2
        assert len({entry["word"] for entry in family}) == len(family)
        for entry in family:
            assert entry["pos"] in {"n", "v", "adj", "adv"}
            assert entry["chinese"].strip()
            assert re.fullmatch(r"[a-z]+(?:[-'][a-z]+)*", entry["word"])
            family_index.setdefault(entry["word"], []).extend(family)
    for head, item in material["usage"].items():
        assert all(isinstance(note, str) and note.strip() for note in item.get("usageNotes", []))
        if "exampleEnglish" not in item:
            continue
        assert item["exampleChinese"].strip()
        forms = catalog.get(head, {}).get("forms", [head])
        assert contains_form(item["exampleEnglish"], forms), head
        assert len(item["collocations"]) >= 2
        for phrase in item["collocations"]:
            assert phrase["chinese"].strip()
            assert contains_form(phrase["english"], forms), (head, phrase)
    for item in material["exercises"]:
        assert item["prompt"].count("___") == 1
        assert item["chinese"].strip() and item["explanation"].strip()
        family = family_index[item["stem"]]
        allowed = {entry["word"] for entry in family}
        allowed.update(entry["word"] + "s" for entry in family if entry["pos"] == "n")
        assert item["answer"] in allowed, item
        assert item["stem"] != item["answer"], item
    for pair in material["antonymPairs"]:
        assert pair["left"] != pair["right"]
        assert all(pair[key].strip() for key in ["leftChinese", "rightChinese", "note"])


def additions(word, material):
    head = word["word"].lower()
    pos = word.get('content', {}).get('pos', word["pos"])
    forms = word["forms"]
    result = {"english": word["english"], **material["usage"].get(head, {})}
    family = {}
    for group in material["families"]:
        if any(entry["word"] == head for entry in group):
            for entry in group:
                if entry["word"] != head:
                    family[entry["word"]] = entry
    if family:
        result["wordFamily"] = list(family.values())
    opposites = []
    for pair in material["antonymPairs"]:
        if pair["left"] == head:
            opposites.append({"word": pair["right"], "chinese": pair["rightChinese"], "note": pair["note"]})
        elif pair["right"] == head:
            opposites.append({"word": pair["left"], "chinese": pair["leftChinese"], "note": pair["note"]})
    if opposites:
        result["antonyms"] = opposites

    inflections = []
    if "verb" in pos or pos == "v, n":
        third = [form for form in forms if form != head and form in {
            head + "s", head + "es", head[:-1] + "ies" if head.endswith("y") else "",
        }]
        if head == "be":
            inflections.append({"label": "现在时", "forms": ["am", "is", "are"]})
        elif head == "have":
            third = ["has"]
        if third:
            inflections.append({"label": "第三人称单数", "forms": third})
        present = [form for form in forms if form.endswith("ing") and form != head]
        if present:
            inflections.append({"label": "现在分词 / 动名词", "forms": present})
        irregular = material["irregularVerbs"].get(head)
        if irregular:
            inflections.extend([
                {"label": "过去式", "forms": irregular["past"]},
                {"label": "过去分词", "forms": irregular["pastParticiple"]},
            ])
        else:
            past = [form for form in forms if form.endswith("ed") and form != head]
            if past:
                inflections.extend([
                    {"label": "过去式", "forms": past},
                    {"label": "过去分词", "forms": past},
                ])
    if "adj" in pos:
        irregular = material["adjectiveComparisons"].get(head)
        if irregular:
            comparative, superlative = irregular["comparative"], irregular["superlative"]
        else:
            comparative = [form for form in forms if form != head and form.endswith("er")]
            superlative = [form for form in forms if form != head and form.endswith("est")]
        if comparative and superlative:
            inflections.extend([
                {"label": "比较级" + ("（" + irregular["sense"] + "）" if irregular and irregular.get("sense") else ""), "forms": comparative},
                {"label": "最高级" + ("（" + irregular["sense"] + "）" if irregular and irregular.get("sense") else ""), "forms": superlative},
            ])
    if inflections:
        result["inflections"] = inflections
    exercise = next((item for item in material["exercises"] if item["stem"] == head), None)
    if exercise:
        result["wordFormation"] = exercise
    return result
