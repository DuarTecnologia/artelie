import type { Metadata } from 'next';
import './globals.css';
import { Shell } from './shell';
export const metadata: Metadata = { title: 'ArteLiê | Espaço Colaborativo', description: 'Artesanato, afeto e conexão.' };
export default function Layout({children}:{children:React.ReactNode}) {return <html lang="pt-BR"><body><Shell>{children}</Shell></body></html>}