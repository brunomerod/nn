# nn — New Note

A tiny shell script that creates a timestamped note, drops a date header in it,
and opens it in your editor. Handy for quick journal entries.

## Usage

```sh
nn
```

That's it. It creates a file like `nn_2026_12_31_2523` — `nn_<year>_<month>_<day>_<second-of-day>`
— writes a header such as `December 31, 2026 :: 18:37`, and opens it.

To run it as `nn` from anywhere, put it on your `PATH`:

```sh
ln -s "$PWD/nn.sh" ~/.local/bin/nn   # or: alias nn="/path/to/nn.sh"
chmod +x nn.sh
```

## Configuration

Config is read from these paths, later overriding earlier:

1. `/etc/nn/config`
2. `${XDG_CONFIG_HOME:-$HOME/.config}/nn/config`
3. `<repo>/config`

Format is `key = value`; blank lines and `#` comments are ignored. Copy the
template to get started:

```sh
mkdir -p ~/.config/nn && cp config.example ~/.config/nn/config
```

| Key | Default | Description |
| --- | --- | --- |
| `text-editor` | `vim` | Program used to open the note. When set to `table-notes`, the header is inserted into cell **B1** with `table-notes -i` instead of written as plain text. |
| `special-argument` | *(empty)* | Extra argument(s) passed to the editor when opening, e.g. `--at B1` for table-notes. |
| `note-location` | `./` | Where new notes are created. |
| `file-extension` | *(empty)* | Extension for new notes, e.g. `.ods` for table-notes. |
| `date-header` | `true` | Whether to write the date header. |

## Using with table-notes

[table-notes](../table-notes) is a table editor. Since a note is then a table,
the header can't be plain text — the script inserts it into cell B1 and opens
the file there:

```ini
text-editor = table-notes
special-argument = --at B1
file-extension = .ods
```
