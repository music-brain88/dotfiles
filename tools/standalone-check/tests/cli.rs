//! CLI の統合テスト。#638 のレビューで作った再現ケースを fixtures として固定する。
use std::path::PathBuf;
use std::process::{Command, Output};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

fn run(args: &[&str]) -> Output {
    run_with_env(args, &[])
}

fn run_with_env(args: &[&str], env: &[(&str, &str)]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_standalone-check"))
        .args(args)
        .env(
            "HOME",
            std::env::temp_dir().join("standalone-check-no-home"),
        )
        .env_remove("STANDALONE_CHECK_YOMIYASU")
        .envs(env.iter().copied())
        .output()
        .expect("binary runs")
}

fn run_yomiyasu_report(report: &str, exit_code: &str, json: bool) -> Output {
    let document = fixture("ok.md");
    let script = fixture("fake_yomiyasu_report.sh");
    let mut args = vec![
        document.to_str().unwrap(),
        "--yomiyasu-script",
        script.to_str().unwrap(),
    ];
    if json {
        args.push("--json");
    }
    run_with_env(
        &args,
        &[
            ("STANDALONE_CHECK_TEST_REPORT", report),
            ("STANDALONE_CHECK_TEST_EXIT_CODE", exit_code),
        ],
    )
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
fn bad_sample_reports_five_warnings_and_table_info() {
    let o = run(&[fixture("bad_sample.md").to_str().unwrap()]);
    assert_eq!(o.status.code(), Some(1));
    let codes = warn_codes(&o);
    assert_eq!(codes.len(), 5, "{}", stdout(&o));
    for c in ["CONTEXT", "TAIGEN", "TSUIKU", "TOUTEN", "LIST"] {
        assert!(codes.iter().any(|x| x == c), "missing {c}: {codes:?}");
    }
    // 見出し直下の表は箇条書きと同じく INFO(Issue #650)
    assert!(stdout(&o).contains("[INFO][MAIN] 節の冒頭が表で始まる"));
}

#[test]
fn table_right_after_heading_is_info_and_exits_zero() {
    let o = run(&[fixture("table_head.md").to_str().unwrap()]);
    let out = stdout(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    assert!(warn_codes(&o).is_empty(), "{out}");
    assert!(
        out.contains("[INFO][MAIN] 節の冒頭が表で始まる(見出しが主文を兼ねているか確認する)"),
        "{out}"
    );
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
        !out.contains("太字の頻度"),
        "読まない指摘が表示された: {out}"
    );
    assert!(out.contains("うち warn 0"), "{out}");
}

/// 偽の lint に report を返させ、(終了コード, 除外の後に残った指摘) を返す。
/// Runs the fake lint with `report` and returns (exit code, findings kept after filtering).
fn yomiyasu_kept(report: &str) -> (Option<i32>, Vec<serde_json::Value>) {
    let o = run_yomiyasu_report(report, "0", true);
    let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
    assert_eq!(
        v["yomiyasu_status"]
            .as_object()
            .unwrap()
            .values()
            .next()
            .unwrap(),
        "ok",
        "report: {report}"
    );
    (o.status.code(), v["yomiyasu"].as_array().unwrap().clone())
}

fn kept_messages(kept: &[serde_json::Value]) -> Vec<&str> {
    kept.iter()
        .map(|f| f["message"].as_str().unwrap())
        .collect()
}

#[test]
fn yomiyasu_excess_bold_and_excess_list_are_dropped() {
    let (code, kept) = yomiyasu_kept(
        r#"{"findings":[
          {"rule":"excess_bold","line":1,"severity":"warn","message":"太字の頻度（1,000字あたり 8.0個）が設定した目安を超えています（推奨: 2.0以下）。","snippet":"**a**"},
          {"rule":"excess_list","line":1,"severity":"warn","message":"箇条書きの比率（60.0%）が設定した目安を超えています（推奨: 15%以下）。","snippet":"- a"}
        ]}"#,
    );
    assert!(kept.is_empty(), "{kept:?}");
    assert_eq!(code, Some(0));
}

#[test]
fn yomiyasu_slop_vocabulary_drops_only_seihon() {
    let (code, kept) = yomiyasu_kept(
        r#"{"findings":[
          {"rule":"slop_vocabulary","line":1,"severity":"warn","message":"AI頻出語彙「正本」が含まれています。","snippet":"正本を更新する。"},
          {"rule":"slop_vocabulary","line":2,"severity":"warn","message":"AI頻出語彙「土台」が含まれています。","snippet":"土台を作る。"}
        ]}"#,
    );
    assert_eq!(
        kept_messages(&kept),
        vec!["AI頻出語彙「土台」が含まれています。"]
    );
    assert_eq!(code, Some(1));
}

#[test]
fn yomiyasu_slop_vocabulary_on_same_line_keeps_other_word() {
    // v2.5.0 の snippet は行全体なので、snippet ではなく message の「<語>」で見分ける
    // Upstream v2.5.0 puts the whole line in snippet, so the word is matched in the message
    let (code, kept) = yomiyasu_kept(
        r#"{"findings":[
          {"rule":"slop_vocabulary","line":1,"severity":"warn","message":"AI頻出語彙「正本」が含まれています。","snippet":"正本の土台を作る。"},
          {"rule":"slop_vocabulary","line":1,"severity":"warn","message":"AI頻出語彙「土台」が含まれています。","snippet":"正本の土台を作る。"}
        ]}"#,
    );
    assert_eq!(
        kept_messages(&kept),
        vec!["AI頻出語彙「土台」が含まれています。"]
    );
    assert_eq!(code, Some(1));
}

#[test]
fn yomiyasu_findings_without_rule_id_are_kept() {
    // rule を持たない指摘(rule が文字列でない指摘を含む)は、message の文言によらず残す。
    // 和欧文間の半角空白の指摘も、上流 v2 が出さないので除外しない
    // Findings without a string rule are kept whatever the message says
    let (code, kept) = yomiyasu_kept(
        r#"{"findings":[
          {"line":1,"severity":"warn","message":"太字の頻度（1,000字あたり 8.0個）が設定した目安を超えています。","snippet":"**a**"},
          {"rule":null,"line":2,"severity":"warn","message":"箇条書きの比率（60.0%）が設定した目安を超えています。","snippet":"- a"},
          {"rule":"unnatural_halfwidth_space","line":3,"severity":"warn","message":"英単語の前後に不要な半角空白が空けられています。","snippet":"run 1 の"}
        ]}"#,
    );
    assert_eq!(kept.len(), 3, "{kept:?}");
    assert_eq!(code, Some(1));
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
fn failing_yomiyasu_with_valid_json_exits_two() {
    for report in [
        r#"{"findings":[]}"#,
        r#"{"findings":[{"severity":"warn","message":"確認候補","snippet":"結果を確認する。"}]}"#,
    ] {
        let o = run_yomiyasu_report(report, "2", true);
        assert_eq!(o.status.code(), Some(2), "{}", stdout(&o));
        let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
        assert_eq!(
            v["yomiyasu_status"]
                .as_object()
                .unwrap()
                .values()
                .next()
                .unwrap(),
            "failed"
        );
        assert!(v["yomiyasu"].as_array().unwrap().is_empty());
        let stderr = String::from_utf8_lossy(&o.stderr);
        assert!(stderr.contains("異常終了"), "{stderr}");
        assert!(stderr.contains("exit status: 2"), "{stderr}");
        assert!(stderr.contains("fake lint failed"), "{stderr}");
    }
}

#[test]
fn invalid_yomiyasu_report_shapes_exit_two() {
    for report in [
        "null",
        "[]",
        "[[]]",
        "{}",
        r#"{"findings":null}"#,
        r#"{"findings":{}}"#,
        r#"{"findings":"invalid"}"#,
        r#"{"findings":[null]}"#,
        r#"{"findings":["invalid"]}"#,
        r#"{"findings":[["warn","message","snippet"]]}"#,
        r#"{"findings":[{"message":42,"snippet":"x"}]}"#,
        r#"{"findings":[{"message":"x","snippet":false}]}"#,
        r#"{"findings":[{"message":"x","snippet":"x","severity":7}]}"#,
        r#"{"findings":[{"message":"x","snippet":"x","severity":null}]}"#,
        r#"{"findings":[{"message":"x","snippet":"x","severity":"unknown"}]}"#,
        r#"{"findings":[{"message":"半角空白","snippet":"x","severity":"unknown"}]}"#,
        r#"{"findings":[{"message":"x"}]}"#,
        r#"{"findings":[{"snippet":"x"}]}"#,
    ] {
        let o = run_yomiyasu_report(report, "0", true);
        assert_eq!(o.status.code(), Some(2), "report: {report}\n{}", stdout(&o));
        let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
        assert_eq!(
            v["yomiyasu_status"]
                .as_object()
                .unwrap()
                .values()
                .next()
                .unwrap(),
            "failed",
            "report: {report}"
        );
        assert!(v["yomiyasu"].as_array().unwrap().is_empty());
        assert!(!o.stderr.is_empty(), "report: {report}");
    }
}

#[test]
fn valid_empty_yomiyasu_report_passes() {
    let o = run_yomiyasu_report(r#"{"findings":[]}"#, "0", true);
    assert_eq!(o.status.code(), Some(0), "{}", stdout(&o));
    let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
    assert_eq!(
        v["yomiyasu_status"]
            .as_object()
            .unwrap()
            .values()
            .next()
            .unwrap(),
        "ok"
    );
    assert!(v["yomiyasu"].as_array().unwrap().is_empty());
    assert!(o.stderr.is_empty());
}

#[test]
fn yomiyasu_default_severity_and_extra_fields_are_preserved() {
    let o = run_yomiyasu_report(
        r#"{"findings":[{"line":3,"rule":"custom","message":"確認候補","snippet":"結果を確認する。","file":"stale.md","context":{"source":"test"}}]}"#,
        "0",
        true,
    );
    assert_eq!(o.status.code(), Some(1), "{}", stdout(&o));
    let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
    let f = &v["yomiyasu"][0];
    assert_eq!(f["severity"], "warn");
    assert_eq!(f["line"], 3);
    assert_eq!(f["rule"], "custom");
    assert_eq!(f["context"]["source"], "test");
    assert_eq!(f["file"], fixture("ok.md").to_str().unwrap());
}

#[test]
fn yomiyasu_severity_remains_case_insensitive() {
    for (severity, expected) in [("INFO", 0), ("WARN", 1), ("ERROR", 1)] {
        let report = format!(
            r#"{{"findings":[{{"severity":"{severity}","message":"確認候補","snippet":"結果を確認する。"}}]}}"#
        );
        let o = run_yomiyasu_report(&report, "0", true);
        assert_eq!(o.status.code(), Some(expected), "{}", stdout(&o));
        let v: serde_json::Value = serde_json::from_str(&stdout(&o)).expect("valid JSON");
        assert_eq!(v["yomiyasu"][0]["severity"], severity);
    }
}

#[test]
fn invalid_yomiyasu_report_is_skip_not_pass() {
    for exit_code in ["0", "2"] {
        let o = run_yomiyasu_report(r#"{"findings":"invalid"}"#, exit_code, false);
        assert_eq!(o.status.code(), Some(2), "{}", stdout(&o));
        assert!(stdout(&o).contains("[SKIP] yomiyasu"));
        assert!(!stdout(&o).contains("[PASS] yomiyasu"));
    }
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
