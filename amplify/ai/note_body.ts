const prefix = 'noteflow:rich:v1\n';

function validAttribute(key: string, value: unknown): boolean {
  switch (key) {
    case 'bold': case 'italic': case 'underline': case 'strike': case 'code':
    case 'blockquote': case 'code-block': return typeof value === 'boolean';
    case 'header': return Number.isInteger(value) && Number(value) >= 1 && Number(value) <= 6;
    case 'indent': return Number.isInteger(value) && Number(value) >= 0 && Number(value) <= 8;
    case 'color': case 'background': return typeof value === 'string' && [7, 9].includes(value.length) && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value);
    case 'size': return typeof value === 'string' && (['small', 'large', 'huge'].includes(value) ||
      (/^\d+(\.\d+)?$/.test(value) && Number(value) >= 8 && Number(value) <= 96));
    case 'list': return typeof value === 'string' && ['ordered', 'bullet', 'checked', 'unchecked'].includes(value);
    case 'align': return typeof value === 'string' && ['left', 'center', 'right', 'justify'].includes(value);
    case 'direction': return value === 'rtl';
    case 'script': return value === 'sub' || value === 'super';
    case 'font': return typeof value === 'string' && value.length <= 100;
    case 'link': return typeof value === 'string' && /^(http|https|mailto):/i.test(value);
    default: return false;
  }
}

/** Matches the client's text-only format; unknown content remains literal. */
export function noteBodyText(content: string): string {
  if (!content.startsWith(prefix)) return content;
  try {
    const operations: unknown = JSON.parse(content.slice(prefix.length));
    if (!Array.isArray(operations) || !operations.length) return content;
    let text = '';
    for (const op of operations) {
      if (!op || typeof op !== 'object' || Array.isArray(op) ||
          typeof op.insert !== 'string' || !op.insert.length ||
          Object.keys(op).some(key => key !== 'insert' && key !== 'attributes')) return content;
      if (op.attributes != null && (typeof op.attributes !== 'object' ||
          Array.isArray(op.attributes) || Object.entries(op.attributes).some(([key, value]) =>
            !validAttribute(key, value)))) return content;
      text += op.insert;
    }
    return text.endsWith('\n') ? text.slice(0, -1) : content;
  } catch {
    return content;
  }
}
