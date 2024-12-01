import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

String remoteDir = '/SD_MMC/upload';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FTP Connection Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 54, 101, 140)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'FTP Connection Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _hostController =
      TextEditingController(text: 'ftp.dlptest.com');
  final TextEditingController _portController =
      TextEditingController(text: '21');
  final TextEditingController _usernameController =
      TextEditingController(text: 'dlpuser');
  final TextEditingController _passwordController =
      TextEditingController(text: 'rNrKYTX9g7z3RgJRmxWuGHbeu');

  String _connectionStatus = "Not Connected";
  String? _selectedFileName;
  String? _selectedFilePath;
  bool _isImageFile = false;

  Future<void> _connectToFtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _connectionStatus = "Connecting...";
    });

    FTPConnect ftpConnect = FTPConnect(
      _hostController.text,
      user: _usernameController.text,
      pass: _passwordController.text,
      port: int.parse(_portController.text),
      timeout: 60,
    );

    try {
      // Set binary mode and active mode
      bool isConnected = await ftpConnect.connect();

      if (isConnected) {
        ftpConnect.transferMode = TransferMode.active;
        await ftpConnect.sendCustomCommand('TYPE I');
        setState(() {
          _connectionStatus = "Connected successfully (Active mode)";
        });
        ftpConnect.setTransferType(TransferType.auto);
        print("Connected successfully");
      } else {
        setState(() {
          _connectionStatus = "Connection failed";
        });
      }
    } catch (e) {
      print("Connection error: $e");
      setState(() {
        _connectionStatus = "Error: ${e.toString()}";
      });
    }
  }

  Future<void> _uploadFileInDefaultMode() async {
    if (!_formKey.currentState!.validate()) return;

    ServerSocket? dataSocket;
    Socket? clientSocket;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null) return;

      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;
        _isImageFile = true;
        _connectionStatus = "Starting upload process...";
      });

      FTPConnect ftpConnect = FTPConnect(_hostController.text,
          user: _usernameController.text,
          pass: _passwordController.text,
          port: int.parse(_portController.text),
          timeout: 180,
          securityType: SecurityType.FTP,
          showLog: true);

      setState(() {
        _connectionStatus = "Connecting...";
      });

      await ftpConnect.connect();

      if (_selectedFilePath != null) {
        File file = File(_selectedFilePath!);

        try {
          // Set binary mode first
          await ftpConnect.sendCustomCommand('TYPE I');

          // Change directory
          await ftpConnect.changeDirectory('/SD_MMC/upload');

          setState(() {
            _connectionStatus = "Setting up data connection...";
          });

          // Setup data connection
          dataSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
          final address = InternetAddress.anyIPv4.address.split('.');
          final port = dataSocket.port;
          final portHi = port ~/ 256;
          final portLo = port % 256;

          // Send PORT command
          final portCommand = 'PORT ${address.join(",")},${portHi},${portLo}';
          await ftpConnect.sendCustomCommand(portCommand);

          // Start upload
          setState(() {
            _connectionStatus = "Starting file upload...";
          });

          // Send STOR command
          await ftpConnect
              .sendCustomCommand('STOR ${result.files.single.name}');

          // Wait for data connection
          var socketFuture = dataSocket.accept();
          clientSocket = await socketFuture.timeout(Duration(seconds: 10));

          // Upload file
          var fileStream = file.openRead();
          await clientSocket.addStream(fileStream);

          setState(() {
            _connectionStatus = "Upload completed successfully";
          });
        } finally {
          // Clean up connections
          if (clientSocket != null) {
            await clientSocket.close();
          }
          if (dataSocket != null) {
            await dataSocket.close();
          }
        }
      }

      await ftpConnect.disconnect();
    } catch (e) {
      print("Upload error: $e");
      setState(() {
        _connectionStatus = "Upload failed: $e";
      });
      try {
        if (clientSocket != null) await clientSocket.close();
        if (dataSocket != null) await dataSocket.close();
        // await ftpConnect?.disconnect();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'Enter FTP host (e.g., 192.168.4.1)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter host';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: 'Enter port (default: 21)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter port';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid port number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter FTP username',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter FTP password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _connectToFtp,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Connect to FTP Server"),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _uploadFileInDefaultMode,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Upload File"),
              ),
              if (_isImageFile && _selectedFilePath != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        const Text(
                          'Selected Image Preview:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Image.file(
                          File(_selectedFilePath!),
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedFileName ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Connection Status:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _connectionStatus,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
