#!/usr/bin/env bash
# Dena.emu GB: during a merge of upstream/main, delete again every path the
# fork removed (docs/dev/gb-fork.md). Resolves modify/delete conflicts and
# drops new upstream files inside removed folders.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
removed=(
  app/lib/src/apps app/lib/src/carts app/lib/src/media app/lib/src/premium
  app/lib/src/romm app/lib/src/webfiles app/lib/src/spike
  app/lib/src/library/carts_tab.dart
  app/test/apps app/test/carts app/test/media app/test/premium app/test/romm
  app/test/webfiles app/test/spike_screen_test.dart app/test/support/media_fixture.dart
  app/integration_test/spike_test.dart app/tool/media_screenshots_test.dart
  backend docs/specs/premium.md docs/feasibility-study.pdf
  shells/android/android/src/main/kotlin/app/dena/dena_android/GoogleAuth.kt
  shells/android/android/src/main/kotlin/app/dena/dena_android/SyncWorker.kt
  shells/android/android/src/main/kotlin/app/dena/dena_android/AuthApi.g.kt
  shells/android/lib/src/auth_api.g.dart shells/android/pigeons/auth_api.dart
  app/android/app/src/main/res/xml/backup_rules.xml
  app/android/app/src/main/res/xml/data_extraction_rules.xml
  cores/beetle_psx cores/beetle_saturn cores/bsnes cores/fake08 cores/fceumm
  cores/flycast cores/mupen64plus cores/pcsx_rearmed cores/ppsspp
)
for path in "${removed[@]}"; do
  if [ -e "$path" ] || git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    git rm -r -q --cached --ignore-unmatch -- "$path"
    rm -rf -- "$path"
    echo "removed $path"
  fi
done
