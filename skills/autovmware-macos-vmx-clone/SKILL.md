---
name: "autovmware-macos-vmx-clone"
description: "Safely discover, validate, plan, and approval-gate cloning 1 to 5 macOS VMware .vmx templates on the remote Windows AutoVMware host. Use when working on DEM-009 macOS VMX clone workflows through Kimi/RustDesk and hard safeguards are required before any real VM action."
version: "0.2.0"
metadata:
  hermes:
    tags: [autovmware, vmware, macos, dem009, safety]
---

# AutoVMware macOS VMX Clone

Use the bundled Python CLI and `config/defaults.json` as the source of truth. Do not improvise clone commands from prose.

```bash
python scripts/cli.py doctor --format markdown
python scripts/cli.py generate-approval 5 --output config/autovmware-macos-vmx-clone.approval.json
python scripts/cli.py discover --drive F --format markdown
python scripts/cli.py validate-approval --approval-json approval.json
python scripts/cli.py plan-clone --approval-json approval.json --format markdown
python scripts/cli.py report-template --approval-json approval.json --output docs/reports/dem009/clone-report.md
```

### Default Test Configuration

The skill includes the current DEM-009 Windows test parameters in `config/defaults.json`:

- `source_vmx`: `F:\15.7.5\W1-OC-Mac-15.7.5\macOS 15\macOS 15.vmx`
- `target_root`: `F:\VMs`
- `name_prefix`: `dem009-batch`
- `memory_gb`: `8`
- `disk_gb`: `64`
- `clone_mode`: `full`
- `power_on`: `false`
- `network`: `nat`
- `retention_policy`: `keep`

When the operator gives only a number such as `5`, treat it as `clone_count=5` with this default config. Generate and validate the approval JSON first, then echo the full source, target root, target paths, power policy, and retention policy. A real clone still requires the human to explicitly confirm the exact action after those details are shown.

### Natural Language Setup

If the operator asks to configure VMware in natural language, help them edit the config values without running VM actions:

1. Ask for the source `.vmx`, target root, clone prefix, memory, disk, clone mode, network, and whether power-on is allowed.
2. Write or update the config only after the operator confirms the values.
3. Run `doctor`.
4. Send the resulting config summary and doctor output to operations for manual validation.

### Hard Rules

- Do not read or print `.env` files.
- Do not run tests, start services, or run `scripts\deploy\start_all.ps1` on the remote AutoVMware host.
- Do not create, start, stop, delete, snapshot, cleanup, clone, or batch-create any VM unless the human has approved the exact object and action.
- Discovery is read-only. Clone execution is separate from discovery and requires a complete approval JSON.
- `clone_count` must be from 1 to 5.
- `power_on` must be explicit. The default is no.
- If the CLI returns a nonzero exit code or an `E_*` error code, stop and report the failure.
- `doctor`, `discover`, `generate-approval`, `validate-approval`, `plan-clone`, and `report-template` are non-destructive. They must report `real_vm_action_executed=false`.

### Approval JSON

The human must provide every field before a real clone workflow:

```json
{
  "source_vmx": "F:\\15.7.5\\W1-OC-Mac-15.7.5\\macOS 15\\macOS 15.vmx",
  "clone_count": 5,
  "target_root": "F:\\VMs",
  "name_prefix": "DEM009-Mac",
  "memory_gb": 8,
  "disk_gb": 60,
  "clone_mode": "linked",
  "power_on": false,
  "network": "inherit",
  "retention_policy": "keep",
  "approved_action": "clone",
  "approved_by": "human",
  "approval_note": "Exact source, target, count, and power policy approved."
}
```

### Workflow

1. Run `doctor` first. Fix missing config or VMware CLI setup before clone planning.
2. For a simple request such as `5`, run `generate-approval 5`, then `validate-approval`, then `plan-clone`.
3. Echo the full planned action and ask for explicit approval before any real clone.
4. Only after a separate explicit instruction to execute, use AutoVMware's existing clone tooling or the project-approved clone script. Do not hand-write destructive commands.
5. Save screenshots and final evidence paths in the report template.

### Expected Report Evidence

The final stage report should include source `.vmx`, clone count, target paths, free space before and after, clone verification, power state, screenshot paths, forbidden action report, cleanup result if approved, and rerun result if approved.

## setup

Use this when an operator asks Kimi to configure VMware clone defaults in natural language. Confirm the requested source `.vmx`, target root, prefix, memory, disk, clone mode, network, power policy, and retention policy before changing config. After config is written, run `doctor` and return the config summary plus doctor output for operations validation. Do not execute VM actions.

## clone

Use this when an operator asks for a default batch clone by count, including a bare number such as `5`. Generate approval from default config, validate it, plan targets, and show the exact action. Stop before real clone execution until the human explicitly confirms the displayed source, count, targets, clone mode, and power policy.

## discover

Read-only discovery only. Searches the requested drive for macOS-like `.vmx` candidates, reports free space, and lists likely AutoVMware clone tooling. It must not modify files or perform VM actions.

## validate-approval

Validates the approval JSON fields and rejects missing approval, invalid clone counts, unsafe paths, ambiguous `power_on`, low memory/disk values, and unsupported clone modes. It does not execute VM actions.

## plan-clone

Builds a deterministic clone plan from the approval JSON. It validates the same gates, estimates conservative disk budget, and returns the exact target `.vmx` paths. The plan output is still non-destructive.

## generate-approval

Creates an approval JSON from `config/defaults.json` and a clone count. This is how a bare operator input like `5` becomes a validated, auditable request. It does not execute VM actions.

## doctor

Runs read-only environment checks: config parse, Windows path validation, source `.vmx` existence on Windows, target drive free space, VMware CLI tools, Kimi CLI, and safety blockers. It does not read `.env` and does not execute VM actions.

## report-template

Writes a Markdown report scaffold for clone evidence. Use this before and after approved clone/delete/rerun work so screenshot paths, free-space evidence, and forbidden-action status are captured consistently.
