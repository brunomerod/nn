#!/usr/bin/env bash
#
# Test suite for nn.sh
#
# Pure bash, no external test framework required. Each test runs nn.sh inside a
# throwaway sandbox with a controlled PATH so we can decide exactly which
# editors are "installed" (vim / table-notes) and which config files exist.
#
# Run:   ./tests/run_tests.sh        (or: bash tests/run_tests.sh)
# Exit code is non-zero if any test fails.

# Resolve repo root and the script under test.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
NN_SRC="$REPO_DIR/nn.sh"

if [ ! -f "$NN_SRC" ]; then
    echo "cannot find nn.sh at $NN_SRC" >&2
    exit 1
fi

# Real coreutils nn.sh depends on. We snapshot their absolute paths now (while
# the real PATH is intact) and symlink them into each sandbox's bin, so the
# sandbox PATH can be locked down to ONLY what we choose to expose.
REQUIRED_BINS=(dirname date sed mkdir basename touch cat)
declare -A REAL_BIN
for b in "${REQUIRED_BINS[@]}"; do
    p="$(command -v "$b")" || { echo "missing required tool: $b" >&2; exit 1; }
    REAL_BIN[$b]="$p"
done

# Absolute path to bash: under `env -i` with a locked-down PATH, a bare `bash`
# would not be resolvable, so we invoke it directly.
BASH_BIN="$(command -v bash)" || { echo "missing bash" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Tiny assertion helpers
# -----------------------------------------------------------------------------
PASS=0
FAIL=0
CURRENT=""

start() { CURRENT="$1"; printf '\n• %s\n' "$1"; }

ok()   { printf '    \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() { # actual expected msg
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi
}
assert_contains() { # haystack needle msg
    case "$1" in
        *"$2"*) ok "$3" ;;
        *) bad "$3 (did not find '$2')" ;;
    esac
}
assert_not_contains() { # haystack needle msg
    case "$1" in
        *"$2"*) bad "$3 (unexpectedly found '$2')" ;;
        *) ok "$3" ;;
    esac
}
assert_match() { # value regex msg
    if [[ "$1" =~ $2 ]]; then ok "$3"; else bad "$3 ('$1' !~ /$2/)"; fi
}

# -----------------------------------------------------------------------------
# Sandbox plumbing
# -----------------------------------------------------------------------------
SANDBOXES=()
cleanup() { for s in "${SANDBOXES[@]}"; do rm -rf "$s"; done; }
trap cleanup EXIT

new_sandbox() {
    SBX="$(mktemp -d "${TMPDIR:-/tmp}/nn-test.XXXXXX")"
    SANDBOXES+=("$SBX")
    mkdir -p "$SBX/bin" "$SBX/home" "$SBX/xdg" "$SBX/run"
    cp "$NN_SRC" "$SBX/nn.sh"
    chmod +x "$SBX/nn.sh"
    for b in "${REQUIRED_BINS[@]}"; do
        ln -s "${REAL_BIN[$b]}" "$SBX/bin/$b"
    done
    # The editor stubs are themselves bash scripts, so bash must be resolvable
    # on the sandbox PATH for them to run.
    ln -s "$BASH_BIN" "$SBX/bin/bash"
}

add_vim_stub() {
    cat > "$SBX/bin/vim" <<'EOF'
#!/usr/bin/env bash
printf 'vim %s\n' "$*" >> "$NN_STUB_LOG"
exit 0
EOF
    chmod +x "$SBX/bin/vim"
}

add_tablenotes_stub() {
    cat > "$SBX/bin/table-notes" <<'EOF'
#!/usr/bin/env bash
printf 'table-notes %s\n' "$*" >> "$NN_STUB_LOG"
# Simulate `table-notes -i <cell> "<header>" <file>` by writing the header into
# the target file (the real tool creates the .ods and fills cell B1).
if [ "$1" = "-i" ]; then
    printf '%s\n' "$3" > "$4"
fi
exit 0
EOF
    chmod +x "$SBX/bin/table-notes"
}

write_xdg_config()  { mkdir -p "$SBX/xdg/nn"; printf '%s\n' "$1" > "$SBX/xdg/nn/config"; }
write_repo_config() { printf '%s\n' "$1" > "$SBX/config"; }

# Runs nn.sh in the sandbox with a locked-down environment.
# Populates: NN_EXIT, NN_OUT, NN_ERR, NN_STUB
run_nn() {
    : > "$SBX/stub.log"
    (
        cd "$SBX/run" || exit 99
        env -i \
            PATH="$SBX/bin" \
            HOME="$SBX/home" \
            XDG_CONFIG_HOME="$SBX/xdg" \
            NN_STUB_LOG="$SBX/stub.log" \
            "$BASH_BIN" "$SBX/nn.sh"
    ) > "$SBX/stdout.log" 2> "$SBX/stderr.log"
    NN_EXIT=$?
    NN_OUT="$(cat "$SBX/stdout.log")"
    NN_ERR="$(cat "$SBX/stderr.log")"
    NN_STUB="$(cat "$SBX/stub.log")"
}

# First nn_* file in a directory (empty string if none).
find_note() { find "$1" -maxdepth 1 -name 'nn_*' 2>/dev/null | head -n1; }

FILENAME_RE='^nn_[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]+'
HEADER_RE='^[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4} :: [0-9]{2}:[0-9]{2}$'

# =============================================================================
# Tests
# =============================================================================

test_filename_and_header() {
    start "default vim: filename format + date header"
    new_sandbox
    add_vim_stub
    write_repo_config "text-editor = vim
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    local note; note="$(find_note "$SBX/notes")"
    if [ -z "$note" ]; then bad "note file was created"; return; fi
    ok "note file was created"
    assert_match "$(basename "$note")" "$FILENAME_RE" "filename matches nn_<y>_<m>_<d>_<sod>"
    assert_match "$(head -n1 "$note")" "$HEADER_RE" "first line is a date header"
    assert_contains "$NN_STUB" "vim " "vim was invoked"
}

test_no_header() {
    start "date-header = false: file is empty"
    new_sandbox
    add_vim_stub
    write_repo_config "text-editor = vim
date-header = false
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    local note; note="$(find_note "$SBX/notes")"
    if [ -z "$note" ]; then bad "note file was created"; return; fi
    ok "note file was created"
    assert_eq "$(wc -c < "$note" | tr -d ' ')" "0" "note file is empty (no header)"
}

test_file_extension() {
    start "file-extension is appended to the filename"
    new_sandbox
    add_vim_stub
    write_repo_config "text-editor = vim
file-extension = .txt
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    local note; note="$(find_note "$SBX/notes")"
    assert_match "$note" '\.txt$' "filename ends with .txt"
}

test_note_location() {
    start "note-location: notes land in the configured dir"
    new_sandbox
    add_vim_stub
    write_repo_config "text-editor = vim
note-location = $SBX/custom-place"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    local note; note="$(find_note "$SBX/custom-place")"
    assert_match "$(basename "${note:-NONE}")" "$FILENAME_RE" "note created under custom-place"
}

test_config_override() {
    start "repo config overrides XDG config (precedence order)"
    new_sandbox
    add_vim_stub
    write_xdg_config  "note-location = $SBX/xdg-notes"
    write_repo_config "note-location = $SBX/repo-notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    assert_match "$(basename "$(find_note "$SBX/repo-notes")")" "$FILENAME_RE" "note created in repo-notes (winner)"
    assert_eq "$(find_note "$SBX/xdg-notes")" "" "nothing created in xdg-notes (overridden)"
    assert_contains "$NN_ERR" "multiple config files" "warns about duplicate configs"
}

test_config_parsing() {
    start "config parsing: comments + surrounding whitespace are trimmed"
    new_sandbox
    add_vim_stub
    write_repo_config "# a comment line
   text-editor   =   vim    # trailing comment

   note-location =   $SBX/notes   "
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    assert_contains "$NN_STUB" "vim " "trimmed text-editor resolved to vim"
    assert_match "$(basename "$(find_note "$SBX/notes")")" "$FILENAME_RE" "trimmed note-location honored"
}

test_tablenotes_fallback() {
    start "table-notes configured but NOT installed: falls back to vim"
    new_sandbox
    add_vim_stub            # vim available, table-notes is not
    write_repo_config "text-editor = table-notes
special-argument = --at B1
file-extension = .ods
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    assert_contains "$NN_ERR" "falling back to vim" "announces the fallback"
    assert_contains "$NN_STUB" "vim " "vim was invoked"
    local note; note="$(find_note "$SBX/notes")"
    assert_not_contains "${note:-x}" ".ods" "table-notes file-extension was dropped"
    assert_not_contains "$NN_STUB" "--at B1" "table-notes special-argument was dropped"
}

test_tablenotes_installed() {
    start "table-notes installed: header goes through table-notes -i"
    new_sandbox
    add_vim_stub
    add_tablenotes_stub
    write_repo_config "text-editor = table-notes
special-argument = --at B1
file-extension = .ods
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    assert_contains "$NN_STUB" "table-notes -i B1" "header inserted via table-notes -i B1"
    assert_contains "$NN_STUB" "table-notes --at B1" "note opened with special-argument"
    local note; note="$(find_note "$SBX/notes")"
    assert_match "$(basename "${note:-NONE}")" '\.ods$' "filename keeps the .ods extension"
    assert_match "$(head -n1 "$note")" "$HEADER_RE" "header was written into the file"
}

test_tablenotes_no_header() {
    start "table-notes + date-header = false: no -i insertion"
    new_sandbox
    add_vim_stub
    add_tablenotes_stub
    write_repo_config "text-editor = table-notes
special-argument = --at B1
file-extension = .ods
date-header = false
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "0" "exits 0"
    assert_not_contains "$NN_STUB" "table-notes -i" "no header insertion call"
    assert_contains "$NN_STUB" "table-notes --at B1" "note still opened"
}

test_no_editor_aborts() {
    start "no usable editor installed: does nothing, exits non-zero"
    new_sandbox
    # No vim, no table-notes stubs in PATH.
    write_repo_config "text-editor = ghost-editor
note-location = $SBX/notes"
    run_nn

    assert_eq "$NN_EXIT" "1" "exits 1"
    assert_contains "$NN_ERR" "doing nothing" "explains it is doing nothing"
    assert_eq "$(find_note "$SBX/notes")" "" "no note file was created"
}

# =============================================================================
# Run everything
# =============================================================================
test_filename_and_header
test_no_header
test_file_extension
test_note_location
test_config_override
test_config_parsing
test_tablenotes_fallback
test_tablenotes_installed
test_tablenotes_no_header
test_no_editor_aborts

printf '\n----------------------------------------\n'
printf 'Total: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
