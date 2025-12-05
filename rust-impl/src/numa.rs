//! NUMA topology detection and thread pinning strategies

use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PinningStrategy {
    Compact, // All threads on consecutive cores (same socket)
    Spread,  // Threads distributed across NUMA nodes
}

impl PinningStrategy {
    pub fn as_str(&self) -> &'static str {
        match self {
            PinningStrategy::Compact => "compact",
            PinningStrategy::Spread => "spread",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "compact" => Some(PinningStrategy::Compact),
            "spread" => Some(PinningStrategy::Spread),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct NumaTopology {
    pub num_nodes: usize,
    pub node_cores: Vec<Vec<usize>>, // node_cores[node] = [core_ids]
}

impl NumaTopology {
    pub fn total_cores(&self) -> usize {
        self.node_cores.iter().map(|v| v.len()).sum()
    }
}

/// Parse CPU list format "0-3,8-11" into vector of core IDs
fn parse_cpulist(cpulist: &str) -> Vec<usize> {
    let mut cores = Vec::new();

    for token in cpulist.trim().split(',') {
        if let Some(dash_pos) = token.find('-') {
            let start: usize = token[..dash_pos].parse().unwrap_or(0);
            let end: usize = token[dash_pos + 1..].parse().unwrap_or(0);
            for i in start..=end {
                cores.push(i);
            }
        } else if let Ok(core) = token.parse() {
            cores.push(core);
        }
    }

    cores
}

/// Detect NUMA topology from /sys filesystem
pub fn detect_numa() -> NumaTopology {
    let base = Path::new("/sys/devices/system/node");
    let mut node_cores: Vec<Vec<usize>> = Vec::new();

    if base.exists() {
        if let Ok(entries) = fs::read_dir(base) {
            let mut nodes: Vec<(usize, Vec<usize>)> = Vec::new();

            for entry in entries.flatten() {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();

                if name_str.starts_with("node") {
                    if let Ok(node_id) = name_str[4..].parse::<usize>() {
                        let cpulist_path = entry.path().join("cpulist");
                        if let Ok(cpulist) = fs::read_to_string(&cpulist_path) {
                            let cores = parse_cpulist(&cpulist);
                            nodes.push((node_id, cores));
                        }
                    }
                }
            }

            // Sort by node ID and build vector
            nodes.sort_by_key(|(id, _)| *id);
            node_cores = nodes.into_iter().map(|(_, cores)| cores).collect();
        }
    }

    // Fallback: single node with all online CPUs
    if node_cores.is_empty() {
        if let Ok(online) = fs::read_to_string("/sys/devices/system/cpu/online") {
            node_cores.push(parse_cpulist(&online));
        } else {
            // Last resort: assume 1 core
            node_cores.push(vec![0]);
        }
    }

    NumaTopology {
        num_nodes: node_cores.len(),
        node_cores,
    }
}

/// Get core IDs for given strategy and thread count
pub fn get_cores(topo: &NumaTopology, strategy: PinningStrategy, num_threads: usize) -> Vec<usize> {
    let mut cores = Vec::with_capacity(num_threads);

    match strategy {
        PinningStrategy::Compact => {
            // Take consecutive cores from first node(s)
            for node_cores in &topo.node_cores {
                for &core in node_cores {
                    cores.push(core);
                    if cores.len() >= num_threads {
                        return cores;
                    }
                }
            }
        }
        PinningStrategy::Spread => {
            // Round-robin across nodes
            let max_per_node = topo.node_cores.iter().map(|v| v.len()).max().unwrap_or(0);

            for i in 0..max_per_node {
                for node_cores in &topo.node_cores {
                    if i < node_cores.len() {
                        cores.push(node_cores[i]);
                        if cores.len() >= num_threads {
                            return cores;
                        }
                    }
                }
            }
        }
    }

    cores
}
