"""Upload a separate APS6408 diagnostic RBF through the MiSTer Linux console."""
import argparse
import gzip
import hashlib
import os
from pathlib import Path
import re
import shlex
import time
import uuid


class Console:
    def __init__(self, port, record):
        self.port = port
        self.record = record

    def read_until(self, pattern, timeout):
        response = bytearray()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            response.extend(self.port.read(4096))
            match = re.search(pattern, response)
            if match:
                self.record(response.decode(errors='replace'))
                return match
        raise TimeoutError('Console did not return the expected marker')

    def login(self, password):
        self.port.write(b'\r')
        match = self.read_until(rb'((?:^|[\r\n])[^\r\n#]*# |login:|Password:)', 15)
        if match[1] == b'login:':
            self.port.write(b'root\r')
            match = self.read_until(rb'((?:^|[\r\n])[^\r\n#]*# |Password:)', 15)
        if match[1] == b'Password:':
            if password is None:
                raise ValueError('Set APS6408_SERIAL_PASSWORD or pass --password')
            self.port.write(password.encode() + b'\r')
            self.read_until(rb'(?:^|[\r\n])[^\r\n#]*# ', 15)

    def command(self, command, timeout=30):
        token = 'APS_' + uuid.uuid4().hex
        wrapped = f"{command}; result=$?; printf '\\n{token}:%s\\n' \"$result\""
        self.port.write(wrapped.encode() + b'\r')
        match = self.read_until(rb'(?:\r?\n)' + token.encode() + rb':([0-9]+)\r?\n', timeout)
        if match[1] != b'0':
            raise RuntimeError('Board command failed with status ' + match[1].decode())
        return match.string.decode(errors='replace')


def upload(console, data, destination, receiver_timeout=180):
    if not re.fullmatch(r'/media/fat/_Console/APS6408_[A-Za-z0-9_.-]+\.rbf', destination):
        raise ValueError('Destination must be a separate APS6408 diagnostic RBF')
    if not 60 <= receiver_timeout <= 600:
        raise ValueError('Receiver timeout must be 60 to 600 seconds')
    token = 'APS_' + uuid.uuid4().hex
    compressed = gzip.compress(data, compresslevel=6, mtime=0)
    digest = hashlib.sha256(data).hexdigest()
    transport = destination + '.' + token + '.upload.gz.part'
    temporary = destination + '.' + token + '.part'
    dest_q, temp_q, transport_q = map(shlex.quote, (destination, temporary, transport))
    console.record(f'Temporary transport: {transport}\nTemporary RBF: {temporary}')
    console.command(f'test -e /dev/MiSTer_cmd && test -d /media/fat/_Console && '
                    f'test -w /media/fat/_Console && command -v timeout >/dev/null && '
                    f'test ! -e {dest_q} && test ! -e {temp_q} && test ! -e {transport_q}')
    ready = token + '_READY'
    received = token + '_RECEIVED'
    continue_token = token + '_CONTINUE'
    continued = token + '_CONTINUED'
    console.record('Receiver release token: ' + continue_token)
    receive = (
        '( saved_tty=$(stty -g); '
        'trap \'stty "$saved_tty"\' EXIT HUP INT TERM; '
        'stty raw -echo -ixon -ixoff; '
        f"printf '\\n{ready}\\n'; "
        f'timeout {receiver_timeout} head -c {len(compressed)} > {transport_q}; '
        'rx_result=$?; stty "$saved_tty"; trap - EXIT HUP INT TERM; '
        f"printf '\\n{received}:%s\\n' \"$rx_result\"; "
        f'while IFS= read -r ack; do [ "$ack" = "{continue_token}" ] && break; done; '
        f'[ "$ack" = "{continue_token}" ] || exit 1; '
        f"printf '\\n{continued}\\n' )"
    )
    console.port.write(receive.encode() + b'\r')
    console.read_until(rb'\r?\n' + ready.encode() + rb'\r?\n', 15)
    started = time.monotonic()
    console.record(f'Sending {len(compressed)} compressed bytes; RBF {len(data)} bytes; SHA256 {digest}')
    next_report = 10
    for offset in range(0, len(compressed), 1024):
        if time.monotonic() - started > receiver_timeout - 15:
            raise TimeoutError('Upload exceeded its receiver time budget; do not send more binary bytes')
        console.port.write(compressed[offset:offset + 1024])
        console.port.flush()
        time.sleep(0.005)
        percent = min(offset + 1024, len(compressed)) * 100 // len(compressed)
        if percent >= next_report:
            console.record(f'Transfer {percent}%')
            next_report += 10
    match = console.read_until(rb'\r?\n' + received.encode() + rb':([0-9]+)\r?\n', receiver_timeout)
    console.port.write(b'\r' + continue_token.encode() + b'\r')
    console.read_until(rb'\r?\n' + continued.encode() + rb'\r?\n', 15)
    if match[1] != b'0':
        raise RuntimeError('Receiver failed or timed out; firmware was not finalized')
    console.command(
        f'gzip -dc {transport_q} > {temp_q} && '
        f'test "$(wc -c < {temp_q})" -eq {len(data)} && '
        f'test "$(sha256sum {temp_q} | cut -d " " -f 1)" = {shlex.quote(digest)}', 45)
    console.command(f'test ! -e {dest_q} && mv {temp_q} {dest_q} && rm -f {transport_q} && sync', 45)
    console.record('Verified firmware ready: ' + destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination')
    parser.add_argument('--port', default='COM13')
    parser.add_argument('--password', default=os.environ.get('APS6408_SERIAL_PASSWORD'))
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--receiver-timeout', type=int, default=180)
    parser.add_argument('--release-receiver', help='Release token from an interrupted upload log, after receiver timeout')
    args = parser.parse_args()
    import serial
    data = args.source.read_bytes()
    with args.log.open('a', encoding='utf-8') as log:
        def record(message):
            print(message, flush=True)
            log.write(message + '\n')
            log.flush()
        try:
            with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=10,
                               rtscts=False, dsrdtr=False, xonxoff=False) as port:
                port.dtr = False
                port.rts = False
                console = Console(port, record)
                if args.release_receiver:
                    if not re.fullmatch(r'APS_[0-9a-f]{32}_CONTINUE', args.release_receiver):
                        raise ValueError('Invalid receiver release token')
                    port.write(b'\r' + args.release_receiver.encode() + b'\r')
                    console.read_until(rb'\r?\n' + args.release_receiver.replace('_CONTINUE', '_CONTINUED').encode() + rb'\r?\n', 15)
                console.login(args.password)
                upload(console, data, args.destination, args.receiver_timeout)
        except Exception as error:
            record(f'Upload failed: {type(error).__name__}: {error}')
            raise


if __name__ == '__main__':
    main()
