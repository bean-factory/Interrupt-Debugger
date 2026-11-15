"""Shared application and waveform colors."""

import os
from pathlib import Path
import sys

from PySide6 import QtGui

PLOT_BACKGROUND = "#191919"
PLOT_FOREGROUND = "#d6d6d6"
TRACE = "#e0e0e0"
COMPARISON = "#929292"
ANNOTATION = "#c8c8c8"
WARNING = "#d4af73"
CHANNEL_COLORS = {
    8: "#9bc77e", 9: "#62c9a5", 10: "#e6aa6b", 11: "#cb98e6",
    12: "#e98f98", 13: "#d6d270", 14: "#80bce6", 15: "#dda3c2",
    16: "#e9bf6a", 17: "#82b9ed", 18: "#e99a85", 19: "#d1cf82",
    20: "#ada1e7", 21: "#bcbcbc",
}

STYLESHEET = """
QMainWindow, QWidget#workspace { background: #f4f4f4; color: #262626; }
QWidget { font-family: 'Segoe UI', sans-serif; font-size: 10pt; }
QLabel#brand { font-size: 17pt; font-weight: 600; color: #202020; }
QLabel#muted { color: #737373; }
QFrame#header { background: white; border-bottom: 1px solid #dedede; }
QFrame#sourceBar { background: white; border: 1px solid #dedede; border-radius: 4px; }
QLabel#sourceBadge { color: #665233; background: #f5efe4; border-radius: 3px;
                    padding: 4px 8px; font-size: 9pt; font-weight: 600; }
QLabel#sourceBadge[recorded=true] { color: #404040; background: #ededed; }
QPushButton, QToolButton { background: white; color: #333333; border: 1px solid #d4d4d4;
                         border-radius: 4px; padding: 6px 12px; min-height: 18px; }
QPushButton:hover, QToolButton:hover { background: #eeeeee; border-color: #aaaaaa; }
QPushButton:pressed, QToolButton:checked { background: #e5e5e5; }
QPushButton:disabled, QToolButton:disabled { color: #a3a3a3; border-color: #e5e5e5; background: #f7f7f7; }
QPushButton#primary { background: #333333; color: white; border-color: #333333; font-weight: 600; }
QPushButton#primary:hover { background: #474747; }
QPushButton#primary:disabled { background: #bfbfbf; border-color: #bfbfbf; }
QComboBox, QLineEdit { background: white; color: #262626; border: 1px solid #d4d4d4;
                      border-radius: 4px; padding: 6px 8px; min-height: 18px; }
QComboBox:focus, QLineEdit:focus { border-color: #777777; }
QComboBox::drop-down { border: 0; width: 22px; }
QCheckBox { spacing: 7px; color: #404040; }
QCheckBox::indicator { width: 14px; height: 14px; }
QCheckBox::indicator:unchecked { background: white; border: 1px solid #aaaaaa; border-radius: 2px; }
QGroupBox { border: 1px solid #dedede; border-radius: 4px; margin-top: 12px;
            padding: 15px 10px 10px; background: white; font-weight: 600; }
QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 4px; }
QTabWidget::pane { background: white; border: 1px solid #dedede; border-top: 0; }
QTabBar::tab { background: #eeeeee; color: #707070; padding: 9px 15px; border-bottom: 2px solid transparent; }
QTabBar::tab:selected { color: #262626; background: white; border-bottom: 2px solid #555555; }
QTextBrowser { background: white; border: 0; padding: 12px; color: #333333; }
QTableWidget { background: white; alternate-background-color: #f8f8f8; border: 1px solid #dedede;
               gridline-color: #eeeeee; selection-background-color: #e5e5e5; selection-color: #202020; }
QTableWidget::item { padding: 6px 9px; border: 0; }
QHeaderView::section { background: #f6f6f6; color: #707070; border: 0;
                       border-bottom: 1px solid #dedede; padding: 8px 9px; font-weight: 600; }
QSplitter::handle { background: #e5e5e5; }
QSplitter::handle:horizontal { width: 1px; }
QSplitter::handle:vertical { height: 1px; }
QStatusBar { background: #eeeeee; color: #707070; border-top: 1px solid #dedede; }
QStatusBar::item { border: 0; }
QProgressBar { border: 1px solid #d9d9d9; border-radius: 3px; background: white; max-height: 8px; }
QProgressBar::chunk { background: #777777; }
QMenu { background: white; color: #333333; border: 1px solid #d4d4d4; padding: 4px; }
QMenu::item { padding: 7px 24px; }
QMenu::item:selected { background: #e5e5e5; }
QToolTip { color: #262626; background: #fff; border: 1px solid #d4d4d4; padding: 5px; }
"""


def apply_theme(app):
    # Windows' offscreen Qt plugin does not enumerate system fonts like the
    # native windows plugin. Register installed fonts for readable headless QA;
    # no font files are bundled or copied into the project.
    if sys.platform == "win32" and app.platformName() == "offscreen" and not app.property("interrupt_debugger_fonts_loaded"):
        fonts = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
        for name in ("segoeui.ttf", "segoeuib.ttf", "seguisb.ttf", "segoeuii.ttf"):
            path = fonts / name
            if path.exists():
                QtGui.QFontDatabase.addApplicationFont(str(path))
        app.setProperty("interrupt_debugger_fonts_loaded", True)
    app.setStyle("Fusion")
    app.setFont(QtGui.QFont("Segoe UI", 10))
    palette = app.palette()
    palette.setColor(QtGui.QPalette.ColorRole.Window, QtGui.QColor("#f4f4f4"))
    palette.setColor(QtGui.QPalette.ColorRole.WindowText, QtGui.QColor("#262626"))
    palette.setColor(QtGui.QPalette.ColorRole.Text, QtGui.QColor("#262626"))
    palette.setColor(QtGui.QPalette.ColorRole.Base, QtGui.QColor("white"))
    palette.setColor(QtGui.QPalette.ColorRole.Button, QtGui.QColor("#ffffff"))
    palette.setColor(QtGui.QPalette.ColorRole.ButtonText, QtGui.QColor("#333333"))
    palette.setColor(QtGui.QPalette.ColorRole.Highlight, QtGui.QColor("#dedede"))
    palette.setColor(QtGui.QPalette.ColorRole.HighlightedText, QtGui.QColor("#202020"))
    palette.setColor(QtGui.QPalette.ColorRole.Link, QtGui.QColor("#444444"))
    app.setPalette(palette)
    app.setStyleSheet(STYLESHEET)
