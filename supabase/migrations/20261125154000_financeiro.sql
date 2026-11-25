begin;
create table public.categorias_financeiras (
 id uuid primary key default gen_random_uuid(),
 nome text not null check (length(trim(nome)) > 0),
 tipo text not null check (tipo in ('entrada','saida')),
 ativo boolean not null default true,
 unique(nome,tipo),
 unique(id,tipo)
);
create table public.gastos (
 id uuid primary key default gen_random_uuid(),
 categoria_id uuid not null,
 tipo text generated always as ('saida'::text) stored,
 descricao text not null check (length(trim(descricao)) > 0),
 valor numeric(12,2) not null check (valor > 0),
 data_vencimento date,
 criado_em timestamptz not null default now(),
 usuario_id uuid references auth.users(id) on delete set null,
 foreign key(categoria_id,tipo) references public.categorias_financeiras(id,tipo)
);
create table public.movimentacoes_caixa (
 id uuid primary key default gen_random_uuid(),
 categoria_id uuid not null,
 tipo text not null check (tipo in ('entrada','saida')),
 origem text not null check (origem in ('manual','pagamento','gasto','estorno')),
 descricao text not null check (length(trim(descricao)) > 0),
 valor numeric(12,2) not null check (valor > 0),
 pagamento_id uuid references public.pagamentos(id),
 gasto_id uuid references public.gastos(id),
 usuario_id uuid references auth.users(id) on delete set null,
 data_movimento timestamptz not null default now(),
 criado_em timestamptz not null default now(),
 foreign key(categoria_id,tipo) references public.categorias_financeiras(id,tipo),
 check ((origem = 'pagamento' and tipo = 'entrada' and pagamento_id is not null and gasto_id is null)
 or (origem = 'gasto' and tipo = 'saida' and gasto_id is not null and pagamento_id is null)
 or (origem = 'manual' and pagamento_id is null and gasto_id is null)
 or (origem = 'estorno' and tipo = 'saida' and pagamento_id is not null and gasto_id is null))
);
create unique index caixa_pagamento_unico on public.movimentacoes_caixa(pagamento_id) where origem = 'pagamento';
create unique index caixa_gasto_unico on public.movimentacoes_caixa(gasto_id) where origem = 'gasto';
create index caixa_data_idx on public.movimentacoes_caixa(data_movimento);
create index caixa_categoria_idx on public.movimentacoes_caixa(categoria_id);
create index gastos_categoria_idx on public.gastos(categoria_id);

alter table public.categorias_financeiras enable row level security;
alter table public.gastos enable row level security;
alter table public.movimentacoes_caixa enable row level security;
revoke all on public.categorias_financeiras, public.gastos, public.movimentacoes_caixa from public, anon, authenticated;
grant all on public.categorias_financeiras, public.gastos, public.movimentacoes_caixa to service_role;

insert into public.categorias_financeiras(nome,tipo) values
 ('Vendas Mercado Pago','entrada'),('Vendas manuais','entrada'),('Outras receitas','entrada'),
 ('Matéria-prima','saida'),('Embalagem','saida'),('Marketing','saida'),('Custos fixos','saida'),
 ('Frete','saida'),('Taxas de pagamento','saida'),('Impostos','saida'),('Reembolsos','saida'),('Outras despesas','saida');

create view public.vw_resumo_financeiro with (security_invoker=true) as
select
 coalesce(sum(case when tipo='entrada' then valor else -valor end),0) as saldo_atual,
 coalesce(sum(valor) filter (where tipo='entrada' and date_trunc('month',data_movimento at time zone 'America/Sao_Paulo') = date_trunc('month',now() at time zone 'America/Sao_Paulo')),0) as entradas_mes,
 coalesce(sum(valor) filter (where tipo='saida' and date_trunc('month',data_movimento at time zone 'America/Sao_Paulo') = date_trunc('month',now() at time zone 'America/Sao_Paulo')),0) as saidas_mes
from public.movimentacoes_caixa where data_movimento <= now();

create view public.vw_financeiro_mensal with (security_invoker=true) as
select date_trunc('month',data_movimento at time zone 'America/Sao_Paulo')::date as mes,
 coalesce(sum(valor) filter (where tipo='entrada'),0) as entradas,
 coalesce(sum(valor) filter (where tipo='saida'),0) as saidas,
 sum(case when tipo='entrada' then valor else -valor end) as resultado
from public.movimentacoes_caixa where data_movimento <= now()
group by 1;
revoke all on public.vw_resumo_financeiro, public.vw_financeiro_mensal from public, anon, authenticated;
grant select on public.vw_resumo_financeiro, public.vw_financeiro_mensal to service_role;
-- Caixa por regime de caixa: gastos cadastrados nao afetam saldo ate lancamento.
-- Backend deve validar autorizacao, valor e status do pagamento, registrar gasto pago
-- e confirmar venda atomicamente. Taxas e estornos exigem conciliacao posterior.
commit;
