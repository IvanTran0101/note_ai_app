/// Bounded offline math syntax. The Presentation renderer also parses it and
/// reports invalid expressions before applying an editor transaction.
void validateDocumentMath(String expression) {
  if (expression.isEmpty ||
      expression.length > 512 ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(expression)) {
    throw ArgumentError('Invalid inline equation.');
  }
  var depth = 0;
  for (var i = 0; i < expression.length; i++) {
    final character = expression[i];
    if (character == '{' && (i == 0 || expression[i - 1] != r'\')) depth++;
    if (character == '}' && (i == 0 || expression[i - 1] != r'\')) depth--;
    if (depth < 0 || depth > 8) {
      throw ArgumentError('Invalid equation grouping.');
    }
  }
  if (depth != 0) throw ArgumentError('Invalid equation grouping.');
  for (final command in RegExp(r'\\([A-Za-z]+)').allMatches(expression)) {
    if (!_commands.contains(command.group(1))) {
      throw ArgumentError('Unsupported equation command.');
    }
  }
}

const _commands = {
  'frac',
  'sqrt',
  'sum',
  'prod',
  'int',
  'lim',
  'sin',
  'cos',
  'tan',
  'log',
  'ln',
  'exp',
  'min',
  'max',
  'alpha',
  'beta',
  'gamma',
  'delta',
  'theta',
  'lambda',
  'mu',
  'pi',
  'sigma',
  'phi',
  'omega',
  'Gamma',
  'Delta',
  'Theta',
  'Lambda',
  'Pi',
  'Sigma',
  'Phi',
  'Omega',
  'infty',
  'times',
  'cdot',
  'div',
  'pm',
  'mp',
  'le',
  'leq',
  'ge',
  'geq',
  'ne',
  'neq',
  'approx',
  'equiv',
  'in',
  'notin',
  'subset',
  'subseteq',
  'cup',
  'cap',
  'emptyset',
  'forall',
  'exists',
  'partial',
  'nabla',
  'ldots',
  'cdots',
  'left',
  'right',
  'mathbb',
  'mathbf',
  'mathrm',
  'overline',
  'underline',
  'vec',
  'hat',
  'bar',
  'text',
};
