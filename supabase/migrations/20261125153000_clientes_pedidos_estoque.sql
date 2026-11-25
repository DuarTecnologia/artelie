begin;

create table public.clientes (
 id uuid primary key default gen_random_uuid(),
 usuario_id uuid unique references auth.users(id) on delete set null,
 nome text not null check (length(trim(nome)) > 0),
 email text not null,
 telefone text,
 endereco jsonb not null default '{}'::jsonb,
 criado_em timestamptz not null default now()
);
create unique index clientes_email_unique on public.clientes(lower(trim(email)));

create table public.pedidos (
 id uuid primary key default gen_random_uuid(),
 numero bigint generated always as identity unique,
 cliente_id uuid not null references public.clientes(id),
 status text not null default 'pendente' check (status in ('pendente','pago','enviado','entregue','cancelado','reembolsado')),
 total numeric(12,2) not null check (total >= 0),
 frete numeric(12,2) not null default 0 check (frete >= 0),
 endereco_entrega jsonb not null default '{}'::jsonb,
 criado_em timestamptz not null default now()
);
create index pedidos_cliente_idx on public.pedidos(cliente_id);
create index pedidos_status_idx on public.pedidos(status, criado_em);

create table public.itens_pedido (
 id uuid primary key default gen_random_uuid(),
 pedido_id uuid not null references public.pedidos(id),
 produto_id uuid not null references public.produtos(id),
 nome_produto text not null,
 quantidade integer not null check (quantidade > 0),
 preco_unitario numeric(12,2) not null check (preco_unitario > 0),
 subtotal numeric(14,2) generated always as (quantidade * preco_unitario) stored,
 unique(pedido_id, produto_id)
);
create index itens_produto_idx on public.itens_pedido(produto_id);

create table public.pagamentos (
 id uuid primary key default gen_random_uuid(),
 pedido_id uuid not null references public.pedidos(id),
 provedor text not null default 'mercado_pago',
 transacao_externa_id text,
 status text not null default 'pendente' check (status in ('pendente','aprovado','recusado','cancelado','reembolsado','contestacao')),
 valor numeric(12,2) not null check (valor > 0),
 moeda text not null default 'BRL' check (moeda = 'BRL'),
 confirmado_em timestamptz,
 criado_em timestamptz not null default now(),
 unique(provedor, transacao_externa_id)
);
create index pagamentos_pedido_idx on public.pagamentos(pedido_id);

create table public.reservas_estoque (
 id uuid primary key default gen_random_uuid(),
 pedido_id uuid not null references public.pedidos(id),
 produto_id uuid not null references public.produtos(id),
 quantidade integer not null check (quantidade > 0),
 status text not null default 'ativa' check (status in ('ativa','consumida','liberada','expirada')),
 criado_em timestamptz not null default now(),
 expira_em timestamptz not null,
 check (expira_em > criado_em),
 unique(pedido_id, produto_id)
);
create index reservas_ativas_idx on public.reservas_estoque(produto_id, expira_em) where status = 'ativa';

create table public.movimentacoes_estoque (
 id uuid primary key default gen_random_uuid(),
 produto_id uuid not null references public.produtos(id),
 pedido_id uuid references public.pedidos(id),
 usuario_id uuid references auth.users(id) on delete set null,
 tipo text not null check (tipo in ('entrada','saida','ajuste','estorno')),
 quantidade integer not null check (quantidade <> 0),
 motivo text not null,
 criado_em timestamptz not null default now(),
 check ((tipo in ('entrada','estorno') and quantidade > 0) or (tipo = 'saida' and quantidade < 0) or tipo = 'ajuste')
);
create index movimentacoes_produto_idx on public.movimentacoes_estoque(produto_id, criado_em);
create unique index movimentacao_venda_unica on public.movimentacoes_estoque(pedido_id, produto_id) where tipo = 'saida' and pedido_id is not null;

alter table public.clientes enable row level security;
alter table public.pedidos enable row level security;
alter table public.itens_pedido enable row level security;
alter table public.pagamentos enable row level security;
alter table public.reservas_estoque enable row level security;
alter table public.movimentacoes_estoque enable row level security;

revoke all on public.clientes, public.pedidos, public.itens_pedido, public.pagamentos, public.reservas_estoque, public.movimentacoes_estoque from public, anon, authenticated;
grant all on public.clientes, public.pedidos, public.itens_pedido, public.pagamentos, public.reservas_estoque, public.movimentacoes_estoque to service_role;
grant usage, select on sequence public.pedidos_numero_seq to service_role;

-- Acesso restrito ao backend confiavel nesta fase.
-- Nenhuma politica de acesso direto para anon/authenticated.
-- Autorizacao administrativa e funcoes transacionais de checkout,
-- reserva, confirmacao e estorno serao implementadas em migracoes posteriores.
-- A reserva por si so nao impede concorrencia nem altera o estoque.

commit;
