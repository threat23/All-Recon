#!/usr/bin/env python3
"""
ALL-RECON GUI
Graphical front-end for the ALL-RECON pentesting automation suite.

Place this file in the project root (same folder as all_recon.sh) and run:
    python3 gui.py

Requires: python3-tk
    sudo apt install python3-tk

Note: raw SYN scans and OS detection (nmap -sS -O) need root privileges.
Tick "Run with sudo" on the Host Scan tab, or launch the whole GUI with
sudo (not recommended for everyday use — prefer the per-scan checkbox).

This GUI does not reimplement your scanning logic. It is a thin front-end
that calls your existing, already-tested modules/*.sh scripts as
subprocesses and streams their output live. Keep your authorization /
scope-of-engagement checks in the shell scripts themselves — the GUI
does not add or remove any safety logic.
"""

import os
import re
import time
import queue
import threading
import subprocess
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
MODULES_DIR = os.path.join(PROJECT_ROOT, "modules")

BG = "#0b0f14"
FG = "#39ff14"
PANEL_BG = "#10161d"
ACCENT = "#1f6feb"


def module_path(name):
    return os.path.join(MODULES_DIR, name)


def require_modules_dir():
    if not os.path.isdir(MODULES_DIR):
        messagebox.showerror(
            "modules/ not found",
            f"Expected a 'modules' directory next to this file:\n{MODULES_DIR}\n\n"
            "Put gui.py in the same folder as all_recon.sh before running it.",
        )


# ──────────────────────────────────────────────────────────────────
# Reusable output + process-runner panel
# ──────────────────────────────────────────────────────────────────
class OutputPanel(ttk.Frame):
    """Scrolling log area with a background subprocess runner.

    Supports two modes:
      .run(cmd)       — one subprocess, for simple one-shot tab actions.
      .run_job(fn)     — fn(panel) runs in a worker thread and can call
                         panel._run_single(cmd, save_to=...) any number of
                         times in sequence (e.g. ping-sweep, then scan each
                         live host). fn should check panel.stop_event
                         between steps so Stop can cancel a multi-step job,
                         not just the current subprocess.
    """

    def __init__(self, parent):
        super().__init__(parent)
        self.process = None
        self.busy = False
        self.stop_event = threading.Event()
        self.msg_queue = queue.Queue()
        self.log = scrolledtext.ScrolledText(
            self, height=20, bg=BG, fg=FG, insertbackground=FG,
            font=("Consolas", 10), wrap="word",
        )
        self.log.pack(fill="both", expand=True, padx=8, pady=(4, 8))
        self.log.configure(state="disabled")

    def write(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text)
        self.log.see("end")
        self.log.configure(state="disabled")

    def clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def _run_single(self, cmd, save_to=None):
        """Run one subprocess to completion, streaming output to the queue
        (and optionally to a file). Must be called from a worker thread.
        Returns the exit code, or None if skipped because stop was requested."""
        if self.stop_event.is_set():
            return None
        self.msg_queue.put(f"\n$ {' '.join(cmd)}\n")
        self.process = subprocess.Popen(
            cmd, cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        fh = open(save_to, "w", encoding="utf-8") if save_to else None
        try:
            for line in self.process.stdout:
                self.msg_queue.put(line)
                if fh:
                    fh.write(line)
                if self.stop_event.is_set():
                    self.process.terminate()
                    break
        finally:
            if fh:
                fh.close()
        self.process.wait()
        return self.process.returncode

    def run(self, cmd):
        """One-shot single command."""
        if self.busy:
            messagebox.showwarning("Busy", "A scan is already running in this tab.\n"
                                            "Stop it first, or wait for it to finish.")
            return
        self.clear()
        self.stop_event.clear()
        self.busy = True

        def worker():
            try:
                rc = self._run_single(cmd)
                if rc is not None:
                    self.msg_queue.put(f"\n[process exited with code {rc}]\n")
            except FileNotFoundError as e:
                self.msg_queue.put(f"\n[error] {e}\n")
            except Exception as e:  # noqa: BLE001
                self.msg_queue.put(f"\n[unexpected error] {e}\n")
            finally:
                self.busy = False

        threading.Thread(target=worker, daemon=True).start()
        self.after(100, self._poll)

    def run_job(self, job_fn):
        """Multi-step job: job_fn(panel) drives one or more _run_single() calls."""
        if self.busy:
            messagebox.showwarning("Busy", "A scan is already running in this tab.\n"
                                            "Stop it first, or wait for it to finish.")
            return
        self.clear()
        self.stop_event.clear()
        self.busy = True

        def worker():
            try:
                job_fn(self)
            except Exception as e:  # noqa: BLE001
                self.msg_queue.put(f"\n[unexpected error] {e}\n")
            finally:
                self.msg_queue.put("\n[job finished]\n")
                self.busy = False

        threading.Thread(target=worker, daemon=True).start()
        self.after(100, self._poll)

    def _poll(self):
        try:
            while True:
                self.write(self.msg_queue.get_nowait())
        except queue.Empty:
            pass
        if self.busy:
            self.after(100, self._poll)

    def stop(self):
        self.stop_event.set()
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.write("\n[stop requested — finishing current step]\n")
        elif not self.busy:
            messagebox.showinfo("Idle", "Nothing is running in this tab.")


def control_row(parent):
    row = ttk.Frame(parent)
    row.pack(fill="x", padx=8, pady=8)
    return row


def labeled_entry(row, label, width=30, default=""):
    ttk.Label(row, text=label).pack(side="left", padx=(0, 4))
    var = tk.StringVar(value=default)
    ttk.Entry(row, textvariable=var, width=width).pack(side="left", padx=(0, 12))
    return var


def labeled_combo(row, label, values, default=None, width=22):
    ttk.Label(row, text=label).pack(side="left", padx=(0, 4))
    var = tk.StringVar(value=default or values[0])
    cb = ttk.Combobox(row, textvariable=var, values=values, state="readonly", width=width)
    cb.pack(side="left", padx=(0, 12))
    return var


def run_stop_buttons(row, on_run, on_stop):
    ttk.Button(row, text="▶ Run", command=on_run).pack(side="left", padx=4)
    ttk.Button(row, text="■ Stop", command=on_stop).pack(side="left", padx=4)


def require(var, field_name):
    val = var.get().strip()
    if not val:
        messagebox.showwarning("Missing input", f"{field_name} is required.")
        return None
    return val


# ──────────────────────────────────────────────────────────────────
# Tab builders — each wires simple inputs to a module script
# ──────────────────────────────────────────────────────────────────
def full_host_scan_cmd(target, use_sudo):
    cmd = ["nmap", "-sS", "-O", "--osscan-guess", "--osscan-limit",
           "--max-os-tries", "1", "-T4", "-Pn", "-p-", target]
    return (["sudo"] + cmd) if use_sudo else cmd


def sweep_and_scan_job(panel, subnet, use_sudo):
    """Replicates all_recon.sh option 1: ping-sweep the /24, then run a
    full nmap scan against every host that answered, one at a time,
    writing each host's results to output/host_<ip>_<timestamp>.txt —
    same naming convention as the bash tool so both front-ends share
    the same output/ directory cleanly."""
    out_dir = os.path.join(PROJECT_ROOT, "output")
    os.makedirs(out_dir, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")

    cidr = f"{subnet}.0/24"
    panel.msg_queue.put(f"[*] Ping sweeping {cidr} ...\n")
    sweep_cmd = (["sudo"] if use_sudo else []) + ["nmap", "-sn", cidr]

    # Capture sweep output ourselves (not via _run_single) so we can parse
    # live hosts out of it once it's done, while still streaming it live.
    if panel.stop_event.is_set():
        return
    panel.msg_queue.put(f"\n$ {' '.join(sweep_cmd)}\n")
    proc = subprocess.Popen(
        sweep_cmd, cwd=PROJECT_ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    panel.process = proc
    collected = []
    for line in proc.stdout:
        panel.msg_queue.put(line)
        collected.append(line)
        if panel.stop_event.is_set():
            proc.terminate()
            break
    proc.wait()
    if panel.stop_event.is_set():
        panel.msg_queue.put("\n[*] Stopped during ping sweep.\n")
        return

    hosts = re.findall(
        r"Nmap scan report for (?:\S+ \()?((?:\d{1,3}\.){3}\d{1,3})\)?",
        "".join(collected),
    )
    hosts = sorted(set(hosts), key=lambda ip: tuple(int(p) for p in ip.split(".")))

    if not hosts:
        panel.msg_queue.put("\n[*] No hosts responded to the ping sweep.\n")
        return

    panel.msg_queue.put(f"\n[+] {len(hosts)} host(s) up: {', '.join(hosts)}\n")
    panel.msg_queue.put("[*] Starting full nmap scans (sequential, one host at a time) ...\n")

    for i, host in enumerate(hosts, 1):
        if panel.stop_event.is_set():
            panel.msg_queue.put(f"\n[*] Stopped before scanning remaining hosts ({len(hosts) - i + 1} left).\n")
            break
        panel.msg_queue.put(f"\n🔎 [{i}/{len(hosts)}] Scanning {host} ...\n")
        out_file = os.path.join(out_dir, f"host_{host.replace('.', '_')}_{timestamp}.txt")
        rc = panel._run_single(full_host_scan_cmd(host, use_sudo), save_to=out_file)
        if rc is None:
            break
        panel.msg_queue.put(f"✅ Scan complete for {host} (results: output/{os.path.basename(out_file)})\n")

    panel.msg_queue.put(f"\n📁 All results saved to: output/\n")


def build_host_scan_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Host / Network Scan")

    row = control_row(tab)
    target = labeled_entry(
        row,
        "Target — full IP/domain for single-host mode, or subnet prefix (e.g. 10.0.0) for sweep modes:",
        width=40,
    )
    mode = labeled_combo(row, "Mode:", [
        "Full TCP scan (single host)",
        "Ping sweep only (subnet)",
        "Full sweep + scan every live host (subnet)",
    ], width=38)
    sudo_var = tk.BooleanVar(value=False)
    ttk.Checkbutton(row, text="Run with sudo (needed for -sS/-O)", variable=sudo_var).pack(side="left", padx=8)

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_run():
        t = require(target, "Target")
        if not t:
            return
        selected = mode.get()
        use_sudo = sudo_var.get()

        if selected.startswith("Full TCP"):
            panel.run(full_host_scan_cmd(t, use_sudo))
        elif selected.startswith("Ping sweep only"):
            cmd = (["sudo"] if use_sudo else []) + ["nmap", "-sn", f"{t}.0/24"]
            panel.run(cmd)
        else:
            if not messagebox.askyesno(
                "Confirm subnet scan",
                f"This will ping-sweep {t}.0/24 and then run a full TCP port "
                f"scan (-p-) against every host that responds, one after another. "
                f"On a /24 this can take a long time.\n\nOnly run this against "
                f"networks you're authorized to scan. Continue?",
            ):
                return
            panel.run_job(lambda p: sweep_and_scan_job(p, t, use_sudo))

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_subdomain_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Subdomain Discovery")
    inner = ttk.Notebook(tab)
    inner.pack(fill="both", expand=True)

    # -- Discover sub-tab --
    discover = ttk.Frame(inner)
    inner.add(discover, text="Discover")
    row = control_row(discover)
    domain = labeled_entry(row, "Target domain:", width=24)
    method = labeled_combo(row, "Method:", [
        "dns", "common", "reverse", "records", "cert",
        "hackertarget", "alienvault", "rapiddns", "osint", "all",
    ], default="all")
    panel1 = OutputPanel(discover)
    panel1.pack(fill="both", expand=True)

    def run_discover():
        d = require(domain, "Target domain")
        if not d:
            return
        panel1.run(["bash", module_path("subdomain_finder.sh"), d, method.get()])

    buttons1 = control_row(discover)
    run_stop_buttons(buttons1, run_discover, panel1.stop)

    # -- Clean sub-tab --
    clean = ttk.Frame(inner)
    inner.add(clean, text="Clean & Export")
    row2 = control_row(clean)
    clean_dir = labeled_entry(row2, "Results directory:", width=36,
                               default=os.path.join("output", "subdomains_*"))

    def browse_dir():
        path = filedialog.askdirectory(initialdir=os.path.join(PROJECT_ROOT, "output"))
        if path:
            clean_dir.set(path)

    ttk.Button(row2, text="Browse…", command=browse_dir).pack(side="left", padx=(0, 12))
    action = labeled_combo(row2, "Action:", [
        "extract", "deduplicate", "active", "group", "csv", "json", "all",
    ], default="all")
    panel2 = OutputPanel(clean)
    panel2.pack(fill="both", expand=True)

    def run_clean():
        d = require(clean_dir, "Results directory")
        if not d:
            return
        panel2.run(["bash", module_path("subdomain_cleaner.sh"), d, action.get()])

    buttons2 = control_row(clean)
    run_stop_buttons(buttons2, run_clean, panel2.stop)


def build_web_vuln_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Web Vulnerabilities")
    row = control_row(tab)
    url = labeled_entry(row, "Target URL (http:// or https://):", width=34)
    scan_map = {
        "SQL Injection": "1", "XSS": "2", "Command Injection": "3",
        "CSRF": "4", "Auth & Authorization": "5", "Broken Access Control": "6",
        "Sensitive Data Exposure": "7", "XXE": "8", "BOLA": "9",
        "Run All Scans": "10",
    }
    vuln = labeled_combo(row, "Vulnerability:", list(scan_map.keys()), default="Run All Scans", width=24)

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_run():
        u = require(url, "Target URL")
        if not u:
            return
        panel.run(["bash", module_path("web_vulnerabilities.sh"), u, scan_map[vuln.get()]])

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_whois_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="WHOIS / Reverse Lookup")
    row = control_row(tab)
    target = labeled_entry(row, "Domain or IP:", width=28)
    mode = labeled_combo(row, "Mode:", ["domain", "ip", "reverse", "ranges", "related", "all"], default="all")

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_run():
        t = require(target, "Domain or IP")
        if not t:
            return
        panel.run(["bash", module_path("whois_recon.sh"), t, mode.get()])

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_passive_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Passive OSINT")
    row = control_row(tab)
    target = labeled_entry(row, "Domain or IP:", width=28)

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_run():
        t = require(target, "Domain or IP")
        if not t:
            return
        panel.run(["bash", module_path("passive.sh"), t])

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_batch_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Batch Scanner")
    row = control_row(tab)
    targets_file = labeled_entry(row, "Targets file:", width=30,
                                  default=os.path.join(PROJECT_ROOT, "targets.txt"))

    def browse_file():
        path = filedialog.askopenfilename(initialdir=PROJECT_ROOT)
        if path:
            targets_file.set(path)

    ttk.Button(row, text="Browse…", command=browse_file).pack(side="left", padx=(0, 12))

    row2 = control_row(tab)
    mode = labeled_combo(row2, "Mode:", ["recon", "whois", "subdomain", "passive", "web", "all"], default="recon")
    concurrency = labeled_entry(row2, "Max workers:", width=4, default="5")

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_run():
        f = require(targets_file, "Targets file")
        if not f:
            return
        if not os.path.isfile(f):
            messagebox.showerror("Not found", f"Targets file does not exist:\n{f}")
            return
        c = concurrency.get().strip() or "5"
        panel.run(["bash", module_path("batch_runner.sh"), f, mode.get(), c])

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_reports_tab(nb):
    tab = ttk.Frame(nb)
    nb.add(tab, text="Reports")
    row = control_row(tab)
    scan_dir = labeled_entry(row, "Scan directory:", width=24, default="output")

    panel = OutputPanel(tab)
    panel.pack(fill="both", expand=True)

    def on_generate():
        d = require(scan_dir, "Scan directory")
        if not d:
            return
        panel.run(["bash", module_path("reporting.sh"), d])

    def on_list():
        panel.run(["bash", module_path("reporting.sh"), "list"])

    buttons = control_row(tab)
    ttk.Button(buttons, text="▶ Generate Report", command=on_generate).pack(side="left", padx=4)
    ttk.Button(buttons, text="📁 List Reports", command=on_list).pack(side="left", padx=4)
    ttk.Button(buttons, text="■ Stop", command=panel.stop).pack(side="left", padx=4)


# ──────────────────────────────────────────────────────────────────
# Main window
# ──────────────────────────────────────────────────────────────────
class AllReconGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("ALL-RECON — Pentester Workflow GUI")
        self.geometry("980x640")
        self.configure(bg=BG)

        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure(".", background=PANEL_BG, foreground=FG, fieldbackground="#1a222c")
        style.configure("TNotebook", background=BG)
        style.configure("TNotebook.Tab", background="#1a222c", foreground=FG, padding=(10, 6))
        style.map("TNotebook.Tab", background=[("selected", ACCENT)])
        style.configure("TFrame", background=PANEL_BG)
        style.configure("TLabel", background=PANEL_BG, foreground=FG)
        style.configure("TButton", padding=6)
        style.configure("TCheckbutton", background=PANEL_BG, foreground=FG)

        header = ttk.Frame(self)
        header.pack(fill="x")
        ttk.Label(
            header, text="  ALL-RECON — unified front-end for modules/*.sh",
            font=("Consolas", 13, "bold"),
        ).pack(side="left", pady=10)

        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=6, pady=6)

        build_host_scan_tab(nb)
        build_subdomain_tab(nb)
        build_web_vuln_tab(nb)
        build_whois_tab(nb)
        build_passive_tab(nb)
        build_batch_tab(nb)
        build_reports_tab(nb)

        status = ttk.Label(
            self,
            text=f"Project root: {PROJECT_ROOT}    |    Authorized targets only.",
            anchor="w",
        )
        status.pack(fill="x", padx=8, pady=(0, 6))


def main():
    require_modules_dir()
    app = AllReconGUI()
    app.mainloop()


if __name__ == "__main__":
    main()
