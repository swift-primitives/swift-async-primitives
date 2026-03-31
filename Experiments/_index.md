# Experiments Index

| Directory | Purpose | Date | Toolchain | Status |
|-----------|---------|------|-----------|--------|
| inout-noncopyable-optional-closure-capture | Verify `inout Optional<~Copyable>` through `Mutex.withLock` for Slot-free channel send fast path | 2026-03-27 | Swift 6.3 | CONFIRMED (9/9 variants; compiler bug found: `o!` crashes IRGen, `.take()!` workaround) |
