# Working on UpdateEverything

**Read [CONTRIBUTING.md](CONTRIBUTING.md) before writing code.** It holds the
house style, the rules a change has to satisfy, the three places this repo
departs from convention and why, and the test conventions. This file covers only
what is not in there: how to set the machine up, and the traps that have
actually cost time.

## The gate

```powershell
.\test.ps1
```

One runner, used unchanged locally and in CI. It must be green, including the
`Lint` tag, before any claim that something works. `-Tag Static`, `-Tag Docs` and
`-Tag Lint` narrow it; `-CI` adds the non-zero exit code and `testResults.xml`.

Do not report a change as working on the strength of having written it. Run it.

## Setting up a machine

**Clone outside OneDrive.** OneDrive's Files On-Demand dehydrates files it thinks
are cold, and a dehydrated module tree is invisible to
`Get-Module -ListAvailable` — which presents as "Pester 6 is not installed" on a
machine where it is. `C:\Users\<you>\source\repos` is fine.

```powershell
Install-Module Pester -MinimumVersion 6.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

**Pester 6, not 5.** This matters more than it sounds, because Pester 5 syntax is
the reflex and it fails in a confusing way. The pipeline form is gone:

```powershell
$x | Should -Be 'y'      # Pester 5. Does not work here.
$x | Should-Be 'y'       # Pester 6. Note the hyphen.
```

The assertions this suite uses, all of which exist:

`Should-Be` `Should-BeNull` `Should-BeTrue` `Should-BeFalse` `Should-MatchString`
`Should-NotMatchString` `Should-BeCollection` `Should-ContainCollection`
`Should-NotBeNull` `Should-BeGreaterThan` `Should-BeGreaterThanOrEqual`
`Should-BeLessThan` `Should-Throw` `Should-HaveType` `Should-HaveParameter`
`Should-BeString` `Should-NotBeString` `Should-NotBeEmptyString` `Should-All`
`Should-Invoke` `Should-NotInvoke`

`Should-BeOfType` and `Should-NotBeNullOrEmpty` do **not** exist in Pester 6.
Reach for `Should-HaveType` and `Should-NotBeEmptyString`.

There is no `Should-NotThrow` either — only `Should-Throw`. To assert that
something does not throw, call it and assert on what it returned; a test that
inspects the result has already proved it.

Check a name before reaching for it rather than after:

```powershell
(Get-Command -Module Pester -Name 'Should-*').Name
```

**PowerShell 7 from the MSI, not the Store.** The MSIX build cannot be elevated,
cannot use in-process COM (the DISM cmdlets fail with "Class not registered"),
and its path carries a version stamp that a scheduled task cannot rely on. The
module has code specifically about this, so testing it needs the MSI:

```powershell
winget install --id Microsoft.PowerShell --exact --source winget --installer-type wix
```

Both builds can coexist. `dism.exe` works from either, being a separate process.

## Traps that have cost time here

**PowerShell's location is not the process working directory.** `[System.IO.File]`
methods resolve relative paths against the process CWD, which is often not where
`Get-Location` says you are. Pass absolute paths to .NET methods.

**Comment-based help ends at any line starting with a dot.** A line whose first
non-space character is a dot is read as a help keyword, whatever word follows, so
a wrapped `.NET global tools` silently discards every help section after it.
`Get-Help` reports no error, it just returns empty. Write `dotnet`. A test now
catches this.

**Windows PowerShell writes UTF-16LE where 7 writes UTF-8.** `Tee-Object` has no
`-Encoding` on 5.1, and `Add-Content -Encoding utf8` means "with BOM" on 5.1 and
"without" on 7. Use `[System.IO.File]::AppendAllText` with an explicit
`UTF8Encoding($false)` — `Write-StepLog` is the pattern.

**Unassigned pipeline output inside a function is the return value.** A bare
`$table | Format-Table` in a function returns formatting objects to the caller
instead of displaying them. `Out-Host` is the fix, and the reason it appears in
`Invoke-Step` and the summary.

**Verify with tools that fail loudly.** `Edit` errors when its target string does
not match; a `.Replace()` that near-misses silently does nothing and leaves you
believing an edit landed. `git stash push -- <untracked-path>` errors on the
pathspec and stashes nothing, which has produced a "passing" verification against
unchanged code.

Do not filter command output in a way that could hide the error you are looking
for. A `-notmatch` on an expected-noise phrase has swallowed the actual failure.

## Publishing

The full procedure is in [CONTRIBUTING.md](CONTRIBUTING.md#publishing). The parts
worth knowing before touching anything release-shaped:

- The gallery has no delete, only unlist. A published version is permanent.
- `Publish.ps1 -WhatIf` runs every check and sends nothing. It is the real gate.
- PSScriptAnalyzer must be clean over `src` under its **default** rules, not this
  repo's tuned settings file. The default rules are what the gallery displays.
- `PrivateData.PSData.ReleaseNotes` is the package page. It ships permanently
  with the version, so it describes that version.

## Tracking

Work lives in [issues](https://github.com/briankronberg/UpdateEverything/issues), separated by labels rather than location. Milestones are not in use. The open 1.1.0 and 1.2.0 milestones are leftovers from early planning, not active release plans. All versions from 1.3 to 1.9 shipped without milestones. Issue #25 was the 1.1.0 roadmap and is now closed. There is no current roadmap issue.

Useful labels include `bug`, `enhancement`, `documentation`, `test`, `blocked`, and `wontfix`.

Close issues from the pull request body with `Closes #N`.

Warning: this section has gone stale before. Treat any version number or issue number written here as a claim to verify, not a fact to trust.

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues on briankronberg/UpdateEverything via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The triage vocabulary was never adopted. Of the five roles, only `wontfix` has a label of its own, and `needs-info` is covered by `question`. There is nothing for `needs-triage`, `ready-for-agent` or `ready-for-human`, so a skill reaching for one should stop and say so rather than pick a near miss. `docs/agents/triage-labels.md` holds the mapping, and the commands to adopt the workflow if that is ever wanted.

### Domain docs

Neither `CONTEXT.md` nor `docs/adr/` exists. This project holds its reasoning in `CONTRIBUTING.md` for rules, this file for setup, `README.md` for purpose, and commit messages as a record of decisions. If an ADR directory is needed, create it deliberately rather than assuming it is present.

### Local model

All model work on this repo runs on the local **qwen3.8:27b** through the `RunLocal` skill. Nothing
about this code goes to a cloud API. Claude stays the agent — it reads the files, applies the edits,
runs the `.\test.ps1` gate and drives git; the local model writes the code and does the review.

Use the **`ollama-local` MCP connector**, registered for this repo in `.mcp.json` and hard-pinned
to `qwen3.8:27b`:

- `local_generate` — the actual work. `session: "UpdateEverything"` keeps one thread across a task.
- `local_load` — pin the model in VRAM at the start of a session; a cold load costs 10-30s.
- `local_unload` — hand the card back when the session is done.
- `local_status` — GPU-versus-spill split and active context, when throughput looks wrong.

The connector is stdlib-only and local; nothing third-party sits in the prompt path. If MCP is
unavailable, the RunLocal skill reaches the same model and shares the same session store:

```bash
python C:/Users/brian/.claude/skills/RunLocal/runlocal.py --prompt-file <file> --session UpdateEverything
```

Carry the actual source in the prompt rather than describing it. `--think` for design and debugging,
off for mechanical rewrites. `--session UpdateEverything` keeps one thread across a task. The default
`--num-ctx` of 172032 is the GPU-resident ceiling; anything past it is truncated **silently**, so split
large jobs instead of overflowing. Set the Bash timeout to 600000 — a cold load costs 10–30s.

Report the local model's output as its own, and say so plainly when a run fails. Never quietly answer
in its place: a silent swap sends the work to a cloud model, which is the one thing this setup exists
to prevent.
