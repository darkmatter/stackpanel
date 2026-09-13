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
root = Path((state / "target-root").read_text()) if (state / "target-root").exists() else state / "repo"
new_repo = state.name in ("new-repository", "resume-new", "resume-tmp")
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
    rendered = message if isinstance(message, str) else json.dumps(message)
    malformed = ((state.name in ("malformed-plan", "malformed-permanent") and phase == "inspection") or
                 (state.name in ("malformed-complete", "claude-malformed-complete") and phase == "setup") or
                 (state.name == "malformed-repair" and phase == "repair"))
    if malformed:
        (state / "valid-reply").write_text(rendered)
        rendered = rendered[:-1] # Missing outer brace, as in the reported failure.
    if tool == "claude":
        denials = [] if phase in ("inspection", "formatting") else [
            {"tool_name": "Glob", "tool_input": {"pattern": "/nix/store/*stackpanel*/**/*.nix"}},
            {"tool_name": "Glob", "tool_input": {"pattern": "/outside/skills/**/SKILL.md"}}]
        print(json.dumps({"type": "result", "subtype": "success", "is_error": False,
                          "result": rendered, "permission_denials": denials}))
        return
    print(json.dumps({"type": "item.completed", "item": {
        "type": "agent_message", "text": rendered}}))
    print(json.dumps({"type": "turn.completed"}))

if tool in ("codex", "claude"):
    assert not os.environ.get("AGENT_SETUP_TEST_DISABLE_AGENT"), "verification retry should not need a coding agent"
    if "--version" in args:
        print("codex-cli 0.100.0")
    elif "--help" in args:
        print("exec --json --sandbox read-only workspace-write --color --config -c --print --output-format stream-json --permission-mode plan acceptEdits --strict-mcp-config --mcp-config --settings")
    else:
        clean_environment()
        root = Path.cwd()
        (state / "target-root").write_text(str(root))
        fixture_config = json.loads((state / "config.json").read_text())
        fixture_config["projectRoot"] = str(root)
        (state / "config.json").write_text(json.dumps(fixture_config))
        prompt = sys.stdin.read()
        phase = "formatting" if "This is a formatting retry only." in prompt else next(
            name for name in ("inspection", "setup", "repair") if "phase " + name + "." in prompt)
        record({"tool": tool, "phase": phase, "args": args})
        if tool == "codex":
            assert "--json" in args and args[-1] == "-"
            sandbox = args[args.index("--sandbox") + 1]
            assert sandbox == ("read-only" if phase in ("inspection", "formatting") else "workspace-write")
        else:
            assert args[args.index("--permission-mode") + 1] == ("plan" if phase in ("inspection", "formatting") else "acceptEdits")
            assert args[args.index("--tools") + 1] == ("Read,Glob,Grep" if phase in ("inspection", "formatting") else "Read,Glob,Grep,Edit,Write")
        if phase == "formatting":
            assert "Do not use tools" in prompt
            original = (state / "valid-reply").read_text()
            if state.name == "malformed-permanent" and not (state / "retry").exists():
                original = original[:-1]
            emit_message(original)
            sys.exit(0)
        if phase == "inspection":
            if (new_repo or state.name == "resume-inspection") and '"values":["Python"]' not in prompt:
                if new_repo:
                    assert "Setup mode: new" in prompt
                emit_message({"status": "needs_input", "questions": [{
                    "id": "language", "prompt": "Language?", "kind": "single",
                    "options": ["Python"], "default": ["Python"], "required": True}]})
                sys.exit(0)
            if state.name == "resume-inspection" and not (state / "interrupted").exists():
                (state / "interrupted").touch()
                print("fixture agent disconnected after receiving answers", file=sys.stderr)
                sys.exit(1)
            if state.name.startswith("resume-") and (state / "retry").exists():
                assert "Resuming saved onboarding" in prompt
            expected = {
                "version": 1, "config": [{"path": ["apps", "web"], "exists": True}],
                "requiredChecks": []}
            if new_repo:
                expected.update({"files": ["app.py", "test_app.py"], "commands": [{
                    "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            emit_message({"status": "plan", "plan": {"summary": "Configure the web app", "expectations": expected}})
        else:
            assert "Do not invoke stack setup, nix, direnv" in prompt
            assert "Do not create or edit flake.lock yourself" in prompt
            assert (root / "flake.nix").is_file(), "host did not scaffold before the sandboxed agent"
            assert (root / ".stack/config.nix").is_file(), "host did not write template configuration"
            if new_repo:
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
            if state.name in ("resume-agent", "resume-new", "resume-tmp") and not (state / "interrupted").exists():
                (state / "interrupted").touch()
                emit_message({"status": "blocked", "summary": "fixture interrupted after partial output"})
                sys.exit(0)
            if state.name.startswith("resume-") and (state / "retry").exists():
                assert "Resuming saved onboarding" in prompt
                if new_repo or state.name == "resume-inspection":
                    assert '\"values\":[\"Python\"]' in prompt
            configured = state.name in ("malformed-plan", "malformed-complete", "malformed-permanent", "claude-malformed-complete") or phase == "repair" and state.name == "malformed-repair" or new_repo or state.name in ("resume-agent", "resume-inspection", "resume-doctor", "resume-kill", "resume-complete") or phase == "repair" and state.name in ("repair-success", "lock-repair", "claude-read-denial") or state.name == "resume-contract" and phase == "repair" and (state / "retry").exists()
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
    if doctor and state.name in ("resume-doctor", "resume-kill") and not (state / "interrupted").exists():
        import signal
        import time
        (state / "interrupted").touch()
        os.kill(os.getppid(), signal.SIGKILL if state.name == "resume-kill" else signal.SIGTERM)
        if state.name == "resume-kill":
            sys.exit(0)
        time.sleep(30) # the host must cancel this process group
        raise AssertionError("host failed to cancel interrupted doctor")
    if doctor:
        expected_path = Path(command[command.index("--expectations") + 1])
        assert not expected_path.is_relative_to(root)
        expected = json.loads(expected_path.read_text())
        previous_path = state / "expectations-path"
        required = ["fixture-repo", "fixture-build"] if previous_path.exists() else []
        contract = {"version": 1, "config": [
            {"path": ["apps", "web"], "exists": True},
            {"path": ["enable"], "equals": True}], "requiredChecks": required}
        if new_repo:
            contract.update({"files": ["app.py", "test_app.py"], "commands": [{
                "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            for path in contract["files"]:
                subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=root, check=True, stdout=subprocess.DEVNULL)
        assert expected == contract, expected
        if previous_path.exists() and not state.name.startswith("resume-"):
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
for name in ("codex", "claude", "nix", "write-files"):
    (bin_dir / name).symlink_to(fake.name)

for name, expected_success in (("repair-success", True), ("permanent-failure", False),
                               ("user-edit-violation", False), ("new-repository", True),
                               ("lock-repair", True), ("claude-read-denial", True),
                               ("claude-read-denial-failure", False), ("resume-agent", False),
                               ("resume-inspection", False), ("resume-doctor", False),
                               ("resume-new", False), ("resume-tmp", False), ("resume-contract", False),
                               ("resume-kill", False), ("resume-user-fix", False), ("resume-complete", True), ("malformed-plan", True),
                               ("malformed-complete", True), ("malformed-repair", True),
                               ("malformed-permanent", False), ("claude-malformed-complete", True)):
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
        "STACKPANEL_USER_CONFIG": str(state / "user-config/stackpanel/stackpanel.yaml"),
        "STACKPANEL_ROOT": str(state / "wrong-repository"),
        "STACKPANEL_CONFIG_JSON": "/invalid/inherited-config.json",
        "STACKPANEL_FILES_MANIFEST": "/invalid/inherited-manifest.json",
        "__STACKPANEL_HOOK_RAN": "1", "DIRENV_DIR": "/invalid/caller"})
    provider = "claude" if name.startswith("claude-") else "codex"
    arguments = [binary, "setup", "--experimental-agent=" + provider, "--yes", "--no-runtime",
        "--flake", "github:fixture/stackpanel"]
    if name in ("new-repository", "resume-new"):
        shutil.rmtree(root)
        arguments += ["--new", str(root)]
    if name == "resume-agent":
        arguments += ["--agent-log", str(state / "agent.jsonl")]
    if name == "resume-tmp":
        arguments += ["--tmp"]
    invocation_dir = state if name in ("new-repository", "resume-new", "resume-tmp") else root
    result = subprocess.run(arguments, cwd=invocation_dir, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    (state / "output.log").write_text(result.stdout + result.stderr)
    if (result.returncode == 0) != expected_success:
        raise AssertionError(name + " produced unexpected status:\n" + result.stdout + result.stderr)

    calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
    if name.startswith("malformed-") or name == "claude-malformed-complete":
        manifests = list((state / "user-config/stackpanel/setup").glob("*.json"))
        assert len(manifests) == 1
        saved = json.loads(manifests[0].read_text())
        if name == "malformed-permanent":
            assert saved["pendingReply"]["message"] == (state / "valid-reply").read_text()[:-1]
            assert "after one formatting retry" in result.stderr
            (state / "retry").touch()
            retry = subprocess.run(arguments, cwd=root, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, timeout=30)
            assert retry.returncode == 0, retry.stdout + retry.stderr
            saved = json.loads(manifests[0].read_text())
            calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
        assert saved["stage"] == "complete" and not saved.get("pendingReply"), saved["stage"]
        phases = [call["phase"] for call in calls if call["tool"] == provider]
        expected = {
            "malformed-plan": ["inspection", "formatting", "setup"],
            "malformed-complete": ["inspection", "setup", "formatting"],
            "claude-malformed-complete": ["inspection", "setup", "formatting"],
            "malformed-repair": ["inspection", "setup", "repair", "formatting"],
            "malformed-permanent": ["inspection", "formatting", "formatting", "setup"],
        }[name]
        assert phases == expected, phases
        reports = sorted(state.glob("doctor-*.json"))
        assert len(reports) == (2 if name == "malformed-repair" else 1)
        report = json.loads(reports[-1].read_text())
        assert not [finding for finding in (report.get("findings") or []) if finding["severity"] == "error"]
        assert git("diff", "--cached", "--", "unrelated.txt") == staged
        assert git("diff", "--", "unrelated.txt") == unstaged
        print("PASS: " + name + " (read-only format recovery, no repeated edits, real doctor)")
        continue
    if name.startswith("resume-"):
        root = Path((state / "target-root").read_text())
        manifests = list((state / "user-config/stackpanel/setup").glob("*.json"))
        manifests = [path for path in manifests if not path.name.startswith("tmp-")]
        assert len(manifests) == 1, manifests
        manifest_path = manifests[0]
        saved = json.loads(manifest_path.read_text())
        assert saved["root"] == str(root)
        assert saved["stage"] == {"resume-agent": "apply", "resume-new": "apply", "resume-tmp": "apply",
                                  "resume-inspection": "inspection", "resume-doctor": "verify", "resume-kill": "verify", "resume-contract": "repair", "resume-user-fix": "repair", "resume-complete": "complete"}[name], saved["stage"]
        if name not in ("resume-kill", "resume-complete"):
            assert "Rerun the same command to resume" in result.stderr, result.stderr
        if name == "resume-contract":
            assert saved["plan"]["expectations"]["requiredChecks"] == ["fixture-repo", "fixture-build"]
        if name in ("resume-inspection", "resume-new", "resume-tmp"):
            assert saved["request"]["answers"] == [{"id": "language", "values": ["Python"]}]
            assert len(saved["conversation"]) == 1
        initial_log = (state / "agent.jsonl").read_bytes() if name == "resume-agent" else None
        phases_before = [call["phase"] for call in calls if call["tool"] == provider]
        (state / "retry").touch()
        if name == "resume-user-fix":
            (root / ".stack/config.nix").write_text("{ enable = true; apps.web = {}; }\n")
        if name in ("resume-doctor", "resume-kill", "resume-user-fix", "resume-complete"):
            env["AGENT_SETUP_TEST_DISABLE_AGENT"] = "1"
        # Omitted configuration flags inherit the original selection.
        retry_args = [arg for arg in arguments if arg != "github:fixture/stackpanel" and arg != "--flake"]
        retry = subprocess.run(retry_args, cwd=invocation_dir, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        assert retry.returncode == 0, name + " retry failed:\n" + retry.stdout + retry.stderr
        assert "Resuming " in retry.stderr
        if name == "resume-agent":
            assert (state / "agent.jsonl").read_bytes() == initial_log
            assert len(list(state.glob("agent.jsonl.resume-*.jsonl"))) == 1
        completed = json.loads(manifest_path.read_text())
        assert completed["stage"] == "complete", completed["stage"]
        assert completed["root"] == str(root)
        assert not completed.get("lastError")
        calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
        phases = [call["phase"] for call in calls if call["tool"] == provider]
        if name in ("resume-doctor", "resume-kill", "resume-user-fix", "resume-complete"):
            assert phases == phases_before, "agent ran again after completing generation"
        elif name == "resume-contract":
            assert phases == phases_before + ["repair"], phases
            assert completed["plan"]["expectations"] == saved["plan"]["expectations"]
        elif name == "resume-inspection":
            assert phases == phases_before + ["inspection", "setup"], phases
            assert len(completed["conversation"]) == 1, "answered question was repeated"
        else:
            assert phases == phases_before + ["setup"], phases
        if name == "resume-tmp":
            assert retry.stdout.strip() == str(root), retry.stdout
            shutil.rmtree(root)
        elif name != "resume-new":
            assert git("diff", "--cached", "--", "unrelated.txt") == staged
            assert git("diff", "--", "unrelated.txt") == unstaged
        print("PASS: " + name + " (separate-process retry, saved choices, current-repository doctor)")
        continue
    if provider == "claude":
        assert "Warning: Claude read permission denied: Glob" in result.stderr
        assert "doctor still verifies" in result.stderr
    if name != "user-edit-violation":
        expected_locks = 1 if name == "new-repository" else 2
        assert sum(bool(call.get("lock")) for call in calls) == expected_locks
    if name == "new-repository":
        assert [call["phase"] for call in calls if call["tool"] == provider] == ["inspection", "inspection", "setup"]
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
        assert [call["phase"] for call in calls if call["tool"] == provider] == ["inspection", "setup", "repair"]
        assert [call["stage"] for call in calls if "stage" in call] == ["reconcile", "doctor"]
        assert not (state / "doctor-2.json").exists(), "doctor ran before the lock was repaired"
        print("PASS: lock-repair (host Nix error reached the single repair attempt)")
        continue
    if name == "user-edit-violation":
        assert [call["phase"] for call in calls if call["tool"] == provider] == ["inspection", "setup"]
        assert not any("stage" in call for call in calls), "reconciliation ran after user edits were overwritten"
        assert "preexisting user edits" in result.stderr and "nothing was reverted" in result.stderr
        assert (root / "unrelated.txt").read_text() == "model overwrote existing user edits\n"
        print("PASS: user-edit-violation (stopped before reconciliation, no automatic revert)")
        continue
    assert [call["phase"] for call in calls if call["tool"] == provider] == ["inspection", "setup", "repair"]
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
