-- ============================================================
-- ComptaConnect — Paiement en ligne CinetPay (journal des transactions)
-- Prérequis : schema.sql, adhesion.sql, tresorerie.sql
-- ============================================================
create table if not exists cc_transactions (
  id bigserial primary key,
  transaction_id text unique not null,
  membre_id bigint references cc_membres(id) on delete set null,
  code text, mois text, montant integer, montant_recu integer,
  telephone text default '', nom text default '', operateur text default '',
  payment_token text default '',
  statut text default 'EN_ATTENTE',          -- EN_ATTENTE | ACCEPTEE | REFUSEE
  cree_le timestamptz default now(), maj_le timestamptz default now()
);
alter table cc_transactions enable row level security;
drop policy if exists "tresorier cc_transactions" on cc_transactions;
create policy "tresorier cc_transactions" on cc_transactions for select to authenticated using (true);
grant select on cc_transactions to authenticated;
revoke all on cc_transactions from anon;

-- Adresse publique du site (pour le retour après paiement)
insert into cc_settings (cle, valeur) values ('site_public', 'https://doregoservices.github.io/compta-connect/')
on conflict (cle) do nothing;

-- Le site public demande si le paiement en ligne est disponible (sans jamais voir les clés)
create or replace function cc_paiement_en_ligne_dispo() returns boolean
language sql security definer set search_path = public as $$
  select exists(select 1 from cc_secrets where cle = 'cinetpay_api_key' and length(valeur) >= 10)
     and exists(select 1 from cc_secrets where cle = 'cinetpay_site_id' and length(valeur) > 0);
$$;
revoke all on function cc_paiement_en_ligne_dispo() from public;
grant execute on function cc_paiement_en_ligne_dispo() to anon, authenticated;
