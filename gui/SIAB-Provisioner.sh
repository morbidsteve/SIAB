#!/bin/bash
# SIAB Provisioner Launcher for Linux/macOS

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is required but not installed."
    echo "Please install Python 3 and try again."
    exit 1
fi

# Check if tkinter is available
if ! python3 -c "import tkinter" 2>/dev/null; then
    echo "Python tkinter module is required but not installed."
    echo ""
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt-get install python3-tk"
    echo "  Fedora/RHEL: sudo dnf install python3-tkinter"
    echo "  macOS: Should be included with Python"
    exit 1
fi

# Get the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run the GUI
python3 "$DIR/siab-provisioner-gui.py"
