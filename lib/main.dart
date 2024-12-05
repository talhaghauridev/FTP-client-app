import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FTP Connection',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 54, 101, 140)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'FTP File Uploader'),
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
  bool _isImageUploading = false;

  final TextEditingController _hostController =
      TextEditingController(text: '192.168.4.1');
  final TextEditingController _portController =
      TextEditingController(text: '21');
  final TextEditingController _usernameController =
      TextEditingController(text: '');
  final TextEditingController _passwordController =
      TextEditingController(text: '');

  String _connectionStatus = "Not Connected";
  String? _selectedFileName;
  String? _selectedFilePath;
  String? _croppedFilePath;
  TransferMode _transferMode = TransferMode.passive;
  FTPConnect? _ftpConnect2;
  bool _isConnected = false;

  dynamic disconnectStyles = false;
  Future<void> _connectToFtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _connectionStatus = "Connecting...";
    });

    _ftpConnect2 = FTPConnect(
      _hostController.text,
      user: _usernameController.text,
      pass: _passwordController.text,
      port: int.parse(_portController.text),
      timeout: 60,
    );

    try {
      bool isConnected = await _ftpConnect2!.connect();
      if (isConnected) {
        _ftpConnect2?.transferMode = _transferMode;
        await _ftpConnect2?.sendCustomCommand('TYPE I');
        setState(() {
          _isConnected = true;
          _connectionStatus = "Connected successfully";
        });
      } else {
        setState(() {
          _isConnected = false;
          _connectionStatus = "Connection failed";
        });
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> _cropImage() async {
    if (_selectedFilePath == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _selectedFilePath!,
      aspectRatio: const CropAspectRatio(ratioX: 1.5, ratioY: 1),
      compressQuality: 100,
      maxWidth: 480,
      maxHeight: 320,
      compressFormat: ImageCompressFormat.jpg,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio3x2,
          lockAspectRatio: true,
          hideBottomControls: true,
          showCropGrid: true,
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          rectWidth: 480,
          rectHeight: 320,
          doneButtonTitle: 'Upload',
        ),
      ],
    );

    if (croppedFile != null) {
      _croppedFilePath = croppedFile.path;
      await _uploadFile();
    }
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: false);

      if (result != null) {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;
        await _cropImage();
      }
    } finally {
      setState(() {
        _isImageUploading = false;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (!_formKey.currentState!.validate() ||
        _ftpConnect2 == null ||
        _croppedFilePath == null) return;

    setState(() {
      _connectionStatus = "Starting upload process...";
    });

    try {
      File file = File(_croppedFilePath!);
      if (!await file.exists()) {
        setState(() {
          _connectionStatus = "File does not exist.";
        });
        return;
      }

      dynamic uploaded = await _ftpConnect2?.uploadFile(
        file,
        sRemoteName: _selectedFileName!,
        onProgress: (progress, transferred, total) {
          setState(() {
            _connectionStatus = "Uploading: ${progress.round()}%";
          });
        },
      );

      setState(() {
        _connectionStatus =
            uploaded ? "File uploaded successfully!" : "Upload failed";
      });
    } catch (e) {
      setState(() {
        _connectionStatus = "Upload failed: ${e.toString()}";
      });
    }
  }

  // ignore: unused_element
  Future<void> _listFiles() async {
    try {
      final listing = await _ftpConnect2!.listDirectoryContent();
      String status = 'Found ${listing.length} files';
      print(listing);
      setState(() {
        _connectionStatus = status;
      });
    } catch (e) {
      setState(() {
        _connectionStatus = "List error: $e";
      });
    }
  }

  Future<void> disconnect() async {
    try {
      if (_ftpConnect2 != null) {
        await _ftpConnect2?.disconnect();
        setState(() {
          _connectionStatus = "Disconnected Successfully";
          _isConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = "Error $e";
      });
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
                  hintText: 'Enter FTP host',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter host' : null,
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
                  if (value?.isEmpty ?? true) return 'Please enter port';
                  if (int.tryParse(value!) == null) {
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
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter username' : null,
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
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter password' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TransferMode>(
                value: _transferMode,
                items: const [
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor:
                      _isConnected ? Colors.green.shade600 : Colors.white,
                ),
                child: Text(
                  _isConnected ? "Connected" : "Connect to Server",
                  style: TextStyle(
                      fontSize: 17,
                      color: _isConnected ? Colors.white : Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isImageUploading
                    ? null
                    : () async {
                        setState(() {
                          _isImageUploading = true;
                        });
                        await _pickImage();
                      },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.white),
                child: _isImageUploading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text("Processing...",
                              style:
                                  TextStyle(fontSize: 17, color: Colors.black)),
                        ],
                      )
                    : const Text("Select File",
                        style: TextStyle(fontSize: 17, color: Colors.black)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _connectionStatus = "Disconnecting...";
                    disconnectStyles = true;
                  });
                  await Future.delayed(const Duration(milliseconds: 1000));
                  await disconnect();
                  setState(() {
                    _connectionStatus = "Disconnected Successfully";

                    disconnectStyles = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor:
                        disconnectStyles ? Colors.red.shade800 : Colors.white),
                child: Text(
                  disconnectStyles ? "Disconnecting..." : "Disconnect",
                  style: TextStyle(
                    color: disconnectStyles ? Colors.white : Colors.black,
                    fontSize: 17,
                  ),
                ),
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
