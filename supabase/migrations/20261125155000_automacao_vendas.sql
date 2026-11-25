begin;
-- All stock-changing workflows must lock the product rows in UUID order.
create function public.reservar_pedido(p_cliente uuid,p_itens jsonb)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_pedido uuid; r record; v_prod public.produtos%rowtype; v_res bigint; v_total numeric := 0; v_exp timestamptz := clock_timestamp()+interval '30 minutes';
begin
 if jsonb_typeof(p_itens) is distinct from 'array' then raise exception 'Carrinho invalido'; end if;
 if jsonb_array_length(p_itens) not between 1 and 100 then raise exception 'Carrinho invalido'; end if;
 if exists(select 1 from jsonb_to_recordset(p_itens) as x(produto_id uuid, quantidade integer) where produto_id is null or quantidade is null or quantidade <= 0 or quantidade > 10000) then raise exception 'Item invalido'; end if;
 insert into public.pedidos(cliente_id,total) values(p_cliente,0) returning id into v_pedido;
 for r in select produto_id,sum(quantidade)::integer as quantidade from jsonb_to_recordset(p_itens) as x(produto_id uuid,quantidade integer) group by produto_id order by produto_id loop
  select * into v_prod from public.produtos where id=r.produto_id for update;
  if not found or not v_prod.ativo or not v_prod.aprovado then raise exception 'Produto indisponivel'; end if;
  select coalesce(sum(quantidade),0) into v_res from public.reservas_estoque where produto_id=r.produto_id and status='ativa' and expira_em>clock_timestamp();
  if v_prod.estoque-v_res<r.quantidade then raise exception 'Estoque insuficiente'; end if;
  insert into public.itens_pedido(pedido_id,produto_id,nome_produto,quantidade,preco_unitario) values(v_pedido,r.produto_id,v_prod.nome,r.quantidade,v_prod.preco);
  insert into public.reservas_estoque(pedido_id,produto_id,quantidade,expira_em) values(v_pedido,r.produto_id,r.quantidade,v_exp);
  v_total:=v_total+r.quantidade*v_prod.preco;
 end loop;
 update public.pedidos set total=v_total where id=v_pedido;
 return v_pedido;
end $$;

create function public.confirmar_pagamento(p_pedido uuid,p_transacao text,p_valor numeric)
returns text language plpgsql security invoker set search_path='' as $$
declare v public.pedidos%rowtype; r record; v_pag uuid; v_cat uuid; v_estoque integer; v_outros bigint;
begin
 if p_transacao is null or trim(p_transacao)='' or p_valor is null then raise exception 'Pagamento invalido'; end if;
 select * into v from public.pedidos where id=p_pedido for update;
 if not found or p_valor<>v.total then raise exception 'Pedido ou valor invalido'; end if;
 if exists(select 1 from public.pagamentos where provedor='mercado_pago' and transacao_externa_id=p_transacao and pedido_id=p_pedido and status='aprovado') then return 'ja_processado'; end if;
 if v.status<>'pendente' then raise exception 'Pedido nao pendente: conciliacao necessaria'; end if;
 if not exists(select 1 from public.itens_pedido where pedido_id=p_pedido) then raise exception 'Pedido vazio'; end if;
 for r in select * from public.itens_pedido where pedido_id=p_pedido order by produto_id loop
  select estoque into v_estoque from public.produtos where id=r.produto_id for update;
  if not exists(select 1 from public.reservas_estoque where pedido_id=p_pedido and produto_id=r.produto_id and quantidade=r.quantidade and status='ativa' and expira_em>clock_timestamp()) then raise exception 'Reserva vencida: conciliacao necessaria'; end if;
  select coalesce(sum(quantidade),0) into v_outros from public.reservas_estoque where produto_id=r.produto_id and pedido_id<>p_pedido and status='ativa' and expira_em>clock_timestamp();
  if v_estoque-v_outros<r.quantidade then raise exception 'Estoque insuficiente: conciliacao necessaria'; end if;
  update public.produtos set estoque=estoque-r.quantidade where id=r.produto_id;
  update public.reservas_estoque set status='consumida' where pedido_id=p_pedido and produto_id=r.produto_id;
  insert into public.movimentacoes_estoque(produto_id,pedido_id,tipo,quantidade,motivo) values(r.produto_id,p_pedido,'saida',-r.quantidade,'Venda confirmada');
 end loop;
 insert into public.pagamentos(pedido_id,transacao_externa_id,status,valor,confirmado_em) values(p_pedido,p_transacao,'aprovado',p_valor,now()) returning id into v_pag;
 select id into strict v_cat from public.categorias_financeiras where nome='Vendas Mercado Pago' and tipo='entrada';
 insert into public.movimentacoes_caixa(categoria_id,tipo,origem,descricao,valor,pagamento_id) values(v_cat,'entrada','pagamento','Venda Mercado Pago',p_valor,v_pag);
 update public.pedidos set status='pago' where id=p_pedido;
 return 'pago';
end $$;

create function public.cancelar_pedido(p_pedido uuid)
returns text language plpgsql security invoker set search_path='' as $$
declare v text;
begin
 select status into v from public.pedidos where id=p_pedido for update;
 if not found then raise exception 'Pedido inexistente'; end if;
 if v='cancelado' then return v; end if;
 if v<>'pendente' then raise exception 'Pedido pago exige reembolso confirmado'; end if;
 update public.reservas_estoque set status='liberada' where pedido_id=p_pedido and status='ativa';
 update public.pedidos set status='cancelado' where id=p_pedido;
 return 'cancelado';
end $$;

create function public.expirar_reservas()
returns integer language plpgsql security invoker set search_path='' as $$
declare r record; n integer:=0;
begin
 for r in select p.id from public.pedidos p where p.status='pendente' and exists(select 1 from public.reservas_estoque s where s.pedido_id=p.id and s.status='ativa' and s.expira_em<=clock_timestamp()) order by p.id for update of p skip locked loop
 update public.reservas_estoque set status='expirada' where pedido_id=r.id and status='ativa';
 update public.pedidos set status='cancelado' where id=r.id;
 n:=n+1;
 end loop;
 return n;
end $$;

create function public.reembolsar_pedido(p_pedido uuid,p_transacao text,p_valor numeric)
returns text language plpgsql security invoker set search_path='' as $$
declare v public.pedidos%rowtype; r record; v_pag uuid; v_cat uuid;
begin
 select * into v from public.pedidos where id=p_pedido for update;
 if not found or p_valor is null or p_valor<>v.total then raise exception 'Reembolso invalido'; end if;
 if v.status='reembolsado' then
 if exists(select 1 from public.pagamentos where pedido_id=p_pedido and provedor='mercado_pago' and transacao_externa_id=p_transacao and status='reembolsado') then return 'ja_processado'; end if;
 raise exception 'Transacao divergente';
 end if;
 if v.status<>'pago' then raise exception 'Reembolso automatico apenas antes do envio'; end if;
 select id into strict v_pag from public.pagamentos where pedido_id=p_pedido and provedor='mercado_pago' and transacao_externa_id=p_transacao and status='aprovado' and valor=p_valor;
 for r in select * from public.itens_pedido where pedido_id=p_pedido order by produto_id loop
 update public.produtos set estoque=estoque+r.quantidade where id=r.produto_id;
 insert into public.movimentacoes_estoque(produto_id,pedido_id,tipo,quantidade,motivo) values(r.produto_id,p_pedido,'estorno',r.quantidade,'Reembolso integral confirmado');
 end loop;
 select id into strict v_cat from public.categorias_financeiras where nome='Reembolsos' and tipo='saida';
 insert into public.movimentacoes_caixa(categoria_id,tipo,origem,descricao,valor,pagamento_id) values(v_cat,'saida','estorno','Reembolso integral',p_valor,v_pag);
 update public.pagamentos set status='reembolsado' where id=v_pag;
 update public.pedidos set status='reembolsado' where id=p_pedido;
 return 'reembolsado';
end $$;

revoke all on function public.reservar_pedido(uuid,jsonb), public.confirmar_pagamento(uuid,text,numeric), public.cancelar_pedido(uuid), public.expirar_reservas(), public.reembolsar_pedido(uuid,text,numeric) from public,anon,authenticated;
grant execute on function public.reservar_pedido(uuid,jsonb), public.confirmar_pagamento(uuid,text,numeric), public.cancelar_pedido(uuid), public.expirar_reservas(), public.reembolsar_pedido(uuid,text,numeric) to service_role;
grant select,update on public.produtos to service_role;
grant select on public.categorias_financeiras to service_role;
-- Backend must verify provider signature, payment status, currency and external reference.
-- Late approvals, partial refunds, fees and shipped returns require reconciliation.
-- Expiration scheduler and checkout preference expiration must be configured separately.
-- All future stock adjustments must respect active reservations and product locks.
commit;