pub fn unique_tags(input: &str) -> Vec<String> {
    input.split(',').map(str::to_string).collect()
}
