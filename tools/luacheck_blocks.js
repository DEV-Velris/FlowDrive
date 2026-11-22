// Verificateur minimal de structure Lua : blocs, parentheses, chaines, commentaires.
// Usage : node luacheck_blocks.js fichier1.lua [fichier2.lua ...]
const fs = require('fs');

function check(path) {
  const src = fs.readFileSync(path, 'utf8');
  const errors = [];
  let i = 0, line = 1;
  const blocks = [];   // {kw, line}
  const brackets = []; // {ch, line}
  let pendingDo = 0;
  const pairs = { ')': '(', ']': '[', '}': '{' };
  const isNameStart = c => /[A-Za-z_]/.test(c);
  const isName = c => /[A-Za-z0-9_]/.test(c);

  function longBracketLevel(pos) {
    if (src[pos] !== '[') return -1;
    let j = pos + 1, level = 0;
    while (src[j] === '=') { level++; j++; }
    return src[j] === '[' ? level : -1;
  }
  function skipLong(pos, level) {
    const close = ']' + '='.repeat(level) + ']';
    const end = src.indexOf(close, pos);
    if (end < 0) { errors.push(`ligne ${line}: chaine/commentaire long non ferme`); return src.length; }
    for (let k = pos; k < end; k++) if (src[k] === '\n') line++;
    return end + close.length;
  }

  while (i < src.length) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }
    if (c === '-' && src[i + 1] === '-') {
      const lvl = longBracketLevel(i + 2);
      if (lvl >= 0) { i = skipLong(i + 2 + lvl + 2, lvl); continue; }
      while (i < src.length && src[i] !== '\n') i++;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c; i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === '\\') i++;
        else if (src[i] === '\n') { errors.push(`ligne ${line}: chaine non fermee`); break; }
        i++;
      }
      i++; continue;
    }
    if (c === '[') {
      const lvl = longBracketLevel(i);
      if (lvl >= 0) { i = skipLong(i + lvl + 2, lvl); continue; }
    }
    if ('([{'.includes(c)) { brackets.push({ ch: c, line }); i++; continue; }
    if (')]}'.includes(c)) {
      const top = brackets.pop();
      if (!top || top.ch !== pairs[c]) errors.push(`ligne ${line}: '${c}' sans ouverture correspondante (ouvert: ${top ? top.ch + ' ligne ' + top.line : 'rien'})`);
      i++; continue;
    }
    if (isNameStart(c)) {
      let j = i; while (j < src.length && isName(src[j])) j++;
      const w = src.slice(i, j);
      const prev = src[i - 1];
      if (prev !== '.' && prev !== ':') {
        if (w === 'function' || w === 'if' || w === 'repeat') blocks.push({ kw: w, line });
        else if (w === 'for' || w === 'while') { blocks.push({ kw: w, line }); pendingDo++; }
        else if (w === 'do') { if (pendingDo > 0) pendingDo--; else blocks.push({ kw: 'do', line }); }
        else if (w === 'end') {
          const top = blocks.pop();
          if (!top || top.kw === 'repeat') errors.push(`ligne ${line}: 'end' en trop (bloc: ${top ? top.kw + ' ligne ' + top.line : 'aucun'})`);
        } else if (w === 'until') {
          const top = blocks.pop();
          if (!top || top.kw !== 'repeat') errors.push(`ligne ${line}: 'until' sans 'repeat'`);
        }
      }
      i = j; continue;
    }
    i++;
  }
  for (const b of blocks) errors.push(`bloc '${b.kw}' ouvert ligne ${b.line} jamais ferme`);
  for (const b of brackets) errors.push(`'${b.ch}' ouvert ligne ${b.line} jamais ferme`);
  if (pendingDo !== 0) errors.push(`'for'/'while' sans 'do' (${pendingDo})`);
  return { errors, lines: line };
}

let failed = false;
for (const p of process.argv.slice(2)) {
  const r = check(p);
  if (r.errors.length) { failed = true; console.log(`ECHEC ${p}`); r.errors.forEach(e => console.log('  ' + e)); }
  else console.log(`OK ${p} (${r.lines} lignes)`);
}
process.exit(failed ? 1 : 0);
