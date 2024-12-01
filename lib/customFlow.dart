import 'dart:io';
import 'dart:convert';

class CustomFTP {
  final String host;
  final int port;
  final String username;
  final String password;
  Socket? _controlSocket;
  Socket? _dataSocket;
  final void Function(String) onStatus;

  CustomFTP({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.onStatus,
  });

  Future<bool> connect() async {
    try {
      // Connect to control port
      _controlSocket = await Socket.connect(host, port);

      // Set up response handling
      _controlSocket!.listen(
        (data) => _handleResponse(utf8.decode(data)),
        onError: (error) => throw Exception('Control socket error: $error'),
        onDone: () => onStatus('Control connection closed'),
      );

      // Wait for welcome message
      await _waitForResponse('220');

      // Login sequence
      await _sendCommand('USER $username');
      await _waitForResponse('331');

      await _sendCommand('PASS $password');
      await _waitForResponse('230');

      onStatus('Connected successfully');
      return true;
    } catch (e) {
      onStatus('Connection failed: $e');
      return false;
    }
  }

  Future<bool> uploadFile(File file) async {
    try {
      // Set binary mode
      await _sendCommand('TYPE I');
      await _waitForResponse('200');

      // Set up data connection using PORT command
      final socket = await ServerSocket.bind('0.0.0.0', 0);
      final address = socket.address.address.split('.');
      final port = socket.port;
      final portHi = port ~/ 256;
      final portLo = port % 256;

      final portCommand = 'PORT ${address.join(",")},${portHi},${portLo}';
      await _sendCommand(portCommand);
      await _waitForResponse('200');

      // Start file upload
      await _sendCommand('STOR ${file.path.split('/').last}');

      // Accept data connection
      _dataSocket = await socket.first;
      socket.close();

      // Upload file data
      final fileStream = file.openRead();
      int totalBytes = file.lengthSync();
      int bytesSent = 0;

      await for (List<int> chunk in fileStream) {
        _dataSocket!.add(chunk);
        bytesSent += chunk.length;
        final progress = (bytesSent / totalBytes * 100).round();
        onStatus('Uploading: $progress%');
      }

      // Close data connection
      await _dataSocket!.close();
      await _waitForResponse('226');

      onStatus('File uploaded successfully');
      return true;
    } catch (e) {
      onStatus('Upload failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_controlSocket != null) {
        await _sendCommand('QUIT');
        await _controlSocket!.close();
      }
      if (_dataSocket != null) {
        await _dataSocket!.close();
      }
    } catch (e) {
      onStatus('Disconnect error: $e');
    }
  }

  Future<void> _sendCommand(String command) async {
    print('> $command');
    _controlSocket!.write('$command\r\n');
  }

  String _lastResponse = '';
  void _handleResponse(String response) {
    print('< $response');
    _lastResponse = response;
  }

  Future<bool> _waitForResponse(String expectedCode) async {
    int attempts = 0;
    while (attempts < 10) {
      if (_lastResponse.startsWith(expectedCode)) {
        return true;
      }
      await Future.delayed(Duration(milliseconds: 100));
      attempts++;
    }
    throw Exception('Timeout waiting for response code $expectedCode');
  }
}
