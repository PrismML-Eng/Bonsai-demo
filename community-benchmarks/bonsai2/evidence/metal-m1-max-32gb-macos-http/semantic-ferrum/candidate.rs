pub fn unique_tags(input: &str) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    input
        .split(',')
        .map(str::trim)
        .filter(|tag| !tag.is_empty())
        .map(|tag| tag.to_ascii_lowercase())
        .filter_map(|tag| seen.insert(tag.clone()).then_some(tag))
        .collect()
}
