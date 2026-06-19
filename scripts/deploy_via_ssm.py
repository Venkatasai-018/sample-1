"""
Send a deploy script to an EC2 instance via AWS SSM, then poll until done.

Reads the local shell script, injects required env-var exports at the top,
runs it on the instance, streams status, and exits non-zero on failure.

Required environment variables:
  EC2_INSTANCE_ID, AWS_REGION, SCRIPT_PATH,
  GH_TOKEN, REPO, RUN_ID, ART_NAME,
  APP_PORT, HEALTH_PATH,
  ENVIRONMENT, BUILD_ID
"""
from __future__ import annotations

import os
import shlex
import sys
import time

import boto3
from botocore.exceptions import ClientError

REQUIRED = [
    "EC2_INSTANCE_ID", "AWS_REGION", "SCRIPT_PATH",
    "GH_TOKEN", "REPO", "RUN_ID", "ART_NAME",
    "APP_PORT", "HEALTH_PATH", "ENVIRONMENT", "BUILD_ID",
]
INJECT = [
    "GH_TOKEN", "REPO", "RUN_ID", "ART_NAME",
    "APP_PORT", "HEALTH_PATH", "ENVIRONMENT", "BUILD_ID",
]
POLL_INTERVAL = 5
POLL_TIMEOUT = 15 * 60  # 15 minutes


def require_env() -> dict[str, str]:
    missing = [k for k in REQUIRED if not os.environ.get(k)]
    if missing:
        sys.exit(f"ERROR: missing required env vars: {', '.join(missing)}")
    return {k: os.environ[k] for k in REQUIRED}


def build_command(env: dict[str, str]) -> list[str]:
    with open(env["SCRIPT_PATH"], "r", encoding="utf-8") as f:
        script_body = f.read()

    exports = "\n".join(
        f"export {k}={shlex.quote(env[k])}" for k in INJECT
    )
    full_script = f"{exports}\n{script_body}"
    return [full_script]


def send_command(ssm, env: dict[str, str], commands: list[str]) -> str:
    resp = ssm.send_command(
        InstanceIds=[env["EC2_INSTANCE_ID"]],
        DocumentName="AWS-RunShellScript",
        Comment=f"Landing page deploy {env['BUILD_ID']}",
        Parameters={"commands": commands},
    )
    cmd_id = resp["Command"]["CommandId"]
    print(f"SSM Command ID: {cmd_id}")
    return cmd_id


def wait_for_completion(ssm, command_id: str, instance_id: str) -> dict:
    deadline = time.time() + POLL_TIMEOUT
    while True:
        if time.time() > deadline:
            sys.exit(f"ERROR: SSM command {command_id} timed out after {POLL_TIMEOUT}s")
        try:
            inv = ssm.get_command_invocation(
                CommandId=command_id, InstanceId=instance_id
            )
        except ClientError as e:
            if e.response["Error"]["Code"] == "InvocationDoesNotExist":
                time.sleep(POLL_INTERVAL)
                continue
            raise
        status = inv["Status"]
        print(f"  status: {status}")
        if status in ("Success", "Failed", "Cancelled", "TimedOut"):
            return inv
        time.sleep(POLL_INTERVAL)


def print_output(inv: dict) -> None:
    print("\n===== STDOUT =====")
    print(inv.get("StandardOutputContent", "").rstrip())
    err = inv.get("StandardErrorContent", "").rstrip()
    if err:
        print("\n===== STDERR =====")
        print(err)
    print(f"\nFinal status: {inv['Status']}")


def main() -> int:
    env = require_env()
    ssm = boto3.client("ssm", region_name=env["AWS_REGION"])
    commands = build_command(env)
    command_id = send_command(ssm, env, commands)
    print(f"Polling for completion (timeout {POLL_TIMEOUT}s)...")
    inv = wait_for_completion(ssm, command_id, env["EC2_INSTANCE_ID"])
    print_output(inv)
    return 0 if inv["Status"] == "Success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
