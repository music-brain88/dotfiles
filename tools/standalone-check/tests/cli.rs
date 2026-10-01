//! CLI の統合テスト。#638 のレビューで作った再現ケースを fixtures として固定する。
use std::path::PathBuf;
use std::process::{Command, Output};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_standalone-check"))
        .args(args)
        .env(
            "HOME",
            std::env::temp_dir().join("standalone-check-no-home"),
        )
        .env_remove("STANDALONE_CHECK_YOMIYASU")
        .output()
        .expect("binary runs")
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn warn_codes(o: &Output) -> Vec<String> {
    stdout(o)
        .lines()
        .filter(|l| l.contains("[WARN]["))
        .map(|l| {
            l.split("[WARN][")
                .nth(1)
                .unwrap()
                .split(']')
                .next()
                .unwrap()
                .to_string()
        })
        .collect()
}

#[test]
fn bad_sample_reports_six_warnings() {
    let o = run(&[fixture("bad_sample.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(1));
    let codes = warn_codes(&o);
    assert_eq!(codes.len(), 6, "{}", stdout(&o));
    for c in ["MAIN", "CONTEXT", "TAIGEN", "TSUIKU", "TOUTEN", "LIST"] {
        assert!(codes.iter().any(|x| x == c), "missing {c}: {codes:?}");
    }
}

#[test]
fn soft_wrapped_sentence_passes() {
    let o = run(&[fixture("wrap.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(0), "{}", stdout(&o));
    assert!(stdout(&o).contains("[PASS]"));
}

#[test]
fn list_continuation_and_multiline_quote_pass() {
    let o = run(&[fixture("listwrap.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(0), "{}", stdout(&o));
}

#[test]
fn truly_unfinished_paragraph_is_flagged() {
    let o = run(&[fixture("frag.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(1));
    let codes = warn_codes(&o);
    assert!(
        codes.iter().filter(|c| *c == "TAIGEN").count() >= 1,
        "{codes:?}"
    );
    assert!(codes.contains(&"MAIN".to_string()), "{codes:?}");
}

#[test]
fn senpo_is_context_warning() {
    let o = run(&[fixture("senpo.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(1));
    assert_eq!(warn_codes(&o), vec!["CONTEXT".to_string()]);
}

#[test]
fn yomiyasu_info_only_exits_zero_and_filters_ignored() {
    let o = run(&[
        fixture("ok.md").to_str().unwrap(),
        "--yomiyasu-script",
        fixture("fake_yomiyasu_info.sh").to_str().unwrap(),
    ]);
    let out = stdout(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    assert!(out.contains("[info]"), "{out}");
    assert!(
        !out.contains("半角空白が"),
        "読まない指摘が表示された: {out}"
    );
    assert!(out.contains("うち warn 0"), "{out}");
}

#[test]
fn yomiyasu_warn_exits_one() {
    let o = run(&[
        fixture("ok.md").to_str().unwrap(),
        "--yomiyasu-script",
        fixture("fake_yomiyasu_warn.sh").to_str().unwrap(),
    ]);
    assert_eq!(o.status.code(), Some(1), "{}", stdout(&o));
    assert!(stdout(&o).contains("[warn]"));
}

#[test]
fn missing_yomiyasu_is_skip_with_exit_two() {
    let o = run(&[fixture("ok.md").to_str().unwrap(), "--with-yomiyasu"]);
    assert_eq!(o.status.code(), Some(2), "{}", stdout(&o));
    assert!(stdout(&o).contains("[SKIP] yomiyasu"));
    assert!(!stdout(&o).contains("[PASS] yomiyasu"));
    assert!(String::from_utf8_lossy(&o.stderr).contains("見つからない"));
}

#[test]
fn broken_yomiyasu_keeps_json_valid_and_exits_two() {
    let o = run(&[
        fixture("ok.md").to_str().unwrap(),
        "--json",
        "--yomiyasu-script",
        fixture("fake_yomiyasu_broken.sh").to_str().unwrap(),
    ]);
    assert_eq!(o.status.code(), Some(2));
    let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("stdout is valid JSON");
    let status = v["yomiyasu_status"].as_object().unwrap();
    assert_eq!(status.values().next().unwrap(), "failed");
    assert!(String::from_utf8_lossy(&o.stderr).contains("解釈できない"));
}

#[test]
fn json_output_has_expected_shape() {
    let o = run(&[fixture("senpo.md").to_str().unwrap(), "--json"]);
    let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
    assert_eq!(v["findings"][0]["code"], "CONTEXT");
    assert_eq!(v["findings"][0]["severity"], "WARN");
    assert_eq!(v["findings"][0]["line"], 3);
    assert!(v["yomiyasu"].as_array().unwrap().is_empty());
}

#[test]
fn unreadable_file_exits_two() {
    let o = run(&[fixture("does-not-exist.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(2));
}

#[test]
fn help_exits_zero() {
    let o = run(&["--help"]);
    assert_eq!(o.status.code(), Some(0));
    assert!(stdout(&o).contains("standalone-check FILE"));
}
