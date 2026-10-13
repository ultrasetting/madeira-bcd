#!/usr/bin/env python3
"""Keep a code invalidation from waiting on its own thread's write hold.

Stardew Valley with FEX_SMCCHECKS=full (2026-10-12 20:28): the full validator
found the stale .NET stub and dropped its block, then the game's main thread
parked for good on CodeInvalidationMutex, which that same thread write-owned:

  [fexlock] STUCK write-wait on mutex ... write-owned=true ... owner tid=00a8
  [fexlock] STUCK read-wait  on mutex ... (the finalizer thread, behind it)

The mutex is not recursive. An invalidation runs with it write-held, and work
done under it can come back into InvalidationTracker on the same thread: the
call-return stack reset decommits and recommits through VirtualFree and
VirtualAlloc (FEXCore::Allocator::VirtualDontNeed), whose memory notifications
invalidate again. The nested call then waits for the lock its own caller holds.

With MADEIRA_FEX_INVAL_NESTED=1, InvalidateIntervalInternal and
HandleRWXAccessViolation take the mutex through the nested-aware acquire the
mutex already has (ios_lock_write_nested_aware): a thread that already
write-owns it runs the invalidation under the outer hold instead of parking,
and only an acquire that really locked unlocks. Any other caller locks exactly
as before. The nested grants are counted (logging there could allocate under
the hold) and reported by the outer holder after it unlocks.

Also names, once each up to a cap, the blocks the full validator drops
([smc-changed]), so a log says which compiled code went stale.

Default off: set in a game's own file. Applied by tools/build-xtajit64.sh
after the other ARM64EC overlays; the pinned submodule is never updated.
"""
from pathlib import Path
import sys

MARKER = "madeira-bcd: inval-nested v1"
TRACKER = "Source/Windows/Common/InvalidationTracker.cpp"
CORE = "FEXCore/Source/Interface/Core/Core.cpp"

HELPER = '''#include "InvalidationTracker.h"

/* madeira-bcd: inval-nested v1 (tools/patch-fex-ios-inval-nested.py).
 * CodeInvalidationMutex is not recursive, and work done under its write hold
 * (the call-return stack reset decommits through VirtualFree) can re-enter the
 * tracker on the same thread. With MADEIRA_FEX_INVAL_NESTED=1 such a nested
 * acquire runs under the outer hold instead of parking on itself. */
namespace {
bool IosInvalNestedEnabled() {
  static std::atomic<int> Cached {-1};
  int Value = Cached.load(std::memory_order_relaxed);
  if (Value < 0) {
    const char* Env = getenv("MADEIRA_FEX_INVAL_NESTED");
    Value = (Env && Env[0] == '1' && Env[1] == '\\0') ? 1 : 0;
    Cached.store(Value, std::memory_order_relaxed);
  }
  return Value == 1;
}

std::atomic<uint64_t> IosInvalNestedGrants {0};
std::atomic<uint64_t> IosInvalNestedReported {0};

class IosCodeInvalidationLock final {
public:
  explicit IosCodeInvalidationLock(FEXCore::Utils::WritePriorityMutex::Mutex& Mutex)
    : M {Mutex} {
    if (IosInvalNestedEnabled()) {
      Locked = M.ios_lock_write_nested_aware();
      if (!Locked) {
        // No logging here: the outer holder may be inside an allocation.
        IosInvalNestedGrants.fetch_add(1, std::memory_order_relaxed);
      }
    } else {
      M.lock();
      Locked = true;
    }
  }

  ~IosCodeInvalidationLock() {
    if (!Locked) {
      return;
    }
    M.unlock();
    const auto Grants = IosInvalNestedGrants.load(std::memory_order_relaxed);
    auto Reported = IosInvalNestedReported.load(std::memory_order_relaxed);
    if (Grants != Reported && IosInvalNestedReported.compare_exchange_strong(Reported, Grants)) {
      LogMan::Msg::EFmt("[inval-nested] madeira-bcd: {} code invalidation(s) re-entered by the thread that held "
                        "CodeInvalidationMutex ran under that hold instead of waiting on it",
                        Grants);
    }
  }

  IosCodeInvalidationLock(const IosCodeInvalidationLock&) = delete;
  IosCodeInvalidationLock& operator=(const IosCodeInvalidationLock&) = delete;

private:
  FEXCore::Utils::WritePriorityMutex::Mutex& M;
  bool Locked {};
};
} // namespace
'''

EDITS = {
    TRACKER: (
        ('#include "InvalidationTracker.h"\n', HELPER),
        (
"""      std::scoped_lock Lock(CTX.GetCodeInvalidationMutex());

      InvalidateIntervalInternalLocked(FaultAddress & FEXCore::Utils::FEX_PAGE_MASK, FEXCore::Utils::FEX_PAGE_SIZE);
""",
"""      IosCodeInvalidationLock Lock(CTX.GetCodeInvalidationMutex()); // madeira-bcd: inval-nested v1

      InvalidateIntervalInternalLocked(FaultAddress & FEXCore::Utils::FEX_PAGE_MASK, FEXCore::Utils::FEX_PAGE_SIZE);
"""),
        (
"""void InvalidationTracker::InvalidateIntervalInternal(uint64_t Address, uint64_t Size) {
  std::scoped_lock CodeLock(CTX.GetCodeInvalidationMutex());
  InvalidateIntervalInternalLocked(Address, Size);
}
""",
"""void InvalidationTracker::InvalidateIntervalInternal(uint64_t Address, uint64_t Size) {
  IosCodeInvalidationLock CodeLock(CTX.GetCodeInvalidationMutex()); // madeira-bcd: inval-nested v1
  InvalidateIntervalInternalLocked(Address, Size);
}
"""),
    ),
    CORE: (
        (
"""void ContextImpl::ThreadRemoveCodeEntryFromJit(FEXCore::Core::CpuStateFrame* Frame, uint64_t GuestRIP) {
""",
"""void ContextImpl::ThreadRemoveCodeEntryFromJit(FEXCore::Core::CpuStateFrame* Frame, uint64_t GuestRIP) {
#ifdef FEX_IOS_HOST
  {
    // madeira-bcd: inval-nested v1 -- the full validator found compiled code whose guest bytes changed.
    static std::atomic<uint64_t> IosSmcChanged {0};
    const auto N = IosSmcChanged.fetch_add(1, std::memory_order_relaxed) + 1;
    if (N <= 32 || (N % 4096) == 0) {
      LogMan::Msg::EFmt("[smc-changed] madeira-bcd #{}: compiled code at {:#x} no longer matches its guest bytes; dropping it",
                        N, GuestRIP);
    }
  }
#endif
"""),
    ),
}


def patch(sources):
    """sources: {relative path: text}. Returns the patched texts."""
    out = dict(sources)
    for rel, edits in EDITS.items():
        text = out[rel]
        if MARKER in text:
            if any(text.count(new) != 1 for _, new in edits):
                raise ValueError(f"partial or changed inval-nested overlay in {rel}")
            continue
        for old, new in edits:
            if text.count(old) != 1:
                raise ValueError(f"anchor not found once in {rel}:\n{old}")
            text = text.replace(old, new, 1)
        out[rel] = text
    return out


if __name__ == "__main__":
    fex = Path(sys.argv[1])
    sources = {rel: (fex / rel).read_text() for rel in EDITS}
    try:
        result = patch(sources)
    except ValueError as error:
        sys.exit("patch-fex-ios-inval-nested: " + str(error))
    for rel, text in result.items():
        if text != sources[rel]:
            (fex / rel).write_text(text)
    print("FEX ARM64EC: a code invalidation re-entered by its own writer runs under that hold "
          "(MADEIRA_FEX_INVAL_NESTED=1); [smc-changed] names dropped blocks")
