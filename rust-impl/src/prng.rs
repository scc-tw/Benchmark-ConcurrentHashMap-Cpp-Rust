//! xorshift64* PRNG implementation
//! CRITICAL: Must produce identical sequence to C++ implementation

/// xorshift64* PRNG
/// Reference: https://en.wikipedia.org/wiki/Xorshift#xorshift*
#[inline]
pub fn xorshift64star(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545F4914F6CDD1Du64)
}

/// Generate random number in range [0, max)
#[inline]
pub fn rand_range(state: &mut u64, max: u64) -> u64 {
    xorshift64star(state) % max
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prng_deterministic() {
        let mut state = 42u64;
        let v1 = xorshift64star(&mut state);

        let mut state2 = 42u64;
        let v2 = xorshift64star(&mut state2);

        assert_eq!(v1, v2);
    }
}
