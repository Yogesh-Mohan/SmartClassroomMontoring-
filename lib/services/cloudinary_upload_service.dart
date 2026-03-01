import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class CloudinaryUploadService {
  const CloudinaryUploadService._();

  static const String _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const String _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static const String _defaultCloudName = 'dhynkthie';
  static const String _defaultUploadPreset = 'student_upload';

  static String get _effectiveCloudName {
    final value = _cloudName.trim();
    if (value.isNotEmpty) return value;
    return _defaultCloudName;
  }

  static String get _effectiveUploadPreset {
    final value = _uploadPreset.trim();
    if (value.isNotEmpty) return value;
    return _defaultUploadPreset;
  }

  static bool get isConfigured =>
      _effectiveCloudName.trim().isNotEmpty && _effectiveUploadPreset.trim().isNotEmpty;

  static String get configHelp =>
      'Cloudinary is not configured. Pass --dart-define=CLOUDINARY_CLOUD_NAME=... and --dart-define=CLOUDINARY_UPLOAD_PRESET=...';

  static Future<String?> uploadImage({
    required File imageFile,
    required String cloudName,
    required String uploadPreset,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

    final response = await request.send();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final responseData = await response.stream.bytesToString();
    final jsonData = json.decode(responseData) as Map<String, dynamic>;
    return jsonData['secure_url'] as String?;
  }

  static Future<String> uploadFile({
    required File file,
    String resourceType = 'auto',
    String? folder,
  }) async {
    if (!isConfigured) {
      throw Exception(configHelp);
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_effectiveCloudName/$resourceType/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _effectiveUploadPreset;
    if (folder != null && folder.trim().isNotEmpty) {
      request.fields['folder'] = folder.trim();
    }

    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await request.send();
    final responseData = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed (${response.statusCode}): $responseData');
    }

    final jsonData = json.decode(responseData) as Map<String, dynamic>;
    final secureUrl = (jsonData['secure_url'] ?? '').toString();
    if (secureUrl.isEmpty) {
      throw Exception('Cloudinary upload succeeded but no secure_url was returned.');
    }
    return secureUrl;
  }

  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String resourceType = 'auto',
    String? folder,
  }) async {
    if (!isConfigured) {
      throw Exception(configHelp);
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_effectiveCloudName/$resourceType/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _effectiveUploadPreset;
    if (folder != null && folder.trim().isNotEmpty) {
      request.fields['folder'] = folder.trim();
    }

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
      contentType: _mediaTypeFromContentType(contentType),
    ));

    final response = await request.send();
    final responseData = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed (${response.statusCode}): $responseData');
    }

    final jsonData = json.decode(responseData) as Map<String, dynamic>;
    final secureUrl = (jsonData['secure_url'] ?? '').toString();
    if (secureUrl.isEmpty) {
      throw Exception('Cloudinary upload succeeded but no secure_url was returned.');
    }
    return secureUrl;
  }

  static MediaType? _mediaTypeFromContentType(String contentType) {
    final raw = contentType.trim();
    if (raw.isEmpty || !raw.contains('/')) return null;
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    return MediaType(parts[0], parts[1]);
  }
}
