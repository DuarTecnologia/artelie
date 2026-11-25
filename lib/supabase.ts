import {createClient, type SupabaseClient} from '@supabase/supabase-js';
let client: SupabaseClient | undefined;
export function getSupabase(){const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;if(!url||!key)throw new Error('Supabase não configurado');if(typeof window==='undefined')return createClient(url,key);return client ??= createClient(url,key);}
