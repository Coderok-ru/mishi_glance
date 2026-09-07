#!/bin/bash
# Собирает и прогоняет оба набора проверок на исходниках приложения.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PY="${MG_PYTHON:-$ROOT/scripts/.venv/bin/python}"
if [[ ! -x "$PY" ]]; then
    python3 -m venv "$ROOT/scripts/.venv"
    "$ROOT/scripts/.venv/bin/pip" install --quiet --upgrade pip
    "$ROOT/scripts/.venv/bin/pip" install --quiet pillow
    PY="$ROOT/scripts/.venv/bin/python"
fi

echo "==> Готовлю изображения"
"$PY" "$ROOT/tests/make-fixtures.py" "$WORK" >/dev/null

cd "$ROOT/Mishi Glance"
# main.swift приложения исключаем: у харнессов свой вход.
SOURCES=$(find . -name "*.swift" ! -name "main.swift" | sort)

echo "==> Компилирую"
# Top-level код Swift допустим только в файле с именем main.swift,
# поэтому каждый харнесс компилируется под этим именем.
for pair in "model_tests.swift:model" "integration_tests.swift:integration"; do
    src="${pair%%:*}"; bin="${pair##*:}"
    mkdir -p "$WORK/$bin.build"
    cp "$ROOT/tests/$src" "$WORK/$bin.build/main.swift"
    xcrun swiftc -O -target arm64-apple-macosx15.0 ${SOURCES} \
        "$WORK/$bin.build/main.swift" -o "$WORK/$bin"
done

echo
"$WORK/model" "$WORK/basic"
echo
"$WORK/integration" "$WORK/basic" "$WORK/sort"
