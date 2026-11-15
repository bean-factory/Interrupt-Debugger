"""Transition-rendered digital waveforms; primary/compare data share time units."""

import numpy as np
import pyqtgraph as pg
import pyqtgraph.exporters
import math
from PySide6.QtCore import Signal
from PySide6 import QtCore, QtGui, QtSvg, QtWidgets

from .protocol import CHANNELS
from .theme import PLOT_BACKGROUND, PLOT_FOREGROUND, TRACE, COMPARISON, ANNOTATION, WARNING, CHANNEL_COLORS

pg.setConfigOptions(antialias=False, background=PLOT_BACKGROUND, foreground=PLOT_FOREGROUND)


def alignment_sample(capture):
    ir = (capture.samples >> 8) & 255
    edges = np.flatnonzero((ir[1:] & ~ir[:-1]) != 0)
    return int(edges[0] + 1) if len(edges) else 0


class WaveformView(pg.GraphicsLayoutWidget):
    event_selected = Signal(str)

    def __init__(self):
        super().__init__()
        self.plot = self.addPlot()
        self.plot.setLabel("bottom", "Time", units="µs")
        self.plot.showGrid(x=True, y=False, alpha=0.2)
        self.plot.setMouseEnabled(x=True, y=False)
        self.plot.hideButtons()
        self.plot.getAxis("bottom").enableAutoSIPrefix(False)
        self.axis_font = QtGui.QFont("Segoe UI", 9)
        for name in ("left", "bottom"):
            self.plot.getAxis(name).setStyle(tickFont=self.axis_font)
        self.capture = None
        self.events = []
        self.shift_us = 0
        self.duration_us = 1
        self.region = None
        self.zoom_labels = []
        self._comparison = None
        self._bounds = (0, 1)
        self.plot.sigXRangeChanged.connect(self._update_label_visibility)
        self.plot.vb.setMouseMode(pg.ViewBox.PanMode)
        self.plot.setMenuEnabled(False)
        self.viewport().grabGesture(QtCore.Qt.GestureType.PinchGesture)

    def pan_time(self, pixels):
        """Scroll without changing the time scale or vertical channel positions."""
        limits = self.plot.viewRange()[0]
        width = max(1.0, self.plot.vb.sceneBoundingRect().width())
        self.plot.vb.translateBy(x=-float(pixels) * (limits[1] - limits[0]) / width)

    def zoom_time(self, factor, position=None):
        if not math.isfinite(factor) or factor <= 0:
            return
        center = None
        if position is not None:
            center = self.plot.vb.mapSceneToView(self.mapToScene(position.toPoint()))
        self.plot.vb.scaleBy((max(0.1, min(10.0, factor)), 1.0), center=center)

    def viewportEvent(self, event):
        kind = event.type()
        if kind == QtCore.QEvent.Type.Wheel:
            pixels, angles = event.pixelDelta(), event.angleDelta()
            horizontal = pixels.x() or angles.x()
            if not horizontal and event.modifiers() & QtCore.Qt.KeyboardModifier.ControlModifier:
                # Windows may deliver trackpad pinch as Ctrl+wheel.
                delta = pixels.y() / 40 if pixels.y() else angles.y() / 120
                self.zoom_time(math.exp(-0.15 * delta), event.position())
            else:
                delta = (pixels.x() or pixels.y()) if not pixels.isNull() else (angles.x() or angles.y()) / 3
                self.pan_time(delta)
            event.accept()
            return True
        if kind == QtCore.QEvent.Type.NativeGesture:
            gesture = event.gestureType()
            if gesture == QtCore.Qt.NativeGestureType.ZoomNativeGesture:
                self.zoom_time(math.exp(-event.value()), event.position())
                event.accept()
                return True
            if gesture == QtCore.Qt.NativeGestureType.PanNativeGesture:
                delta = event.delta()
                self.pan_time(delta.x() or delta.y())
                event.accept()
                return True
        if kind == QtCore.QEvent.Type.Gesture:
            pinch = event.gesture(QtCore.Qt.GestureType.PinchGesture)
            if pinch:
                previous = pinch.lastScaleFactor()
                if previous > 0 and pinch.scaleFactor() > 0:
                    self.zoom_time(previous / pinch.scaleFactor())
                event.accept()
                return True
        return super().viewportEvent(event)

    def show_capture(self, capture, events, comparison=None, show_all=False):
        preserve_view = self.capture is capture and self._comparison is comparison
        previous_range = self.plot.viewRange()[0]
        self.capture, self.events = capture, events
        self._comparison = comparison
        self.zoom_labels = []
        self.plot.clear()
        self.plot.setLabel("bottom", "Time relative to request" if comparison is not None
                           else "Time from capture start", units="µs")
        self.plot.setLimits(xMin=-1e6, xMax=1e6)
        channels = [8+i for i in range(8) if show_all or np.any(capture.samples & (1 << (8+i)))
                    or (comparison is not None and np.any(comparison.samples & (1 << (8+i))))]
        channels += [16, 17, 18, 19, 20]
        if show_all:
            channels += list(range(8)) + [21]
        self.shift_us = alignment_sample(capture) / capture.sample_rate * 1e6 if comparison else 0
        ticks = []
        for row, bit in enumerate(channels):
            y = len(channels) - row + 5
            ticks.append((y + 0.3, CHANNELS[bit]))
            self._lane(capture, bit, y, self.shift_us, CHANNEL_COLORS.get(bit, TRACE))
            if comparison is not None:
                shift = alignment_sample(comparison) / comparison.sample_rate * 1e6
                self._lane(comparison, bit, y + 0.09, shift, COMPARISON, compare=True)
        ticks += [(4.3, "D[7:0]"), (3.2, "ACK"), (2.3, "Vector"), (1.3, "PIC commands")]
        if any(event.kind in ("warning", "diagnosis") for event in events):
            ticks.append((0.3, "Findings"))
        self.plot.getAxis("left").setTicks([ticks])
        label_width = QtGui.QFontMetricsF(self.axis_font).horizontalAdvance("PIC commands")
        self.plot.getAxis("left").setWidth(max(120, round(label_width) + 28))
        self.plot.setYRange(-0.35, len(channels)+6, padding=0.02)
        self._bus(events)
        spots = []
        for event in events:
            y = (3.2 if event.kind in ("ack1", "ack2") else 2.3 if event.kind == "vector"
                 else 1.3 if event.kind == "eoi" or event.description.startswith("IMR") else 0.3)
            if event.kind not in ("ack1", "ack2", "vector", "eoi", "warning", "diagnosis") and not event.description.startswith("IMR"):
                continue
            x = event.start / capture.sample_rate * 1e6 - self.shift_us
            color = WARNING if y < 1 else ANNOTATION
            spots.append({"pos": (x, y), "data": event.id, "brush": color})
            if event.kind in ("ack1", "ack2", "vector", "eoi") or event.description.startswith("IMR"):
                label = (event.kind.upper() if event.kind in ("ack1", "ack2") else
                          f"{event.fields['value']:02X}h" if event.kind == "vector" else
                          f"Mask {event.fields['value']:02X}h" if event.description.startswith("IMR") else event.description)
                text = pg.TextItem(label, color=color, anchor=(0, 1))
                text.setPos(x, y+0.1)
                self.plot.addItem(text)
                if event.kind in ("ack1", "ack2", "eoi") or event.description.startswith("IMR"):
                    self.zoom_labels.append(text)
        scatter = pg.ScatterPlotItem(size=9, symbol="t", pen=None)
        scatter.addPoints(spots)
        scatter.sigClicked.connect(lambda _item, points, _ev: self.event_selected.emit(points[0].data()))
        self.plot.addItem(scatter)
        self.region = pg.LinearRegionItem(values=(0, 0), movable=False, brush=(190, 190, 190, 32), pen=None)
        self.plot.addItem(self.region)
        self.region.hide()
        self.duration_us = len(capture.samples) / capture.sample_rate * 1e6
        self._bounds = (-self.shift_us, self.duration_us - self.shift_us)
        if comparison is not None:
            other_shift = alignment_sample(comparison) / comparison.sample_rate * 1e6
            self._bounds = (min(self._bounds[0], -other_shift),
                            max(self._bounds[1], len(comparison.samples) / comparison.sample_rate * 1e6 - other_shift))
        if preserve_view:
            self.plot.setXRange(*previous_range, padding=0)
        else:
            self.overview()
        self._update_label_visibility()

    def _bus(self, events):
        """Only label qualified reads, writes and vectors; leave other bus values unclaimed."""
        start, end = -self.shift_us, len(self.capture.samples) / self.capture.sample_rate * 1e6 - self.shift_us
        self.plot.plot([start, end], [4.3, 4.3], pen=pg.mkPen("#444444"))
        for event in events:
            if event.kind not in ("vector", "read", "write", "eoi") or "value" not in event.fields:
                continue
            a = event.start / self.capture.sample_rate * 1e6 - self.shift_us
            b = event.end / self.capture.sample_rate * 1e6 - self.shift_us
            rectangle = QtWidgets.QGraphicsRectItem(a, 4.02, max(b-a, 0.02), 0.56)
            rectangle.setPen(pg.mkPen("#888888"))
            rectangle.setBrush(pg.mkBrush("#303030"))
            self.plot.addItem(rectangle)
            label = pg.TextItem(f"{event.fields['value']:02X}h", color=PLOT_FOREGROUND, anchor=(0.5, 0.5))
            label.setPos((a+b)/2, 4.3)
            self.plot.addItem(label)
            self.zoom_labels.append(label)

    def _update_label_visibility(self, *_):
        limits = self.plot.viewRange()[0]
        for label in self.zoom_labels:
            label.setVisible(limits[1]-limits[0] < 20)

    def _lane(self, capture, bit, y, shift, color, compare=False):
        values = ((capture.samples >> bit) & 1).astype(np.uint8)
        changes = np.flatnonzero(values[1:] != values[:-1]) + 1
        boundaries = np.r_[0, changes, len(values)]
        levels = y + 0.65 * values[boundaries[:-1]]
        x = np.repeat(boundaries, 2)[1:-1] / capture.sample_rate * 1e6 - shift
        levels = np.repeat(levels, 2)
        pen = pg.mkPen(color, width=1.3)
        if compare:
            pen.setStyle(pg.QtCore.Qt.PenStyle.DashLine)
        self.plot.plot(x, levels, pen=pen)

    def overview(self):
        self.plot.setXRange(*self._bounds, padding=0.02)

    def select(self, event):
        if self.capture is None:
            return
        self.highlight(event)
        a = event.start / self.capture.sample_rate * 1e6 - self.shift_us
        b = event.end / self.capture.sample_rate * 1e6 - self.shift_us
        span = max(5.0, (b-a)*3)
        # Persistent request events extend to capture end; inspect their edge,
        # rather than zooming out to include the entire asserted level.
        if event.kind in ("request", "request_present", "int", "diagnosis"):
            span = 8.0
        self.plot.setXRange(a-span/3, a+span*2/3, padding=0)

    def highlight(self, event):
        a = event.start / self.capture.sample_rate * 1e6 - self.shift_us
        b = event.end / self.capture.sample_rate * 1e6 - self.shift_us
        self.region.setRegion((a, b))
        self.region.show()

    def export(self, path):
        if str(path).lower().endswith(".svg"):
            # Use Qt's SVG painter directly: pyqtgraph 0.14's path-rewriting
            # exporter is incompatible with some Qt 6.12 path encodings.
            source = self.plot.sceneBoundingRect()
            width = 1800
            height = max(1, round(width * source.height() / source.width()))
            generator = QtSvg.QSvgGenerator()
            generator.setFileName(str(path))
            generator.setSize(QtCore.QSize(width, height))
            generator.setViewBox(QtCore.QRect(0, 0, width, height))
            generator.setTitle("Interrupt Debugger waveform")
            painter = QtGui.QPainter()
            if not painter.begin(generator):
                raise OSError(f"Cannot export {path}")
            try:
                target = QtCore.QRectF(0, 0, width, height)
                painter.fillRect(target, QtGui.QColor(PLOT_BACKGROUND))
                self.scene().render(painter, target, source)
            finally:
                painter.end()
                # Axis pictures cache painter metrics. Discard the SVG painter's
                # cache before returning to the screen's device coordinates.
                for name in ("left", "bottom"):
                    self.plot.getAxis(name).setStyle(tickFont=self.axis_font)
        else:
            exporter = pg.exporters.ImageExporter(self.plot)
            exporter.parameters()["width"] = 1800
            exporter.export(str(path))
