#!/usr/bin/env python3
"""
SIAB Provisioning GUI
A graphical interface for deploying SIAB on bare metal hardware.

Requirements: Python 3.6+ with tkinter (usually included)
Usage: Double-click this file or run: python3 siab-provisioner-gui.py
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox, filedialog
import subprocess
import threading
import os
import json
import socket
import re
from datetime import datetime

class SIABProvisionerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("SIAB Provisioner")
        self.root.geometry("900x700")

        # Set icon if available
        try:
            self.root.iconbitmap("siab-icon.ico")
        except:
            pass

        # Variables
        self.provisioning_method = tk.StringVar(value="pxe")
        self.subnet = tk.StringVar(value=self.detect_subnet())
        self.cluster_name = tk.StringVar(value="siab-cluster")
        self.node_count = tk.IntVar(value=3)
        self.maas_url = tk.StringVar(value="http://localhost:5240/MAAS")
        self.maas_api_key = tk.StringVar()

        self.setup_ui()

    def detect_subnet(self):
        """Auto-detect local subnet"""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            subnet = '.'.join(ip.split('.')[:-1]) + '.0/24'
            return subnet
        except:
            return "192.168.1.0/24"

    def setup_ui(self):
        """Setup the user interface"""

        # Header
        header = tk.Frame(self.root, bg="#2563eb", height=60)
        header.pack(fill=tk.X)
        header.pack_propagate(False)

        title = tk.Label(header, text="SIAB Provisioner",
                        font=("Arial", 20, "bold"),
                        bg="#2563eb", fg="white")
        title.pack(pady=15)

        # Main container
        main = ttk.Notebook(self.root)
        main.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # Tabs
        self.setup_tab = ttk.Frame(main)
        self.discover_tab = ttk.Frame(main)
        self.deploy_tab = ttk.Frame(main)
        self.monitor_tab = ttk.Frame(main)

        main.add(self.setup_tab, text="Setup")
        main.add(self.discover_tab, text="Discover Hardware")
        main.add(self.deploy_tab, text="Deploy Cluster")
        main.add(self.monitor_tab, text="Monitor")

        self.setup_setup_tab()
        self.setup_discover_tab()
        self.setup_deploy_tab()
        self.setup_monitor_tab()

        # Status bar
        self.status_bar = tk.Label(self.root, text="Ready",
                                  bd=1, relief=tk.SUNKEN, anchor=tk.W)
        self.status_bar.pack(side=tk.BOTTOM, fill=tk.X)

    def setup_setup_tab(self):
        """Setup configuration tab"""
        frame = ttk.LabelFrame(self.setup_tab, text="Provisioning Method", padding=10)
        frame.pack(fill=tk.X, padx=10, pady=10)

        ttk.Radiobutton(frame, text="PXE Boot Server (Lightweight)",
                       variable=self.provisioning_method, value="pxe").pack(anchor=tk.W)
        ttk.Radiobutton(frame, text="MAAS (Enterprise)",
                       variable=self.provisioning_method, value="maas").pack(anchor=tk.W)

        # Network settings
        net_frame = ttk.LabelFrame(self.setup_tab, text="Network Configuration", padding=10)
        net_frame.pack(fill=tk.X, padx=10, pady=10)

        ttk.Label(net_frame, text="Subnet (CIDR):").grid(row=0, column=0, sticky=tk.W, pady=5)
        ttk.Entry(net_frame, textvariable=self.subnet, width=30).grid(row=0, column=1, pady=5)

        # MAAS settings (shown conditionally)
        self.maas_frame = ttk.LabelFrame(self.setup_tab, text="MAAS Configuration", padding=10)
        self.maas_frame.pack(fill=tk.X, padx=10, pady=10)

        ttk.Label(self.maas_frame, text="MAAS URL:").grid(row=0, column=0, sticky=tk.W, pady=5)
        ttk.Entry(self.maas_frame, textvariable=self.maas_url, width=40).grid(row=0, column=1, pady=5)

        ttk.Label(self.maas_frame, text="API Key:").grid(row=1, column=0, sticky=tk.W, pady=5)
        ttk.Entry(self.maas_frame, textvariable=self.maas_api_key, width=40, show="*").grid(row=1, column=1, pady=5)

        # Setup button
        btn_frame = tk.Frame(self.setup_tab)
        btn_frame.pack(fill=tk.X, padx=10, pady=20)

        ttk.Button(btn_frame, text="Setup Provisioning Server",
                  command=self.setup_provisioning, style="Accent.TButton").pack()

        # Log output
        log_frame = ttk.LabelFrame(self.setup_tab, text="Output", padding=10)
        log_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        self.setup_log = scrolledtext.ScrolledText(log_frame, height=10)
        self.setup_log.pack(fill=tk.BOTH, expand=True)

    def setup_discover_tab(self):
        """Setup hardware discovery tab"""
        frame = ttk.LabelFrame(self.discover_tab, text="Scan Options", padding=10)
        frame.pack(fill=tk.X, padx=10, pady=10)

        self.scan_ipmi = tk.BooleanVar(value=True)
        self.scan_pxe = tk.BooleanVar(value=True)

        ttk.Checkbutton(frame, text="Scan for IPMI interfaces",
                       variable=self.scan_ipmi).pack(anchor=tk.W)
        ttk.Checkbutton(frame, text="Filter PXE-capable devices",
                       variable=self.scan_pxe).pack(anchor=tk.W)

        ttk.Button(frame, text="Scan Network",
                  command=self.discover_hardware).pack(pady=10)

        # Results
        results_frame = ttk.LabelFrame(self.discover_tab, text="Discovered Hardware", padding=10)
        results_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # Treeview for results
        self.hardware_tree = ttk.Treeview(results_frame,
                                         columns=("IP", "MAC", "Hostname", "IPMI", "PXE"),
                                         show="tree headings")
        self.hardware_tree.heading("#0", text="Status")
        self.hardware_tree.heading("IP", text="IP Address")
        self.hardware_tree.heading("MAC", text="MAC Address")
        self.hardware_tree.heading("Hostname", text="Hostname")
        self.hardware_tree.heading("IPMI", text="IPMI")
        self.hardware_tree.heading("PXE", text="PXE Ready")

        self.hardware_tree.column("#0", width=50)
        self.hardware_tree.column("IP", width=120)
        self.hardware_tree.column("MAC", width=140)
        self.hardware_tree.column("Hostname", width=150)
        self.hardware_tree.column("IPMI", width=80)
        self.hardware_tree.column("PXE", width=80)

        scrollbar = ttk.Scrollbar(results_frame, orient=tk.VERTICAL, command=self.hardware_tree.yview)
        self.hardware_tree.configure(yscrollcommand=scrollbar.set)

        self.hardware_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Export button
        ttk.Button(results_frame, text="Export to JSON",
                  command=self.export_hardware).pack(pady=5)

    def setup_deploy_tab(self):
        """Setup cluster deployment tab"""
        config_frame = ttk.LabelFrame(self.deploy_tab, text="Cluster Configuration", padding=10)
        config_frame.pack(fill=tk.X, padx=10, pady=10)

        ttk.Label(config_frame, text="Cluster Name:").grid(row=0, column=0, sticky=tk.W, pady=5)
        ttk.Entry(config_frame, textvariable=self.cluster_name, width=30).grid(row=0, column=1, pady=5)

        ttk.Label(config_frame, text="Number of Nodes:").grid(row=1, column=0, sticky=tk.W, pady=5)
        ttk.Spinbox(config_frame, from_=1, to=100, textvariable=self.node_count, width=28).grid(row=1, column=1, pady=5)

        # Deploy button
        ttk.Button(config_frame, text="Deploy Cluster",
                  command=self.deploy_cluster, style="Accent.TButton").pack(pady=10)

        # Deployment log
        log_frame = ttk.LabelFrame(self.deploy_tab, text="Deployment Progress", padding=10)
        log_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        self.deploy_log = scrolledtext.ScrolledText(log_frame, height=15)
        self.deploy_log.pack(fill=tk.BOTH, expand=True)

    def setup_monitor_tab(self):
        """Setup monitoring tab"""
        frame = ttk.LabelFrame(self.monitor_tab, text="Cluster Status", padding=10)
        frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        ttk.Button(frame, text="Refresh Status",
                  command=self.refresh_status).pack(pady=5)

        self.monitor_log = scrolledtext.ScrolledText(frame, height=20)
        self.monitor_log.pack(fill=tk.BOTH, expand=True)

    def log_output(self, widget, message, level="INFO"):
        """Log message to a text widget"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        formatted = f"[{timestamp}] [{level}] {message}\n"
        widget.insert(tk.END, formatted)
        widget.see(tk.END)
        widget.update()

    def run_command(self, command, log_widget, cwd=None):
        """Run a shell command and log output"""
        self.status_bar.config(text=f"Running: {command[:50]}...")

        try:
            process = subprocess.Popen(
                command,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                cwd=cwd
            )

            for line in process.stdout:
                self.log_output(log_widget, line.strip())

            process.wait()

            if process.returncode == 0:
                self.log_output(log_widget, "Command completed successfully", "SUCCESS")
                self.status_bar.config(text="Ready")
                return True
            else:
                self.log_output(log_widget, f"Command failed with code {process.returncode}", "ERROR")
                self.status_bar.config(text="Error")
                return False

        except Exception as e:
            self.log_output(log_widget, f"Error: {str(e)}", "ERROR")
            self.status_bar.config(text="Error")
            return False

    def setup_provisioning(self):
        """Setup provisioning server"""
        method = self.provisioning_method.get()

        def run():
            if method == "pxe":
                script = "./provisioning/pxe/setup-pxe-server.sh"
                if os.path.exists(script):
                    self.run_command(f"sudo {script}", self.setup_log)
                else:
                    self.log_output(self.setup_log, "PXE setup script not found. Please ensure you're in the SIAB directory.", "ERROR")
            else:
                script = "./provisioning/maas/setup-maas.sh"
                if os.path.exists(script):
                    self.run_command(f"sudo {script}", self.setup_log)
                else:
                    self.log_output(self.setup_log, "MAAS setup script not found. Please ensure you're in the SIAB directory.", "ERROR")

        threading.Thread(target=run, daemon=True).start()

    def discover_hardware(self):
        """Discover hardware on network"""
        subnet = self.subnet.get()

        def run():
            self.hardware_tree.delete(*self.hardware_tree.get_children())

            cmd = f"./provisioning/scripts/discover-hardware.sh --subnet {subnet}"
            if self.scan_ipmi.get():
                cmd += " --ipmi"
            if self.scan_pxe.get():
                cmd += " --pxe"
            cmd += " --output /tmp/siab-discovery.json"

            self.status_bar.config(text=f"Scanning {subnet}...")

            if self.run_command(cmd, self.setup_log):
                # Load results
                try:
                    with open("/tmp/siab-discovery.json", "r") as f:
                        results = json.load(f)

                    for host in results:
                        self.hardware_tree.insert("", tk.END, text="✓",
                                                 values=(
                                                     host.get("ip", ""),
                                                     host.get("mac", ""),
                                                     host.get("hostname", ""),
                                                     "Yes" if host.get("ipmi_available") else "No",
                                                     "Yes" if host.get("pxe_capable") else "No"
                                                 ))

                    self.status_bar.config(text=f"Found {len(results)} hosts")
                except Exception as e:
                    self.log_output(self.setup_log, f"Error loading results: {str(e)}", "ERROR")

        threading.Thread(target=run, daemon=True).start()

    def export_hardware(self):
        """Export hardware inventory to file"""
        filename = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")]
        )

        if filename:
            try:
                import shutil
                shutil.copy("/tmp/siab-discovery.json", filename)
                messagebox.showinfo("Success", f"Hardware inventory exported to {filename}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to export: {str(e)}")

    def deploy_cluster(self):
        """Deploy SIAB cluster"""
        method = self.provisioning_method.get()
        cluster_name = self.cluster_name.get()
        node_count = self.node_count.get()

        def run():
            cmd = f"./provisioning/scripts/provision-cluster.sh --method {method} --nodes {node_count} --cluster {cluster_name}"

            if method == "maas":
                api_key = self.maas_api_key.get()
                if api_key:
                    cmd = f"MAAS_API_KEY='{api_key}' {cmd}"

            self.run_command(cmd, self.deploy_log)

        threading.Thread(target=run, daemon=True).start()

    def refresh_status(self):
        """Refresh cluster status"""
        def run():
            self.monitor_log.delete(1.0, tk.END)

            commands = [
                ("kubectl get nodes", "Nodes"),
                ("kubectl get pods -A", "All Pods"),
                ("kubectl get siabapplications", "SIAB Applications")
            ]

            for cmd, title in commands:
                self.log_output(self.monitor_log, f"\n=== {title} ===", "INFO")
                self.run_command(cmd, self.monitor_log)

        threading.Thread(target=run, daemon=True).start()

def main():
    root = tk.Tk()

    # Style
    style = ttk.Style()
    style.theme_use('clam')

    # Custom button style
    style.configure("Accent.TButton",
                   background="#2563eb",
                   foreground="white",
                   borderwidth=0,
                   focuscolor='none',
                   padding=10)

    app = SIABProvisionerGUI(root)
    root.mainloop()

if __name__ == "__main__":
    main()
