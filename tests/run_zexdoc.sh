#!/usr/bin/env bash
# Build the console tests and run zexdoc on the Z80 emulator in SpecEmu.pas.
#
#   tests/run_zexdoc.sh path/to/zexdoc.com [ONLY=n,m env var to pick tests]
#
# zexdoc.com (Frank D. Cringle's Z80 instruction exerciser, GPL) is not part
# of the repo; it is in e.g. https://github.com/anotherlin/z80emu/tree/master/testfiles
set -euo pipefail

cd "$(dirname "$0")"
FPC=${FPC:-$HOME/opt/fpc/bin/fpc}
mkdir -p lib
for prog in cpm render; do
  "$FPC" -Mdelphi -O3 -Fustubs -Fu.. -FUlib -o"lib/$prog" "$prog.pas" > lib/$prog.log 2>&1 ||
    { cat lib/$prog.log; exit 1; }
done
lib/cpm "$1" | tr '\r' '\n' | grep -v '^$'
