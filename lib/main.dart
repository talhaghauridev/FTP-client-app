import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';

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

  String _connectionStatus = "Not Connected";
  String? _selectedFileName;
  String? _selectedFilePath;
  // ignore: unused_field
  bool _isImageFile = false;
  TransferMode _transferMode = TransferMode.passive; // Default mode
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
      bool isConnected = await ftpConnect.connect();

      if (isConnected) {
        setState(() {
          _connectionStatus = "Connected successfully ";
        });
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

      FTPConnect ftpConnect = FTPConnect(
        _hostController.text,
        user: _usernameController.text,
        pass: _passwordController.text,
        port: int.parse(_portController.text),
        timeout: 180,
        securityType: SecurityType.FTP,
        showLog: true,
      );

      try {
        setState(() {
          _connectionStatus = "Connecting...";
        });

        bool isConnected = await ftpConnect.connect();
        if (!isConnected) {
          throw Exception('Not connected');
        }

        // Set the transfer mode
        ftpConnect.transferMode = _transferMode;

        if (_selectedFilePath != null) {
          File file = File(_selectedFilePath!);

          if (!await file.exists()) {
            setState(() {
              _connectionStatus = "File does not exist.";
            });
            return;
          }

          int fileSize = await file.length();
          if (fileSize <= 0) {
            setState(() {
              _connectionStatus = "File is empty.";
            });
            return;
          }

          setState(() {
            _connectionStatus = "Starting file upload...";
          });

          bool uploaded = await ftpConnect.uploadFileWithRetry(
            file,
            pRemoteName: _selectedFileName as String,
            pRetryCount: 2,
            onProgress: (double progress, int? transferred, int? total) {
              setState(() {
                _connectionStatus = "Uploading: ${progress.round()}%";
              });
            },
          );

          if (uploaded) {
            setState(() {
              _connectionStatus = "File uploaded successfully!";
            });
          } else {
            setState(() {
              _connectionStatus = "Upload failed";
            });
          }
        }

        await ftpConnect.disconnect();
      } catch (e) {
        print("Upload error: $e");
        await ftpConnect.disconnect();
        setState(() {
          _connectionStatus = "Upload failed: $e";
        });
      }
    } catch (e) {
      print("Process error: $e");
      setState(() {
        _connectionStatus = "Error: ${e.toString()}";
      });
    }
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
                onPressed: _uploadFileInDefaultMode,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Upload File"),
              ),
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
