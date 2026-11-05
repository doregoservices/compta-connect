-- ============================================================
-- ComptaConnect — Vie du réseau
--   • Matricule de carte (CC-AA-NNNNN) attribué automatiquement
--   • Photos (membres, bureau, rencontres) dans Supabase Storage
--   • Bureau affiché sur la page d'accueil
--   • Galerie « Nos rencontres »
--   • Appels à paiement (formations, documents, carte membre…)
-- À coller dans Supabase → SQL Editor → Run (rejouable sans danger)
-- Prérequis : schema.sql, adhesion.sql, tresorerie.sql, cinetpay.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) MATRICULE
-- ------------------------------------------------------------
alter table cc_membres add column if not exists matricule text unique;
alter table cc_membres add column if not exists photo_url text default '';
alter table cc_membres add column if not exists titre text default '';   -- ex. « Comptable senior | Consultant fiscal »

-- Normalise une saisie : « cc-26-00026 », « CC2600026 », « 2600026 » → « CC-26-00026 »
create or replace function cc_matricule_normaliser(p text) returns text
language plpgsql immutable as $$
declare v text := upper(regexp_replace(coalesce(p,''), '[^0-9A-Za-z]', '', 'g'));
begin
  if v like 'CC%' then v := substr(v, 3); end if;
  if v !~ '^\d{7}$' then return null; end if;
  return 'CC-' || substr(v,1,2) || '-' || substr(v,3,5);
end $$;

-- Numéro suivant : la série (5 chiffres) continue d'année en année ; l'année est celle de l'attribution.
create or replace function cc_matricule_suivant() returns text
language plpgsql as $$
declare v_max int; v_dernier text;
begin
  select coalesce(max(substr(matricule, 7, 5)::int), 0) into v_max
    from cc_membres where matricule ~ '^CC-\d{2}-\d{5}$';
  -- le trésorier peut réserver des numéros déjà imprimés : réglage « matricule_depart »
  select valeur into v_dernier from cc_settings where cle = 'matricule_depart';
  if v_dernier ~ '^\d+$' and v_dernier::int > v_max then v_max := v_dernier::int; end if;
  return 'CC-' || to_char(current_date, 'YY') || '-' || lpad((v_max + 1)::text, 5, '0');
end $$;

-- Attribution automatique à la création (import CSV, formulaire, adhésion en ligne)
create or replace function cc_membres_matricule_auto() returns trigger
language plpgsql as $$
begin
  if new.matricule is null or trim(new.matricule) = '' then
    new.matricule := cc_matricule_suivant();
  else
    new.matricule := coalesce(cc_matricule_normaliser(new.matricule), upper(trim(new.matricule)));
  end if;
  return new;
end $$;
drop trigger if exists trg_cc_membres_matricule on cc_membres;
create trigger trg_cc_membres_matricule before insert or update of matricule on cc_membres
  for each row execute function cc_membres_matricule_auto();

-- Membres déjà présents sans matricule : attribués dans l'ordre des codes
do $$
declare r record;
begin
  for r in select id from cc_membres where matricule is null or matricule = '' order by code loop
    update cc_membres set matricule = cc_matricule_suivant() where id = r.id;
  end loop;
end $$;

insert into cc_settings (cle, valeur) values ('matricule_depart', '0') on conflict (cle) do nothing;

-- Le membre qui a oublié son matricule le retrouve avec son téléphone
create or replace function cc_retrouver_matricule(p_tel text) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_m record;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_tel) < 8 then return json_build_object('ok', false); end if;
  select matricule, nom into v_m from cc_membres
    where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if not found then return json_build_object('ok', false); end if;
  return json_build_object('ok', true, 'matricule', v_m.matricule, 'prenom', split_part(v_m.nom, ' ', 1));
end $$;
revoke all on function cc_retrouver_matricule(text) from public;
grant execute on function cc_retrouver_matricule(text) to anon, authenticated;

-- Le membre met à jour SA photo (après avoir confirmé les 4 derniers chiffres de son téléphone)
create or replace function cc_membre_photo(p_matricule text, p_tel4 text, p_url text) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record;
begin
  select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(regexp_replace(coalesce(v_m.telephone,''), '\D', '', 'g')) >= 4
     and right(regexp_replace(v_m.telephone, '\D', '', 'g'), 4) <> regexp_replace(coalesce(p_tel4,''), '\D', '', 'g') then
    return json_build_object('ok', false, 'motif', 'telephone');
  end if;
  update cc_membres set photo_url = coalesce(p_url,'') where id = v_m.id;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_membre_photo(text,text,text) from public;
grant execute on function cc_membre_photo(text,text,text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2) PHOTOS : un seul bucket public, images ≤ 400 Ko (compressées par le navigateur)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cc_photos', 'cc_photos', true, 400000, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 400000, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "cc_photos lecture" on storage.objects;
create policy "cc_photos lecture" on storage.objects for select using (bucket_id = 'cc_photos');
drop policy if exists "cc_photos tresorier" on storage.objects;
create policy "cc_photos tresorier" on storage.objects for all to authenticated
  using (bucket_id = 'cc_photos') with check (bucket_id = 'cc_photos');
-- un membre (anonyme) ne peut déposer que dans membres/ (sa propre photo)
drop policy if exists "cc_photos membre depot" on storage.objects;
create policy "cc_photos membre depot" on storage.objects for insert to anon
  with check (bucket_id = 'cc_photos' and name like 'membres/%');
drop policy if exists "cc_photos membre maj" on storage.objects;
create policy "cc_photos membre maj" on storage.objects for update to anon
  using (bucket_id = 'cc_photos' and name like 'membres/%') with check (bucket_id = 'cc_photos' and name like 'membres/%');

-- ------------------------------------------------------------
-- 3) BUREAU (page d'accueil)
-- ------------------------------------------------------------
create table if not exists cc_bureau (
  id bigserial primary key,
  nom text not null,
  poste text not null,
  telephone text default '',
  photo_url text default '',
  ordre integer default 100,
  actif boolean default true
);
alter table cc_bureau enable row level security;
drop policy if exists "lecture publique cc_bureau" on cc_bureau;
create policy "lecture publique cc_bureau" on cc_bureau for select using (true);
drop policy if exists "ecriture tresorier cc_bureau" on cc_bureau;
create policy "ecriture tresorier cc_bureau" on cc_bureau for all to authenticated using (true) with check (true);
grant select on cc_bureau to anon, authenticated;
grant insert, update, delete on cc_bureau to authenticated;
grant usage, select on sequence cc_bureau_id_seq to authenticated;

insert into cc_settings (cle, valeur) values ('photo_groupe_url', ''), ('presentation', '') on conflict (cle) do nothing;

-- ------------------------------------------------------------
-- 4) NOS RENCONTRES (galerie)
-- ------------------------------------------------------------
create table if not exists cc_rencontres (
  id bigserial primary key,
  titre text not null,
  date date not null default current_date,
  lieu text default '',
  description text default '',
  photos jsonb not null default '[]'::jsonb,     -- liste d'URL
  publie boolean default true
);
alter table cc_rencontres enable row level security;
drop policy if exists "lecture publique cc_rencontres" on cc_rencontres;
create policy "lecture publique cc_rencontres" on cc_rencontres for select using (true);
drop policy if exists "ecriture tresorier cc_rencontres" on cc_rencontres;
create policy "ecriture tresorier cc_rencontres" on cc_rencontres for all to authenticated using (true) with check (true);
grant select on cc_rencontres to anon, authenticated;
grant insert, update, delete on cc_rencontres to authenticated;
grant usage, select on sequence cc_rencontres_id_seq to authenticated;

-- ------------------------------------------------------------
-- 5) APPELS À PAIEMENT (formation, document, carte membre, autre)
-- ------------------------------------------------------------
create table if not exists cc_appels (
  id bigserial primary key,
  titre text not null,
  type text default 'autre',             -- formation | document | carte | autre
  description text default '',
  montant integer not null check (montant > 0),
  date_limite date,
  lien_apres text default '',            -- lien remis après paiement (document, salle de formation…)
  ouvert boolean default true,
  cree_le timestamptz default now()
);
alter table cc_appels enable row level security;
drop policy if exists "lecture publique cc_appels" on cc_appels;
create policy "lecture publique cc_appels" on cc_appels for select using (true);
drop policy if exists "ecriture tresorier cc_appels" on cc_appels;
create policy "ecriture tresorier cc_appels" on cc_appels for all to authenticated using (true) with check (true);
grant select on cc_appels to anon, authenticated;
grant insert, update, delete on cc_appels to authenticated;
grant usage, select on sequence cc_appels_id_seq to authenticated;

-- Un paiement peut concerner un appel (et non une cotisation mensuelle : mois reste vide)
alter table cc_paiements add column if not exists appel_id bigint references cc_appels(id) on delete set null;
alter table cc_transactions add column if not exists appel_id bigint references cc_appels(id) on delete set null;

-- Le lien « après paiement » n'est remis qu'à un membre qui a payé l'appel
create or replace function cc_appel_acces(p_matricule text, p_appel bigint) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_a record; v_paye int;
begin
  select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select * into v_a from cc_appels where id = p_appel;
  if not found then return json_build_object('ok', false, 'motif', 'appel'); end if;
  select coalesce(sum(montant),0) into v_paye from cc_paiements where membre_id = v_m.id and appel_id = p_appel and statut = 'RAPPROCHE';
  if v_paye < v_a.montant then return json_build_object('ok', false, 'motif', 'impaye', 'paye', v_paye); end if;
  return json_build_object('ok', true, 'lien', v_a.lien_apres, 'paye', v_paye);
end $$;
revoke all on function cc_appel_acces(text,bigint) from public;
grant execute on function cc_appel_acces(text,bigint) to anon, authenticated;

-- ------------------------------------------------------------
-- 6) L'adhésion en ligne renvoie aussi le matricule attribué
-- ------------------------------------------------------------
create or replace function cc_adherer(p_nom text, p_tel text, p_ville text default '', p_email text default '', p_specialite text default '')
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  v_code text;
  v_id bigint;
  v_mat text;
  v_existant record;
begin
  if length(trim(coalesce(p_nom,''))) < 3 then raise exception 'Nom trop court'; end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;

  select id, code, matricule, actif into v_existant from cc_membres
    where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if found then
    return json_build_object('code', v_existant.code, 'matricule', v_existant.matricule, 'id', v_existant.id, 'actif', v_existant.actif, 'existant', true);
  end if;

  select lpad((coalesce(max(code::int), 0) + 1)::text, 3, '0') into v_code from cc_membres where code ~ '^\d+$';

  insert into cc_membres (code, nom, telephone, ville, specialite, email, cotisation, date_adhesion, actif, exonere)
  values (v_code, trim(p_nom), v_tel, coalesce(p_ville,''), coalesce(p_specialite,''), coalesce(p_email,''),
          coalesce((select valeur::int from cc_settings where cle='cotisation'), 5000),
          to_char(current_date, 'YYYY-MM-DD'), false, false)
  returning id, matricule into v_id, v_mat;

  return json_build_object('code', v_code, 'matricule', v_mat, 'id', v_id, 'actif', false, 'existant', false);
end $$;
revoke all on function cc_adherer(text,text,text,text,text) from public;
grant execute on function cc_adherer(text,text,text,text,text) to anon, authenticated;

-- ------------------------------------------------------------
-- 7) ANNONCES (tableau d'affichage officiel du bureau)
-- ------------------------------------------------------------
create table if not exists cc_annonces (
  id bigserial primary key,
  titre text not null,
  texte text default '',
  image_url text default '',
  lien text default '',
  lien_libelle text default '',
  appel_id bigint references cc_appels(id) on delete set null,
  epingle boolean default false,
  publie boolean default true,
  date date not null default current_date,
  cree_le timestamptz default now()
);
alter table cc_annonces enable row level security;
drop policy if exists "lecture publique cc_annonces" on cc_annonces;
create policy "lecture publique cc_annonces" on cc_annonces for select using (true);
drop policy if exists "ecriture tresorier cc_annonces" on cc_annonces;
create policy "ecriture tresorier cc_annonces" on cc_annonces for all to authenticated using (true) with check (true);
grant select on cc_annonces to anon, authenticated;
grant insert, update, delete on cc_annonces to authenticated;
grant usage, select on sequence cc_annonces_id_seq to authenticated;

-- ------------------------------------------------------------
-- 8) MARCHÉ : vitrines louées (revenu du réseau ; la vente se fait entre acheteur et vendeur, hors plateforme)
-- ------------------------------------------------------------
create table if not exists cc_vitrines (
  id bigserial primary key,
  nom text not null,
  proprietaire text default '',
  membre_id bigint references cc_membres(id) on delete set null,
  telephone text default '',                 -- WhatsApp du vendeur
  categorie text default '',
  description text default '',
  logo_url text default '',
  photos jsonb not null default '[]'::jsonb,
  produits jsonb not null default '[]'::jsonb,   -- [{"nom":"…","prix":5000}]
  loyer_mensuel integer default 0,
  fin_location date,                         -- vitrine visible tant que fin_location >= aujourd'hui
  en_avant boolean default false,
  publie boolean default true,
  cree_le timestamptz default now()
);
alter table cc_vitrines enable row level security;
drop policy if exists "lecture publique cc_vitrines" on cc_vitrines;
create policy "lecture publique cc_vitrines" on cc_vitrines for select using (true);
drop policy if exists "ecriture tresorier cc_vitrines" on cc_vitrines;
create policy "ecriture tresorier cc_vitrines" on cc_vitrines for all to authenticated using (true) with check (true);
grant select on cc_vitrines to anon, authenticated;
grant insert, update, delete on cc_vitrines to authenticated;
grant usage, select on sequence cc_vitrines_id_seq to authenticated;

-- Un appel à paiement peut être un loyer de vitrine : le paiement prolonge automatiquement la location
alter table cc_appels add column if not exists vitrine_id bigint references cc_vitrines(id) on delete set null;
alter table cc_appels add column if not exists duree_mois integer default 0;

create or replace function cc_prolonger_vitrine() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_a record;
begin
  if new.appel_id is null or new.statut <> 'RAPPROCHE' then return new; end if;
  select vitrine_id, duree_mois into v_a from cc_appels where id = new.appel_id;
  if v_a.vitrine_id is null or coalesce(v_a.duree_mois,0) <= 0 then return new; end if;
  update cc_vitrines
     set fin_location = (greatest(coalesce(fin_location, current_date), current_date) + (v_a.duree_mois || ' months')::interval)::date,
         publie = true
   where id = v_a.vitrine_id;
  return new;
end $$;
drop trigger if exists trg_cc_prolonger_vitrine on cc_paiements;
create trigger trg_cc_prolonger_vitrine after insert or update of statut, appel_id on cc_paiements
  for each row execute function cc_prolonger_vitrine();

-- ------------------------------------------------------------
-- 9) MATRICULE : saisi par le membre (carte) ; attribution automatique seulement si le trésorier l'active
-- ------------------------------------------------------------
insert into cc_settings (cle, valeur) values ('matricule_auto', 'non') on conflict (cle) do nothing;

create or replace function cc_membres_matricule_auto() returns trigger
language plpgsql as $$
declare v_auto text; v_depart text;
begin
  if new.matricule is not null and trim(new.matricule) <> '' then
    new.matricule := coalesce(cc_matricule_normaliser(new.matricule), upper(trim(new.matricule)));
    return new;
  end if;
  new.matricule := null;
  select valeur into v_auto from cc_settings where cle = 'matricule_auto';
  select valeur into v_depart from cc_settings where cle = 'matricule_depart';
  if v_auto = 'oui' and v_depart ~ '^\d+$' and v_depart::int > 0 then
    new.matricule := cc_matricule_suivant();
  end if;
  return new;
end $$;

-- Les matricules provisoires attribués automatiquement lors de l'installation sont retirés :
-- chaque membre saisira celui de sa carte.
update cc_membres set matricule = null
 where matricule is not null and coalesce((select valeur from cc_settings where cle='matricule_auto'),'non') <> 'oui'
   and not exists (select 1 from cc_settings where cle = 'matricules_conserves' and valeur = 'oui');
insert into cc_settings (cle, valeur) values ('matricules_conserves', 'oui') on conflict (cle) do nothing;

-- Le membre déclare son matricule (une seule fois). Identifié par son téléphone.
create or replace function cc_declarer_matricule(p_tel text, p_matricule text) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_m record; v_mat text;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  v_mat := cc_matricule_normaliser(p_matricule);
  if v_mat is null then return json_build_object('ok', false, 'motif', 'format'); end if;
  select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if v_m.matricule is not null and v_m.matricule <> '' then return json_build_object('ok', false, 'motif', 'deja', 'matricule', v_m.matricule); end if;
  if exists (select 1 from cc_membres where matricule = v_mat) then return json_build_object('ok', false, 'motif', 'pris'); end if;
  update cc_membres set matricule = v_mat where id = v_m.id;
  return json_build_object('ok', true, 'matricule', v_mat);
end $$;
revoke all on function cc_declarer_matricule(text,text) from public;
grant execute on function cc_declarer_matricule(text,text) to anon, authenticated;

-- Photo du membre : identifié par matricule OU téléphone (4 derniers chiffres confirmés)
drop function if exists cc_membre_photo(text,text,text);
create or replace function cc_membre_photo(p_matricule text, p_tel text, p_tel4 text, p_url text) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if cc_matricule_normaliser(p_matricule) is not null then
    select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  elsif length(v_tel) >= 8 then
    select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  end if;
  if v_m is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(regexp_replace(coalesce(v_m.telephone,''), '\D', '', 'g')) >= 4
     and right(regexp_replace(v_m.telephone, '\D', '', 'g'), 4) <> regexp_replace(coalesce(p_tel4,''), '\D', '', 'g') then
    return json_build_object('ok', false, 'motif', 'telephone');
  end if;
  update cc_membres set photo_url = coalesce(p_url,'') where id = v_m.id;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_membre_photo(text,text,text,text) from public;
grant execute on function cc_membre_photo(text,text,text,text) to anon, authenticated;

-- ------------------------------------------------------------
-- 10) FICHE MEMBRE complétée par le membre lui-même (infos non sensibles)
-- ------------------------------------------------------------
alter table cc_membres add column if not exists employeur text default '';
alter table cc_membres add column if not exists fiche_maj_le timestamptz;
insert into cc_settings (cle, valeur) values ('debut_cotisations', '') on conflict (cle) do nothing;

create or replace function cc_maj_fiche(p_tel text, p_matricule text, p_nom text, p_email text, p_ville text, p_specialite text, p_employeur text) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if cc_matricule_normaliser(p_matricule) is not null then
    select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  elsif length(v_tel) >= 8 then
    select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  end if;
  if v_m is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_nom,''))) < 3 then return json_build_object('ok', false, 'motif', 'nom'); end if;
  update cc_membres set nom = left(trim(p_nom), 80), email = left(lower(trim(coalesce(p_email,''))), 120),
    ville = left(trim(coalesce(p_ville,'')), 60), specialite = left(trim(coalesce(p_specialite,'')), 80),
    employeur = left(trim(coalesce(p_employeur,'')), 80), fiche_maj_le = now()
  where id = v_m.id;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_maj_fiche(text,text,text,text,text,text,text) from public;
grant execute on function cc_maj_fiche(text,text,text,text,text,text,text) to anon, authenticated;
