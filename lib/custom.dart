import 'dart:io';
import 'dart:async';
import 'dart:convert';

enum FtpTransferMode { active, passive }

class CustomFTPClient {
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpTransferMode transferMode;
  Function(String)? onLogMessage; // Callback for logging

  Socket? _controlSocket;
  Socket? _dataSocket;
  ServerSocket? _passiveServer;

  List<String> _logs = []; // Store logs

  StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;
  List<String> get logs => _logs; // Getter for logs
  Completer<Socket>? _activeSocketCompleter;
  StreamSubscription<Socket>? _serverSubscription;

  CustomFTPClient({
    required this.host,
    this.port = 21,
    required this.username,
    required this.password,
    this.transferMode = FtpTransferMode.passive,
    this.onLogMessage,
  });

  void _log(String message) {
    final logMessage = "${DateTime.now().toIso8601String()} - $message";
    _logs.add(logMessage);
    _logController.add(logMessage);
    onLogMessage?.call(logMessage);
    print(logMessage); // Print to console
  }

  Future<void> connect() async {
    try {
      _log('Connecting to $host:$port');

      // Connect to control port
      _controlSocket = await Socket.connect(host, port);
      _log('Control connection established');

      // Set up control connection handling
      _controlSocket!.encoding = ascii;
      _controlSocket!.listen(
        _handleControlResponse,
        onError: (error) {
          _log('Control connection error: $error');
          throw Exception('Control connection error: $error');
        },
        onDone: () => _log('Control connection closed'),
      );

      // Wait for welcome message
      String welcome = await _waitForResponse('220');
      _log('Server welcome message: $welcome');

      // Login sequence
      _log('Starting login sequence...');
      await _sendCommand('USER $username');
      await _waitForResponse('331');

      await _sendCommand('PASS $password');
      await _waitForResponse('230');

      _log('Login successful');

      // Set transfer mode
      if (transferMode == FtpTransferMode.passive) {
        _log('Setting passive mode');
      } else {
        _log('Setting active mode');
        await _setupActiveMode();
      }
    } catch (e) {
      _log('Connection error: $e');
      throw Exception('Failed to connect: $e');
    }
  }

  Future<void> _setupActiveMode() async {
    try {
      _activeSocketCompleter = Completer<Socket>();

      // Get the best network interface
      final interfaces = await NetworkInterface.list();
      NetworkInterface? bestInterface;

      // Try to find a non-loopback interface
      for (var interface in interfaces) {
        var addresses = interface.addresses.where((addr) =>
            addr.type == InternetAddressType.IPv4 && !addr.isLoopback);
        if (addresses.isNotEmpty) {
          bestInterface = interface;
          break;
        }
      }

      if (bestInterface == null) {
        throw Exception('No suitable network interface found');
      }

      // Get the first IPv4 address
      final ipAddress = bestInterface.addresses
          .firstWhere((addr) => addr.type == InternetAddressType.IPv4);

      // Create server socket
      _passiveServer = await ServerSocket.bind(ipAddress, 0);
      final port = _passiveServer!.port;

      // Format IP for PORT command
      final formattedIp = ipAddress.address.split('.').join(',');
      final p1 = port ~/ 256;
      final p2 = port % 256;

      final portCommand = 'PORT $formattedIp,$p1,$p2';
      _log('Setting up active mode with IP: ${ipAddress.address}:$port');
      _log('Sending PORT command: $portCommand');

      await _sendCommand(portCommand);
      final response = await _waitForResponse('200',
          acceptableResponses: ['200', '501', '500']);

      if (!response.startsWith('200')) {
        throw Exception('Server rejected PORT command: $response');
      }

      // Set up listener with timeout
      _serverSubscription?.cancel();
      _serverSubscription = _passiveServer!.listen(
        (Socket socket) {
          _log(
              'Received data connection from: ${socket.remoteAddress.address}:${socket.remotePort}');
          if (_activeSocketCompleter != null &&
              !_activeSocketCompleter!.isCompleted) {
            _activeSocketCompleter!.complete(socket);
          }
        },
        onError: (error) {
          _log('Active mode listener error: $error');
          if (_activeSocketCompleter != null &&
              !_activeSocketCompleter!.isCompleted) {
            _activeSocketCompleter!.completeError(error);
          }
        },
        cancelOnError: true,
      );

      _log('Active mode server listening on ${ipAddress.address}:$port');
    } catch (e) {
      _log('Active mode setup failed: $e');
      await _cleanup();
      throw Exception('Failed to setup active mode: $e');
    }
  }

  Future<Socket> _waitForActiveConnection() async {
    if (_activeSocketCompleter == null) {
      throw Exception('Active mode not properly initialized');
    }

    try {
      return await _activeSocketCompleter!.future.timeout(
        Duration(seconds: 10), // Reduced timeout
        onTimeout: () {
          _log('Active mode connection timeout - falling back to passive mode');
          throw TimeoutException('Active mode connection timeout');
        },
      );
    } catch (e) {
      // Try to clean up on error
      await _cleanup();
      rethrow;
    }
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    bool useFallbackMode = false;

    try {
      _log('Starting file upload process...');

      // Set binary mode
      await _sendCommand('TYPE I');
      await _waitForResponse('200');

      // First establish data connection BEFORE sending STOR
      if (transferMode == FtpTransferMode.passive) {
        _log('Setting up passive mode connection');
        await _sendCommand('PASV');
        String pasvResponse = await _waitForResponse('227');
        var dataPort = _parsePASVResponse(pasvResponse);
        _log('Connecting to port: $dataPort');

        // Create data connection
        _dataSocket = await Socket.connect(host, dataPort);
        await Future.delayed(
            Duration(milliseconds: 100)); // Give connection time to stabilize

        if (_dataSocket == null) {
          throw Exception('Failed to establish data connection');
        }
        _log('Data connection established successfully');
      }

      // Now send STOR command
      _log('Sending STOR command');
      await _sendCommand('STOR $remotePath');
      await _waitForResponse('150', acceptableResponses: ['125', '150', '200']);

      // Read and upload file
      File file = File(localPath);
      final bytes = await file.readAsBytes();

      // Upload with smaller chunks and progress tracking
      int chunkSize = 4096; // 4KB chunks
      int uploaded = 0;

      for (var i = 0; i < bytes.length; i += chunkSize) {
        if (_dataSocket == null) {
          throw Exception('Lost data connection during upload');
        }

        var end = (i + chunkSize) < bytes.length ? i + chunkSize : bytes.length;
        var chunk = bytes.sublist(i, end);

        _dataSocket!.add(chunk);
        uploaded += chunk.length;

        var progress = ((uploaded / bytes.length) * 100).toStringAsFixed(1);
        _log('Upload progress: $progress%');
      }

      // Ensure all data is written
      await _dataSocket!.flush();
      await _dataSocket!.close();

      // Wait for transfer completion
      final response = await _waitForResponse('226',
          acceptableResponses: ['225', '226', '250']);
      _log('Upload complete: $response');
    } catch (e) {
      _log('Upload error: $e');
      throw Exception('Upload failed: $e');
    } finally {
      await _cleanup();
    }
  }

  Future<void> _cleanup() async {
    try {
      _log('Starting cleanup');

      // Clean up data socket
      if (_dataSocket != null) {
        try {
          await _dataSocket!.flush();
          await _dataSocket!.close();
        } catch (e) {
          _log('Error cleaning up data socket: $e');
        }
        _dataSocket = null;
      }

      // Clean up active mode resources
      if (transferMode == FtpTransferMode.active) {
        _serverSubscription?.cancel();
        _serverSubscription = null;

        try {
          await _passiveServer?.close();
        } catch (e) {
          _log('Error closing server socket: $e');
        }
        _passiveServer = null;

        _activeSocketCompleter = null;
      }

      _log('Cleanup completed');
    } catch (e) {
      _log('Error during cleanup: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      _log('Initiating disconnect sequence');
      _serverSubscription?.cancel();
      _serverSubscription = null;
      _activeSocketCompleter = null;

      if (_controlSocket != null) {
        await _sendCommand('QUIT');
        await _waitForResponse('221');
        _controlSocket!.destroy();
        _controlSocket = null;
      }
      _dataSocket?.destroy();
      _dataSocket = null;
      await _passiveServer?.close();
      _passiveServer = null;
      _log('Disconnect complete');
    } catch (e) {
      _log('Disconnect error: $e');
    }
  }

  Future<void> _sendCommand(String command) async {
    if (_controlSocket == null) {
      throw Exception('Not connected');
    }

    // Mask password in logs
    final logCommand = command.startsWith('PASS ') ? 'PASS ****' : command;
    _log('Sending command: $logCommand');

    _controlSocket!.writeln(command);
  }

  String _responseBuffer = '';
  Completer<String>? _responseCompleter;

  void _handleControlResponse(List<int> data) {
    _responseBuffer += ascii.decode(data);
    _log('Received: $_responseBuffer');

    if (_responseBuffer.contains('\n')) {
      if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
        _responseCompleter!.complete(_responseBuffer.trim());
      }
      _responseBuffer = '';
      _responseCompleter = null;
    }
  }

  Future<String> _waitForResponse(String expectedCode,
      {List<String>? acceptableResponses}) async {
    _responseCompleter = Completer<String>();
    String response = await _responseCompleter!.future.timeout(
      Duration(seconds: 30),
      onTimeout: () {
        _log('Response timeout waiting for $expectedCode');
        throw TimeoutException('Server response timeout');
      },
    );

    acceptableResponses = acceptableResponses ?? [expectedCode];

    if (!acceptableResponses.any((code) => response.startsWith(code))) {
      _log('Unexpected response: $response (Expected: $expectedCode)');
      throw Exception('Unexpected response: $response');
    }

    return response;
  }

  int _parsePASVResponse(String response) {
    _log('Parsing PASV response: $response');
    RegExp regex = RegExp(r'\((\d+,\d+,\d+,\d+,\d+,\d+)\)');
    Match? match = regex.firstMatch(response);

    if (match == null) {
      // Attempt alternative parsing without parentheses
      regex = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)');
      match = regex.firstMatch(response);
      if (match == null || match.groupCount != 6) {
        _log('Invalid PASV response format');
        throw Exception('Invalid PASV response: $response');
      }
    }

    try {
      List<int> numbers = [];
      for (int i = 1; i <= 6; i++) {
        numbers.add(int.parse(match!.group(i)!));
      }
      final port = numbers[4] * 256 + numbers[5];
      _log('Calculated data port: $port');
      return port;
    } catch (e) {
      _log('Error parsing PASV response: $e');
      throw Exception('Error parsing PASV response: $e');
    }
  }
}
