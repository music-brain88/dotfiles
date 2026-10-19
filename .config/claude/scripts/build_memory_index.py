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

Usage / 使い方:
  python3 -I build_memory_index.py [--root PATH] [--project NAME] [--check]

Exit status / 終了コード: 0 ok, 1 --check found a root over the limit, 2 bad input.
Standard library only, no PyYAML / 標準ライブラリだけで動く(PyYAML は使わない)。
"""

import argparse
import os
import posixpath
import re
import stat
import sys
import tempfile
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

# Claude Code stops reading MEMORY.md here / Claude Code が MEMORY.md を読むのはここまで
LIMIT_LINES, LIMIT_BYTES = 200, 25000
# Aim, shown in the --check table only / 目標。--check の表に出すだけで終了コードには効かせない
TARGET_LINES, TARGET_BYTES = 100, 15000

TOP_KEY = re.compile(r"^([A-Za-z_][\w-]*):(?:\s(.*))?$")
NESTED_KEY = re.compile(r"^  ([A-Za-z_][\w-]*):(?:\s(.*))?$")
FIRST_LINK = re.compile(r"\]\(([^)\s]+)\)")


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
class Plan:
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
    YAML の実装ではない。1 行 1 つの key: value を読み、入れ子は metadata: 直下の
    2 スペース字下げだけを読み、値の前後の引用符を外す。
    """
    lines = text.splitlines()
    if not lines or lines[0].rstrip() != "---":
        return None
    top, metadata = {}, {}
    in_metadata = False
    for line in lines[1:]:
        if line.rstrip() == "---":
            return top, metadata
        match = TOP_KEY.match(line)
        if match:
            key, value = match.group(1), unquote(match.group(2))
            top[key] = value
            in_metadata = key == "metadata" and not value
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
    status(active → その他の値 → 無し)、modified の降順(無しは末尾)、name の順に並べる。
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


def drop_inbox_lines(lines, indexed_files, removed):
    kept, in_fence = [], False
    for line in lines:
        if line.lstrip().startswith(("```", "~~~")):
            in_fence = not in_fence
        elif not in_fence and inbox_target(line) in indexed_files:
            removed.append(line.rstrip("\r\n"))
            continue
        kept.append(line)
    return kept


def merge_root(text, block, indexed_files):
    """Put the generated block into the root and drop covered inbox lines.
    root に生成領域を入れ、今回の生成に載った記憶を指す受信箱の行を手書き領域から除く。

    Without markers the whole file is handwritten and the block is appended
    after one blank line. With markers only the region between them is replaced.
    マーカーが無ければファイル全体を手書き領域とみなし、空行 1 つを挟んで末尾に足す。
    マーカーがあれば区間の中だけを置き換える。
    """
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
        return (handwritten + "\n\n" if handwritten else "") + block, removed
    after = drop_inbox_lines(after, indexed_files, removed)
    return "".join(before) + block + "".join(after), removed


def plan_project(root, project):
    """Compute every file of one project without writing / 1 プロジェクト分の出力を計算する(まだ書かない)"""
    project_dir = os.path.join(root, project)
    memories = load_memories(project_dir, project)
    if not memories:
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

    root_path = os.path.join(project_dir, "MEMORY.md")
    try:
        existing = read_text(root_path)
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
            existing = read_bytes(path)
            if existing is not None and existing.startswith(BRANCH_FRONTMATTER.encode()):
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


def build(root, projects):
    # Plan every project first, so a broken root stops the run before any write
    # 先に全プロジェクトを計算し、壊れた root が 1 つでもあれば 1 ファイルも書かずに止める
    plans, errors = [], []
    for project in projects:
        try:
            plan = plan_project(root, project)
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
    return 0


def check(root, projects):
    rows = []
    for project in projects:
        data = read_bytes(os.path.join(root, project, "MEMORY.md"))
        if data is not None:
            rows.append((project, len(data.splitlines()), len(data)))
    limit = f"limit({LIMIT_LINES}/{LIMIT_BYTES})"
    target = f"target({TARGET_LINES}/{TARGET_BYTES})"
    width = max([len("project")] + [len(row[0]) for row in rows])
    print(f"{'project':<{width}}  {'lines':>5}  {'bytes':>6}  {limit}  {target}")
    over = 0
    for project, lines, size in rows:
        within_limit = lines <= LIMIT_LINES and size <= LIMIT_BYTES
        within_target = lines <= TARGET_LINES and size <= TARGET_BYTES
        over += not within_limit
        print(
            f"{project:<{width}}  {lines:>5}  {size:>6}  "
            f"{'ok' if within_limit else 'OVER':<{len(limit)}}  {'ok' if within_target else 'over'}"
        )
    if over:
        print(f"上限を超えた root: {over} 本", file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build the AgentMemory indexes from memory frontmatter / 記憶の frontmatter から索引を作る"
    )
    parser.add_argument("--root", default=DEFAULT_ROOT, help=f"AgentMemory root (default: {DEFAULT_ROOT})")
    parser.add_argument("--project", help="limit to one project directory / 1 プロジェクトに絞る")
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; report root sizes and exit 1 over the limit / 書かずに root のサイズだけ検査する",
    )
    args = parser.parse_args(argv)
    root = os.path.expanduser(args.root)
    try:
        projects = list_projects(root, args.project)
        return check(root, projects) if args.check else build(root, projects)
    except InputError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
