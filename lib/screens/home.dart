import 'package:device_info_plus/device_info_plus.dart';
import 'package:first_app/widgets/button.dart';
import 'package:first_app/widgets/status_card.dart';
import 'package:first_app/widgets/input.dart';
import 'package:first_app/widgets/transfer_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _formKey = GlobalKey<FormState>();
  final _cropController = CropController();
  bool _isImageUploading = false;
  bool _isCropping = false;
  Uint8List? _imageData;
  final FocusNode _focusNode = FocusNode();
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
  String? _croppedFilePath;
  TransferMode _transferMode = TransferMode.passive;
  FTPConnect? _ftpConnect2;
  bool _isConnected = false;

  dynamic disconnectStyles = false;
  void _clearFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _connectToFtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ftpConnect2 != null) return;
    setState(() {
      _connectionStatus = "Connecting...";
    });

    _ftpConnect2 = FTPConnect(
      _hostController.text,
      user: _usernameController.text.trimRight(),
      pass: _passwordController.text.trimRight(),
      port: int.parse(_portController.text),
      timeout: 60,
      showLog: true,
      logger: Logger(),
    );

    try {
      bool isConnected = await _ftpConnect2!.connect();
      if (isConnected) {
        _ftpConnect2?.transferMode = _transferMode;
        await _ftpConnect2?.sendCustomCommand('TYPE I');
        setState(() {
          _isConnected = true;
          disconnectStyles = false;
          _connectionStatus = "Connected successfully";
        });
      } else {
        setState(() {
          _isConnected = false;
          _connectionStatus = "Connection failed";
        });
      }
    } catch (e) {
      print("Connect $e");
      setState(() {
        _connectionStatus = "Connection error:`$e`";
        _isImageUploading = false;
        _isConnected = false;
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
                _clearFocus();
                Navigator.pop(context);
                setState(() {
                  _isImageUploading = false;
                  _connectionStatus =
                      _isConnected ? "Connected successfully" : "Disconnected";
                });
              },
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.check, color: Colors.white),
                onPressed: _isCropping
                    ? null
                    : () {
                        _clearFocus();
                        setState(() {
                          _connectionStatus = "Starting upload process...";
                        });
                        _cropController.crop();
                        Navigator.pop(context);
                      },
              ),
            ],
            title: Text('Cropper', style: TextStyle(color: Colors.white)),
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
                    setState(() {
                      _isCropping = true;
                    });
                    try {
                      final img.Image? originalImage =
                          img.decodeImage(croppedData);
                      if (originalImage != null) {
                        final img.Image resizedImage = img.copyResize(
                            originalImage,
                            width: 480,
                            height: 320,
                            interpolation: img.Interpolation.linear);

                        final processedData =
                            img.encodeJpg(resizedImage, quality: 100);

                        final tempDir = await getTemporaryDirectory();
                        final file = File(
                            '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
                        await file.writeAsBytes(processedData);
                        _croppedFilePath = file.path;
                        await _uploadFile();
                      }
                    } catch (e) {
                      print("Cropping error: $e");
                      setState(() {
                        _connectionStatus = "Error processing image: $e";
                      });
                    } finally {
                      setState(() => _isCropping = false);
                    }
                  },
                  initialSize: 1,
                  maskColor: Colors.black.withOpacity(0.7),
                  baseColor: Colors.black,
                  progressIndicator:
                      Text("Loading...", style: TextStyle(color: Colors.white)),
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

      setState(() {
        _connectionStatus = "Picking image...";
        _isImageUploading = true;
      });

      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: false);

      if (result != null) {
        _selectedFileName = result.files.single.name;

        // Read image data
        final file = File(result.files.single.path!);
        _imageData = await file.readAsBytes();

        // Show crop dialog
        // ignore: use_build_context_synchronously
        await _showCropDialog(context);
      }
      if (result == null) {
        setState(() {
          _isImageUploading = false;
          _connectionStatus =
              _isConnected ? "Connected successfully" : "Disconnected";
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
        _ftpConnect2 = null;
      }
    } catch (e) {
      setState(() {
        _connectionStatus = "Error $e";
      });
    } finally {
      setState(() {
        _connectionStatus = "Disconnected Successfully";
        _isImageUploading = false;
        disconnectStyles = false;
        _isConnected = false;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
        title: Text("FTP File Uploader"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: GestureDetector(
            onTap: _clearFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextInput(
                  controller: _hostController,
                  labelText: 'Host',
                  hintText: 'Enter FTP host',
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter host' : null,
                ),
                const SizedBox(height: 16),
                TextInput(
                  controller: _portController,
                  labelText: 'Port',
                  hintText: 'Enter port (default: 21)',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value?.isEmpty ?? true) return 'Please enter port';
                    if (int.tryParse(value!) == null) {
                      return 'Please enter a valid port number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextInput(
                  controller: _usernameController,
                  labelText: 'Username',
                  hintText: 'Enter FTP username',
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter username' : null,
                ),
                const SizedBox(height: 16),
                TextInput(
                  controller: _passwordController,
                  labelText: 'Password',
                  hintText: 'Enter FTP password',
                  isPassword: true,
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter password' : null,
                ),
                const SizedBox(height: 16),
                TransferModeDropdown(
                  value: _transferMode,
                  onChanged: (value) {
                    setState(() {
                      _transferMode = value!;
                    });
                  },
                ),
                const SizedBox(height: 24),
                Button(
                  onPressed: () {
                    _clearFocus();
                    _connectToFtp();
                  },
                  text: _isConnected ? "Connected" : "Connect to Server",
                  backgroundColor:
                      _isConnected ? Colors.green.shade600 : Colors.white,
                  textColor: _isConnected ? Colors.white : Colors.black,
                ),
                const SizedBox(height: 16),
                Button(
                  onPressed: _isImageUploading ? null : _pickImage,
                  text: "Select File",
                  isLoading: _isImageUploading,
                ),
                const SizedBox(height: 16),
                Button(
                  onPressed: () async {
                    _clearFocus();
                    setState(() {
                      _connectionStatus = "Disconnecting...";
                      disconnectStyles = true;
                      _isConnected = false;
                    });
                    await Future.delayed(const Duration(milliseconds: 1000));

                    await disconnect();
                  },
                  text: disconnectStyles ? "Disconnecting..." : "Disconnect",
                  backgroundColor:
                      disconnectStyles ? Colors.red.shade800 : Colors.white,
                  textColor: disconnectStyles ? Colors.white : Colors.black,
                ),
                const SizedBox(height: 24),
                StatusCard(status: _connectionStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
