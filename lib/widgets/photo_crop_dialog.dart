import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shows a circle crop dialog. Returns cropped image bytes or null if cancelled.
Future<Uint8List?> showPhotoCropDialog(BuildContext context, Uint8List imageBytes) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _CropDialog(imageBytes: imageBytes),
  );
}

class _CropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropDialog({required this.imageBytes});
  @override State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  final _repaintKey = GlobalKey();
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  ui.Image? _uiImage;
  bool _loading = true;
  bool _cropping = false;
  double _cropSize = 300;

  // Minimum scale = image fits exactly inside the circle (no black bars)
  double _minScale = 0.1;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    setState(() {
      _uiImage = img;
      _loading = false;
      // Fit image to fill the crop circle initially
      final scaleW = _cropSize / img.width;
      final scaleH = _cropSize / img.height;
      _scale = max(scaleW, scaleH); // fill — largest dimension fills circle
      _minScale = min(scaleW, scaleH) * 0.5; // can zoom out to see full image
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = _scale;
    _baseOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_baseScale * d.scale).clamp(_minScale, 8.0);
      _offset = _baseOffset + d.focalPointDelta;
    });
  }

  Future<void> _crop() async {
    setState(() => _cropping = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final result = byteData!.buffer.asUint8List();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _cropSize = min(size.width, size.height) * 0.78;
    final w = size.width;
    final scale = (w / 390.0).clamp(0.72, 1.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(16 * scale),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: EdgeInsets.only(bottom: 16 * scale),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              onTap: () => Navigator.pop(context, null),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10 * scale)),
                child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 14 * scale))),
            ),
            Text('Adjust Photo', style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.w700)),
            GestureDetector(
              onTap: _cropping ? null : _crop,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C5CFA), Color(0xFF5A3FD6)]),
                  borderRadius: BorderRadius.circular(10 * scale)),
                child: _cropping
                  ? SizedBox(width: 14 * scale, height: 14 * scale, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Use Photo', style: TextStyle(color: Colors.white, fontSize: 14 * scale, fontWeight: FontWeight.w700))),
            ),
          ]),
        ),

        // Crop area with circle overlay
        SizedBox(
          width: _cropSize, height: _cropSize,
          child: Stack(children: [
            // The actual content that gets captured
            ClipOval(
              child: RepaintBoundary(
                key: _repaintKey,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Container(
                    width: _cropSize, height: _cropSize,
                    color: Colors.black,
                    child: _loading || _uiImage == null
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFA)))
                      : OverflowBox(
                          maxWidth: double.infinity,
                          maxHeight: double.infinity,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..translate(_offset.dx, _offset.dy)
                              ..scale(_scale),
                            alignment: Alignment.center,
                            child: Image.memory(widget.imageBytes, fit: BoxFit.none, filterQuality: FilterQuality.high),
                          ),
                        ),
                  ),
                ),
              ),
            ),
            // Circle border overlay
            IgnorePointer(
              child: CustomPaint(
                size: Size(_cropSize, _cropSize),
                painter: _CircleBorderPainter(),
              ),
            ),
          ]),
        ),

        SizedBox(height: 12 * scale),
        Text('Pinch to zoom • Drag to reposition',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12 * scale)),
        SizedBox(height: 8 * scale),
      ]),
    );
  }
}

class _CircleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    // Subtle white circle border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 1, borderPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
