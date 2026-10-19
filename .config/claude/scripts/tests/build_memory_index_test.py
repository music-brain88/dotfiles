"""Tests for build_memory_index.py / 索引ビルダー build_memory_index.py のテスト

Every case builds a fake AgentMemory root under a temporary directory and runs
the script on it with --root. HOME also points at the temporary directory, so
the real vault ($HOME/Documents/Obsidian/AgentMemory) is never read or written.
各ケースは一時ディレクトリの下に偽の AgentMemory を作り、--root でスクリプトを走らせる。
HOME も一時ディレクトリに向けるので、実物の vault には読みも書きもしない。

Usage / 使い方:
  python3 -I -B -m unittest discover -s .config/claude/scripts/tests -p '*_test.py'
"""

import os
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

    def read(self, relative):
        with open(os.path.join(self.root, relative), encoding="utf-8") as f:
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


if __name__ == "__main__":
    unittest.main()
