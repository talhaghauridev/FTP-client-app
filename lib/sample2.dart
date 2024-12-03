import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import "package:first_app/custom.dart";

void main() {
  runApp(const MyApp());
}

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
  CustomFTPClient? _ftpClient;
  String _connectionStatus = "Not Connected";
  String? _selectedFileName;
  String? _selectedFilePath;
  List<String> _logs = [];
  // ignore: unused_field
  bool _isImageFile = false;

  TransferMode _transferMode = TransferMode.passive; // Default mode
  Future<void> _uploadFile() async {
    if (_ftpClient == null) {
      setState(() {
        _connectionStatus = "Not connected";
      });
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null) return;

      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;
        _connectionStatus = "Starting upload...";
      });

      if (_selectedFilePath != null) {
        // Note the change in path - we're uploading directly to root
        await _ftpClient!.uploadFile(_selectedFilePath!,
            '/${_selectedFileName ?? 'uploaded_file.jpg'}' // Changed from /SD_MMC/
            );

        setState(() {
          _connectionStatus = "Upload completed successfully";
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = "Upload failed: $e";
      });
    }
  }

  Future<void> _connectToFtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _connectionStatus = "Connecting...";
    });

    try {
      // Convert TransferMode to FtpTransferMode
      FtpTransferMode selectedMode = _transferMode == TransferMode.active
          ? FtpTransferMode.active
          : FtpTransferMode.passive;

      _ftpClient = CustomFTPClient(
        host: _hostController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text,
        password: _passwordController.text,
        transferMode: selectedMode, // Use the selected mode
        onLogMessage: (log) {
          print(log);
          setState(() {
            _logs.add(log);
            if (_logs.length > 100) _logs.removeAt(0);
          });
        },
      );

      // Subscribe to log stream
      _ftpClient!.logStream.listen((log) {
        setState(() {
          _logs.add(log);
          if (_logs.length > 100) _logs.removeAt(0);
        });
      });

      await _ftpClient!.connect();

      setState(() {
        _connectionStatus =
            "Connected successfully (${selectedMode == FtpTransferMode.active ? 'Active Mode' : 'Passive Mode'})";
      });
    } catch (e) {
      setState(() {
        _connectionStatus = "Connection failed: $e";
      });
    }
  }

  Future<void> _uploadLocalAsset() async {
    if (_ftpClient == null) {
      setState(() {
        _connectionStatus = "Not connected";
      });
      return;
    }

    try {
      setState(() {
        _connectionStatus = "Starting local asset upload...";
      });

      // First verify asset exists
      final assetPath = 'assets/adaptive-icon.png';
      try {
        await rootBundle.load(assetPath);
      } catch (e) {
        throw Exception(
            'Asset not found: Make sure $assetPath is added to pubspec.yaml');
      }

      // Create a temporary file from the asset
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();

      // Use application's temporary directory
      final tempDir = await Directory.systemTemp.createTemp();
      final tempPath = '${tempDir.path}/adaptive-icon.png';
      final File tempFile = File(tempPath);

      try {
        await tempFile.writeAsBytes(bytes);
        print('Created temporary file at: $tempPath');

        // Upload the file
        await _ftpClient!.uploadFile(tempPath, '/adaptive-icon.png');

        setState(() {
          _connectionStatus = "Icon uploaded successfully";
        });
      } finally {
        // Cleanup
        try {
          await tempFile.delete();
          await tempDir.delete(recursive: true);
          print('Temporary files cleaned up');
        } catch (e) {
          print('Cleanup error: $e');
        }
      }
    } catch (e) {
      print('Upload error: $e');
      setState(() {
        _connectionStatus = "Icon upload failed: $e";
      });
    }
  }

  @override
  void dispose() {
    _ftpClient?.disconnect();
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
              const SizedBox(height: 16),
              DropdownButtonFormField<TransferMode>(
                value: _transferMode,
                items: [
                  DropdownMenuItem(
                    value: TransferMode.active,
                    child: Text('Active Mode'),
                  ),
                  DropdownMenuItem(
                    value: TransferMode.passive,
                    child: Text('Passive Mode'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _transferMode = value!;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Select Transfer Mode',
                  border: OutlineInputBorder(),
                ),
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
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _uploadFile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Upload File"),
              ),
              const SizedBox(height: 24),
              // Add new button for uploading the icon
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _uploadLocalAsset,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Upload Icon"),
              ),
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
