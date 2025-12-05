//! Memory measurement utilities

use std::fs;

/// Get peak resident set size in KB (VmHWM = High Water Mark)
pub fn get_peak_rss_kb() -> i64 {
    read_proc_status("VmHWM:")
}

/// Get current resident set size in KB
pub fn get_current_rss_kb() -> i64 {
    read_proc_status("VmRSS:")
}

fn read_proc_status(field: &str) -> i64 {
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|content| {
            content
                .lines()
                .find(|line| line.starts_with(field))
                .and_then(|line| line.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(-1)
}

/// Compute bytes per entry
pub fn bytes_per_entry(rss_kb: i64, num_entries: u64) -> f64 {
    if num_entries == 0 {
        return 0.0;
    }
    (rss_kb as f64 * 1024.0) / num_entries as f64
}

/// Compute overhead ratio (actual / theoretical minimum)
/// Theoretical minimum for u64 key + u64 value = 16 bytes
pub fn overhead_ratio(rss_kb: i64, num_entries: u64) -> f64 {
    bytes_per_entry(rss_kb, num_entries) / 16.0
}
