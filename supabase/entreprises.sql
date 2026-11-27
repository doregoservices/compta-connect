-- ============================================================================
-- Entreprises : dépôt d'offres (emploi, stage, mission) ouvert à toutes, accès aux annuaires sans coordonnées,
-- coordonnées contre abonnement annuel ou à l'unité (crédits). Accès sans mot de passe : téléphone + code.
-- Annuaire des stagiaires « vivant » : confirmation mensuelle « toujours en recherche ? ».
-- ============================================================================
create table if not exists cc_entreprises (
  id             bigserial primary key,
  nom            text not null,
  secteur        text not null default '',
  ville          text not null default '',
  pays           text not null default '',
  contact_nom    text not null default '',
  telephone      text not null unique,                      -- identifiant de connexion
  email          text not null default '',
  code           text not null,                             -- code d'accès (6 caractères)
  abonne_jusqu   date,                                      -- abonnement annuel actif tant que >= aujourd'hui
  credits        integer not null default 0,                -- contacts achetés à l'unité
  publie         boolean not null default true,
  cree_le        timestamptz not null default now(),
  maj_le         timestamptz not null default now()
);
alter table cc_entreprises enable row level security;
drop policy if exists "tresorier cc_entreprises" on cc_entreprises;
create policy "tresorier cc_entreprises" on cc_entreprises for all to authenticated using (true) with check (true);
grant all on cc_entreprises to authenticated; grant usage, select on sequence cc_entreprises_id_seq to authenticated;
revoke all on cc_entreprises from anon;

create table if not exists cc_offres (
  id             bigserial primary key,
  entreprise_id  bigint not null references cc_entreprises(id) on delete cascade,
  type           text not null default 'emploi',            -- emploi | stage | mission
  titre          text not null,
  description    text not null default '',
  ville          text not null default '',
  contrat        text not null default '',                  -- CDI, CDD, stage 3 mois, mission 2 semaines…
  remuneration   text not null default '',
  date_limite    date,
  comment_postuler text not null default '',                -- e-mail / WhatsApp / lien indiqué par l'entreprise
  valide         boolean not null default false,            -- entreprises abonnées : validée d'office ; autres : validation bureau
  publie         boolean not null default true,
  candidatures   integer not null default 0,                -- clics « Postuler »
  cree_le        timestamptz not null default now(),
  maj_le         timestamptz not null default now()
);
alter table cc_offres enable row level security;
drop policy if exists "tresorier cc_offres" on cc_offres;
create policy "tresorier cc_offres" on cc_offres for all to authenticated using (true) with check (true);
grant all on cc_offres to authenticated; grant usage, select on sequence cc_offres_id_seq to authenticated;
revoke all on cc_offres from anon;

create table if not exists cc_entreprises_contacts (
  id bigserial primary key,
  entreprise_id bigint references cc_entreprises(id) on delete cascade,
  cible text not null,                                      -- stagiaire | membre
  cible_id bigint not null,
  mode text not null,                                       -- abonnement | credit
  quand timestamptz not null default now()
);
alter table cc_entreprises_contacts enable row level security;
drop policy if exists "tresorier cc_entreprises_contacts" on cc_entreprises_contacts;
create policy "tresorier cc_entreprises_contacts" on cc_entreprises_contacts for select to authenticated using (true);
grant select on cc_entreprises_contacts to authenticated; revoke all on cc_entreprises_contacts from anon;

alter table cc_transactions add column if not exists entreprise_id bigint references cc_entreprises(id) on delete set null;
alter table cc_transactions add column if not exists objet text not null default '';

-- Vues publiques
drop view if exists cc_entreprises_public;
create view cc_entreprises_public as
  select e.id, e.nom, e.secteur, e.ville, e.pays, (e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire, e.cree_le
  from cc_entreprises e where e.publie;
grant select on cc_entreprises_public to anon, authenticated;

drop view if exists cc_offres_public;
create view cc_offres_public as
  select o.id, o.entreprise_id, e.nom as entreprise, e.secteur, (e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire,
         o.type, o.titre, o.description, o.ville, o.contrat, o.remuneration, o.date_limite, o.comment_postuler, o.candidatures, o.cree_le
  from cc_offres o join cc_entreprises e on e.id = o.entreprise_id
  where o.publie and o.valide and e.publie and (o.date_limite is null or o.date_limite >= current_date);
grant select on cc_offres_public to anon, authenticated;

create or replace function cc_entreprise_abonnee(p_id bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from cc_entreprises where id = p_id and abonne_jusqu is not null and abonne_jusqu >= current_date);
$$;
revoke all on function cc_entreprise_abonnee(bigint) from public;

-- Inscription / mise à jour d'une entreprise : renvoie le code d'accès (nouveau) ou confirme (existant : le code n'est pas renvoyé)
create or replace function cc_entreprise_enregistrer(p_tel text, p_fiche json)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_e record; v_code text; v_nom text := trim(coalesce(p_fiche->>'nom',''));
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_nom) < 2 then raise exception 'Nom de l''entreprise trop court'; end if;
  select * into v_e from cc_entreprises where telephone = v_tel;
  if found then
    return json_build_object('ok', true, 'id', v_e.id, 'existant', true);
  end if;
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into cc_entreprises (nom, secteur, ville, pays, contact_nom, telephone, email, code)
  values (v_nom, coalesce(p_fiche->>'secteur',''), coalesce(p_fiche->>'ville',''), coalesce(p_fiche->>'pays',''), coalesce(p_fiche->>'contact_nom',''), v_tel, coalesce(p_fiche->>'email',''), v_code)
  returning * into v_e;
  return json_build_object('ok', true, 'id', v_e.id, 'code', v_code, 'existant', false);
end $$;
revoke all on function cc_entreprise_enregistrer(text, json) from public;
grant execute on function cc_entreprise_enregistrer(text, json) to anon, authenticated;

-- Espace entreprise : téléphone + code
create or replace function cc_entreprise_acces(p_tel text, p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_e record; v_offres json; v_tarif int; v_ctarif int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_e from cc_entreprises where telephone = v_tel and code = upper(trim(coalesce(p_code,''))) and publie;
  if not found then
    perform pg_sleep(0.5);   -- freine les essais de codes
    return json_build_object('ok', false);
  end if;
  select coalesce(json_agg(row_to_json(o) order by o.id desc), '[]'::json) into v_offres from cc_offres o where o.entreprise_id = v_e.id;
  v_tarif := coalesce(nullif((select valeur from cc_settings where cle='entreprises_tarif'), '')::int, 150000);
  v_ctarif := coalesce(nullif((select valeur from cc_settings where cle='entreprises_contact_tarif'), '')::int, 5000);
  return json_build_object('ok', true, 'entreprise', json_build_object('id', v_e.id, 'nom', v_e.nom, 'secteur', v_e.secteur, 'ville', v_e.ville, 'pays', v_e.pays,
      'contact_nom', v_e.contact_nom, 'email', v_e.email, 'abonne_jusqu', v_e.abonne_jusqu, 'abonnee', cc_entreprise_abonnee(v_e.id), 'credits', v_e.credits),
    'offres', v_offres, 'tarif_abonnement', v_tarif, 'tarif_contact', v_ctarif,
    'contacts', (select coalesce(json_agg(json_build_object('cible', c.cible, 'cible_id', c.cible_id)), '[]'::json) from cc_entreprises_contacts c where c.entreprise_id = v_e.id));
end $$;
revoke all on function cc_entreprise_acces(text, text) from public;
grant execute on function cc_entreprise_acces(text, text) to anon, authenticated;

-- Dépôt d'une offre (abonnée : publiée d'office ; sinon validation par le bureau)
create or replace function cc_offre_deposer(p_tel text, p_code text, p_offre json)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_e record; v_id bigint; v_type text := coalesce(p_offre->>'type','emploi'); v_ab boolean;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_e from cc_entreprises where telephone = v_tel and code = upper(trim(coalesce(p_code,''))) and publie;
  if not found then return json_build_object('ok', false, 'motif', 'acces'); end if;
  if length(trim(coalesce(p_offre->>'titre',''))) < 5 then raise exception 'Titre trop court'; end if;
  if v_type not in ('emploi','stage','mission') then v_type := 'emploi'; end if;
  if (select count(*) from cc_offres where entreprise_id = v_e.id and cree_le > now() - interval '1 day') >= 5 then raise exception '5 offres par jour maximum'; end if;
  v_ab := cc_entreprise_abonnee(v_e.id);
  insert into cc_offres (entreprise_id, type, titre, description, ville, contrat, remuneration, date_limite, comment_postuler, valide)
  values (v_e.id, v_type, trim(p_offre->>'titre'), left(coalesce(p_offre->>'description',''), 2000), coalesce(p_offre->>'ville',''), coalesce(p_offre->>'contrat',''),
          coalesce(p_offre->>'remuneration',''), nullif(p_offre->>'date_limite','')::date, coalesce(p_offre->>'comment_postuler',''), v_ab)
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id, 'valide', v_ab);
end $$;
revoke all on function cc_offre_deposer(text, text, json) from public;
grant execute on function cc_offre_deposer(text, text, json) to anon, authenticated;

-- Retirer une de ses offres
create or replace function cc_offre_retirer(p_tel text, p_code text, p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_n int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  update cc_offres o set publie = false, maj_le = now() from cc_entreprises e
    where o.id = p_id and e.id = o.entreprise_id and e.telephone = v_tel and e.code = upper(trim(coalesce(p_code,'')));
  get diagnostics v_n = row_count; return json_build_object('ok', v_n > 0);
end $$;
revoke all on function cc_offre_retirer(text, text, bigint) from public;
grant execute on function cc_offre_retirer(text, text, bigint) to anon, authenticated;

-- Compteur « Postuler » (anonyme)
create or replace function cc_offre_postuler(p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_c text;
begin
  update cc_offres set candidatures = candidatures + 1 where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
revoke all on function cc_offre_postuler(bigint) from public;
grant execute on function cc_offre_postuler(bigint) to anon, authenticated;

-- Coordonnées pour une entreprise : abonnement actif, sinon un crédit, sinon « payer »
create or replace function cc_entreprise_contact(p_tel text, p_code text, p_cible text, p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_e record; v_mode text; v_deja boolean; v_s record; v_m record; v_ctarif int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_e from cc_entreprises where telephone = v_tel and code = upper(trim(coalesce(p_code,''))) and publie;
  if not found then return json_build_object('ok', false, 'motif', 'acces'); end if;
  if p_cible not in ('stagiaire','membre') then return json_build_object('ok', false, 'motif', 'cible'); end if;
  v_deja := exists (select 1 from cc_entreprises_contacts where entreprise_id = v_e.id and cible = p_cible and cible_id = p_id);
  if v_deja then v_mode := 'deja';
  elsif cc_entreprise_abonnee(v_e.id) then v_mode := 'abonnement';
  elsif v_e.credits > 0 then v_mode := 'credit';
  else
    v_ctarif := coalesce(nullif((select valeur from cc_settings where cle='entreprises_contact_tarif'), '')::int, 5000);
    return json_build_object('ok', false, 'motif', 'payer', 'tarif_contact', v_ctarif,
      'tarif_abonnement', coalesce(nullif((select valeur from cc_settings where cle='entreprises_tarif'), '')::int, 150000));
  end if;
  if p_cible = 'stagiaire' then
    select * into v_s from cc_stagiaires where id = p_id and publie and not trouve and (type = 'membre' or (paye_jusqu is not null and paye_jusqu >= current_date));
    if v_s.id is null then return json_build_object('ok', false, 'motif', 'introuvable'); end if;
  else
    select * into v_m from cc_membres where id = p_id and actif and annuaire;
    if v_m.id is null then return json_build_object('ok', false, 'motif', 'introuvable'); end if;
  end if;
  if v_mode = 'credit' then update cc_entreprises set credits = credits - 1, maj_le = now() where id = v_e.id; end if;
  if v_mode <> 'deja' then insert into cc_entreprises_contacts (entreprise_id, cible, cible_id, mode) values (v_e.id, p_cible, p_id, v_mode); end if;
  if p_cible = 'stagiaire' then
    return json_build_object('ok', true, 'mode', v_mode, 'nom', v_s.nom, 'telephone', v_s.telephone, 'email', v_s.email, 'cv_url', v_s.cv_url,
      'credits', (select credits from cc_entreprises where id = v_e.id));
  end if;
  return json_build_object('ok', true, 'mode', v_mode, 'nom', v_m.nom, 'telephone', v_m.telephone, 'email', v_m.email, 'cv_url', '',
    'credits', (select credits from cc_entreprises where id = v_e.id));
end $$;
revoke all on function cc_entreprise_contact(text, text, text, bigint) from public;
grant execute on function cc_entreprise_contact(text, text, text, bigint) to anon, authenticated;

-- Activation après paiement (service de paiement) ou par le trésorier : abonnement (durée paramétrée) ou crédit(s)
create or replace function cc_entreprise_activer(p_id bigint, p_objet text, p_nb int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare v_mois int := coalesce(nullif((select valeur from cc_settings where cle = 'entreprises_duree_mois'), '')::int, 12); v_e record;
begin
  if coalesce(current_setting('request.jwt.claims', true)::json->>'role', '') <> 'service_role' and not cc_est_tresorier() then
    raise exception 'Réservé au trésorier';
  end if;
  if p_objet = 'abonnement' then
    update cc_entreprises set abonne_jusqu = (greatest(coalesce(abonne_jusqu, current_date), current_date) + (v_mois || ' months')::interval)::date, publie = true, maj_le = now()
      where id = p_id returning * into v_e;
    -- ses offres en attente deviennent publiées
    update cc_offres set valide = true, maj_le = now() where entreprise_id = p_id and not valide and publie;
  else
    update cc_entreprises set credits = credits + greatest(1, coalesce(p_nb, 1)), maj_le = now() where id = p_id returning * into v_e;
  end if;
  return json_build_object('ok', v_e.id is not null, 'abonne_jusqu', v_e.abonne_jusqu, 'credits', v_e.credits);
end $$;
revoke all on function cc_entreprise_activer(bigint, text, int) from public;
grant execute on function cc_entreprise_activer(bigint, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Annuaire des stagiaires « vivant » : confirmation mensuelle
-- ---------------------------------------------------------------------------
alter table cc_stagiaires add column if not exists confirme_le timestamptz not null default now();
alter table cc_stagiaires add column if not exists rappele_le timestamptz;

drop view if exists cc_stagiaires_public;
create view cc_stagiaires_public as
  select s.id, s.membre_id, s.type, s.nom, s.ecole, s.niveau, s.domaine, s.filiere, s.ville, s.pays, s.logiciels, s.apprendre, s.competences,
         s.type_stage, s.montant, s.duree, s.disponible_le, (s.cv_url <> '') as a_cv, s.message, s.paye_jusqu, s.confirme_le, s.cree_le, s.maj_le
  from cc_stagiaires s
  where s.publie and not s.trouve
    and s.confirme_le >= now() - interval '45 days'
    and (s.type = 'membre' or (s.paye_jusqu is not null and s.paye_jusqu >= current_date));
grant select on cc_stagiaires_public to anon, authenticated;

create or replace function cc_stagiaire_confirmer(p_tel text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_n int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  update cc_stagiaires set confirme_le = now(), trouve = false, maj_le = now()
    where telephone = v_tel or membre_id in (select id from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  get diagnostics v_n = row_count; return json_build_object('ok', v_n > 0);
end $$;
revoke all on function cc_stagiaire_confirmer(text) from public;
grant execute on function cc_stagiaire_confirmer(text) to anon, authenticated;

-- L'enregistrement / la mise à jour d'une fiche vaut confirmation ; le contact d'une entreprise compte dans les contacts du stagiaire
create or replace function cc_stagiaires_confirme_trg() returns trigger language plpgsql as $$
begin new.confirme_le := now(); return new; end $$;
drop trigger if exists trg_cc_stagiaires_confirme on cc_stagiaires;
create trigger trg_cc_stagiaires_confirme before update of nom, ecole, niveau, filiere, type_stage, montant, message, cv_url on cc_stagiaires
  for each row execute function cc_stagiaires_confirme_trg();

insert into cc_settings (cle, valeur) values ('entreprises', 'oui'), ('entreprises_tarif', '150000'), ('entreprises_duree_mois', '12'), ('entreprises_contact_tarif', '5000')
  on conflict (cle) do nothing;
notify pgrst, 'reload schema';
-- Packs de contacts et crédit offert à l'inscription des entreprises
insert into cc_settings (cle, valeur) values ('entreprises_credit_offert', '1'), ('entreprises_pack3_tarif', '12000'), ('entreprises_pack10_tarif', '30000') on conflict (cle) do nothing;

create or replace function cc_entreprise_enregistrer(p_tel text, p_fiche json)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_e record; v_code text; v_nom text := trim(coalesce(p_fiche->>'nom',''));
  v_offert int := coalesce(nullif((select valeur from cc_settings where cle='entreprises_credit_offert'), '')::int, 0);
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_nom) < 2 then raise exception 'Nom de l''entreprise trop court'; end if;
  select * into v_e from cc_entreprises where telephone = v_tel;
  if found then return json_build_object('ok', true, 'id', v_e.id, 'existant', true); end if;
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into cc_entreprises (nom, secteur, ville, pays, contact_nom, telephone, email, code, credits)
  values (v_nom, coalesce(p_fiche->>'secteur',''), coalesce(p_fiche->>'ville',''), coalesce(p_fiche->>'pays',''), coalesce(p_fiche->>'contact_nom',''), v_tel, coalesce(p_fiche->>'email',''), v_code, greatest(0, v_offert))
  returning * into v_e;
  return json_build_object('ok', true, 'id', v_e.id, 'code', v_code, 'existant', false, 'credits', v_e.credits);
end $$;
