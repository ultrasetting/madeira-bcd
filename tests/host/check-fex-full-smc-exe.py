#!/usr/bin/env python3
"""tools/patch-fex-ios-full-smc-exe.py and tools/patch-fex-ios-inval-nested.py.

Replays the ARM64EC overlay chain of tools/build-xtajit64.sh on the pinned FEX,
checks both overlays are idempotent and refuse a changed anchor, and compiles
their C++ with stand-ins: the MADEIRA_FULL_SMC_EXE list matching, and the
nested-aware CodeInvalidationMutex acquire (a nested acquire by the owner runs
under the outer hold; only the acquire that locked unlocks; switched off, the
mutex is locked exactly as before).
"""
from pathlib import Path
import importlib.util
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fexpatch_eval as ev  # noqa: E402


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


smc = load('full_smc_exe', root / 'tools/patch-fex-ios-full-smc-exe.py')
nested = load('inval_nested', root / 'tools/patch-fex-ios-inval-nested.py')
CXX = os.environ.get('CXX', 'c++')

with tempfile.TemporaryDirectory() as tmp:
    fex, applied = ev.chain_tree(root, tmp)
    assert applied[-2:] == ['patch-fex-ios-full-smc-exe.py', 'patch-fex-ios-inval-nested.py'], applied
    module = (fex / smc.MODULE).read_text()
    assert module.count(smc.MARKER) == 1 and smc.patch(module) == module
    assert module.index('launcher-smc-v1 madeira-bcd') < module.index(smc.MARKER) < module.index(smc.ANCHOR)
    for broken in (module.replace(smc.ADD, smc.ADD.replace('FullSmcEnable = true;', 'FullSmcEnable = false;')),):
        try:
            smc.patch(broken)
        except ValueError:
            pass
        else:
            raise AssertionError('a changed full-smc-exe block was accepted')
    sources = {rel: (fex / rel).read_text() for rel in nested.EDITS}
    assert nested.patch(sources) == sources
    for rel, edits in nested.EDITS.items():
        for _, new in edits:
            assert sources[rel].count(new) == 1, rel
    pristine = {rel: (root / 'FEX' / rel).read_text() for rel in nested.EDITS}
    drift = dict(pristine)
    drift[nested.TRACKER] = drift[nested.TRACKER].replace('std::scoped_lock CodeLock(', 'std::unique_lock CodeLock(')
    try:
        nested.patch(drift)
    except ValueError:
        pass
    else:
        raise AssertionError('a changed InvalidateIntervalInternal was accepted')
    tracker = sources[nested.TRACKER]
    assert tracker.count('IosCodeInvalidationLock Lock(CTX.GetCodeInvalidationMutex())') == 1
    assert tracker.count('IosCodeInvalidationLock CodeLock(CTX.GetCodeInvalidationMutex())') == 1
print(f'full-smc-exe, inval-nested: applied last of {len(applied)} build overlays, idempotent, drift refused')

# The list matching, compiled from the overlay's own text.
start = smc.ADD.index('    bool FullSmcEnable = false;')
end = smc.ADD.index('    if (FullSmcEnable) {')
body = smc.ADD[start:end]
harness = '''#include <cstdio>
#include <cstring>
#include <strings.h>
#include <string>
#define _strnicmp strncasecmp
static bool Match(const char* List, const char* Explicit, const char* Name) {
  const std::string FullSmcName {Name};
  const char* FullSmcList = List;
  const char* FullSmcExplicit = Explicit;
''' + body + '''  return FullSmcEnable;
}
int main() {
  struct { const char* List; const char* Explicit; const char* Name; bool Want; } Cases[] = {
    {"Stardew Valley.exe", nullptr, "Stardew Valley.exe", true},
    {"stardew valley.EXE", nullptr, "Stardew Valley.exe", true},
    {" Foo.exe ; Stardew Valley.exe ;", nullptr, "Stardew Valley.exe", true},
    {"Stardew Valley.exe", nullptr, "dockhost.exe", false},
    {"Stardew Valley.exe", nullptr, "Stardew.exe", false},
    {"Stardew", nullptr, "Stardew Valley.exe", false},
    {"Stardew Valley.exe", "full", "Stardew Valley.exe", false},
    {"Stardew Valley.exe", "", "Stardew Valley.exe", true},
    {"", nullptr, "Stardew Valley.exe", false},
    {";;", nullptr, "a.exe", false},
    {nullptr, nullptr, "a.exe", false},
  };
  int Bad = 0;
  for (const auto& C : Cases) {
    if (Match(C.List, C.Explicit, C.Name) != C.Want) {
      std::printf("FAIL list=%s name=%s\\n", C.List ? C.List : "(null)", C.Name);
      Bad++;
    }
  }
  return Bad;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src, exe = Path(tmp) / 'match.cpp', Path(tmp) / 'match'
    src.write_text(harness)
    subprocess.run([CXX, '-std=c++20', '-O1', '-Wall', '-Werror', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
print('full-smc-exe: names match whole, in any case, in a ;-list; an explicit FEX_SMCCHECKS wins')

# The nested-aware lock, compiled from the overlay's own helper with a stand-in mutex.
helper = nested.HELPER.split('\n', 1)[1]
lock_harness = '''#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>
static int Logs;
namespace LogMan::Msg {
template<typename... Args>
void EFmt(const char*, Args&&...) {
  Logs++;
}
} // namespace LogMan::Msg
namespace FEXCore::Utils::WritePriorityMutex {
class Mutex {
public:
  void lock() {
    M.lock();
    Owner = std::this_thread::get_id();
    Held = true;
    Locks++;
  }
  void unlock() {
    Held = false;
    Owner = {};
    Unlocks++;
    M.unlock();
  }
  // As the real one: the write owner gets a grant without locking.
  bool ios_lock_write_nested_aware() {
    if (Held && Owner == std::this_thread::get_id()) {
      Nested++;
      return false;
    }
    lock();
    return true;
  }
  std::mutex M;
  std::thread::id Owner;
  bool Held {};
  int Locks {}, Unlocks {}, Nested {};
};
} // namespace FEXCore::Utils::WritePriorityMutex
''' + helper + '''
int main(int argc, char** argv) {
  FEXCore::Utils::WritePriorityMutex::Mutex M;
  const bool Nest = argc > 1 && std::strcmp(argv[1], "nest") == 0;
  {
    IosCodeInvalidationLock Outer(M);
    if (Nest) {
      IosCodeInvalidationLock Inner(M);
      IosCodeInvalidationLock Deeper(M);
    }
  }
  {
    // Another thread still gets the mutex afterwards: nothing leaked.
    std::thread T([&] { IosCodeInvalidationLock Other(M); });
    T.join();
  }
  std::printf("%d %d %d %d %d\\n", M.Locks, M.Unlocks, M.Nested, Logs, M.Held ? 1 : 0);
  return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src, exe = Path(tmp) / 'lock.cpp', Path(tmp) / 'lock'
    src.write_text(lock_harness)
    subprocess.run([CXX, '-std=c++20', '-O1', '-Wall', '-Werror', '-pthread', str(src), '-o', str(exe)], check=True)
    env = {k: v for k, v in os.environ.items() if k != 'MADEIRA_FEX_INVAL_NESTED'}

    def run(value, *args):
        e = dict(env)
        if value is not None:
            e['MADEIRA_FEX_INVAL_NESTED'] = value
        return subprocess.run([str(exe), *args], env=e, capture_output=True, text=True, check=True,
                              timeout=20).stdout.split()

    # On: two nested grants under one outer hold, one lock and one unlock each for the
    # outer hold and the other thread, the grants reported once after the outer unlock.
    assert run('1', 'nest') == ['2', '2', '2', '1', '0'], run('1', 'nest')
    assert run('1') == ['2', '2', '0', '0', '0'], run('1')
    # Off (unset, 0, anything but exactly 1): plain lock and unlock, no grants, no log.
    for value in (None, '0', '', '11', 'yes'):
        assert run(value) == ['2', '2', '0', '0', '0'], (value, run(value))
print('inval-nested: the owner\'s nested acquires run under its hold and leave the lock free; '
      'MADEIRA_FEX_INVAL_NESTED unset or not 1 locks as before')

# Build wiring: last in the chain, before the patched build; every edited file restored;
# the workflow refuses an IPA whose module lacks either overlay.
build = (root / 'tools/build-xtajit64.sh').read_text()
lines = [f'python3 "$R/tools/{name}" "$R/FEX"\n' for name in ('patch-fex-ios-full-smc-exe.py', 'patch-fex-ios-inval-nested.py')]
for line in lines:
    assert build.count(line) == 1, line
assert build.index('patch-fex-ios-ec-ret-direct.py" "$R/FEX"') < build.index(lines[0]) < build.index(lines[1]) \
    < build.index('\nbuild\n', build.index(lines[1]))
restore = [line for line in build.splitlines() if line.startswith('git -C FEX checkout --')]
assert len(restore) == 1 and all(f' {rel}' in restore[0] for rel in [smc.MODULE, *nested.EDITS]), 'every patched file must be restored'
workflow = (root / '.github/workflows/build-ipa.yml').read_text()
assert "b'full-smc-exe-v1 madeira-bcd' not in module" in workflow
assert "b'[inval-nested] madeira-bcd' not in module" in workflow and "b'[smc-changed] madeira-bcd' not in module" in workflow
assert 'python3 tests/host/check-fex-full-smc-exe.py' in workflow
print('full-smc-exe, inval-nested: wired into the ARM64EC build and the IPA module check')
