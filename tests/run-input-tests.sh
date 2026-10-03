#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_root=${OMARCHY_PATH:-/usr/share/omarchy}/shell
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/InputTest"
ln -s "$shell_root/Commons" "$test_dir/Commons"
ln -s "$shell_root/Ui" "$test_dir/Ui"
printf 'module InputTest\nplugin inputtest\n' > "$test_dir/InputTest/qmldir"
/usr/lib/qt6/moc $(pkg-config --cflags Qt6Qml) "$repo/tests/input.test.cpp" -o "$test_dir/input.test.moc"
c++ -std=c++17 -fPIC -shared -I"$test_dir" "$repo/tests/input.test.cpp" \
  -o "$test_dir/InputTest/libinputtest.so" $(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6Gui)
cp "$repo/tests/input.test.qml" "$test_dir/shell.qml"
APPDECK_TEST_REPO="$repo" QML_IMPORT_PATH="$test_dir${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  timeout 30s quickshell -p "$test_dir/shell.qml" --no-color
