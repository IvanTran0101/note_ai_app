/// Search aliases only; the user's slash query remains unchanged in the note.
String foldBlockSearch(String value) {
  var folded = value.toLowerCase();
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in groups.entries) {
    for (final rune in entry.value.runes) {
      folded = folded.replaceAll(String.fromCharCode(rune), entry.key);
    }
  }
  return folded.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
}

const vietnameseBlockAliases = [
  'văn bản đoạn văn',
  'tiêu đề 1',
  'tiêu đề 2',
  'tiêu đề 3',
  'tiêu đề 4',
  'danh sách dấu đầu dòng',
  'danh sách đánh số',
  'việc cần làm hộp kiểm',
  'danh sách thu gọn',
  'khung chú thích',
  'trích dẫn',
  'bảng',
  'đường phân cách',
];
