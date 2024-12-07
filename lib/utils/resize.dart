import 'dart:io';
import 'package:image/image.dart' as img;

// ignore: unused_element
Future<File> _resizeImage(String imagePath) async {
  // Read image file
  final File imageFile = File(imagePath);
  final List<int> imageBytes = await imageFile.readAsBytes();
  final img.Image? originalImage = img.decodeImage(imageBytes as dynamic);

  if (originalImage == null) throw Exception('Failed to decode image');

  // Resize image
  final img.Image resizedImage = img.copyResize(
    originalImage,
    width: 480,
    height: 320,
    interpolation: img.Interpolation.linear,
  );

  // Get temporary directory to store resized image
  final Directory tempDir = await Directory.systemTemp.createTemp();
  final String tempPath =
      '${tempDir.path}/resized_${DateTime.now().millisecondsSinceEpoch}.jpg';

  // Save resized image
  final List<int> resizedBytes = img.encodeJpg(resizedImage, quality: 90);
  final File resizedFile = File(tempPath);
  await resizedFile.writeAsBytes(resizedBytes);

  return resizedFile;
}
