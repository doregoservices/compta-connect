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

-- ------------------------------------------------------------
-- 11) CAISSE DES FRAIS D'INSCRIPTION — tenue à part des cotisations
--     caisse = 'cotisation' (défaut) | 'inscription'. Les frais d'inscription n'entrent jamais
--     dans le calcul des cotisations ni dans le solde de caisse général.
-- ------------------------------------------------------------
alter table cc_paiements add column if not exists caisse text not null default 'cotisation';
alter table cc_paiements add column if not exists reference_externe text default '';
create index if not exists cc_paiements_caisse_idx on cc_paiements (caisse);
create unique index if not exists cc_paiements_reference_externe_idx on cc_paiements (reference_externe) where reference_externe <> '';
alter table cc_transactions add column if not exists caisse text not null default 'cotisation';

-- 12) Bureau exécutif (source : ComptaConnect_Bureau_Executif.docx) — inséré le 06/11/2026 ; postes vacants affichés « Poste à pourvoir »
insert into cc_bureau (nom, poste, telephone, ordre, actif)
select * from (values
 ('EKLOU Basil', 'Président Fondateur', '0102389926', 1, true),
 ('Jean Yves ALLASSANON', 'Secrétaire Général', '0556124488', 2, true),
 ('Kouassi Parfait DABILA', 'Responsable Formation & Événements', '0757912515', 3, true),
 ('Poste à pourvoir', 'Responsable Communication & Contenu', '', 4, true),
 ('Poste à pourvoir', 'Responsable Emploi & Opportunités', '', 5, true),
 ('Poste à pourvoir', 'Responsable Relations Membres & Partenariats', '', 6, true),
 ('Poste à pourvoir', 'Trésorier(e)', '', 7, true)) v(nom, poste, telephone, ordre, actif)
where not exists (select 1 from cc_bureau);

-- ------------------------------------------------------------
-- 13) RÔLES D'ACCÈS À L'ESPACE TRÉSORIER
--     tresorier  : lecture + écriture (défaut pour un compte non listé tant que la table est vide)
--     fondateur  : consulte tout (toutes les pages du trésorier), ne modifie rien
--     Les comptes eux-mêmes sont créés dans Supabase Auth (Authentication → Users) ; cette table dit ce que chacun peut faire.
-- ------------------------------------------------------------
create table if not exists cc_roles (
  email text primary key,
  role text not null default 'fondateur' check (role in ('tresorier','fondateur')),
  nom text default '',
  cree_le timestamptz default now()
);
alter table cc_roles enable row level security;

create or replace function cc_mon_role() returns text
language sql stable security definer set search_path = public as $$
  select case
    when auth.role() <> 'authenticated' then 'public'
    when not exists (select 1 from cc_roles) then 'tresorier'                       -- compatibilité : aucun rôle défini → compte trésorier
    else coalesce((select r.role from cc_roles r where lower(r.email) = lower(coalesce(auth.jwt()->>'email',''))), 'fondateur')
  end;
$$;
grant execute on function cc_mon_role() to anon, authenticated;
create or replace function cc_est_tresorier() returns boolean
language sql stable security definer set search_path = public as $$ select cc_mon_role() = 'tresorier' $$;
grant execute on function cc_est_tresorier() to anon, authenticated;

drop policy if exists "lecture connectes cc_roles" on cc_roles;
create policy "lecture connectes cc_roles" on cc_roles for select to authenticated using (true);
drop policy if exists "ecriture tresorier cc_roles" on cc_roles;
create policy "ecriture tresorier cc_roles" on cc_roles for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
grant select, insert, update, delete on cc_roles to authenticated;

-- Toutes les écritures réservées au rôle trésorier ; la lecture reste ouverte aux comptes connectés (fondateur inclus)
do $$ declare t text; begin
  foreach t in array array['cc_membres','cc_paiements','cc_settings','cc_depenses','cc_appels','cc_bureau','cc_rencontres','cc_annonces','cc_vitrines'] loop
    execute format('drop policy if exists "ecriture tresorier %1$s" on %1$I', t);
    execute format('create policy "ecriture tresorier %1$s" on %1$I for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier())', t);
    execute format('drop policy if exists "lecture connectes %1$s" on %1$I', t);
    execute format('create policy "lecture connectes %1$s" on %1$I for select to authenticated using (true)', t);
  end loop;
end $$;
drop policy if exists "tresorier cc_secrets" on cc_secrets;
create policy "tresorier cc_secrets" on cc_secrets for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
drop policy if exists "cc_photos tresorier" on storage.objects;
create policy "cc_photos tresorier" on storage.objects for all to authenticated using (bucket_id = 'cc_photos' and cc_est_tresorier()) with check (bucket_id = 'cc_photos' and cc_est_tresorier());

-- ------------------------------------------------------------
-- 14) FRAIS DE PLATEFORME (Chariow hier, CinetPay demain)
--     montant = ce que le membre a payé (crédité à sa cotisation) ; frais = commission retenue ; net = montant − frais = ce qui entre en caisse.
-- ------------------------------------------------------------
alter table cc_paiements add column if not exists frais integer not null default 0;
insert into cc_settings (cle, valeur) values ('cinetpay_commission', '3.5') on conflict (cle) do nothing;

-- 15) Pays du membre (recherche, statistiques par pays)
alter table cc_membres add column if not exists pays text default 'Côte d’Ivoire';
drop function if exists cc_maj_fiche(text,text,text,text,text,text,text);
create or replace function cc_maj_fiche(p_tel text, p_matricule text, p_nom text, p_email text, p_ville text, p_specialite text, p_employeur text, p_pays text default null) returns json
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
    employeur = left(trim(coalesce(p_employeur,'')), 80), pays = coalesce(nullif(left(trim(p_pays),60),''), pays, 'Côte d’Ivoire'), fiche_maj_le = now()
  where id = v_m.id;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_maj_fiche(text,text,text,text,text,text,text,text) from public;
grant execute on function cc_maj_fiche(text,text,text,text,text,text,text,text) to anon, authenticated;

-- 16) Zone de couverture du paiement en ligne (CinetPay : zone XOF du compte ivoirien) + procédure hors zone
insert into cc_settings (cle, valeur) values ('pays_couverts', 'Côte d’Ivoire, Burkina Faso, Togo') on conflict (cle) do nothing;
insert into cc_settings (cle, valeur) values ('hors_zone_procedure',
  'Le paiement en ligne n’est pas encore disponible dans votre pays. Envoyez le montant par transfert international mobile money (Wave, Orange Money, MTN, Moov…) au numéro de la trésorerie, puis transmettez la capture d’écran par WhatsApp avec votre nom et votre matricule : votre paiement est enregistré sous 24 h et votre situation mise à jour ici.')
  on conflict (cle) do nothing;
-- Pays saisi dès l'adhésion
drop function if exists cc_adherer(text,text,text,text,text);
create or replace function cc_adherer(p_nom text, p_tel text, p_ville text default '', p_email text default '', p_specialite text default '', p_pays text default '')
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

  insert into cc_membres (code, nom, telephone, ville, specialite, email, pays, cotisation, date_adhesion, actif, exonere)
  values (v_code, trim(p_nom), v_tel, coalesce(p_ville,''), coalesce(p_specialite,''), coalesce(p_email,''),
          coalesce(nullif(left(trim(p_pays),60),''), 'Côte d’Ivoire'),
          coalesce((select valeur::int from cc_settings where cle='cotisation'), 5000),
          to_char(current_date, 'YYYY-MM-DD'), false, false)
  returning id, matricule into v_id, v_mat;

  return json_build_object('code', v_code, 'matricule', v_mat, 'id', v_id, 'actif', false, 'existant', false);
end $$;
revoke all on function cc_adherer(text,text,text,text,text,text) from public;
grant execute on function cc_adherer(text,text,text,text,text,text) to anon, authenticated;

-- 17) Option C : accès par téléphone ; le n° de carte (matricule) devient facultatif, saisi/modifié par le membre lui-même
-- Suppression (une seule fois) des matricules générés automatiquement à l'import (CC-26-<code>) : ils ne correspondaient à aucune carte.
update cc_membres set matricule = null
 where matricule = 'CC-26-' || lpad(code, 5, '0')
   and not exists (select 1 from cc_settings where cle = 'matricules_generes_effaces');
insert into cc_settings (cle, valeur) values ('matricules_generes_effaces', 'oui') on conflict (cle) do nothing;

-- Le membre (identifié par son téléphone) enregistre ou corrige le numéro de sa carte ; vide = effacer.
create or replace function cc_maj_carte(p_tel text, p_carte text) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_m record; v_mat text;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if trim(coalesce(p_carte,'')) = '' then
    update cc_membres set matricule = null, fiche_maj_le = now() where id = v_m.id;
    return json_build_object('ok', true, 'matricule', null);
  end if;
  v_mat := cc_matricule_normaliser(p_carte);
  if v_mat is null then return json_build_object('ok', false, 'motif', 'format'); end if;
  if exists (select 1 from cc_membres where matricule = v_mat and id <> v_m.id) then return json_build_object('ok', false, 'motif', 'pris'); end if;
  update cc_membres set matricule = v_mat, fiche_maj_le = now() where id = v_m.id;
  return json_build_object('ok', true, 'matricule', v_mat);
end $$;
revoke all on function cc_maj_carte(text,text) from public;
grant execute on function cc_maj_carte(text,text) to anon, authenticated;

-- Accès aux liens d'événement : par n° de carte OU téléphone
create or replace function cc_appel_acces(p_matricule text, p_appel bigint) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_a record; v_paye int; v_tel text := regexp_replace(coalesce(p_matricule,''), '\D', '', 'g');
begin
  if cc_matricule_normaliser(p_matricule) is not null then
    select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  elsif length(v_tel) >= 8 then
    if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
    select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  end if;
  if v_m is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select * into v_a from cc_appels where id = p_appel;
  if not found then return json_build_object('ok', false, 'motif', 'appel'); end if;
  select coalesce(sum(montant),0) into v_paye from cc_paiements where membre_id = v_m.id and appel_id = p_appel and statut = 'RAPPROCHE';
  if v_paye < v_a.montant then return json_build_object('ok', false, 'motif', 'impaye', 'paye', v_paye); end if;
  return json_build_object('ok', true, 'lien', v_a.lien_apres, 'paye', v_paye);
end $$;

-- 18) Nouvelle API CinetPay v1 (clé sk_test_/sk_live_ + mot de passe API) : jetons de notification et identifiant CinetPay
alter table cc_transactions add column if not exists notify_token text;
alter table cc_transactions add column if not exists cinetpay_id text;

-- Journal des relances automatiques (serveur) — lecture trésorier, écriture service uniquement.
create table if not exists cc_relances (
  id bigserial primary key,
  date date not null default current_date,
  type text not null,                      -- appel | rappel | dernier | retard
  membre_id bigint references cc_membres(id) on delete cascade,
  canal text default 'aucun',              -- email | whatsapp | aucun
  statut text default 'a_faire',           -- envoye | erreur | a_faire | fait
  detail text default '',
  reste integer default 0,
  nb_mois integer default 1,
  cree_le timestamptz default now()
);
alter table cc_relances enable row level security;
drop policy if exists "lecture tresorier cc_relances" on cc_relances;
create policy "lecture tresorier cc_relances" on cc_relances for select to authenticated using (cc_est_tresorier());
drop policy if exists "maj tresorier cc_relances" on cc_relances;
create policy "maj tresorier cc_relances" on cc_relances for update to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
create index if not exists cc_relances_date on cc_relances(date, type);

-- Onglet Formation : vidéos, documents, lives, parcours Skool. Les liens réservés ne sont remis qu'aux membres identifiés (et à jour si demandé).
create table if not exists cc_formations (
  id bigserial primary key,
  titre text not null,
  type text default 'video',               -- video | document | live | skool | autre
  description text default '',
  lien text default '',
  date date default current_date,
  acces text default 'membres',            -- public | membres | a_jour
  publie boolean default true,
  cree_le timestamptz default now()
);
alter table cc_formations enable row level security;
drop policy if exists "lecture publique cc_formations" on cc_formations;
create policy "lecture publique cc_formations" on cc_formations for select using (true);
drop policy if exists "ecriture tresorier cc_formations" on cc_formations;
create policy "ecriture tresorier cc_formations" on cc_formations for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
grant select on cc_formations to anon, authenticated;
grant insert, update, delete on cc_formations to authenticated;
grant usage, select on sequence cc_formations_id_seq to authenticated;

-- Anniversaires : date de naissance facultative (renseignée par le membre dans sa fiche), affichage réglé par « anniversaires » dans Paramètres.
alter table cc_membres add column if not exists date_naissance date;
create or replace function cc_maj_fiche(p_tel text, p_matricule text, p_nom text, p_email text, p_ville text, p_specialite text, p_employeur text, p_pays text default null, p_naissance text default null) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_n date;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if cc_matricule_normaliser(p_matricule) is not null then
    select * into v_m from cc_membres where matricule = cc_matricule_normaliser(p_matricule);
  elsif length(v_tel) >= 8 then
    select * into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  end if;
  if v_m is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_nom,''))) < 3 then return json_build_object('ok', false, 'motif', 'nom'); end if;
  begin v_n := nullif(trim(coalesce(p_naissance,'')), '')::date; exception when others then v_n := null; end;
  if v_n is not null and (v_n > current_date or v_n < date '1920-01-01') then v_n := null; end if;
  update cc_membres set nom = left(trim(p_nom), 80), email = left(lower(trim(coalesce(p_email,''))), 120),
    ville = left(trim(coalesce(p_ville,'')), 60), specialite = left(trim(coalesce(p_specialite,'')), 80),
    employeur = left(trim(coalesce(p_employeur,'')), 80), pays = coalesce(nullif(left(trim(p_pays),60),''), pays, 'Côte d’Ivoire'),
    date_naissance = coalesce(v_n, case when p_naissance is null then date_naissance else null end), fiche_maj_le = now()
  where id = v_m.id;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_maj_fiche(text,text,text,text,text,text,text,text,text) from public;
grant execute on function cc_maj_fiche(text,text,text,text,text,text,text,text,text) to anon, authenticated;
drop function if exists cc_maj_fiche(text,text,text,text,text,text,text,text);
drop function if exists cc_maj_fiche(text,text,text,text,text,text,text);

-- Questions / Réponses : un membre identifié pose une question ; un validateur unique (bureau) répond, avec son nom et la date ; seules les réponses validées sont publiées.
create table if not exists cc_questions (
  id bigserial primary key,
  membre_id bigint references cc_membres(id) on delete set null,
  question text not null,
  reponse text default '',
  repondu_par text default '',
  repondu_le timestamptz,
  publie boolean default false,
  anonyme boolean default false,
  cree_le timestamptz default now()
);
alter table cc_questions enable row level security;
drop policy if exists "lecture cc_questions" on cc_questions;
create policy "lecture cc_questions" on cc_questions for select using (publie = true or cc_est_tresorier());
drop policy if exists "ecriture tresorier cc_questions" on cc_questions;
create policy "ecriture tresorier cc_questions" on cc_questions for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
grant select on cc_questions to anon, authenticated;
grant insert, update, delete on cc_questions to authenticated;
grant usage, select on sequence cc_questions_id_seq to authenticated;
create or replace function cc_poser_question(p_tel text, p_question text, p_anonyme boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare v_m record; v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_m from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_m is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_question,''))) < 10 then return json_build_object('ok', false, 'motif', 'courte'); end if;
  if (select count(*) from cc_questions where membre_id = v_m.id and cree_le > now() - interval '1 day') >= 3 then return json_build_object('ok', false, 'motif', 'limite'); end if;
  insert into cc_questions (membre_id, question, anonyme) values (v_m.id, left(trim(p_question), 1000), coalesce(p_anonyme, false));
  return json_build_object('ok', true);
end $$;
revoke all on function cc_poser_question(text,text,boolean) from public;
grant execute on function cc_poser_question(text,text,boolean) to anon, authenticated;

-- Q/R v2 : contributions des membres. Une question (membre identifié) reçoit des réponses d'autres membres ;
-- une réponse est publiée quand au moins N validateurs (Paramètres « qr_validateurs » = téléphones, « qr_validations_min » = 2) l'ont approuvée, chacun avec nom + date.
alter table cc_questions drop column if exists reponse, drop column if exists repondu_par, drop column if exists repondu_le;
alter table cc_questions alter column publie set default true;
update cc_questions set publie = true;
create table if not exists cc_reponses (
  id bigserial primary key,
  question_id bigint not null references cc_questions(id) on delete cascade,
  membre_id bigint references cc_membres(id) on delete set null,
  texte text not null,
  validations jsonb not null default '[]'::jsonb,     -- [{"membre_id":..,"nom":"..","date":".."}]
  publie boolean default false,
  cree_le timestamptz default now()
);
alter table cc_reponses enable row level security;
drop policy if exists "lecture cc_reponses" on cc_reponses;
create policy "lecture cc_reponses" on cc_reponses for select using (publie = true or cc_est_tresorier());
drop policy if exists "ecriture tresorier cc_reponses" on cc_reponses;
create policy "ecriture tresorier cc_reponses" on cc_reponses for all to authenticated using (cc_est_tresorier()) with check (cc_est_tresorier());
grant select on cc_reponses to anon, authenticated;
grant insert, update, delete on cc_reponses to authenticated;
grant usage, select on sequence cc_reponses_id_seq to authenticated;
insert into cc_settings (cle, valeur) values ('qr_validations_min', '2') on conflict (cle) do nothing;
insert into cc_settings (cle, valeur) values ('qr_validateurs', '') on conflict (cle) do nothing;

create or replace function cc_membre_par_tel(p_tel text) returns cc_membres language sql stable security definer set search_path = public as $$
  select * from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (regexp_replace(coalesce(p_tel,''), '\D', '', 'g'),
    case when length(regexp_replace(coalesce(p_tel,''), '\D', '', 'g')) = 13 then substr(regexp_replace(p_tel, '\D', '', 'g'), 4) else '225' || regexp_replace(coalesce(p_tel,''), '\D', '', 'g') end) limit 1;
$$;
create or replace function cc_est_validateur_qr(p_membre cc_membres) returns boolean language sql stable security definer set search_path = public as $$
  select position(regexp_replace(coalesce(p_membre.telephone,''), '\D', '', 'g') in regexp_replace(coalesce((select valeur from cc_settings where cle = 'qr_validateurs'), ''), '\D', ',', 'g')) > 0
     and length(regexp_replace(coalesce(p_membre.telephone,''), '\D', '', 'g')) >= 8;
$$;
create or replace function cc_repondre(p_tel text, p_question_id bigint, p_texte text) returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_texte,''))) < 10 then return json_build_object('ok', false, 'motif', 'courte'); end if;
  if not exists (select 1 from cc_questions where id = p_question_id) then return json_build_object('ok', false, 'motif', 'question'); end if;
  if (select count(*) from cc_reponses where membre_id = v_m.id and cree_le > now() - interval '1 day') >= 10 then return json_build_object('ok', false, 'motif', 'limite'); end if;
  insert into cc_reponses (question_id, membre_id, texte) values (p_question_id, v_m.id, left(trim(p_texte), 3000));
  return json_build_object('ok', true);
end $$;
create or replace function cc_valider_reponse(p_tel text, p_reponse_id bigint, p_decision text default 'valider') returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres; v_r cc_reponses; v_min int := coalesce(nullif((select valeur from cc_settings where cle = 'qr_validations_min'), '')::int, 2); v_val jsonb;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null or not cc_est_validateur_qr(v_m) then return json_build_object('ok', false, 'motif', 'non_validateur'); end if;
  select * into v_r from cc_reponses where id = p_reponse_id;
  if v_r.id is null then return json_build_object('ok', false, 'motif', 'reponse'); end if;
  if p_decision = 'refuser' then delete from cc_reponses where id = p_reponse_id; return json_build_object('ok', true, 'supprimee', true); end if;
  if v_r.membre_id = v_m.id then return json_build_object('ok', false, 'motif', 'propre_reponse'); end if;
  if exists (select 1 from jsonb_array_elements(v_r.validations) e where (e->>'membre_id')::bigint = v_m.id) then return json_build_object('ok', false, 'motif', 'deja'); end if;
  v_val := v_r.validations || jsonb_build_object('membre_id', v_m.id, 'nom', v_m.nom, 'date', to_char(now(), 'YYYY-MM-DD'));
  update cc_reponses set validations = v_val, publie = (jsonb_array_length(v_val) >= v_min) where id = p_reponse_id;
  return json_build_object('ok', true, 'nb', jsonb_array_length(v_val), 'publiee', jsonb_array_length(v_val) >= v_min);
end $$;
create or replace function cc_reponses_a_valider(p_tel text) returns setof cc_reponses
language sql stable security definer set search_path = public as $$
  select r.* from cc_reponses r where not r.publie and cc_est_validateur_qr(cc_membre_par_tel(p_tel)) order by r.id;
$$;
create or replace function cc_mes_reponses(p_tel text) returns setof cc_reponses
language sql stable security definer set search_path = public as $$
  select r.* from cc_reponses r where not r.publie and r.membre_id = (cc_membre_par_tel(p_tel)).id order by r.id;
$$;
revoke all on function cc_repondre(text,bigint,text), cc_valider_reponse(text,bigint,text), cc_reponses_a_valider(text), cc_mes_reponses(text) from public;
grant execute on function cc_repondre(text,bigint,text), cc_valider_reponse(text,bigint,text), cc_reponses_a_valider(text), cc_mes_reponses(text) to anon, authenticated;
revoke all on function cc_membre_par_tel(text), cc_est_validateur_qr(cc_membres) from public;

-- Q/R v3 : base de connaissances + animation. Question et réponse postées ensemble possibles ; mots-clés ; 1 validation par défaut.
alter table cc_questions add column if not exists tags text default '';
update cc_settings set valeur = '1' where cle = 'qr_validations_min' and valeur = '2';
insert into cc_settings (cle, valeur) values ('palmares', 'oui'), ('palmares_prime', ''),
  ('pts_reponse', '5'), ('pts_question', '2'), ('pts_validation', '1'), ('pts_paiement_mois', '3'), ('pts_paiement_avance', '4'), ('pts_fiche', '2')
  on conflict (cle) do nothing;
create or replace function cc_poser_question(p_tel text, p_question text, p_anonyme boolean default false, p_reponse text default null, p_tags text default null) returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres; v_id bigint;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_question,''))) < 10 then return json_build_object('ok', false, 'motif', 'courte'); end if;
  if (select count(*) from cc_questions where membre_id = v_m.id and cree_le > now() - interval '1 day') >= 5 then return json_build_object('ok', false, 'motif', 'limite'); end if;
  insert into cc_questions (membre_id, question, anonyme, tags) values (v_m.id, left(trim(p_question), 1000), coalesce(p_anonyme, false), left(lower(trim(coalesce(p_tags,''))), 200)) returning id into v_id;
  if length(trim(coalesce(p_reponse,''))) >= 10 then insert into cc_reponses (question_id, membre_id, texte) values (v_id, v_m.id, left(trim(p_reponse), 3000)); end if;
  return json_build_object('ok', true, 'id', v_id);
end $$;
drop function if exists cc_poser_question(text, text, boolean);
revoke all on function cc_poser_question(text,text,boolean,text,text) from public;
grant execute on function cc_poser_question(text,text,boolean,text,text) to anon, authenticated;

-- Anti-doublons : similarité de texte (pg_trgm). Une question trop proche d'une existante est refusée (motif « doublon » + id), sauf si le membre confirme (p_forcer).
create extension if not exists pg_trgm;
create or replace function unaccent_lite(t text) returns text language sql immutable as $$
  select translate(coalesce(t,''), 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ’''', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC  ');
$$;
create or replace function cc_question_normaliser(t text) returns text language sql immutable as $$
  select regexp_replace(lower(unaccent_lite(t)), '[^a-z0-9 ]+', ' ', 'g');
$$;
create or replace function cc_questions_similaires(p_texte text, p_limite int default 5) returns table(id bigint, question text, similarite real)
language sql stable security definer set search_path = public as $$
  select q.id, q.question, similarity(cc_question_normaliser(q.question), cc_question_normaliser(p_texte)) as similarite
  from cc_questions q
  where length(coalesce(p_texte,'')) >= 10 and similarity(cc_question_normaliser(q.question), cc_question_normaliser(p_texte)) > 0.25
  order by 3 desc limit p_limite;
$$;
grant execute on function cc_questions_similaires(text,int) to anon, authenticated;
create or replace function cc_poser_question(p_tel text, p_question text, p_anonyme boolean default false, p_reponse text default null, p_tags text default null, p_forcer boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres; v_id bigint; v_d record;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  if length(trim(coalesce(p_question,''))) < 10 then return json_build_object('ok', false, 'motif', 'courte'); end if;
  if (select count(*) from cc_questions where membre_id = v_m.id and cree_le > now() - interval '1 day') >= 5 then return json_build_object('ok', false, 'motif', 'limite'); end if;
  select * into v_d from cc_questions_similaires(p_question, 1) where similarite >= 0.6;
  if v_d.id is not null and not coalesce(p_forcer, false) then return json_build_object('ok', false, 'motif', 'doublon', 'id', v_d.id, 'question', v_d.question); end if;
  if v_d.id is not null and v_d.similarite >= 0.9 then return json_build_object('ok', false, 'motif', 'identique', 'id', v_d.id, 'question', v_d.question); end if;
  insert into cc_questions (membre_id, question, anonyme, tags) values (v_m.id, left(trim(p_question), 1000), coalesce(p_anonyme, false), left(lower(trim(coalesce(p_tags,''))), 200)) returning id into v_id;
  if length(trim(coalesce(p_reponse,''))) >= 10 then insert into cc_reponses (question_id, membre_id, texte) values (v_id, v_m.id, left(trim(p_reponse), 3000)); end if;
  return json_build_object('ok', true, 'id', v_id);
end $$;
drop function if exists cc_poser_question(text, text, boolean, text, text);
revoke all on function cc_poser_question(text,text,boolean,text,text,boolean) from public;
grant execute on function cc_poser_question(text,text,boolean,text,text,boolean) to anon, authenticated;

-- ====================================================================================
-- Animation de la communauté : parrainage, sondages, défi du mois, membre à l'honneur, certificats
-- (toutes ces fonctions sont paramétrables depuis Paramètres → « Animation de la communauté »)
-- ====================================================================================
alter table cc_membres add column if not exists parrain_id bigint references cc_membres(id) on delete set null;

insert into cc_settings (cle, valeur) values
  ('defi','oui'), ('defi_objectif','80'), ('defi_jour','25'), ('defi_texte',''),
  ('honneur','oui'), ('honneur_membre_id',''), ('honneur_texte',''),
  ('sondages','oui'), ('certificats','oui'), ('parrainage','oui'), ('pts_parrainage','10')
on conflict (cle) do nothing;

-- Adhésion avec parrain (téléphone d'un membre actif ; ignoré s'il est inconnu ou s'il s'agit du nouveau membre lui-même)
drop function if exists cc_adherer(text,text,text,text,text,text);
create or replace function cc_adherer(p_nom text, p_tel text, p_ville text default '', p_email text default '', p_specialite text default '', p_pays text default '', p_parrain_tel text default '')
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  v_ptel text := regexp_replace(coalesce(p_parrain_tel,''), '\D', '', 'g');
  v_code text; v_id bigint; v_mat text; v_parrain bigint; v_existant record;
begin
  if length(trim(coalesce(p_nom,''))) < 3 then raise exception 'Nom trop court'; end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_ptel) = 13 and v_ptel like '225%' then v_ptel := substr(v_ptel, 4); end if;

  select id, code, matricule, actif into v_existant from cc_membres
    where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if found then
    return json_build_object('code', v_existant.code, 'matricule', v_existant.matricule, 'id', v_existant.id, 'actif', v_existant.actif, 'existant', true);
  end if;
  if length(v_ptel) >= 8 and v_ptel <> v_tel and coalesce((select valeur from cc_settings where cle='parrainage'),'oui') <> 'non' then
    select id into v_parrain from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_ptel, '225' || v_ptel) limit 1;
  end if;

  select lpad((coalesce(max(code::int), 0) + 1)::text, 3, '0') into v_code from cc_membres where code ~ '^\d+$';
  insert into cc_membres (code, nom, telephone, ville, specialite, email, pays, cotisation, date_adhesion, actif, exonere, parrain_id)
  values (v_code, trim(p_nom), v_tel, coalesce(p_ville,''), coalesce(p_specialite,''), coalesce(p_email,''),
          coalesce(nullif(left(trim(p_pays),60),''), 'Côte d’Ivoire'),
          coalesce((select valeur::int from cc_settings where cle='cotisation'), 5000),
          to_char(current_date, 'YYYY-MM-DD'), false, false, v_parrain)
  returning id, matricule into v_id, v_mat;
  return json_build_object('code', v_code, 'matricule', v_mat, 'id', v_id, 'actif', false, 'existant', false, 'parrain', v_parrain is not null);
end $$;
revoke all on function cc_adherer(text,text,text,text,text,text,text) from public;
grant execute on function cc_adherer(text,text,text,text,text,text,text) to anon, authenticated;

-- Sondages rapides du bureau : une question, 2 à 6 choix, un vote par membre (identifié par téléphone)
create table if not exists cc_sondages (
  id bigserial primary key,
  question text not null,
  options text[] not null,
  ouvert boolean not null default true,
  cree_le timestamptz not null default now(),
  clos_le timestamptz
);
create table if not exists cc_votes (
  id bigserial primary key,
  sondage_id bigint not null references cc_sondages(id) on delete cascade,
  membre_id bigint not null references cc_membres(id) on delete cascade,
  choix int not null,
  date timestamptz not null default now(),
  unique (sondage_id, membre_id)
);
alter table cc_sondages enable row level security; alter table cc_votes enable row level security;
drop policy if exists "lecture publique cc_sondages" on cc_sondages;
create policy "lecture publique cc_sondages" on cc_sondages for select using (true);
drop policy if exists "ecriture tresorier cc_sondages" on cc_sondages;
create policy "ecriture tresorier cc_sondages" on cc_sondages for all to authenticated using (true) with check (true);
drop policy if exists "lecture publique cc_votes" on cc_votes;
create policy "lecture publique cc_votes" on cc_votes for select using (true);
grant select on cc_sondages, cc_votes to anon, authenticated;
grant insert, update, delete on cc_sondages to authenticated;
grant delete on cc_votes to authenticated;
grant usage, select on sequence cc_sondages_id_seq, cc_votes_id_seq to authenticated;
grant all on cc_sondages, cc_votes to service_role;

create or replace function cc_voter(p_tel text, p_sondage_id bigint, p_choix int) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_m record; v_s record;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_m from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select * into v_s from cc_sondages where id = p_sondage_id;
  if not found or not v_s.ouvert then return json_build_object('ok', false, 'motif', 'clos'); end if;
  if p_choix < 0 or p_choix >= array_length(v_s.options, 1) then return json_build_object('ok', false, 'motif', 'choix'); end if;
  insert into cc_votes (sondage_id, membre_id, choix) values (p_sondage_id, v_m.id, p_choix)
    on conflict (sondage_id, membre_id) do update set choix = excluded.choix, date = now();
  return json_build_object('ok', true);
end $$;
revoke all on function cc_voter(text,bigint,int) from public;
grant execute on function cc_voter(text,bigint,int) to anon, authenticated;

-- Fusion de doublons (trésorier) : les réponses du doublon sont rattachées à la question d'origine,
-- le texte du doublon est conservé en « variante » (pour la recherche), son auteur en co-auteur (garde ses points), puis le doublon est supprimé.
alter table cc_questions add column if not exists variantes text[] not null default '{}';
alter table cc_questions add column if not exists co_auteurs bigint[] not null default '{}';
create or replace function cc_fusionner_questions(p_doublon bigint, p_cible bigint) returns json
language plpgsql security definer set search_path = public as $$
declare v_d record; v_c record;
begin
  if not cc_est_tresorier() then raise exception 'Réservé au trésorier'; end if;
  if p_doublon = p_cible then return json_build_object('ok', false, 'motif', 'identique'); end if;
  select * into v_d from cc_questions where id = p_doublon; if not found then return json_build_object('ok', false, 'motif', 'doublon_inconnu'); end if;
  select * into v_c from cc_questions where id = p_cible;   if not found then return json_build_object('ok', false, 'motif', 'cible_inconnue'); end if;
  update cc_reponses set question_id = p_cible where question_id = p_doublon;
  update cc_questions set
    variantes = array_cat(variantes, array[v_d.question] || v_d.variantes),
    co_auteurs = (select array_agg(distinct x) from unnest(co_auteurs || v_d.co_auteurs || array[v_d.membre_id]) x where x is not null and x <> coalesce(membre_id, -1)),
    tags = trim(both ', ' from coalesce(tags,'') || case when coalesce(v_d.tags,'') <> '' then ', ' || v_d.tags else '' end)
    where id = p_cible;
  delete from cc_questions where id = p_doublon;
  return json_build_object('ok', true, 'cible', p_cible, 'reponses_deplacees', (select count(*) from cc_reponses where question_id = p_cible));
end $$;
revoke all on function cc_fusionner_questions(bigint,bigint) from public;
grant execute on function cc_fusionner_questions(bigint,bigint) to authenticated;

-- ====================================================================================
-- Professionnalisation : cotisation en nature, reçus numérotés, journal d'audit, annuaire opt-in, consentement
-- ====================================================================================
alter table cc_membres add column if not exists cotisation_nature text default '';        -- description de l'apport en nature (vide = cotisation normale)
alter table cc_membres add column if not exists nature_montant int default 0;             -- valeur annuelle estimée (révisable chaque décembre par le bureau)
alter table cc_membres add column if not exists nature_revise_le date;                    -- dernière révision par le bureau
alter table cc_membres add column if not exists annuaire boolean default false;           -- apparaît dans l'annuaire professionnel (choix du membre)
alter table cc_membres add column if not exists consentement_le timestamptz;              -- acceptation charte + politique de confidentialité
alter table cc_paiements add column if not exists recu_numero text;                       -- reçu n° RC-AAAA-NNNNN, attribué automatiquement
insert into cc_settings (cle, valeur) values ('nature_revision_mois','12'), ('annuaire','oui'), ('audit','oui') on conflict (cle) do nothing;

-- Numérotation des reçus : séquence annuelle, jamais de trou, jamais de doublon
create table if not exists cc_compteurs (cle text primary key, valeur bigint not null default 0);
grant select on cc_compteurs to anon, authenticated; grant all on cc_compteurs to service_role;
create or replace function cc_recu_numeroter() returns trigger language plpgsql security definer set search_path = public as $$
declare v_an text := to_char(coalesce(new.date::date, current_date), 'YYYY'); v_n bigint;
begin
  if new.recu_numero is null or new.recu_numero = '' then
    insert into cc_compteurs (cle, valeur) values ('recu_'||v_an, 1) on conflict (cle) do update set valeur = cc_compteurs.valeur + 1 returning valeur into v_n;
    new.recu_numero := 'RC-'||v_an||'-'||lpad(v_n::text, 5, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_recu_numero on cc_paiements;
create trigger trg_recu_numero before insert on cc_paiements for each row execute function cc_recu_numeroter();
-- Paiements existants : numérotés dans l’ordre chronologique (une seule fois)
with n as (select id, 'RC-'||to_char(date::date,'YYYY')||'-'||lpad((row_number() over (partition by to_char(date::date,'YYYY') order by date, id))::text,5,'0') as num
           from cc_paiements where recu_numero is null)
update cc_paiements p set recu_numero = n.num from n where p.id = n.id;
insert into cc_compteurs (cle, valeur)
  select 'recu_'||to_char(date::date,'YYYY'), count(*) from cc_paiements group by 1
  on conflict (cle) do update set valeur = greatest(cc_compteurs.valeur, excluded.valeur);

-- Journal d'audit : qui a modifié quoi (trésorier connecté, fonction serveur, membre via son téléphone)
create table if not exists cc_audit (
  id bigserial primary key,
  date timestamptz not null default now(),
  utilisateur text,                 -- e-mail du compte connecté, ou 'serveur' / 'membre' / 'anonyme'
  action text not null,             -- INSERT / UPDATE / DELETE / FUSION…
  tbl text not null,
  ligne_id text,
  avant jsonb,
  apres jsonb
);
create index if not exists cc_audit_date on cc_audit(date desc);
alter table cc_audit enable row level security;
drop policy if exists "lecture tresorier cc_audit" on cc_audit;
create policy "lecture tresorier cc_audit" on cc_audit for select to authenticated using (true);
grant select on cc_audit to authenticated; grant all on cc_audit to service_role;
create or replace function cc_audit_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare v_user text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email', nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', 'serveur');
        v_id text; v_avant jsonb; v_apres jsonb;
begin
  if tg_op = 'DELETE' then v_avant := to_jsonb(old); v_id := coalesce(v_avant->>'id', v_avant->>'email');
  elsif tg_op = 'INSERT' then v_apres := to_jsonb(new); v_id := coalesce(v_apres->>'id', v_apres->>'email');
  else v_avant := to_jsonb(old); v_apres := to_jsonb(new); v_id := coalesce(v_apres->>'id', v_apres->>'email');
    if v_avant - 'fiche_maj_le' = v_apres - 'fiche_maj_le' then return new; end if;   -- rien de significatif
  end if;
  if tg_table_name = 'cc_membres' then v_avant := v_avant - 'photo_url'; v_apres := v_apres - 'photo_url'; end if;
  insert into cc_audit (utilisateur, action, tbl, ligne_id, avant, apres) values (v_user, tg_op, tg_table_name, v_id, v_avant, v_apres);
  return coalesce(new, old);
end $$;
do $$ declare t text; begin
  foreach t in array array['cc_paiements','cc_membres','cc_depenses','cc_settings','cc_questions','cc_reponses','cc_appels','cc_roles','cc_bureau'] loop
    execute format('drop trigger if exists trg_audit on %I', t);
    execute format('create trigger trg_audit after insert or update or delete on %I for each row execute function cc_audit_trg()', t);
  end loop;
end $$;
-- cc_settings n'a pas de colonne id : trigger dédié
create or replace function cc_audit_settings_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare v_user text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email', 'serveur');
begin
  if tg_op = 'UPDATE' and old.valeur is not distinct from new.valeur then return new; end if;
  insert into cc_audit (utilisateur, action, tbl, ligne_id, avant, apres) values (v_user, tg_op, 'cc_settings', coalesce(new.cle, old.cle),
    case when tg_op <> 'INSERT' then jsonb_build_object('valeur', old.valeur) end, case when tg_op <> 'DELETE' then jsonb_build_object('valeur', new.valeur) end);
  return coalesce(new, old);
end $$;
drop trigger if exists trg_audit on cc_settings;
create trigger trg_audit after insert or update or delete on cc_settings for each row execute function cc_audit_settings_trg();

-- Le membre choisit lui-même d'apparaître dans l'annuaire ; enregistre son consentement
create or replace function cc_annuaire_opt(p_tel text, p_oui boolean) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_id bigint;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_id from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_id is null then return json_build_object('ok', false); end if;
  update cc_membres set annuaire = p_oui, consentement_le = coalesce(consentement_le, now()) where id = v_id;
  return json_build_object('ok', true, 'annuaire', p_oui);
end $$;
revoke all on function cc_annuaire_opt(text,boolean) from public;
grant execute on function cc_annuaire_opt(text,boolean) to anon, authenticated;

-- Adhésion : horodatage du consentement (charte + confidentialité) — même signature, consentement systématique
create or replace function cc_adherer(p_nom text, p_tel text, p_ville text default '', p_email text default '', p_specialite text default '', p_pays text default '', p_parrain_tel text default '')
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  v_ptel text := regexp_replace(coalesce(p_parrain_tel,''), '\D', '', 'g');
  v_code text; v_id bigint; v_mat text; v_parrain bigint; v_existant record;
begin
  if length(trim(coalesce(p_nom,''))) < 3 then raise exception 'Nom trop court'; end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_ptel) = 13 and v_ptel like '225%' then v_ptel := substr(v_ptel, 4); end if;
  select id, code, matricule, actif into v_existant from cc_membres
    where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if found then
    return json_build_object('code', v_existant.code, 'matricule', v_existant.matricule, 'id', v_existant.id, 'actif', v_existant.actif, 'existant', true);
  end if;
  if length(v_ptel) >= 8 and v_ptel <> v_tel and coalesce((select valeur from cc_settings where cle='parrainage'),'oui') <> 'non' then
    select id into v_parrain from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_ptel, '225' || v_ptel) limit 1;
  end if;
  select lpad((coalesce(max(code::int), 0) + 1)::text, 3, '0') into v_code from cc_membres where code ~ '^\d+$';
  insert into cc_membres (code, nom, telephone, ville, specialite, email, pays, cotisation, date_adhesion, actif, exonere, parrain_id, consentement_le)
  values (v_code, trim(p_nom), v_tel, coalesce(p_ville,''), coalesce(p_specialite,''), coalesce(p_email,''),
          coalesce(nullif(left(trim(p_pays),60),''), 'Côte d’Ivoire'),
          coalesce((select valeur::int from cc_settings where cle='cotisation'), 5000),
          to_char(current_date, 'YYYY-MM-DD'), false, false, v_parrain, now())
  returning id, matricule into v_id, v_mat;
  return json_build_object('code', v_code, 'matricule', v_mat, 'id', v_id, 'actif', false, 'existant', false, 'parrain', v_parrain is not null);
end $$;

-- Nabil : cotisation en nature (hébergement, domaine, maintenance), 5 700 F/an révisable — décision du bureau
update cc_membres set exonere = true,
  cotisation_nature = 'Hébergement du serveur, nom de domaine et maintenance de la plateforme',
  nature_montant = 5700, nature_revise_le = current_date
  where telephone in ('0502657392','2250502657392') and coalesce(cotisation_nature,'') = '';

-- Cotisation en nature : date de début (avant = cotisation normale) et exceptions par année sur le complément annuel
alter table cc_membres add column if not exists nature_depuis date;
alter table cc_membres add column if not exists nature_exceptions jsonb not null default '{}'::jsonb;
-- Nabil : espèces jusqu'en août 2026, en nature depuis septembre 2026 ; complément 4 420 F en déc. 2026, puis 5 700 F/an
update cc_membres set exonere = false, nature_depuis = '2026-09-01', nature_montant = 5700, nature_exceptions = '{"2026": 4420}'::jsonb
  where id = 89 and coalesce(cotisation_nature,'') <> '';

-- ====================================================================================
-- Vague 2 : révision annuelle des contributions, agenda des événements, réglages PWA/vitrine
-- ====================================================================================
insert into cc_settings (cle, valeur) values ('qr_revision','oui'), ('pts_revision','2'), ('agenda','oui'), ('temoignages','') on conflict (cle) do nothing;

-- Révision annuelle : chaque réponse publiée porte l'année pour laquelle elle a été vérifiée.
-- Dès l'année suivante elle est « à revérifier » ; N'IMPORTE QUEL membre peut la confirmer (points) ou proposer une mise à jour (nouvelle réponse → validateur).
alter table cc_reponses add column if not exists verifiee_annee int;
alter table cc_reponses add column if not exists revisions jsonb not null default '[]'::jsonb;   -- [{"membre_id","nom","date","annee"}]
update cc_reponses set verifiee_annee = extract(year from coalesce(cree_le, now()))::int where verifiee_annee is null;
create or replace function cc_confirmer_reponse(p_tel text, p_reponse_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres; v_r cc_reponses; v_an int := extract(year from now())::int;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null or not v_m.actif then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select * into v_r from cc_reponses where id = p_reponse_id and publie;
  if not found then return json_build_object('ok', false, 'motif', 'reponse'); end if;
  if coalesce(v_r.verifiee_annee, 0) >= v_an then return json_build_object('ok', false, 'motif', 'deja'); end if;
  update cc_reponses set verifiee_annee = v_an,
    revisions = revisions || jsonb_build_object('membre_id', v_m.id, 'nom', v_m.nom, 'date', to_char(now(), 'YYYY-MM-DD'), 'annee', v_an)
    where id = p_reponse_id;
  return json_build_object('ok', true, 'annee', v_an);
end $$;
revoke all on function cc_confirmer_reponse(text,bigint) from public;
grant execute on function cc_confirmer_reponse(text,bigint) to anon, authenticated;
-- Une réponse nouvellement validée est vérifiée pour l'année en cours
create or replace function cc_reponse_publiee_annee() returns trigger language plpgsql as $$
begin if new.publie and (old.publie is distinct from true) then new.verifiee_annee := extract(year from now())::int; end if; return new; end $$;
drop trigger if exists trg_reponse_annee on cc_reponses;
create trigger trg_reponse_annee before update on cc_reponses for each row execute function cc_reponse_publiee_annee();

-- Agenda : événements à venir (inscription des membres, rappel la veille) et comptes rendus après coup
create table if not exists cc_evenements (
  id bigserial primary key,
  titre text not null,
  date date not null,
  heure text default '',
  lieu text default '',
  description text default '',
  lien text default '',                 -- visio / formulaire / plan
  inscription boolean not null default true,
  places int default 0,                 -- 0 = illimité
  publie boolean not null default true,
  compte_rendu text default '',
  rencontre_id bigint references cc_rencontres(id) on delete set null,   -- galerie photos associée
  cree_le timestamptz not null default now()
);
create table if not exists cc_evenement_inscrits (
  id bigserial primary key,
  evenement_id bigint not null references cc_evenements(id) on delete cascade,
  membre_id bigint not null references cc_membres(id) on delete cascade,
  date timestamptz not null default now(),
  present boolean,
  unique (evenement_id, membre_id)
);
alter table cc_evenements enable row level security; alter table cc_evenement_inscrits enable row level security;
drop policy if exists "lecture publique cc_evenements" on cc_evenements;
create policy "lecture publique cc_evenements" on cc_evenements for select using (publie or cc_est_tresorier());
drop policy if exists "ecriture tresorier cc_evenements" on cc_evenements;
create policy "ecriture tresorier cc_evenements" on cc_evenements for all to authenticated using (true) with check (true);
drop policy if exists "lecture publique cc_evenement_inscrits" on cc_evenement_inscrits;
create policy "lecture publique cc_evenement_inscrits" on cc_evenement_inscrits for select using (true);
drop policy if exists "ecriture tresorier cc_evenement_inscrits" on cc_evenement_inscrits;
create policy "ecriture tresorier cc_evenement_inscrits" on cc_evenement_inscrits for all to authenticated using (true) with check (true);
grant select on cc_evenements, cc_evenement_inscrits to anon, authenticated;
grant insert, update, delete on cc_evenements, cc_evenement_inscrits to authenticated;
grant usage, select on sequence cc_evenements_id_seq, cc_evenement_inscrits_id_seq to authenticated;
grant all on cc_evenements, cc_evenement_inscrits to service_role;
create or replace function cc_inscrire_evenement(p_tel text, p_evenement_id bigint, p_oui boolean default true) returns json
language plpgsql security definer set search_path = public as $$
declare v_m cc_membres; v_e cc_evenements; v_n int;
begin
  v_m := cc_membre_par_tel(p_tel);
  if v_m.id is null or not v_m.actif then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select * into v_e from cc_evenements where id = p_evenement_id and publie;
  if not found or not v_e.inscription then return json_build_object('ok', false, 'motif', 'ferme'); end if;
  if v_e.date < current_date then return json_build_object('ok', false, 'motif', 'passe'); end if;
  if not p_oui then delete from cc_evenement_inscrits where evenement_id = p_evenement_id and membre_id = v_m.id; return json_build_object('ok', true, 'inscrit', false); end if;
  select count(*) into v_n from cc_evenement_inscrits where evenement_id = p_evenement_id;
  if v_e.places > 0 and v_n >= v_e.places and not exists (select 1 from cc_evenement_inscrits where evenement_id = p_evenement_id and membre_id = v_m.id) then return json_build_object('ok', false, 'motif', 'complet'); end if;
  insert into cc_evenement_inscrits (evenement_id, membre_id) values (p_evenement_id, v_m.id) on conflict do nothing;
  return json_build_object('ok', true, 'inscrit', true);
end $$;
revoke all on function cc_inscrire_evenement(text,bigint,boolean) from public;
grant execute on function cc_inscrire_evenement(text,bigint,boolean) to anon, authenticated;

-- ============================================================
-- Vague communication (Brevo) : codes de connexion à usage unique
-- ============================================================
create table if not exists cc_otp (
  id bigserial primary key,
  email text not null,
  hache text not null,
  essais int not null default 0,
  utilise boolean not null default false,
  expire_le timestamptz not null,
  cree_le timestamptz not null default now()
);
alter table cc_otp enable row level security;   -- aucune politique : seul le service (serveur) y accède
create index if not exists cc_otp_email_idx on cc_otp(email, cree_le desc);
-- Retrouve un compte de connexion par e-mail (réservé au service)
create or replace function cc_compte_par_email(p_email text)
returns table(id uuid, email text) language sql security definer set search_path = public, auth as $$
  select u.id, u.email::text from auth.users u where lower(u.email) = lower(p_email) and coalesce(u.banned_until, now() - interval '1 second') < now() limit 1
$$;
revoke all on function cc_compte_par_email(text) from public, anon, authenticated;
grant execute on function cc_compte_par_email(text) to service_role;
