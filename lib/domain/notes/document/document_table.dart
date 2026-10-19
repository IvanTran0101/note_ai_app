import 'document_inline.dart';

final class DocumentCell {
  DocumentCell({required this.id, required Iterable<DocumentInline> runs})
    : runs = freezeDocumentRuns(runs) {
    requireDocumentId(id);
  }
  final String id;
  final List<DocumentInline> runs;
  String get plainText => runs.map((run) => run.plainText).join();
  @override
  bool operator ==(Object other) =>
      other is DocumentCell &&
      other.id == id &&
      sameDocumentValues(other.runs, runs);
  @override
  int get hashCode => Object.hash(id, Object.hashAll(runs));
}

final class DocumentRow {
  DocumentRow({required this.id, required Iterable<DocumentCell> cells})
    : cells = List.unmodifiable(cells) {
    requireDocumentId(id);
  }
  final String id;
  final List<DocumentCell> cells;
  @override
  bool operator ==(Object other) =>
      other is DocumentRow &&
      other.id == id &&
      sameDocumentValues(other.cells, cells);
  @override
  int get hashCode => Object.hash(id, Object.hashAll(cells));
}

void requireDocumentId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) {
    throw ArgumentError('Invalid document identity.');
  }
}

bool sameDocumentValues<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((index) => a[index] == b[index]);
