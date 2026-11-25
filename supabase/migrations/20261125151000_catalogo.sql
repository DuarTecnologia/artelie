begin;
create table public.usuarios_admin (
 id uuid primary key references auth.users(id) on delete cascade,
 nome text not null,
 ativo boolean not null default true
);
create table public.expositores (
 id uuid primary key default gen_random_uuid(),
 usuario_id uuid unique references auth.users(id),
 nome text not null,
 ativo boolean not null default true
);
create table public.classificacoes (
 id uuid primary key default gen_random_uuid(),
 nome text not null unique
);
create table public.tipos_produto (
 id uuid primary key default gen_random_uuid(),
 nome text not null unique
);
create table public.produtos (
 id uuid primary key default gen_random_uuid(),
 nome text not null,
 descricao text not null,
 foto_url text not null,
 preco numeric(12,2) not null check (preco > 0),
 estoque integer not null default 0 check (estoque >= 0),
 estoque_minimo integer not null default 2 check (estoque_minimo >= 0),
 classificacao_id uuid not null references public.classificacoes(id),
 tipo_id uuid not null references public.tipos_produto(id),
 expositor_id uuid references public.expositores(id),
 ativo boolean not null default false,
 aprovado boolean not null default false,
 criado_em timestamptz not null default now()
);
alter table public.usuarios_admin enable row level security;
alter table public.expositores enable row level security;
alter table public.classificacoes enable row level security;
alter table public.tipos_produto enable row level security;
alter table public.produtos enable row level security;
revoke all on public.usuarios_admin, public.expositores, public.classificacoes, public.tipos_produto, public.produtos from anon, authenticated;
grant select on public.classificacoes, public.tipos_produto, public.produtos to anon, authenticated;
create policy catalogo_classificacoes on public.classificacoes for select to anon, authenticated using (true);
create policy catalogo_tipos on public.tipos_produto for select to anon, authenticated using (true);
create policy catalogo_produtos on public.produtos for select to anon, authenticated using (ativo and aprovado);
insert into public.classificacoes(nome) values ('Bolsas'),('Colares'),('Brincos'),('Decoração'),('Carteiras');
insert into public.tipos_produto(nome) values ('Artesanal'),('Sob encomenda'),('Pronta entrega');
commit;