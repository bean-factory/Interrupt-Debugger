"""Start the VM bridge, an SSH tunnel and the GUI as one managed session.

Never programs, resets, starts or reads the FPGA by itself.
"""
import argparse
from contextlib import contextmanager
import getpass
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import threading
import uuid

import paramiko

from jtag_tunnel import tunnel

ROOT = Path(__file__).resolve().parents[1]


def connect(config):
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.load_host_keys(str(ROOT / 'config/known_hosts'))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    password = os.environ.get('ISE_VM_PASSWORD')
    options = dict(hostname=config['host'], username=config['user'], timeout=10,
                   auth_timeout=10, banner_timeout=10)
    try:
        try:
            client.connect(**options, password=password,
                           allow_agent=not bool(password), look_for_keys=not bool(password))
        except paramiko.SSHException as exc:
            if password or (not isinstance(exc, paramiko.AuthenticationException) and
                            str(exc) != 'No authentication methods available'):
                raise
            client.close()
            password = getpass.getpass('ISE VM password (not saved): ')
            client.connect(**options, password=password, allow_agent=False, look_for_keys=False)
        client.get_transport().set_keepalive(30)
        return client
    except BaseException:
        client.close()
        raise


@contextmanager
def bridge(client, config):
    session = uuid.uuid4().hex
    remote_dir = None
    channel = None
    reader = None
    logdir = ROOT / '.runtime'
    logdir.mkdir(exist_ok=True)
    with (logdir / ('bridge-' + session + '.log')).open('w', encoding='utf-8') as log:
        try:
            with client.open_sftp() as sftp:
                home = sftp.normalize('.')
                remote_dir = home + '/.interrupt-debugger-' + session
                sftp.mkdir(remote_dir, mode=0o700)
                remote_file = remote_dir + '/jtag_bridge.tcl'
                data = (ROOT / 'tools/jtag_bridge.tcl').read_bytes()
                with sftp.open(remote_file, 'wb') as stream:
                    stream.write(data)
                with sftp.open(remote_file, 'rb') as stream:
                    if stream.read() != data:
                        raise RuntimeError('Bridge upload integrity check failed')
            ise = config['ise_root']
            libraries = ise + '/lib/lin64:' + ise.rsplit('/', 1)[0] + '/common/lib/lin64'
            command = ('env XILINX=' + shlex.quote(ise) + ' LD_LIBRARY_PATH=' + shlex.quote(libraries) +
                       ' ' + shlex.quote(ise + '/bin/lin64/xtclsh') + ' ' + shlex.quote(remote_file) +
                       ' --bind 127.0.0.1 --port 0')
            channel = client.get_transport().open_session(timeout=10)
            channel.set_combine_stderr(True)
            channel.settimeout(20)
            channel.exec_command(command)
            output = channel.makefile('rb')
            for raw in output:
                line = raw.decode('utf-8', errors='replace')
                log.write(line)
                log.flush()
                if line.startswith('BRIDGE_READY_PORT='):
                    port = int(line.split('=', 1)[1])
                    break
            else:
                raise RuntimeError('VM bridge failed to start; see ' + str(logdir))
            channel.settimeout(None)

            def drain():
                try:
                    for raw in output:
                        log.write(raw.decode('utf-8', errors='replace'))
                        log.flush()
                except (OSError, EOFError):
                    pass

            reader = threading.Thread(target=drain, daemon=True)
            reader.start()
            yield port
        finally:
            if channel is not None:
                try:
                    channel.sendall(b'STOP\n')
                    channel.shutdown_write()
                except (OSError, EOFError):
                    pass
                if reader is not None:
                    reader.join(5)
                channel.close()
                if reader is not None and reader.is_alive():
                    reader.join(2)
            if remote_dir is not None:
                try:
                    with client.open_sftp() as sftp:
                        sftp.remove(remote_dir + '/jtag_bridge.tcl')
                        sftp.rmdir(remote_dir)
                except OSError:
                    pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-port', type=int, default=0,
                        help='Local tunnel port; default chooses a free port automatically')
    parser.add_argument('--check-connection', action='store_true',
                        help='Check bridge/tunnel startup and shutdown without opening the GUI or touching the FPGA')
    args, gui_args = parser.parse_known_args()
    config = json.loads((ROOT / 'config/vm.json').read_text())
    print('Connecting to the ISE VM...', flush=True)
    with connect(config) as client:
        with bridge(client, config) as port, tunnel(client, port, args.local_port) as endpoint:
            # Establish a connection only; no command is sent to the bridge/cable.
            host, local_port = endpoint.rsplit(':', 1)
            with socket.create_connection((host, int(local_port)), timeout=5):
                pass
            print('Bridge and SSH tunnel ready at ' + endpoint, flush=True)
            print('No FPGA programming/reset/start performed. Keep this window open.', flush=True)
            if args.check_connection:
                print('Connection check passed.', flush=True)
                return 0
            return subprocess.call([sys.executable, '-m', 'host.app', '--bridge', endpoint, *gui_args],
                                   cwd=ROOT)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:
        print('Could not start the demo: ' + str(exc), file=sys.stderr)
        print('Check VM power/network, config/vm.json, SSH credentials and config/known_hosts.', file=sys.stderr)
        sys.exit(1)
