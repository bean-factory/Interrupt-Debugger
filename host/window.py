"""Capture workspace and serial acquisition controls."""

from html import escape
from pathlib import Path
import threading

from PySide6 import QtCore, QtGui, QtWidgets
from serial.tools import list_ports

from .capture import acquire, clear_device, hardware_metadata
from .explain import analyze, default_profile
from .jtag import acquire as acquire_jtag, clear_device as clear_jtag
from .plot import WaveformView
from .protocol import Capture
from .report import write_report
from .theme import apply_theme

SCENARIO_NAMES = {
    "normal": "Normal service",
    "priority": "Simultaneous requests",
    "masked": "IR3 masked",
    "masked_ir1": "IRQ1 masked",
    "missing_eoi": "Missing IR1 EOI",
}
EVENT_NAMES = {
    "request": "Request", "request_present": "Request present", "int": "INT",
    "ack1": "ACK1", "ack2": "ACK2", "ack_unknown": "Unpaired ACK",
    "vector": "Vector", "eoi": "EOI", "write": "PIC write", "read": "PIC read",
    "warning": "Warning", "diagnosis": "Finding",
}


def paragraph(text):
    return f"<p>{escape(str(text))}</p>"


def section(title, body):
    return f'<h3 style="font-size:11pt; color:#333333; margin-top:20px">{escape(title)}</h3>{body}'


class SerialWorker(QtCore.QThread):
    result = QtCore.Signal(object)
    failed = QtCore.Signal(str)
    progress = QtCore.Signal(int, int)
    cancelled = QtCore.Signal()

    def __init__(self, port, command, metadata):
        super().__init__()
        self.port = port
        self.command = command
        self.metadata = metadata
        self.cancel = threading.Event()

    def run(self):
        try:
            if self.metadata.get("target") == "fpga_jtag":
                if self.command == "R":
                    clear_jtag(self.port)
                    self.result.emit(None)
                else:
                    self.result.emit(acquire_jtag(self.port, self.command, self.metadata, 90 if self.command == "B" else 30,
                                                   self.cancel, self.progress.emit))
            elif self.command == "R":
                clear_device(self.port, self.metadata.get("serial_baud", 500000))
                self.result.emit(None)
            else:
                self.result.emit(acquire(self.port, self.command, self.metadata, 30,
                                         self.cancel, self.progress.emit))
        except InterruptedError:
            self.cancelled.emit()
        except Exception as exc:
            self.failed.emit(str(exc))


class MainWindow(QtWidgets.QMainWindow):
    def __init__(self, target=None):
        super().__init__()
        apply_theme(QtWidgets.QApplication.instance())
        self.setWindowTitle("Interrupt Debugger")
        self.resize(1440, 940)
        self.setMinimumSize(1000, 680)
        self.capture = None
        self.comparison = None
        self.events = []
        self.worker = None
        self.selected_id = None
        self.capture_path = None
        self.initial_target = target or ("fpga_jtag" if hardware_metadata().get("project_mode") == "fpga_hosted_8086_8259" else "external")
        self.last_serial_port = ""
        self.bridge_endpoint = hardware_metadata().get("jtag_bridge", "192.168.56.102:9374")
        central = QtWidgets.QWidget(objectName="workspace")
        layout = QtWidgets.QVBoxLayout(central)
        layout.setContentsMargins(16, 12, 16, 8)
        layout.setSpacing(10)
        self.setCentralWidget(central)
        self._build_header(layout)
        self._build_device_panel()
        self._build_source_bar(layout)
        self._build_workspace(layout)
        self.progress = QtWidgets.QProgressBar()
        self.progress.setMaximumWidth(160)
        self.progress.setTextVisible(False)
        self.progress.hide()
        self.statusBar().addPermanentWidget(self.progress)
        self.cancel_button = self._button("Cancel capture", lambda: self.start_serial("R"))
        self.cancel_button.hide()
        self.statusBar().addPermanentWidget(self.cancel_button)
        self._set_capture_actions(False)
        self._show_empty()
        self.refresh_ports()
        self.target.setCurrentIndex(self.target.findData(self.initial_target))
        self._target_changed()

    def _button(self, text, slot, shortcut=None, tooltip=None):
        button = QtWidgets.QPushButton(text)
        button.clicked.connect(slot)
        if shortcut:
            button.setShortcut(QtGui.QKeySequence(shortcut))
        button.setToolTip(tooltip or (f"{text} ({shortcut})" if shortcut else text))
        return button

    def _build_header(self, layout):
        header = QtWidgets.QFrame(objectName="header")
        row = QtWidgets.QHBoxLayout(header)
        row.setContentsMargins(0, 0, 0, 12)
        row.addWidget(QtWidgets.QLabel("Interrupt Debugger", objectName="brand"))
        row.addStretch()
        self.open_button = self._button("Open…", self.open, "Ctrl+O")
        self.save_button = self._button("Save…", self.save, "Ctrl+S")
        self.compare_button = self._button("Compare…", self.compare)
        self.export_button = self._button("Export…", self.export, "Ctrl+E")
        self.read_button = self._button("Read capture", lambda: self.start_serial("B"), "Ctrl+R",
                                        "Read the capture started with the physical NORTH button")
        self.read_button.setObjectName("primary")
        for button in (self.read_button, self.open_button, self.save_button, self.compare_button, self.export_button):
            row.addWidget(button)
        row.addSpacing(8)
        self.device_button = QtWidgets.QToolButton()
        self.device_button.setText("Device")
        self.device_button.setCheckable(True)
        self.device_button.setToolTip("Connection settings")
        self.device_button.toggled.connect(lambda checked: self.device_panel.setVisible(checked))
        row.addWidget(self.device_button)
        layout.addWidget(header)

    def _build_device_panel(self):
        self.device_panel = QtWidgets.QDialog(self)
        self.device_panel.setWindowTitle("Device settings")
        self.device_panel.resize(880, 300)
        self.device_panel.finished.connect(lambda _: self.device_button.setChecked(False))
        row = QtWidgets.QHBoxLayout(self.device_panel)
        row.setContentsMargins(12, 8, 12, 12)
        serial = QtWidgets.QGroupBox("Connection")
        form = QtWidgets.QFormLayout(serial)
        self.connection_form = form
        self.target = QtWidgets.QComboBox()
        self.target.addItem("FPGA-hosted · USB-JTAG", "fpga_jtag")
        self.target.addItem("FPGA-hosted · RS-232 (optional)", "fpga_hosted")
        self.target.addItem("External trainer analyzer", "external")
        form.addRow("System", self.target)
        if self.initial_target == "fpga_jtag":
            self.target.hide()
            form.labelForField(self.target).hide()
        ports = QtWidgets.QHBoxLayout()
        self.port = QtWidgets.QComboBox()
        self.port.setEditable(True)
        self.port.setMinimumWidth(130)
        self.port.setToolTip("COM port for the selected system; 8 data bits, no parity, one stop bit")
        ports.addWidget(self.port)
        self.refresh_button = self._button("Refresh", self.refresh_ports)
        ports.addWidget(self.refresh_button)
        self.port_label = QtWidgets.QLabel("Serial port")
        form.addRow(self.port_label, ports)
        self.baud = QtWidgets.QComboBox()
        self.baud.addItem("115,200 baud", 115200)
        self.baud.addItem("500,000 baud", 500000)
        form.addRow("Link speed", self.baud)
        self.capture_mode = QtWidgets.QComboBox()
        for label, command in (("Passive observation", "A"), ("Sequential IR1 / IR3", "C"),
                               ("Simultaneous IR1 + IR3", "P")):
            self.capture_mode.addItem(label, command)
        self.capture_mode.currentIndexChanged.connect(self._mode_changed)
        form.addRow("Capture mode", self.capture_mode)
        buttons = QtWidgets.QHBoxLayout()
        self.acquire_button = self._button("Arm capture", lambda: self.start_serial(self.capture_mode.currentData()))
        self.acquire_button.setObjectName("primary")
        self.clear_button = self._button("Clear", lambda: self.start_serial("R"), tooltip="Clear generated requests and disarm the FPGA")
        buttons.addWidget(self.acquire_button)
        buttons.addWidget(self.clear_button)
        form.addRow(buttons)
        row.addWidget(serial, 2)
        self.target_group = QtWidgets.QGroupBox("Target setup")
        target = QtWidgets.QVBoxLayout(self.target_group)
        self.firmware = QtWidgets.QComboBox()
        for label, scenario in (("Normal service", "normal"), ("IR3 masked", "masked"),
                                ("Missing IR1 EOI", "missing_eoi")):
            self.firmware.addItem(label, scenario)
        self.firmware.setToolTip("Selects a program built into the FPGA image; each capture resets the CPU and PIC")
        target.addWidget(self.firmware)
        self.profile = QtWidgets.QComboBox()
        self.profile.addItems(["Unknown PIC configuration", "Normal · base 20h, mask F5h", "IR3 masked · base 20h, mask FDh"])
        self.profile.setToolTip("An operator-supplied starting state, not a firmware loader")
        self.profile.currentIndexChanged.connect(lambda _: self.confirm_profile.setChecked(False))
        target.addWidget(self.profile)
        self.confirm_profile = QtWidgets.QCheckBox("PIC reinitialized; no pending or in-service IRQs")
        self.confirm_profile.setToolTip("Confirm the selected edge-triggered, single-PIC, fixed-priority, manual-EOI configuration before each run.")
        self.confirm_hardware = QtWidgets.QCheckBox("Voltage levels checked; IR1 / IR3 drivers isolated")
        self.confirm_hardware.setToolTip("Verify level translators, common ground and physical injection-enable switch. Never parallel push-pull drivers.")
        target.addWidget(self.confirm_profile)
        target.addWidget(self.confirm_hardware)
        self.safety_note = QtWidgets.QLabel("Passive mode does not generate interrupt requests.", objectName="muted")
        self.safety_note.setWordWrap(True)
        target.addWidget(self.safety_note)
        row.addWidget(self.target_group, 3)
        self.device_panel.hide()
        self.target.currentIndexChanged.connect(self._target_changed)

    def _target_changed(self):
        jtag = self.target.currentData() == "fpga_jtag"
        hosted = self.target.currentData() != "external"
        self.target_group.setTitle("Built-in firmware" if hosted else "Target setup")
        self.firmware.setVisible(hosted)
        for widget in (self.profile, self.confirm_profile, self.confirm_hardware):
            widget.setVisible(not hosted)
        self.confirm_profile.setChecked(False)
        self.confirm_hardware.setChecked(False)
        self.baud.setCurrentIndex(0 if hosted else 1)
        self.baud.setVisible(not jtag)
        self.connection_form.labelForField(self.baud).setVisible(not jtag)
        self.baud.setEnabled(not hosted)
        self.refresh_button.setVisible(not jtag)
        self.capture_mode.setVisible(not jtag)
        self.connection_form.labelForField(self.capture_mode).setVisible(not jtag)
        self.acquire_button.setVisible(not jtag)
        self.clear_button.setVisible(not jtag)
        self.port_label.setText("Bridge address" if jtag else "Serial port")
        if jtag:
            if ":" not in self.port.currentText():
                self.last_serial_port = self.port.currentText()
                self.port.clear()
                self.port.setEditText(self.bridge_endpoint)
            self.port.setToolTip("Host-only address of the ISE VM JTAG bridge, as host:port")
        else:
            if ":" in self.port.currentText():
                self.bridge_endpoint = self.port.currentText()
                self.port.clear()
                self.port.setEditText(self.last_serial_port)
            self.port.setToolTip("COM port for the serial adapter")
        self.capture_mode.blockSignals(True)
        self.capture_mode.clear()
        if not hosted:
            self.capture_mode.addItem("Passive observation", "A")
        if jtag:
            self.capture_mode.addItem("Board switches + Start", "B")
        if not jtag:
            self.capture_mode.addItem("Sequential IR1 / IR3", "C")
            self.capture_mode.addItem("Simultaneous IR1 + IR3", "P")
        self.capture_mode.blockSignals(False)
        self._mode_changed()

    def _build_source_bar(self, layout):
        frame = QtWidgets.QFrame(objectName="sourceBar")
        row = QtWidgets.QHBoxLayout(frame)
        row.setContentsMargins(12, 8, 12, 8)
        self.banner = QtWidgets.QLabel("NO CAPTURE", objectName="sourceBadge")
        self.source_title = QtWidgets.QLabel("Open a capture or connect the board")
        self.source_title.setTextFormat(QtCore.Qt.TextFormat.PlainText)
        self.metrics = QtWidgets.QLabel("", objectName="muted")
        row.addWidget(self.banner)
        row.addWidget(self.source_title)
        row.addStretch()
        row.addWidget(self.metrics)
        layout.addWidget(frame)

    def _build_workspace(self, layout):
        horizontal = QtWidgets.QSplitter(QtCore.Qt.Orientation.Horizontal)
        horizontal.setChildrenCollapsible(False)
        left = QtWidgets.QSplitter(QtCore.Qt.Orientation.Vertical)
        left.setChildrenCollapsible(False)
        wave_panel = QtWidgets.QWidget()
        wave_layout = QtWidgets.QVBoxLayout(wave_panel)
        wave_layout.setContentsMargins(0, 0, 0, 0)
        wave_layout.setSpacing(6)
        tools = QtWidgets.QHBoxLayout()
        tools.addWidget(QtWidgets.QLabel("Waveforms"))
        tools.addStretch()
        self.all_channels = QtWidgets.QCheckBox("All channels")
        self.all_channels.toggled.connect(self.redraw)
        self.fit_button = self._button("Fit capture", lambda: self.waveforms.overview(), "Home")
        self.remove_comparison_button = self._button("Remove comparison", self.remove_comparison)
        self.remove_comparison_button.hide()
        for widget in (self.remove_comparison_button, self.all_channels, self.fit_button):
            tools.addWidget(widget)
        wave_layout.addLayout(tools)
        self.wave_stack = QtWidgets.QStackedWidget()
        empty = QtWidgets.QWidget()
        empty_layout = QtWidgets.QVBoxLayout(empty)
        empty_layout.addStretch()
        title = QtWidgets.QLabel("No capture loaded")
        title.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("font-size:18px; font-weight:600; color:#555555")
        empty_layout.addWidget(title)
        hint = QtWidgets.QLabel("Open a saved packet or connect the board.", objectName="muted")
        hint.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        empty_layout.addWidget(hint)
        empty_layout.addStretch()
        self.wave_stack.addWidget(empty)
        self.waveforms = WaveformView()
        self.waveforms.event_selected.connect(self.select_id)
        self.wave_stack.addWidget(self.waveforms)
        wave_layout.addWidget(self.wave_stack)
        left.addWidget(wave_panel)
        events_panel = QtWidgets.QWidget()
        events_layout = QtWidgets.QVBoxLayout(events_panel)
        events_layout.setContentsMargins(0, 6, 0, 0)
        events_layout.setSpacing(6)
        event_tools = QtWidgets.QHBoxLayout()
        self.event_count = QtWidgets.QLabel("Events")
        event_tools.addWidget(self.event_count)
        event_tools.addStretch()
        events_layout.addLayout(event_tools)
        self.table = QtWidgets.QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["Time (µs)", "Event", "Basis", "Description"])
        self.table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QtWidgets.QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setAlternatingRowColors(True)
        self.table.setShowGrid(False)
        self.table.setWordWrap(False)
        self.table.verticalHeader().hide()
        self.table.verticalHeader().setDefaultSectionSize(34)
        self.table.horizontalHeader().setSectionResizeMode(3, QtWidgets.QHeaderView.ResizeMode.Stretch)
        for column, width in enumerate((100, 120, 100)):
            self.table.setColumnWidth(column, width)
        self.table.itemSelectionChanged.connect(self._table_selection_changed)
        events_layout.addWidget(self.table)
        left.addWidget(events_panel)
        left.setSizes([540, 220])
        horizontal.addWidget(left)
        self.inspector = QtWidgets.QTabWidget()
        self.inspector.setMinimumWidth(290)
        self.details = QtWidgets.QTextBrowser()
        self.state_details = QtWidgets.QTextBrowser()
        for browser in (self.details, self.state_details):
            browser.setOpenExternalLinks(False)
        self.inspector.addTab(self.details, "Event")
        self.inspector.addTab(self.state_details, "PIC state")
        horizontal.addWidget(self.inspector)
        horizontal.setSizes([1050, 330])
        horizontal.setStretchFactor(0, 1)
        horizontal.setStretchFactor(1, 0)
        layout.addWidget(horizontal, 1)

    def _show_empty(self):
        self.details.setHtml(section("Event details", paragraph("Select an event in a loaded capture.")))
        self.state_details.setHtml(section("PIC state", paragraph("State tracking requires a capture and a known PIC configuration.")))
        self.statusBar().showMessage("Ready")

    def _set_capture_actions(self, enabled):
        for widget in (self.save_button, self.compare_button, self.export_button,
                       self.fit_button, self.all_channels):
            widget.setEnabled(enabled)

    def refresh_ports(self):
        previous = self.port.currentText()
        self.port.clear()
        for port in list_ports.comports():
            self.port.addItem(port.device)
            self.port.setItemData(self.port.count() - 1, port.description, QtCore.Qt.ItemDataRole.ToolTipRole)
        if previous:
            self.port.setCurrentText(previous)
        self.port.lineEdit().setPlaceholderText("COM port")

    def _mode_changed(self):
        jtag = self.target.currentData() == "fpga_jtag"
        hosted = self.target.currentData() != "external"
        passive = self.capture_mode.currentData() == "A"
        board = jtag and self.capture_mode.currentData() == "B"
        self.acquire_button.setText("Read board capture" if board else "Arm capture" if passive else "Capture")
        self.firmware.setEnabled(not board)
        self.target_group.setVisible(not board)
        if jtag:
            self.device_panel.resize(640 if board else 880, 280 if board else 300)
        self.confirm_hardware.setVisible(not hosted and not passive)
        self.confirm_hardware.setChecked(False)
        self.confirm_profile.setChecked(False)
        self.safety_note.setText("USB-JTAG. SW3 on; select SW1:SW0, press NORTH, then read the capture." if board else
                                "SW3 off. GUI capture resets the CPU and PIC." if jtag else
                                "Uses the board's RS-232 DCE port. Captures include CPU/PIC initialization; no external trainer is needed." if hosted else
                                "Passive mode does not generate interrupt requests." if passive
                                 else "Capture drives IR1 / IR3. Enable injection only after checking the interface.")

    def notify(self, text):
        dialog = QtWidgets.QMessageBox(self)
        dialog.setWindowTitle("Interrupt Debugger")
        dialog.setIcon(QtWidgets.QMessageBox.Icon.Warning)
        dialog.setTextFormat(QtCore.Qt.TextFormat.PlainText)
        dialog.setText(str(text))
        dialog.exec()

    def load_capture(self, capture, path=None):
        self.capture = capture
        self.capture_path = Path(path) if path else None
        self.comparison = None
        self.selected_id = None
        self.events = analyze(capture)
        synthetic = bool(capture.metadata.get("synthetic"))
        self.banner.setText("SYNTHETIC" if synthetic else "RECORDED")
        self.banner.setProperty("recorded", not synthetic)
        self.banner.style().unpolish(self.banner)
        self.banner.style().polish(self.banner)
        self.banner.setToolTip("Generated data, not a measurement of the trainer." if synthetic
                               else "Recorded packet; inspect the Capture tab for its origin and configuration.")
        scenario = capture.metadata.get("scenario")
        title = SCENARIO_NAMES.get(scenario, self.capture_path.parent.name if self.capture_path else "Serial capture")
        if not synthetic and capture.metadata.get("target") == "fpga_jtag":
            requested = capture.metadata.get("requested_scenario", "normal")
            if capture.metadata.get("board_mode"):
                condition = SCENARIO_NAMES.get(capture.metadata["board_mode"], "Board capture")
                timing = "simultaneous" if capture.flags & 8 else "sequential"
                title = f"{condition} · {timing} · Board Start"
            elif requested == "normal" and capture.flags & 8:
                requested = "priority"
                title = SCENARIO_NAMES[requested] + " · USB-JTAG"
            else:
                title = SCENARIO_NAMES.get(requested, "FPGA capture") + " · USB-JTAG"
        if synthetic and scenario not in SCENARIO_NAMES:
            title = capture.metadata.get("origin", "Generated capture")
        self.source_title.setText(title)
        self.metrics.setText(f"{len(capture.samples):,} samples · {capture.sample_rate / 1e6:g} MS/s · {len(capture.samples) / capture.sample_rate * 1e6:.2f} µs")
        self.table.blockSignals(True)
        self.table.clearSelection()
        self.table.setCurrentCell(-1, -1)
        self.table.setRowCount(len(self.events))
        for row, event in enumerate(self.events):
            cells = (f"{event.start / capture.sample_rate * 1e6:.3f}",
                     EVENT_NAMES.get(event.kind, event.kind), event.confidence.capitalize(), event.description)
            for column, text in enumerate(cells):
                item = QtWidgets.QTableWidgetItem(text)
                item.setToolTip(text)
                if column == 0:
                    item.setTextAlignment(QtCore.Qt.AlignmentFlag.AlignRight | QtCore.Qt.AlignmentFlag.AlignVCenter)
                self.table.setItem(row, column, item)
        self.table.blockSignals(False)
        self.table.scrollToTop()
        self.event_count.setText(f"Events · {len(self.events)}")
        self._set_capture_actions(True)
        self.remove_comparison_button.hide()
        self.wave_stack.setCurrentIndex(1)
        self.redraw()
        findings = [e.description for e in self.events if e.kind in ("diagnosis", "warning")]
        if not self.events and capture.metadata.get("target") in ("fpga_hosted", "fpga_jtag"):
            findings.append("No interrupt or PIC bus activity was observed. A valid packet does not prove CPU startup.")
        body = "".join(paragraph(text) for text in findings)
        self.details.setHtml(section("Capture findings" if findings else "Event details", body)
                             + paragraph("Select an event to inspect its timing and evidence."))
        self.state_details.setHtml(section("PIC state", paragraph("Select an event to view the tracked state at that point.")))
        self.statusBar().showMessage("Capture loaded")

    def redraw(self, *_):
        if self.capture:
            self.waveforms.show_capture(self.capture, self.events, self.comparison, self.all_channels.isChecked())
            if self.selected_id:
                selected = next((event for event in self.events if event.id == self.selected_id), None)
                if selected:
                    self.waveforms.highlight(selected)

    def _table_selection_changed(self):
        rows = self.table.selectionModel().selectedRows()
        if rows:
            self.select_row(rows[0].row())

    def select_row(self, row, _column=0):
        if not 0 <= row < len(self.events):
            return
        event = self.events[row]
        self.selected_id = event.id
        self.waveforms.select(event)
        self.inspector.setCurrentIndex(0)
        by_id = {item.id: item for item in self.events}
        supporting = [by_id[item] for item in event.evidence if item in by_id] or [event]
        evidence = "".join(paragraph(f"{item.start / self.capture.sample_rate * 1e6:.3f} µs · {item.description}") for item in supporting)
        content = f"<h2 style='font-size:14pt'>{escape(event.description)}</h2>"
        content += paragraph(f"{event.confidence.capitalize()} · {event.start / self.capture.sample_rate * 1e6:.3f} µs")
        if event.why:
            content += section("Interpretation", paragraph(event.why))
        content += section("Evidence", evidence)
        fields = {"value": "Value", "irq": "IRQ", "a0": "Register select (A0)",
                  "eoi_irq": "EOI level", "int_to_ack_us": "INT to ACK1 (µs)"}
        rows = []
        for key, label in fields.items():
            if key in event.fields:
                value = event.fields[key]
                if key == "value" and isinstance(value, int):
                    value = f"{value:02X}h"
                elif isinstance(value, float):
                    value = f"{value:.3f}"
                rows.append(f"<tr><td style='padding:4px 14px 4px 0'>{label}</td><td>{escape(str(value))}</td></tr>")
        if rows:
            content += section("Decoded values", "<table>" + "".join(rows) + "</table>")
        self.details.setHtml(content)
        self.details.verticalScrollBar().setValue(0)
        self._state_information(event)

    def _state_information(self, event):
        def value(key):
            number = event.state.get(key)
            return f"{number:02X}h" if isinstance(number, int) else "Unknown"
        content = section("Tracked PIC state", paragraph("After the selected event. These values are model predictions, updated by captured commands and register reads."))
        content += "<table cellpadding='5'>" + "".join(
            f"<tr><td>{label}</td><td><b>{value(key)}</b></td></tr>" for label, key in (
                ("Mask (IMR)", "mask"), ("In service (ISR)", "predicted_isr"),
                ("Pending", "predicted_pending"), ("Vector base", "vector_base"))) + "</table>"
        if not event.state.get("model_known"):
            content += paragraph("Configuration or history is incomplete. State-based conclusions are unavailable.")
        content += section("Configuration source", paragraph(event.state.get("context", "Unknown")))
        self.state_details.setHtml(content)

    def select_id(self, event_id):
        for row, event in enumerate(self.events):
            if event.id == event_id:
                already_selected = self.table.currentRow() == row and bool(self.table.selectedItems())
                self.table.selectRow(row)
                self.table.scrollToItem(self.table.item(row, 0))
                if already_selected:
                    self.select_row(row)
                break

    def start_serial(self, command):
        if self.worker is not None:
            if command == "R":
                self.worker.cancel.set()
                self.clear_button.setEnabled(False)
                self.cancel_button.setEnabled(False)
                self.statusBar().showMessage("Cancelling capture…")
            return
        if self.target.currentData() == "fpga_jtag" and command not in ("B", "R"):
            self.notify("Start the experiment using the physical switches and NORTH button, then read the capture.")
            return
        port = self.port.currentText().strip()
        if not port:
            self.notify("Enter the connection address in Device settings.")
            return
        hosted = self.target.currentData() != "external"
        if hosted and command == "A":
            self.notify("Choose sequential or simultaneous capture for the FPGA-hosted system.")
            return
        if command in ("C", "P") and not hosted:
            if not self.profile.currentIndex() or not self.confirm_profile.isChecked():
                self.notify("Choose the PIC configuration and confirm that the target was reinitialized.")
                return
            if not self.confirm_hardware.isChecked():
                self.notify("Check the level translators, common ground and injection-enable switch. Isolate the original IR1 / IR3 drivers before enabling stimulus.")
                return
        metadata = {"profile": None, "target": self.target.currentData()}
        if self.target.currentData() != "fpga_jtag":
            metadata["serial_baud"] = self.baud.currentData()
        if hosted:
            metadata["requested_scenario"] = self.firmware.currentData()
        if not hosted and self.profile.currentIndex() and self.confirm_profile.isChecked():
            metadata["profile"] = default_profile(0xFD if self.profile.currentIndex() == 2 else 0xF5)
            metadata["profile"]["provenance"] = "Operator-confirmed initial configuration; initialization not captured."
        self.confirm_profile.setChecked(False)
        self.confirm_hardware.setChecked(False)
        self.worker = SerialWorker(port, command, metadata)
        self.worker.result.connect(self.serial_result)
        self.worker.failed.connect(self.serial_error)
        self.worker.cancelled.connect(lambda: self.statusBar().showMessage("Capture cancelled. Partial data discarded."))
        self.worker.progress.connect(self._serial_progress)
        self.worker.finished.connect(self.worker_finished)
        self.device_button.setChecked(True)
        for widget in (self.read_button, self.acquire_button, self.port, self.refresh_button, self.capture_mode, self.target, self.baud,
                       self.target_group, self.device_button,
                       self.open_button, self.compare_button):
            widget.setEnabled(False)
        self.clear_button.setText("Cancel")
        self.progress.setRange(0, 0)
        self.progress.show()
        self.cancel_button.setEnabled(True)
        self.cancel_button.show()
        self.statusBar().showMessage("Waiting for board Start…" if command == "B" else "Waiting for trigger…" if command == "A" else "Clearing device…" if command == "R" else "Acquiring…")
        self.worker.start()

    def _serial_progress(self, received, total):
        self.progress.setRange(0, total)
        self.progress.setValue(received)
        self.statusBar().showMessage(f"Receiving capture · {received:,} / {total:,} bytes")

    def serial_result(self, capture):
        if capture is not None:
            self.load_capture(capture)
            self.device_button.setChecked(False)
            self.statusBar().showMessage(f"Read {len(capture.samples):,} samples · CRC verified · NORTH starts a new capture")
        else:
            self.statusBar().showMessage("Experiment reset." if self.target.currentData() != "external" else
                                         "Requests cleared. Reinitialize the PIC before the next stimulus capture.")

    def serial_error(self, message):
        self.statusBar().showMessage("Capture failed")
        self.notify(message)

    def worker_finished(self):
        worker = self.worker
        self.worker = None
        if worker:
            worker.deleteLater()
        for widget in (self.read_button, self.acquire_button, self.port, self.refresh_button, self.capture_mode, self.target, self.baud,
                       self.target_group, self.device_button,
                       self.open_button, self.clear_button):
            widget.setEnabled(True)
        self.compare_button.setEnabled(self.capture is not None)
        self.baud.setEnabled(self.target.currentData() == "external")
        self.clear_button.setText("Clear")
        self.progress.hide()
        self.cancel_button.hide()

    def save(self):
        if not self.capture:
            return
        path = QtWidgets.QFileDialog.getExistingDirectory(self, "Save capture to folder")
        if path:
            destination = Path(path)
            if (destination / "capture.bin").exists() and QtWidgets.QMessageBox.question(
                    self, "Replace capture?", "This folder already contains a capture. Replace it?") != QtWidgets.QMessageBox.StandardButton.Yes:
                return
            try:
                self.save_to(destination)
            except Exception as exc:
                self.notify(str(exc))

    def save_to(self, destination):
        """Save the primary packet, reports and overview without changing the viewport."""
        destination = Path(destination)
        self.capture.save(destination)
        write_report(self.capture, destination, self.events)
        limits = self.waveforms.plot.viewRange()[0]
        try:
            self.waveforms.overview()
            self.waveforms.export(destination / "overview.png")
            self.waveforms.export(destination / "overview.svg")
        finally:
            self.waveforms.plot.setXRange(*limits, padding=0)
        self.statusBar().showMessage(f"Saved to {destination}")

    def open(self):
        path, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Open capture", "", "Interrupt Debugger capture (*.bin)")
        if path:
            try:
                self.load_capture(Capture.load(path), path)
            except Exception as exc:
                self.notify(str(exc))

    def compare(self):
        if not self.capture:
            return
        path, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Compare capture", "", "Interrupt Debugger capture (*.bin)")
        if path:
            try:
                self.set_comparison(Capture.load(path))
            except Exception as exc:
                self.notify(str(exc))

    def set_comparison(self, capture):
        self.comparison = capture
        self.remove_comparison_button.show()
        self.redraw()
        self.statusBar().showMessage("Dashed trace: comparison. Aligned to first request; events refer to the primary capture.")

    def remove_comparison(self):
        self.comparison = None
        self.remove_comparison_button.hide()
        self.redraw()
        self.statusBar().showMessage("Comparison removed")

    def export(self):
        if not self.capture:
            return
        path, selected_filter = QtWidgets.QFileDialog.getSaveFileName(self, "Export waveform", "waveform.png", "PNG (*.png);;SVG (*.svg)")
        if path:
            suffix = ".svg" if "SVG" in selected_filter else ".png"
            destination = Path(path)
            if not destination.suffix:
                destination = destination.with_suffix(suffix)
            try:
                self.waveforms.export(destination)
                self.statusBar().showMessage(f"Exported {destination.name}")
            except Exception as exc:
                self.notify(str(exc))

    def closeEvent(self, event):
        if self.worker is not None:
            self.worker.cancel.set()
            if not self.worker.wait(1500):
                self.statusBar().showMessage("Waiting for capture to stop…")
                event.ignore()
                return
        event.accept()
