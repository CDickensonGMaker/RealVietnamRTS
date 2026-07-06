#!/usr/bin/env python3
"""
Autonomous Test Harness for RealVietnamRTS
Drives the TestDaemon via file-based commands for overnight testing.

Usage:
    python autonomous_test.py [--scenario clearing|building|full]

The game must be running with clearing_test.tscn loaded.
"""

import json
import time
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional

# Godot user:// directory location on Windows
GODOT_USER_DIR = Path(os.path.expandvars(r"%APPDATA%\Godot\app_userdata\RealVietnamRTS"))
DAEMON_DIR = GODOT_USER_DIR / "test_daemon"
COMMANDS_FILE = DAEMON_DIR / "commands.jsonl"
RESULTS_FILE = DAEMON_DIR / "results.jsonl"
HEALTH_FILE = DAEMON_DIR / "health.json"
STATE_FILE = DAEMON_DIR / "state_snapshot.json"

# Test output
OUTPUT_DIR = Path(__file__).parent / "test_results"
LOG_FILE = OUTPUT_DIR / f"test_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"


class TestHarness:
    def __init__(self):
        self.command_id = 0
        self.results: Dict[int, Dict] = {}
        self.log_lines: List[str] = []
        OUTPUT_DIR.mkdir(exist_ok=True)

    def log(self, message: str):
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {message}"
        print(line)
        self.log_lines.append(line)

    def save_log(self):
        with open(LOG_FILE, "w") as f:
            f.write("\n".join(self.log_lines))
        self.log(f"Log saved to {LOG_FILE}")

    def send_command(self, cmd: str, args: Dict = None) -> int:
        """Send a command to the daemon and return the command ID."""
        self.command_id += 1
        command = {
            "id": self.command_id,
            "cmd": cmd,
            "args": args or {}
        }

        with open(COMMANDS_FILE, "a") as f:
            f.write(json.dumps(command) + "\n")

        self.log(f"CMD {self.command_id}: {cmd} {args or ''}")
        return self.command_id

    def wait_for_result(self, cmd_id: int, timeout: float = 30.0) -> Optional[Dict]:
        """Wait for a specific command result."""
        start = time.time()

        while time.time() - start < timeout:
            if RESULTS_FILE.exists():
                with open(RESULTS_FILE, "r") as f:
                    for line in f:
                        try:
                            result = json.loads(line.strip())
                            if result.get("id") == cmd_id:
                                self.results[cmd_id] = result
                                return result
                        except json.JSONDecodeError:
                            continue
            time.sleep(0.5)

        self.log(f"TIMEOUT waiting for command {cmd_id}")
        return None

    def send_and_wait(self, cmd: str, args: Dict = None, timeout: float = 30.0) -> Optional[Dict]:
        """Send command and wait for result."""
        cmd_id = self.send_command(cmd, args)
        result = self.wait_for_result(cmd_id, timeout)
        if result:
            status = result.get("status", "unknown")
            data = result.get("data", {})
            if status == "ok":
                self.log(f"  -> OK: {data}")
            else:
                self.log(f"  -> ERROR: {data}")
        return result

    def check_health(self) -> Dict:
        """Read current health status."""
        if HEALTH_FILE.exists():
            with open(HEALTH_FILE, "r") as f:
                return json.load(f)
        return {}

    def wait_seconds(self, seconds: float):
        """Wait with health monitoring."""
        self.log(f"Waiting {seconds}s...")
        start = time.time()
        while time.time() - start < seconds:
            health = self.check_health()
            if health.get("frozen", False):
                self.log("WARNING: Game appears frozen!")
            time.sleep(1.0)

    def clear_daemon_files(self):
        """Clear old command/result files for fresh test."""
        for f in [COMMANDS_FILE, RESULTS_FILE]:
            if f.exists():
                f.unlink()
        self.log("Cleared daemon files")


class ClearingLoopTest:
    """Test scenario: Clearing terrain and verifying workers complete jobs."""

    def __init__(self, harness: TestHarness):
        self.harness = harness

    def run(self) -> bool:
        h = self.harness
        h.log("=" * 60)
        h.log("SCENARIO: Clearing Loop Test")
        h.log("=" * 60)

        # Ping daemon
        result = h.send_and_wait("ping")
        if not result or result.get("status") != "ok":
            h.log("FAIL: Daemon not responding")
            return False

        # Get initial state
        h.send_and_wait("get_state")

        # Check for workers
        result = h.send_and_wait("get_workers")
        workers = result.get("data", {}).get("workers", []) if result else []
        h.log(f"Found {len(workers)} workers")

        if len(workers) == 0:
            h.log("Spawning engineers and bulldozers...")
            for i in range(4):
                h.send_and_wait("spawn_engineer", {"position": [20 + i*5, 0, 20]})
            for i in range(2):
                h.send_and_wait("spawn_bulldozer", {"position": [40 + i*8, 0, 20]})
            h.wait_seconds(2)

        # Create a clearing job
        h.log("Creating clearing job at center of map...")
        result = h.send_and_wait("paint_clearing", {
            "center": [100, 0, 100],
            "radius": 20.0
        })

        if not result or result.get("status") != "ok":
            h.log("FAIL: Could not create clearing job")
            return False

        job_id = result.get("data", {}).get("job_created", "")
        h.log(f"Created job: {job_id}")

        # Monitor job progress
        h.log("Monitoring job progress...")
        max_wait = 120  # 2 minutes max
        start = time.time()
        last_progress = 0.0
        stall_count = 0

        while time.time() - start < max_wait:
            # Check jobs
            result = h.send_and_wait("get_jobs")
            jobs = result.get("data", {}).get("jobs", []) if result else []

            active_jobs = [j for j in jobs if j.get("state_name") in ["IN_PROGRESS", "READY"]]
            h.log(f"  Active jobs: {len(active_jobs)}")

            for job in active_jobs:
                progress = job.get("progress", 0)
                workers = job.get("workers_assigned", 0)
                h.log(f"    Job {job.get('id')}: {progress:.1%} progress, {workers} workers")

                if progress > last_progress:
                    last_progress = progress
                    stall_count = 0
                else:
                    stall_count += 1

            # Check for anomalies
            result = h.send_and_wait("get_job_anomalies")
            anomalies = result.get("data", {}).get("anomalies", []) if result else []
            if anomalies:
                h.log(f"  ANOMALIES DETECTED: {len(anomalies)}")
                for a in anomalies:
                    h.log(f"    {a.get('type_name')}: {a.get('issues')}")

            # Check if complete
            completed_jobs = [j for j in jobs if j.get("state_name") == "COMPLETE"]
            if completed_jobs:
                h.log("SUCCESS: Job completed!")
                h.send_and_wait("screenshot", {"filename": "clearing_complete.png"})
                return True

            # Check for stall
            if stall_count > 5:
                h.log("WARNING: Progress stalled for 5 cycles")
                result = h.send_and_wait("validate_job_workers")
                h.log(f"  Worker validation: {result.get('data', {})}")

            h.wait_seconds(5)

        h.log("FAIL: Job did not complete in time")
        return False


class BuildingLoopTest:
    """Test scenario: Clear terrain then build a structure."""

    def __init__(self, harness: TestHarness):
        self.harness = harness

    def run(self) -> bool:
        h = self.harness
        h.log("=" * 60)
        h.log("SCENARIO: Building Loop Test")
        h.log("=" * 60)

        # First run clearing
        clearing = ClearingLoopTest(h)
        if not clearing.run():
            h.log("FAIL: Clearing prerequisite failed")
            return False

        # Now place a building
        h.log("Placing bunker on cleared terrain...")
        result = h.send_and_wait("place_building", {
            "type": "bunker",
            "position": [100, 0, 100],
            "rotation": 0.0
        })

        if not result or result.get("status") != "ok":
            h.log(f"FAIL: Could not place building: {result}")
            return False

        job_id = result.get("data", {}).get("job_created", "")
        h.log(f"Created build job: {job_id}")

        # Monitor until complete
        h.log("Monitoring build progress...")
        max_wait = 180  # 3 minutes
        start = time.time()

        while time.time() - start < max_wait:
            result = h.send_and_wait("get_jobs")
            jobs = result.get("data", {}).get("jobs", []) if result else []

            build_jobs = [j for j in jobs if j.get("type_name") == "BUILD_STRUCTURE"]
            for job in build_jobs:
                progress = job.get("progress", 0)
                stage = job.get("current_stage", "")
                workers = job.get("workers_assigned", 0)
                h.log(f"  Build: {progress:.1%} - Stage: {stage} - Workers: {workers}")

                if job.get("state_name") == "COMPLETE":
                    h.log("SUCCESS: Building completed!")
                    h.send_and_wait("screenshot", {"filename": "building_complete.png"})
                    return True

            h.wait_seconds(5)

        h.log("FAIL: Building did not complete in time")
        return False


class FullLoopTest:
    """Test scenario: Full clearing -> building -> verify loop."""

    def __init__(self, harness: TestHarness):
        self.harness = harness

    def run(self) -> bool:
        h = self.harness
        h.log("=" * 60)
        h.log("SCENARIO: Full Clearing -> Building Loop")
        h.log("=" * 60)

        results = {
            "clearing": False,
            "building": False,
            "anomalies_detected": [],
            "screenshots": []
        }

        # Take initial screenshot
        h.send_and_wait("screenshot", {"filename": "test_start.png"})
        results["screenshots"].append("test_start.png")

        # Run building test (includes clearing)
        building = BuildingLoopTest(h)
        if building.run():
            results["building"] = True
            results["clearing"] = True

        # Final health check
        health = h.check_health()
        h.log(f"Final health: FPS={health.get('fps_avg', 0):.1f}, Memory={health.get('memory_mb', 0):.1f}MB")

        # Get final anomalies
        result = h.send_and_wait("get_job_anomalies")
        anomalies = result.get("data", {}).get("anomalies", []) if result else []
        results["anomalies_detected"] = anomalies

        # Take final screenshot
        h.send_and_wait("screenshot", {"filename": "test_end.png"})
        results["screenshots"].append("test_end.png")

        # Summary
        h.log("=" * 60)
        h.log("TEST SUMMARY")
        h.log("=" * 60)
        h.log(f"Clearing: {'PASS' if results['clearing'] else 'FAIL'}")
        h.log(f"Building: {'PASS' if results['building'] else 'FAIL'}")
        h.log(f"Anomalies: {len(results['anomalies_detected'])}")

        return results["clearing"] and results["building"]


def main():
    parser = argparse.ArgumentParser(description="Autonomous Test Harness for RealVietnamRTS")
    parser.add_argument("--scenario", choices=["clearing", "building", "full"], default="full",
                        help="Test scenario to run")
    parser.add_argument("--clear", action="store_true", help="Clear daemon files before starting")
    args = parser.parse_args()

    # Ensure daemon directory exists
    if not DAEMON_DIR.exists():
        print(f"ERROR: Daemon directory not found at {DAEMON_DIR}")
        print("Make sure the game is running with TestDaemon autoload.")
        sys.exit(1)

    harness = TestHarness()

    if args.clear:
        harness.clear_daemon_files()

    harness.log(f"Starting autonomous test: {args.scenario}")
    harness.log(f"Daemon dir: {DAEMON_DIR}")

    try:
        if args.scenario == "clearing":
            success = ClearingLoopTest(harness).run()
        elif args.scenario == "building":
            success = BuildingLoopTest(harness).run()
        else:
            success = FullLoopTest(harness).run()

        harness.log("=" * 60)
        harness.log(f"FINAL RESULT: {'PASS' if success else 'FAIL'}")
        harness.log("=" * 60)

    except KeyboardInterrupt:
        harness.log("Test interrupted by user")
    except Exception as e:
        harness.log(f"ERROR: {e}")
        import traceback
        harness.log(traceback.format_exc())
    finally:
        harness.save_log()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
