//! Fast hash function for u64 keys
//! CRITICAL: Must produce identical hashes to C++ implementation

use std::hash::{BuildHasher, Hasher};

/// Fast hasher using FxHash-style multiplication
#[derive(Default, Clone)]
pub struct FastHasher {
    hash: u64,
}

impl Hasher for FastHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        // For u64 keys, this will be called via write_u64
        for &byte in bytes {
            self.hash = self
                .hash
                .wrapping_mul(0x517cc1b727220a95u64)
                .wrapping_add(byte as u64);
        }
    }

    #[inline]
    fn write_u64(&mut self, key: u64) {
        self.hash = key.wrapping_mul(0x517cc1b727220a95u64);
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

/// BuildHasher implementation for use with DashMap
#[derive(Default, Clone)]
pub struct BuildFastHasher;

impl BuildHasher for BuildFastHasher {
    type Hasher = FastHasher;

    #[inline]
    fn build_hasher(&self) -> FastHasher {
        FastHasher::default()
    }
}

/// Standalone hash function for verification
#[inline]
pub fn hash_u64(key: u64) -> u64 {
    key.wrapping_mul(0x517cc1b727220a95u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_deterministic() {
        assert_eq!(hash_u64(0), 0);
        assert_eq!(hash_u64(1), 0x517cc1b727220a95u64);
        assert_eq!(hash_u64(42), 42u64.wrapping_mul(0x517cc1b727220a95u64));
    }
}
