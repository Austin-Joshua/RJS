files = ['lib/src/screens/map_screen.dart', 'lib/src/map/map_layer_placeholders.dart']
for path in files:
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    text = text.replace("import 'package:maplibre_gl/mapbox_gl.dart';", "import 'package:maplibre_gl/maplibre_gl.dart';")
    text = text.replace("import 'package:maplibre_gl/mapbox_gl.dart' as maplibre;", "import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
print('Fixed imports in other files!!!')
