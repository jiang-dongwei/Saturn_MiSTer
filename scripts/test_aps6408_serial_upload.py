import re
import unittest
from unittest.mock import patch
from aps6408_serial_upload import Console, upload


class FakePort:
    def __init__(self):
        self.writes = []
        self.responses = []

    def write(self, data):
        self.writes.append(data)

    def read(self, count):
        return self.responses.pop(0) if self.responses else b''

    def flush(self):
        pass


class FakeConsole:
    def __init__(self, failed_command=None, receiver_status=b'0'):
        self.port = FakePort()
        self.commands = []
        self.failed_command = failed_command
        self.receiver_status = receiver_status
        self.messages = []

    def record(self, message):
        self.messages.append(message)

    def command(self, command, timeout=30):
        self.commands.append(command)
        if len(self.commands) == self.failed_command:
            raise RuntimeError('Injected board failure')

    def read_until(self, pattern, timeout):
        if b'RECEIVED' in pattern:
            return re.search(rb'([0-9]+)', self.receiver_status)
        return None


class UploadTests(unittest.TestCase):
    destination = '/media/fat/_Console/APS6408_CROSS_test.rbf'

    def test_uboot_info_is_not_a_linux_prompt(self):
        port = FakePort()
        port.responses = [b'\r\n## Info: input data size = 1005\r\n', b'\r\n/root# ']
        Console(port, lambda message: None).login(None)
        self.assertEqual(port.responses, [])

    def test_command_echo_cannot_complete_command(self):
        port = FakePort()
        port.responses = [b"printf '\\nAPS_nonce:%s\\n'\r\n", b'\r\nAPS_nonce:0\r\n']
        console = Console(port, lambda message: None)
        with patch('aps6408_serial_upload.uuid.uuid4') as nonce:
            nonce.return_value.hex = 'nonce'
            console.command('test -e /dev/MiSTer_cmd')
        self.assertEqual(port.responses, [])

    def test_wrong_board_or_existing_destination_sends_no_binary(self):
        console = FakeConsole(failed_command=1)
        with self.assertRaises(RuntimeError):
            upload(console, b'firmware', self.destination)
        self.assertEqual(console.port.writes, [])

    def test_receiver_timeout_never_verifies_or_renames(self):
        console = FakeConsole(receiver_status=b'124')
        with self.assertRaises(RuntimeError), patch('aps6408_serial_upload.time.sleep'):
            upload(console, b'firmware', self.destination)
        self.assertEqual(len(console.commands), 1)
        receiver = console.port.writes[0].decode()
        self.assertIn('timeout 180 head', receiver)
        self.assertIn('stty "$saved_tty"', receiver)
        self.assertIn('trap', receiver)
        self.assertIn('while IFS= read -r ack', receiver)

    def test_integrity_failure_never_renames(self):
        console = FakeConsole(failed_command=2)
        with self.assertRaises(RuntimeError), patch('aps6408_serial_upload.time.sleep'):
            upload(console, b'firmware', self.destination)
        self.assertEqual(len(console.commands), 2)
        self.assertFalse(any('mv ' in command for command in console.commands))

    def test_disconnected_link_never_verifies_or_renames(self):
        console = FakeConsole()
        with patch.object(console.port, 'flush', side_effect=OSError('UART disconnected')):
            with self.assertRaises(OSError):
                upload(console, b'firmware', self.destination)
        self.assertEqual(len(console.commands), 1)
        self.assertFalse(any('Verified firmware ready' in message for message in console.messages))
        self.assertTrue(any('Receiver release token' in message for message in console.messages))

    def test_success_checks_size_and_hash_before_finalizing(self):
        console = FakeConsole()
        with patch('aps6408_serial_upload.time.sleep'):
            upload(console, b'firmware', self.destination)
        self.assertEqual(len(console.commands), 3)
        self.assertIn('wc -c', console.commands[1])
        self.assertIn('sha256sum', console.commands[1])
        self.assertIn('test ! -e', console.commands[2])
        self.assertIn('mv ', console.commands[2])
        self.assertIn('Verified firmware ready', console.messages[-1])

    def test_production_destination_is_rejected(self):
        console = FakeConsole()
        with self.assertRaises(ValueError):
            upload(console, b'firmware', '/media/fat/_Console/Saturn.rbf')
        self.assertEqual(console.commands, [])


if __name__ == '__main__':
    unittest.main()
