use candidate::unique_tags;

#[test]
fn normalizes_and_deduplicates_in_first_occurrence_order() {
    assert_eq!(unique_tags(" Rust, AI, rust, Metal ,AI "), ["rust", "ai", "metal"]);
    assert_eq!(unique_tags("Z,a,Z,B,a"), ["z", "a", "b"]);
}

#[test]
fn handles_empty_whitespace_and_non_ascii_without_lowercasing_unicode() {
    assert!(unique_tags("").is_empty());
    assert!(unique_tags(" , \n,\t, ").is_empty());
    assert_eq!(unique_tags(" Ä, ä, Ä, RÜST, Rüst ,rüst "), ["Ä", "ä", "rÜst", "rüst"]);
    assert_eq!(unique_tags("  tag with spaces ,tag with spaces,comma-free "), ["tag with spaces", "comma-free"]);
}
