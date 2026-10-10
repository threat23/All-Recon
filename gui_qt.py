#!/usr/bin/env python3
"""
ALL-RECON GUI (Qt Version)
Graphical front-end for the ALL-RECON pentesting automation suite.

Place this file in the project root (same folder as all_recon.sh) and run:
    python3 gui_qt.py

Requires: PyQt6
    pip install PyQt6

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
import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QLabel, QLineEdit, QComboBox, QCheckBox, QPushButton,
    QTextEdit, QFileDialog, QMessageBox, QFrame, QSplitter, QStyle
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QProcess, QTimer
from PyQt6.QtGui import QIcon, QPalette, QColor, QFont, QTextCursor

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
MODULES_DIR = os.path.join(PROJECT_ROOT, "modules")


def module_path(name):
    return os.path.join(MODULES_DIR, name)


def require_modules_dir():
    if not os.path.isdir(MODULES_DIR):
        QMessageBox.critical(
            None,
            "modules/ not found",
            f"Expected a 'modules' directory next to this file:\n{MODULES_DIR}\n\n"
            "Put gui_qt.py in the same folder as all_recon.sh before running it.",
        )


# ──────────────────────────────────────────────────────────────────
# Dark Theme Styling
# ──────────────────────────────────────────────────────────────────
def set_dark_theme(app):
    app.setStyle("Fusion")
    
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor("#0b0f14"))
    palette.setColor(QPalette.ColorRole.WindowText, QColor("#39ff14"))
    palette.setColor(QPalette.ColorRole.Base, QColor("#10161d"))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor("#0b0f14"))
    palette.setColor(QPalette.ColorRole.ToolTipBase, QColor("#39ff14"))
    palette.setColor(QPalette.ColorRole.ToolTipText, QColor("#0b0f14"))
    palette.setColor(QPalette.ColorRole.Text, QColor("#39ff14"))
    palette.setColor(QPalette.ColorRole.Button, QColor("#1a222c"))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor("#39ff14"))
    palette.setColor(QPalette.ColorRole.BrightText, QColor("#ff0000"))
    palette.setColor(QPalette.ColorRole.Link, QColor("#1f6feb"))
    palette.setColor(QPalette.ColorRole.Highlight, QColor("#1f6feb"))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor("#0b0f14"))
    
    app.setPalette(palette)


# ──────────────────────────────────────────────────────────────────
# Worker Thread for subprocess execution
# ──────────────────────────────────────────────────────────────────
class ProcessWorker(QThread):
    output = pyqtSignal(str)
    finished = pyqtSignal(int)
    error = pyqtSignal(str)
    
    def __init__(self, cmd, cwd=None, save_to=None):
        super().__init__()
        self.cmd = cmd
        self.cwd = cwd or PROJECT_ROOT
        self.save_to = save_to
        self.process = None
        self._stop_requested = False
    
    def run(self):
        try:
            self.output.emit(f"\n$ {' '.join(self.cmd)}\n")
            
            fh = open(self.save_to, "w", encoding="utf-8") if self.save_to else None
            try:
                self.process = subprocess.Popen(
                    self.cmd, cwd=self.cwd,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, bufsize=1,
                )
                
                for line in self.process.stdout:
                    if self._stop_requested:
                        self.process.terminate()
                        break
                    self.output.emit(line)
                    if fh:
                        fh.write(line)
                
                self.process.wait()
                self.finished.emit(self.process.returncode)
            finally:
                if fh:
                    fh.close()
        except FileNotFoundError as e:
            self.error.emit(f"\n[error] {e}\n")
        except Exception as e:
            self.error.emit(f"\n[unexpected error] {e}\n")
    
    def stop(self):
        self._stop_requested = True
        if self.process and self.process.poll() is None:
            self.process.terminate()


# ──────────────────────────────────────────────────────────────────
# Output Panel
# ──────────────────────────────────────────────────────────────────
class OutputPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.layout = QVBoxLayout(self)
        self.layout.setContentsMargins(8, 4, 8, 8)
        
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        self.log.setStyleSheet("""
            QTextEdit {
                background-color: #0b0f14;
                color: #39ff14;
                border: 1px solid #1a222c;
                border-radius: 4px;
                font-family: 'Consolas', 'Monaco', monospace;
                font-size: 10pt;
            }
        """)
        self.layout.addWidget(self.log)
        
        self.worker = None
        self.busy = False
    
    def write(self, text):
        cursor = self.log.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        cursor.insertText(text)
        self.log.setTextCursor(cursor)
        self.log.ensureCursorVisible()
    
    def clear(self):
        self.log.clear()
    
    def run(self, cmd):
        if self.busy:
            QMessageBox.warning(self, "Busy", "A scan is already running in this tab.\n"
                                            "Stop it first, or wait for it to finish.")
            return
        
        self.clear()
        self.busy = True
        
        self.worker = ProcessWorker(cmd)
        self.worker.output.connect(self.write)
        self.worker.finished.connect(self._on_finished)
        self.worker.error.connect(self.write)
        self.worker.start()
    
    def _on_finished(self, exit_code):
        self.write(f"\n[process exited with code {exit_code}]\n")
        self.busy = False
        self.worker = None
    
    def stop(self):
        if self.worker:
            self.worker.stop()
            self.write("\n[stop requested]\n")
        else:
            QMessageBox.information(self, "Idle", "Nothing is running in this tab.")


# ──────────────────────────────────────────────────────────────────
# Control Row Builder
# ──────────────────────────────────────────────────────────────────
def control_row(parent):
    row = QHBoxLayout()
    row.setContentsMargins(8, 8, 8, 8)
    container = QWidget()
    container.setLayout(row)
    parent.layout().addWidget(container)
    return row


def labeled_entry(row, label, width=30, default=""):
    lbl = QLabel(label)
    lbl.setStyleSheet("color: #39ff14;")
    row.addWidget(lbl)
    
    entry = QLineEdit(default)
    entry.setFixedWidth(int(width * 8))
    entry.setStyleSheet("""
        QLineEdit {
            background-color: #1a222c;
            color: #39ff14;
            border: 1px solid #1f6feb;
            border-radius: 3px;
            padding: 4px;
        }
    """)
    row.addWidget(entry)
    row.addSpacing(12)
    return entry


def labeled_combo(row, label, values, default=None, width=22):
    lbl = QLabel(label)
    lbl.setStyleSheet("color: #39ff14;")
    row.addWidget(lbl)
    
    combo = QComboBox()
    combo.addItems(values)
    combo.setCurrentText(default or values[0])
    combo.setFixedWidth(int(width * 8))
    combo.setStyleSheet("""
        QComboBox {
            background-color: #1a222c;
            color: #39ff14;
            border: 1px solid #1f6feb;
            border-radius: 3px;
            padding: 4px;
        }
        QComboBox::drop-down {
            border: none;
        }
        QComboBox::down-arrow {
            image: url(none);
        }
    """)
    row.addWidget(combo)
    row.addSpacing(12)
    return combo


def run_stop_buttons(row, on_run, on_stop):
    run_btn = QPushButton("Run")
    run_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_MediaPlay))
    run_btn.setStyleSheet("""
        QPushButton {
            background-color: #1f6feb;
            color: #0b0f14;
            border: none;
            border-radius: 4px;
            padding: 6px 16px;
            font-weight: bold;
        }
        QPushButton:hover {
            background-color: #2a7fee;
        }
        QPushButton:pressed {
            background-color: #1a5dd6;
        }
    """)
    run_btn.clicked.connect(on_run)
    row.addWidget(run_btn)
    
    stop_btn = QPushButton("Stop")
    stop_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_MediaStop))
    stop_btn.setStyleSheet("""
        QPushButton {
            background-color: #ff4444;
            color: #0b0f14;
            border: none;
            border-radius: 4px;
            padding: 6px 16px;
            font-weight: bold;
        }
        QPushButton:hover {
            background-color: #ff6666;
        }
        QPushButton:pressed {
            background-color: #cc3333;
        }
    """)
    stop_btn.clicked.connect(on_stop)
    row.addWidget(stop_btn)


def require(entry, field_name):
    val = entry.text().strip()
    if not val:
        QMessageBox.warning(None, "Missing input", f"{field_name} is required.")
        return None
    return val


# ──────────────────────────────────────────────────────────────────
# Tab Builders
# ──────────────────────────────────────────────────────────────────
def full_host_scan_cmd(target, use_sudo):
    cmd = ["nmap", "-sS", "-O", "--osscan-guess", "--osscan-limit",
           "--max-os-tries", "1", "-T4", "-Pn", "-p-", target]
    return (["sudo"] + cmd) if use_sudo else cmd


def build_host_scan_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Host / Network Scan")
    
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
    
    sudo_cb = QCheckBox("Run with sudo (needed for -sS/-O)")
    sudo_cb.setStyleSheet("color: #39ff14;")
    row.addWidget(sudo_cb)
    
    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)
    
    def on_run():
        t = require(target, "Target")
        if not t:
            return
        selected = mode.currentText()
        use_sudo = sudo_cb.isChecked()
        
        if selected.startswith("Full TCP"):
            panel.run(full_host_scan_cmd(t, use_sudo))
        elif selected.startswith("Ping sweep only"):
            cmd = (["sudo"] if use_sudo else []) + ["nmap", "-sn", f"{t}.0/24"]
            panel.run(cmd)
        else:
            reply = QMessageBox.question(
                tab, "Confirm subnet scan",
                f"This will ping-sweep {t}.0/24 and then run a full TCP port "
                f"scan (-p-) against every host that responds, one after another. "
                f"On a /24 this can take a long time.\n\nOnly run this against "
                f"networks you're authorized to scan. Continue?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply == QMessageBox.StandardButton.Yes:
                panel.run(full_host_scan_cmd(t, use_sudo))
    
    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_subdomain_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Subdomain Discovery")
    
    inner = QTabWidget()
    tab.layout().addWidget(inner)
    
    # -- Discover sub-tab --
    discover = QWidget()
    discover.setLayout(QVBoxLayout())
    inner.addTab(discover, "Discover")
    
    row = control_row(discover)
    domain = labeled_entry(row, "Target domain:", width=24)
    method = labeled_combo(row, "Method:", [
        "dns", "common", "reverse", "records", "cert",
        "hackertarget", "alienvault", "rapiddns", "osint", "all",
    ], default="all")
    
    panel1 = OutputPanel(discover)
    discover.layout().addWidget(panel1)
    
    def run_discover():
        d = require(domain, "Target domain")
        if not d:
            return
        panel1.run(["bash", module_path("subdomain_finder.sh"), d, method.currentText()])
    
    buttons1 = control_row(discover)
    run_stop_buttons(buttons1, run_discover, panel1.stop)
    
    # -- Clean sub-tab --
    clean = QWidget()
    clean.setLayout(QVBoxLayout())
    inner.addTab(clean, "Clean & Export")
    
    row2 = control_row(clean)
    clean_dir = labeled_entry(row2, "Results directory:", width=36,
                               default=os.path.join("output", "subdomains_*"))
    
    def browse_dir():
        path = QFileDialog.getExistingDirectory(None, "Select Directory", os.path.join(PROJECT_ROOT, "output"))
        if path:
            clean_dir.setText(path)
    
    browse_btn = QPushButton("Browse…")
    browse_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_DialogOpenButton))
    browse_btn.setStyleSheet("""
        QPushButton {
            background-color: #1a222c;
            color: #39ff14;
            border: 1px solid #1f6feb;
            border-radius: 3px;
            padding: 4px 12px;
        }
    """)
    browse_btn.clicked.connect(browse_dir)
    row2.addWidget(browse_btn)
    row2.addSpacing(12)
    
    action = labeled_combo(row2, "Action:", [
        "extract", "deduplicate", "active", "group", "csv", "json", "all",
    ], default="all")
    
    panel2 = OutputPanel(clean)
    clean.layout().addWidget(panel2)
    
    def run_clean():
        d = require(clean_dir, "Results directory")
        if not d:
            return
        panel2.run(["bash", module_path("subdomain_cleaner.sh"), d, action.currentText()])
    
    buttons2 = control_row(clean)
    run_stop_buttons(buttons2, run_clean, panel2.stop)


def build_web_vuln_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Web Vulnerabilities")
    
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
    tab.layout().addWidget(panel)
    
    def on_run():
        u = require(url, "Target URL")
        if not u:
            return
        panel.run(["bash", module_path("web_vulnerabilities.sh"), u, scan_map[vuln.currentText()]])
    
    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_whois_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "WHOIS / Reverse Lookup")
    
    row = control_row(tab)
    target = labeled_entry(row, "Domain or IP:", width=28)
    mode = labeled_combo(row, "Mode:", ["domain", "ip", "reverse", "ranges", "related", "all"], default="all")
    
    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)
    
    def on_run():
        t = require(target, "Domain or IP")
        if not t:
            return
        panel.run(["bash", module_path("whois_recon.sh"), t, mode.currentText()])
    
    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_passive_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Passive OSINT")
    
    row = control_row(tab)
    target = labeled_entry(row, "Domain or IP:", width=28)
    
    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)
    
    def on_run():
        t = require(target, "Domain or IP")
        if not t:
            return
        panel.run(["bash", module_path("passive.sh"), t])
    
    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)



def build_enrichment_tab(nb):
    """UI for the new ASN, HTTP/TLS, and DNS/email recon modules."""
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Recon Enrichment")

    row = control_row(tab)
    target = labeled_entry(row, "Authorized target (domain, IP, or URL):", width=34)
    tool_map = {
        "ASN / IP Mapping": "asn_recon.py",
        "HTTP / TLS Fingerprinting": "http_fingerprint.py",
        "DNS & Email Security": "dns_email_audit.py",
    }
    tool = labeled_combo(row, "Module:", list(tool_map.keys()),
                         default="ASN / IP Mapping", width=30)

    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)

    def on_run():
        value = require(target, "Target")
        if not value:
            return
        module = tool_map[tool.currentText()]
        panel.run([
            sys.executable, module_path(module), value,
            "--output-dir", os.path.join(PROJECT_ROOT, "output")
        ])

    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_batch_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Batch Scanner")
    
    row = control_row(tab)
    targets_file = labeled_entry(row, "Targets file:", width=30,
                                  default=os.path.join(PROJECT_ROOT, "targets.txt"))
    
    def browse_file():
        path = QFileDialog.getOpenFileName(None, "Select Targets File", PROJECT_ROOT)[0]
        if path:
            targets_file.setText(path)
    
    browse_btn = QPushButton("Browse…")
    browse_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_DialogOpenButton))
    browse_btn.setStyleSheet("""
        QPushButton {
            background-color: #1a222c;
            color: #39ff14;
            border: 1px solid #1f6feb;
            border-radius: 3px;
            padding: 4px 12px;
        }
    """)
    browse_btn.clicked.connect(browse_file)
    row.addWidget(browse_btn)
    row.addSpacing(12)
    
    row2 = control_row(tab)
    mode = labeled_combo(row2, "Mode:", ["recon", "whois", "subdomain", "passive", "web", "all"], default="recon")
    concurrency = labeled_entry(row2, "Max workers:", width=4, default="5")
    
    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)
    
    def on_run():
        f = require(targets_file, "Targets file")
        if not f:
            return
        if not os.path.isfile(f):
            QMessageBox.critical(None, "Not found", f"Targets file does not exist:\n{f}")
            return
        c = concurrency.text().strip() or "5"
        panel.run(["bash", module_path("batch_runner.sh"), f, mode.currentText(), c])
    
    buttons = control_row(tab)
    run_stop_buttons(buttons, on_run, panel.stop)


def build_reports_tab(nb):
    tab = QWidget()
    tab.setLayout(QVBoxLayout())
    nb.addTab(tab, "Reports")
    
    row = control_row(tab)
    scan_dir = labeled_entry(row, "Scan directory:", width=24, default="output")
    
    panel = OutputPanel(tab)
    tab.layout().addWidget(panel)
    
    def on_generate():
        d = require(scan_dir, "Scan directory")
        if not d:
            return
        panel.run(["bash", module_path("reporting.sh"), d])
    
    def on_list():
        panel.run(["bash", module_path("reporting.sh"), "list"])
    
    buttons = control_row(tab)
    
    gen_btn = QPushButton("Generate Report")
    gen_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_FileIcon))
    gen_btn.setStyleSheet("""
        QPushButton {
            background-color: #1f6feb;
            color: #0b0f14;
            border: none;
            border-radius: 4px;
            padding: 6px 16px;
            font-weight: bold;
        }
        QPushButton:hover {
            background-color: #2a7fee;
        }
    """)
    gen_btn.clicked.connect(on_generate)
    buttons.addWidget(gen_btn)
    
    list_btn = QPushButton("List Reports")
    list_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_FileDialogDetailedView))
    list_btn.setStyleSheet("""
        QPushButton {
            background-color: #1a222c;
            color: #39ff14;
            border: 1px solid #1f6feb;
            border-radius: 4px;
            padding: 6px 16px;
        }
        QPushButton:hover {
            background-color: #2a333c;
        }
    """)
    list_btn.clicked.connect(on_list)
    buttons.addWidget(list_btn)
    
    stop_btn = QPushButton("Stop")
    stop_btn.setIcon(QApplication.style().standardIcon(QStyle.StandardPixmap.SP_MediaStop))
    stop_btn.setStyleSheet("""
        QPushButton {
            background-color: #ff4444;
            color: #0b0f14;
            border: none;
            border-radius: 4px;
            padding: 6px 16px;
            font-weight: bold;
        }
        QPushButton:hover {
            background-color: #ff6666;
        }
    """)
    stop_btn.clicked.connect(panel.stop)
    buttons.addWidget(stop_btn)


# ──────────────────────────────────────────────────────────────────
# Main Window
# ──────────────────────────────────────────────────────────────────
class AllReconGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ALL-RECON — Pentester Workflow GUI")
        self.setGeometry(100, 100, 1024, 680)
        
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.central_widget.setLayout(QVBoxLayout())
        
        # Header
        header = QFrame()
        header.setStyleSheet("background-color: #10161d; border-bottom: 1px solid #1a222c;")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(12, 10, 12, 10)
        
        title = QLabel("  ALL-RECON — unified front-end for modules/*.sh")
        title.setFont(QFont("Consolas", 13, QFont.Weight.Bold))
        title.setStyleSheet("color: #39ff14;")
        header_layout.addWidget(title)
        header_layout.addStretch()
        
        self.central_widget.layout().addWidget(header)
        
        # Tab widget
        self.nb = QTabWidget()
        self.nb.setStyleSheet("""
            QTabWidget::pane {
                border: 1px solid #1a222c;
                background-color: #10161d;
            }
            QTabBar::tab {
                background-color: #1a222c;
                color: #39ff14;
                padding: 8px 16px;
                border: 1px solid #1a222c;
                border-bottom: none;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background-color: #1f6feb;
                color: #0b0f14;
            }
            QTabBar::tab:hover:!selected {
                background-color: #2a333c;
            }
        """)
        self.central_widget.layout().addWidget(self.nb)
        
        # Build tabs
        build_host_scan_tab(self.nb)
        build_subdomain_tab(self.nb)
        build_web_vuln_tab(self.nb)
        build_whois_tab(self.nb)
        build_passive_tab(self.nb)
        build_enrichment_tab(self.nb)
        build_batch_tab(self.nb)
        build_reports_tab(self.nb)
        
        # Status bar
        status = QLabel(f"Project root: {PROJECT_ROOT}    |    Authorized targets only.")
        status.setStyleSheet("color: #39ff14; padding: 6px;")
        self.central_widget.layout().addWidget(status)


def main():
    require_modules_dir()
    app = QApplication([])
    set_dark_theme(app)
    gui = AllReconGUI()
    gui.show()
    app.exec()


if __name__ == "__main__":
    main()
