//! Thread affinity (CPU pinning) via libc

use std::mem;

/// Pin current thread to specific CPU core
pub fn pin_thread(core_id: usize) -> Result<(), String> {
    unsafe {
        let mut cpuset: libc::cpu_set_t = mem::zeroed();
        libc::CPU_ZERO(&mut cpuset);
        libc::CPU_SET(core_id, &mut cpuset);

        let result = libc::pthread_setaffinity_np(
            libc::pthread_self(),
            mem::size_of::<libc::cpu_set_t>(),
            &cpuset,
        );

        if result == 0 {
            Ok(())
        } else {
            Err(format!(
                "Failed to pin thread to core {}: error {}",
                core_id, result
            ))
        }
    }
}
