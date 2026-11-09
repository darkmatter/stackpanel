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
    if state.name == "malformed-plan" and phase == "inspection":
        rendered = rendered[:-2] # Providers sometimes stop before the last braces.
    if tool == "claude":
        denials = [] if phase == "inspection" else [
            {"tool_name": "Glob", "tool_input": {"pattern": "/nix/store/*stackpanel*/**/*.nix"}},
            {"tool_name": "Bash", "tool_input": {"command": "private-command-input"}}]
        print(json.dumps({"type": "result", "subtype": "success", "is_error": False,
                          "result": rendered, "permission_denials": denials}))
        return
    print("Reading prompt from stdin...")
    print(json.dumps({"type": "item.completed", "item": {
        "type": "agent_message", "text": rendered}}))
    print(json.dumps({"type": "turn.completed"}))

if tool in ("codex", "claude"):
    assert not os.environ.get("AGENT_SETUP_TEST_DISABLE_AGENT"), "verification retry should not need a coding agent"
    if args == ["--version"]:
        print(tool + " 1.0.0")
        sys.exit(0)
    clean_environment()
    root = Path.cwd()
    (state / "target-root").write_text(str(root))
    fixture_config = json.loads((state / "config.json").read_text())
    fixture_config["projectRoot"] = str(root)
    (state / "config.json").write_text(json.dumps(fixture_config))
    prompt = sys.stdin.read()
    phase = next(name for name in ("inspection", "setup", "repair") if "phase " + name + "." in prompt)
    record({"tool": tool, "phase": phase, "args": args})
    if tool == "codex":
        assert "--json" in args and args[-1] == "-"
        assert args[args.index("--sandbox") + 1] == ("read-only" if phase == "inspection" else "workspace-write")
    else:
        assert args[args.index("--permission-mode") + 1] == ("plan" if phase == "inspection" else "acceptEdits")
        assert args[args.index("--tools") + 1] == ("Read,Glob,Grep" if phase == "inspection" else "Read,Glob,Grep,Edit,Write")
    assert '"optionSchema"' in prompt and '.tooling.dev.package"' in prompt, "agent did not receive pinned app schema"
    retry = (state / "retry").exists()
    if retry:
        assert "Resuming saved onboarding" in prompt
    if phase == "inspection":
        if (new_repo or state.name == "resume-inspection") and '"values":["Python"]' not in prompt:
            if new_repo:
                assert "Setup mode: new" in prompt
            emit_message({"status": "needs_input", "questions": [{
                "id": "language", "prompt": "Language?", "kind": "single",
                "options": ["Python"], "default": ["Python"], "required": True}]})
            sys.exit(0)
        if state.name == "resume-inspection" and not retry:
            print("fixture agent disconnected after receiving answers", file=sys.stderr)
            sys.exit(1)
        if state.name == "prose-replies":
            emit_message("I will add the web app to .stack/config.nix.")
            sys.exit(0)
        expected = {"version": 1, "config": [{"path": ["apps", "web"], "exists": True}]}
        plan = {"summary": "Configure the web app", "expectations": expected}
        if new_repo:
            expected.update({"files": ["app.py", "test_app.py", "deps.lock"], "commands": [{
                "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            plan["prepare"] = [{"id": "deps", "dir": ".", "argv": [
                sys.executable, "-c", "open('deps.lock', 'w').write('locked\\n')"]}]
        if state.name == "prepare-repair":
            plan["prepare"] = [{"id": "deps", "dir": ".", "argv": [sys.executable, "-c",
                "import os, sys\nmarker = os.environ['AGENT_SETUP_TEST_STATE'] + '/prepare-attempted'\n"
                "if not os.path.exists(marker):\n    open(marker, 'w').close()\n    sys.exit('fixture registry error')"]}]
        emit_message({"status": "plan", "plan": plan})
        sys.exit(0)
    assert "Do not run nix" in prompt and "do not edit flake.lock" in prompt
    assert (root / "flake.nix").is_file(), "host did not scaffold before the agent"
    assert (root / ".stack/config.nix").is_file(), "host did not write template configuration"
    if new_repo:
        assert not (root / "flake.lock").exists(), "locking must wait for the app's input edits"
        (root / "app.py").write_text('def greet(name):\n    return "Hello, " + name\n')
        assert not (root / "deps.lock").exists(), "lockfiles belong to host preparation"
        (root / "test_app.py").write_text('from app import greet\nassert greet("world") == "Hello, world"\n'
                                          'assert open("deps.lock").read() == "locked\\n"\n')
    (root / ".stack/onboarded.nix").write_text("{ onboarded = true; }\n")
    if state.name == "edits-user-files":
        (root / "unrelated.txt").write_text("the agent replaced this dirty file\n")
        with (root / "flake.nix").open("a") as flake:
            flake.write("# edited by the agent\n")
    if phase == "repair":
        if state.name == "devshell-repair":
            assert "fixture devshell error" in prompt
        elif state.name == "prepare-repair":
            assert "prepare command deps failed" in prompt and "fixture registry error" in prompt
        else:
            assert "apps.web: expected exists=true" in prompt, "repair did not receive doctor's findings"
            # Weakening the checks file cannot help: the host writes it again
            # from the accepted plan before each doctor run.
            path = Path((state / "expectations-path").read_text())
            path.write_text(json.dumps({"version": 1, "config": [{"path": ["enable"], "equals": True}]}))
    if state.name in ("resume-agent", "resume-new", "resume-tmp") and not retry:
        print("fixture agent crashed after partial output", file=sys.stderr)
        sys.exit(1)
    # Scenarios that need a repair leave the app out until their repair turn.
    configured = not (phase == "setup" and state.name in ("repair-success", "claude-denials"))
    if state.name in ("permanent-failure", "resume-user-fix"):
        configured = False
    (root / ".stack/config.nix").write_text("{ enable = true; " + ("apps.web = {}; " if configured else "") + "}\n")
    emit_message("All done." if state.name == "prose-replies" else {"status": "complete", "summary": "Setup is complete"})
elif tool == "write-files":
    record({"tool": tool})
elif args[:2] == ["flake", "metadata"]:
    clean_environment()
    record({"tool": tool, "args": args})
    print(json.dumps({"url": "github:fixture/stackpanel/" + "a" * 40,
                      "locked": {"rev": "a" * 40}}))
elif args and args[0] == "eval":
    record({"tool": tool, "args": args})
    if any("#lib.initTemplates.default" in arg for arg in args):
        print(json.dumps({"flake.nix": "{ outputs = _: {}; }\n", ".stack/config.nix": "{ enable = true; }\n"}))
    elif any("#lib.initAddons" in arg for arg in args):
        print("{}")
    elif "--expr" in args and "flake.lib.getOptions" in args[-1]:
        clean_environment()
        assert "--impure" not in args
        assert 'builtins.getFlake "github:fixture/stackpanel/' + "a" * 40 + '"' in args[-1]
        print(json.dumps([{"name": "apps.<name>.tooling.dev.package", "type": "package", "description": "Tool binary package"}]))
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
    assert args[:3] == ["develop", ".", "--command"], args
    index = subprocess.check_output(["git", "ls-files", "--stage", "--debug", "-z",
                                    "--", ".stack/onboarded.nix"], cwd=root)
    flags = int(index.split(b"\tflags: ")[-1].strip(), 16)
    assert flags & 0x20000000, "new Nix input is not visible through intent-to-add"
    command = args[3:]
    doctor = "--expectations" in command
    stage = "doctor" if doctor else "prepare" if "stackpanel-prepare" in command else "reconcile"
    record({"tool": tool, "args": args, "stage": stage})
    marker = state / "devshell-failed"
    if state.name == "devshell-repair" and not marker.exists():
        marker.touch()
        print("fixture devshell error", file=sys.stderr)
        sys.exit(1)
    # Like Nix, entering the shell creates a missing lock file.
    if not (root / "flake.lock").exists():
        (root / "flake.lock").write_text('{"version":7,"root":"root","nodes":{"root":{}}}\n')
    (root / ".stack/gen/codegen").mkdir(parents=True, exist_ok=True)
    (root / ".stack/gen/codegen/env-manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "dataRoot": ".stack/data", "targets": []}))
    if doctor and state.name in ("resume-doctor", "resume-kill") and not (state / "retry").exists():
        import signal
        import time
        os.kill(os.getppid(), signal.SIGKILL if state.name == "resume-kill" else signal.SIGTERM)
        if state.name == "resume-kill":
            sys.exit(0)
        time.sleep(30) # the host must cancel this process group
        raise AssertionError("host failed to cancel interrupted doctor")
    if doctor:
        expected_path = Path(command[command.index("--expectations") + 1])
        assert not expected_path.is_relative_to(root)
        expected = json.loads(expected_path.read_text())
        contract = {"version": 1, "requiredChecks": None, "config": [
            {"path": ["apps", "web"], "exists": True},
            {"path": ["enable"], "equals": True}]}
        if state.name == "prose-replies":
            contract["config"] = [{"path": ["enable"], "equals": True}]
        if new_repo:
            contract.update({"files": ["app.py", "test_app.py", "deps.lock"], "commands": [{
                "id": "app-test", "scope": "build", "dir": ".", "argv": [sys.executable, "test_app.py"]}]})
            for path in contract["files"]:
                subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=root, check=True, stdout=subprocess.DEVNULL)
        assert expected == contract, expected
        (state / "expectations-path").write_text(str(expected_path))
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

# name -> (setup exits 0, setup finishes with doctor warnings)
scenarios = {
    "repair-success": (True, False), "permanent-failure": (True, True), "edits-user-files": (True, False),
    "new-repository": (True, False), "devshell-repair": (True, False), "prepare-repair": (True, False),
    "claude-denials": (True, False), "malformed-plan": (True, False), "prose-replies": (True, False),
    "resume-agent": (False, False), "resume-inspection": (False, False), "resume-doctor": (False, False),
    "resume-kill": (False, False), "resume-new": (False, False), "resume-tmp": (False, False),
    "resume-user-fix": (True, True), "resume-complete": (True, False),
}
for name, (expected_success, warnings) in scenarios.items():
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
        # Doctor cannot run this type here; setup must not treat it as a problem.
        {"id": "fixture-unsupported", "module": "fixture", "name": "Unsupported probe",
         "scope": "repo", "enabled": True, "type": "HEALTHCHECK_TYPE_NIX",
         "severity": "HEALTHCHECK_SEVERITY_CRITICAL"},
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
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    (state / "output.log").write_text(result.stdout + result.stderr)
    if (result.returncode == 0) != expected_success:
        raise AssertionError(name + " produced unexpected status:\n" + result.stdout + result.stderr)
    assert ("stack doctor still reports" in result.stderr) == warnings, result.stderr
    root = Path((state / "target-root").read_text())
    calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
    phases = [call["phase"] for call in calls if call["tool"] == provider]
    stages = [call["stage"] for call in calls if "stage" in call]
    manifests = [p for p in (state / "user-config/stackpanel/setup").glob("*.json") if not p.name.startswith("tmp-")]
    assert len(manifests) == 1, manifests
    manifest_path = manifests[0]
    saved = json.loads(manifest_path.read_text())
    assert saved["root"] == str(root)

    if name == "permanent-failure":
        # The saved checks still run without an agent, and still fail.
        doctor_env = dict(env)
        doctor_env.update({"STACKPANEL_ROOT": str(root), "STACKPANEL_STATE_DIR": str(root / ".stack/profile"),
            "STACKPANEL_CONFIG_JSON": str(state / "config.json"), "STACKPANEL_FILES_MANIFEST": str(state / "files.json"),
            "STACKPANEL_FILES_PREFLIGHT_MANIFEST": str(state / "fileops.json"), "AGENT_SETUP_TEST_DISABLE_AGENT": "1"})
        manifest_bytes = manifest_path.read_bytes()
        doctor = subprocess.run([binary, "doctor", "--onboarding", "--json"], cwd=root, env=doctor_env,
                                capture_output=True, text=True, timeout=30)
        assert doctor.returncode == 1, doctor.stdout + doctor.stderr
        assert any(f["id"] == "config:apps.web" for f in json.loads(doctor.stdout)["findings"])
        assert manifest_path.read_bytes() == manifest_bytes, "doctor changed saved setup state"

    if name.startswith("resume-"):
        assert saved["stage"] == {"resume-agent": "apply", "resume-new": "apply", "resume-tmp": "apply",
                                  "resume-inspection": "inspection", "resume-doctor": "verify", "resume-kill": "verify",
                                  "resume-user-fix": "complete", "resume-complete": "complete"}[name], saved["stage"]
        if not expected_success and name != "resume-kill":
            assert "Rerun the same" in result.stderr, result.stderr
        if name in ("resume-inspection", "resume-new", "resume-tmp"):
            assert saved["request"]["answers"] == [{"id": "language", "values": ["Python"]}]
            assert len(saved["conversation"]) == 1
        if name in ("resume-new", "resume-inspection"):
            # Manifests from before the schema context gain it without
            # repeating answers.
            brief = json.loads(saved["request"]["context"])
            del brief["optionSchema"]
            saved["request"]["context"] = json.dumps(brief)
            manifest_path.write_text(json.dumps(saved))
        initial_log = (state / "agent.jsonl").read_bytes() if name == "resume-agent" else None
        (state / "retry").touch()
        if name == "resume-user-fix":
            (root / ".stack/config.nix").write_text("{ enable = true; apps.web = {}; }\n")
        if name in ("resume-doctor", "resume-kill", "resume-user-fix", "resume-complete"):
            env["AGENT_SETUP_TEST_DISABLE_AGENT"] = "1"
        # Omitted configuration flags inherit the original selection.
        retry_args = [arg for arg in arguments if arg not in ("github:fixture/stackpanel", "--flake")]
        retry = subprocess.run(retry_args, cwd=invocation_dir, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
        assert retry.returncode == 0, name + " retry failed:\n" + retry.stdout + retry.stderr
        assert "Resuming " in retry.stderr and "stack doctor still reports" not in retry.stderr, retry.stderr
        if name == "resume-agent":
            assert (state / "agent.jsonl").read_bytes() == initial_log
            assert len(list(state.glob("agent.jsonl.resume-*.jsonl"))) == 1
        completed = json.loads(manifest_path.read_text())
        assert completed["stage"] == "complete" and completed["root"] == str(root), completed
        assert not completed.get("lastError")
        calls = [json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()]
        after = [call["phase"] for call in calls if call["tool"] == provider]
        expected_phases = {"resume-inspection": ["inspection", "setup"], "resume-agent": ["setup"],
                           "resume-new": ["setup"], "resume-tmp": ["setup"]}.get(name, [])
        assert after == phases + expected_phases, after
        if name == "resume-inspection":
            assert len(completed["conversation"]) == 1, "answered question was asked again"
        if name == "resume-tmp":
            assert retry.stdout.strip() == str(root), retry.stdout
        if name == "resume-complete":
            # A Pi-backed session re-verifies current files without provider
            # credentials, like the CLI backends. Doctor never calls Pi.
            completed["agent"] = "pi"
            completed["options"]["agentModel"] = "openai/gpt-5"
            completed["pi"] = {"model": "openai/gpt-5"}
            manifest_path.write_text(json.dumps(completed))
            pi_env = dict(env, OPENAI_API_KEY="", ANTHROPIC_API_KEY="")
            pi_args = ["--experimental-agent=pi" if arg.startswith("--experimental-agent=") else arg for arg in retry_args]
            pi_retry = subprocess.run(pi_args, cwd=invocation_dir, env=pi_env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
            assert pi_retry.returncode == 0, pi_retry.stdout + pi_retry.stderr
            print("PASS: pi-verification-resume (real doctor, no API key or coding agent)")
        if name not in ("resume-new", "resume-tmp"):
            assert git("diff", "--cached", "--", "unrelated.txt") == staged
        if name == "resume-tmp":
            shutil.rmtree(root)
        print("PASS: " + name + " (separate-process retry, saved choices, current-repository doctor)")
        continue

    assert saved["stage"] == "complete", saved["stage"]
    reports = [json.loads(path.read_text()) for path in sorted(state.glob("doctor-*.json"))]
    for report in reports:
        assert set(report["reconcilers"]) >= {"codegen", "files", "fileops", "checks", "verification"}
        statuses = {entry["id"]: entry["status"] for entry in report["checkResults"]}
        assert statuses.get("fixture-repo") == "pass" and statuses.get("fixture-build") == "pass", statuses
        assert statuses.get("fixture-unsupported") == "skipped", statuses
    visibility = git("ls-files", "--stage", "--debug", "-z", "--", ".stack/onboarded.nix")
    assert int(visibility.split(b"\tflags: ")[-1].strip(), 16) & 0x20000000, "new Nix input is not visible to Nix"
    if name != "new-repository":
        assert git("diff", "--cached", "--", "unrelated.txt") == staged, "setup changed the user's staged changes"
    if provider == "claude":
        assert "Claude was denied Glob" in result.stderr and "denied Bash" in result.stderr, result.stderr
        assert "private-command-input" not in result.stderr
    if name == "new-repository":
        assert phases == ["inspection", "inspection", "setup"], phases
        assert stages == ["reconcile", "prepare", "doctor"], stages
        statuses = {entry["id"]: entry["status"] for entry in reports[0]["checkResults"]}
        assert {statuses[key] for key in ("file:app.py", "file:test_app.py", "file:deps.lock", "acceptance:app-test")} == {"pass"}, statuses
        assert "Host preparation" in result.stderr and "Preparing deps" in result.stderr
        assert "turn.completed" not in result.stderr and "item.completed" not in result.stderr
        print("PASS: new-repository (question round, empty target, host preparation, source visibility and real acceptance command)")
        continue
    expected = {
        "repair-success": (["inspection", "setup", "repair"], ["reconcile", "doctor", "reconcile", "doctor"]),
        "permanent-failure": (["inspection", "setup", "repair"], ["reconcile", "doctor", "reconcile", "doctor"]),
        "claude-denials": (["inspection", "setup", "repair"], ["reconcile", "doctor", "reconcile", "doctor"]),
        "devshell-repair": (["inspection", "setup", "repair"], ["reconcile", "reconcile", "doctor"]),
        "prepare-repair": (["inspection", "setup", "repair"], ["reconcile", "prepare", "reconcile", "prepare", "doctor"]),
        "edits-user-files": (["inspection", "setup"], ["reconcile", "doctor"]),
        "malformed-plan": (["inspection", "setup"], ["reconcile", "doctor"]),
        "prose-replies": (["inspection", "setup"], ["reconcile", "doctor"]),
    }[name]
    assert (phases, stages) == expected, (phases, stages)
    if len(reports) == 2:
        assert any(finding["id"] == "config:apps.web" for finding in reports[0]["findings"])
    last_errors = [f for f in (reports[-1].get("findings") or []) if f["severity"] == "error" and "fixture-unsupported" not in f["id"]]
    assert bool(last_errors) == warnings, last_errors
    assert (root / "flake.lock").read_bytes() == original_lock
    if name == "edits-user-files":
        assert (root / "unrelated.txt").read_text() == "the agent replaced this dirty file\n"
        assert (root / "flake.nix").read_bytes() == original_flake + b"# edited by the agent\n"
    else:
        assert git("diff", "--", "unrelated.txt") == unstaged
        assert (root / "flake.nix").read_bytes() == original_flake
    assert (root / ".stack/gen/codegen/modules.json").is_file()
    assert (root / "packages/gen/env/src/runtime/generated-payloads/registry.ts").is_file()
    print("PASS: " + name + " (real doctor, accepted plan's checks)")
PY
