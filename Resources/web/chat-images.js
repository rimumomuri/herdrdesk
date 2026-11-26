// Only native-produced PNG bytes become image sources. File paths never become URLs in WebKit.
/** `token` (optional) ties the shown images to their message so the image viewer can page through them. */
export function chatImageMarkup(previews, token = '') {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const safeToken=/^image\d{1,9}$/.test(token)?token:'';
  return Array.isArray(previews)&&previews.length ? '<div class="chat-images"'+(safeToken?' data-chat-images="'+safeToken+'"':'')+'>'+previews.slice(0,4).map((item,index)=>{
    const png=typeof item?.thumbnail==='string'&&item.thumbnail.length<=174764&&/^iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$/.test(item.thumbnail);
    return '<figure class="chat-image"'+(safeToken?' data-index="'+index+'"'+(png?' tabindex="0" role="button"':''):'')+'>'+(png?'<img src="data:image/png;base64,'+item.thumbnail+'" alt="'+esc(item.name)+'" loading="lazy" decoding="async">':'<span class="chat-image-fallback">이미지 미리보기를 표시할 수 없어요</span>')+'<figcaption>'+esc(item?.name)+'</figcaption></figure>';
  }).join('')+'</div>' : '';
}

// The full record binding is the cache key, so reused IDs or changed bodies cannot inherit a preview.
export class ChatImagePreviews {
  constructor(post,changed){this.post=post;this.changed=changed;this.cache=new Map();this.tokens=new Map();this.next=0;}
  markup(record){
    if(!record||!record.id||!record.role||!record.session||typeof record.body!=='string'||record.body.length>8192||(!record.sentImages&&!record.body.includes('![')&&!/(?:png|jpe?g|gif|webp|heic|tiff?)(?:[)>\s]|$)/i.test(record.body)))return '';
    const key=JSON.stringify([record.id,record.role,record.session,record.body]);
    let entry=this.cache.get(key);
    if(!entry){
      entry={token:'image'+(++this.next),record,requested:false,previews:null};this.cache.set(key,entry);this.tokens.set(entry.token,entry);
      if(this.cache.size>300){const first=this.cache.keys().next().value;this.tokens.delete(this.cache.get(first).token);this.cache.delete(first);}
    }
    return entry.previews===null?'<span class="chat-image-pending" data-chat-preview="'+entry.token+'"></span>':chatImageMarkup(entry.previews,entry.token);
  }
  request(token){
    const entry=this.tokens.get(token);if(!entry||entry.requested)return;
    entry.requested=true;const {id,role,session,body}=entry.record;
    this.post({type:'chatImages',token,id,role,session,body});
  }
  /** Ask native for one shown image at viewer size. Only the record is named; native resolves and checks the file. */
  large(token,index){
    const entry=this.tokens.get(token);
    if(!entry||!Number.isInteger(index)||index<0||index>3)return;
    const {id,role,session,body}=entry.record;
    this.post({type:'chatImageLarge',token,index,id,role,session,body});
  }
  receive(payload){
    const entry=this.tokens.get(payload?.token);
    if(!entry||!entry.requested||entry.previews!==null)return;
    entry.previews=Array.isArray(payload.previews)?payload.previews.slice(0,4):[];this.changed();
  }
}

// Disk history retains binding metadata, while the native store owns the image bytes.
export function chatImageHistory(records){
  return records.map(({previews,...record})=>record);
}
