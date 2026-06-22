# Tests

Pure-bash test suite for `nn.sh` — no external framework (no `bats`) required.

```sh
./tests/run_tests.sh
# or
bash tests/run_tests.sh
```

Exit code is `0` when everything passes, non-zero otherwise.

## How it works

Each test runs `nn.sh` inside a throwaway sandbox (`mktemp -d`) under a
locked-down environment (`env -i`) so it is fully isolated and reproducible:

- `PATH` points at a sandbox `bin/` holding only the coreutils `nn.sh` needs
  plus the editor *stubs* we choose to expose. This lets a test decide exactly
  which editors are "installed" (`vim`, `table-notes`, or neither).
- The `vim` / `table-notes` stubs just record their invocation to a log instead
  of opening anything, so the `exec` at the end of `nn.sh` is observable and
  harmless.
- `HOME` and `XDG_CONFIG_HOME` point into the sandbox, and `nn.sh` is copied in
  so its `<repo>/config` lookup resolves to the sandbox too — every config path
  is controlled.

## What's covered

| Feature | Test |
| --- | --- |
| Filename format `nn_<y>_<m>_<d>_<sod>` | `default vim` |
| Date header content | `default vim`, `table-notes installed` |
| `date-header = false` | `date-header = false`, `table-notes + date-header = false` |
| `file-extension` | `file-extension`, `table-notes installed` |
| `note-location` | `note-location` |
| Config precedence (repo overrides XDG) | `repo config overrides XDG config` |
| Config parsing (comments / whitespace) | `config parsing` |
| Duplicate-config warning | `repo config overrides XDG config` |
| table-notes fallback to vim when missing | `table-notes configured but NOT installed` |
| table-notes header insertion via `-i` | `table-notes installed` |
| Abort when no editor is installed | `no usable editor installed` |
