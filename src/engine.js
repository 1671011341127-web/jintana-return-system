export const REQUIRED_COLUMNS = ['DOC_CODE','SHIPTO_CODE','SHIPTO_NAME','ITEM_CODE','ITEM_NAME','RETRUN_QTY'];
export const CATEGORY_RULES = [
  {name:'เสื้อใน', words:['เสื้อใน','BRA','BRASSIERE']},
  {name:'กางเกงใน', words:['กางเกงใน','PANTY','BRIEF','UNDERWEAR']},
  {name:'เสื้อกล้ามเด็ก', words:['เสื้อกล้ามเด็ก','KIDS TANK']},
  {name:'เสื้อกล้าม', words:['เสื้อกล้าม','TANK TOP']},
];
export function categoryOf(name='') {
  const s = String(name).toUpperCase();
  return CATEGORY_RULES.find(c => c.words.some(w => s.includes(w.toUpperCase())))?.name || 'รอตรวจสอบประเภท';
}
export function parseRows(rows, fileName, batchId) {
  const missing = REQUIRED_COLUMNS.filter(c => !(c in (rows[0] || {})));
  if (missing.length) throw new Error(`ไม่พบคอลัมน์ที่จำเป็น: ${missing.join(', ')}`);
  return rows.map((r,i) => ({
    id: `${batchId}-${i}-${String(r.LINE_NO ?? i)}`,
    batchId, fileName, docCode:String(r.DOC_CODE ?? ''),
    storeCode:String(r.SHIPTO_CODE ?? '').trim(), storeName:String(r.SHIPTO_NAME ?? '').trim(),
    sku:String(r.ITEM_CODE ?? '').trim(), itemName:String(r.ITEM_NAME ?? '').trim(),
    category:categoryOf(r.ITEM_NAME), qty:Number(r.RETRUN_QTY) || 0,
    employeeName:String(r.EMPLOYEE_NAME ?? ''), raw:r
  })).filter(r => r.storeCode && r.sku && r.qty > 0);
}
export function buildSuggestions(rows, capacities, mode='ranked') {
  const bySku = new Map();
  rows.forEach(r => {
    if (!bySku.has(r.sku)) bySku.set(r.sku, []);
    const arr=bySku.get(r.sku);
    let store=arr.find(x=>x.storeCode===r.storeCode);
    if(!store){store={storeCode:r.storeCode,storeName:r.storeName,sku:r.sku,itemName:r.itemName,category:r.category,qty:0,sourceRows:[]};arr.push(store);}
    store.qty+=r.qty; store.sourceRows.push(r.id);
  });
  const result=[];
  for(const [sku,stores] of bySku){
    const cap=Number(capacities[sku] ?? capacities[stores[0]?.category] ?? 0);
    const sorted=[...stores].sort((a,b)=>b.qty-a.qty);
    if(mode==='manual'){
      result.push({sku,category:stores[0]?.category,capacity:cap,stores:sorted,total:sorted.reduce((n,x)=>n+x.qty,0),reason:'เลือกร้านที่ต้องการรวมในกลุ่มนี้'});
      continue;
    }
    // First-fit decreasing: each store appears once and a box never mixes SKUs.
    const bins=[];
    for(const store of sorted){
      let bin = cap>0 && store.qty<=cap ? bins.find(b=>b.total+store.qty<=cap) : null;
      if(!bin){bin={stores:[],total:0,overCapacity:cap>0&&store.qty>cap};bins.push(bin);}
      bin.stores.push(store); bin.total+=store.qty;
    }
    bins.forEach((bin,index)=>result.push({
      sku,category:stores[0]?.category,capacity:cap,stores:bin.stores,total:bin.total,
      fill:cap?Math.min(100,Math.round(bin.total/cap*100)):0,
      overCapacity:bin.overCapacity,
      reason:bin.overCapacity?'ร้านนี้มีจำนวนเกินความจุกล่อง ต้องตรวจสอบ/แบ่งกล่องเพิ่ม':mode==='auto'?'จัดกลุ่มอัตโนมัติตาม SKU':'แนะนำกลุ่มที่ใช้ความจุกล่องได้เหมาะสม'
    }));
  }
  return result;
}
