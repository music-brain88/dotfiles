//! standalone-check — 配布文書の自立可読性を機械的に点検する。
//! Mechanical checks for standalone readability of distributed Japanese documents.
//!
//! 検査項目 / Checks:
//!   MAIN     節の冒頭の段落に主文(句点で終わる文)がない、または表や箇条書きで始まっている
//!   TAIGEN   段落や文が句点で終わらない、または名詞で終わる(体言止め)
//!   LIST     20 字以上の箇条書き項目が句点で終わらない
//!   CONTEXT  直前の会話を前提にする語(こっち、先方、例の、さっき など)
//!   TOUTEN   1 文に読点が 3 つ以上あり、節がつながれている
//!   TSUIKU   「X は A、Y は B」型の並列で動詞がない(対句の疑い)
//!
//! 判定は物理行ではなく段落単位で行う。連続する本文行・引用行は 1 つの段落に結合し、
//! 箇条書きは続きの行(インデント行、または空行を挟まない直後の行)を項目に結合する。
//! 行に "standalone: ignore" を含む HTML コメントを置くと、その行は検査しない。
//! 重さ: WARN(終了コード 1 の対象)と INFO(確認だけ)。MAIN の表始まりと箇条書き始まりは INFO。
//!
//! 終了コード / Exit code:
//!   0  WARN なし(INFO と yomiyasu の info は影響しない)
//!   1  本ツールの WARN、または yomiyasu の warn / error がある
//!   2  ファイルを読めない、または --with-yomiyasu を付けたのに lint を実行できなかった

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::sync::OnceLock;

const USAGE: &str = "\
使い方 / Usage:
  standalone-check FILE [FILE ...] [--with-yomiyasu] [--yomiyasu-script PATH] [--json]

  --with-yomiyasu        yomiyasu の lint も実行する(本環境の表記と衝突する指摘は除く)
  --yomiyasu-script PATH lint の場所を指定する(省略時は ~/.claude/skills/yomiyasu/scripts/yomiyasu_lint.py、
                         次に ~/.copilot/skills/yomiyasu/scripts/yomiyasu_lint.py を探す)。
                         .py なら python3 で、それ以外はそのまま実行する
  --json                 JSON で出力する(findings / yomiyasu / yomiyasu_status)
  -h, --help             この説明を出す

検査項目: MAIN(節の冒頭の主文の欠落) / TAIGEN(体言止め) / LIST(箇条書きの体言止め) /
CONTEXT(文脈依存語) / TOUTEN(読点の多い文) / TSUIKU(対句の疑い)
終了コード: 0 = WARN なし / 1 = WARN か yomiyasu の warn あり / 2 = ファイルを読めない、lint を実行できない";

const IGNORE_MARK: &str = "standalone: ignore";
const CLOSERS: &[char] = &[
    '）', ')', '」', '』', '】', ']', '*', '_', '`', '"', '\'', ' ', '\u{3000}',
];
const SENTENCE_END: &[char] = &['。', '！', '？', '!', '?'];
/// 段落・箇条書きの末尾として受ける文字。英文の行はピリオドで終わるので足す(文の分割には使わない)。
const PARAGRAPH_END: &[char] = &['。', '！', '？', '!', '?', '.'];
const PARTICLES: &[char] = &[
    'は', 'が', 'を', 'に', 'で', 'と', 'の', 'へ', 'や', 'か', 'も', 'ね', 'よ', 'な',
];

fn re(cell: &'static OnceLock<Regex>, pat: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pat).expect("valid regex"))
}

macro_rules! lazy_re {
    ($name:ident, $pat:expr) => {
        fn $name() -> &'static Regex {
            static CELL: OnceLock<Regex> = OnceLock::new();
            re(&CELL, $pat)
        }
    };
}

lazy_re!(re_heading, r"^#{1,6}\s");
lazy_re!(re_table, r"^\s*\|");
lazy_re!(re_list_item, r"^\s*(?:[-*+]|\d+\.)\s+(.*)$");
lazy_re!(re_blockquote, r"^\s*>\s?(.*)$");
lazy_re!(re_fence, r"^\s*(```|~~~)");
lazy_re!(
    re_context_words,
    r"こっち|あっち|そっち|先方|あの人|例の|さっき|先ほどの|前に話した|前回話した|この前の|あの件|その件|くだんの|上で言った|冒頭で言った"
);
// yomiyasu の指摘のうち、本環境の表記と衝突するため読まないもの(SKILL.md「yomiyasu の指摘の読み方」)
lazy_re!(
    re_yomiyasu_ignore,
    r"半角空白|太字の頻度|箇条書きの比率|「正本」|正本"
);
lazy_re!(re_trailing_paren, r"\s*[（(][^（）()]*[）)]\s*$");
lazy_re!(re_ascii_tail, r"[A-Za-z0-9)\]]$");
lazy_re!(re_ascii_head, r"^[A-Za-z0-9(\[]");
lazy_re!(re_inline_code, r"`[^`]*`");
lazy_re!(re_bold, r"\*\*([^*]+)\*\*");
lazy_re!(re_link, r"\[([^\]]+)\]\([^)]*\)");
lazy_re!(re_quoted, r"「[^」]*」");
lazy_re!(re_tsuiku_clause, r"^[^はがをにで]{1,14}は[^は]{1,12}$");

#[derive(Debug, Clone, Serialize)]
struct Finding {
    file: String,
    line: usize,
    code: &'static str,
    severity: &'static str,
    message: String,
    snippet: String,
}

#[derive(Deserialize)]
struct YomiyasuReport {
    findings: Vec<YomiyasuFinding>,
}

#[derive(Deserialize)]
struct YomiyasuFinding {
    #[serde(default = "default_yomiyasu_severity")]
    severity: String,
    message: String,
    snippet: String,
    #[serde(flatten)]
    extra: serde_json::Map<String, serde_json::Value>,
}

fn default_yomiyasu_severity() -> String {
    "warn".into()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Heading,
    Table,
    List,
    Quote,
    Para,
    Blank,
    Fence,
    Code,
    Ignored,
}

#[derive(Debug, Clone)]
struct Block {
    kind: Kind,
    start: usize,
    text: String,
}

fn opener_close(c: char) -> Option<char> {
    match c {
        '（' => Some('）'),
        '(' => Some(')'),
        '「' => Some('」'),
        '『' => Some('』'),
        '【' => Some('】'),
        _ => None,
    }
}

fn strip_closers(s: &str) -> &str {
    s.trim_end_matches(CLOSERS)
}

/// 文末の括弧書き(補足)を外す。「〜しない(理由)。」の動詞を見るため。
fn strip_trailing_paren(s: &str) -> String {
    let mut cur = s.to_string();
    loop {
        let next = re_trailing_paren().replace(&cur, "").into_owned();
        if next == cur {
            return cur;
        }
        cur = next;
    }
}

/// 括弧と鉤括弧の中身を除いた文字列を返す(読点の数え上げ用)。
fn outside_parens(s: &str) -> String {
    let mut out = String::new();
    let mut stack: Vec<char> = Vec::new();
    for ch in s.chars() {
        if let Some(close) = opener_close(ch) {
            stack.push(close);
            continue;
        }
        if stack.last() == Some(&ch) {
            stack.pop();
            continue;
        }
        if stack.is_empty() {
            out.push(ch);
        }
    }
    out
}

fn last_char(s: &str) -> Option<char> {
    s.chars().next_back()
}

fn is_hiragana(c: char) -> bool {
    ('ぁ'..='ん').contains(&c)
}

/// 節が用言で終わるとみなせるか。末尾が平仮名で、助詞ではないとき。
fn is_verbal(clause: &str) -> bool {
    match last_char(clause) {
        Some(c) => is_hiragana(c) && !PARTICLES.contains(&c),
        None => false,
    }
}

fn strip_inline(s: &str) -> String {
    let s = re_inline_code().replace_all(s, "code");
    let s = re_bold().replace_all(&s, "$1");
    let s = re_link().replace_all(&s, "$1");
    s.trim().to_string()
}

/// 折り返された 2 行をつなぐ。和文は詰め、欧文同士は半角空白を挟む。
fn join_wrapped(a: &str, b: &str) -> String {
    let a = a.trim_end();
    let b = b.trim();
    if a.is_empty() {
        return b.to_string();
    }
    if b.is_empty() {
        return a.to_string();
    }
    if re_ascii_tail().is_match(a) && re_ascii_head().is_match(b) {
        format!("{a} {b}")
    } else {
        format!("{a}{b}")
    }
}

/// 句点で区切った文を返す。括弧の中の句点では切らない。末尾に句点がない残りも 1 文として返す。
fn sentences(text: &str) -> Vec<(String, bool)> {
    let mut out = Vec::new();
    let mut buf = String::new();
    let mut stack: Vec<char> = Vec::new();
    for ch in text.chars() {
        buf.push(ch);
        if let Some(close) = opener_close(ch) {
            stack.push(close);
        } else if stack.last() == Some(&ch) {
            stack.pop();
        } else if SENTENCE_END.contains(&ch) && stack.is_empty() {
            out.push((buf.trim().to_string(), true));
            buf.clear();
        }
    }
    let rest = buf.trim();
    if !rest.is_empty() {
        out.push((rest.to_string(), false));
    }
    out
}

/// 段落に主文(句点で終わる文)があるか。英文の段落はピリオド終わりを受ける。
fn has_complete_sentence(text: &str) -> bool {
    let plain = strip_inline(text);
    if sentences(&plain).iter().any(|(_, ended)| *ended) {
        return true;
    }
    last_char(strip_closers(&plain)).is_some_and(|c| PARAGRAPH_END.contains(&c))
}

fn truncate_chars(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// 各行の種別を返す。fence の中は code 扱い。
fn classify_lines(lines: &[String], start: usize) -> Vec<(Kind, String)> {
    let mut kinds: Vec<(Kind, String)> = Vec::with_capacity(lines.len());
    let mut in_fence = false;
    for (i, raw) in lines.iter().enumerate() {
        if i < start {
            kinds.push((Kind::Ignored, String::new()));
            continue;
        }
        if raw.contains(IGNORE_MARK) {
            kinds.push((Kind::Ignored, String::new()));
            continue;
        }
        if re_fence().is_match(raw) {
            in_fence = !in_fence;
            kinds.push((Kind::Fence, String::new()));
            continue;
        }
        if in_fence {
            kinds.push((Kind::Code, String::new()));
            continue;
        }
        if raw.trim().is_empty() {
            kinds.push((Kind::Blank, String::new()));
        } else if re_heading().is_match(raw) {
            kinds.push((
                Kind::Heading,
                raw.trim_matches(|c| c == '#' || c == ' ')
                    .trim()
                    .to_string(),
            ));
        } else if re_table().is_match(raw) {
            kinds.push((Kind::Table, raw.clone()));
        } else if let Some(cap) = re_list_item().captures(raw) {
            kinds.push((Kind::List, cap[1].to_string()));
        } else if let Some(cap) = re_blockquote().captures(raw) {
            kinds.push((Kind::Quote, cap[1].to_string()));
        } else {
            kinds.push((Kind::Para, raw.trim().to_string()));
        }
    }
    kinds
}

/// 行を段落(ブロック)にまとめる。
fn build_blocks(kinds: &[(Kind, String)]) -> Vec<Block> {
    let mut blocks: Vec<Block> = Vec::new();
    let mut cur: Option<Block> = None;
    for (i, (kind, text)) in kinds.iter().enumerate() {
        match kind {
            Kind::Blank
            | Kind::Fence
            | Kind::Code
            | Kind::Ignored
            | Kind::Heading
            | Kind::Table => {
                if let Some(b) = cur.take() {
                    blocks.push(b);
                }
                if *kind != Kind::Blank {
                    blocks.push(Block {
                        kind: *kind,
                        start: i,
                        text: text.clone(),
                    });
                }
            }
            Kind::Para => {
                match cur.as_mut() {
                    Some(b) if b.kind == Kind::Para => {
                        b.text = join_wrapped(&b.text, text);
                    }
                    // 空行を挟まずに箇条書きへ続く本文行は項目の続き(インデント行と CommonMark の lazy continuation)
                    Some(b) if b.kind == Kind::List => {
                        b.text = join_wrapped(&b.text, text);
                    }
                    _ => {
                        if let Some(b) = cur.take() {
                            blocks.push(b);
                        }
                        cur = Some(Block {
                            kind: Kind::Para,
                            start: i,
                            text: text.clone(),
                        });
                    }
                }
            }
            Kind::Quote => match cur.as_mut() {
                Some(b) if b.kind == Kind::Quote => {
                    b.text = join_wrapped(&b.text, text);
                }
                _ => {
                    if let Some(b) = cur.take() {
                        blocks.push(b);
                    }
                    cur = Some(Block {
                        kind: Kind::Quote,
                        start: i,
                        text: text.clone(),
                    });
                }
            },
            Kind::List => {
                if let Some(b) = cur.take() {
                    blocks.push(b);
                }
                cur = Some(Block {
                    kind: Kind::List,
                    start: i,
                    text: text.clone(),
                });
            }
        }
    }
    if let Some(b) = cur.take() {
        blocks.push(b);
    }
    blocks
}

fn check_text(file: &str, content: &str) -> Vec<Finding> {
    let lines: Vec<String> = content.lines().map(|l| l.to_string()).collect();
    let mut start = 0;
    if lines.first().map(|l| l.trim()) == Some("---") {
        if let Some(end) = lines
            .iter()
            .enumerate()
            .skip(1)
            .find(|(_, l)| l.trim() == "---")
        {
            start = end.0 + 1;
        }
    }
    let kinds = classify_lines(&lines, start);
    let blocks = build_blocks(&kinds);
    let mut findings: Vec<Finding> = Vec::new();

    let mut add =
        |code: &'static str, lineno: usize, msg: String, snippet: &str, severity: &'static str| {
            findings.push(Finding {
                file: file.to_string(),
                line: lineno + 1,
                code,
                severity,
                message: msg,
                snippet: truncate_chars(snippet, 70),
            });
        };

    // MAIN: 節の冒頭
    for (n, b) in blocks.iter().enumerate() {
        if b.kind != Kind::Heading {
            continue;
        }
        for b2 in &blocks[n + 1..] {
            match b2.kind {
                Kind::Fence | Kind::Code | Kind::Ignored => continue,
                Kind::Heading => break, // 空の節(親見出し)は対象外
                Kind::Table => add(
                    "MAIN",
                    b2.start,
                    "節の冒頭が表で始まる(見出しが主文を兼ねているか確認する)".into(),
                    lines[b2.start].trim(),
                    "INFO",
                ),
                Kind::List => add(
                    "MAIN",
                    b2.start,
                    "節の冒頭が箇条書きで始まる(見出しが主文を兼ねているか確認する)".into(),
                    lines[b2.start].trim(),
                    "INFO",
                ),
                Kind::Para | Kind::Quote if !has_complete_sentence(&b2.text) => {
                    add(
                        "MAIN",
                        b2.start,
                        "節の冒頭の段落が句点で終わる文を含まない".into(),
                        &b2.text,
                        "WARN",
                    );
                }
                Kind::Para | Kind::Quote | Kind::Blank => {}
            }
            break;
        }
    }

    // 段落単位・文単位の検査
    for b in &blocks {
        match b.kind {
            Kind::Heading | Kind::Fence | Kind::Code | Kind::Ignored | Kind::Blank => continue,
            Kind::Table => {
                let unquoted = re_quoted().replace_all(&b.text, "「」");
                if re_context_words().is_match(&unquoted) {
                    add(
                        "CONTEXT",
                        b.start,
                        "直前の会話を前提にする語がある".into(),
                        b.text.trim(),
                        "WARN",
                    );
                }
                continue;
            }
            _ => {}
        }
        let plain = strip_inline(&b.text);
        if plain.is_empty() {
            continue;
        }
        let unquoted = re_quoted().replace_all(&plain, "「」");
        if let Some(m) = re_context_words().find(&unquoted) {
            add(
                "CONTEXT",
                b.start,
                format!("直前の会話を前提にする語がある: {}", m.as_str()),
                &plain,
                "WARN",
            );
        }

        let tail = strip_closers(&plain);
        match b.kind {
            Kind::Para | Kind::Quote
                if last_char(tail).is_some_and(|c| !PARAGRAPH_END.contains(&c)) =>
            {
                add(
                    "TAIGEN",
                    b.start,
                    "段落が句点で終わっていない".into(),
                    &plain,
                    "WARN",
                );
            }
            Kind::List => {
                let unfinished = last_char(tail).is_some_and(|c| !PARAGRAPH_END.contains(&c));
                if plain.chars().count() >= 20 && !plain.ends_with(':') && unfinished {
                    add(
                        "LIST",
                        b.start,
                        "20 字以上の箇条書きが句点で終わっていない(体言止め)".into(),
                        &plain,
                        "WARN",
                    );
                }
            }
            _ => {}
        }

        for (n_sent, (sent, ended)) in sentences(&plain).iter().enumerate() {
            let core: String = if *ended {
                let mut cs = sent.chars();
                cs.next_back();
                cs.collect()
            } else {
                sent.clone()
            };
            let body_owned = strip_trailing_paren(&core);
            let body = strip_closers(&body_owned);
            let is_label = b.kind == Kind::List && n_sent == 0 && body.chars().count() <= 10;
            if *ended && !is_label {
                if let Some(c) = last_char(body) {
                    if !is_hiragana(c) {
                        add(
                            "TAIGEN",
                            b.start,
                            "文が名詞で終わっている(体言止め)".into(),
                            sent,
                            "WARN",
                        );
                    }
                }
            }
            let visible = outside_parens(&core);
            let clauses: Vec<&str> = visible
                .split('、')
                .map(|c| c.trim())
                .filter(|c| !c.is_empty())
                .collect();
            let verbal_all = clauses.iter().filter(|c| is_verbal(c)).count();
            let verbal_nonfinal = clauses
                .iter()
                .take(clauses.len().saturating_sub(1))
                .filter(|c| is_verbal(c))
                .count();
            let n_touten = visible.matches('、').count();
            if n_touten >= 3 && verbal_all >= 2 && verbal_nonfinal >= 1 {
                add(
                    "TOUTEN",
                    b.start,
                    format!("読点が {n_touten} つあり、節がつながれている"),
                    sent,
                    "WARN",
                );
            }
            if clauses.len() >= 2 {
                let hit = clauses
                    .iter()
                    .filter(|c| {
                        re_tsuiku_clause().is_match(c) && !last_char(c).is_some_and(is_hiragana)
                    })
                    .count();
                if hit >= 2 {
                    add(
                        "TSUIKU",
                        b.start,
                        "動詞のない「X は A、Y は B」型の並列(対句の疑い)".into(),
                        sent,
                        "WARN",
                    );
                }
            }
        }
    }
    findings
}

fn check_file(path: &Path) -> Result<Vec<Finding>, String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: cannot read: {e}", path.display()))?;
    Ok(check_text(&path.display().to_string(), &content))
}

fn find_yomiyasu(explicit: Option<&Path>) -> Option<PathBuf> {
    if let Some(p) = explicit {
        return if p.exists() {
            Some(p.to_path_buf())
        } else {
            None
        };
    }
    if let Ok(p) = std::env::var("STANDALONE_CHECK_YOMIYASU") {
        let p = PathBuf::from(p);
        if p.exists() {
            return Some(p);
        }
    }
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    for rel in [
        ".claude/skills/yomiyasu/scripts/yomiyasu_lint.py",
        ".copilot/skills/yomiyasu/scripts/yomiyasu_lint.py",
    ] {
        let p = home.join(rel);
        if p.exists() {
            return Some(p);
        }
    }
    None
}

/// yomiyasu の lint を実行する。戻り値は (status, findings, detail)。
/// status は "ok" か "failed"。失敗の理由は detail に入れ、呼び出し側が stderr に出す。
fn run_yomiyasu(script: &Path, file: &Path) -> (&'static str, Vec<serde_json::Value>, String) {
    let is_py = script.extension().is_some_and(|e| e == "py");
    let output = if is_py {
        Command::new("python3")
            .arg(script)
            .arg(file)
            .arg("--json")
            .output()
    } else {
        Command::new(script).arg(file).arg("--json").output()
    };
    let output = match output {
        Ok(o) => o,
        Err(e) => return ("failed", Vec::new(), format!("起動できない: {e}")),
    };
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    if !output.status.success() {
        return (
            "failed",
            Vec::new(),
            format!(
                "lint が異常終了した({}): {}",
                output.status,
                truncate_chars(detail, 200)
            ),
        );
    }
    let parsed: YomiyasuReport =
        match serde_json::from_slice::<serde_json::Map<String, serde_json::Value>>(&output.stdout)
            .and_then(|obj| serde_json::from_value(serde_json::Value::Object(obj)))
        {
            Ok(v) => v,
            Err(e) => {
                return (
                    "failed",
                    Vec::new(),
                    format!(
                        "出力を JSON レポートとして解釈できない: {e}; {}",
                        truncate_chars(detail, 200)
                    ),
                );
            }
        };
    let mut kept = Vec::new();
    for f in parsed.findings {
        if !matches!(
            f.severity.to_lowercase().as_str(),
            "info" | "warn" | "error"
        ) {
            return (
                "failed",
                Vec::new(),
                format!("lint の応答形式が不正: 未知の severity {:?}", f.severity),
            );
        }
        if re_yomiyasu_ignore().is_match(&f.message)
            || (f.snippet.contains("正本") && f.message.contains("スロップ"))
        {
            continue;
        }
        let mut obj = f.extra;
        obj.insert("severity".into(), serde_json::Value::String(f.severity));
        obj.insert("message".into(), serde_json::Value::String(f.message));
        obj.insert("snippet".into(), serde_json::Value::String(f.snippet));
        obj.insert(
            "file".into(),
            serde_json::Value::String(file.display().to_string()),
        );
        kept.push(serde_json::Value::Object(obj));
    }
    ("ok", kept, String::new())
}

#[derive(Serialize)]
struct JsonReport<'a> {
    findings: &'a [Finding],
    yomiyasu: &'a [serde_json::Value],
    yomiyasu_status: &'a BTreeMap<String, &'static str>,
}

struct Args {
    files: Vec<PathBuf>,
    with_yomiyasu: bool,
    json: bool,
    yomiyasu_script: Option<PathBuf>,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        files: Vec::new(),
        with_yomiyasu: false,
        json: false,
        yomiyasu_script: None,
    };
    let mut it = std::env::args_os().skip(1);
    while let Some(a) = it.next() {
        let s = a.to_string_lossy();
        match s.as_ref() {
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            "--with-yomiyasu" => args.with_yomiyasu = true,
            "--json" => args.json = true,
            "--yomiyasu-script" => {
                let p = it.next().ok_or("--yomiyasu-script にはパスが要る")?;
                args.yomiyasu_script = Some(PathBuf::from(p));
                args.with_yomiyasu = true;
            }
            _ if s.starts_with('-') => return Err(format!("不明なオプション: {s}\n\n{USAGE}")),
            _ => args.files.push(PathBuf::from(a)),
        }
    }
    if args.files.is_empty() {
        return Err(format!("検査するファイルを 1 つ以上指定する\n\n{USAGE}"));
    }
    Ok(args)
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(2);
        }
    };

    let mut all_findings: Vec<Finding> = Vec::new();
    let mut yomi: Vec<serde_json::Value> = Vec::new();
    let mut yomi_status: BTreeMap<String, &'static str> = BTreeMap::new();
    let mut had_error = false;

    let script = if args.with_yomiyasu {
        find_yomiyasu(args.yomiyasu_script.as_deref())
    } else {
        None
    };
    if args.with_yomiyasu && script.is_none() {
        eprintln!("yomiyasu_lint.py が見つからない(--yomiyasu-script、STANDALONE_CHECK_YOMIYASU、~/.claude/skills/yomiyasu/scripts、~/.copilot/skills/yomiyasu/scripts の順に探した)");
    }

    for f in &args.files {
        match check_file(f) {
            Ok(res) => all_findings.extend(res),
            Err(e) => {
                eprintln!("{e}");
                had_error = true;
                continue;
            }
        }
        if args.with_yomiyasu {
            let key = f.display().to_string();
            match &script {
                None => {
                    yomi_status.insert(key, "unavailable");
                }
                Some(s) => {
                    let (status, items, detail) = run_yomiyasu(s, f);
                    yomi_status.insert(key.clone(), status);
                    if status != "ok" {
                        eprintln!("{key}: yomiyasu を実行できなかった: {detail}");
                        continue;
                    }
                    yomi.extend(items);
                }
            }
        }
    }

    let yomi_failed = yomi_status.values().any(|s| *s != "ok");
    let yomi_warns = yomi
        .iter()
        .filter(|y| {
            let sev = y
                .get("severity")
                .and_then(|s| s.as_str())
                .unwrap_or("warn")
                .to_lowercase();
            sev == "warn" || sev == "error"
        })
        .count();

    if args.json {
        let report = JsonReport {
            findings: &all_findings,
            yomiyasu: &yomi,
            yomiyasu_status: &yomi_status,
        };
        println!(
            "{}",
            serde_json::to_string_pretty(&report).expect("serializable")
        );
    } else {
        if all_findings.is_empty() {
            println!("[PASS] standalone-check: 指摘なし");
        } else {
            println!("[NOTICE] standalone-check: {} 件", all_findings.len());
            for f in &all_findings {
                println!(
                    "{}:L{}: [{}][{}] {}",
                    f.file, f.line, f.severity, f.code, f.message
                );
                println!("  > {}", f.snippet);
            }
        }
        if args.with_yomiyasu {
            println!("{}", "-".repeat(60));
            let skipped = yomi_status.values().filter(|s| **s != "ok").count();
            if skipped > 0 {
                println!("[SKIP] yomiyasu: 実行できなかったファイルがある({skipped} 件。理由は stderr)。検査済みとはみなさない");
            }
            if yomi_status.values().any(|s| *s == "ok") {
                if yomi.is_empty() {
                    println!("[PASS] yomiyasu: 読む対象の指摘なし");
                } else {
                    println!(
                        "[NOTICE] yomiyasu: {} 件(うち warn {yomi_warns}。半角空白・太字頻度・箇条書き比率・「正本」は除外)",
                        yomi.len()
                    );
                    for y in &yomi {
                        let file = y.get("file").and_then(|v| v.as_str()).unwrap_or("?");
                        let line = y
                            .get("line")
                            .map(|v| v.to_string())
                            .unwrap_or_else(|| "?".into());
                        let sev = y.get("severity").and_then(|v| v.as_str()).unwrap_or("warn");
                        let msg = y.get("message").and_then(|v| v.as_str()).unwrap_or("");
                        let snip = y.get("snippet").and_then(|v| v.as_str()).unwrap_or("");
                        println!("{file}:L{line}: [{sev}] {msg}");
                        println!("  > {}", truncate_chars(snip, 70));
                    }
                }
            }
        }
    }

    if had_error || yomi_failed {
        return ExitCode::from(2);
    }
    let warns = all_findings.iter().filter(|f| f.severity == "WARN").count();
    if warns > 0 || yomi_warns > 0 {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sentences_do_not_split_inside_parens() {
        let v = sentences("作る（推奨。理由は後述）。次の文。");
        assert_eq!(v.len(), 2);
        assert_eq!(v[0].0, "作る（推奨。理由は後述）。");
        assert!(v[0].1);
    }

    #[test]
    fn sentences_keep_unfinished_rest() {
        let v = sentences("終わる。途中");
        assert_eq!(
            v,
            vec![("終わる。".to_string(), true), ("途中".to_string(), false)]
        );
    }

    #[test]
    fn join_wrapped_handles_japanese_and_ascii() {
        assert_eq!(
            join_wrapped("依頼し、", "日程を取る。"),
            "依頼し、日程を取る。"
        );
        assert_eq!(join_wrapped("run 1", "graph"), "run 1 graph");
        assert_eq!(join_wrapped("", "x"), "x");
    }

    #[test]
    fn is_verbal_rejects_particles_and_nouns() {
        assert!(is_verbal("書く"));
        assert!(is_verbal("済ませず"));
        assert!(!is_verbal("ファイル名は"));
        assert!(!is_verbal("依頼者"));
        assert!(!is_verbal("誰か"));
    }

    #[test]
    fn strip_trailing_paren_exposes_verb() {
        assert_eq!(strip_trailing_paren("書き換えない(code)"), "書き換えない");
        assert_eq!(strip_trailing_paren("置く（推奨。E3 と同じ）"), "置く");
    }

    #[test]
    fn outside_parens_drops_nested_content() {
        assert_eq!(
            outside_parens("役割表(役割、誰か)を置く、はい"),
            "役割表を置く、はい"
        );
    }

    #[test]
    fn soft_wrap_is_one_paragraph() {
        let f = check_text(
            "t.md",
            "# 手順\n\n依頼者は弁護士に注釈を依頼し、\n日程を 2 回分取る。\n",
        );
        assert!(f.is_empty(), "{f:?}");
    }

    #[test]
    fn list_lazy_continuation_and_multiline_quote_pass() {
        let f = check_text(
            "t.md",
            "# 手順\n\n> 位置づけは、\n> この文書の入口である。\n\n- 依頼者は弁護士に注釈を依頼し、\n  日程を 2 回分取る。\n- DS は κ を出し、\n報告を 1 枚書く。\n",
        );
        assert!(f.is_empty(), "{f:?}");
    }

    #[test]
    fn senpo_is_context() {
        let f = check_text("t.md", "# 確認\n\n先方が確認する。\n");
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].code, "CONTEXT");
    }

    #[test]
    fn english_paragraph_ending_with_period_passes() {
        let f = check_text(
            "t.md",
            "# Title\n\nThis directory vendors the upstream skill without modification.\n",
        );
        assert!(f.is_empty(), "{f:?}");
    }

    #[test]
    fn version_number_is_not_a_sentence_break() {
        let v = sentences("v1.0.0 を同梱する。");
        assert_eq!(v.len(), 1);
    }

    #[test]
    fn frontmatter_is_skipped() {
        let f = check_text("t.md", "---\ntitle: x\n---\n# 題\n\n依頼者が確認する。\n");
        assert!(f.is_empty(), "{f:?}");
    }

    #[test]
    fn ignore_marker_skips_line() {
        let f = check_text(
            "t.md",
            "# 題\n\n依頼者が確認する。\n\n| 正解はこっち | <!-- standalone: ignore -->\n",
        );
        assert!(f.is_empty(), "{f:?}");
    }
}
