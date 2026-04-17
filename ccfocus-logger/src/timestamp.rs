use time::macros::format_description;
use time::OffsetDateTime;

pub fn now_iso8601() -> String {
    let fmt =
        format_description!("[year]-[month]-[day]T[hour]:[minute]:[second].[subsecond digits:3]Z");
    OffsetDateTime::now_utc().format(fmt).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::now_iso8601;

    #[test]
    fn format_matches_iso8601_utc_millis() {
        let s = now_iso8601();
        assert_eq!(s.len(), 24);
        assert!(s.ends_with('Z'));
        assert_eq!(&s[4..5], "-");
        assert_eq!(&s[7..8], "-");
        assert_eq!(&s[10..11], "T");
    }
}
