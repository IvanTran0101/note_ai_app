import '../../application/labels/local_label_state.dart';
import '../../application/sync/note_sync_status.dart';
import '../../domain/labels/label.dart';
import '../../domain/labels/label_projection.dart';
import '../sync/local_sync_codec_reader.dart';

abstract final class LabelCodec {
  static const fields = {
    'id',
    'ownerId',
    'name',
    'createdAt',
    'updatedAt',
    'deletedAt',
    'serverRevision',
    'status',
    'conflictRemote',
  };
  static Map<String, Object?> encode(LocalLabelState label) => {
    'id': label.id,
    'ownerId': label.ownerId,
    'name': label.name,
    'createdAt': label.createdAt.toIso8601String(),
    'updatedAt': label.updatedAt.toIso8601String(),
    'deletedAt': label.deletedAt?.toIso8601String(),
    'serverRevision': label.serverRevision,
    'status': label.status.name,
    'conflictRemote': label.conflictRemote == null
        ? null
        : encode(label.conflictRemote!),
  };
  static LocalLabelState decode(Object? raw, {bool nested = false}) {
    final r = SyncCodecObject.from(raw, path: 'label', allowedFields: fields);
    return decodeRecord(r, nested: nested);
  }

  static LocalLabelState decodeRecord(
    SyncCodecObject r, {
    bool nested = false,
  }) {
    final remote = r.rawValue('conflictRemote');
    if (nested && remote != null) {
      throw const FormatException('Nested label conflict.');
    }
    return buildCodecModel(
      () => LocalLabelState(
        id: r.requireNonBlankString('id'),
        ownerId: r.requireNonBlankString('ownerId'),
        name: r.requireString('name'),
        createdAt: r.requireTimestamp('createdAt'),
        updatedAt: r.requireTimestamp('updatedAt'),
        deletedAt: r.requireNullableTimestamp('deletedAt'),
        serverRevision: r.requireNonNegativeInt('serverRevision'),
        status: r.requireEnum('status', NoteSyncStatus.values),
        conflictRemote: remote == null ? null : decode(remote, nested: true),
      ),
      path: r.path,
    );
  }

  static LocalLabelState decodeWire(Object? raw) {
    if (raw is! Map) throw const FormatException('Label snapshot required.');
    final value = Map<String, Object?>.from(raw);
    final mapped = <String, Object?>{
      'id': value['id'],
      'ownerId': value['ownerId'],
      'name': value['name'],
      'createdAt': value['createdAt'],
      'updatedAt': value['serverUpdatedAt'],
      'deletedAt': value['deletedAt'],
      'serverRevision': value['revision'],
      'status': 'synced',
      'conflictRemote': null,
    };
    final r = SyncCodecObject.from(
      mapped,
      path: 'label',
      allowedFields: fields,
    );
    if (r.requirePositiveInt('serverRevision') < 1) {
      throw const FormatException();
    }
    return decode(mapped);
  }

  static List<String> ids(Object? raw) {
    if (raw is! List || raw.any((v) => v is! String)) {
      throw const FormatException('Label IDs required.');
    }
    final values = raw.cast<String>();
    final result = freezeLabelIds(values);
    if (result.length != values.length) {
      throw const FormatException('Duplicate label ID.');
    }
    return result;
  }

  static List<Map<String, Object?>> projections(
    Iterable<LabelProjection> values,
  ) =>
      values.map((l) => <String, Object?>{'id': l.id, 'name': l.name}).toList();
  static List<LabelProjection> decodeProjections(Object? raw) {
    if (raw is! List || raw.length > 32) {
      throw const FormatException('Label projection required.');
    }
    final values = raw.map((v) {
      final r = SyncCodecObject.from(
        v,
        path: 'labelProjection',
        allowedFields: {'id', 'name'},
      );
      return LabelProjection(
        id: r.requireNonBlankString('id'),
        name: r.requireString('name'),
      );
    }).toList();
    if (values.map((l) => l.id).toSet().length != values.length) {
      throw const FormatException('Duplicate label projection.');
    }
    return List.unmodifiable(values);
  }
}
