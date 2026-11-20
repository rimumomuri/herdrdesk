// Chat tables use pipe-delimited rows. Recover a flattened table only when it
// has an explicit separator row and every following row has the same width.
const tableDivider=/^:?-{3,}:?$/;
const isTableLine=line=>line.trim().startsWith('|')&&line.trim().endsWith('|');
function tableCells(line){
  if(!line.includes('|'))return [];
  return line.trim().replace(/^\||\|$/g,'').split(/(?<!\\)\|/).map(cell=>cell.trim().replace(/\\\|/g,'|'));
}

function flattenedTableRows(line){
  const cleaned=line.trim().replace(/^&#x20;[ \t]*/i,'').replace(/^\\\|/,'|');
  if(!isTableLine(cleaned))return [cleaned===line.trim()?line:cleaned];
  const rows=cleaned.split(/(?<=\|)[ \t]+(?=\|)/);
  const width=tableCells(rows[0]).length;
  if(rows.length<3||width<2)return [cleaned];
  const rule=tableCells(rows[1]);
  return rule.length===width&&rule.every(cell=>tableDivider.test(cell))
    &&rows.slice(2).every(row=>tableCells(row).length===width)?rows:[cleaned];
}

export function chatMarkdownBlocks(message){
  // Codex appends its memory citations as raw tags; they are bookkeeping, not part of the answer.
  const visible=String(message??'').replace(/\r\n?/g,'\n').replace(/\s*<oai-mem-citation>[\s\S]*?(?:<\/oai-mem-citation>|$)/g,'');
  const lines=visible.split('\n');
  const blocks=[];
  let text=[], fence=null;
  const flush=()=>{if(text.length){blocks.push({text:text.join('\n')});text=[];}};
  for(let i=0;i<lines.length;i++){
    const match=lines[i].match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if(fence||match){
      if(!fence)fence=match[1];
      else if(match&&match[1][0]===fence[0]&&match[1].length>=fence.length&&!match[2].trim())fence=null;
      text.push(lines[i]);
      continue;
    }
    const rows=flattenedTableRows(lines[i]);
    const header=tableCells(rows[0]);
    const rule=tableCells(rows[1]??lines[i+1]??'');
    if(header.length<2||rule.length!==header.length||!rule.every(cell=>tableDivider.test(cell))){
      text.push(lines[i]);
      continue;
    }
    flush();
    const table={header,rows:rows.slice(2).map(tableCells)};
    if(rows.length===1){
      i++;
      while(i+1<lines.length){
        const row=tableCells(lines[i+1]);
        if(row.length!==header.length)break;
        table.rows.push(row);
        i++;
      }
    }
    blocks.push(table);
  }
  flush();
  return blocks;
}
