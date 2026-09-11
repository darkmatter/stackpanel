#!/usr/bin/env bash
# Exercise the real setup/doctor CLI with deterministic agent and Nix stand-ins.
# Run inside the devshell. No model credentials, network, or Nix builds required.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/stackpanel-agent-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
test_binary="${STACKPANEL_TEST_BINARY:-$test_dir/stack}"
if [[ -z "${STACKPANEL_TEST_BINARY:-}" ]]; then
  go -C "$project_root/apps/stackpanel-go" build -o "$test_binary" .
fi

python3 - "$test_dir" "$test_binary" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

work = Path(sys.argv[1])
binary = str(Path(sys.argv[2]).resolve())
bin_dir = work / "bin"
bin_dir.mkdir()

# Both executables log calls, but only Nix evaluation/provider transport is
# simulated. Each develop subprocess executes the actual Go CLI and doctor.
fake = bin_dir / "fake.py"
fake.write_text(r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

state = Path(os.environ["AGENT_SETUP_TEST_STATE"])
root = state / "repo"
args = sys.argv[1:]
tool = Path(sys.argv[0]).name

def record(event):
    with (state / "calls.jsonl").open("a") as output:
        output.write(json.dumps(event) + "\n")

def clean_environment():
    stale = [key for key in os.environ if key != "STACKPANEL_USER_CONFIG" and key.startswith(("STACKPANEL_", "__STACKPANEL_", "DIRENV_"))]
    assert not stale, "inherited caller environment: " + ", ".join(stale)
    assert "IN_NIX_SHELL" not in os.environ

def emit_message(message):
    print(json.dumps({"type": "item.completed", "item": {
        "type": "agent_message", "text": json.dumps(message)}}))
    print(json.dumps({"type": "turn.completed"}))

if tool == "codex":
    if "--version" in args:
        print("codex-cli 0.100.0")
    elif "--help" in args:
        print("exec --json --sandbox read-only workspace-write --color --config -c")
    else:
        clean_environment()
        prompt = sys.stdin.read()
        phase = next(name for name in ("inspection", "setup", "repair")
                     if "phase " + name + "." in prompt)
        record({"tool": tool, "phase": phase, "args": args})
        assert "--json" in args and args[-1] == "-"
        sandbox = args[args.index("--sandbox") + 1]
        assert sandbox == ("read-only" if phase == "inspection" else "workspace-write")
        if phase == "inspection":
            if state.name == "new-repository" and '"values":["Python"]' not in prompt:
                assert "Setup mode: new" in prompt
                emit_message({"status": "needs_input", "questions": [{
                    "id": "language", "prompt": "Language?", "kind": "single",
                    "options": ["Python"], "default": ["Python"], "required": True}]})
                sys.exit(0)
            expected = {
                "version": 1, "config": [{"path": ["apps", "web"], "exists": True}],
                "requiredChecks": []}
            if state.name == "new-repository":
                expected.update({"files": ["app.py", "test_app.py"], "commands": [{
                    "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            emit_message({"status": "plan", "plan": {"summary": "Configure the web app", "expectations": expected}})
        else:
            assert "Do not invoke stack setup, nix, direnv" in prompt
            assert "Do not create or edit flake.lock yourself" in prompt
            assert (root / "flake.nix").is_file(), "host did not scaffold before the sandboxed agent"
            assert (root / ".stack/config.nix").is_file(), "host did not write template configuration"
            if state.name == "new-repository":
                assert not (root / "flake.lock").exists(), "locking must wait for the app's input edits"
                (root / "app.py").write_text('def greet(name):\n    return "Hello, " + name\n')
                (root / "test_app.py").write_text('from app import greet\nassert greet("world") == "Hello, world"\n')
            (root / ".stack/onboarded.nix").write_text("{ onboarded = true; }\n")
            if state.name == "user-edit-violation":
                (root / "unrelated.txt").write_text("model overwrote existing user edits\n")
            if phase == "repair" and state.name == "lock-repair":
                assert "fixture lock error" in prompt
            elif phase == "repair":
                assert "config:apps.web" in prompt, "repair did not receive doctor failure"
                # Try to weaken the external file. The orchestrator must replace
                # it from the original in-memory contract before the next doctor.
                path = Path((state / "expectations-path").read_text())
                path.write_text(json.dumps({"version": 1, "config": [
                    {"path": ["enable"], "equals": True}], "requiredChecks": []}))
            configured = state.name == "new-repository" or phase == "repair" and state.name in ("repair-success", "lock-repair")
            (root / ".stack/config.nix").write_text(
                "{ enable = true; " + ("apps.web = {}; " if configured else "") + "}\n")
            emit_message({"status": "complete", "summary": "Setup is complete"})
elif tool == "write-files":
    record({"tool": tool})
elif args[:2] == ["flake", "metadata"]:
    clean_environment()
    record({"tool": tool, "args": args})
    print(json.dumps({"url": "github:fixture/stackpanel/" + "a" * 40,
                      "locked": {"rev": "a" * 40}}))
elif args[:2] == ["flake", "lock"]:
    clean_environment()
    assert args[:4] == ["flake", "lock", ".", "--output-lock-file"] and len(args) == 5
    output = Path(args[4])
    assert not output.is_relative_to(root), "lock output must not let Nix stage repository files"
    record({"tool": tool, "args": args, "lock": True})
    marker = state / "lock-attempted"
    if state.name == "lock-repair" and not marker.exists():
        marker.touch()
        print("fixture lock error", file=sys.stderr)
        sys.exit(1)
    lock = root / "flake.lock"
    output.write_bytes(lock.read_bytes() if lock.exists() else b'{"version":7,"root":"root","nodes":{"root":{}}}\n')
elif args and args[0] == "eval":
    record({"tool": tool, "args": args})
    if any("#lib.initTemplates.default" in arg for arg in args):
        print(json.dumps({"flake.nix": "{ outputs = _: {}; }\n", ".stack/config.nix": "{ enable = true; }\n"}))
    elif any("#lib.initAddons" in arg for arg in args):
        print("{}")
    elif any(".stackpanelConfig" in arg for arg in args):
        assert "--no-update-lock-file" in args and "--no-write-lock-file" in args
        config = {"enable": True, "apps": {}, "doctorList": json.loads((state / "checks.json").read_text())}
        if "apps.web" in (root / ".stack/config.nix").read_text():
            config["apps"]["web"] = {}
        print(json.dumps(config))
    else:
        raise AssertionError("unexpected evaluation: " + repr(args))
elif args and args[0] == "build":
    assert args == ["build", "--no-link", "/nix/store/fixture-check.drv^*"]
    record({"tool": tool, "args": args})
elif args and args[0] == "develop":
    clean_environment()
    assert (root / "flake.lock").is_file(), "host did not lock before devshell entry"
    (root / ".stack/gen/codegen").mkdir(parents=True, exist_ok=True)
    (root / ".stack/gen/codegen/env-manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "dataRoot": ".stack/data", "targets": []}))
    assert args[:5] == ["develop", ".", "--no-update-lock-file", "--no-write-lock-file", "--command"]
    index = subprocess.check_output(["git", "ls-files", "--stage", "--debug", "-z",
                                    "--", ".stack/onboarded.nix"], cwd=root)
    flags = int(index.split(b"\tflags: ")[-1].strip(), 16)
    assert flags & 0x20000000, "new Nix input is not visible through intent-to-add"
    command = args[5:]
    doctor = "--expectations" in command
    record({"tool": tool, "args": args, "stage": "doctor" if doctor else "reconcile"})
    if doctor:
        expected_path = Path(command[command.index("--expectations") + 1])
        assert not expected_path.is_relative_to(root)
        expected = json.loads(expected_path.read_text())
        previous_path = state / "expectations-path"
        required = ["fixture-repo", "fixture-build"] if previous_path.exists() else []
        contract = {"version": 1, "config": [
            {"path": ["apps", "web"], "exists": True},
            {"path": ["enable"], "equals": True}], "requiredChecks": required}
        if state.name == "new-repository":
            contract.update({"files": ["app.py", "test_app.py"], "commands": [{
                "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            for path in contract["files"]:
                subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=root, check=True, stdout=subprocess.DEVNULL)
        assert expected == contract, expected
        if previous_path.exists():
            assert previous_path.read_text() == str(expected_path)
        previous_path.write_text(str(expected_path))
    shell_env = dict(os.environ)
    shell_env.update({"STACKPANEL_ROOT": str(root),
        "STACKPANEL_STATE_DIR": str(root / ".stack/profile"),
        "STACKPANEL_CONFIG_JSON": str(state / "config.json"),
        "STACKPANEL_FILES_MANIFEST": str(state / "files.json"),
        "STACKPANEL_FILES_PREFLIGHT_MANIFEST": str(state / "fileops.json")})
    print("NOISY REPOSITORY SHELL HOOK: {this is not JSON}", flush=True)
    result = subprocess.run(command, env=shell_env)
    if doctor:
        report_path = Path(command[command.index("stackpanel-doctor") + 1])
        report = json.loads(report_path.read_text())
        reports = sorted(state.glob("doctor-*.json"))
        (state / ("doctor-%d.json" % (len(reports) + 1))).write_text(json.dumps(report))
    sys.exit(result.returncode)
else:
    raise AssertionError("unexpected tool command: " + tool + " " + repr(args))
''')
fake.chmod(0o755)
for name in ("codex", "nix", "write-files"):
    (bin_dir / name).symlink_to(fake.name)

for name, expected_success in (("repair-success", True), ("permanent-failure", False),
                               ("user-edit-violation", False), ("new-repository", True),
                               ("lock-repair", True)):
    state = work / name
    root = state / "repo"
    (root / ".stack/gen/codegen").mkdir(parents=True)
    (root / "flake.nix").write_text("{ outputs = _: { existing = true; }; }\n")
    (root / "flake.lock").write_text('{"version":7,"root":"root","nodes":{"root":{}}}\n')
    (root / ".stack/config.nix").write_text("{ enable = true; }\n")
    (root / ".stack/gen/codegen/env-manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "dataRoot": ".stack/data", "targets": []}))
    (root / "unrelated.txt").write_text("committed\n")

    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)

    git("init", "-q")
    git("add", ".")
    git("-c", "user.name=Stackpanel Test", "-c", "user.email=test@example.invalid",
        "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
    (root / "unrelated.txt").write_text("staged change\n")
    git("add", "unrelated.txt")
    (root / "unrelated.txt").write_text("staged change\nunstaged change\n")
    staged = git("diff", "--cached", "--", "unrelated.txt")
    unstaged = git("diff", "--", "unrelated.txt")
    original_flake = (root / "flake.nix").read_bytes()
    original_lock = (root / "flake.lock").read_bytes()

    probe = state / "check-repo"
    probe.write_text("#!/bin/sh\nexit 0\n")
    probe.chmod(0o755)
    checks = [
        {"id": "fixture-repo", "module": "fixture", "name": "Repository probe",
         "scope": "repo", "enabled": True, "type": "HEALTHCHECK_TYPE_SCRIPT",
         "severity": "HEALTHCHECK_SEVERITY_CRITICAL", "scriptPath": str(probe)},
        {"id": "fixture-build", "module": "fixture", "name": "Build probe",
         "scope": "build", "enabled": True, "type": "HEALTHCHECK_TYPE_DERIVATION",
         "severity": "HEALTHCHECK_SEVERITY_CRITICAL", "required": True,
         "drvPath": "/nix/store/fixture-check.drv"},
        {"id": "fixture-runtime", "module": "fixture", "name": "Excluded runtime",
         "scope": "runtime", "enabled": True, "type": "HEALTHCHECK_TYPE_SCRIPT",
         "severity": "HEALTHCHECK_SEVERITY_CRITICAL", "scriptPath": "/absent-runtime-probe"},
    ]
    (state / "checks.json").write_text(json.dumps(checks))
    (state / "config.json").write_text(json.dumps({"version": 1, "projectName": name,
        "projectRoot": str(root), "doctor": checks, "addons": []}))
    (state / "files.json").write_text('{"version":2,"files":[]}')
    (state / "fileops.json").write_text('{"version":1,"files":[]}')

    env = dict(os.environ)
    env.update({"PATH": str(bin_dir) + os.pathsep + env["PATH"],
        "AGENT_SETUP_TEST_STATE": str(state), "XDG_CONFIG_HOME": str(state / "user-config"),
        "STACKPANEL_ROOT": str(state / "wrong-repository"),
        "STACKPANEL_CONFIG_JSON": "/invalid/inherited-config.json",
        "STACKPANEL_FILES_MANIFEST": "/invalid/inherited-manifest.json",
        "__STACKPANEL_HOOK_RAN": "1", "DIRENV_DIR": "/invalid/caller"})
    arguments = [binary, "setup", "--experimental-agent=codex", "--yes", "--no-runtime",
        "--flake", "github:fixture/stackpanel"]
    if name == "new-repository":
        shutil.rmtree(root)
        arguments += ["--new", str(root)]
    result = subprocess.run(arguments, cwd=state if name == "new-repository" else root, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    (state / "output.log").write_text(result.stdout + result.stderr)
    if (result.returncode == 0) != expected_success:
        raise AssertionError(name + " produced unexpected status:\n" + result.stdout + result.stderr)

    calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
    if name != "user-edit-violation":
        expected_locks = 1 if name == "new-repository" else 2
        assert sum(bool(call.get("lock")) for call in calls) == expected_locks
    if name == "new-repository":
        assert [call["phase"] for call in calls if call["tool"] == "codex"] == ["inspection", "inspection", "setup"]
        assert [call["stage"] for call in calls if "stage" in call] == ["reconcile", "doctor"]
        report = json.loads((state / "doctor-1.json").read_text())
        statuses = {entry["id"]: entry["status"] for entry in report["checkResults"]}
        assert statuses == {"fixture-repo": "pass", "fixture-build": "pass", "file:app.py": "pass",
                            "file:test_app.py": "pass", "acceptance:app-test": "pass"}, statuses
        assert "turn.completed" not in result.stderr and "item.completed" not in result.stderr
        print("PASS: new-repository (question round, empty target, source visibility and real acceptance command)")
        continue
    visibility = git("ls-files", "--stage", "--debug", "-z", "--", ".stack/onboarded.nix")
    if expected_success:
        flags = int(visibility.split(b"\tflags: ")[-1].strip(), 16)
        assert flags & 0x20000000, "successful onboarding must remain evaluable"
    else:
        assert visibility == b"", "failed onboarding left its own index entries behind"
    assert (root / ".stack/onboarded.nix").is_file(), "cleanup deleted agent worktree output"
    assert git("diff", "--cached", "--", "unrelated.txt") == staged
    if name == "lock-repair":
        assert [call["phase"] for call in calls if call["tool"] == "codex"] == ["inspection", "setup", "repair"]
        assert [call["stage"] for call in calls if "stage" in call] == ["reconcile", "doctor"]
        assert not (state / "doctor-2.json").exists(), "doctor ran before the lock was repaired"
        print("PASS: lock-repair (host Nix error reached the single repair attempt)")
        continue
    if name == "user-edit-violation":
        assert [call["phase"] for call in calls if call["tool"] == "codex"] == ["inspection", "setup"]
        assert not any("stage" in call for call in calls), "reconciliation ran after user edits were overwritten"
        assert "preexisting user edits" in result.stderr and "nothing was reverted" in result.stderr
        assert (root / "unrelated.txt").read_text() == "model overwrote existing user edits\n"
        print("PASS: user-edit-violation (stopped before reconciliation, no automatic revert)")
        continue
    assert [call["phase"] for call in calls if call["tool"] == "codex"] == ["inspection", "setup", "repair"]
    assert [call["stage"] for call in calls if "stage" in call] == ["reconcile", "doctor", "reconcile", "doctor"]
    reports = [json.loads(path.read_text()) for path in sorted(state.glob("doctor-*.json"))]
    assert len(reports) == 2
    for report in reports:
        assert set(report["reconcilers"]) >= {"codegen", "files", "fileops", "checks", "verification"}
        statuses = {entry["id"]: entry["status"] for entry in report["checkResults"]}
        assert statuses == {"fixture-repo": "pass", "fixture-build": "pass"}, statuses
        assert not report.get("changes"), report
    assert any(finding["id"] == "config:apps.web" for finding in reports[0]["findings"])
    last_errors = [finding for finding in (reports[-1].get("findings") or []) if finding["severity"] == "error"]
    assert bool(last_errors) != expected_success, last_errors
    assert git("diff", "--cached", "--", "unrelated.txt") == staged
    assert git("diff", "--", "unrelated.txt") == unstaged
    assert (root / "flake.nix").read_bytes() == original_flake
    assert (root / "flake.lock").read_bytes() == original_lock
    assert (root / ".stack/gen/codegen/modules.json").is_file()
    assert (root / "packages/gen/env/src/runtime/generated-payloads/registry.ts").is_file()
    print("PASS: " + name + " (real doctor, fixed expectations, existing Git changes preserved)")
PY
