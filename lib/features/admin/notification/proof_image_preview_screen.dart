import 'package:flutter/material.dart';

class ProofImagePreviewScreen extends StatelessWidget {
  const ProofImagePreviewScreen({
    super.key,
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Proof Preview'),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4.0,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Unable to load image',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
