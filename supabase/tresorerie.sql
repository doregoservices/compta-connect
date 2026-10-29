-- ============================================================
-- ComptaConnect — Trésorerie (dépenses + solde) et lien Skool
-- À coller dans Supabase → SQL Editor → Run (rejouable sans danger)
-- Prérequis : schema.sql puis adhesion.sql déjà exécutés.
-- ============================================================

-- 1) Lien Skool (bibliothèque de formation) remis avec le lien WhatsApp
insert into cc_settings (cle, valeur) values ('skool_lien', '')
on conflict (cle) do nothing;

create or replace function cc_bienvenue(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_m record;
  v_nb int;
begin
  select * into v_m from cc_membres where code = lpad(p_code, 3, '0');
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select count(*) into v_nb from cc_paiements where membre_id = v_m.id and statut = 'RAPPROCHE';
  if not v_m.actif or v_nb = 0 then
    return json_build_object('ok', false, 'motif', 'attente');
  end if;
  return json_build_object('ok', true,
    'nom', v_m.nom,
    'whatsapp', (select valeur from cc_settings where cle='whatsapp_lien'),
    'skool',    (select valeur from cc_settings where cle='skool_lien'),
    'message',  (select valeur from cc_settings where cle='bienvenue'),
    'tresorier', (select valeur from cc_settings where cle='tresorier'),
    'tresorier_tel', (select valeur from cc_settings where cle='tresorier_tel'));
end $$;
revoke all on function cc_bienvenue(text) from public;
grant execute on function cc_bienvenue(text) to anon, authenticated;

-- 2) Dépenses du réseau
create table if not exists cc_depenses (
  id bigserial primary key,
  date date not null default current_date,
  libelle text not null,
  categorie text default 'Autre',
  montant integer not null check (montant > 0),
  beneficiaire text default '',
  note text default '',
  cree_le timestamptz default now()
);
alter table cc_depenses enable row level security;

-- Les dépenses ne sont visibles que par le trésorier connecté (pas de lecture publique)
drop policy if exists "lecture tresorier cc_depenses" on cc_depenses;
create policy "lecture tresorier cc_depenses" on cc_depenses for select to authenticated using (true);
drop policy if exists "ecriture tresorier cc_depenses" on cc_depenses;
create policy "ecriture tresorier cc_depenses" on cc_depenses for all to authenticated using (true) with check (true);
