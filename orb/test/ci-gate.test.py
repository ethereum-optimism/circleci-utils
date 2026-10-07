#!/usr/bin/env python3
"""Run the real ci-gate shell command against scripted API responses, without sleeps."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(os.environ.get(
    "CI_GATE_SOURCE",
    Path(__file__).resolve().parents[1] / "src/commands/ci-gate.yml",
))
WORKFLOW_URL = "https://circleci.com/api/v2/workflow/workflow-id/job"


def page(*statuses, next_token=None):
    return {
        "items": [
            {"id": "gate", "name": "required-rust-e2e",
             "dependencies": [f"dep-{i}" for i in range(len(statuses))]},
            *({"id": f"dep-{i}", "name": f"test-{i}", "status": status}
              for i, status in enumerate(statuses)),
        ],
        "next_page_token": next_token,
    }


class GateTest(unittest.TestCase):
    def run_gate(self, responses, *, skip=False, token="test-token", job="required-rust-e2e"):
        with tempfile.TemporaryDirectory(prefix="ci-gate-test-") as tmp:
            root = Path(tmp)
            script = SOURCE.read_text().split("      command: |\n", 1)[1]
            script = "\n".join(line.removeprefix("        ") for line in script.splitlines())
            script = script.replace("<< parameters.always-succeed >>", str(skip).lower())
            script = script.replace("<< parameters.circleci-api-token >>", "TEST_API_TOKEN")
            (root / "gate.sh").write_text(script)
            (root / "responses.json").write_text(json.dumps(responses))
            curl = root / "curl"
            curl.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
counter = root / "requests.json"
requests = json.loads(counter.read_text()) if counter.exists() else []
responses = json.loads((root / "responses.json").read_text())
index = len(requests)
requests.append(sys.argv[1:])
counter.write_text(json.dumps(requests))
if not responses:
    sys.exit(99)
response = responses[min(index, len(responses) - 1)]
if isinstance(response, int):
    sys.exit(response)
print(json.dumps(response))
''')
            curl.chmod(0o755)
            sleep = root / "sleep"
            sleep.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_ROOT/sleeps"\n')
            sleep.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", TEST_ROOT=tmp,
                       TEST_API_TOKEN=token, CIRCLE_JOB=job, CIRCLE_WORKFLOW_ID="workflow-id")
            result = subprocess.run(["bash", "-eo", "pipefail", str(root / "gate.sh")],
                                    env=env, text=True, capture_output=True, timeout=60)
            requests = json.loads((root / "requests.json").read_text()) if (root / "requests.json").exists() else []
            sleeps = (root / "sleeps").read_text().splitlines() if (root / "sleeps").exists() else []
            return result, requests, sleeps

    def test_success_without_delay(self):
        result, requests, sleeps = self.run_gate([page("success", "success")])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(requests), 1)
        self.assertEqual(sleeps, [])

    def test_statuses_settle_after_old_retry_window(self):
        # Replay the incident's stale running dependencies for longer than 55s.
        stale = page("success", "running", "running")
        result, requests, sleeps = self.run_gate([stale] * 24 + [page("success", "success", "success")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(requests), 25)
        self.assertEqual(sleeps, ["5"] * 24)
        self.assertIn("Waiting for test-1 (dep-1): running", result.stdout)
        self.assertIn("All required jobs passed.", result.stdout)

    def test_all_nonterminal_states_retry(self):
        for status in ("running", "queued", "not_run", "not_running", "blocked", "on_hold"):
            with self.subTest(status=status):
                result, _, sleeps = self.run_gate([page(status), page("success")])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(sleeps, ["5"])

    def test_terminal_failures_do_not_retry_even_with_stale_sibling(self):
        for status in ("failed", "canceled", "unauthorized", "timedout", "unknown"):
            with self.subTest(status=status):
                result, requests, sleeps = self.run_gate([page("running", status)])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(requests), 1)
                self.assertEqual(sleeps, [])
                self.assertIn(f"FAIL test-1: {status}", result.stdout)

    def test_failure_after_retry_stops_immediately(self):
        result, requests, sleeps = self.run_gate([page("running"), page("failed")])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(requests), 2)
        self.assertEqual(sleeps, ["5"])

    def test_retry_budget_exhaustion_fails_closed(self):
        result, requests, sleeps = self.run_gate([page("running")])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(requests), 60)
        self.assertEqual(sleeps, ["5"] * 59)
        self.assertIn("FAIL test-0: running", result.stdout)

    def test_paginated_dependencies_are_refetched(self):
        first = page("success", next_token="next-page")
        dependency = first["items"].pop()
        stale = dict(dependency, status="running")
        result, requests, sleeps = self.run_gate([
            first, {"items": [stale]}, first, {"items": [dependency]},
        ])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([args[-1] for args in requests],
                         [WORKFLOW_URL, WORKFLOW_URL + "?page-token=next-page"] * 2)
        self.assertEqual(sleeps, ["5"])

    def test_missing_gate_or_dependency_fails_closed(self):
        missing_dependency = page("success")
        missing_dependency["items"].pop()
        for response in (page(), {"items": []}, missing_dependency):
            with self.subTest(response=response):
                result, _, sleeps = self.run_gate([response])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(sleeps, [])

    def test_missing_configuration_fails_before_api_call(self):
        for kwargs in ({"token": ""}, {"job": ""}):
            with self.subTest(kwargs=kwargs):
                result, requests, sleeps = self.run_gate([], **kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(requests, [])
                self.assertEqual(sleeps, [])

    def test_always_succeed_needs_no_credentials_or_api(self):
        result, requests, sleeps = self.run_gate([], skip=True, token="", job="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests, [])
        self.assertEqual(sleeps, [])


if __name__ == "__main__":
    unittest.main()
