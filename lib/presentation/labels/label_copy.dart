import 'package:flutter/widgets.dart';

final class LabelCopy {
  LabelCopy(BuildContext context)
    : vi = Localizations.localeOf(context).languageCode == 'vi';
  final bool vi;
  String get labels => vi ? 'Nhãn' : 'Labels';
  String get removed => vi ? 'Nhãn đã xóa — bỏ gắn' : 'Removed label — detach';
  String get unavailable =>
      vi ? 'Nhãn chưa tải — bỏ gắn' : 'Label not loaded — detach';
  String get search => vi ? 'Tìm ghi chú' : 'Search notes';
  String get manage => vi ? 'Quản lý nhãn' : 'Manage labels';
  String get add => vi ? 'Thêm nhãn' : 'Add label';
  String get rename => vi ? 'Đổi tên nhãn' : 'Rename label';
  String get delete => vi ? 'Xóa nhãn' : 'Delete label';
  String get name => vi ? 'Tên nhãn' : 'Label name';
  String get cancel => vi ? 'Hủy' : 'Cancel';
  String get save => vi ? 'Lưu' : 'Save';
  String get filter =>
      vi ? 'Lọc theo nhãn (tất cả)' : 'Filter labels (all selected)';
  String get organize => vi ? 'Chọn nhãn cho ghi chú' : 'Choose note labels';
  String get clear => vi ? 'Xóa bộ lọc' : 'Clear filters';
  String get empty => vi ? 'Chưa có nhãn' : 'No labels yet';
  String get noResults =>
      vi ? 'Không có ghi chú phù hợp.' : 'No matching notes.';
  String get error => vi
      ? 'Không thể thay đổi nhãn. Kiểm tra quyền và xung đột.'
      : 'Cannot change label. Check access and conflicts.';
  String get invalid => vi
      ? 'Tên cần 1–64 ký tự Unicode, không có ký tự điều khiển.'
      : 'Use 1–64 Unicode characters without control characters.';
  String get keepLocal => vi ? 'Giữ bản local' : 'Keep local';
  String get useCloud => vi ? 'Dùng bản cloud' : 'Use cloud';
  String get confirmDelete => vi
      ? 'Xóa nhãn? Ghi chú vẫn được giữ.'
      : 'Delete this label? Notes will be retained.';
}
