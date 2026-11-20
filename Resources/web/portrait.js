// Exact silhouettes from the provider artwork bundled with HerdrDesk.
export const claudeShape = "M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z";
export const codexShape = "M9.064 3.344a4.578 4.578 0 012.285-.312c1 .115 1.891.54 2.673 1.275.01.01.024.017.037.021a.09.09 0 00.043 0 4.55 4.55 0 013.046.275l.047.022.116.057a4.581 4.581 0 012.188 2.399c.209.51.313 1.041.315 1.595a4.24 4.24 0 01-.134 1.223.123.123 0 00.03.115c.594.607.988 1.33 1.183 2.17.289 1.425-.007 2.71-.887 3.854l-.136.166a4.548 4.548 0 01-2.201 1.388.123.123 0 00-.081.076c-.191.551-.383 1.023-.74 1.494-.9 1.187-2.222 1.846-3.711 1.838-1.187-.006-2.239-.44-3.157-1.302a.107.107 0 00-.105-.024c-.388.125-.78.143-1.204.138a4.441 4.441 0 01-1.945-.466 4.544 4.544 0 01-1.61-1.335c-.152-.202-.303-.392-.414-.617a5.81 5.81 0 01-.37-.961 4.582 4.582 0 01-.014-2.298.124.124 0 00.006-.056.085.085 0 00-.027-.048 4.467 4.467 0 01-1.034-1.651 3.896 3.896 0 01-.251-1.192 5.189 5.189 0 01.141-1.6c.337-1.112.982-1.985 1.933-2.618.212-.141.413-.251.601-.33.215-.089.43-.164.646-.227a.098.098 0 00.065-.066 4.51 4.51 0 01.829-1.615 4.535 4.535 0 011.837-1.388zm3.482 10.565a.637.637 0 000 1.272h3.636a.637.637 0 100-1.272h-3.636zM8.462 9.23a.637.637 0 00-1.106.631l1.272 2.224-1.266 2.136a.636.636 0 101.095.649l1.454-2.455a.636.636 0 00.005-.64L8.462 9.23z";


const classicWool='M51 113C35 104 34 85 45 71C53 61 64 58 77 60C84 51 95 47 105 49C115 32 134 27 153 29C171 31 187 42 194 57C217 60 232 78 232 98C244 111 240 129 230 139C234 157 221 174 204 178C200 195 185 206 166 206C153 219 129 222 110 212C89 220 64 207 57 189C44 181 42 164 46 153C33 141 36 123 51 113Z';
const outline=(d,fill,width=7.5)=>'<path d="'+d+'" fill="'+fill+'" stroke="#191a26" stroke-width="'+width+'" stroke-linejoin="round"/>';
const stitch=(d,color='#574558',width=4)=>'<path d="'+d+'" fill="none" stroke="'+color+'" stroke-width="'+width+'" stroke-linecap="round"/>';
const wash=(d,fill,opacity)=>'<path d="'+d+'" fill="'+fill+'" opacity="'+opacity+'"/>';
const ear=(shape,lining,wool)=>outline(shape,wool,7)+wash(lining,'#a34d70',.36);
const horn=(shape,highlight,ribs)=>outline(shape,'#d0a078',8)+wash(highlight,'#fff0cd',.69)+stitch(ribs,'#7e5343',3.8);

export const sheepStyles=['classic','marshmallow','lamb','clover','bighorn','twin'];
const oldSheep=new Map([
  ['cotton','marshmallow'],['popcorn','marshmallow'],['tuft','marshmallow'],['highland','marshmallow'],
  ['bell','lamb'],['harebell','lamb'],['meadow','lamb'],
  ['windswept','clover'],['soft-ear','clover'],
  ['spiral','bighorn'],['mountain','bighorn'],['button','bighorn'],['loop','bighorn'],
  ['crescent','twin'],['crown','twin'],['ridge','twin'],['twist','twin'],['jacob','twin'],
]);
export const resolveSheepStyle=id=>sheepStyles.includes(id)?id:oldSheep.get(id)||'classic';
export const sheepCoats=new Map([
  ['cream','#f9f3e8'],['oat','#e5c5a0'],['peach','#fac3a9'],['rose','#f5aece'],['berry','#ce9cdb'],
  ['iris','#b9b1f3'],['blue','#abcbf7'],['mint','#a8e0d1'],['moss','#c6d79d'],['ash','#bcc3ce'],
  ['cherry','#ff4967'],['tangerine','#ff872a'],['sun','#ffd144'],['lime','#9adc40'],
  ['emerald','#22ce8f'],['aqua','#2edbd9'],['royal','#5796ff'],['electric','#a473ff'],['magenta','#f95ccc'],
]);

const sheepArt={
  classic:{ silhouette:classicWool },
  marshmallow:{
    silhouette:'M50 113C30 109 29 88 40 77C35 60 50 46 69 48C68 31 89 22 102 34C111 14 141 12 154 29C171 17 196 24 200 44C218 40 234 54 232 72C247 80 252 105 239 119C251 138 241 159 225 164C229 183 209 197 190 194C184 215 157 226 138 213C125 223 103 223 89 211C70 216 55 204 54 189C38 184 33 164 44 150C32 140 36 120 50 113Z',
    shadow:'M135 209Q182 208 211 174Q231 152 224 121Q240 135 232 153Q228 161 222 162Q223 184 192 191Q184 214 138 212Z',
    light:'M53 66Q62 53 78 58Q76 43 92 39Q102 37 107 46Q118 26 143 30Q127 34 122 51Q113 58 101 50Q91 48 87 62Q74 70 53 66Z',
    line:'M113 61C113 45 133 41 140 52C144 61 134 66 129 61M181 51q15-1 20 9M199 108q17-5 22 9',
    eye:[89,82,8,8], blush:[112,103,10,5],
  },
  lamb:{
    silhouette:'M51 115C39 105 36 91 46 79C42 65 57 53 73 56C79 41 98 37 109 45C119 30 139 30 151 43C167 34 182 42 189 56C207 58 220 69 221 86C235 101 234 123 224 136C228 155 214 171 198 174C197 193 180 207 161 204C144 220 122 216 111 209C89 217 68 201 58 186C44 181 41 166 46 153C34 141 39 125 51 115Z',
    far:w=>ear('M53 81C39 67 17 72 16 91C16 110 26 121 48 111Z','M43 87C30 78 23 91 28 103Q36 106 45 99Z',w),
    near:w=>ear('M182 78C207 63 240 76 241 102C242 126 225 147 207 145C189 142 200 123 198 109Q191 91 182 78Z','M205 86C223 83 235 95 231 113C226 128 218 135 208 135Q218 110 205 86Z',w),
    shadow:'M193 163Q210 149 213 130Q225 150 199 173Q194 199 163 200L154 205Q178 185 193 163Z',
    light:'M52 75Q54 62 74 62Q86 46 104 51Q114 52 117 58Q100 54 95 64Q80 71 52 75Z',
    line:'M116 63c10-15 28-17 35-3 4 9-3 17-13 13-5-2-5-8 0-10',
    eye:[89,86,8.5,10], blush:[113,106,11,5.8], gesture:'hop',
  },
  clover:{
    silhouette:'M50 113C27 103 31 77 49 69C46 52 67 40 86 48C91 29 119 22 132 39C146 19 174 25 182 46C204 35 220 51 221 69C239 75 249 97 237 113C251 130 242 151 224 156C223 179 206 189 188 187C186 211 161 221 143 209C126 224 106 219 91 208C73 219 55 202 54 186C38 177 35 159 43 150C28 141 34 122 50 113Z',
    far:w=>ear('M164 57C169 32 192 14 217 19C214 44 196 65 180 67Z','M181 54Q191 31 207 26Q201 45 181 54Z',w),
    near:w=>ear('M192 85C207 66 232 64 248 72C241 95 222 111 203 106Z','M209 96Q221 79 239 77Q229 96 209 96Z',w),
    shadow:'M149 208Q187 203 199 170Q226 155 228 124Q236 135 224 154Q222 177 187 184Q184 208 149 208Z',
    light:'M49 75Q60 51 88 56Q100 37 124 44Q110 46 102 58Q90 71 49 75Z',
    line:'M119 64c3-9 17-13 22-5 4 7-2 14-10 12',
    eye:[90,83,7,9], blush:[115,101,10,5.5], gesture:'hop',
  },
  bighorn:{
    silhouette:'M51 113C29 102 36 78 54 69C57 53 75 47 91 54C101 37 124 31 145 39C168 33 194 46 200 63C225 64 240 83 237 104C250 119 245 141 229 149C233 169 212 186 194 185C187 207 159 220 138 211C116 225 91 215 80 204C63 206 54 192 52 180C39 169 40 157 46 149C31 139 34 119 51 113Z',
    far:()=>horn('M103 66C83 59 79 43 85 27C97 36 112 31 121 45L124 60Z','M91 33Q104 43 111 41Q103 49 95 45Z','M90 43q11 3 15 11'),
    near:()=>horn('M181 71C163 55 165 29 184 17C205 2 234 10 246 30C262 56 248 84 227 92C208 99 191 88 192 76C193 67 200 63 208 68C212 71 212 77 216 77C231 77 237 59 230 47C225 35 212 33 204 38C197 43 195 54 201 62Q194 73 181 71Z','M178 54C172 28 200 13 217 20Q233 24 239 40Q228 27 212 29Q189 33 189 58Z','M177 45q7 1 14 8m-8-21q7 2 12 8m1-17q5 3 8 10m11-9q4 4 4 10m19 2-7 7m13 7-9 4m8 13-10-2m2 17-9-6'),
    shadow:'M145 210Q188 201 203 177Q230 168 225 142Q238 150 223 168Q217 180 193 181Q184 203 145 210Z',
    light:'M51 76Q62 57 89 60Q107 44 132 46Q111 52 107 62Q87 66 51 76Z',
    line:'M116 69q14-13 25-4M120 89l5 2m4-7 5 2', 
    eye:[90,83,8,8], blush:[111,102,10,5], gesture:'nod',
  },
  twin:{
    silhouette:'M50 113C32 104 35 86 47 76C49 62 64 53 81 57C91 42 111 43 123 47C134 30 155 34 168 47C185 39 204 50 211 64C231 68 243 87 236 105C253 117 245 142 229 148C231 167 214 184 197 183C188 207 163 212 144 208C124 223 107 217 95 211C74 218 57 202 53 188C39 179 36 164 43 151C31 141 36 121 50 113Z',
    far:()=>horn('M82 67C64 66 51 55 54 36C55 27 60 19 68 15C65 27 72 34 82 38C94 42 101 49 98 56Z','M62 24Q62 45 81 47L80 53Q64 52 61 43Z','M59 44l11 4m-6 7 13-4'),
    near:()=>horn('M171 64C173 46 185 41 198 34C209 28 213 17 210 6C230 13 235 32 225 47C216 58 204 56 201 65C198 75 207 81 216 77C211 92 190 94 180 81Q172 74 171 64Z','M178 61Q185 47 201 40Q217 33 219 19Q225 39 206 47Q193 54 192 65Z','M182 55l10 7m1-15 8 8m3-14 7 8m4-15 9 3m-34 41 11-2'),
    shadow:'M144 208Q183 201 198 174Q224 167 227 144Q233 158 214 172Q206 180 193 181Q182 202 144 208Z',
    light:'M49 79Q63 61 86 62Q99 50 119 54Q135 43 153 48Q139 53 132 65Q115 73 97 64Q74 70 49 79Z',
    line:'M123 70C131 58 142 59 147 67Q152 76 143 80Q135 82 134 75M190 112q12-9 21 0',
    eye:[91,83,7.2,9.5], blush:[115,103,8.5,5], gesture:'nod',
  },
};

const accessoryArt={
  glasses:{
    front:(x,y)=>'<g transform="translate('+x+' '+y+')">'
      +'<path d="M-29 -7h8m36 3 33-8" stroke="#17171d" stroke-width="7" fill="none" stroke-linecap="round"/>'
      +'<rect x="-21" y="-15" width="38" height="30" rx="7" fill="none" stroke="#17171d" stroke-width="8"/></g>',
  },
  beard:{
    chin:()=>outline('M67 179Q110 187 154 178C160 193 148 206 135 208C127 223 106 222 97 214C78 213 66 198 67 179Z','#212126',5)
      +stitch('M83 190q26 14 55 1','#5a5a63',3.5),
  },
  hair:{
    back:()=>outline('M125 48C133 20 159 15 186 22C223 31 234 61 232 91Q233 116 245 144Q250 188 222 205Q196 225 158 209Q178 173 165 138Z','#1e1e24',5),
    front:()=>outline('M127 54Q140 26 173 31Q161 40 157 55Q147 69 132 70Z','#25252c',4)
      +outline('M202 108C226 105 236 142 229 162Q227 192 193 207Q209 184 201 169Q202 145 202 108Z','#25252c',4)
      +stitch('M214 123q13 39-3 61','#61616c',3.8),
  },
  headset:{
    front:()=>stitch('M59 94Q54 47 108 38Q125 35 139 44','#202027',9)
      +outline('M53 96Q63 87 73 95L77 113Q70 124 58 118Z','#25252c',5)
      +stitch('M64 116q1 10 19 12','#202027',5)+'<circle cx="84" cy="128" r="4" fill="#565661"/>',
  },
  bow:{
    front:()=>outline('M111 52Q101 29 110 30Q127 33 138 43Q161 23 170 29Q175 45 161 54Q172 63 166 72Q149 72 138 57Q122 76 109 71Q104 62 111 52Z','#25252c',6)
      +'<rect x="132" y="42" width="12" height="13" rx="4" fill="#73737d"/>',
  },
};
export const sheepAccessories=['none', ...Object.keys(accessoryArt)];
export const resolveSheepAccessory=id=>sheepAccessories.includes(id)?id:'none';

const orbitPath='M242 151A112 48 0 0 1 18 151A112 48 0 0 1 242 151';
function portraitOrbit(front,moving,preview=false) {
  const arc=front?'M242 151A112 48 0 0 1 18 151':'M18 151A112 48 0 0 1 242 151';
  const rider=(attrs,delay)=>'<circle '+attrs+'>'
    +'<animateMotion path="'+orbitPath+'" dur="1.4s" begin="'+delay+'" repeatCount="indefinite"/>'
    +'<animate attributeName="opacity" values="'+(front?'1;0;0':'0;1;1')
    +'" keyTimes="0;.5;1" calcMode="discrete" dur="1.4s" begin="'+delay+'" repeatCount="indefinite"/></circle>';
  // Working: the marker runs fast with two fading sparks behind it.
  const marker=moving?rider('class="portrait-trail" r="5" fill="#ffd3a0" fill-opacity=".45"','-0.14s')
    +rider('class="portrait-trail" r="7.5" fill="#ffc07a" fill-opacity=".7"','-0.07s')
    +rider('r="10.4" fill="#f9f3e8" stroke="#ffad53" stroke-width="4.8"','0s')
    :front?'<circle class="'+(preview?'portrait-preview-orbit':'')+'" cx="165" cy="196" r="10.4" fill="#f9f3e8" stroke="#ffad53" stroke-width="4.8"/>':'';
  return '<g transform="rotate(-17 130 151)">'
    +(front?'<path d="'+arc+'" stroke="#f9f3e8" stroke-width="13" fill="none"/>':'')
    +'<path d="'+arc+'" stroke="#fb8a22" stroke-width="7.5" fill="none"/>'+marker+'</g>';
}

// Three square viewports per row share the approved generated raster artwork.
// Saved customizations decorate the approved artwork; no choice is reset.
function minimalPortrait(provider,moving,preview,sleeping,name,coat,extra) {
  const row=provider==='claude'?1:0;
  const wool=sheepCoats.get(coat);
  // All portraits share the approved face. Existing choices decorate that face,
  // rather than routing a customized character back to the retired mouth artwork.
  const style=name==='lamb'?ear('M65 92C32 66 13 89 27 116Q40 133 64 113Z','M43 93Q27 93 35 109L53 106Z',wool)
    +ear('M190 92C223 66 242 89 228 116Q215 133 191 113Z','M212 93Q228 93 220 109L202 106Z',wool)
    :name==='clover'?ear('M61 82Q16 72 29 43Q57 43 72 74Z','M38 54L58 74L34 66Z',wool)
    +ear('M193 82Q238 72 225 43Q197 43 182 74Z','M216 54L196 74L220 66Z',wool)
    :name==='marshmallow'?outline('M68 65Q51 47 66 35Q78 26 91 37Q91 15 110 18Q126 20 125 40L114 64Z',wool,6):'';
  const horns=name==='bighorn'?sheepArt.bighorn.near():name==='twin'?sheepArt.twin.far()+sheepArt.twin.near():'';
  const accessories={
    glasses:'<g fill="none" stroke="#191a26" stroke-width="5"><rect x="77" y="99" width="43" height="33" rx="9"/><rect x="146" y="99" width="43" height="33" rx="9"/><path d="M120 112h26M67 108h10m112 0h10"/></g>',
    beard:outline('M105 207Q127 216 151 207Q155 230 130 238Q107 233 105 207Z','#25252c',4),
    hair:outline('M65 96Q41 57 71 49Q84 41 105 51Q84 62 82 89L72 106Q65 152 48 164Q52 123 65 96Z','#25252c',4)
      +outline('M204 111Q220 146 206 183L191 197Q199 158 191 126Z','#25252c',4),
    headset:stitch('M64 111Q52 51 128 48Q205 50 197 112','#25252c',7)
      +'<rect x="55" y="102" width="17" height="32" rx="7" fill="#25252c"/><rect x="188" y="102" width="17" height="32" rx="7" fill="#25252c"/>'+stitch('M196 133q-2 15-24 16','#25252c',5),
    bow:'<g transform="translate(-18 24) scale(.8)">'+accessoryArt.bow.front()+'</g>',
  };
  const frame=(state,column)=>{
    const id='sheep-v5-'+provider+'-'+coat+'-'+column;
    const image='<svg x="0" y="0" width="256" height="256" viewBox="'+(column*512)+' '+(row*512)+' 512 512" overflow="hidden" focusable="false"><image href="icons/sheep-minimal-v5.png" x="0" y="0" width="1536" height="1024"/></svg>';
    // A luminance-derived wool mask colors only pale wool. Protect the white
    // terminal glyph; dark outlines and provider colors stay intact.
    const tint=coat==='cream'?'':'<defs><filter id="'+id+'-light" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 5 5 5 0 -12"/><feComposite in2="SourceAlpha" operator="in"/></filter><mask id="'+id+'-mask" maskUnits="userSpaceOnUse" x="0" y="0" width="256" height="256">'
      +'<g filter="url(#'+id+'-light)">'+image+'</g>'
      +(provider==='codex'&&column!==1?'<ellipse cx="132" cy="166" rx="48" ry="37" fill="black"/>':'')
      +'</mask></defs><rect class="portrait-coat-layer" width="256" height="256" fill="'+wool+'" mask="url(#'+id+'-mask)"/>';
    return '<g class="portrait-frame portrait-frame-'+state+'">'+image+tint+'</g>';
  };
  return '<span class="agent-portrait" data-artwork="minimal-v5" data-atlas-row="'+row+'" data-provider="'+provider+'" data-sheep="'+name+'" data-coat="'+coat+'" data-accessory="'+extra+'" data-gesture="peek" data-preview="'+preview+'" data-chewing="'+moving+'" data-sleep="'+Boolean(sleeping)+'" aria-hidden="true">'
    +'<svg viewBox="0 0 256 256" focusable="false"><g class="portrait-body">'
    +'<g class="portrait-style-layer">'+style+'</g>'+frame('open',0)+frame('sleep',1)+frame('wake',2)
    +'<g class="portrait-style-layer">'+horns+'</g><g class="portrait-custom-accessory">'+(accessories[extra]||'')+'</g></g></svg></span>';
}

export function portraitArtwork(provider,moving,variant='classic',coat='cream',preview=false,accessory='none',sleeping=false) {
  const name=resolveSheepStyle(variant);
  const art=sheepArt[name];
  const extra=resolveSheepAccessory(accessory);
  const costume=accessoryArt[extra];
  const wool=sheepCoats.get(coat)||sheepCoats.get('cream');
  if (provider==='codex'||provider==='claude') {
    return minimalPortrait(provider,moving,preview,sleeping,name,sheepCoats.has(coat)?coat:'cream',extra);
  }
  const isClaude=provider==='claude';
  const isCodex=provider==='codex';
  const mark=isClaude?'<path d="'+claudeShape+'" fill="#ff8937" fill-rule="evenodd"/>'
    :isCodex?'<rect x="6.7" y="8.1" width="10.4" height="8" rx="2" fill="#fff9f4"/><path d="'+codexShape+'" fill="#5845bf" fill-rule="evenodd"/>':'';
  const lip='M50 177Q83 165 121 173Q153 177 178 169';
  const spark=name==='classic'?'<path d="M216 37c2 11 6 15 17 17-11 2-15 6-17 17-2-11-6-15-17-17 11-2 15-6 17-17Z" fill="#fb8a22"/>':'';
  const [eyeX,eyeY,eyeW,eyeH]=art.eye||[89,83,7,9];
  const blush=art.blush?'<ellipse cx="'+art.blush[0]+'" cy="'+art.blush[1]+'" rx="'+art.blush[2]+'" ry="'+art.blush[3]+'" fill="#9f3e67" opacity=".27"/>':'';
  const eye='<g class="portrait-eye-open"><ellipse cx="'+eyeX+'" cy="'+eyeY+'" rx="'+eyeW+'" ry="'+eyeH+'" fill="#191a26"/>'
    +'<circle cx="'+(eyeX+2.3)+'" cy="'+(eyeY-3.1)+'" r="'+(art.eye?2.4:1.9)+'" fill="#f9f3e8"/></g>'
    +'<path class="portrait-eye-closed" d="M'+(eyeX-11)+' '+eyeY+'q11 15 24 4" fill="none" stroke="#191a26" stroke-width="5.7" stroke-linecap="round"/>';
  return '<span class="agent-portrait" data-provider="'+provider+'" data-sheep="'+name+'" data-coat="'+(sheepCoats.has(coat)?coat:'cream')
    +'" data-accessory="'+extra+'" data-gesture="'+(art.gesture||'peek')+'" data-preview="'+preview+'" data-chewing="'+moving+'" data-sleep="'+Boolean(sleeping)+'" aria-hidden="true">'
    +'<svg viewBox="0 0 256 256" focusable="false">'
    +portraitOrbit(false,moving)
    +'<g class="portrait-body">'
    +(costume?.back?.()||'')+(art.far?.(wool)||'')+outline(art.silhouette,wool,9)
    +(art.shadow?wash(art.shadow,'#664153',.16)+wash(art.light,'#fff9ee',.33)+stitch(art.line,'#3b2b3f',4):'')
    +(name==='classic'?'<path d="M194 57c5 16-2 29-16 33-15 5-29-2-30-14-1-6 2-11 7-14" fill="none" stroke="#191a26" stroke-width="9" stroke-linecap="round"/>':'')
    +(art.near?.(wool)||'')+blush+eye+(costume?.front?.(eyeX,eyeY)||'')
    +'<g class="portrait-mouth-open"><path d="M55 114C73 101 103 104 126 117C151 130 172 151 180 177C170 191 146 204 118 204C91 204 67 193 55 174C46 158 45 130 55 114Z" fill="#191a26"/>'
    +(!mark?'<path d="M72 155Q98 138 120 159Q113 174 89 179Z" fill="#a55570"/>':'')
    +(isClaude?'<path d="M26 142l-10-4m17-6-8-8m19 2-4-12" fill="none" stroke="#fb8a22" stroke-width="5" stroke-linecap="round"/>':'')
    +(mark?'<g transform="'+(isClaude?'translate(86 165) rotate(-14)':'translate(110 152) rotate(-9) scale(1.13)')
    +'"><g class="portrait-character"><g transform="translate(-48 -48) scale(4)">'+mark+'</g></g></g>':'')
    +'<path d="M78 108q9 0 15 4c-2 7-6 11-11 9-3-1-5-6-4-13Z" fill="#f9f3e8"/></g>'
    +'<path d="'+lip+' C185 192 160 211 122 212C84 215 56 202 50 177Z" fill="'+wool+'"/>'
    +'<path d="'+lip+'" fill="none" stroke="#191a26" stroke-width="6" stroke-linecap="round"/>'
    +(costume?.chin?.()||'')+'</g>'
    +portraitOrbit(true,moving,preview)
    +spark+'<g class="portrait-zz" fill="none" stroke="#c7cbe0" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">'
    +'<path d="M196 92h20l-20 22h20"/><path d="M226 58h14l-14 15h14"/></g></svg></span>';
}

export const workHammer='<svg class="hr-tool" viewBox="0 0 14 14" aria-hidden="true"><rect x="6" y="5" width="2" height="9" rx="1"/><rect class="hr-tool-head" x="2" y="1.5" width="10" height="4.5" rx="1.2"/></svg>';
/** Marks a portrait as working and puts the hammer inside it, so it moves with the face wherever the portrait is shown. */
export function withWorkTool(html){
  if(!html||!html.startsWith('<span class="agent-portrait" ')||!html.endsWith('</svg></span>'))return html;
  return '<span class="agent-portrait" data-working '+html.slice('<span class="agent-portrait" '.length,-'</span>'.length)+workHammer+'</span>';
}
