#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError(f"Expected one production declaration: {marker}")
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    position = opening + 1
    while depth and position < len(source):
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    if depth:
        raise ValueError(f"Unclosed production declaration: {marker}")
    return source[start:position]


def isolated_ax_source(source):
    source = re.sub(r"\bAXUIElementPerformAction\s*\(", "AXFixture.performAction(", source)
    for api in ["AXObserverAddNotification", "AXObserverRemoveNotification"]:
        source = re.sub(r"\b" + api + r"\s*\(", "AXFixture.forbiddenObserverCall(", source)
    calls = set(re.findall(r"\b(AX[A-Za-z0-9_]+)\s*\(", source))
    permitted = {"AXUIElementCreateApplication", "AXBudget", "AXMenuReader", "AXMenuSession",
                 "AXContextWitness", "AXPathStep", "AXCommandReference"}
    unexpected = calls - permitted
    if unexpected:
        raise ValueError(f"Unisolated AX API or unknown constructor: {sorted(unexpected)}")
    return source


def run(command, directory, log, environment=None):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=directory, env=environment,
                                stdout=output, stderr=subprocess.STDOUT, timeout=180)
    if result.returncode:
        print(log.read_text(), file=sys.stderr)
        raise RuntimeError(f"exit {result.returncode}: {' '.join(map(str, command))}; {log}")
    return log.read_text()


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


def shell_regression(output):
    records = []
    for plugins_present in [False, True]:
        folder = output / ("plugin present" if plugins_present else "plugin absent")
        fixture = folder / "repository with spaces"
        fixture.mkdir(parents=True)
        (fixture / "scripts").mkdir()
        for name in ["verify.sh", "check-source.py"]:
            shutil.copy2(ROOT / "scripts" / name, fixture / "scripts" / name)
        for name in ["Package.swift", "README.md", "README.ja.md", "AGENTS.md", "LICENSE", "docs", "Resources", "Sources"]:
            (fixture / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
        shims = folder / "shims"
        shims.mkdir()
        swift = folder / "toolchain/bin/swift"
        swift.parent.mkdir(parents=True)
        swift.write_text("fixture\n")
        plugins = swift.parent.parent / "lib/swift/host/plugins/testing"
        if plugins_present:
            plugins.mkdir(parents=True)
        command_log = folder / "commands.jsonl"
        environment = os.environ.copy()
        environment.update(PATH=str(shims) + os.pathsep + environment.get("PATH", ""),
                           TRANSOM_TEST_COMMANDS=str(command_log), TRANSOM_TEST_SWIFT=str(swift),
                           TRANSOM_TEST_PYTHON=sys.executable)
        executable(shims / "uname", '#!/bin/bash\nprintf "%s\\n" Darwin\n')
        executable(shims / "xcrun", f'''#!{sys.executable}
import json, os, sys
with open(os.environ["TRANSOM_TEST_COMMANDS"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:] == ["--find", "swift"]:
    print(os.environ["TRANSOM_TEST_SWIFT"])
elif sys.argv[1:3] not in (["swift", "build"], ["swift", "test"]):
    sys.exit(2)
''')
        executable(shims / "python3", f'''#!{sys.executable}
import json, os, sys
if sys.argv[1:] == ["scripts/run-regression-tests.py"]:
    with open(os.environ["TRANSOM_TEST_COMMANDS"], "a") as output:
        output.write(json.dumps(["regression-runner"]) + "\\n")
else:
    os.execv(os.environ["TRANSOM_TEST_PYTHON"], [os.environ["TRANSOM_TEST_PYTHON"], *sys.argv[1:]])
''')
        run(["/bin/bash", "scripts/verify.sh"], fixture, folder / "verify.log", environment)
        actual = [json.loads(line) for line in command_log.read_text().splitlines()]
        test_command = ["swift", "test"]
        if plugins_present:
            test_command += ["-Xswiftc", "-plugin-path", "-Xswiftc", str(plugins)]
        expected = [["swift", "build", "--product", "Transom"],
                    ["swift", "build", "--product", "TransomLab"], ["--find", "swift"],
                    test_command, ["regression-runner"]]
        if actual != expected:
            raise AssertionError(f"verify.sh commands differ: {actual!r} != {expected!r}")
        records.append({"plugins_present": plugins_present, "commands": actual})
    (output / "shell-results.json").write_text(json.dumps(records, indent=2) + "\n")
    print("RESULT shell passed=2 total=2", flush=True)


def controller_source(read):
    controller = read("Sources/TransomApp/App/AppController.swift")
    runtime = read("Sources/TransomApp/App/RuntimeModels.swift")
    server = read("Sources/TransomApp/WindowServer/WindowServer.swift")
    methods = ["follow(", "worker(for ", "snapshot(for ", "valid(", "toggleMaximize(",
               "toggleVerticalMaximize(", "reserveOnBar(", "reposition(", "focusedCandidate()",
               "scan(pid:", "trackedWindowIDs()", "recordInteraction()", "transition()",
               "observeMouseInteraction()", "suspend()"]
    bodies = [declaration(controller, "private func " + marker) for marker in methods]
    bodies.append(declaration(controller, "@objc private func reserveFocused()"))
    bodies = [re.sub(r"\bNSEvent\b", "FixtureEvent", body) for body in bodies]
    storage_names = ["workers", "panels", "metadata", "enabled", "trusted", "running", "quarantineUntil",
                     "dirtyApplications", "reservePermit", "reserveTarget", "restoreFrames", "verticalRestoreFrames",
                     "extraPermits", "fastPollUntil", "lastFrontmostPID", "barHeight", "interactionUntil",
                     "localMouseMonitor", "globalMouseMonitor"]
    fields = []
    for name in storage_names:
        matches = re.findall(r"^    private var " + re.escape(name) + r"\b[^\n]*", controller, re.M)
        if len(matches) != 1:
            raise ValueError(f"Production storage not found exactly once: {name}")
        fields.append(matches[0])
    bindings = []
    for marker in ["tracker.onFrames =", "tracker.windowIDs =", "drag.onMoved ="]:
        matches = [line.strip() for line in controller.splitlines() if marker in line]
        if len(matches) != 1:
            raise ValueError(f"Production binding not found exactly once: {marker}")
        bindings.append(matches[0])
    template = (ROOT / "Tests/Regression/ControllerTests.swift.in").read_text()
    assembled = template.replace("__CONTROLLER_STORAGE__", "\n".join(fields))
    assembled = assembled.replace("__CONTROLLER_METHODS__", "\n\n".join(bodies))
    assembled = assembled.replace("__TRACKER_BINDINGS__", "\n".join(bindings))
    assembled = assembled.replace("NSRunningApplication", "FixtureApplication").replace("NSWorkspace", "FixtureWorkspace")
    shared = [runtime[:runtime.index("struct ScreenGeometry {")], declaration(server, "struct ServerWindow {"),
              declaration(server, "struct ServerSnapshot {"), "@MainActor\n" + declaration(controller, "private final class WorkerState")]
    return "import AppKit\nimport TransomCore\n" + "\n".join(shared) + "\n" + assembled


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["all", "accessibility", "controller", "menu", "gesture", "shell"], default="all")
    parser.add_argument("--output-dir", type=Path)
    arguments = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("App regression fixtures require macOS; portable tests use swift test")
    (ROOT / ".build").mkdir(exist_ok=True)
    output = arguments.output_dir.resolve() if arguments.output_dir else Path(tempfile.mkdtemp(prefix="regression-", dir=ROOT / ".build"))
    output.mkdir(parents=True, exist_ok=True)
    sources = {}

    def read(relative):
        source = (ROOT / relative).read_text()
        sources[relative] = hashlib.sha256(source.encode()).hexdigest()
        (output / "source-hashes.json").write_text(json.dumps(sources, sort_keys=True, indent=2) + "\n")
        return source

    print(f"Regression evidence: {output}", flush=True)
    selected = ["accessibility", "controller", "menu", "gesture", "shell"] if arguments.suite == "all" else [arguments.suite]
    if any(suite != "shell" for suite in selected):
        core = sorted((ROOT / "Sources/TransomCore").glob("*.swift"))
        for path in core:
            read(str(path.relative_to(ROOT)))
        run(["xcrun", "swiftc", "-swift-version", "5", "-emit-library", "-emit-module", "-module-name", "TransomCore",
             *map(str, core), "-emit-module-path", str(output / "TransomCore.swiftmodule"),
             "-o", str(output / "libTransomCore.dylib")], ROOT, output / "core-build.log")
    for suite in selected:
        if suite == "shell":
            read("scripts/verify.sh")
            shell_regression(output)
            continue
        files = []
        if suite == "accessibility":
            for relative in ["Accessibility/AXAppWorker.swift", "Accessibility/AXMenuStore.swift", "App/RuntimeModels.swift"]:
                source = read("Sources/TransomApp/" + relative)
                source = isolated_ax_source(source)
                path = output / Path(relative).name
                path.write_text(source)
                files.append(path)
            files += [ROOT / "Tests/Regression/AccessibilityFixture.swift", ROOT / "Tests/Regression/AccessibilityTests.swift"]
        elif suite == "controller":
            path = output / "Controller.swift"
            path.write_text(controller_source(read))
            tracker = output / "FrameTracker.swift"
            tracker.write_text(read("Sources/TransomApp/WindowServer/FrameTracker.swift"))
            files = [path, tracker]
        elif suite == "gesture":
            path = output / "HeaderView.swift"
            source = read("Sources/TransomApp/Header/HeaderView.swift")
            source, replacements = re.subn(r"\bNSEvent\.mouseLocation\b", "FixturePointer.location", source)
            if replacements != 2:
                raise ValueError("Expected both HeaderView and DragSurface pointer inputs")
            path.write_text(source)
            runtime = output / "RuntimeModels.swift"
            runtime.write_text(read("Sources/TransomApp/App/RuntimeModels.swift"))
            files = [path, runtime, ROOT / "Tests/Regression/GestureTests.swift"]
        else:
            path = output / "Menu.swift"
            source = read("Sources/TransomApp/Menu/MenuCoordinator.swift")
            for name in ["NSMenuItem", "NSMenu", "NSRunningApplication", "NSWorkspace"]:
                source = re.sub(r"\b" + name + r"\b", "Fixture" + name.removeprefix("NS"), source)
            path.write_text(source + "\n" + (ROOT / "Tests/Regression/MenuTests.swift").read_text())
            files = [path]
        binary = output / suite
        run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(output), "-L", str(output),
             "-lTransomCore", "-Xlinker", "-rpath", "-Xlinker", str(output),
             *map(str, files), "-o", str(binary)], ROOT, output / (suite + "-build.log"))
        result = run([str(binary)], ROOT, output / (suite + "-results.log"))
        summary = re.search(r"RESULT " + suite + r" passed=(\d+) total=(\d+)", result)
        if not summary or int(summary[1]) == 0 or summary[1] != summary[2]:
            raise AssertionError(f"Missing or failing result for {suite}: {result}")
        print(result, end="", flush=True)
    (output / "source-hashes.json").write_text(json.dumps(sources, sort_keys=True, indent=2) + "\n")
    print("Regression fixtures passed; live AX and GUI acceptance are separate.", flush=True)


if __name__ == "__main__":
    main()
