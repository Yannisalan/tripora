"""Boot the REAL backend locally (same venv, same Neon DB via backend/.env)
and hammer register with a clean/unique/policy-safe payload, then print the
REAL exception that lives in the local Flask log (the one the deployed
generic-500 handler hides).
"""
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = r"C:\Users\odjoy\tripora\backend"
PY = os.path.join(ROOT, "venv", "Scripts", "python.exe")
OUTF = os.path.join(ROOT, "local_out.log")
ERRF = os.path.join(ROOT, "local_err.log")


def port_open(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def main():
    for f in (OUTF, ERRF):
        if os.path.exists(f):
            os.remove(f)

    proc = subprocess.Popen(
        [PY, "app.py"],
        cwd=ROOT,
        stdout=open(OUTF, "wb"),
        stderr=open(ERRF, "wb"),
    )
    print("backend pid {}. waiting for boot...".format(proc.pid))

    booted = False
    for _ in range(120):
        time.sleep(0.5)
        if port_open("127.0.0.1", 5000):
            booted = True
            break
    if not booted:
        print("!! no boot. err tail:")
        with open(ERRF, "r", errors="replace") as fh:
            print("".join(fh.readlines()[-40:]))
        proc.terminate()
        sys.exit(1)
    print("booted.")

    email = "local-repro-{}-{}@neon.local".format(
        int(time.time()), random.randint(10**6, 10**7 - 1))
    payload = {
        "name": "Local Repro",
        "email": email,
        "password": "Loc4lRepro!x1",
        "preferred_language": "en",
        "preferred_currency": "USD",
    }
    req = urllib.request.Request(
        "http://127.0.0.1:5000/api/auth/register",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            print("register -> {} | {}".format(r.status, r.read().decode()))
    except urllib.error.HTTPError as e:
        print("register -> {} | {}".format(e.code, e.read().decode()))
    except Exception as e:
        print("register -> ERR: {} {}".format(type(e).__name__, e))

    time.sleep(1)
    print()
    print("=== REAL SERVER-SIDE EXCEPTION (what Render's log hides / Mobile shows as 500) ===")
    shown = 0
    with open(ERRF, "r", errors="replace") as fh:
        for line in fh:
            if re.search(
                r"Traceback|File \"| line \d+, in |raise |sqlalchemy\.exc|psycopg|"
                r"OperationalError|ProgrammingError|OperationalError|UndefinedTable|"
                r"UndefinedColumn|UndefinedFunction|UndefinedObject|relation \"|column \"|"
                r"does not exist|does not have|IntegrityError|DataError|duplicate|"
                r"psycopg2|psycopg|sqlite3|neon|connect|timeout|password|DETAIL|HINT|"
                r"could not|couldn't|database|role ",
                line,
            ):
                print(line.rstrip())
                shown += 1
                if shown >= 50:
                    break
    if shown == 0:
        print("(pattern matched nothing; dumping err tail untouched)")
        with open(ERRF, "r", errors="replace") as fh:
            print("".join(fh.readlines()[-25:]))

    proc.terminate()
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        proc.kill()
    print("backend stopped.")


if __name__ == "__main__":
    main()
