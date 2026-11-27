-- Offres partagées par les membres + plafond mensuel de coordonnées de stagiaires par membre
alter table cc_offres alter column entreprise_id drop not null;
alter table cc_offres add column if not exists membre_id bigint references cc_membres(id) on delete cascade;
alter table cc_offres add column if not exists organisme text not null default '';   -- entreprise / cabinet cité par le membre
insert into cc_settings (cle, valeur) values ('stagiaires_contacts_mois', '10'), ('pts_offre', '3') on conflict (cle) do nothing;

drop view if exists cc_offres_public;
create view cc_offres_public as
  select o.id, o.entreprise_id, o.membre_id,
         coalesce(e.nom, nullif(o.organisme, ''), '') as entreprise, coalesce(e.secteur, '') as secteur,
         (e.id is not null and e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire,
         case when o.membre_id is not null then m.nom else '' end as membre_nom,
         o.type, o.titre, o.description, o.ville, o.contrat, o.remuneration, o.date_limite, o.comment_postuler, o.candidatures, o.cree_le
  from cc_offres o left join cc_entreprises e on e.id = o.entreprise_id left join cc_membres m on m.id = o.membre_id
  where o.publie and o.valide and (e.id is null or e.publie) and (o.membre_id is null or m.actif) and (o.date_limite is null or o.date_limite >= current_date);
grant select on cc_offres_public to anon, authenticated;

-- Un membre actif partage une offre (validée ensuite par le bureau) ; 3 par jour maximum
create or replace function cc_offre_partager(p_tel text, p_offre json)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint; v_id bigint; v_type text := coalesce(p_offre->>'type','emploi');
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_mid is null then return json_build_object('ok', false, 'motif', 'membre'); end if;
  if length(trim(coalesce(p_offre->>'titre',''))) < 5 then raise exception 'Titre trop court'; end if;
  if v_type not in ('emploi','stage','mission') then v_type := 'emploi'; end if;
  if (select count(*) from cc_offres where membre_id = v_mid and cree_le > now() - interval '1 day') >= 3 then raise exception '3 offres par jour maximum'; end if;
  insert into cc_offres (membre_id, organisme, type, titre, description, ville, contrat, remuneration, date_limite, comment_postuler, valide)
  values (v_mid, left(coalesce(p_offre->>'organisme',''), 80), v_type, trim(p_offre->>'titre'), left(coalesce(p_offre->>'description',''), 2000), coalesce(p_offre->>'ville',''), coalesce(p_offre->>'contrat',''),
          coalesce(p_offre->>'remuneration',''), nullif(p_offre->>'date_limite','')::date, coalesce(p_offre->>'comment_postuler',''), false)
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id, 'valide', false);
end $$;
revoke all on function cc_offre_partager(text, json) from public;
grant execute on function cc_offre_partager(text, json) to anon, authenticated;

create or replace function cc_offre_retirer_membre(p_tel text, p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint; v_n int;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  update cc_offres set publie = false, maj_le = now() where id = p_id and membre_id = v_mid; get diagnostics v_n = row_count;
  return json_build_object('ok', v_n > 0);
end $$;
revoke all on function cc_offre_retirer_membre(text, bigint) from public;
grant execute on function cc_offre_retirer_membre(text, bigint) to anon, authenticated;

-- Offres d'un membre (pour son espace) : lecture anonyme limitée à ses propres offres via téléphone
create or replace function cc_offres_du_membre(p_tel text)
returns setof cc_offres language plpgsql stable security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  return query select * from cc_offres where membre_id = v_mid order by id desc limit 50;
end $$;
revoke all on function cc_offres_du_membre(text) from public;
grant execute on function cc_offres_du_membre(text) to anon, authenticated;

-- Coordonnées d'un stagiaire : membres à jour, plafond mensuel (fiches distinctes) ; revoir une fiche déjà consultée ne compte pas
create or replace function cc_stagiaire_contact(p_tel text, p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint; v_s record;
  v_max int := coalesce(nullif((select valeur from cc_settings where cle='stagiaires_contacts_mois'), '')::int, 10); v_n int; v_deja boolean;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select id into v_mid from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_mid is null then return json_build_object('ok', false, 'motif', 'membre'); end if;
  if not cc_membre_a_jour(v_mid) then return json_build_object('ok', false, 'motif', 'a_jour'); end if;
  select * into v_s from cc_stagiaires where id = p_id and publie and not trouve
    and (type = 'membre' or (paye_jusqu is not null and paye_jusqu >= current_date));
  if v_s.id is null then return json_build_object('ok', false, 'motif', 'introuvable'); end if;
  v_deja := exists (select 1 from cc_stagiaires_contacts where membre_id = v_mid and stagiaire_id = v_s.id);
  select count(distinct stagiaire_id) into v_n from cc_stagiaires_contacts where membre_id = v_mid and quand >= date_trunc('month', now());
  if not v_deja and v_max > 0 and v_n >= v_max then return json_build_object('ok', false, 'motif', 'plafond', 'max', v_max); end if;
  insert into cc_stagiaires_contacts (stagiaire_id, membre_id) values (v_s.id, v_mid);
  return json_build_object('ok', true, 'nom', v_s.nom, 'telephone', v_s.telephone, 'email', v_s.email, 'cv_url', v_s.cv_url, 'reste', greatest(0, v_max - v_n - case when v_deja then 0 else 1 end));
end $$;
