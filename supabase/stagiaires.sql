-- ============================================================================
-- Annuaire des stagiaires (étudiants et jeunes diplômés en recherche de stage)
--  • Deux listes : membres du réseau (gratuit, fiche visible tant que le membre est à jour — contrôle côté
--    application avec la règle de pointage) et public (inscription payante, validité limitée).
--  • Les coordonnées (téléphone, e-mail, CV) ne sont JAMAIS exposées en lecture anonyme : elles sont remises
--    par la fonction cc_stagiaire_contact à un membre actif à jour, et chaque consultation est journalisée.
-- ============================================================================
create table if not exists cc_stagiaires (
  id            bigserial primary key,
  membre_id     bigint references cc_membres(id) on delete set null,
  type          text not null default 'public',            -- membre | public
  nom           text not null,
  telephone     text not null default '',
  email         text not null default '',
  ecole         text not null default '',
  niveau        text not null default '',                  -- BTS, Licence, Master, DSCG, jeune diplômé…
  domaine       text not null default 'compta',            -- compta (comptabilité/finance/audit/fiscalité) | autre (toutes autres filières : toujours liste publique payante)
  filiere       text not null default '',                  -- comptabilité, finance, audit, fiscalité… ou filière libre si domaine = autre
  ville         text not null default '',
  pays          text not null default '',
  logiciels     text not null default '',                  -- SAARI, Excel, FNE… (texte libre)
  apprendre     boolean not null default false,            -- « aucune maîtrise, je veux apprendre »
  competences   text not null default '',
  type_stage    text not null default 'prise_en_charge',   -- benevole | prise_en_charge | remunere
  montant       integer not null default 0,                -- prétention mensuelle (F), 0 = non précisé
  duree         text not null default '',                  -- 1 mois, 3 mois, 6 mois…
  disponible_le date,
  cv_url        text not null default '',
  message       text not null default '',
  paye_le       timestamptz,
  paye_jusqu    date,                                      -- liste publique : visible jusqu'à cette date
  publie        boolean not null default true,             -- le trésorier peut retirer une fiche
  trouve        boolean not null default false,            -- « j'ai trouvé mon stage »
  cree_le       timestamptz not null default now(),
  maj_le        timestamptz not null default now()
);
create unique index if not exists cc_stagiaires_membre_uq on cc_stagiaires(membre_id) where membre_id is not null;
create unique index if not exists cc_stagiaires_tel_uq on cc_stagiaires(telephone) where membre_id is null;
alter table cc_stagiaires enable row level security;
drop policy if exists "tresorier cc_stagiaires" on cc_stagiaires;
create policy "tresorier cc_stagiaires" on cc_stagiaires for all to authenticated using (true) with check (true);
grant all on cc_stagiaires to authenticated;
grant usage, select on sequence cc_stagiaires_id_seq to authenticated;
revoke all on cc_stagiaires from anon;

-- Journal des consultations de coordonnées (qui a contacté qui)
create table if not exists cc_stagiaires_contacts (
  id bigserial primary key,
  stagiaire_id bigint references cc_stagiaires(id) on delete cascade,
  membre_id bigint references cc_membres(id) on delete set null,
  quand timestamptz not null default now()
);
alter table cc_stagiaires_contacts enable row level security;
drop policy if exists "tresorier cc_stagiaires_contacts" on cc_stagiaires_contacts;
create policy "tresorier cc_stagiaires_contacts" on cc_stagiaires_contacts for select to authenticated using (true);
grant select on cc_stagiaires_contacts to authenticated;
revoke all on cc_stagiaires_contacts from anon;

alter table cc_stagiaires add column if not exists domaine text not null default 'compta';

-- Transactions CinetPay : rattachement éventuel à une fiche stagiaire (inscription publique)
alter table cc_transactions add column if not exists stagiaire_id bigint references cc_stagiaires(id) on delete set null;

-- Vue publique SANS coordonnées (lecture anonyme) : membres = publiés et non trouvés ; public = payés et dans la validité
drop view if exists cc_stagiaires_public;
create view cc_stagiaires_public as
  select s.id, s.membre_id, s.type, s.nom, s.ecole, s.niveau, s.domaine, s.filiere, s.ville, s.pays, s.logiciels, s.apprendre, s.competences,
         s.type_stage, s.montant, s.duree, s.disponible_le, (s.cv_url <> '') as a_cv, s.message, s.paye_jusqu, s.cree_le, s.maj_le
  from cc_stagiaires s
  where s.publie and not s.trouve
    and (s.type = 'membre' or (s.paye_jusqu is not null and s.paye_jusqu >= current_date));
grant select on cc_stagiaires_public to anon, authenticated;

-- Membre « à jour » côté base : actif et (exonéré, en nature, ou un paiement rapproché de cotisation sur le mois courant /
-- le mois précédent pendant la tolérance / en avance). Approximation fidèle de la règle de pointage de l'application.
create or replace function cc_membre_a_jour(p_membre_id bigint)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_m record; v_tol int := coalesce((select valeur::int from cc_settings where cle = 'cotisation_tolerance'), 10);
        v_mois text := to_char(current_date, 'YYYY-MM'); v_prec text := to_char(current_date - interval '1 month', 'YYYY-MM');
begin
  select * into v_m from cc_membres where id = p_membre_id;
  if not found or not v_m.actif then return false; end if;
  if v_m.exonere or coalesce(v_m.cotisation_nature, '') <> '' then return true; end if;
  return exists (select 1 from cc_paiements p where p.membre_id = p_membre_id and p.statut = 'RAPPROCHE' and p.caisse = 'cotisation'
                 and (p.mois >= v_mois or (p.mois = v_prec and extract(day from current_date) <= v_tol)));
end $$;
revoke all on function cc_membre_a_jour(bigint) from public;

-- Enregistrer / mettre à jour sa fiche (membre identifié par son téléphone, ou étudiant du public)
create or replace function cc_stagiaire_enregistrer(p_tel text, p_fiche json)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_m record; v_id bigint; v_type text; v_tarif int; v_s record;
        v_nom text := trim(coalesce(p_fiche->>'nom','')); v_type_stage text := coalesce(p_fiche->>'type_stage','prise_en_charge');
        v_dom text := case when coalesce(p_fiche->>'domaine','compta') = 'autre' then 'autre' else 'compta' end;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  if length(v_tel) < 8 then raise exception 'Numéro de téléphone invalide'; end if;
  if length(v_nom) < 3 then raise exception 'Nom trop court'; end if;
  if v_type_stage not in ('benevole','prise_en_charge','remunere') then v_type_stage := 'prise_en_charge'; end if;
  select id, nom, actif into v_m from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  -- étudiants hors comptabilité/finance : toujours liste publique payante, même si le numéro est connu
  v_type := case when found and v_m.actif and v_dom = 'compta' then 'membre' else 'public' end;
  v_tarif := coalesce((select valeur::int from cc_settings where cle = 'stagiaires_tarif'), 2000);

  if v_type = 'membre' then
    select * into v_s from cc_stagiaires where membre_id = v_m.id;
  else
    select * into v_s from cc_stagiaires where membre_id is null and telephone = v_tel;
  end if;

  if v_s.id is null then
    insert into cc_stagiaires (membre_id, type, nom, telephone, email, ecole, niveau, domaine, filiere, ville, pays, logiciels, apprendre, competences,
                               type_stage, montant, duree, disponible_le, cv_url, message)
    values (case when v_type = 'membre' then v_m.id end, v_type, v_nom, v_tel, coalesce(p_fiche->>'email',''), coalesce(p_fiche->>'ecole',''),
            coalesce(p_fiche->>'niveau',''), v_dom, coalesce(p_fiche->>'filiere',''), coalesce(p_fiche->>'ville',''), coalesce(p_fiche->>'pays',''),
            coalesce(p_fiche->>'logiciels',''), coalesce((p_fiche->>'apprendre')::boolean, false), coalesce(p_fiche->>'competences',''),
            v_type_stage, greatest(0, coalesce((p_fiche->>'montant')::int, 0)), coalesce(p_fiche->>'duree',''),
            nullif(p_fiche->>'disponible_le','')::date, coalesce(p_fiche->>'cv_url',''), left(coalesce(p_fiche->>'message',''), 600))
    returning id into v_id;
  else
    update cc_stagiaires set nom = v_nom, email = coalesce(p_fiche->>'email',''), ecole = coalesce(p_fiche->>'ecole',''), niveau = coalesce(p_fiche->>'niveau',''),
      domaine = v_dom, filiere = coalesce(p_fiche->>'filiere',''), ville = coalesce(p_fiche->>'ville',''), pays = coalesce(p_fiche->>'pays',''), logiciels = coalesce(p_fiche->>'logiciels',''),
      apprendre = coalesce((p_fiche->>'apprendre')::boolean, false), competences = coalesce(p_fiche->>'competences',''), type_stage = v_type_stage,
      montant = greatest(0, coalesce((p_fiche->>'montant')::int, 0)), duree = coalesce(p_fiche->>'duree',''), disponible_le = nullif(p_fiche->>'disponible_le','')::date,
      cv_url = case when coalesce(p_fiche->>'cv_url','') <> '' then p_fiche->>'cv_url' else cv_url end, message = left(coalesce(p_fiche->>'message',''), 600),
      trouve = false, type = v_type, membre_id = case when v_type = 'membre' then v_m.id else membre_id end, maj_le = now()
    where id = v_s.id returning id into v_id;
  end if;

  return json_build_object('ok', true, 'id', v_id, 'type', v_type,
    'a_jour', case when v_type = 'membre' then cc_membre_a_jour(v_m.id) else null end,
    'paye_jusqu', (select paye_jusqu from cc_stagiaires where id = v_id),
    'a_payer', case when v_type = 'public' and coalesce((select paye_jusqu from cc_stagiaires where id = v_id) < current_date, true) then v_tarif else 0 end);
end $$;
revoke all on function cc_stagiaire_enregistrer(text, json) from public;
grant execute on function cc_stagiaire_enregistrer(text, json) to anon, authenticated;

-- Ma fiche (pour la modifier) : identifiée par le téléphone
create or replace function cc_stagiaire_ma_fiche(p_tel text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_s record; v_tarif int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select s.* into v_s from cc_stagiaires s
    where s.telephone = v_tel or s.membre_id in (select id from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel))
    order by (s.membre_id is not null) desc limit 1;
  if v_s.id is null then return json_build_object('ok', false); end if;
  v_tarif := coalesce((select valeur::int from cc_settings where cle = 'stagiaires_tarif'), 2000);
  return json_build_object('ok', true, 'fiche', row_to_json(v_s),
    'a_jour', case when v_s.membre_id is not null then cc_membre_a_jour(v_s.membre_id) else null end,
    'a_payer', case when v_s.type = 'public' and coalesce(v_s.paye_jusqu < current_date, true) then v_tarif else 0 end);
end $$;
revoke all on function cc_stagiaire_ma_fiche(text) from public;
grant execute on function cc_stagiaire_ma_fiche(text) to anon, authenticated;

-- « J'ai trouvé mon stage » / remettre la fiche en ligne
create or replace function cc_stagiaire_trouve(p_tel text, p_oui boolean)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_n int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  update cc_stagiaires set trouve = p_oui, maj_le = now()
    where telephone = v_tel or membre_id in (select id from cc_membres where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  get diagnostics v_n = row_count;
  return json_build_object('ok', v_n > 0);
end $$;
revoke all on function cc_stagiaire_trouve(text, boolean) from public;
grant execute on function cc_stagiaire_trouve(text, boolean) to anon, authenticated;

-- Coordonnées d'un stagiaire : réservées aux membres actifs à jour ; chaque consultation est journalisée
create or replace function cc_stagiaire_contact(p_tel text, p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint; v_s record;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_mid is null then return json_build_object('ok', false, 'motif', 'membre'); end if;
  if not cc_membre_a_jour(v_mid) then return json_build_object('ok', false, 'motif', 'a_jour'); end if;
  select * into v_s from cc_stagiaires where id = p_id and publie and not trouve
    and (type = 'membre' or (paye_jusqu is not null and paye_jusqu >= current_date));
  if v_s.id is null then return json_build_object('ok', false, 'motif', 'introuvable'); end if;
  insert into cc_stagiaires_contacts (stagiaire_id, membre_id) values (v_s.id, v_mid);
  return json_build_object('ok', true, 'nom', v_s.nom, 'telephone', v_s.telephone, 'email', v_s.email, 'cv_url', v_s.cv_url);
end $$;
revoke all on function cc_stagiaire_contact(text, bigint) from public;
grant execute on function cc_stagiaire_contact(text, bigint) to anon, authenticated;

-- Activation de la liste publique après paiement (appelée par la fonction de paiement, rôle service)
create or replace function cc_stagiaire_activer(p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_mois int := coalesce((select valeur::int from cc_settings where cle = 'stagiaires_duree_mois'), 6); v_j date;
begin
  -- appelable par le service de paiement (service_role) ou par le trésorier connecté
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role'
     and coalesce(current_setting('request.jwt.claims', true)::json->>'role', '') <> 'service_role'
     and not cc_est_tresorier() then
    raise exception 'Réservé au trésorier';
  end if;
  update cc_stagiaires set paye_le = now(), publie = true,
    paye_jusqu = (greatest(coalesce(paye_jusqu, current_date), current_date) + (v_mois || ' months')::interval)::date, maj_le = now()
    where id = p_id returning paye_jusqu into v_j;
  return json_build_object('ok', v_j is not null, 'paye_jusqu', v_j);
end $$;
revoke all on function cc_stagiaire_activer(bigint) from public;
grant execute on function cc_stagiaire_activer(bigint) to authenticated;

insert into cc_settings (cle, valeur) values ('stagiaires', 'oui'), ('stagiaires_tarif', '2000'), ('stagiaires_duree_mois', '6')
  on conflict (cle) do nothing;
notify pgrst, 'reload schema';
