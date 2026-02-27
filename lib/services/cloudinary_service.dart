import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const String _cloudName = 'hDdpfVjB2tzz8qglCiWzWGqXMzM';
  static const String _uploadPreset = 'student_upload';

  /// Uploads [imageFile] to Cloudinary and returns the secure URL,
  /// or null if the upload fails.
  static Future<String?> uploadImage(File imageFile) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = _uploadPreset;
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );

    final response = await request.send();

    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      final jsonData = json.decode(responseData) as Map<String, dynamic>;
      return jsonData['secure_url'] as String?;
    } else {
      return null;
    }
  }
}
