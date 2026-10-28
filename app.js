/* Shaybani Offline-first starter. Financial mutations should be implemented through reviewed RPCs before production. */
(() => {
'use strict';
const DB_NAME='shaybani_accounting_local_v1', DB_VERSION=1;
let db, supabaseClient=null, editingId=null, toastTimer;
const $=id=>document.getElementById(id);
const now=()=>new Date().toISOString();
const uid=()=>crypto.randomUUID?crypto.randomUUID():('id-'+Date.now()+'-'+Math.random().toString(16).slice(2));
function openDB(){return new Promise((resolve,reject)=>{const req=indexedDB.open(DB_NAME,DB_VERSION);req.onupgradeneeded=()=>{const d=req.result;if(!d.objectStoreNames.contains('products'))d.createObjectStore('products',{keyPath:'id'});if(!d.objectStoreNames.contains('outbox')){const s=d.createObjectStore('outbox',{keyPath:'client_mutation_id'});s.createIndex('created_at','created_at')}};req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)})}
function store(name,mode='readonly'){return db.transaction(name,mode).objectStore(name)}
function reqP(r){return new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})}
const allProducts=()=>reqP(store('products').getAll());
const allQueue=()=>reqP(store('outbox').getAll());
function putLocal(p){return reqP(store('products','readwrite').put(p))}
function putQueue(q){return reqP(store('outbox','readwrite').put(q))}
function deleteQueue(id){return reqP(store('outbox','readwrite').delete(id))}
function toast(msg){$('toast').textContent=msg;$('toast').classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('show'),3000)}
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function money(v){return Number(v||0).toLocaleString('ar-YE',{maximumFractionDigits:3})}
async function render(){const products=await allProducts(),queue=await allQueue(),q=$('search').value.trim().toLowerCase();$('statProducts').textContent=products.length;$('statQueue').textContent=queue.length;$('statLastSync').textContent=localStorage.getItem('shaybani_last_sync')?new Date(localStorage.getItem('shaybani_last_sync')).toLocaleString('ar-YE'):'لم تتم بعد';$('statDb').textContent=supabaseClient?'مهيأة':'غير مهيأة';const rows=products.filter(p=>!p.deleted_at&&(!q||`${p.name} ${p.sku||''}`.toLowerCase().includes(q))).sort((a,b)=>a.name.localeCompare(b.name,'ar'));$('productsBody').innerHTML=rows.map(p=>`<tr><td><strong>${esc(p.name)}</strong><br><small>${esc(p.sku||'—')}</small></td><td>${esc(p.unit||'كيلو')}</td><td>${money(p.quantity)}</td><td>${money(p.purchase_price)}</td><td>${money(p.sale_price)}</td><td>${esc(p.currency||'YER')}</td><td><span class="pill ${p.sync_status==='pending'?'pending':''}">${p.sync_status==='pending'?'بانتظار المزامنة':'محفوظ محليًا'}</span></td><td><div class="row-actions"><button data-edit="${esc(p.id)}">تعديل</button><button data-delete="${esc(p.id)}">حذف</button></div></td></tr>`).join('');$('emptyState').hidden=rows.length!==0;$('productsBody').querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openForm(rows.find(p=>p.id===b.dataset.edit)));$('productsBody').querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>removeProduct(b.dataset.delete));if(!rows.length)$('productsBody').innerHTML=`<tr><td colspan="8" class="empty">لا توجد أصناف مطابقة.</td></tr>`;updateNetwork()}
function updateNetwork(){$('netDot').style.background=navigator.onLine?'#27955a':'#d79b32';$('netLabel').textContent=navigator.onLine?'متصل':'دون اتصال';}
function openForm(p){editingId=p?.id||null;$('productForm').reset();$('productId').value=p?.id||'';$('pName').value=p?.name||'';$('pSku').value=p?.sku||'';$('pCategory').value=p?.category||'';$('pUnit').value=p?.unit||'كيلو';$('pQty').value=p?.quantity??0;$('pBuy').value=p?.purchase_price??0;$('pSell').value=p?.sale_price??0;$('pCurrency').value=p?.currency||'YER';$('pMin').value=p?.minimum_stock??0;$('pNotes').value=p?.notes||'';$('modalTitle').textContent=p?'تعديل بيانات الصنف':'إضافة صنف جديد';$('formError').textContent='';$('productModal').hidden=false;$('pName').focus()}
function closeForm(){$('productModal').hidden=true;editingId=null}
async function saveProduct(e){e.preventDefault();$('formError').textContent='';const name=$('pName').value.trim();if(!name){$('formError').textContent='يرجى إدخال اسم الصنف.';return}const products=await allProducts(),sku=$('pSku').value.trim();if(sku&&products.some(p=>p.sku===sku&&p.id!==editingId&&!p.deleted_at)){ $('formError').textContent='رمز الصنف مستخدم مسبقًا.';return}
const existing=products.find(p=>p.id===editingId);const p={id:editingId||uid(),name,sku,category:$('pCategory').value.trim(),unit:$('pUnit').value,quantity:Number($('pQty').value||0),purchase_price:Number($('pBuy').value||0),sale_price:Number($('pSell').value||0),currency:$('pCurrency').value,minimum_stock:Number($('pMin').value||0),notes:$('pNotes').value.trim(),created_at:existing?.created_at||now(),updated_at:now(),deleted_at:null,sync_status:'pending',version:(existing?.version||0)+1,device_id:getDeviceId()};
try{await putLocal(p);await putQueue({client_mutation_id:uid(),entity:'products',entity_id:p.id,operation:existing?'upsert':'insert',base_version:existing?.version||0,payload:p,created_at:now(),status:'pending'});closeForm();await render();toast(navigator.onLine?'حُفظ محليًا؛ ستبدأ المزامنة عند توفر الإعدادات.':'حُفظ محليًا دون إنترنت.')}catch(err){$('formError').textContent='تعذر الحفظ المحلي: '+err.message}}
function getDeviceId(){let id=localStorage.getItem('shaybani_device_id');if(!id){id=uid();localStorage.setItem('shaybani_device_id',id)}return id}
async function removeProduct(id){if(!confirm('هل تريد إخفاء هذا الصنف؟ ستتم مزامنة التغيير عند توفر الاتصال.'))return;const p=(await allProducts()).find(x=>x.id===id);if(!p)return;p.deleted_at=now();p.updated_at=now();p.version=(p.version||0)+1;p.sync_status='pending';await putLocal(p);await putQueue({client_mutation_id:uid(),entity:'products',entity_id:p.id,operation:'delete',base_version:p.version-1,payload:p,created_at:now(),status:'pending'});await render();toast('تم الإخفاء محليًا، بانتظار المزامنة')}

// Bulk import: CSV/TSV works without a spreadsheet library; XLSX uses SheetJS when available.
let importRows=[];
const headerAliases={
 name:['اسم الصنف','اسم الصنف *','الصنف','اسم المنتج','الاسم','name','item name','product name','item','product'],
 sku:['رمز الصنف','الباركود','رمز الصنف / الباركود','sku','barcode','item code','code'],
 category:['التصنيف','الفئة','القسم','category'],
 unit:['الوحدة','وحدة التخزين','وحدة','unit','uom'],
 quantity:['الكمية','الكمية الحالية','الرصيد','quantity','qty','stock'],
 purchase_price:['سعر الشراء','سعر الشراء *','سعر التكلفة','التكلفة','purchase price','buy price','cost'],
 sale_price:['سعر البيع','سعر البيع *','سعر التجزئة','sale price','selling price','sell price','price'],
 currency:['العملة','عملة الأسعار','نوع العملة','currency'],
 minimum_stock:['حد التنبيه','حد التنبيه للمخزون','الحد الأدنى','minimum stock','min stock','reorder level'],
 notes:['ملاحظات','ملاحظة','notes','note','description']
};
function normHeader(v){return String(v??'').replace(/^\uFEFF/,'').trim().toLowerCase().replace(/[ًٌٍَُِّْـ]/g,'').replace(/[\s_\-\/]+/g,' ')}
function cellNumber(v, fallback=0){if(typeof v==='number')return Number.isFinite(v)?v:fallback;let s=String(v??'').trim().replace(/[٠-٩]/g,d=>'٠١٢٣٤٥٦٧٨٩'.indexOf(d)).replace(/[۰-۹]/g,d=>'۰۱۲۳۴۵۶۷۸۹'.indexOf(d)).replace(/٬/g,'').replace(/٫/g,'.').replace(/,/g,'');if(!s)return fallback;const n=Number(s);return Number.isFinite(n)&&n>=0?n:fallback}
function parseCSV(text){
 text=String(text).replace(/^\uFEFF/,'');
 const first=(text.split(/\r?\n/)[0]||'');
 const candidates=[',',';','\t'];let delimiter=',',max=-1;
 for(const d of candidates){const count=first.split(d).length;if(count>max){max=count;delimiter=d}}
 const rows=[];let row=[],cell='',quoted=false;
 for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++}else quoted=!quoted}
 else if(c===delimiter&&!quoted){row.push(cell);cell=''}
 else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);if(row.some(x=>String(x).trim()!==''))rows.push(row);row=[];cell=''}
 else cell+=c}
 if(cell.length||row.length){row.push(cell);if(row.some(x=>String(x).trim()!==''))rows.push(row)}
 return rows
}
function mapImportData(matrix){
 if(!matrix.length)return [];
 const headers=matrix[0].map(normHeader),indexes={};
 for(const [field,aliases] of Object.entries(headerAliases)){const normalized=aliases.map(normHeader);indexes[field]=headers.findIndex(h=>normalized.includes(h))}
 if(indexes.name<0)throw new Error('لم أجد عمود اسم الصنف. استخدم قالب CSV أو أضف عمود «اسم الصنف».');
 const out=[];
 for(let i=1;i<matrix.length;i++){
  const row=matrix[i];if(!row.some(v=>String(v??'').trim()))continue;
  const get=f=>indexes[f]>=0?row[indexes[f]]:'';
  const name=String(get('name')??'').trim();if(!name)continue;
  const currencyRaw=String(get('currency')||'YER').trim().toUpperCase();
  const currency= /SAR|سعود/.test(currencyRaw)?'SAR':(/USD|دولار|دولار أمريكي/.test(currencyRaw)?'USD':'YER');
  const unitRaw=String(get('unit')||'كيلو').trim();
  out.push({name,sku:String(get('sku')||'').trim(),category:String(get('category')||'').trim(),unit:unitRaw||'كيلو',
   quantity:cellNumber(get('quantity')),purchase_price:cellNumber(get('purchase_price')),sale_price:cellNumber(get('sale_price')),
   currency,minimum_stock:cellNumber(get('minimum_stock')),notes:String(get('notes')||'').trim()});
 }
 return out;
}
function closeImport(){ $('importModal').hidden=true; $('importFile').value=''; $('importFileInfo').textContent='لم يتم اختيار ملف بعد.'; $('importPreviewWrap').hidden=true;$('importSummary').hidden=true;$('importError').textContent='';$('confirmImportBtn').disabled=true;importRows=[]; }
function previewImport(rows){
 importRows=rows;
 $('importError').textContent='';
 $('importFileInfo').textContent=`تم العثور على ${rows.length} صنف في الملف.`;
 $('importPreviewBody').innerHTML=rows.slice(0,12).map(p=>`<tr><td>${esc(p.name)}</td><td>${esc(p.unit)}</td><td>${money(p.quantity)}</td><td>${money(p.purchase_price)}</td><td>${money(p.sale_price)}</td><td>${esc(p.currency)}</td></tr>`).join('');
 $('importPreviewWrap').hidden=!rows.length;
 $('importSummary').hidden=true;
 $('confirmImportBtn').disabled=!rows.length;
 if(rows.length>12)$('importFileInfo').textContent+=` تُعرض أول 12 صنفًا للمعاينة.`;
 if(!rows.length)$('importError').textContent='لم أجد أصنافًا صالحة في الملف.';
}
async function readImportFile(file){
 $('importError').textContent='';$('confirmImportBtn').disabled=true;
 if(!file)return;
 try{
  let matrix;
  const ext=file.name.split('.').pop().toLowerCase();
  if(['xlsx','xls'].includes(ext)){
   if(!window.XLSX)throw new Error('قارئ Excel غير متاح. اتصل بالإنترنت ثم أعد فتح الصفحة، أو احفظ الملف بصيغة CSV UTF-8.');
   const buffer=await file.arrayBuffer();const wb=XLSX.read(buffer,{type:'array'});const sheet=wb.Sheets[wb.SheetNames[0]];
   matrix=XLSX.utils.sheet_to_json(sheet,{header:1,defval:'',raw:true});
  }else{matrix=parseCSV(await file.text())}
  const rows=mapImportData(matrix);
  previewImport(rows);
 }catch(err){importRows=[];$('importFileInfo').textContent=file.name;$('importError').textContent=err.message||'تعذر قراءة الملف.'}
}
async function confirmImport(){
 if(!importRows.length)return;
 const btn=$('confirmImportBtn');btn.disabled=true;btn.textContent='جارٍ الاستيراد…';$('importError').textContent='';
 try{
  const current=await allProducts(),existingNames=new Set(current.filter(p=>!p.deleted_at).map(p=>normHeader(p.name))),existingSkus=new Set(current.filter(p=>!p.deleted_at&&p.sku).map(p=>String(p.sku).trim().toLowerCase()));
  const seenNames=new Set(),seenSkus=new Set();let imported=0,skipped=0;
  for(const row of importRows){
   const n=normHeader(row.name),s=row.sku.trim().toLowerCase();
   if(existingNames.has(n)||seenNames.has(n)||(s&&(existingSkus.has(s)||seenSkus.has(s)))){skipped++;continue}
   const p={...row,id:uid(),created_at:now(),updated_at:now(),deleted_at:null,sync_status:'pending',version:1,device_id:getDeviceId()};
   await putLocal(p);
   await putQueue({client_mutation_id:uid(),entity:'products',entity_id:p.id,operation:'insert',base_version:0,payload:p,created_at:now(),status:'pending'});
   existingNames.add(n);seenNames.add(n);if(s){existingSkus.add(s);seenSkus.add(s)}imported++;
  }
  closeImport();await render();
  toast(`تم استيراد ${imported} صنف${skipped?`، وتخطي ${skipped} مكررًا`:''}.`);
 }catch(err){$('importError').textContent='حدث خطأ أثناء الاستيراد: '+err.message}
 finally{btn.disabled=!importRows.length;btn.textContent='استيراد الأصناف'}
}
function downloadImportTemplate(){
 const rows=[['اسم الصنف','رمز الصنف','التصنيف','الوحدة','الكمية','سعر الشراء','سعر البيع','العملة','حد التنبيه','ملاحظات'],
 ['كمون حب','SP-001','بهارات','كيلو',10,1500,1800,'YER',2,'مثال فقط']];
 const csv='\uFEFF'+rows.map(r=>r.map(v=>{const s=String(v??'');return /[",\r\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s}).join(',')).join('\r\n');
 const blob=new Blob([csv],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='قالب_استيراد_أصناف_الشيباني.csv';document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(url);
}

async function initSupabase(){
 const c=window.SHAYBANI_CONFIG;
 if(!c?.SUPABASE_URL||!c?.SUPABASE_ANON_KEY||c.SUPABASE_URL.includes('YOUR_PROJECT')||!window.supabase){
  $('statDb').textContent='غير مهيأة';
  return false;
 }
 try{
  supabaseClient=window.supabase.createClient(c.SUPABASE_URL,c.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  $('statDb').textContent='اتصال مهيأ';
  return true;
 }catch(e){console.warn('Supabase init',e);$('statDb').textContent='خطأ بالإعداد';return false}
}
function showLogin(message=''){
 $('appShell').hidden=true;
 $('loginGate').hidden=false;
 $('loginError').textContent=message;
 $('loginPassword').value='';
}
function showApp(){
 $('loginGate').hidden=true;
 $('appShell').hidden=false;
 render().catch(e=>{console.error(e);toast('تعذر تحميل البيانات المحلية')});
}
async function verifyOwner(user){
 if(!supabaseClient||!user)return {ok:false,message:'تعذر التحقق من حساب المستخدم.'};
 if(!navigator.onLine)return {ok:true,offline:true};
 const {data,error}=await supabaseClient.from('app_profiles').select('role,display_name').eq('user_id',user.id).maybeSingle();
 if(error)return {ok:false,message:'تعذر التحقق من صلاحيات الحساب: '+error.message};
 if(!data)return {ok:false,message:'هذا الحساب غير مرتبط بملف صلاحيات في النظام. راجع مسؤول قاعدة البيانات.'};
 if(data.role!=='owner')return {ok:false,message:'هذا الحساب ليس مالك النظام، ولا يملك صلاحية الدخول إلى لوحة الإدارة.'};
 return {ok:true,profile:data};
}
async function handleLogin(e){
 e.preventDefault();
 const email=$('loginEmail').value.trim(),code=$('loginCode').value.trim(),password=$('loginPassword').value;
 $('loginError').textContent='';
 if(!supabaseClient){$('loginError').textContent='تعذر تحميل اتصال Supabase. تأكد من رفع config.js وفتح الموقع عبر HTTPS، ثم أعد تحميل الصفحة.';return}
 if(!navigator.onLine){$('loginError').textContent='يلزم الاتصال بالإنترنت لتسجيل الدخول. اتصل بالإنترنت ثم حاول مجددًا.';return}
 if(!email||!/^[0-9]{6}$/.test(code)||!password){$('loginError').textContent='أدخل رمز المستخدم المكوّن من 6 أرقام وكلمة المرور.';return}
 const btn=$('loginSubmit');btn.disabled=true;btn.textContent='جارٍ التحقق…';
 try{
  const pinResult=await supabaseClient.rpc('check_shaybani_login_code',{p_code:code});
  if(pinResult.error)throw new Error('تعذر التحقق من رمز المستخدم. نفّذ ملف supabase/login_code_settings.sql أولًا. '+pinResult.error.message);
  if(pinResult.data!==true)throw new Error('رمز المستخدم غير صحيح.');
  const {data,error}=await supabaseClient.auth.signInWithPassword({email,password});
  if(error)throw error;
  const check=await verifyOwner(data.user);
  if(!check.ok){await supabaseClient.auth.signOut();throw new Error(check.message)}
  $('loginCode').value='';$('loginPassword').value='';
  $('statDb').textContent='متصل بحساب المدير';showApp();
 }catch(err){$('loginError').textContent=err.message==='Invalid login credentials'?'كلمة المرور غير صحيحة. تحقق منها ثم حاول مجددًا.':(err.message||'تعذر تسجيل الدخول. حاول مرة أخرى.')}
 finally{btn.disabled=false;btn.textContent='دخول إلى النظام'}
}
async function saveLoginCode(e){
 e.preventDefault();$('settingsError').textContent='';
 const a=$('newLoginCode').value.trim(),b=$('confirmLoginCode').value.trim(),btn=$('saveLoginCode');
 if(!/^\d{6}$/.test(a)){$('settingsError').textContent='يجب أن يتكون الرمز من 6 أرقام.';return;}
 if(a!==b){$('settingsError').textContent='الرمزان غير متطابقين.';return;}
 btn.disabled=true;btn.textContent='جارٍ الحفظ…';
 try{
  const {data:{session}}=await supabaseClient.auth.getSession();if(!session)throw new Error('انتهت الجلسة. سجّل الدخول مجددًا.');
  const {error}=await supabaseClient.rpc('change_shaybani_login_code',{p_new_code:a});if(error)throw error;
  $('settingsModal').hidden=true;$('settingsForm').reset();toast('تم تغيير رمز المستخدم بنجاح. كلمة المرور لم تتغير.');
 }catch(err){$('settingsError').textContent=err.message||'تعذر حفظ الرمز.';}
 finally{btn.disabled=false;btn.textContent='حفظ الرمز';}
}
function closeSettings(){$('settingsModal').hidden=true;$('settingsForm').reset();$('settingsError').textContent='';}
async function logout(){
 if(supabaseClient){try{await supabaseClient.auth.signOut({scope:'local'})}catch(e){console.warn('Local sign out',e)}}
 showLogin(navigator.onLine?'تم تسجيل الخروج.':'تم تسجيل الخروج من هذا الجهاز. يلزم الاتصال بالإنترنت لتسجيل الدخول مجددًا.');
}
async function syncNow(){updateNetwork();if(!navigator.onLine){toast('لا يوجد اتصال؛ احتفظنا بالعمليات محليًا.');return}if(!supabaseClient){toast('تعذر الاتصال: راجع إعدادات config.js.');return}
const {data:{session}}=await supabaseClient.auth.getSession();if(!session){showLogin('سجّل الدخول أولًا.');return}
const queue=await allQueue();if(!queue.length){toast('لا توجد عمليات بانتظار المزامنة.');localStorage.setItem('shaybani_last_sync',now());await render();return}
toast('اتصال المدير قائم، لكن إرسال طابور العمليات إلى الخادم غير مكتمل في هذه النسخة؛ لم تُرسل تغييرات لتجنب فقد البيانات.');console.warn('Outbox preserved until conflict-safe RPC client integration is implemented.');
}
$('loginForm').addEventListener('submit',handleLogin);
 window.__shaybaniLoginReady=true;
$('logoutBtn').addEventListener('click',logout);
$('settingsBtn').addEventListener('click',()=>{$('settingsError').textContent='';$('settingsModal').hidden=false;});
$('closeSettingsModal').addEventListener('click',closeSettings);$('cancelSettings').addEventListener('click',closeSettings);$('settingsModal').addEventListener('click',e=>{if(e.target===$('settingsModal'))closeSettings()});$('settingsForm').addEventListener('submit',saveLoginCode);
$('importProductsBtn').onclick=()=>{$('importModal').hidden=false};
$('closeImportModal').onclick=closeImport;$('cancelImport').onclick=closeImport;
$('importModal').addEventListener('click',e=>{if(e.target===$('importModal'))closeImport()});
$('importFile').addEventListener('change',e=>readImportFile(e.target.files?.[0]));
$('confirmImportBtn').onclick=confirmImport;$('downloadTemplateBtn').onclick=downloadImportTemplate;
$('addProductBtn').onclick=()=>openForm();$('emptyAdd').onclick=()=>openForm();$('closeModal').onclick=closeForm;$('cancelModal').onclick=closeForm;$('productModal').addEventListener('click',e=>{if(e.target===$('productModal'))closeForm()});$('productForm').addEventListener('submit',saveProduct);$('search').addEventListener('input',render);$('syncBtn').onclick=syncNow;window.addEventListener('online',()=>{updateNetwork();toast('عاد الاتصال بالإنترنت. يمكنك بدء المزامنة.');});window.addEventListener('offline',updateNetwork);
(async()=>{
 try{
  db=await openDB();
  const ready=await initSupabase();
  if(ready){
   const {data:{session},error}=await supabaseClient.auth.getSession();
   if(error)console.warn('Session restore',error);
   if(session?.user){
    if(!navigator.onLine){showApp();}
    else{
     const check=await verifyOwner(session.user);
     if(check.ok)showApp();
     else{await supabaseClient.auth.signOut();showLogin(check.message)}
    }
   }else showLogin(ready?'أدخل بيانات حساب المدير للمتابعة.':'');
  }else showLogin('إعدادات الاتصال غير جاهزة. تأكد من وجود config.js ومكتبة Supabase، وافتح النظام عبر موقع HTTPS.');
  if('serviceWorker'in navigator && /^https?:$/.test(location.protocol))navigator.serviceWorker.register('./sw.js').catch(console.warn);
 }catch(e){console.error(e);showLogin('تعذر تهيئة النظام: '+(e.message||'خطأ غير معروف'))}
})();
})();