// Comment text for the canvas: the editor wraps a comment to its box
// width, so hard line breaks inside a sentence stop it reflowing when the
// box is widened. reflow() joins those lines back into paragraphs and
// keeps the breaks that mean something:
//   - blank lines (paragraph breaks)
//   - a title first line (no lower-case letters)
//   - lines laid out in columns (a run of 2+ spaces) or starting "-"
//   - the line after one ending in ":"
const isTitle = l => /[A-Z]/.test(l) && !/[a-z]/.test(l);
const isTable = l => /\S {2,}\S/.test(l) || /^\s*-/.test(l);

export function reflow(text) {
  const out = [];
  for (const para of String(text).replace(/\r\n?/g, '\n').split(/\n{2,}/)) {
    const lines = para.split('\n');
    const kept = [];
    lines.forEach((line, i) => {
      const prev = kept.length ? kept[kept.length - 1] : null;
      const keepBreak = prev === null
        || (i === 1 && out.length === 0 && isTitle(lines[0]))
        || isTable(line) || isTable(prev)
        || /:\s*$/.test(prev);
      if (keepBreak) kept.push(line);
      else kept[kept.length - 1] = prev.replace(/\s+$/, '') + ' ' + line.replace(/^\s+/, '');
    });
    out.push(kept.join('\n'));
  }
  return out.join('\n\n');
}
