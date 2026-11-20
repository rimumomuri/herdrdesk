// Recognize chat shortcuts without interpreting the rest of the message as HTML.
const shortcutPattern=/~~~[\s\S]*?(?:~~~|$)|```[\s\S]*?(?:```|$)|``[\s\S]*?``|`(?<code>[^\n`]+)`|\[(?<label>[^\n\[\]]+)\]\((?:<(?<wrapped>[^\n>]+)>(?:[ \t]+(?:"[^"\n]*"|'[^'\n]*'))?|(?<destination>(?:[^\n()]|\([^\n()]*\))+))\)|<(?<angled>(?:https?:\/\/|file:\/\/|~?\/)[^\n>]+)>|["“](?<quoted>(?:file:\/\/|~?\/)[^\n"”]+)["”]|(?<![\w@/.-])(?<plain>(?:https?:\/\/|file:\/\/|(?:[a-z\d-]+\.)?(?:notion\.so|notion\.site|notion\.com|youtube\.com|youtu\.be|github\.com)\/|~\/|\/(?:Users|Volumes|tmp|private|var|opt|etc|Applications|System|Library)\/)[^\s<>"`“”]+)/giu;

const shortcutHost=(host,domain)=>host===domain||host.endsWith('.'+domain);
function chatShortcut(target,label) {
  const value=target.trim();
  if(!value||value.length>4096||/[\u0000-\u001f\u007f]/u.test(value))return null;
  let path=value;
  if(/^file:\/\//i.test(value)){
    try {
      const file=new URL(value);
      if(file.host && file.host!=='localhost'||file.search||file.hash)return null;
      path=decodeURIComponent(file.pathname);
    } catch { return null; }
  }
  if((path.startsWith('/')&&!path.startsWith('//'))||path.startsWith('~/')){
    if(/[\u0000-\u001f\u007f]/u.test(path))return null;
    const basename=path.replace(/\/+$/,'').split('/').at(-1)||path;
    return {label:label||basename, kind:'file', href:'herdrdesk-path:'+encodeURIComponent(path), title:path};
  }
  const address=/^https?:\/\//i.test(value)?value
    :/^(?:[a-z\d-]+\.)?(?:notion\.so|notion\.site|notion\.com|youtube\.com|youtu\.be|github\.com)\//i.test(value)?'https://'+value:'';
  if(!address)return null;
  try {
    const url=new URL(address);
    if(!url.hostname||url.username||url.password)return null;
    const host=url.hostname.toLowerCase(), is=domain=>shortcutHost(host,domain);
    const kind=is('notion.so')||is('notion.site')||is('notion.com')?'notion'
      :is('youtube.com')||host==='youtu.be'?'youtube':is('github.com')?'github':'web';
    const name={notion:'Notion',youtube:'YouTube',github:'GitHub'}[kind]||host;
    return {label:label||name,kind,href:url.href,title:address};
  }catch{return null;}
}

function trimRawShortcut(value){
  let trimmed=value.replace(/[.,!?;:。、，！？；…」』】]+$/u,'');
  for(const [open,close] of [['(',')'],['[',']'],['{','}']]){
    const count=char=>Array.from(trimmed).filter(value=>value===char).length;
    let extra=count(close)-count(open);
    while(extra>0&&trimmed.endsWith(close)){
      trimmed=trimmed.slice(0,-1);
      extra--;
    }
  }
  return trimmed;
}

export function chatShortcutSegments(message){
  const text=String(message??'');
  const segments=[];
  let start=0;
  for(const match of text.matchAll(shortcutPattern)){
    const {label,wrapped,destination,code,angled,quoted,plain}=match.groups;
    const markdownDestination=destination?.replace(/^((?:https?:\/\/|file:\/\/)\S+)[ \t]+(?:"[^"\n]*"|'[^'\n]*')$/i,'$1');
    const target=plain?trimRawShortcut(plain):wrapped||markdownDestination||code||angled||quoted;
    const link=target&&chatShortcut(target,label);
    if(!link&&!code)continue;
    if(match.index>start)segments.push(text.slice(start,match.index));
    segments.push(link||{kind:'code',label:code});
    if(plain&&target.length<plain.length)segments.push(plain.slice(target.length));
    start=match.index+match[0].length;
  }
  if(start<text.length)segments.push(text.slice(start));
  return segments;
}
