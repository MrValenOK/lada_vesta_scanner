import 'dart:io';

void main() async {
  final output = File('project_analysis.txt');
  final sink = output.openWrite();
  
  final pubspec = File('pubspec.yaml');
  if (await pubspec.exists()) {
    sink.writeln('// ===== FILE: pubspec.yaml =====');
    sink.writeln(await pubspec.readAsString());
    sink.writeln('// ===== END OF FILE =====\n');
  }

  final libDir = Directory('lib');
  if (await libDir.exists()) {
    final files = libDir.listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
      
    for (final file in files) {
      final relativePath = file.path.replaceAll('\\', '/');
      sink.writeln('// ===== FILE: $relativePath =====');
      sink.writeln(await file.readAsString());
      sink.writeln('// ===== END OF FILE =====\n');
    }
  }
  
  await sink.close();
  print('Done');
}