#!/usr/bin/env python3
"""Build the AgentMemory indexes from memory frontmatter / 記憶の frontmatter から AgentMemory の索引を作る

Each project directory under the AgentMemory root becomes a three-level tree.
The root MEMORY.md is read automatically (only its first 200 lines / 25KB),
the branches index/project.md and index/reference.md are opened on demand,
and the memory files are the leaves, which this script never rewrites.
Only the region between the markers in MEMORY.md is generated; the rest of the
file is handwritten (reading guide and inbox) and stays as it is, except that
inbox lines pointing at memories now listed by the generated tree are dropped.
AgentMemory のルート直下の各プロジェクトを root → 枝 → 葉の 3 段にする。
root(MEMORY.md)は自動で読まれるが先頭 200 行 / 25KB までしか読まれない。
枝(index/project.md・index/reference.md)は必要なときに開く。葉(記憶ファイル)は書き換えない。
MEMORY.md はマーカーの間だけを生成し、外側は手書き領域(読み方・受信箱)として残す。
ただし、今回の生成に載った記憶を指す受信箱の行は手書き領域から取り除く。

A full run (without --project) also builds the shared indexes of the vault:
sessions/INDEX.md and sessions/YYYY-MM.md from the session notes under
<vault>/Zettelkasten/ResearchNotes, and episodes/INDEX.md from episodes/*.md.
--project を付けない全体実行では vault 共通の索引も作る。<vault>/Zettelkasten/ResearchNotes の
セッションノートから sessions/INDEX.md と月別の sessions/YYYY-MM.md を、episodes/*.md から
episodes/INDEX.md を作る。

Usage / 使い方:
  python3 -I build_memory_index.py [--root PATH] [--vault PATH] [--project NAME] [--check]

After writing, every planned root is checked like --check: a root over the limit
is reported with its longest lines (exit 1, the files are still written), a root
over the target only is warned about. A description over DESCRIPTION_BYTES is
warned about and indexed as it is.
書き込みの後、計画した各 root を --check と同じ判定で検問する。上限を超えた root は
長い行の上位とともに知らせて終了コード 1 にする(ファイルは書いたまま)。目標を超えただけの
root は警告だけ出す。description が DESCRIPTION_BYTES を超える記憶は警告し、切り詰めずに載せる。

Exit status / 終了コード: 0 ok, 1 a root is over the limit (after writing, or with --check), 2 bad input.
Standard library only, no PyYAML / 標準ライブラリだけで動く(PyYAML は使わない)。
"""

import argparse
import os
import posixpath
import re
import stat
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass

DEFAULT_ROOT = "~/Documents/Obsidian/AgentMemory"
# Shared areas of the vault, not projects / プロジェクトではない vault 共通の領域
EXCLUDED_DIRS = {"core", "episodes", "workbench", "sessions"}
KINDS = ("state", "user", "feedback", "project", "reference")
# Listed in the root itself, in this order / root にそのまま載せる種別(この順に並べる)
ALWAYS_SHOWN = ("state", "user", "feedback")
UNCLASSIFIED = "未分類"

BEGIN_MARKER = "<!-- memory-index:begin -->"
END_MARKER = "<!-- memory-index:end -->"
ROOT_NOTE = "<!-- この区間は build_memory_index.py が生成する。手書きは区間の外に書く -->"
BRANCH_NOTE = "<!-- build_memory_index.py が各記憶の frontmatter から生成する。手で直さない -->"
BRANCH_FRONTMATTER = "---\ntype: index\n---\n"

# Shared indexes, built on a full run only / 全体実行のときだけ作る vault 共通の索引
SESSION_PREFIX = "ClaudeCodeSession-"
SESSION_NOTES = ("Zettelkasten", "ResearchNotes")
SHARED_INDEX = "INDEX.md"
MONTH_FILE = re.compile(r"^\d{4}-\d{2}\.md$")
# Eight digits of a date in a file name / ファイル名の 8 桁の日付
FILE_DATE = re.compile(r"(\d{4})(\d{2})(\d{2})(?!\d)")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}")
TITLE_LIMIT = 120
PENDING = "⏳"
# Wikilinks cannot be resolved outside Obsidian, so the notes say where the files are.
# Writing "[[...]]" here would leave an unresolved link in the vault, hence "wikilink".
# Obsidian の外では wikilink を解決できないので、ノートの実体の置き場を注記に書く。
# 注記に [[...]] と書くと vault に未解決のリンクが増えるので「wikilink」と書く。
MONTH_NOTE = (
    "> build_memory_index.py がセッションノートの frontmatter と最初の H1 から生成する。手で直さない。"
    "wikilink の実体は `{notes}/<ノート名>.md`。"
    "⏳ は `triage: candidate` のまま `distilled_to` が空の(未蒸留の)ノート。"
)
SESSIONS_INDEX_NOTE = (
    "> build_memory_index.py がセッションノートから生成する。手で直さない。"
    "月のファイルに 1 ノート 1 行で載り、ノートの実体は `{notes}/<ノート名>.md`。"
    "tags は月内で多い順の上位 3 つ、⏳ は `triage: candidate` のまま `distilled_to` が空の(未蒸留の)ノートの本数。"
)
EPISODES_NOTE = (
    "> build_memory_index.py が各私記の frontmatter から生成する。手で直さない。"
    "行末の wikilink は私記の元になったセッションノートで、実体は `{notes}/<ノート名>.md`。"
)

# Claude Code stops reading MEMORY.md here / Claude Code が MEMORY.md を読むのはここまで
LIMIT_LINES, LIMIT_BYTES = 200, 25000
# Aim, warned about but never in the exit status / 目標。警告や表に出すだけで終了コードには効かせない
TARGET_LINES, TARGET_BYTES = 100, 15000
# UTF-8 bytes one description may take; longer ones are warned about, never cut,
# since a cut would hide what the index leaves out in another way.
# 記憶 1 件の description の予算(UTF-8 のバイト数)。超えたら警告するが切り詰めない。
# 切り詰めると、索引の欠け方が見えなくなる問題を別の形で作るため。
DESCRIPTION_BYTES = 600
# Longest lines listed for a root over the limit / 上限を超えた root について並べる長い行の件数
LONG_LINES = 3

TOP_KEY = re.compile(r"^([A-Za-z_][\w-]*):(?:\s(.*))?$")
NESTED_KEY = re.compile(r"^  ([A-Za-z_][\w-]*):(?:\s(.*))?$")
LIST_ITEM = re.compile(r"^  - (.*)$")
# A link target, optionally followed by a title: [t](url "title") / リンク先(タイトル付きの形も拾う)
FIRST_LINK = re.compile(r"\]\(\s*([^)\s]+)(?:\s+\"[^\"]*\"|\s+'[^']*')?\s*\)")
# Fence of a code block, any indentation (errs on keeping lines) / コードブロックのフェンス(字下げは問わない)
FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")


class InputError(Exception):
    """Bad input that stops the run before anything is written / 何も書かずに止める入力の異常"""


@dataclass
class Memory:
    file: str
    name: str
    description: str
    kind: str
    status: str
    modified: str


@dataclass
class Session:
    file: str
    date: str
    title: str
    tags: list
    pending: bool


@dataclass
class Episode:
    file: str
    date: str
    name: str
    description: str
    origin: str


@dataclass
class Plan:
    # A project directory, or a shared area (sessions, episodes)
    # プロジェクトのディレクトリか、vault 共通の領域(sessions・episodes)
    project: str
    # Relative path -> new content, or None to remove a stale branch.
    # Branches come before MEMORY.md so the root never links to a missing file.
    # 相対パス → 新しい内容(None は空になった枝の削除)。root が無い枝を指さないよう枝を先に書く
    files: dict
    removed: list
    summary: str


def warn(project, filename, message):
    print(f"warning: {project}/{filename}: {message}", file=sys.stderr)


def unquote(value):
    value = (value or "").strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_frontmatter(text):
    """Return (top-level fields, metadata fields), or None without frontmatter.
    frontmatter の最上位の値と metadata: 直下の値を返す。frontmatter が無ければ None。

    A minimal reader, not YAML: one "key: value" per line, only the lines indented
    by two spaces right under "metadata:" are nested, surrounding quotes are dropped.
    "  - item" lines right after a key without a value make that key a list.
    YAML の実装ではない。1 行 1 つの key: value を読み、入れ子は metadata: 直下の
    2 スペース字下げだけを読み、値の前後の引用符を外す。値の無い key の直後に続く
    "  - item" の行は、その key の値を list として読む(block list)。
    """
    lines = text.splitlines()
    if not lines or lines[0].rstrip() != "---":
        return None
    top, metadata = {}, {}
    in_metadata = False
    list_key = None
    for line in lines[1:]:
        if line.rstrip() == "---":
            return top, metadata
        match = TOP_KEY.match(line)
        if match:
            key, value = match.group(1), unquote(match.group(2))
            top[key] = value
            in_metadata = key == "metadata" and not value
            list_key = None if value else key
            continue
        match = LIST_ITEM.match(line)
        if match and list_key:
            top[list_key] = (top[list_key] or []) + [unquote(match.group(1))]
            continue
        match = NESTED_KEY.match(line)
        if match and in_metadata:
            metadata[match.group(1)] = unquote(match.group(2))
    return None


def file_words(filename):
    return [word for word in re.split(r"[_-]", filename[: -len(".md")]) if word]


def classify(top, metadata, filename):
    """Decide where a memory goes in the tree / 記憶の種別を決める

    metadata.type, then kind: state, then the top-level type, then the first
    word of the file name; otherwise it is listed as unclassified.
    metadata.type → kind: state → 最上位の type → ファイル名の最初の語の順に見て、
    どれでも決まらなければ未分類にする。
    """
    if metadata.get("type") in KINDS:
        return metadata["type"]
    if top.get("kind") == "state":
        return "state"
    if top.get("type") in KINDS:
        return top["type"]
    words = file_words(filename)
    if words and words[0] in KINDS:
        return words[0]
    return UNCLASSIFIED


def topic_word(filename):
    """Heading of the reference branch: the first word after the type prefix.
    reference 枝の見出し語。ファイル名から種別の接頭辞を外した残りの最初の語。
    """
    words = file_words(filename)
    if len(words) > 1 and words[0] in KINDS:
        return words[1]
    return words[0] if words else filename


def load_memories(project_dir, project):
    memories = []
    for entry in sorted(os.listdir(project_dir)):
        path = os.path.join(project_dir, entry)
        # Files starting with "_" are drafts or helpers by convention
        # 先頭が _ のファイルは下書きや補助スクリプトの慣習なので対象外
        if (
            entry == "MEMORY.md"
            or entry.startswith(("_", "."))
            or not entry.endswith(".md")
            or not os.path.isfile(path)
        ):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                parsed = parse_frontmatter(f.read())
        except UnicodeDecodeError:
            warn(project, entry, "UTF-8 として読めないので索引の対象外にする")
            continue
        if parsed is None:
            warn(project, entry, "frontmatter が無いので索引の対象外にする")
            continue
        top, metadata = parsed
        kind = classify(top, metadata, entry)
        if kind == UNCLASSIFIED:
            warn(project, entry, f"種別が決まらないので project 枝の「{UNCLASSIFIED}」に載せる")
        name = top.get("name") or entry[: -len(".md")]
        if not top.get("name"):
            warn(project, entry, "name が無いのでファイル名を使う")
        if not top.get("description"):
            warn(project, entry, "description が無い")
        description = top.get("description", "")
        size = len(description.encode("utf-8")) if isinstance(description, str) else 0
        if size > DESCRIPTION_BYTES:
            warn(
                project,
                entry,
                f"description が {size} バイトあり、予算の {DESCRIPTION_BYTES} バイトを超えている"
                "(切り詰めずに索引へ載せる。経過は本文へ移す)",
            )
        memories.append(
            Memory(
                file=entry,
                name=name,
                description=top.get("description", ""),
                kind=kind,
                status=top.get("status", ""),
                # Only the frontmatter value, never the file mtime (deterministic output)
                # frontmatter の値だけを使い、mtime で補わない(出力を決定的に保つ)
                modified=top.get("modified") or metadata.get("modified", ""),
            )
        )
    return memories


def by_name(memory):
    return (memory.name, memory.file)


def project_order(memories):
    """active first, then other statuses, then none; newer first; then by name.
    Statuses other than active are grouped by value, in alphabetical order of the value.
    status(active → その他の値 → 無し)、modified の降順(無しは末尾)、name の順に並べる。
    active 以外の status は値ごとにまとめる(値のアルファベット順)。
    """
    ordered = sorted(memories, key=by_name)
    # Stable sorts, applied from the weakest key / 安定ソートを弱いキーから順にかける
    ordered.sort(key=lambda m: m.modified, reverse=True)
    ordered.sort(key=lambda m: (0 if m.status == "active" else 1 if m.status else 2, m.status))
    return ordered


def entry_line(memory, link_prefix=""):
    line = f"- [{memory.name}]({link_prefix}{memory.file})"
    return f"{line} — {memory.description}" if memory.description else line


def render_branch(title, sections):
    out = [BRANCH_FRONTMATTER, BRANCH_NOTE, "", f"# {title}"]
    for heading, memories in sections:
        if not memories:
            continue
        out.append("")
        if heading:
            out += [f"## {heading}", ""]
        out += [entry_line(m, "../") for m in memories]
    return "\n".join(out) + "\n"


def render_root_block(always, branch_lines):
    out = [BEGIN_MARKER, ROOT_NOTE]
    if always:
        out += ["", "## 常時表示", ""] + [entry_line(m) for m in always]
    if branch_lines:
        out += ["", "## 枝", ""] + branch_lines
    out += ["", END_MARKER]
    return "\n".join(out) + "\n"


def inbox_target(line):
    """File a bullet line links to, if it sits in the project directory itself.
    箇条書き行の最初のリンク先。プロジェクト直下のファイルを指すときだけ返す。
    """
    if not line.startswith("- "):
        return None
    match = FIRST_LINK.search(line)
    if not match:
        return None
    target = posixpath.normpath(match.group(1).split("#", 1)[0])
    return None if "/" in target else target


def fence_of(line):
    """Fence characters of a code fence line, or None / コードフェンスの行ならフェンスの文字列を返す"""
    match = FENCE.match(line.rstrip("\r\n"))
    if not match:
        return None
    # A backtick fence cannot carry backticks in its info string (that is inline code)
    # バッククォートのフェンスの info 文字列にバッククォートは入らない(入っていればインラインコード)
    if match.group(1)[0] == "`" and "`" in match.group(2):
        return None
    return match.group(1), match.group(2)


def with_code_blocks(lines):
    """Pair each line with whether it is part of a code block, fences included.
    各行に、コードブロックの一部(フェンスの行を含む)かどうかを添える。

    A block closes only on a fence of the same character that is at least as
    long as the opening one (CommonMark).
    ブロックを閉じるのは、開きと同じ文字で長さが開き以上のフェンスだけ(CommonMark の規則)。
    """
    opening = None
    for line in lines:
        fence = fence_of(line)
        if opening is None and fence:
            opening = fence[0]
            yield line, True
        elif (
            opening
            and fence
            and fence[0][0] == opening[0]
            and len(fence[0]) >= len(opening)
            and not fence[1].strip()
        ):
            opening = None
            yield line, True
        else:
            yield line, opening is not None


def drop_inbox_lines(lines, indexed_files, removed):
    # Lines inside code blocks are never removed / コードブロックの中の行は消さない
    kept = []
    for line, in_code in with_code_blocks(lines):
        if not in_code and inbox_target(line) in indexed_files:
            removed.append(line.rstrip("\r\n"))
            continue
        kept.append(line)
    return kept


def merge_root(text, block, indexed_files):
    """Put the generated block into the root and drop covered inbox lines.
    root に生成領域を入れ、今回の生成に載った記憶を指す受信箱の行を手書き領域から除く。

    Without markers the whole file is handwritten and the block is appended
    after one blank line. With markers only the region between them is replaced.
    The block and the separator use CRLF when the root already does.
    マーカーが無ければファイル全体を手書き領域とみなし、空行 1 つを挟んで末尾に足す。
    マーカーがあれば区間の中だけを置き換える。root が CRLF なら区切りと生成領域も CRLF にする。
    """
    newline = "\r\n" if "\r\n" in text else "\n"
    block = block.replace("\n", newline)
    lines = text.splitlines(keepends=True)
    begins = [i for i, line in enumerate(lines) if line.strip() == BEGIN_MARKER]
    ends = [i for i, line in enumerate(lines) if line.strip() == END_MARKER]
    if not begins and not ends:
        before, after = lines, None
    elif len(begins) == 1 and len(ends) == 1 and begins[0] < ends[0]:
        before, after = lines[: begins[0]], lines[ends[0] + 1 :]
    else:
        raise InputError(
            f"マーカーが壊れている(begin {len(begins)} 個・end {len(ends)} 個。"
            "begin と end が 1 個ずつ、begin が先にある形だけを受け付ける)"
        )
    removed = []
    before = drop_inbox_lines(before, indexed_files, removed)
    if after is None:
        handwritten = "".join(before).rstrip("\r\n")
        return (handwritten + newline * 2 if handwritten else "") + block, removed
    after = drop_inbox_lines(after, indexed_files, removed)
    return "".join(before) + block + "".join(after), removed


def plan_project(root, project):
    """Compute every file of one project without writing / 1 プロジェクト分の出力を計算する(まだ書かない)"""
    project_dir = os.path.join(root, project)
    memories = load_memories(project_dir, project)
    try:
        existing = read_text(os.path.join(project_dir, "MEMORY.md"))
    except InputError as error:
        raise InputError(f"{project}/MEMORY.md: {error}") from None
    # A project without memories is left alone unless it was generated before; then
    # planning goes on so stale branches and counts are cleared and markers are checked.
    # 記憶の無いプロジェクトは、一度も生成していなければ触らない。生成済みなら計画を続け、
    # 古い枝と件数を消し、マーカーの検証も走らせる。
    if not memories and not was_generated(project_dir, existing):
        return None

    always = [
        m for kind in ALWAYS_SHOWN for m in sorted((m for m in memories if m.kind == kind), key=by_name)
    ]
    projects = project_order([m for m in memories if m.kind == "project"])
    unclassified = sorted((m for m in memories if m.kind == UNCLASSIFIED), key=by_name)
    topics = {}
    for m in sorted((m for m in memories if m.kind == "reference"), key=by_name):
        topics.setdefault(topic_word(m.file), []).append(m)
    headings = sorted(topics)
    reference_count = sum(len(v) for v in topics.values())

    files, branch_lines = {}, []
    project_count = len(projects) + len(unclassified)
    if project_count:
        files["index/project.md"] = render_branch(
            "project 枝", [(None, projects), (UNCLASSIFIED, unclassified)]
        )
        note = f"(うち{UNCLASSIFIED} {len(unclassified)} 件)" if unclassified else ""
        branch_lines.append(f"- [project 枝](index/project.md) — {project_count} 件{note}")
    else:
        files["index/project.md"] = None
    if reference_count:
        files["index/reference.md"] = render_branch(
            "reference 枝", [(h, topics[h]) for h in headings]
        )
        branch_lines.append(
            f"- [reference 枝](index/reference.md) — {reference_count} 件: {'・'.join(headings)}"
        )
    else:
        files["index/reference.md"] = None

    try:
        files["MEMORY.md"], removed = merge_root(
            existing, render_root_block(always, branch_lines), {m.file for m in memories}
        )
    except InputError as error:
        raise InputError(f"{project}/MEMORY.md: {error}") from None

    summary = (
        f"{project}: 常時表示 {len(always)} 件・project 枝 {project_count} 件・"
        f"reference 枝 {reference_count} 件・受信箱から除去 {len(removed)} 行"
    )
    return Plan(project=project, files=files, removed=removed, summary=summary)


def read_text(path):
    """Read a root as is, keeping its line endings / root を改行コードごとそのまま読む"""
    try:
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()
    except FileNotFoundError:
        return ""
    except UnicodeDecodeError:
        raise InputError("UTF-8 として読めない") from None


def read_bytes(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None


def is_generated_branch(path):
    """Whether a branch file was written by this script / このスクリプトが生成した枝か"""
    data = read_bytes(path)
    return data is not None and data.startswith(BRANCH_FRONTMATTER.encode())


def was_generated(project_dir, root_text):
    """Whether the project has a marker or a generated branch / マーカーか生成済みの枝があるか"""
    if any(line.strip() in (BEGIN_MARKER, END_MARKER) for line in root_text.splitlines()):
        return True
    return any(
        is_generated_branch(os.path.join(project_dir, branch))
        for branch in ("index/project.md", "index/reference.md")
    )


def display_path(path):
    """Path with the home directory written as ~, the same on every machine.
    ホームを ~ で書いたパス。Obsidian Sync で共有する索引がマシンごとに変わらないようにする。
    """
    home = os.path.normpath(os.path.expanduser("~"))
    if path == home or path.startswith(home + os.sep):
        return "~" + path[len(home) :]
    return path


def file_date(filename, prefix=""):
    """YYYY-MM-DD from the eight digits right after the prefix / 接頭辞の直後の 8 桁から日付を作る"""
    match = FILE_DATE.match(filename, len(prefix)) if filename.startswith(prefix) else None
    return "-".join(match.groups()) if match else None


def iso_date(value):
    """YYYY-MM-DD at the head of a frontmatter value / frontmatter の値の先頭の日付"""
    match = ISO_DATE.match(value) if isinstance(value, str) else None
    return match.group(0) if match else None


def is_empty(value):
    """distilled_to counts as empty when missing, blank or [] / キー無し・空文字・[] を空とみなす"""
    return value in (None, "", "[]", [])


def read_note(path, area, entry):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        warn(area, entry, "UTF-8 として読めないので索引の対象外にする")
        return None


def first_heading(text):
    """Text of the first H1 after the frontmatter and outside code blocks, where a
    "# comment" line of a shell snippet is not a heading.
    frontmatter の後で、コードブロックの外にある最初の H1 の文。
    シェルの断片の「# コメント」の行は見出しではないので拾わない。
    """
    lines = text.splitlines()
    start = 0
    if lines and lines[0].rstrip() == "---":
        start = next((i + 1 for i, line in enumerate(lines[1:], 1) if line.rstrip() == "---"), 0)
    for line, in_code in with_code_blocks(lines[start:]):
        if not in_code and line.startswith("# ") and line[2:].strip():
            return line[2:].strip()
    return None


def load_sessions(notes_dir):
    sessions = []
    for entry in sorted(os.listdir(notes_dir)):
        path = os.path.join(notes_dir, entry)
        if not entry.startswith(SESSION_PREFIX) or not entry.endswith(".md") or not os.path.isfile(path):
            continue
        text = read_note(path, "ResearchNotes", entry)
        if text is None:
            continue
        parsed = parse_frontmatter(text)
        if parsed is None:
            warn("ResearchNotes", entry, "frontmatter が無いので日付はファイル名から取る")
        top = parsed[0] if parsed else {}
        date = iso_date(top.get("date")) or file_date(entry, SESSION_PREFIX)
        if not date:
            warn("ResearchNotes", entry, "日付が決まらない(date もファイル名の 8 桁も無い)ので索引の対象外にする")
            continue
        title = first_heading(text) or entry[: -len(".md")]
        if len(title) > TITLE_LIMIT:
            title = title[:TITLE_LIMIT] + "…"
        tags = top.get("tags")
        sessions.append(
            Session(
                file=entry,
                date=date,
                title=title,
                tags=[tag for tag in (tags if isinstance(tags, list) else [tags]) if tag],
                pending=top.get("triage") == "candidate" and is_empty(top.get("distilled_to")),
            )
        )
    return sessions


def load_episodes(episodes_dir):
    episodes = []
    for entry in sorted(os.listdir(episodes_dir)):
        path = os.path.join(episodes_dir, entry)
        if (
            entry == SHARED_INDEX
            or entry.startswith(("_", "."))
            or not entry.endswith(".md")
            or not os.path.isfile(path)
        ):
            continue
        text = read_note(path, "episodes", entry)
        if text is None:
            continue
        parsed = parse_frontmatter(text)
        if parsed is None:
            warn("episodes", entry, "frontmatter が無いので索引の対象外にする")
            continue
        top = parsed[0]
        date = file_date(entry) or iso_date(top.get("modified"))
        if not date:
            warn("episodes", entry, "日付が決まらない(ファイル名の 8 桁も modified も無い)ので索引の対象外にする")
            continue
        if not top.get("name"):
            warn("episodes", entry, "name が無いのでファイル名を使う")
        if not top.get("description"):
            warn("episodes", entry, "description が無い")
        episodes.append(
            Episode(
                file=entry,
                date=date,
                name=top.get("name") or entry[: -len(".md")],
                description=top.get("description", ""),
                origin=top.get("origin_session", ""),
            )
        )
    return episodes


def session_line(session):
    parts = [f"- {session.date} [[{session.file[: -len('.md')]}]] — {session.title}"]
    if session.tags:
        parts.append(", ".join(session.tags))
    if session.pending:
        parts.append(PENDING)
    return " · ".join(parts)


def month_line(month, sessions):
    counts = Counter(tag for session in sessions for tag in dict.fromkeys(session.tags))
    top_tags = sorted(counts, key=lambda tag: (-counts[tag], tag))[:3]
    parts = [f"- [{month}]({month}.md) — {len(sessions)} 本"]
    if top_tags:
        parts.append(", ".join(top_tags))
    parts.append(f"{PENDING} {sum(session.pending for session in sessions)}")
    return " · ".join(parts)


def episode_line(episode):
    line = f"- {episode.date} [{episode.name}]({episode.file})"
    tail = " · ".join(part for part in (episode.description, episode.origin) if part)
    return f"{line} — {tail}" if tail else line


def render_shared_index(title, note, lines):
    return "\n".join([BRANCH_FRONTMATTER, f"# {title}", "", note, ""] + lines) + "\n"


def refuse_handwritten(area, directory, files):
    """Stop when a file to be written exists and was not generated by this script.
    書き先にこのスクリプトの生成物ではないファイルがあれば止める。
    """
    for relative, content in files.items():
        path = os.path.join(directory, relative)
        if content is not None and os.path.exists(path) and not is_generated_branch(path):
            raise InputError(
                f"{area}/{relative}: 生成物ではない(先頭が type: index の frontmatter でない)ファイルがあるので上書きしない"
            )


def plan_sessions(root, vault):
    """Compute sessions/INDEX.md and the month files without writing / sessions の索引を計算する(まだ書かない)"""
    notes_dir = os.path.join(vault, *SESSION_NOTES)
    if not os.path.isdir(notes_dir):
        print(f"sessions: セッションノートの置き場が無いので飛ばす: {notes_dir}")
        return None
    months = {}
    for session in sorted(load_sessions(notes_dir), key=lambda s: (s.date, s.file)):
        months.setdefault(session.date[:7], []).append(session)
    sessions_dir = os.path.join(root, "sessions")
    # Without notes, planning goes on while sessions/ exists: month files are written before
    # INDEX.md, so an interrupted run can leave generated months without a generated INDEX.md.
    # apply_plan removes only generated files. ノートが無くても sessions/ があれば計画を続ける。
    # 月別ファイルは INDEX.md より先に書くので、途中で止まった実行は INDEX.md の無い月別ファイルを
    # 残しうる。消すのは apply_plan が生成物に限る。
    if not months and not os.path.isdir(sessions_dir):
        return None

    notes = display_path(notes_dir)
    # Month files, then INDEX.md, then removals, so INDEX.md never links to a missing file
    # 月別ファイル → INDEX.md → 消す月の順に並べ、INDEX.md が無いファイルを指さないようにする
    files = {
        f"{month}.md": render_shared_index(
            f"Sessions {month}", MONTH_NOTE.format(notes=notes), [session_line(s) for s in months[month]]
        )
        for month in sorted(months)
    }
    files[SHARED_INDEX] = (
        render_shared_index(
            "Sessions index",
            SESSIONS_INDEX_NOTE.format(notes=notes),
            [month_line(month, months[month]) for month in sorted(months, reverse=True)],
        )
        if months
        else None
    )
    if os.path.isdir(sessions_dir):
        for entry in sorted(os.listdir(sessions_dir)):
            if MONTH_FILE.match(entry) and entry not in files:
                files[entry] = None
    refuse_handwritten("sessions", sessions_dir, files)

    count = sum(len(sessions) for sessions in months.values())
    pending = sum(s.pending for sessions in months.values() for s in sessions)
    summary = f"sessions: {len(months)} か月・{count} 本・{PENDING} {pending} 本"
    return Plan(project="sessions", files=files, removed=[], summary=summary)


def plan_episodes(root, vault):
    """Compute episodes/INDEX.md without writing / episodes/INDEX.md を計算する(まだ書かない)"""
    episodes_dir = os.path.join(root, "episodes")
    episodes = load_episodes(episodes_dir) if os.path.isdir(episodes_dir) else []
    if not episodes and not is_generated_branch(os.path.join(episodes_dir, SHARED_INDEX)):
        return None
    lines = [episode_line(e) for e in sorted(episodes, key=lambda e: (e.date, e.file))]
    note = EPISODES_NOTE.format(notes=display_path(os.path.join(vault, *SESSION_NOTES)))
    files = {SHARED_INDEX: render_shared_index("Episodes index", note, lines) if lines else None}
    refuse_handwritten("episodes", episodes_dir, files)
    return Plan(project="episodes", files=files, removed=[], summary=f"episodes: {len(lines)} 本")


def current_umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


def write_atomic(path, content):
    """Write through a temporary file in the same directory and rename it.
    同じディレクトリの一時ファイルに書いてから os.replace で差し替える。
    """
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except FileNotFoundError:
        mode = 0o666 & ~current_umask()
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(content)
        # mkstemp creates 0600; keep the mode the file had / mkstemp は 0600 で作るので元の権限に戻す
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def apply_plan(root, plan):
    written = 0
    for relative, content in plan.files.items():
        path = os.path.join(root, plan.project, relative)
        label = f"{plan.project}/{relative}"
        if content is None:
            # Remove a branch that became empty, but only one this script generated
            # 空になった枝を消す。ただしこのスクリプトが生成したファイルに限る
            if is_generated_branch(path):
                os.remove(path)
                print(f"deleted: {label}")
                written += 1
            continue
        # Unchanged output is not rewritten (no churn for Obsidian Sync and git)
        # 内容が同じなら書かない(Obsidian Sync と git に無用な更新を出さない)
        if read_bytes(path) == content.encode("utf-8"):
            continue
        write_atomic(path, content)
        print(f"wrote: {label}")
        written += 1
    return written


def list_projects(root, only):
    if not os.path.isdir(root):
        raise InputError(f"AgentMemory のルートが無い: {root}")
    projects = [
        entry
        for entry in sorted(os.listdir(root))
        if os.path.isdir(os.path.join(root, entry))
        and entry not in EXCLUDED_DIRS
        and not entry.startswith(("_", "."))
    ]
    if only is None:
        return projects
    if only not in projects:
        raise InputError(f"プロジェクトが無いか対象外: {only}")
    return [only]


def size_status(lines, size):
    """(within the limit, within the target) of a root, shared by build and --check.
    root が上限内か・目標内か。書き出し後の検問と --check の両方がこの判定を使う。
    """
    return (
        lines <= LIMIT_LINES and size <= LIMIT_BYTES,
        lines <= TARGET_LINES and size <= TARGET_BYTES,
    )


def long_lines(data, count=LONG_LINES):
    """The longest lines of a root as (UTF-8 bytes, memory file or the first 60 characters).
    root の長い行の上位を (UTF-8 のバイト数, 行が指す記憶ファイル名か先頭 60 文字) で返す。
    """
    ranked = sorted(data.splitlines(), key=len, reverse=True)[:count]
    rows = []
    for raw in ranked:
        line = raw.decode("utf-8", errors="replace")
        rows.append((len(raw), inbox_target(line) or line[:60]))
    return rows


def report_over_limit(project, data):
    """Tell which root is over the limit and which lines make it so / 上限を超えた root と長い行を知らせる"""
    lines, size = len(data.splitlines()), len(data)
    print(
        f"error: {project}/MEMORY.md: {lines} 行 / {size} バイトで、上限の "
        f"{LIMIT_LINES} 行 / {LIMIT_BYTES} バイトを超えている(Claude Code は上限より後ろを読まない)",
        file=sys.stderr,
    )
    for length, label in long_lines(data):
        print(f"  長い行: {length} バイト: {label}", file=sys.stderr)


def build(root, projects, vault=None):
    # Plan every project first, so a broken root stops the run before any write
    # 先に全プロジェクトを計算し、壊れた root が 1 つでもあれば 1 ファイルも書かずに止める
    steps = [(plan_project, project) for project in projects]
    if vault is not None:
        # The shared indexes join the same plan-then-write run / 共有領域の索引も同じ計算 → 書き込みに乗せる
        steps += [(plan_sessions, vault), (plan_episodes, vault)]
    plans, errors = [], []
    for planner, target in steps:
        try:
            plan = planner(root, target)
        except InputError as error:
            errors.append(str(error))
            continue
        if plan is not None:
            plans.append(plan)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print("error: 何も書かずに終了する", file=sys.stderr)
        return 2

    written = 0
    for plan in plans:
        for line in plan.removed:
            print(f"removed: {plan.project}/MEMORY.md: {line}")
        written += apply_plan(root, plan)
        print(plan.summary)
    print(f"書き換えたファイル: {written} 本")
    # Gate every planned root, written or unchanged, after all writes: an index over the
    # limit is still written, and an unchanged one keeps failing on every later run.
    # 書き込みを全部終えてから、計画した全 root(書かなかった同じ内容の root も含む)を検問する。
    # 上限を超えた索引も書いたうえで知らせ、変わらないまま超えている root も毎回知らせる。
    over = 0
    for plan in plans:
        content = plan.files.get("MEMORY.md")
        if content is None:
            continue
        data = content.encode("utf-8")
        lines, size = len(data.splitlines()), len(data)
        within_limit, within_target = size_status(lines, size)
        if not within_limit:
            over += 1
            report_over_limit(plan.project, data)
        elif not within_target:
            warn(
                plan.project,
                "MEMORY.md",
                f"{lines} 行 / {size} バイトで、目標の {TARGET_LINES} 行 / {TARGET_BYTES} バイトを超えている",
            )
    if over:
        print(f"上限を超えた root: {over} 本", file=sys.stderr)
        return 1
    return 0


def shared_rows(root):
    """Sizes of the shared indexes on disk / 共有領域の索引のサイズ(ディスク上の今の状態)"""
    sessions_dir = os.path.join(root, "sessions")
    entries = sorted(os.listdir(sessions_dir)) if os.path.isdir(sessions_dir) else []
    labels = [f"sessions/{e}" for e in entries if e == SHARED_INDEX or MONTH_FILE.match(e)]
    rows = []
    for label in labels + [f"episodes/{SHARED_INDEX}"]:
        data = read_bytes(os.path.join(root, label))
        if data is not None:
            rows.append((label, len(data.splitlines()), len(data)))
    return rows


def check(root, projects, shared=False):
    rows, contents = [], {}
    for project in projects:
        data = read_bytes(os.path.join(root, project, "MEMORY.md"))
        if data is not None:
            rows.append((project, len(data.splitlines()), len(data)))
            contents[project] = data
    # Read on demand, so no limit applies; listed for their size only
    # 必要なときに Read で開くものなので上限は無い。大きさを見るためだけに表に出す
    extra = shared_rows(root) if shared else []
    limit = f"limit({LIMIT_LINES}/{LIMIT_BYTES})"
    target = f"target({TARGET_LINES}/{TARGET_BYTES})"
    width = max([len("project")] + [len(row[0]) for row in rows + extra])
    print(f"{'project':<{width}}  {'lines':>5}  {'bytes':>6}  {limit}  {target}")
    over = []
    for project, lines, size in rows:
        within_limit, within_target = size_status(lines, size)
        if not within_limit:
            over.append(project)
        print(
            f"{project:<{width}}  {lines:>5}  {size:>6}  "
            f"{'ok' if within_limit else 'OVER':<{len(limit)}}  {'ok' if within_target else 'over'}"
        )
    for label, lines, size in extra:
        print(f"{label:<{width}}  {lines:>5}  {size:>6}  {'-':<{len(limit)}}  -")
    if over:
        # The table stays on stdout as it was; the long lines go to stderr
        # 標準出力の表の形は変えず、長い行の列挙は標準エラーに出す
        for project in over:
            report_over_limit(project, contents[project])
        print(f"上限を超えた root: {len(over)} 本", file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build the AgentMemory indexes from memory frontmatter / 記憶の frontmatter から索引を作る"
    )
    parser.add_argument("--root", default=DEFAULT_ROOT, help=f"AgentMemory root (default: {DEFAULT_ROOT})")
    parser.add_argument(
        "--vault",
        help="vault holding Zettelkasten/ResearchNotes (default: the parent of --root) / "
        "セッションノートを探す vault のルート(既定は --root の親)",
    )
    parser.add_argument(
        "--project",
        help="limit to one project directory; sessions and episodes are skipped / "
        "1 プロジェクトに絞る(sessions と episodes の索引は作らない)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; report root and shared index sizes, exit 1 when a root is over the limit / "
        "書かずに root と共有領域の索引のサイズだけ検査する",
    )
    args = parser.parse_args(argv)
    root = os.path.expanduser(args.root)
    if args.vault:
        vault = os.path.abspath(os.path.expanduser(args.vault))
    else:
        vault = os.path.dirname(os.path.abspath(root))
    # sessions and episodes belong to the whole vault, so only a full run touches them
    # sessions と episodes は vault 全体のものなので、全体実行のときだけ扱う
    shared = args.project is None
    try:
        projects = list_projects(root, args.project)
        if args.check:
            return check(root, projects, shared)
        return build(root, projects, vault if shared else None)
    except InputError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
