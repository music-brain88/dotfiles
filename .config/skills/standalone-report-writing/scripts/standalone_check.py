#!/usr/bin/env python3
"""standalone_check.py - 配布文書の自立可読性を機械的に点検する。
Mechanical checks for standalone readability of distributed Japanese documents.

検査項目 / Checks:
  MAIN     節の冒頭に主文(句点で終わる文)がなく、表や箇条書きで始まっている
  TAIGEN   本文の行や文が句点で終わらない、または名詞で終わる(体言止め)
  LIST     20 字以上の箇条書き項目が句点で終わらない
  CONTEXT  直前の会話を前提にする語(こっち、先方、例の、さっき など)
  TOUTEN   1 文に読点が 3 つ以上ある
  TSUIKU   「X は A、Y は B」型の並列で動詞がない(対句の疑い)
行に "standalone: ignore" を含む HTML コメントを置くと、その行は検査しない。
重さ: WARN(終了コード 1 の対象)と INFO(確認だけ)。MAIN の箇条書き始まりは INFO。

使い方 / Usage:
  standalone_check.py FILE [FILE ...] [--with-yomiyasu] [--json]
終了コード / Exit code: WARN あり 1、なし 0、ファイルエラー 2
標準ライブラリのみで動作する。
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HEADING = re.compile(r"^#{1,6}\s")
TABLE = re.compile(r"^\s*\|")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+(.*)$")
BLOCKQUOTE = re.compile(r"^\s*>\s?(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
CLOSERS = "）)」』】]*_`\"' 　"
OPENERS = {"（": "）", "(": ")", "「": "」", "『": "』", "【": "】"}
SENTENCE_END = "。！？!?"
HIRAGANA = re.compile(r"[ぁ-ん]")
CONTEXT_WORDS = re.compile(
    r"こっち|あっち|そっち|例の|さっき|先ほどの|前に話した|前回話した|この前の|あの件|その件|くだんの|上で言った|冒頭で言った"
)
# yomiyasu の指摘のうち、本環境の表記と衝突するため読まないもの(SKILL.md「yomiyasu の指摘の読み方」)
YOMIYASU_IGNORE = re.compile(r"半角空白|太字の頻度|箇条書きの比率|「正本」|正本")


IGNORE_MARK = "standalone: ignore"
PARTICLES = set("はがをにでとのへやかもねよな")
TRAILING_PAREN = re.compile(r"\s*[（(][^（）()]*[）)]\s*$")


def strip_closers(s: str) -> str:
    return s.rstrip(CLOSERS)


def strip_trailing_paren(s: str) -> str:
    """文末の括弧書き(補足)を外す。「〜しない(理由)。」の動詞を見るため。"""
    prev = None
    while prev != s:
        prev = s
        s = TRAILING_PAREN.sub("", s)
    return s


def outside_parens(s: str) -> str:
    """括弧と鉤括弧の中身を除いた文字列を返す(読点の数え上げ用)。"""
    out, stack = [], []
    for ch in s:
        if ch in OPENERS:
            stack.append(OPENERS[ch])
            continue
        if stack and ch == stack[-1]:
            stack.pop()
            continue
        if not stack:
            out.append(ch)
    return "".join(out)


def is_verbal(clause: str) -> bool:
    """節が用言で終わるとみなせるか。末尾が平仮名で、助詞ではないとき。"""
    return bool(clause) and bool(HIRAGANA.search(clause[-1])) and clause[-1] not in PARTICLES


def strip_inline(s: str) -> str:
    s = re.sub(r"`[^`]*`", "code", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    return s.strip()


def sentences(text: str):
    """句点で区切った文を返す。括弧の中の句点では切らない。末尾に句点がない残りも 1 文として返す。"""
    buf = ""
    stack = []
    for ch in text:
        buf += ch
        if ch in OPENERS:
            stack.append(OPENERS[ch])
        elif stack and ch == stack[-1]:
            stack.pop()
        elif ch in SENTENCE_END and not stack:
            yield buf.strip(), True
            buf = ""
    rest = buf.strip()
    if rest:
        yield rest, False


def check_file(path: Path):
    findings = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        print(f"{path}: cannot read: {e}", file=sys.stderr)
        return None

    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break

    in_fence = False
    kinds = {}  # line index -> (kind, text)
    for i in range(start, len(lines)):
        raw = lines[i]
        if IGNORE_MARK in raw:
            kinds[i] = ("ignored", "")
            continue
        if FENCE.match(raw):
            in_fence = not in_fence
            kinds[i] = ("fence", "")
            continue
        if in_fence:
            kinds[i] = ("code", "")
            continue
        if not raw.strip():
            kinds[i] = ("blank", "")
        elif HEADING.match(raw):
            kinds[i] = ("heading", raw.strip("# ").strip())
        elif TABLE.match(raw):
            kinds[i] = ("table", raw)
        elif LIST_ITEM.match(raw):
            kinds[i] = ("list", LIST_ITEM.match(raw).group(1))
        elif BLOCKQUOTE.match(raw):
            kinds[i] = ("quote", BLOCKQUOTE.match(raw).group(1))
        else:
            kinds[i] = ("para", raw.strip())

    def add(code, lineno, msg, snippet, severity="WARN"):
        findings.append({
            "file": str(path), "line": lineno + 1, "code": code, "severity": severity,
            "message": msg, "snippet": snippet[:70],
        })

    # MAIN: 節の冒頭
    idx = sorted(kinds)
    for n, i in enumerate(idx):
        kind, _ = kinds[i]
        if kind != "heading":
            continue
        for j in idx[n + 1:]:
            k2, t2 = kinds[j]
            if k2 in ("blank", "fence", "code", "ignored"):
                continue
            if k2 == "heading":
                break  # 空の節(親見出し)は対象外
            if k2 == "table":
                add("MAIN", j, "節の冒頭が表で始まり、表が何を並べているかの主文がない", lines[j].strip())
            elif k2 == "list":
                add("MAIN", j, "節の冒頭が箇条書きで始まる(見出しが主文を兼ねているか確認する)", lines[j].strip(), "INFO")
            elif k2 in ("para", "quote"):
                if not any(e for _, e in sentences(strip_inline(t2))):
                    add("MAIN", j, "節の冒頭の段落が句点で終わる文を含まない", t2)
            break

    # 行単位・文単位の検査
    for i in idx:
        kind, text = kinds[i]
        if kind in ("blank", "heading", "fence", "code", "table", "ignored"):
            if kind == "table" and CONTEXT_WORDS.search(text):
                add("CONTEXT", i, "直前の会話を前提にする語がある", text.strip())
            continue
        plain = strip_inline(text)
        if not plain:
            continue
        unquoted = re.sub(r"「[^」]*」", "「」", plain)
        if CONTEXT_WORDS.search(unquoted):
            add("CONTEXT", i, "直前の会話を前提にする語がある: " + CONTEXT_WORDS.search(unquoted).group(0), plain)

        if kind in ("para", "quote"):
            tail = strip_closers(plain)
            if tail and tail[-1] not in SENTENCE_END:
                add("TAIGEN", i, "本文の行が句点で終わっていない", plain)
        elif kind == "list":
            tail = strip_closers(plain)
            if len(plain) >= 20 and tail and tail[-1] not in SENTENCE_END and not plain.endswith(":"):
                add("LIST", i, "20 字以上の箇条書きが句点で終わっていない(体言止め)", plain)

        for n_sent, (sent, ended) in enumerate(sentences(plain)):
            core = sent[:-1] if ended else sent
            body = strip_closers(strip_trailing_paren(core))
            is_label = kind == "list" and n_sent == 0 and len(body) <= 10
            if ended and body and not HIRAGANA.search(body[-1]) and not is_label:
                add("TAIGEN", i, "文が名詞で終わっている(体言止め)", sent)
            visible = outside_parens(core)
            clauses = [c.strip() for c in visible.split("、") if c.strip()]
            verbal_all = [c for c in clauses if is_verbal(c)]
            verbal_nonfinal = [c for c in clauses[:-1] if is_verbal(c)]
            n_touten = visible.count("、")
            if n_touten >= 3 and len(verbal_all) >= 2 and verbal_nonfinal:
                add("TOUTEN", i, f"読点が {n_touten} つあり、節がつながれている", sent)
            if len(clauses) >= 2:
                pat = re.compile(r"^[^はがをにで]{1,14}は[^は]{1,12}$")
                hit = [c for c in clauses if pat.match(c) and not HIRAGANA.search(c[-1])]
                if len(hit) >= 2:
                    add("TSUIKU", i, "動詞のない「X は A、Y は B」型の並列(対句の疑い)", sent)

    return findings


def find_yomiyasu():
    here = Path(__file__).resolve()
    candidates = [
        here.parents[2] / "yomiyasu" / "scripts" / "yomiyasu_lint.py",
        Path.home() / ".claude" / "skills" / "yomiyasu" / "scripts" / "yomiyasu_lint.py",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def run_yomiyasu(script: Path, path: Path):
    proc = subprocess.run(
        [sys.executable, str(script), str(path), "--json"],
        capture_output=True, text=True,
    )
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(f"  yomiyasu の出力を解釈できない: {proc.stderr.strip()[:200]}")
        return []
    kept = []
    for f in result.get("findings", []):
        msg = f.get("message", "")
        snip = f.get("snippet", "")
        if YOMIYASU_IGNORE.search(msg) or ("正本" in snip and "スロップ" in msg):
            continue
        kept.append(f)
    return kept


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--with-yomiyasu", action="store_true", help="隣の yomiyasu の lint も実行する(読まない指摘は除く)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    all_findings = []
    yomi = []
    had_error = False
    for f in args.files:
        p = Path(f)
        res = check_file(p)
        if res is None:
            had_error = True
            continue
        all_findings.extend(res)
        if args.with_yomiyasu:
            script = find_yomiyasu()
            if script is None:
                print("yomiyasu_lint.py が見つからない(../yomiyasu/scripts または ~/.claude/skills/yomiyasu/scripts)", file=sys.stderr)
            else:
                for y in run_yomiyasu(script, p):
                    y["file"] = str(p)
                    yomi.append(y)

    if args.json:
        print(json.dumps({"findings": all_findings, "yomiyasu": yomi}, ensure_ascii=False, indent=2))
    else:
        if not all_findings:
            print("[PASS] standalone_check: 指摘なし")
        else:
            print(f"[NOTICE] standalone_check: {len(all_findings)} 件")
            for f in all_findings:
                print(f"{f['file']}:L{f['line']}: [{f['severity']}][{f['code']}] {f['message']}")
                print(f"  > {f['snippet']}")
        if args.with_yomiyasu:
            print("-" * 60)
            if not yomi:
                print("[PASS] yomiyasu: 読む対象の指摘なし")
            else:
                print(f"[NOTICE] yomiyasu: {len(yomi)} 件(半角空白・太字頻度・箇条書き比率・「正本」は除外)")
                for y in yomi:
                    print(f"{y['file']}:L{y.get('line', '?')}: {y.get('message', '')}")
                    print(f"  > {str(y.get('snippet', ''))[:70]}")

    if had_error:
        sys.exit(2)
    warns = [f for f in all_findings if f["severity"] == "WARN"]
    sys.exit(1 if (warns or yomi) else 0)


if __name__ == "__main__":
    main()
