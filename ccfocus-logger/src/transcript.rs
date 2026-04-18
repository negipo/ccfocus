use once_cell::sync::Lazy;
use regex::Regex;

static ASK_QMARK: Lazy<Regex> = Lazy::new(|| Regex::new(r"[?？]").unwrap());
static ASK_POLITE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(確認してください|試していただけ|確認していただけ|教えていただけ|教えてください)")
        .unwrap()
});

pub fn classify_has_question(text: &str) -> bool {
    let tail: String = text
        .lines()
        .map(|l| l.trim_end())
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .take(3)
        .collect::<Vec<_>>()
        .join("\n");
    ASK_QMARK.is_match(&tail) || ASK_POLITE.is_match(&tail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qmark_in_last_line_is_question() {
        assert!(classify_has_question("結果です。\nこれで進めていいですか?"));
    }

    #[test]
    fn fullwidth_qmark_is_question() {
        assert!(classify_has_question("どちらにしましょうか？"));
    }

    #[test]
    fn polite_request_is_question() {
        assert!(classify_has_question("ビルドしました。\n動作を確認してください"));
    }

    #[test]
    fn plain_done_report_is_not_question() {
        assert!(!classify_has_question("実装完了しました。\nテストも通っています。"));
    }

    #[test]
    fn dou_iu_is_not_question_without_qmark() {
        assert!(!classify_has_question("どういう設計になっているか整理しました。"));
    }

    #[test]
    fn qmark_outside_tail3_is_ignored() {
        let text = "?\n\n\n(1) 最初に\n(2) 次に\n(3) 最後に完了しました。";
        assert!(!classify_has_question(text));
    }

    #[test]
    fn empty_text_is_not_question() {
        assert!(!classify_has_question(""));
    }
}
