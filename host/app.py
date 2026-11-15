"""Launch Interrupt Debugger from the project root: python -m host.app."""

import argparse
from pathlib import Path
import sys

from PySide6 import QtCore, QtWidgets

from .protocol import Capture
from .window import MainWindow as MainWindow
from .window import SerialWorker as SerialWorker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--open", type=Path)
    parser.add_argument("--screenshot", type=Path, help="Save a screenshot and exit")
    parser.add_argument("--bridge", help="Override the JTAG bridge endpoint, e.g. 127.0.0.1:9374")
    args = parser.parse_args()
    app = QtWidgets.QApplication(sys.argv[:1])
    app.setApplicationName("Interrupt Debugger")
    window = MainWindow(target="fpga_jtag" if args.bridge else None)
    if args.bridge:
        window.port.setCurrentText(args.bridge)
    if args.open:
        window.load_capture(Capture.load(args.open), args.open)
    window.show()
    if args.screenshot:
        def screenshot():
            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
            window.grab().save(str(args.screenshot))
            app.quit()
        QtCore.QTimer.singleShot(700, screenshot)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
