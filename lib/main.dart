import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

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
  final _cropController = CropController();
  bool _isImageUploading = false;
  bool _isCropping = false;
  Uint8List? _imageData;

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
      setState(() {
        _connectionStatus = "Connection error: $e";
        _isImageUploading = false;
      });
    }
  }

  Future<void> _showCropDialog(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            leading: IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isImageUploading = false;
                });
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.check, color: Colors.white),
                onPressed: _isCropping
                    ? null
                    : () async {
                        Navigator.pop(context); // Close immediately
                        _cropController.crop(); // Start cropping after closing
                        await _uploadFile();
                      },
              ),
            ],
            title: Text(
              'Cropper',
              style: TextStyle(color: Colors.white),
            ),
          ),
          backgroundColor: Colors.black,
          body: Column(
            children: [
              Expanded(
                child: Crop(
                  controller: _cropController,
                  image: _imageData!,
                  aspectRatio: 480 / 320,
                  onCropped: (croppedData) async {
                    setState(() => _isCropping = true);
                    try {
                      final tempDir = await getTemporaryDirectory();
                      final file = File(
                          '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await file.writeAsBytes(croppedData);
                      _croppedFilePath = file.path;
                    } catch (e) {
                      print("Cropping error: $e");
                      setState(() {
                        _connectionStatus = "Error processing image: $e";
                      });
                    } finally {
                      setState(() {
                        _isCropping = false;
                      });
                    }
                  },
                  initialSize: 1,
                  maskColor: Colors.black.withOpacity(0.7),
                  baseColor: Colors.black,
                  progressIndicator: Text(
                    "Loading...",
                    style: TextStyle(color: Colors.white),
                  ),
                  cornerDotBuilder: (size, edgeAlignment) =>
                      const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        final photos = await Permission.photos.request();
        return photos.isGranted;
      } else if (androidInfo.version.sdkInt >= 30) {
        final storage = await Permission.storage.request();
        return storage.isGranted;
      } else {
        final storage = await Permission.storage.request();
        return storage.isGranted;
      }
    }
    return true;
  }

  Future<void> _pickImage() async {
    try {
      bool hasPermission = await _requestPermissions();
      if (!hasPermission) {
        setState(() {
          _connectionStatus = "Storage permission required";
          _isImageUploading = false;
        });
        return;
      }

      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: false);

      if (result != null) {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;

        // Read image data
        final file = File(result.files.single.path!);
        _imageData = await file.readAsBytes();

        // Show crop dialog
        await _showCropDialog(context);
      }
      if (result == null) {
        setState(() {
          _isImageUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = "Error picking image: $e";
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

      // Set binary mode explicitly before upload
      await _ftpConnect2?.sendCustomCommand('TYPE I');

      print("File size: ${await file.length()}");
      print("File name: $_selectedFileName");
      print("File path: ${file.path}");

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
        _isImageUploading = false;
        _connectionStatus =
            uploaded ? "File uploaded successfully!" : "Upload failed";
      });
    } catch (e) {
      setState(() {
        _connectionStatus = "Upload failed: ${e.toString()}";
        _isImageUploading = false;
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
                    _isConnected = false;
                  });
                  await Future.delayed(const Duration(milliseconds: 1000));
                  await disconnect();
                  setState(() {
                    _connectionStatus = "Disconnected Successfully";
                    _isImageUploading = false;
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
