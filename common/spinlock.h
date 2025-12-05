#pragma once

#include <atomic>

namespace bench {

// Lightweight spinlock for short critical sections
// Avoids syscall overhead of std::mutex (~10x faster uncontended)
// Reference: WebKit WTF::Lock, Cosmopolitan nsync
class SpinLock {
    std::atomic_flag flag_ = ATOMIC_FLAG_INIT;

public:
    void lock() noexcept {
        while (flag_.test_and_set(std::memory_order_acquire)) {
            // Reduce power consumption and improve HT performance
            #if defined(__x86_64__) || defined(_M_X64)
            __builtin_ia32_pause();
            #elif defined(__aarch64__)
            __asm__ volatile("yield");
            #endif
        }
    }

    void unlock() noexcept {
        flag_.clear(std::memory_order_release);
    }

    // RAII guard
    class Guard {
        SpinLock& lock_;
    public:
        explicit Guard(SpinLock& lock) noexcept : lock_(lock) { lock_.lock(); }
        ~Guard() noexcept { lock_.unlock(); }
        Guard(const Guard&) = delete;
        Guard& operator=(const Guard&) = delete;
    };
};

} // namespace bench
