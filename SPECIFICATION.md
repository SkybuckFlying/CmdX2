# CmdX2 Technical Specification & Architecture Document

Version: 2.0
Target Compilers: Delphi 13 (RAD Studio) & Free Pascal Compiler 3.2+ (Delphi Mode `-Mdelphi`)

---

## 1. Executive Summary & Purpose

CmdX2 is a `cmd.exe`-compatible shell designed to eliminate the legacy Windows `PATH` length limitation (4095 characters in the registry, 8191 characters in legacy `cmd.exe` environment expansion). CmdX2 stores `PATH` in its own configuration files, holds `PATH` in memory as an unrestricted Unicode string (supporting 500 KB+ / 10,000+ entries), performs custom command resolution without calling `SearchPathW`, constructs custom process environment blocks for `CreateProcessW`, and empirically probes the host system's `CreateProcessW` environment block ceiling.

---

## 2. Compiler & Portability Requirements

1. **Delphi & Free Pascal Compatibility**:
   - Source code must compile cleanly on Delphi 13 and Free Pascal Compiler (FPC 3.2.2+).
   - Delphi mode directive `{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}` is included in all units.
   - Platform conditional compilation (`{$IFDEF WINDOWS}` vs `{$IFDEF LINUX}`) ensures core shell functionality, parsing, resolution, and batch evaluation run seamlessly across Windows and Linux / POSIX systems.
2. **Unicode Core**:
   - Uses native `UnicodeString` / `string` (UTF-16 on Windows).
   - Win32 API calls explicitly target `-W` unicode endpoints (`CreateProcessW`, `GetEnvironmentStringsW`, etc.).
3. **No Direct Dependency on Obsolete Win32 Limits**:
   - Does not call `SearchPathW`.
   - Does not depend on Registry `PATH` or system environment limits for internal resolution.

---

## 3. Modular Architecture & Unit Decomposition

The implementation is structured into clean, modular Pascal units:

1. **`CmdX2Types.pas`**
   - Core data types (`TEnvironmentMap`, `TPathList`, `TSession`, `TLimits`, `TConfig`, `TCommandToken`, `TExecStrategy`).

2. **`CmdX2Config.pas`**
   - TOML configuration parser and loader.
   - Merges configurations across priority layers: Session (`--config`), Project (`./.cmdx2/config.toml`), Machine (`%PROGRAMDATA%\CmdX2\config.toml`), and Global (`%APPDATA%\CmdX2\config.toml`).
   - Supports registry import (`cmdx2 import`).

3. **`CmdX2Path.pas`**
   - In-memory PATH storage and manipulation.
   - Deduplication, normalization, raw semicolon string generation, entry enumeration with source tracing.

4. **`CmdX2Resolver.pas`**
   - Custom command resolution algorithm using `PATH` and `PATHEXT`.
   - Handles absolute paths, relative shell prefixes (`./`, `.\`), built-ins, and extension matching.
   - Session-level resolution cache.

5. **`CmdX2Env.pas`**
   - Environment map management.
   - UTF-16LE null-terminated environment block builder for process creation.
   - Case-insensitive key comparison and stable key ordering.

6. **`CmdX2Probe.pas`**
   - Empirical `CreateProcessW` environment block ceiling measurement probe.
   - Exponential growth + binary search algorithm.
   - Fallback ceiling (65,534 bytes) when probe cannot run.

7. **`CmdX2Parser.pas`**
   - Command line lexer, tokeniser, variable expansion engine (`%VAR%`, `!VAR!`, caret escape handling).
   - Pipeline (`|`), redirection (`<`, `>`, `>>`, `2>`), and operator parsing (`&&`, `||`, `&`).

8. **`CmdX2Exec.pas`**
   - Process launcher and pipeline orchestrator.
   - Handles Strategy A (Warn & Proceed), Strategy B (Session-used PATH trimming), Strategy C (Shim directory), and Strategy D (Refuse & Explain).

9. **`CmdX2Builtins.pas`**
   - Standard `cmd.exe` built-ins (`dir`, `cd`, `set`, `echo`, `copy`, `del`, `cls`, `pushd`, `popd`, `if`, `for`, `exit`, etc.).
   - CmdX2 specific introspective commands (`cmdx2 limits`, `cmdx2 path`, `cmdx2 which`, `cmdx2 diagnose`, `cmdx2 env-dump`, `cmdx2 probe`, `cmdx2 import`, `cmdx2 reload`).

10. **`CmdX2Batch.pas`**
    - Batch file processor (`.bat`, `.cmd`).
    - Label scanning (`:label`), `goto`, `call`, `setlocal`/`endlocal` stack.

11. **`CmdX2Diagnostics.pas`**
    - Environment block introspection, headroom reporting, log file writer.

---

## 4. Built-In Diagnostic Commands

- `cmdx2 limits`: Displays measured ceiling, current PATH byte size, remaining headroom, and status (OK / WARNING / EXCEEDED).
- `cmdx2 path`: Displays indexed PATH entries with origin file source annotations (`--raw`, `--length`, `--duplicates`).
- `cmdx2 which <cmd>`: Resolves `<cmd>` and shows exact matching file path, PATH index, and matched `PATHEXT` extension.
- `cmdx2 diagnose <cmd>`: Runs command and assesses failure reasons related to environment block ceilings.
- `cmdx2 env-dump`: Dumps the UTF-16 child environment block representation.
- `cmdx2 probe`: Manually triggers empirical ceiling probe.
- `cmdx2 import`: Imports registry `PATH` variables into global config.
- `cmdx2 reload`: Re-reads configuration files and re-merges `PATH`.

---

## 5. Acceptance Criteria Verification Plan

1. Interactive REPL and Batch file execution support.
2. In-memory storage and resolution independent of registry `PATH`.
3. Custom resolver without `SearchPathW`.
4. Full UTF-16 environment block passed to subprocesses.
5. Empirical ceiling probe measuring `CreateProcessW` limits.
6. Support for 500 KB+ / 10,000+ PATH entries without silent truncation.
7. Verification across both native FPC builds and cross-compiled Windows binaries (`-Twin64 -Mdelphi`).
