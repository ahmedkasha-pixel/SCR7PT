import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

abstract class GalleryPicker {
  Future<List<Uint8List>> pickImages();
}

class ImagePickerGallery implements GalleryPicker {
  ImagePickerGallery({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<Uint8List>> pickImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 92,
      maxWidth: 2400,
    );
    final images = <Uint8List>[];
    for (final file in files) {
      images.add(await file.readAsBytes());
    }
    return images;
  }
}
