// custom.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';

enum FtpTransferMode { active, passive }

class FtpEntry {
  final String name;
  final bool isDirectory;
  final int size;
  final String permissions;
  final String modified;
  final String owner;
  final String group;

  FtpEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.permissions,
    required this.modified,
    required this.owner,
    required this.group,
  });

  @override
  String toString() {
    return '${isDirectory ? 'd' : '-'}$permissions $owner $group $size $modified $name';
  }
}

class CustomFTPClient {
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpTransferMode transferMode;
  Function(String)? onLogMessage;

  Socket? _controlSocket;
  Socket? _dataSocket;
  ServerSocket? _passiveServer;
  List<String> _logs = [];
  StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;
  List<String> get logs => _logs;
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
    print(logMessage);
  }

  Future<void> connect() async {
    try {
      _log('Connecting to $host:$port');
      _controlSocket = await Socket.connect(host, port);
      _log('Control connection established');

      _controlSocket!.encoding = ascii;
      _controlSocket!.listen(
        _handleControlResponse,
        onError: (error) {
          _log('Control connection error: $error');
          throw Exception('Control connection error: $error');
        },
        onDone: () => _log('Control connection closed'),
      );

      String welcome = await _waitForResponse('220');
      _log('Server welcome message: $welcome');

      _log('Starting login sequence...');
      await _sendCommand('USER $username');
      await _waitForResponse('331');

      await _sendCommand('PASS $password');
      await _waitForResponse('230');

      _log('Login successful');

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

      final interfaces = await NetworkInterface.list();
      var selectedInterface = interfaces.firstWhere(
          (i) =>
              i.addresses.any((addr) => addr.address.startsWith('192.168.4')),
          orElse: () => interfaces.first);

      var ipAddress = selectedInterface.addresses.firstWhere(
          (addr) =>
              addr.type == InternetAddressType.IPv4 &&
              addr.address.startsWith('192.168.4'),
          orElse: () => selectedInterface.addresses.first);

      _log(
          'Using interface: ${selectedInterface.name}, IP: ${ipAddress.address}');

      _passiveServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = _passiveServer!.port;

      final portCmd =
          'PORT ${ipAddress.address.split('.').join(',')},${port ~/ 256},${port % 256}';
      await _sendCommand(portCmd);
      await _waitForResponse('200');

      _serverSubscription = _passiveServer!.listen(
        (Socket socket) {
          _log(
              'Data connection received from: ${socket.remoteAddress.address}');
          if (!_activeSocketCompleter!.isCompleted) {
            _activeSocketCompleter!.complete(socket);
          }
        },
        onError: (e) => _log('Server error: $e'),
      );
    } catch (e) {
      _log('Active mode setup error: $e');
      await _cleanup();
      rethrow;
    }
  }

  Future<Socket> _waitForActiveConnection() async {
    if (_activeSocketCompleter == null) {
      throw Exception('Active mode not properly initialized');
    }

    try {
      return await _activeSocketCompleter!.future.timeout(
        Duration(seconds: 30),
        onTimeout: () {
          _log('Active mode connection timeout');
          throw TimeoutException('Active mode connection timeout');
        },
      );
    } catch (e) {
      await _cleanup();
      rethrow;
    }
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    try {
      _log('Starting file upload process...');

      await _sendCommand('TYPE I');
      await _waitForResponse('200');

      if (transferMode == FtpTransferMode.active) {
        await _setupActiveMode();
        _dataSocket = await _waitForActiveConnection();
      } else {
        await _sendCommand('PASV');
        String pasvResponse = await _waitForResponse('227');
        var dataPort = _parsePASVResponse(pasvResponse);
        _dataSocket = await Socket.connect(host, dataPort);
      }

      await _sendCommand('STOR $remotePath');
      await _waitForResponse('150', acceptableResponses: ['125', '150', '200']);

      File file = File(localPath);
      final bytes = await file.readAsBytes();

      int chunkSize = 1024;
      int uploaded = 0;

      for (var i = 0; i < bytes.length; i += chunkSize) {
        var end = (i + chunkSize) < bytes.length ? i + chunkSize : bytes.length;
        var chunk = bytes.sublist(i, end);
        _dataSocket!.add(chunk);
        uploaded += chunk.length;

        if (uploaded % (chunkSize * 10) == 0) {
          await _dataSocket!.flush();
          await Future.delayed(Duration(milliseconds: 50));
        }
      }

      await _dataSocket!.flush();
      await _dataSocket!.close();

      await _waitForResponse('226', acceptableResponses: ['225', '226', '250']);
    } catch (e) {
      _log('Upload error: $e');
      throw Exception('Upload failed: $e');
    } finally {
      await _cleanup();
    }
  }

  Future<List<FtpEntry>> listDirectoryContent([String path = '']) async {
    List<FtpEntry> entries = [];

    try {
      await _sendCommand('TYPE A');
      await _waitForResponse('200');

      if (transferMode == FtpTransferMode.active) {
        await _setupActiveMode();
        _dataSocket = await _waitForActiveConnection();
      } else {
        await _sendCommand('PASV');
        String pasvResponse = await _waitForResponse('227');
        var dataPort = _parsePASVResponse(pasvResponse);
        _dataSocket = await Socket.connect(host, dataPort);
      }

      await _sendCommand('LIST $path');
      await _waitForResponse('150', acceptableResponses: ['125', '150']);

      List<int> responseData = [];
      await _dataSocket!.listen(
        (data) {
          responseData.addAll(data);
        },
        onDone: () async {
          _log('Directory listing complete');
        },
      ).asFuture();

      await _dataSocket!.close();
      await _waitForResponse('226');

      String listing = utf8.decode(responseData);
      entries = _parseDirectoryListing(listing);
    } catch (e) {
      _log('List directory error: $e');
      throw Exception('Failed to list directory: $e');
    } finally {
      await _cleanup();
    }

    return entries;
  }

  List<FtpEntry> _parseDirectoryListing(String listing) {
    List<FtpEntry> entries = [];

    for (String line in listing.split('\n')) {
      if (line.trim().isEmpty) continue;

      try {
        RegExp regex = RegExp(
            r'^([\-ld])([rwxt-]{9})\s+(\d+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+)\s+(.+)$');

        var match = regex.firstMatch(line);
        if (match != null) {
          bool isDirectory = match.group(1) == 'd';
          String permissions = match.group(2) ?? '';
          String owner = match.group(4) ?? '';
          String group = match.group(5) ?? '';
          int size = int.tryParse(match.group(6) ?? '0') ?? 0;
          String modified = match.group(7) ?? '';
          String name = match.group(8) ?? '';

          entries.add(FtpEntry(
            name: name,
            isDirectory: isDirectory,
            size: size,
            permissions: permissions,
            modified: modified,
            owner: owner,
            group: group,
          ));
        }
      } catch (e) {
        _log('Error parsing line: $line');
      }
    }

    return entries;
  }

  Future<void> _cleanup() async {
    try {
      _log('Starting cleanup');

      if (_dataSocket != null) {
        try {
          await _dataSocket!.flush();
          await _dataSocket!.close();
        } catch (e) {
          _log('Error cleaning up data socket: $e');
        }
        _dataSocket = null;
      }

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
      regex = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)');
      match = regex.firstMatch(response);
      if (match == null || match.groupCount != 6) {
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
      throw Exception('Error parsing PASV response: $e');
    }
  }
}
