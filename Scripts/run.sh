#!/usr/bin/env bash
# Rebuilds the app bundle and relaunches it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
pkill -x SkillsManager 2>/dev/null || true
"$ROOT/Scripts/package_app.sh" "${1:-debug}"
open "$ROOT/build/SkillsManager.app"
