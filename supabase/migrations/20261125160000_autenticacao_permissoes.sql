begin;
create function public.e_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.usuarios_admin where id=auth.uid() and ativo)
$$;
create function public.meu_expositor() returns uuid language sql stable security definer set search_path='' as $$
 select id from public.expositores where usuario_id=auth.uid() and ativo
$$;
revoke all on function public.e_admin(), public.meu_expositor() from public,anon,authenticated;
grant execute on function public.e_admin(), public.meu_expositor() to authenticated,service_role;
alter table public.produtos add column motivo_reprovacao text;
alter table public.produtos add column aprovado_em timestamptz;
alter table public.produtos add column aprovado_por uuid references auth.users(id) on delete set null;
grant select on public.usuarios_admin,public.expositores,public.clientes,public.pedidos,public.itens_pedido,public.pagamentos,public.reservas_estoque,public.movimentacoes_estoque,public.categorias_financeiras,public.gastos,public.movimentacoes_caixa to authenticated;
grant select on public.vw_resumo_financeiro,public.vw_financeiro_mensal to authenticated;
create policy admin_perfil on public.usuarios_admin for select to authenticated using (public.e_admin());
create policy expositor_perfil on public.expositores for select to authenticated using (public.e_admin() or id=public.meu_expositor());
create policy produtos_privados on public.produtos for select to authenticated using (public.e_admin() or expositor_id=public.meu_expositor());
create policy clientes_leitura on public.clientes for select to authenticated using (public.e_admin() or usuario_id=auth.uid());
create policy pedidos_leitura on public.pedidos for select to authenticated using (public.e_admin() or exists(select 1 from public.clientes c where c.id=cliente_id and c.usuario_id=auth.uid()));
create policy itens_leitura on public.itens_pedido for select to authenticated using (public.e_admin() or exists(select 1 from public.pedidos p join public.clientes c on c.id=p.cliente_id where p.id=pedido_id and c.usuario_id=auth.uid()));
create policy pagamentos_admin on public.pagamentos for select to authenticated using (public.e_admin());
create policy reservas_admin on public.reservas_estoque for select to authenticated using (public.e_admin());
create policy estoque_leitura on public.movimentacoes_estoque for select to authenticated using (public.e_admin() or exists(select 1 from public.produtos p where p.id=produto_id and p.expositor_id=public.meu_expositor()));
create policy categorias_fin_admin on public.categorias_financeiras for select to authenticated using (public.e_admin());
create policy gastos_admin on public.gastos for select to authenticated using (public.e_admin());
create policy caixa_admin on public.movimentacoes_caixa for select to authenticated using (public.e_admin());
-- Financial views remain backend-only to avoid misleading zero balances for non-admins.
revoke select on public.vw_resumo_financeiro,public.vw_financeiro_mensal from authenticated;
grant insert(nome,descricao,foto_url,preco,classificacao_id,tipo_id,expositor_id) on public.produtos to authenticated;
grant update(nome,descricao,foto_url,preco,classificacao_id,tipo_id) on public.produtos to authenticated;
create policy produtos_inserir on public.produtos for insert to authenticated with check ((public.e_admin() or expositor_id=public.meu_expositor()) and not aprovado and not ativo and estoque=0);
create policy produtos_editar on public.produtos for update to authenticated using (public.e_admin() or expositor_id=public.meu_expositor()) with check (public.e_admin() or expositor_id=public.meu_expositor());
create function public.revisao_produto() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if row(new.nome,new.descricao,new.foto_url,new.preco,new.classificacao_id,new.tipo_id,new.expositor_id) is distinct from row(old.nome,old.descricao,old.foto_url,old.preco,old.classificacao_id,old.tipo_id,old.expositor_id) then
 new.aprovado:=false; new.ativo:=false; new.aprovado_em:=null; new.aprovado_por:=null; new.motivo_reprovacao:=null;
 end if;
 return new;
end $$;
create trigger revisao_produto before update on public.produtos for each row execute function public.revisao_produto();
revoke all on function public.revisao_produto() from public,anon,authenticated;
create function public.decidir_produto(p_id uuid,p_aprovar boolean,p_motivo text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.e_admin() then raise exception 'Acesso negado'; end if;
 if p_aprovar is null or (not p_aprovar and nullif(trim(p_motivo),'') is null) then raise exception 'Decisao invalida'; end if;
 update public.produtos set aprovado=p_aprovar,ativo=p_aprovar,aprovado_em=case when p_aprovar then now() end,aprovado_por=case when p_aprovar then auth.uid() end,motivo_reprovacao=case when not p_aprovar then p_motivo end where id=p_id;
 if not found then raise exception 'Produto inexistente'; end if;
end $$;
revoke all on function public.decidir_produto(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.decidir_produto(uuid,boolean,text) to authenticated;
-- Explicitly prevent direct writes to privileged columns, including through inherited table grants.
revoke update on public.produtos from anon,authenticated;
grant update(nome,descricao,foto_url,preco,classificacao_id,tipo_id) on public.produtos to authenticated;
-- Account provisioning and linking customer identities must be performed by trusted backend.
-- No automatic linking by unverified email; no direct stock changes or role assignment.
commit;