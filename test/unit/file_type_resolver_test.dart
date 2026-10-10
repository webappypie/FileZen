import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:filezen/features/files/presentation/resolvers/file_type_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

void main() {
  late Directory dir;
  setUpAll(() async => dir = await Directory.systemTemp.createTemp('filezen_types_'));
  tearDownAll(() async => dir.delete(recursive: true));

  Future<FileViewerKind> resolve(String name, List<int> bytes, {String? mime}) async {
    final f = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return FileTypeResolver.resolveFile(f.path, mimeType: mime);
  }

  List<int> zip(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      final data = utf8.encode(content);
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return ZipEncoder().encode(archive)!;
  }

  Future<List<int>> realPdf() async {
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Invoice 42')));
    return doc.save();
  }

  test('real files of every supported format resolve to the right viewer', () async {
    final pdf = await realPdf();
    final ooxml = zip({'[Content_Types].xml': '<Types/>', 'word/document.xml': '<w:document/>'});
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13];
    final mp4 = [0, 0, 0, 0x18, ...ascii.encode('ftypisom'), 0, 0, 0, 0];
    final m4a = [0, 0, 0, 0x18, ...ascii.encode('ftypM4A '), 0, 0, 0, 0];

    final cases = <String, (List<int>, FileViewerKind)>{
      'statement.pdf': (pdf, FileViewerKind.pdf),
      'SCAN.PDF': (pdf, FileViewerKind.pdf),
      'report.docx': (ooxml, FileViewerKind.office),
      'budget.xlsx': (ooxml, FileViewerKind.office),
      'deck.pptx': (ooxml, FileViewerKind.office),
      'legacy.doc': ([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], FileViewerKind.office),
      'legacy.XLS': ([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], FileViewerKind.office),
      'legacy.ppt': ([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], FileViewerKind.office),
      'feed.xml': (utf8.encode('<?xml version="1.0"?><rss/>'), FileViewerKind.markup),
      'page.HTML': (utf8.encode('<!doctype html><p>hi</p>'), FileViewerKind.markup),
      'logo.svg': (utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'), FileViewerKind.markup),
      'data.json': (utf8.encode('{"a": 1}'), FileViewerKind.text),
      'table.csv': (utf8.encode('a,b\n1,2\n'), FileViewerKind.text),
      'notes.txt': (utf8.encode('plain notes'), FileViewerKind.text),
      'README.md': (utf8.encode('# Title'), FileViewerKind.text),
      'main.dart': (utf8.encode('void main() {}'), FileViewerKind.text),
      'Script.PY': (utf8.encode('print(1)'), FileViewerKind.text),
      'backup.zip': (zip({'a.txt': 'x'}), FileViewerKind.archive),
      'logs.gz': ([0x1F, 0x8B, 0x08, 0x00], FileViewerKind.archive),
      'photo.jpg': ([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10], FileViewerKind.image),
      'image.PNG': (png, FileViewerKind.image),
      'clip.mp4': (mp4, FileViewerKind.video),
      'clip.MOV': (mp4, FileViewerKind.video),
      'voice.m4a': (m4a, FileViewerKind.audio),
      'song.mp3': ([0x49, 0x44, 0x33, 3, 0], FileViewerKind.audio),
      'track.ogg': (ascii.encode('OggS\x00\x02'), FileViewerKind.audio),
      'app.apk': (zip({'AndroidManifest.xml': 'x'}), FileViewerKind.external),
      'archive.7z': ([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], FileViewerKind.external),
      'mystery.xyz': (utf8.encode('???'), FileViewerKind.external),
      'letter.rtf': (utf8.encode(r'{\rtf1 hello}'), FileViewerKind.external),
    };

    for (final entry in cases.entries) {
      final (bytes, expected) = entry.value;
      expect(await resolve(entry.key, bytes), expected, reason: entry.key);
    }
  });

  test('content decides over a wrong extension or MIME type', () async {
    final pdf = await realPdf();
    expect(await resolve('invoice.txt', pdf), FileViewerKind.pdf, reason: 'PDF must never open as text');
    expect(await resolve('download', pdf), FileViewerKind.pdf, reason: 'no extension');
    expect(await resolve('photo.txt', [0xFF, 0xD8, 0xFF, 0xE0]), FileViewerKind.image);
    expect(await resolve('bundle.txt', zip({'x': 'y'})), FileViewerKind.archive);
    expect(await resolve('file.bin', pdf, mime: 'application/octet-stream'), FileViewerKind.pdf);
    expect(await resolve('weird.dat', utf8.encode('hello'), mime: 'text/plain'), FileViewerKind.text);
  });

  test('binary data is never routed to the text viewer', () async {
    expect(await resolve('dump.txt', [0x41, 0x00, 0x42, 0x00, 0x13]), FileViewerKind.external);
    expect(await resolve('data.json', [0x7B, 0x00, 0x7D]), FileViewerKind.external);
  });

  test('missing, empty and unreadable files fall back to the name', () async {
    expect(await resolve('empty.txt', const []), FileViewerKind.text);
    expect(
      await FileTypeResolver.resolveFile(p.join(dir.path, 'does_not_exist.pdf')),
      FileViewerKind.pdf,
    );
  });

  test('extension normalisation', () {
    expect(FileTypeResolver.normalizeExtension('.PDF'), 'pdf');
    expect(FileTypeResolver.normalizeExtension(' Docx '), 'docx');
    expect(FileTypeResolver.resolve(extension: '.JPEG'), FileViewerKind.image);
  });
}
