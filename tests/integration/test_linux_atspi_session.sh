#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
fixture="$tmp_dir/atspi_fixture"
log="$tmp_dir/fixture.log"
fixture_pid=""
memory_model="${CBSS_MEMORY_MODEL:-arc}"
use_valgrind="${CBSS_ATSPI_VALGRIND:-0}"
atspi_null_path="/org/a11y/atspi/null"

case "$memory_model" in
  arc|orc) ;;
  *)
    printf 'Unsupported CBSS_MEMORY_MODEL: %s\n' "$memory_model" >&2
    exit 2
    ;;
esac

cleanup() {
  if [[ -n "$fixture_pid" ]] && kill -0 "$fixture_pid" 2>/dev/null; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

report_failure() {
  status="$?"
  if [[ -f "$log" ]]; then
    printf '%s\n' "--- AT-SPI fixture log ---" >&2
    cat "$log" >&2
  fi
  exit "$status"
}
trap report_failure ERR

nim c --mm:"$memory_model" -d:cbssLinuxAtspi --path:"$repo_root/src" \
  --nimcache:"$tmp_dir/nimcache" --out:"$fixture" \
  "$repo_root/tests/integration/atspi_linux_fixture.nim"

address_reply="$(gdbus call --session --dest org.a11y.Bus \
  --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress)"
address="$(printf '%s' "$address_reply" | sed -n "s/^('\(.*\)',)$/\1/p")"
test -n "$address"

fixture_command=("$fixture")
if [[ "$use_valgrind" == "1" ]]; then
  fixture_command=(
    valgrind
    --quiet
    --leak-check=full
    --show-leak-kinds=definite
    --errors-for-leak-kinds=definite
    --error-exitcode=97
    --suppressions="$repo_root/tests/sanitizers/valgrind-dlopen.supp"
    "$fixture"
  )
fi

"${fixture_command[@]}" >"$log" 2>&1 &
fixture_pid="$!"

for _ in $(seq 1 100); do
  if grep -q '^READY ' "$log"; then
    break
  fi
  if ! kill -0 "$fixture_pid" 2>/dev/null; then
    cat "$log"
    exit 1
  fi
  sleep 0.05
done

grep -q '^READY ' "$log"
bus_name="$(awk '/^READY / { print $2; exit }' "$log")"
root_path="$(awk '/^ROOT / { print $2; exit }' "$log")"
button_path="$(awk '/^BUTTON / { print $2; exit }' "$log")"
checkbox_path="$(awk '/^CHECKBOX / { print $2; exit }' "$log")"
slider_path="$(awk '/^SLIDER / { print $2; exit }' "$log")"

toolkit_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$root_path" --method org.freedesktop.DBus.Properties.Get \
  org.a11y.atspi.Application ToolkitName)"
[[ "$toolkit_result" == *"CBSS"* ]]

name_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.freedesktop.DBus.Properties.Get \
  org.a11y.atspi.Accessible Name)"
[[ "$name_result" == *"Save"* ]]

role_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Accessible.GetRole)"
[[ "$role_result" == *"uint32 43"* ]]

checkbox_role="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$checkbox_path" --method org.a11y.atspi.Accessible.GetRole)"
[[ "$checkbox_role" == *"uint32 7"* ]]

slider_role="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$slider_path" --method org.a11y.atspi.Accessible.GetRole)"
[[ "$slider_role" == *"uint32 51"* ]]

state_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Accessible.GetState)"
[[ "$state_result" == *"uint32 8"* ]]
[[ "$state_result" == *"[uint32 8, 11,"* ]]

interfaces_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Accessible.GetInterfaces)"
[[ "$interfaces_result" == *"org.a11y.atspi.Action"* ]]
[[ "$interfaces_result" == *"org.a11y.atspi.Component"* ]]

children_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$root_path" --method org.a11y.atspi.Accessible.GetChildren)"
[[ "$children_result" == *"$button_path"* ]]

contains_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Component.Contains \
  1 1 0)"
[[ "$contains_result" == *"true"* ]]

inside_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" \
  --method org.a11y.atspi.Component.GetAccessibleAtPoint 1 1 0)"
[[ "$inside_result" == *"$button_path"* ]]

outside_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" \
  --method org.a11y.atspi.Component.GetAccessibleAtPoint 1 40 0)"
[[ "$outside_result" == *"$atspi_null_path"* ]]

invalid_action_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Action.DoAction 99)"
[[ "$invalid_action_result" == *"false"* ]]

action_result="$(gdbus call --address "$address" --dest "$bus_name" \
  --object-path "$button_path" --method org.a11y.atspi.Action.DoAction 0)"
[[ "$action_result" == *"true"* ]]

wait "$fixture_pid"
fixture_pid=""
grep -q '^ACTIVATIONS 1$' "$log"
grep -q '^CLOSED true$' "$log"

printf 'Linux AT-SPI D-Bus session integration passed under %s.\n' \
  "$memory_model"
