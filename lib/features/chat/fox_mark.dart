import 'package:flutter/material.dart';

const _foxPathData = '''
M 69.148,11.253 L 65.093,14.519 L 62.503,19.363 L 62.953,20.264 L 69.599,22.066 L 71.626,23.530 L 71.176,24.319 L 69.937,23.305 L 65.093,21.503 L 62.503,21.390 L 58.898,16.321 L 52.478,10.915 L 48.423,9.113 L 47.297,9.113 L 44.931,14.745 L 44.819,26.346 L 47.297,30.739 L 47.522,32.429 L 44.368,36.821 L 41.440,38.173 L 41.890,38.286 L 41.327,38.962 L 41.102,38.511 L 41.327,40.989 L 42.341,41.214 L 43.242,43.467 L 43.918,43.467 L 45.720,45.607 L 48.761,47.184 L 50.000,48.536 L 52.027,48.423 L 53.830,49.324 L 53.041,52.027 L 46.283,59.799 L 46.621,61.038 L 46.846,60.701 L 50.563,63.179 L 50.901,62.841 L 61.376,67.234 L 63.404,68.810 L 63.179,69.261 L 64.305,70.838 L 63.854,71.401 L 61.940,70.162 L 60.813,68.698 L 59.687,68.810 L 50.113,64.530 L 46.508,62.503 L 44.481,60.701 L 42.791,58.448 L 41.552,54.731 L 42.341,53.041 L 42.003,51.577 L 43.918,48.761 L 41.440,46.959 L 34.794,46.283 L 36.709,46.396 L 33.330,46.396 L 34.456,46.508 L 30.739,46.846 L 27.923,47.747 L 21.277,51.126 L 16.997,57.434 L 15.871,60.363 L 15.533,63.516 L 16.096,70.725 L 16.659,70.951 L 16.547,71.626 L 19.475,77.258 L 21.390,79.849 L 26.684,84.580 L 34.118,88.635 L 35.920,89.085 L 36.709,89.986 L 48.761,90.887 L 56.420,89.761 L 64.305,86.382 L 65.544,84.805 L 66.445,84.580 L 66.896,85.706 L 69.824,84.580 L 74.217,79.624 L 75.343,79.060 L 75.343,78.047 L 77.033,75.456 L 78.497,71.401 L 79.173,67.571 L 78.610,61.602 L 76.582,57.434 L 76.470,56.195 L 73.203,52.140 L 67.797,48.761 L 54.280,45.607 L 51.690,44.255 L 48.423,41.102 L 48.648,40.313 L 52.365,39.074 L 53.942,39.525 L 55.294,38.624 L 57.772,38.511 L 63.516,40.088 L 63.516,40.651 L 64.981,40.764 L 64.868,41.102 L 65.544,40.989 L 69.036,43.129 L 71.964,43.918 L 80.074,43.918 L 80.187,45.382 L 78.835,46.846 L 75.907,48.536 L 71.964,48.874 L 71.626,49.324 L 72.190,50.113 L 72.865,49.662 L 76.019,49.662 L 79.849,47.860 L 83.566,43.805 L 84.354,42.003 L 84.129,41.327 L 81.201,40.313 L 79.511,38.849 L 77.709,34.343 L 77.596,35.019 L 76.920,31.753 L 76.808,32.091 L 75.456,28.712 L 72.527,25.332 L 72.640,24.544 L 73.766,25.332 L 74.217,24.995 L 73.766,19.926 L 71.739,14.181 Z
M 39.299,49.662 L 37.610,52.816 L 37.723,54.843 L 38.624,56.646 L 38.398,58.786 L 39.863,60.137 L 40.313,60.025 L 42.341,62.728 L 39.525,62.841 L 34.907,61.376 L 34.118,61.602 L 34.231,63.404 L 33.555,65.093 L 35.470,69.374 L 35.245,70.162 L 34.343,70.162 L 30.852,68.022 L 28.374,65.657 L 25.332,60.137 L 23.418,61.714 L 21.615,66.445 L 20.827,66.107 L 20.038,66.670 L 19.701,62.052 L 20.264,59.462 L 21.841,56.195 L 23.755,53.942 L 24.657,53.717 L 24.431,53.154 L 26.234,52.365 L 27.473,51.126 L 28.261,51.126 L 28.148,50.788 L 32.879,49.437 L 37.272,49.212 Z
M 62.953,36.258 L 63.516,34.907 L 65.319,33.442 L 68.810,33.780 L 70.049,34.681 L 69.599,36.709 L 67.234,35.582 L 65.093,35.695 L 63.179,36.821 Z
M 50.563,16.547 L 53.041,18.124 L 53.830,19.701 L 54.731,19.926 L 55.970,22.742 L 53.942,23.643 L 50.113,27.247 L 48.986,20.827 L 50.000,20.602 L 49.775,17.673 Z
''';

class FoxMark extends StatelessWidget {
  const FoxMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FoxGPT',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _FoxMarkPainter()),
      ),
    );
  }
}

class _FoxMarkPainter extends CustomPainter {
  const _FoxMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final path = _parseFoxPath();
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFF6F1C),
          Color(0xFFFC6117),
        ],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Path _parseFoxPath() {
  final path = Path()..fillType = PathFillType.evenOdd;
  final tokens = _foxPathData
      .replaceAll(',', ' ')
      .trim()
      .split(RegExp(r'\s+'));

  var index = 0;
  while (index < tokens.length) {
    final command = tokens[index++];
    switch (command) {
      case 'M':
        path.moveTo(
          double.parse(tokens[index++]),
          double.parse(tokens[index++]),
        );
        break;
      case 'L':
        path.lineTo(
          double.parse(tokens[index++]),
          double.parse(tokens[index++]),
        );
        break;
      case 'Z':
        path.close();
        break;
      default:
        throw FormatException('Commande de tracé FoxGPT inconnue: $command');
    }
  }
  return path;
}
