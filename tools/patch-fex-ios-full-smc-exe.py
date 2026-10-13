#!/usr/bin/env python3
"""Run FEX's full code validator only in the programs a game's settings name.

FEX_SMCCHECKS=full is process-wide and the game's environment reaches every
program of the session, Steam's client included. MADEIRA_FULL_SMC_EXE names
the programs (file names, ';'-separated, any case) whose process gets the
full validator: before each guest instruction the JIT checks the bytes it was
compiled from and recompiles a changed block. Every other program keeps the
configured policy. An explicit FEX_SMCCHECKS wins, as with the Launcher switch.

Stardew Valley (2026-10-12): .NET rewrites a method's entry stub from "call
the prestub" to "jump to the compiled code"; FEX kept running its compiled
copy of the old stub and the game spun in PreStubWorker. FEX_SMCCHECKS=full
broke that loop on device.

Applied by tools/build-xtajit64.sh after the other ARM64EC overlays; the
pinned submodule is never updated.
"""
from pathlib import Path
import sys

MARKER = "madeira-bcd: full-smc-exe v1"
MODULE = "Source/Windows/ARM64EC/Module.cpp"
ANCHOR = '  FEXCore::Config::Set(FEXCore::Config::CONFIG_IS64BIT_MODE, "1");\n'
# The Launcher switch must already be in place: this block follows it.
AFTER = 'LogMan::Msg::IFmt("FEX: launcher-smc-v1 madeira-bcd enabled={} mode={} exe={}",'
ADD = '''#ifdef FEX_IOS_HOST
  /* madeira-bcd: full-smc-exe v1 (tools/patch-fex-ios-full-smc-exe.py).
   * MADEIRA_FULL_SMC_EXE names programs (';'-separated file names, any case)
   * whose process runs FEX's full code validator; every other program keeps
   * the configured policy. An explicit FEX_SMCCHECKS wins. */
  {
    const auto FullSmcName = fextl::string {ExecutableName};
    const char* FullSmcList = getenv("MADEIRA_FULL_SMC_EXE");
    const char* FullSmcExplicit = getenv("FEX_SMCCHECKS");
    bool FullSmcEnable = false;
    if (FullSmcList && !(FullSmcExplicit && FullSmcExplicit[0])) {
      const char* P = FullSmcList;
      while (*P && !FullSmcEnable) {
        while (*P == ' ' || *P == ';') {
          P++;
        }
        const char* E = P;
        while (*E && *E != ';') {
          E++;
        }
        const char* T = E;
        while (T > P && T[-1] == ' ') {
          T--;
        }
        const size_t Len = static_cast<size_t>(T - P);
        if (Len && Len == FullSmcName.size() && _strnicmp(P, FullSmcName.c_str(), Len) == 0) {
          FullSmcEnable = true;
        }
        P = E;
      }
    }
    if (FullSmcEnable) {
      FEXCore::Config::Set(FEXCore::Config::CONFIG_SMCCHECKS,
                          fextl::fmt::format("{}", static_cast<unsigned>(FEXCore::Config::CONFIG_SMC_FULL)));
    }
    FEX_CONFIG_OPT(FullSmcEffective, SMCCHECKS);
    LogMan::Msg::IFmt("FEX: full-smc-exe-v1 madeira-bcd enabled={} mode={} exe={}", FullSmcEnable,
                      static_cast<unsigned>(FullSmcEffective()), ExecutableName);
  }
#endif
'''


def patch(source):
    if MARKER in source:
        if source.count(ADD + ANCHOR) != 1:
            raise ValueError("partial or changed full-smc-exe overlay")
        return source
    if source.count(ANCHOR) != 1:
        raise ValueError("ProcessInit configuration anchor changed")
    if AFTER not in source or source.index(AFTER) > source.index(ANCHOR):
        raise ValueError("the Launcher SMC switch must be applied first")
    return source.replace(ANCHOR, ADD + ANCHOR, 1)


if __name__ == "__main__":
    fex = Path(sys.argv[1])
    path = fex / MODULE
    source = path.read_text()
    try:
        result = patch(source)
    except ValueError as error:
        sys.exit("patch-fex-ios-full-smc-exe: " + str(error))
    if result != source:
        path.write_text(result)
    print("FEX ARM64EC: full code validator only for the programs MADEIRA_FULL_SMC_EXE names")
