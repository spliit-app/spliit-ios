#!/usr/bin/env python3
"""Exercise the installed Android prototype against disposable, freshly seeded groups.

Run: python3 Scripts/android-smoke.py --serial emulator-5556
Requires adb, Node, the installed APK, and the e2e server on localhost:3009.
Does not clear app data or stop the shared server. Uses only Python's standard library.
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time
import threading
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
APP = "app.spliit.android.prototype"
ACTIVITY = f"{APP}/spliit.ui.MainActivity"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--lifecycle-only", action="store_true", help="Only run delayed-response cancellation checks")
    parser.add_argument("--navigation-only", action="store_true", help="Only run group, links, search, and sharing checks")
    args = parser.parse_args()
    sdk = Path(os.environ.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
    adb = shutil.which("adb") or str(sdk / "platform-tools/adb")

    def run(*command):
        return subprocess.check_output(
            [adb, "-s", args.serial, *command], text=True, timeout=40
        )

    def shell(*command):
        return run("shell", shlex.join(command))

    def dump():
        target = "/data/local/tmp/spliit-smoke.xml"
        shell("rm", "-f", target)
        result = shell("uiautomator", "dump", "--compressed", target)
        assert "dumped to:" in result, result
        return ET.fromstring(shell("cat", target))

    def find(selector, scroll=False, timeout=12):
        deadline = time.monotonic() + timeout
        for _ in range(8 if scroll else 20):
            root = dump()
            for node in root.iter("node"):
                if selector in (node.get("resource-id"), node.get("text"), node.get("content-desc")):
                    if node.get("enabled") == "true":
                        return node
            if time.monotonic() >= deadline:
                break
            if scroll:
                bounds = list(map(int, re.findall(r"\d+", next(root.iter("node")).get("bounds"))))
                width, height = bounds[2:]
                shell("input", "swipe", str(width // 2), str(height * 3 // 4),
                      str(width // 2), str(height // 3), "250")
        visible = [n.get("text") or n.get("resource-id") for n in root.iter("node")]
        raise AssertionError(f"Missing {selector!r}: {list(filter(None, visible))}")

    def tap(selector, scroll=False):
        node = find(selector, scroll)
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        shell("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))

    def enter(selector, value, scroll=False):
        tap(selector, scroll)
        shell("input", "keycombination", "113", "29")  # Ctrl+A
        shell("input", "keyevent", "67")  # Delete the selection.
        shell("input", "text", value.replace(" ", "%s"))
        shell("input", "keyevent", "4")  # Dismiss the keyboard.

    def swipe_delete(title):
        node = find(title)
        _, y1, _, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        root = dump()
        width = int(re.findall(r"\d+", next(root.iter("node")).get("bounds"))[2])
        shell("input", "swipe", str(width * 9 // 10), str((y1 + y2) // 2),
              str(width // 4), str((y1 + y2) // 2), "350")

    def query(procedure, data):
        encoded = urllib.parse.urlencode({"input": json.dumps({"json": data})})
        with urllib.request.urlopen(f"http://localhost:3009/api/trpc/{procedure}?{encoded}", timeout=20) as response:
            return json.load(response)["result"]["data"]["json"]

    def expenses():
        return query("groups.expenses.list", {"groupId": group_id, "limit": 50})["expenses"]

    def details(title):
        expense = next(e for e in expenses() if e["title"] == title)
        return query("groups.expenses.get", {"groupId": group_id, "expenseId": expense["id"]})["expense"]

    def seed():
        return json.loads(subprocess.check_output(
            ["node", str(ROOT / "e2e/seed.mjs")], text=True, timeout=90
        ))

    # Read the original locale before changing it; restore it even on a failed assertion.
    locales = shell("cmd", "locale", "get-app-locales", APP, "--user", "0")
    original_locale = re.search(r"\[(.*?)\]", locales).group(1)
    seeded = seed()
    group = seeded["groups"]["empty"]
    group_id = group["id"]
    fen, gil = (group["participants"][name] for name in ("Fen", "Gil"))
    print(f"Testing isolated Book club group {group_id}", flush=True)
    try:
        shell("cmd", "locale", "set-app-locales", APP, "--user", "0", "--locales", "en-US")
        shell("am", "start", "-W", "-S", "-n", ACTIVITY)
        if not args.lifecycle_only and not args.navigation_only:
            tap("plus")
            tap("groups.addByURL")
            enter("addByURL.field", f"http://10.0.2.2:3009/groups/{group_id}")
            tap("addByURL.add")
            tap(f"groups.row.{group_id}.title")
            find("expenses.emptyAdd")

            for mode, values, shares in [
                ("EVENLY", None, (100, 100)),
                ("BY_SHARES", ("1", "3"), (100, 300)),
                ("BY_PERCENTAGE", ("25", "75"), (2500, 7500)),
                ("BY_AMOUNT", ("20", "80"), (2000, 8000)),
            ]:
                title = f"Smoke {mode}"
                tap("expenses.add")
                enter("expenseForm.title", title)
                enter("expenseForm.amount", "100.00")
                tap(f"expenseForm.split.{mode}")
                if values:
                    enter(f"expenseForm.share.{fen}", values[0], scroll=True)
                    enter(f"expenseForm.share.{gil}", values[1], scroll=True)
                tap("expenseForm.save")
                find(title)
                saved = details(title)
                assert saved["amount"] == 10000 and saved["splitMode"] == mode, saved
                assert {p["participantId"]: p["shares"] for p in saved["paidFor"]} == dict(zip((fen, gil), shares)), saved
                print(f"PASS {mode}: UI save and server shares", flush=True)

            tap("Balances")
            assert find(f"balances.row.{fen}.amount").get("text") == "£280.00"
            assert find(f"balances.row.{gil}.amount").get("text") == "-£280.00"
            tap("Expenses")
            tap("Smoke EVENLY")
            enter("expenseForm.title", "Smoke edited")
            enter("expenseForm.amount", "120.00")
            tap("expenseForm.save")
            find("Smoke edited")
            assert details("Smoke edited")["amount"] == 12000
            print("PASS edit: persisted title and amount", flush=True)

            swipe_delete("Smoke BY_AMOUNT")
            tap("expenses.undoDelete")
            find("Smoke BY_AMOUNT")
            assert len(expenses()) == 4
            print("PASS delete undo", flush=True)
            tap("Smoke BY_AMOUNT")
            tap("expenseForm.delete", scroll=True)
            for _ in range(10):
                if len(expenses()) == 3:
                    break
                time.sleep(1)
            assert len(expenses()) == 3
            print("PASS committed delete", flush=True)

            shell("am", "start", "-W", "-S", "-n", ACTIVITY)
            tap(f"groups.row.{group_id}.title")
            find("Smoke edited")
            tap("Balances")
            assert find(f"balances.row.{fen}.amount").get("text") == "£210.00"
            assert find(f"balances.row.{gil}.amount").get("text") == "-£210.00"
            print("PASS restart persistence and final balances", flush=True)
        if not args.lifecycle_only:
            shell("am", "start", "-W", "-S", "-n", ACTIVITY)
            tap("plus")
            tap("groups.create")
            name = f"Android smoke {int(time.time())}"
            enter("groupForm.name", name)
            tap("groupForm.serverPicker")
            tap("10.0.2.2:3009")
            tap("groupForm.save")
            find(name)
            find("expenses.emptyAdd")
            tap("group.menu")
            tap("group.edit")
            enter("groupForm.name", name + " edited")
            tap("groupForm.save")
            find(name + " edited")
            print("PASS create and edit group on the selected local instance", flush=True)

            for index, key in enumerate(("lisbon", "flat", "flat")):
                linked = seeded["groups"][key]
                command = ["am", "start", "-W"] + (["-S"] if index == 0 else [])
                shell(*command, "-a", "android.intent.action.VIEW", "-d",
                      f"app.spliit.spliitmobile://groups/{linked['id']}", APP)
                find("Weekend in Lisbon" if key == "lisbon" else "Flat 3B")
                find("expenses.add")
            print("PASS cold, warm, and repeated custom-scheme links", flush=True)
            tap("Totals")
            find("stats.groupTotal")
            tap("Information")
            find("information.server")
            tap("information.activity")
            find("Activity")
            shell("input", "keyevent", "4")
            group_id = seeded["groups"]["flat"]["id"]
            internet = details("Internet")
            tap("Search")
            enter("search.field", "Internet")
            assert find(f"expenses.row.{internet['id']}.title").get("text") == "Internet"
            tap("search.cancel")
            tap("group.menu")
            tap("group.share")
            find(f"http://10.0.2.2:3009/groups/{seeded['groups']['flat']['id']}")
            shell("input", "keyevent", "4")
            print("PASS totals, activity, search, and instance-specific Android sharing", flush=True)
            tap("Expenses")
            tap("expenses.add")
            enter("expenseForm.title", "Converted smoke")
            rotation = shell("settings", "get", "system", "user_rotation").strip()
            automatic = shell("settings", "get", "system", "accelerometer_rotation").strip()
            try:
                shell("settings", "put", "system", "accelerometer_rotation", "0")
                shell("settings", "put", "system", "user_rotation", "1")
                assert find("expenseForm.title").get("text") == "Converted smoke"
                bounds = list(map(int, re.findall(r"\d+", next(dump().iter("node")).get("bounds"))))
                assert bounds[2] > bounds[3], f"Rotation did not reach landscape: {bounds}"
            finally:
                shell("settings", "put", "system", "user_rotation", rotation)
                shell("settings", "put", "system", "accelerometer_rotation", automatic)
            print("PASS rotation preserves the expense draft", flush=True)
            tap("expenseForm.currency", scroll=True)
            tap("currencyPicker.row.GBP")
            enter("expenseForm.originalAmount", "5", scroll=True)
            enter("expenseForm.conversionRate", "1.25", scroll=True)
            tap("expenseForm.save")
            find("Converted smoke")
            group_id = seeded["groups"]["flat"]["id"]
            converted = details("Converted smoke")
            assert converted["amount"] == 625 and converted["originalAmount"] == 500, converted
            assert converted["originalCurrency"] == "GBP", converted
            assert float(converted["conversionRate"]) == 1.25, converted
            print("PASS manual currency conversion and persisted minor units", flush=True)
            tap("Balances")
            tap("activeUser.balances")
            dana = seeded["groups"]["flat"]["participants"]["Dana"]
            tap(f"activeUser.option.{dana}")
            find(f"activeUser.badge.{dana}")
            tap("balances.markAsPaid.0", scroll=True)
            tap("expenseForm.save")
            find("balances.settled")
            reimbursement = details("Reimbursement")
            assert reimbursement["isReimbursement"], reimbursement
            print("PASS participant picker and settlement", flush=True)
            if args.navigation_only:
                return

        # Delay actual server responses, not synthetic fixtures, to exercise cancellation.
        group_started, group_finished, stats_started = (threading.Event() for _ in range(3))
        delay_group = True
        stats_requests = 0

        class Proxy(BaseHTTPRequestHandler):
            def do_GET(self):
                nonlocal stats_requests
                is_group = self.path.startswith("/api/trpc/groups.get?") and delay_group
                try:
                    if is_group:
                        group_started.set()
                        time.sleep(5)
                    if self.path.startswith("/api/trpc/groups.stats."):
                        stats_requests += 1
                        if stats_requests == 1:
                            stats_started.set()
                            time.sleep(8)
                    try:
                        response = urllib.request.urlopen("http://localhost:3009" + self.path, timeout=20)
                    except urllib.error.HTTPError as error:
                        response = error
                    with response:
                        data = response.read()
                        self.send_response(response.status)
                        self.send_header("Content-Type", "application/json")
                        self.send_header("Content-Length", str(len(data)))
                        self.end_headers()
                        self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # Expected when the client cancels the deliberately delayed request.
                finally:
                    if is_group:
                        group_finished.set()

            def log_message(self, *_):
                pass

        proxy = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        try:
            # This group must not already be remembered by the navigation checks.
            other = (seeded if args.lifecycle_only else seed())["groups"]["flat"]
            proxy_link = f"http://10.0.2.2:{proxy.server_port}/groups/{other['id']}"
            shell("am", "start", "-W", "-S", "-n", ACTIVITY)
            tap("plus")
            tap("groups.addByURL")
            enter("addByURL.field", proxy_link)
            tap("addByURL.add")
            assert group_started.wait(5), "The delayed group lookup never started"
            shell("input", "keyevent", "4")  # Android Back cancels adding the group.
            assert group_finished.wait(10), "The delayed group response never finished"
            assert not any(n.get("resource-id") == f"groups.row.{other['id']}.title"
                           for n in dump().iter("node")), "Canceled lookup still added the group"
            print("PASS Android Back cancels add-by-link", flush=True)

            delay_group = False
            tap("plus")
            tap("groups.addByURL")
            enter("addByURL.field", proxy_link)
            tap("addByURL.add")
            tap(f"groups.row.{other['id']}.title")
            # Cache the unchanged tab bar's observed bounds so returning really is immediate.
            tab_points = {}
            for tab in ("Totals", "Expenses"):
                x1, y1, x2, y2 = map(int, re.findall(r"\d+", find(tab).get("bounds")))
                tab_points[tab] = (str((x1 + x2) // 2), str((y1 + y2) // 2))
            shell("input", "tap", *tab_points["Totals"])
            assert stats_started.wait(5), "The delayed totals request never started"
            shell("input", "tap", *tab_points["Expenses"])
            find("expenses.add")
            shell("input", "tap", *tab_points["Totals"])
            find("stats.groupTotal", timeout=25)
            print(f"PASS Totals loads after leaving during a delayed response ({stats_requests} requests)", flush=True)
        finally:
            proxy.shutdown()
            proxy.server_close()
    finally:
        shell("cmd", "locale", "set-app-locales", APP, "--user", "0", "--locales", original_locale)


if __name__ == "__main__":
    main()
