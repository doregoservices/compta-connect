-- Confidentialité : les visiteurs ne lisent plus cc_membres ni cc_paiements directement.
-- 1) Vues publiques sans téléphone / e-mail / matricule / date de naissance complète / expéditeur / reçu.
-- 2) Fonction cc_mon_espace(p_cle) : un membre obtient SA fiche complète et SES paiements (téléphone ou matricule).
-- 3) Retrait des politiques « lecture publique » sur les deux tables (les comptes bureau — rôle authenticated — gardent tout).

create or replace view cc_membres_public as
  select id, code, nom, ville, pays, specialite, titre, employeur, photo_url, actif, exonere, annuaire,
         date_adhesion, parrain_id, cotisation, cotisation_nature, nature_montant, nature_depuis, nature_exceptions,
         nature_revise_le, consentement_le, fiche_maj_le,
         case when date_naissance is not null then '0000-' || to_char(date_naissance, 'MM-DD') end as date_naissance
  from cc_membres;
grant select on cc_membres_public to anon, authenticated;

create or replace view cc_paiements_public as
  select id, membre_id, date, mois, montant, caisse, statut, methode, appel_id
  from cc_paiements where membre_id is not null;
grant select on cc_paiements_public to anon, authenticated;

create or replace function cc_mon_espace(p_cle text) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_cle,''), '\D', '', 'g'); v_mat text; v_id bigint;
begin
  v_mat := cc_matricule_normaliser(p_cle);
  if v_mat is not null then
    select id into v_id from cc_membres where matricule = v_mat limit 1;
  elsif length(v_tel) >= 8 then
    if v_tel like '00%' then v_tel := substr(v_tel, 3); end if;
    if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
    if length(v_tel) in (9,11) and v_tel like '0%' then v_tel := substr(v_tel, 2); end if;
    select id into v_id from cc_membres
      where regexp_replace(coalesce(telephone,''), '\D', '', 'g') in (v_tel, '225' || v_tel, '0' || v_tel) limit 1;
  end if;
  if v_id is null then return json_build_object('ok', false); end if;
  perform pg_sleep(0.15);   -- freine une énumération de numéros
  return json_build_object('ok', true,
    'membre', (select row_to_json(m) from cc_membres m where m.id = v_id),
    'paiements', coalesce((select json_agg(row_to_json(p)) from cc_paiements p where p.membre_id = v_id), '[]'::json));
end $$;
grant execute on function cc_mon_espace(text) to anon, authenticated;

drop policy if exists "lecture publique cc_membres" on cc_membres;
drop policy if exists "lecture publique cc_paiements" on cc_paiements;
notify pgrst, 'reload schema';

-- Coordonnées de l'annuaire : uniquement pour un membre à jour (vérifié côté serveur), uniquement les membres ayant consenti.
create or replace function cc_annuaire_coordonnees(p_tel text) returns json
language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(coalesce(telephone,''), '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_mid is null then return json_build_object('ok', false, 'motif', 'membre'); end if;
  if not cc_membre_a_jour(v_mid) then return json_build_object('ok', false, 'motif', 'a_jour'); end if;
  return json_build_object('ok', true, 'coordonnees',
    coalesce((select json_agg(json_build_object('id', id, 'telephone', telephone, 'email', email)) from cc_membres where actif and annuaire), '[]'::json));
end $$;
grant execute on function cc_annuaire_coordonnees(text) to anon, authenticated;
notify pgrst, 'reload schema';
