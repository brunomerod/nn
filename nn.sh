#!/bin/bash

# NN => New Note
# This simple script automates the process to create new notes.
# For the most part, used as a journal entry.
#
# Use => just type nn anywhere in terminal, it will create a
# file at desired location, inputs a date header and open this
# new created note in your preferred application.
#
# *****************************************************************************
#
# First, it loads the config file. If a key is not provided, the
# default below is used.
#
# Defaults
#   text-editor      = vim     program used to open the note. When this is
#                              table-notes, the date header is inserted into
#                              cell B1 with `table-notes -i ...` instead of being
#                              written as plain text.
#   special-argument = empty   extra argument(s) passed to the editor when
#                              opening, e.g. --at B1 for table-notes
#   note-location    = ./      where new notes are created
#   file-extension   = empty   e.g. .ods for table-notes
#   date-header      = true    write a date header into the new note
#
# The note filename has the format:
#   nn_<year>_<month>_<day>_<second-of-day>      e.g. nn_2026_12_31_2523
# The date header has the format:
#   June 16, 2026 :: 18:37

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
TEXT_EDITOR="vim"
SPECIAL_ARGUMENT=""
NOTE_LOCATION="./"
FILE_EXTENSION=""
DATE_HEADER="true"

# -----------------------------------------------------------------------------
# Load config. Later files override earlier ones.
# Format is "key = value"; blank lines and lines starting with # are ignored.
# Parsed manually (not sourced) so the config can't run arbitrary code.
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_config() {
    local file="$1"
    [ -f "$file" ] || return 0

    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
        # strip comments and require a key=value line
        line="${line%%#*}"
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        # trim leading/trailing whitespace
        key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$key" ] && continue

        case "$key" in
            text-editor)      TEXT_EDITOR="$value" ;;
            special-argument) SPECIAL_ARGUMENT="$value" ;;
            note-location)    NOTE_LOCATION="$value" ;;
            file-extension)   FILE_EXTENSION="$value" ;;
            date-header)      DATE_HEADER="$value" ;;
        esac
    done < "$file"
}

# Looked up in order, later files override earlier ones (lowest priority first):
#   /etc/nn/config                  system-wide
#   $XDG_CONFIG_HOME/nn/config      per-user (falls back to ~/.config/nn/config)
#   <repo>/config                   alongside this script
load_config "/etc/nn/config"
load_config "${XDG_CONFIG_HOME:-$HOME/.config}/nn/config"
load_config "$SCRIPT_DIR/config"

# -----------------------------------------------------------------------------
# Build the filename: nn_<year>_<month>_<day>_<second-of-day>
# -----------------------------------------------------------------------------
H="$(date +%H)"
M="$(date +%M)"
S="$(date +%S)"
# 10# forces base-10 so values like "08" aren't parsed as octal
SECOND_OF_DAY=$((10#$H * 3600 + 10#$M * 60 + 10#$S))

BASENAME="nn_$(date +%Y_%m_%d)_${SECOND_OF_DAY}"
NOTE_DIR="${NOTE_LOCATION%/}"
[ -z "$NOTE_DIR" ] && NOTE_DIR="."
mkdir -p "$NOTE_DIR"
FILENAME="${NOTE_DIR}/${BASENAME}${FILE_EXTENSION}"

# Date header, e.g. "June 16, 2026 :: 18:37"
HEADER="$(date '+%B %-d, %Y :: %H:%M')"

# -----------------------------------------------------------------------------
# Create the note (with header) and open it.
#
# table-notes branch: the note is a table, so the header can't be written as
# plain text. We run `table-notes -i B1 "<header>" <file>` to insert the header
# into cell B1 (which also creates the file), then open the note.
#
# Default branch (vim, etc.): write the header as plain text, then open.
#
# $SPECIAL_ARGUMENT is left unquoted so multiple args (e.g. --at B1) word-split.
# -----------------------------------------------------------------------------
if [ "$(basename "$TEXT_EDITOR")" = "table-notes" ]; then
    if [ "$DATE_HEADER" = "true" ]; then
        "$TEXT_EDITOR" -i B1 "$HEADER" "$FILENAME"
    fi
    exec "$TEXT_EDITOR" $SPECIAL_ARGUMENT "$FILENAME"
else
    if [ "$DATE_HEADER" = "true" ]; then
        printf '%s\n\n' "$HEADER" > "$FILENAME"
    else
        touch "$FILENAME"
    fi
    exec "$TEXT_EDITOR" $SPECIAL_ARGUMENT "$FILENAME"
fi
