'use client';
import Link from 'next/link';
import {createContext,useContext,useState,useEffect} from 'react';
import {products} from './data';
type Cart=Record<string,number>;
const Context=createContext<{cart:Cart;change:(id:string,n:number)=>void}>({cart:{},change:()=>{}});
export const useCart=()=>useContext(Context);
export function Shell({children}:{children:React.ReactNode}){const [cart,setCart]=useState<Cart>({});const [ready,setReady]=useState(false);
useEffect(()=>{try{const raw=JSON.parse(localStorage.getItem('artelie-cart')||'{}');const clean:Cart={};for(const p of products){const n=raw?.[p.id];if(Number.isInteger(n)&&n>0)clean[p.id]=Math.min(n,p.stock)}setCart(clean)}catch{}setReady(true)},[]);
useEffect(()=>{if(ready)localStorage.setItem('artelie-cart',JSON.stringify(cart))},[cart,ready]);
function change(id:string,n:number){const p=products.find(x=>x.id===id);if(!p)return;setCart(old=>{const next={...old};const q=Math.max(0,Math.min(p.stock,(old[id]||0)+n));if(q)next[id]=q;else delete next[id];return next})}
return <Context.Provider value={{cart,change}}><header className="wrap nav"><Link href="/" className="brand">Arte<span>Liê</span><small className="block text-xs tracking-widest">ESPAÇO COLABORATIVO</small></Link><nav aria-label="Menu principal"><Link href="/#vitrine">Vitrine</Link><Link href="/historia">Nossa história</Link><Link href="/login">Entrar</Link><Link href="/carrinho">Sacola ({Object.values(cart).reduce((a,b)=>a+b,0)})</Link></nav></header><main className="wrap">{children}</main><footer><div className="wrap"><strong>ArteLiê · Espaço Colaborativo</strong><p>Artesanato — Afeto — Conexão</p><p className="muted">Ambiente demonstrativo · Nenhuma compra real é processada.</p></div></footer></Context.Provider>}