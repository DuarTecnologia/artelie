import {getSupabase} from '../lib/supabase';
export type Product={id:string;name:string;category:string;type:string;price:number;stock:number;description:string;image:string;exhibitor:string};
export const money=(n:number)=>n.toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export async function loadProducts():Promise<Product[]>{
 const db=getSupabase();
 const {data,error}=await db.from('produtos').select('id,nome,descricao,foto_url,preco,estoque,classificacoes(nome),tipos_produto(nome),expositores(nome)').eq('ativo',true).eq('aprovado',true).order('nome');
 if(error)throw error;
 const name=(v:unknown)=>{const a=Array.isArray(v)?v[0]:v;return (a as {nome?:string}|null)?.nome||''};
 return (data||[]).map(p=>({id:p.id,name:p.nome,description:p.descricao||'',image:p.foto_url||'/arte/bolsa.svg',price:Number(p.preco),stock:Math.max(0,Number(p.estoque)),category:name(p.classificacoes),type:name(p.tipos_produto),exhibitor:name(p.expositores)}));
}
