"""Tests for build_memory_index.py / 索引ビルダー build_memory_index.py のテスト

Every case builds a fake AgentMemory root under a temporary directory and runs
the script on it with --root. HOME also points at the temporary directory, so
the real vault ($HOME/Documents/Obsidian/AgentMemory) is never read or written.
Session notes go under <tmp>/Zettelkasten/ResearchNotes, found through the default
--vault (the parent of --root).
各ケースは一時ディレクトリの下に偽の AgentMemory を作り、--root でスクリプトを走らせる。
HOME も一時ディレクトリに向けるので、実物の vault には読みも書きもしない。
セッションノートは <tmp>/Zettelkasten/ResearchNotes に置き、--vault の既定(--root の親)で見つけさせる。

Usage / 使い方:
  python3 -I -B -m unittest discover -s .config/claude/scripts/tests -p '*_test.py'
"""

import os
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "build_memory_index.py")
BEGIN = "<!-- memory-index:begin -->"
END = "<!-- memory-index:end -->"

# Nested metadata.type only (the older form) / metadata.type だけを持つ古い形
FEEDBACK_NESTED = """---
name: alpha-rule
description: "Always branch first: never push to main (see #12)"
metadata:
  type: feedback
  modified: 2026-09-01
---
body
"""

# Schema v3 with metadata.type / スキーマ v3 の形(metadata.type も持つ)
USER_V3 = """---
name: alpha-style
description: Prefers terminal-first tools
type: agent-memory
kind: disposition
subject: user
status: active
modified: 2026-07-30T16:06:31.053Z
metadata:
  type: user
---
"""

# State file: kind: state without metadata.type / 状態ファイル。metadata.type を持たない
STATE_V3 = """---
name: state-alpha
description: State as of 2026-10-19: next is the review
type: agent-memory
kind: state
---
"""

ROOT_WITHOUT_MARKERS = """# Memory Index
- [Core index](../core/MEMORY.md) — read this first
- [Alpha rule](feedback_alpha_rule.md) — an old hook line
- [Gone](feedback_gone.md) — points at a file that does not exist
- [Plain](plain_note.md) — points at a file without frontmatter
- inbox note without a link
"""


def memory(name, description, kind=None, **fields):
    lines = ["---", f"name: {name}", f"description: {description}"]
    lines += [f"{key}: {value}" for key, value in fields.items()]
    if kind:
        lines += ["metadata:", f"  type: {kind}"]
    return "\n".join(lines + ["---", ""])


def session(h1, date=None, tags=(), **fields):
    """A session note shaped like the real ones; a field set to "" becomes a key without a value.
    実物と同じ形のセッションノート。値が "" の項目は値の無いキーとして書く。
    """
    lines = ["---"] + ([f"date: {date}"] if date else [])
    if tags:
        lines += ["tags:"] + [f"  - {tag}" for tag in tags]
    lines += ["type: research-note"]
    lines += [f"{key}: {value}" if value else f"{key}:" for key, value in fields.items()]
    lines += ["---", ""] + ([f"# {h1}", ""] if h1 else [])
    return "\n".join(lines + ["body", ""])


def entries(text):
    return [line for line in text.splitlines() if line.startswith("- ")]


class BuildMemoryIndexTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = tmp.name
        self.root = os.path.join(tmp.name, "AgentMemory")
        for excluded in ("core", "episodes", "workbench"):
            os.makedirs(os.path.join(self.root, excluded))
        self.write("core/MEMORY.md", "- [Self](self.md) — not a project\n")

    def write(self, relative, text):
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def write_bytes(self, relative, data):
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    def write_session(self, name, text, vault=None):
        # The vault defaults to the parent of --root / vault の既定は --root の親
        notes = os.path.join(vault or self.home, "Zettelkasten", "ResearchNotes")
        os.makedirs(notes, exist_ok=True)
        with open(os.path.join(notes, f"ClaudeCodeSession-{name}.md"), "w", encoding="utf-8") as f:
            f.write(text)

    def make_shared(self):
        self.write_session("20260720-B", session("July B", "2026-07-20", ["nix", "herdr"], triage="candidate"))
        self.write_session("20260705-A", session("July A", "2026-07-05", ["herdr", "fish"]))
        self.write_session("20260705-C", session("July C", "2026-07-05", ["herdr", "nix", "atuin"]))
        # Dated by the file name / 日付はファイル名から
        self.write_session("20260810-D", session("August D", tags=["herdr"], triage="reference"))
        # frontmatter date wins over the file name / frontmatter の date がファイル名に勝つ
        self.write_session("20260731-E", session("August E", "2026-08-01"))
        self.write("episodes/20260801-later.md", memory(
            "episode-later", "Later one", origin_session='"[[ClaudeCodeSession-20260801-X]]"'
        ))
        self.write("episodes/20260720-first.md", memory("episode-first", "First one"))

    def read(self, relative):
        with open(os.path.join(self.root, relative), encoding="utf-8") as f:
            return f.read()

    def read_bytes(self, relative):
        with open(os.path.join(self.root, relative), "rb") as f:
            return f.read()

    def exists(self, relative):
        return os.path.exists(os.path.join(self.root, relative))

    def run_script(self, *args):
        env = dict(os.environ, HOME=self.home)
        return subprocess.run(
            [sys.executable, "-I", "-B", SCRIPT, "--root", self.root, *args],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def build(self, *args):
        result = self.run_script(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def snapshot(self):
        files = {}
        for directory, _, names in os.walk(self.root):
            for name in names:
                path = os.path.join(directory, name)
                with open(path, "rb") as f:
                    files[os.path.relpath(path, self.root)] = (f.read(), os.stat(path).st_mtime_ns)
        return files

    def region(self, relative="alpha/MEMORY.md"):
        text = self.read(relative)
        return text[text.index(BEGIN) : text.index(END)]

    def make_alpha(self):
        self.write("alpha/feedback_alpha_rule.md", FEEDBACK_NESTED)
        self.write("alpha/user_alpha_style.md", USER_V3)
        self.write("alpha/state_alpha.md", STATE_V3)
        self.write("alpha/project_alpha_plan.md", memory("alpha-plan", "The plan", "project"))
        self.write("alpha/reference_tool_trap.md", memory("tool-trap", "A trap", "reference"))
        self.write("alpha/_drafts-ideas.md", "no frontmatter, ignored by convention\n")
        self.write("alpha/plain_note.md", "no frontmatter\n")
        self.write("alpha/MEMORY.md", ROOT_WITHOUT_MARKERS)

    # (1) Both frontmatter forms are read / 入れ子と v3 の両方から種別を読む
    def test_reads_kind_from_nested_metadata_and_v3(self):
        self.make_alpha()
        self.write("alpha/project_top_level.md", memory("top-level", "Top-level type only", type="project"))
        self.write("alpha/reference_by_name.md", memory("by-name", "Kind from the file name"))
        self.build()
        region = self.region()
        self.assertIn(
            '- [alpha-rule](feedback_alpha_rule.md) — Always branch first: never push to main (see #12)',
            region,
        )
        self.assertIn("- [alpha-style](user_alpha_style.md) — Prefers terminal-first tools", region)
        project = self.read("alpha/index/project.md")
        self.assertIn("- [alpha-plan](../project_alpha_plan.md) — The plan", project)
        self.assertIn("- [top-level](../project_top_level.md) — Top-level type only", project)
        self.assertIn("- [by-name](../reference_by_name.md)", self.read("alpha/index/reference.md"))

    # (2) kind: state is always shown, before user and feedback / state は常時表示の先頭に載る
    def test_state_is_always_shown_first(self):
        self.make_alpha()
        self.build()
        region = self.region()
        state = region.index("](state_alpha.md) — State as of 2026-10-19: next is the review")
        self.assertLess(state, region.index("](user_alpha_style.md)"))
        self.assertLess(region.index("](user_alpha_style.md)"), region.index("](feedback_alpha_rule.md)"))
        self.assertNotIn("state_alpha.md", self.read("alpha/index/project.md"))

    # (3a) First run appends the markers after the handwritten text / 初回は末尾にマーカー区間を足す
    def test_first_run_appends_region_after_one_blank_line(self):
        self.make_alpha()
        self.build()
        text = self.read("alpha/MEMORY.md")
        handwritten, _, generated = text.partition(BEGIN)
        self.assertTrue(handwritten.startswith("# Memory Index\n- [Core index](../core/MEMORY.md)"))
        self.assertTrue(handwritten.endswith("- inbox note without a link\n\n"))
        self.assertTrue(text.endswith(END + "\n"))
        self.assertIn("- [project 枝](index/project.md) — 1 件", generated)
        self.assertIn("- [reference 枝](index/reference.md) — 1 件: tool", generated)

    # (3b) Second run replaces only the region / 2 回目は区間の中だけを置き換える
    def test_second_run_keeps_handwritten_lines(self):
        self.make_alpha()
        self.build()
        text = self.read("alpha/MEMORY.md")
        text = text.replace("# Memory Index\n", "# Memory Index\n- added by hand\n")
        self.write("alpha/MEMORY.md", text + "after the region\n")
        self.write("alpha/feedback_alpha_rule.md", FEEDBACK_NESTED.replace("Always", "Usually"))
        self.build()
        text = self.read("alpha/MEMORY.md")
        self.assertIn("# Memory Index\n- added by hand\n", text)
        self.assertTrue(text.endswith(END + "\nafter the region\n"))
        self.assertIn("— Usually branch first", self.region())
        self.assertEqual(text.count(BEGIN), 1)

    # (4) Inbox lines for indexed memories go, the rest stays / 受信箱の行を除き、他所を指す行は残す
    def test_inbox_lines_are_removed_and_others_kept(self):
        self.make_alpha()
        result = self.build()
        self.assertIn(
            "removed: alpha/MEMORY.md: - [Alpha rule](feedback_alpha_rule.md) — an old hook line",
            result.stdout,
        )
        self.assertEqual(result.stdout.count("removed: "), 1)
        handwritten = self.read("alpha/MEMORY.md").partition(BEGIN)[0]
        self.assertNotIn("an old hook line", handwritten)
        self.assertIn("- [Core index](../core/MEMORY.md) — read this first", handwritten)
        self.assertIn("- [Gone](feedback_gone.md)", handwritten)
        self.assertIn("- [Plain](plain_note.md)", handwritten)
        self.assertIn("- inbox note without a link", handwritten)
        self.assertIn("plain_note.md: frontmatter が無い", result.stderr)
        self.assertNotIn("_drafts-ideas.md", result.stderr + self.read("alpha/index/project.md"))

    # (5) A second run writes nothing / 2 回目は 1 ファイルも書き換えない
    def test_second_run_is_idempotent(self):
        self.make_alpha()
        self.build()
        before = self.snapshot()
        result = self.build()
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn("wrote: ", result.stdout)
        self.assertIn("書き換えたファイル: 0 本", result.stdout)

    # (6) --check exit codes, and it writes nothing / --check の終了コード。何も書かない
    def test_check_exit_codes(self):
        self.make_alpha()
        before = self.snapshot()
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("alpha", result.stdout)
        self.assertEqual(self.snapshot(), before)

        self.write("beta/MEMORY.md", "- line\n" * 201)
        self.assertEqual(self.run_script("--check").returncode, 1)
        self.write("beta/MEMORY.md", "x" * 25001)
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("OVER", result.stdout)
        # Over the target only: reported, exit 0 / 目標超過だけなら表に出して終了コード 0
        self.write("beta/MEMORY.md", "- line\n" * 150)
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0)
        self.assertIn("over", result.stdout)
        self.assertFalse(self.exists("beta/index"))

    # (6b) A root over the limit is written, then fails with its longest lines, on every run
    # 上限を超えた root は書いたうえで、長い行とともに終了コード 1。2 回目の実行でも同じ
    def test_root_over_the_limit_is_written_and_exits_1(self):
        self.make_alpha()
        big = "x" * 26000
        self.write("beta/feedback_big.md", memory("big", big, "feedback"))
        self.write("beta/feedback_small.md", memory("small", "Small rule", "feedback"))
        for run in ("first", "second"):
            with self.subTest(run):
                result = self.run_script()
                self.assertEqual(result.returncode, 1, result.stderr)
                # The writes and the summary are not stopped / 書き込みと summary は止めない
                self.assertIn("書き換えたファイル: ", result.stdout)
                if run == "second":
                    self.assertIn("書き換えたファイル: 0 本", result.stdout)
                data = self.read_bytes("beta/MEMORY.md")
                self.assertIn(f"- [big](feedback_big.md) — {big}\n", data.decode("utf-8"))
                self.assertIn(
                    f"error: beta/MEMORY.md: {len(data.splitlines())} 行 / {len(data)} バイトで、"
                    "上限の 200 行 / 25000 バイトを超えている",
                    result.stderr,
                )
                longest = len(f"- [big](feedback_big.md) — {big}".encode("utf-8"))
                listed = re.findall(r"^  長い行: (\d+) バイト: (.*)$", result.stderr, re.M)
                self.assertEqual(len(listed), 3)
                self.assertEqual(listed[0], (str(longest), "feedback_big.md"))
                self.assertIn("上限を超えた root: 1 本", result.stderr)
                # The healthy project is neither reported nor left unwritten / 正常なプロジェクトは名指しされず、書かれている
                self.assertNotIn("alpha/MEMORY.md", result.stderr)
                self.assertTrue(self.exists("alpha/index/project.md"))
        # --check lists the same long lines on stderr / --check も同じ長い行を標準エラーに並べる
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"  長い行: {longest} バイト: feedback_big.md", result.stderr)
        self.assertNotIn("長い行", result.stdout)

    # (6c) A root over the target only is warned about, exit 0 / 目標を超えただけの root は警告だけで終了コード 0
    def test_root_over_the_target_only_warns(self):
        self.make_alpha()
        for i in range(120):
            self.write(f"beta/feedback_rule_{i:03}.md", memory(f"rule-{i:03}", f"Rule {i}", "feedback"))
        result = self.build()
        data = self.read_bytes("beta/MEMORY.md")
        self.assertGreater(len(data.splitlines()), 100)
        self.assertIn(
            f"warning: beta/MEMORY.md: {len(data.splitlines())} 行 / {len(data)} バイトで、"
            "目標の 100 行 / 15000 バイトを超えている",
            result.stderr,
        )
        self.assertNotIn("長い行", result.stderr)
        self.assertNotIn("上限を超えた root", result.stderr)

    # (6d) A description over the budget is warned about and indexed uncut
    # 予算を超えた description は警告し、索引には切り詰めずに載せる
    def test_description_over_the_budget_is_warned_and_kept(self):
        self.make_alpha()
        long_description = "あ" * 201
        self.write("alpha/feedback_long.md", memory("long", long_description, "feedback"))
        self.write("alpha/feedback_edge.md", memory("edge", "y" * 600, "feedback"))
        result = self.build()
        self.assertIn(
            "warning: alpha/feedback_long.md: description が 603 バイトあり、予算の 600 バイトを超えている",
            result.stderr,
        )
        self.assertNotIn("feedback_edge.md", result.stderr)
        self.assertIn(f"- [long](feedback_long.md) — {long_description}\n", self.read("alpha/MEMORY.md"))

    # (7) Broken markers stop the run with 2, nothing written / 壊れたマーカーは終了コード 2、何も書かない
    def test_broken_markers_exit_2_without_writing(self):
        self.make_alpha()
        cases = {
            "begin only": f"{BEGIN}\n",
            "end before begin": f"{END}\n{BEGIN}\n",
            "two begins": f"{BEGIN}\n{BEGIN}\n{END}\n",
        }
        for label, root in cases.items():
            with self.subTest(label):
                self.write("beta/feedback_beta.md", memory("beta", "Beta rule", "feedback"))
                self.write("beta/MEMORY.md", root)
                before = self.snapshot()
                result = self.run_script()
                self.assertEqual(result.returncode, 2)
                self.assertIn("beta/MEMORY.md: マーカーが壊れている", result.stderr)
                # The healthy project is not written either / 正常なプロジェクトも書かない
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.exists("alpha/index"))

    # A titled first link pointing elsewhere keeps the line / タイトル付きの最初のリンクが他所を指す行は残す
    def test_titled_first_link_decides_the_target(self):
        self.make_alpha()
        kept = [
            '- [Guide](https://example.com "guide") — see [Plan](project_alpha_plan.md)',
            "- [Guide](https://example.com 'guide') — see [Plan](project_alpha_plan.md)",
        ]
        dropped = '- [Alpha plan](project_alpha_plan.md "plan") — a titled inbox line'
        self.write("alpha/MEMORY.md", ROOT_WITHOUT_MARKERS + "\n".join(kept + [dropped]) + "\n")
        result = self.build()
        handwritten = self.read("alpha/MEMORY.md").partition(BEGIN)[0]
        for line in kept:
            self.assertIn(line, handwritten)
        self.assertNotIn(dropped, handwritten)
        self.assertIn(f"removed: alpha/MEMORY.md: {dropped}", result.stdout)

    # Fences close only on the same character, at least as long / 同じ文字で長さが開き以上のフェンスだけで閉じる
    def test_code_fences_close_only_on_matching_fences(self):
        self.make_alpha()
        inside_backticks = "- [Alpha rule](feedback_alpha_rule.md) — inside a four-backtick block"
        inside_tildes = "- [Alpha rule](feedback_alpha_rule.md) — after tildes in a backtick block"
        after = "- [Alpha rule](feedback_alpha_rule.md) — an inbox line after the blocks"
        root = "\n".join([
            "# Memory Index",
            "````markdown",
            "```",
            inside_backticks,
            "```",
            "````",
            "```",
            "~~~",
            inside_tildes,
            "```",
            after,
            "",
        ])
        self.write("alpha/MEMORY.md", root)
        result = self.build()
        handwritten = self.read("alpha/MEMORY.md").partition(BEGIN)[0]
        self.assertIn(inside_backticks, handwritten)
        self.assertIn(inside_tildes, handwritten)
        self.assertNotIn(after, handwritten)
        self.assertEqual(result.stdout.count("removed: "), 1)

    # A CRLF root gets CRLF separators and region / CRLF の root には CRLF で区切りと区間を足す
    def test_crlf_root_keeps_crlf_on_first_run(self):
        self.make_alpha()
        self.write_bytes("alpha/MEMORY.md", ROOT_WITHOUT_MARKERS.replace("\n", "\r\n").encode("utf-8"))
        self.build()
        data = self.read_bytes("alpha/MEMORY.md")
        self.assertIn(b"- inbox note without a link\r\n\r\n" + BEGIN.encode(), data)
        self.assertTrue(data.endswith(END.encode() + b"\r\n"))
        self.assertIsNone(re.search(rb"(?<!\r)\n", data), "LF without CR found")
        before = self.snapshot()
        self.build()
        self.assertEqual(self.snapshot(), before)

    # A generated project whose memories are all gone is cleared / 記憶が全部消えた生成済みのプロジェクトを片付ける
    def test_generated_project_without_memories_is_cleared(self):
        self.make_alpha()
        self.build()
        for name in ("feedback_alpha_rule", "user_alpha_style", "state_alpha", "project_alpha_plan", "reference_tool_trap"):
            os.remove(os.path.join(self.root, f"alpha/{name}.md"))
        # Never generated and without memories: left alone / 一度も生成していない空のプロジェクトは触らない
        self.write("gamma/MEMORY.md", "- a note\n")
        result = self.build()
        self.assertIn("deleted: alpha/index/project.md", result.stdout)
        self.assertFalse(self.exists("alpha/index/project.md"))
        self.assertFalse(self.exists("alpha/index/reference.md"))
        region = self.region()
        self.assertNotIn("## 常時表示", region)
        self.assertNotIn("## 枝", region)
        self.assertNotIn("](", region)
        self.assertEqual(self.read("gamma/MEMORY.md"), "- a note\n")
        self.assertNotIn("gamma", result.stdout)
        # Its markers are still checked / マーカーの検証も走る
        self.write("alpha/MEMORY.md", f"{BEGIN}\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn("alpha/MEMORY.md: マーカーが壊れている", result.stderr)

    def test_missing_root_exits_2(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", SCRIPT, "--root", os.path.join(self.home, "nowhere")],
            capture_output=True,
            text=True,
            env=dict(os.environ, HOME=self.home),
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("ルートが無い", result.stderr)

    def test_project_branch_order(self):
        self.write("alpha/project_a.md", memory("a-none-old", "x", "project", modified="2026-01-01"))
        self.write("alpha/project_b.md", memory("b-active-old", "x", "project", status="active", modified="2026-02-01"))
        self.write("alpha/project_c.md", memory("c-active-new", "x", "project", status="active", modified="2026-09-01"))
        self.write("alpha/project_d.md", memory("d-tentative", "x", "project", status="tentative"))
        self.write("alpha/project_e.md", memory("e-none-undated", "x", "project"))
        self.write("alpha/project_f.md", """---
name: f-none-new
description: modified under metadata
metadata:
  type: project
  modified: 2026-10-01
---
""")
        self.build()
        project = self.read("alpha/index/project.md")
        order = ["c-active-new", "b-active-old", "d-tentative", "f-none-new", "a-none-old", "e-none-undated"]
        positions = [project.index(f"[{name}]") for name in order]
        self.assertEqual(positions, sorted(positions))

    def test_reference_headings_come_from_file_names(self):
        self.write("alpha/reference_nix_gc.md", memory("nix-gc", "x", "reference"))
        self.write("alpha/reference_herdr_split.md", memory("split", "x", "reference"))
        self.write("alpha/reference_herdr_attach.md", memory("attach", "x", "reference"))
        self.write("alpha/fish_shim.md", memory("fish-shim", "x", "reference"))
        self.build()
        reference = self.read("alpha/index/reference.md")
        self.assertTrue(reference.startswith("---\ntype: index\n---\n"))
        headings = [line for line in reference.splitlines() if line.startswith("## ")]
        self.assertEqual(headings, ["## fish", "## herdr", "## nix"])
        self.assertLess(reference.index("[attach]"), reference.index("[split]"))
        self.assertIn("— 4 件: fish・herdr・nix", self.region())

    def test_unclassified_goes_to_the_end_of_the_project_branch(self):
        self.write("alpha/project_plan.md", memory("plan", "x", "project"))
        self.write("alpha/misc_note.md", memory("misc", "No kind anywhere"))
        result = self.build()
        project = self.read("alpha/index/project.md")
        self.assertTrue(project.startswith("---\ntype: index\n---\n"))
        self.assertLess(project.index("[plan]"), project.index("## 未分類"))
        self.assertLess(project.index("## 未分類"), project.index("- [misc](../misc_note.md)"))
        self.assertIn("misc_note.md: 種別が決まらない", result.stderr)
        self.assertIn("— 2 件(うち未分類 1 件)", self.region())

    def test_empty_branches_are_not_created(self):
        self.write("alpha/feedback_only.md", memory("only", "x", "feedback"))
        self.build()
        self.assertFalse(self.exists("alpha/index/project.md"))
        self.assertFalse(self.exists("alpha/index/reference.md"))
        self.assertNotIn("## 枝", self.region())
        # A branch that empties later is removed / 後から空になった枝は消す
        self.write("alpha/reference_tool_x.md", memory("tool-x", "x", "reference"))
        self.build()
        self.assertTrue(self.exists("alpha/index/reference.md"))
        os.remove(os.path.join(self.root, "alpha/reference_tool_x.md"))
        self.build()
        self.assertFalse(self.exists("alpha/index/reference.md"))
        self.assertNotIn("reference 枝", self.region())

    def test_project_option_limits_the_run(self):
        self.make_alpha()
        self.write("beta/feedback_beta.md", memory("beta", "Beta rule", "feedback"))
        self.build("--project", "beta")
        self.assertTrue(self.exists("beta/MEMORY.md"))
        self.assertEqual(self.read("alpha/MEMORY.md"), ROOT_WITHOUT_MARKERS)
        self.assertNotEqual(self.run_script("--project", "core").returncode, 0)

    # A block list does not swallow the keys after it / block list の後ろのキーも読める
    def test_block_list_keeps_the_following_keys(self):
        self.write("alpha/feedback_listed.md", "\n".join([
            "---", "name: listed", "tags:", "  - a", "  - b", "description: After the list",
            "metadata:", "  type: feedback", "---", "",
        ]))
        self.build()
        self.assertIn("- [listed](feedback_listed.md) — After the list", self.region())

    # (8) ⏳ only for candidates whose distilled_to is empty / ⏳ は candidate かつ distilled_to が空のときだけ
    def test_hourglass_marks_undistilled_candidates_only(self):
        cases = {
            "20260701-Empty": ({"triage": "candidate", "distilled_to": ""}, True),
            "20260702-Brackets": ({"triage": "candidate", "distilled_to": "[]"}, True),
            "20260703-NoKey": ({"triage": "candidate"}, True),
            "20260704-Distilled": ({"triage": "candidate", "distilled_to": '"[[Permanent note]]"'}, False),
            "20260705-Reference": ({"triage": "reference", "distilled_to": ""}, False),
            "20260706-Untriaged": ({"distilled_to": ""}, False),
        }
        for name, (fields, _) in cases.items():
            self.write_session(name, session(name, **fields))
        self.build()
        lines = entries(self.read("sessions/2026-07.md"))
        for name, (_, pending) in cases.items():
            with self.subTest(name):
                line = next(line for line in lines if f"[[ClaudeCodeSession-{name}]]" in line)
                self.assertEqual(line.endswith(" · ⏳"), pending, line)
        self.assertEqual(entries(self.read("sessions/INDEX.md")), ["- [2026-07](2026-07.md) — 6 本 · ⏳ 3"])

    # (9) No H1 falls back to the stem, long H1s are cut at 120 / H1 が無ければ stem、120 字で切る
    def test_title_falls_back_to_the_stem_and_is_cut_at_120(self):
        self.write_session("20260801-NoHeading", session(None, "2026-08-01"))
        self.write_session("20260802-Long", session("あ" * 121, "2026-08-02", ["nix"]))
        self.write_session("20260803-Exact", session("い" * 120, "2026-08-03"))
        self.build()
        # Without tags and ⏳ the separators go too / tags と ⏳ が無ければ区切りごと省く
        self.assertEqual(entries(self.read("sessions/2026-08.md")), [
            "- 2026-08-01 [[ClaudeCodeSession-20260801-NoHeading]] — ClaudeCodeSession-20260801-NoHeading",
            f"- 2026-08-02 [[ClaudeCodeSession-20260802-Long]] — {'あ' * 120}… · nix",
            f"- 2026-08-03 [[ClaudeCodeSession-20260803-Exact]] — {'い' * 120}",
        ])

    # A "# comment" in a code block is not the H1 / コードブロックの中の「# コメント」は H1 ではない
    def test_heading_inside_a_code_block_is_skipped(self):
        self.write_session("20260804-Fenced", "\n".join([
            "---", "date: 2026-08-04", "---", "", "```bash", "# Install deps", "npm ci", "```", "",
            "# Real heading", "", "body", "",
        ]))
        self.build()
        self.assertEqual(entries(self.read("sessions/2026-08.md")), [
            "- 2026-08-04 [[ClaudeCodeSession-20260804-Fenced]] — Real heading",
        ])

    # Only "#" lines in code blocks: the stem is used / コードブロックの中にしか「#」行が無ければ stem を使う
    def test_heading_only_inside_a_code_block_falls_back_to_the_stem(self):
        self.write_session("20260805-OnlyFenced", "\n".join([
            "---", "date: 2026-08-05", "---", "", "~~~sh", "# Only a comment", "~~~", "", "body", "",
        ]))
        self.build()
        self.assertEqual(entries(self.read("sessions/2026-08.md")), [
            "- 2026-08-05 [[ClaudeCodeSession-20260805-OnlyFenced]] — ClaudeCodeSession-20260805-OnlyFenced",
        ])

    # (10) One file per month, the index newest first / 月ごとに 1 ファイル、INDEX は新しい月から
    def test_months_make_files_and_index_lines(self):
        self.make_shared()
        self.build()
        july = self.read("sessions/2026-07.md")
        self.assertTrue(july.startswith("---\ntype: index\n---\n\n# Sessions 2026-07\n\n> "))
        self.assertIn("`~/Zettelkasten/ResearchNotes/<ノート名>.md`", july)
        self.assertEqual(entries(july), [
            "- 2026-07-05 [[ClaudeCodeSession-20260705-A]] — July A · herdr, fish",
            "- 2026-07-05 [[ClaudeCodeSession-20260705-C]] — July C · herdr, nix, atuin",
            "- 2026-07-20 [[ClaudeCodeSession-20260720-B]] — July B · nix, herdr · ⏳",
        ])
        self.assertEqual(entries(self.read("sessions/2026-08.md")), [
            "- 2026-08-01 [[ClaudeCodeSession-20260731-E]] — August E",
            "- 2026-08-10 [[ClaudeCodeSession-20260810-D]] — August D · herdr",
        ])
        index = self.read("sessions/INDEX.md")
        self.assertTrue(index.startswith("---\ntype: index\n---\n\n# Sessions index\n\n> "))
        # Top tags by count, ties in string order / 上位 tags は出現回数順、同数は文字列順
        self.assertEqual(entries(index), [
            "- [2026-08](2026-08.md) — 2 本 · herdr · ⏳ 0",
            "- [2026-07](2026-07.md) — 3 本 · herdr, nix, atuin · ⏳ 1",
        ])
        # A month whose notes are gone is removed / ノートが無くなった月のファイルは消す
        for name in ("20260810-D", "20260731-E"):
            os.remove(os.path.join(self.home, "Zettelkasten", "ResearchNotes", f"ClaudeCodeSession-{name}.md"))
        result = self.build()
        self.assertIn("deleted: sessions/2026-08.md", result.stdout)
        self.assertFalse(self.exists("sessions/2026-08.md"))
        self.assertEqual(len(entries(self.read("sessions/INDEX.md"))), 1)

    # A month file left without INDEX.md (an interrupted run) is removed once the notes are gone
    # INDEX.md の無いまま残った月別ファイル(途中で止まった実行の跡)も、ノートが無くなれば消す
    def test_stale_month_without_index_is_removed(self):
        os.makedirs(os.path.join(self.home, "Zettelkasten", "ResearchNotes"))
        self.write("sessions/2026-07.md", "---\ntype: index\n---\n\n# Sessions 2026-07\n")
        self.write("sessions/2026-06.md", "# A handwritten month\n")
        result = self.build()
        self.assertIn("deleted: sessions/2026-07.md", result.stdout)
        self.assertFalse(self.exists("sessions/2026-07.md"))
        self.assertTrue(self.exists("sessions/2026-06.md"))
        self.assertFalse(self.exists("sessions/INDEX.md"))

    # (11) Episodes by date, origin_session kept as a wikilink / 私記は日付順、origin_session は wikilink のまま
    def test_episodes_index_lists_episodes_by_date(self):
        self.make_shared()
        self.write("episodes/notes-undated.md", memory("episode-undated", "Dated by modified", modified="2026-07-25"))
        self.write("episodes/_draft.md", memory("draft", "Ignored by convention"))
        self.build()
        index = self.read("episodes/INDEX.md")
        self.assertTrue(index.startswith("---\ntype: index\n---\n\n# Episodes index\n\n> "))
        self.assertEqual(entries(index), [
            "- 2026-07-20 [episode-first](20260720-first.md) — First one",
            "- 2026-07-25 [episode-undated](notes-undated.md) — Dated by modified",
            "- 2026-08-01 [episode-later](20260801-later.md) — Later one · [[ClaudeCodeSession-20260801-X]]",
        ])

    # (12) No episodes, no index; a generated one is removed / 私記が無ければ作らず、生成済みなら消す
    def test_episodes_index_needs_episodes(self):
        self.make_alpha()
        self.build()
        self.assertFalse(self.exists("episodes/INDEX.md"))
        self.write("episodes/20260720-first.md", memory("episode-first", "First one"))
        self.build()
        self.assertTrue(self.exists("episodes/INDEX.md"))
        os.remove(os.path.join(self.root, "episodes/20260720-first.md"))
        result = self.build()
        self.assertIn("deleted: episodes/INDEX.md", result.stdout)
        self.assertFalse(self.exists("episodes/INDEX.md"))

    # (13) A handwritten index stops the whole run / 手書きの索引があれば全体を止める
    def test_handwritten_sessions_index_exits_2_without_writing(self):
        self.make_alpha()
        self.make_shared()
        self.write("sessions/INDEX.md", "# My own list of sessions\n")
        before = self.snapshot()
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn("sessions/INDEX.md: 生成物ではない", result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.exists("alpha/index"))

    # (14) --project leaves the shared indexes alone / --project 指定では共有領域に触らない
    def test_project_option_skips_sessions_and_episodes(self):
        self.make_alpha()
        self.make_shared()
        result = self.build("--project", "alpha")
        self.assertFalse(self.exists("sessions"))
        self.assertFalse(self.exists("episodes/INDEX.md"))
        self.assertNotIn("sessions", result.stdout)
        self.build()
        self.assertNotIn("sessions/", self.run_script("--check", "--project", "alpha").stdout)

    # (15) --check lists the shared indexes without a limit / --check は共有領域の索引を上限なしで並べる
    def test_check_lists_shared_indexes(self):
        self.make_alpha()
        self.make_shared()
        self.build()
        self.write("sessions/2026-07.md", "---\ntype: index\n---\n" + "- line\n" * 300)
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {line.split()[0]: line.split()[1:] for line in result.stdout.splitlines()[1:]}
        for label in ("sessions/INDEX.md", "sessions/2026-07.md", "sessions/2026-08.md", "episodes/INDEX.md"):
            with self.subTest(label):
                data = self.read_bytes(label)
                self.assertEqual(rows[label], [str(len(data.splitlines())), str(len(data)), "-", "-"])
        self.assertEqual(rows["alpha"][2:], ["ok", "ok"])

    # (16) A full run with the shared indexes writes nothing the second time / 2 回目の全体実行は何も書かない
    def test_full_run_with_shared_indexes_is_idempotent(self):
        self.make_alpha()
        self.make_shared()
        result = self.build()
        # Month files are written before the index that links to them / 月別ファイルを INDEX より先に書く
        self.assertLess(result.stdout.index("wrote: sessions/2026-07.md"), result.stdout.index("wrote: sessions/INDEX.md"))
        self.assertIn("wrote: episodes/INDEX.md", result.stdout)
        self.assertIn("sessions: 2 か月・5 本・⏳ 1 本", result.stdout)
        before = self.snapshot()
        result = self.build()
        self.assertEqual(self.snapshot(), before)
        self.assertIn("書き換えたファイル: 0 本", result.stdout)

    # (17) Without Zettelkasten the sessions are skipped; --vault points elsewhere
    # Zettelkasten が無ければ sessions は飛ばす。--vault で別の vault を指せる
    def test_vault_option_and_missing_notes(self):
        result = self.build()
        self.assertIn("sessions: セッションノートの置き場が無いので飛ばす", result.stdout)
        self.assertFalse(self.exists("sessions"))
        elsewhere = os.path.join(self.home, "elsewhere")
        self.write_session("20260901-Far", session("Far away", "2026-09-01"), vault=elsewhere)
        self.build("--vault", elsewhere)
        month = self.read("sessions/2026-09.md")
        self.assertIn("[[ClaudeCodeSession-20260901-Far]] — Far away", month)
        self.assertIn("`~/elsewhere/Zettelkasten/ResearchNotes/<ノート名>.md`", month)


if __name__ == "__main__":
    unittest.main()
