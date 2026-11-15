"""Loopback-only TCP forwarding through an already authenticated SSH client."""

from contextlib import contextmanager
import select
import socketserver
import threading


@contextmanager
def tunnel(client, remote_port, local_port=0):
    class Forward(socketserver.BaseRequestHandler):
        def handle(self):
            channel = client.get_transport().open_channel(
                "direct-tcpip", ("127.0.0.1", remote_port), self.client_address, timeout=5)
            try:
                self.request.settimeout(120)
                channel.settimeout(120)
                while True:
                    readable, _, _ = select.select([self.request, channel], [], [], 120)
                    if not readable:
                        break
                    if self.request in readable:
                        data = self.request.recv(32768)
                        if not data:
                            break
                        channel.sendall(data)
                    if channel in readable:
                        data = channel.recv(32768)
                        if not data:
                            break
                        self.request.sendall(data)
            finally:
                channel.close()

    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True
        allow_reuse_address = False

    with Server(("127.0.0.1", local_port), Forward) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"127.0.0.1:{server.server_address[1]}"
        finally:
            server.shutdown()
            thread.join(2)
