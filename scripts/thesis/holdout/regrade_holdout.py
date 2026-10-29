# Thesis fork: grades the EU holdout runs again from their logs, with the grading fixes found after
# 2.11.15 (FORK_CHANGES 2.11.16), the same way for every system. The data file stays where it is
# (`rag-tests/eu_data.json`, never copied into the repository); this script holds no questions or
# answers and prints counts only. It also writes a grading sheet for a person to grade each answer.
#
# Fixes over the developer's grading (which is kept as "v1" for comparison):
#   1. A Greek question also accepts the English expected terms (`any`), and an answer in English
#      to a Greek question is counted separately as a language mismatch.
#   2. A question without expected terms is "ungraded" (left to the person), not passed.
#   3. A refusal is recognized when the answer, after a "[Needs Verification]" banner, opens by
#      saying the passages don't address the topic ("is not explicitly addressed", "do not contain
#      any information", Greek «δεν αναφέρεται», …), unless that sentence goes on with "but/however".
#   4. "strict": the expected term must be in the answer's first paragraph, so a figure mentioned in
#      passing later doesn't pass a wrong main answer (crude; the person's grade is the final one).
#
# Usage: python3 regrade_holdout.py <eu_data.json> <out-dir> <name>=<log> [<name>=<log> ...]
import csv, json, re, sys

data = json.load(open(sys.argv[1]))
out_dir = sys.argv[2]
systems = [arg.split("=", 1) for arg in sys.argv[3:]]
labels = ["English passages, English questions", "Greek passages, English questions", "Greek passages, Greek questions"]
line_re = re.compile(r"^\[EUHoldout\] (" + "|".join(map(re.escape, labels)) + r") (Q\d\d) (.*)$")

# The app's "needs verification" banner and the fixed sentence after it.
BANNER = re.compile(r"^\W*(?:\*\*)?\[?\s*needs verification\s*\]?(?:\*\*)?\s*"
                    r"(?:this answer was drafted but could not be (?:strictly )?verified[^:]*:)?\W*", re.I)
REFUSAL = re.compile(
    r"\b(?:is|are|was|were)\s+not\s+(?:explicitly\s+|directly\s+|specifically\s+|clearly\s+)?"
    r"(?:addressed|mentioned|covered|specified|stated|provided|included|discussed|defined)\b"
    r"|\b(?:do|does)\s+not\s+(?:explicitly\s+|directly\s+|specifically\s+)?"
    r"(?:contain|address|mention|specify|provide|state|include|cover|define)\b"
    r"|\bno\s+(?:information|mention|details?)\b|\binsufficient\s+(?:evidence|information)\b"
    r"|\bnot\s+enough\s+(?:evidence|information)\b|\bcannot\s+(?:be\s+)?(?:answer|determine)"
    r"|δεν\s+(?:αναφέρ|περιέχ|προβλέπ|καθορίζ|διευκρινίζ|παρέχ|υπάρχ\w*\s+(?:πληροφορ|στοιχεί))"
    r"|δεν\s+βρέθηκαν", re.I)
QUALIFIER = re.compile(r"\b(?:but|however|although|though|except)\b|\bαλλά\b|\bωστόσο\b|\bεκτός\b", re.I)


def has_word(text, word):
    return re.search(r"(?<![0-9A-Za-z])" + re.escape(word.lower()) + r"(?![0-9A-Za-z])", text.lower()) is not None


def has_term(text, term):
    closed = term.isdigit()
    return re.search(r"(?<![\w])" + re.escape(term.lower()) + (r"(?![\w])" if closed else ""), text.lower()) is not None


def greek_ratio(text):
    letters = [c for c in text if c.isalpha()]
    return sum("Ͱ" <= c <= "Ͽ" or "ἀ" <= c <= "῿" for c in letters) / max(1, len(letters))


def refuses(answer):
    text = BANNER.sub("", answer.strip())
    first = re.split(r"(?<=[.;!?])\s+", text, maxsplit=1)[0]
    return REFUSAL.search(first) is not None and QUALIFIER.search(first) is None


def first_paragraph(answer):
    text = BANNER.sub("", answer.strip())
    return re.split(r"\s{2,}|\n\s*\n|(?<=[.;!?])\s+(?=[-•*]|\d+\.)", text, maxsplit=1)[0]


def parse(path):
    runs = {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        m = line_re.match(raw.rstrip("\n"))
        if not m:
            continue
        label, q, rest = m.groups()
        if rest.startswith("no answer"):
            status, _, answer = rest.partition(" | ")
            runs[(label, q)] = ("declined" in status and "ANSWERED" not in status, answer.strip())
        else:
            parts = rest.split(" | ", 2)
            runs[(label, q)] = (parts[1] == "answer DECLINED", parts[2].strip() if len(parts) > 2 else "")
    return runs


rows, summary = [], []
for name, path in systems:
    runs = parse(path)
    for label in labels:
        greek_q = label.endswith("Greek questions")
        c = dict(v1_right=0, v2_right=0, strict_right=0, answerable=0, ungraded=0, unanswerable=0,
                 v1_declined=0, v2_declined=0, v2_false_declines=0, english_answers=0, missing=0)
        for i, item in enumerate(data["questions"]):
            q = f"Q{i + 1:02d}"
            if (label, q) not in runs:
                c["missing"] += 1
                continue
            v1_declined, answer = runs[(label, q)]
            v2_declined = v1_declined or refuses(answer)
            english = greek_q and not v2_declined and greek_ratio(answer) < 0.3
            c["english_answers"] += english
            if item["passage"] == 0:
                c["unanswerable"] += 1
                c["v1_declined"] += v1_declined
                c["v2_declined"] += v2_declined
                v1, v2, strict = ("declined" if v1_declined else "answered"), ("declined" if v2_declined else "answered"), ""
            else:
                c["answerable"] += 1
                v1_terms = (item.get("any_el") if greek_q else item.get("any")) or []
                v1_ok = not v1_declined and (not v1_terms or any(
                    (has_term if greek_q else has_word)(answer, t) for t in v1_terms))
                terms = list(v1_terms) + (list(item.get("any") or []) if greek_q else [])
                match = lambda text: any(has_term(text, t) if re.search(r"[Ͱ-Ͽ]", t) else has_word(text, t) for t in terms)
                c["v1_right"] += v1_ok
                if v2_declined:
                    c["v2_false_declines"] += 1
                    v2 = strict = "declined"
                elif not terms:
                    c["ungraded"] += 1
                    v2 = strict = "ungraded"
                else:
                    v2 = "right" if match(answer) else "wrong"
                    strict = "right" if match(first_paragraph(answer)) else "wrong"
                    c["v2_right"] += v2 == "right"
                    c["strict_right"] += strict == "right"
                v1 = "right" if v1_ok else ("declined" if v1_declined else "wrong")
            rows.append([name, label, q, "no answer in text" if item["passage"] == 0 else f"passage {item['passage']}",
                         v1, v2, strict, "English" if english else "", ""])
        summary.append((name, label, c))

with open(f"{out_dir}/holdout_grading_sheet.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["system", "condition", "question", "expected", "auto_v1 (developer)", "auto_v2 (fixed)",
                "auto_v2 strict (first paragraph)", "answer language", "your grade (right / wrong / declined / right but English)"])
    w.writerows(rows)
for name, label, c in summary:
    print(f"{name} | {label} | v1 right {c['v1_right']}/{c['answerable']} declined {c['v1_declined']}/{c['unanswerable']}"
          f" | v2 right {c['v2_right']}/{c['answerable']} (strict {c['strict_right']}), ungraded {c['ungraded']},"
          f" declined {c['v2_declined']}/{c['unanswerable']}, answerable declined {c['v2_false_declines']},"
          f" English answers {c['english_answers']}, missing {c['missing']}")
