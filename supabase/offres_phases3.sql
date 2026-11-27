-- Correctif : les membres reçoivent toujours le contact des offres d'emploi ; l'aperçu (sans contact) ne concerne que les non-membres
drop view if exists cc_offres_public;
drop function if exists cc_offre_postuler(bigint, text);
drop function if exists cc_offres_liste(text);
drop view if exists cc_offres_tout;
create view cc_offres_tout as
  with b as (
    select o.*, d.membres_h, d.stagiaires_h,
           case when o.valide_le > now() - (d.membres_h || ' hours')::interval then 'membres'
                when o.valide_le > now() - ((d.membres_h + d.stagiaires_h) || ' hours')::interval then 'stagiaires' else 'web' end as phase_temps
    from cc_offres o cross join cc_offres_delais() d)
  select b.id, b.entreprise_id, b.membre_id,
         coalesce(e.nom, nullif(b.organisme, ''), '') as entreprise, coalesce(e.secteur, '') as secteur,
         (e.id is not null and e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire,
         case when b.membre_id is not null then m.nom else '' end as membre_nom,
         b.type, b.titre, b.description, b.ville, b.contrat, b.remuneration, b.date_limite, b.comment_postuler,
         b.candidatures, b.cree_le, b.valide_le,
         coalesce(b.fige_phase, b.phase_temps) as phase,
         (b.type <> 'stage' and coalesce(b.fige_phase, b.phase_temps) <> 'membres') as apercu,   -- pour les non-membres : visible sans contact
         (b.fige_phase is not null) as figee,
         b.valide_le + (b.membres_h || ' hours')::interval as stagiaires_le,
         b.valide_le + ((b.membres_h + b.stagiaires_h) || ' hours')::interval as web_le
  from b left join cc_entreprises e on e.id = b.entreprise_id left join cc_membres m on m.id = b.membre_id
  where b.publie and b.valide and (e.id is null or e.publie) and (b.membre_id is null or m.actif) and (b.date_limite is null or b.date_limite >= current_date);
grant select on cc_offres_tout to authenticated;
create view cc_offres_public as
  select id, entreprise_id, membre_id, entreprise, secteur, partenaire, membre_nom, type, titre, description, ville, contrat, remuneration, date_limite,
         case when apercu then '' else comment_postuler end as comment_postuler, candidatures, cree_le, valide_le, phase, apercu, figee, stagiaires_le, web_le
  from cc_offres_tout where phase = 'web';
grant select on cc_offres_public to anon, authenticated;

create or replace function cc_offres_liste(p_tel text)
returns setof cc_offres_tout language plpgsql stable security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_membre boolean; v_stag boolean;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  v_membre := length(v_tel) >= 8 and exists (select 1 from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  v_stag := not v_membre and length(v_tel) >= 8 and exists (select 1 from cc_stagiaires where publie and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  return query select t.id, t.entreprise_id, t.membre_id, t.entreprise, t.secteur, t.partenaire, t.membre_nom, t.type, t.titre, t.description, t.ville, t.contrat, t.remuneration, t.date_limite,
      case when v_membre or not t.apercu then t.comment_postuler else '' end, t.candidatures, t.cree_le, t.valide_le, t.phase,
      (t.apercu and not v_membre), t.figee, t.stagiaires_le, t.web_le
    from cc_offres_tout t where v_membre or (v_stag and t.phase <> 'membres') or t.phase = 'web' order by t.id desc limit 200;
end $$;
revoke all on function cc_offres_liste(text) from public;
grant execute on function cc_offres_liste(text) to anon, authenticated;

create or replace function cc_offre_postuler(p_id bigint, p_tel text default '')
returns json language plpgsql security definer set search_path = public as $$
declare v_t record; v_c text;
begin
  select * into v_t from cc_offres_liste(p_tel) where id = p_id;
  if v_t.id is null then return json_build_object('ok', false, 'motif', 'phase'); end if;
  if v_t.apercu then return json_build_object('ok', false, 'motif', 'membres'); end if;
  update cc_offres set candidatures = candidatures + 1,
         fige_phase = case when fige_phase is null and v_t.phase in ('membres','stagiaires') then v_t.phase else fige_phase end,
         fige_le = case when fige_phase is null and v_t.phase in ('membres','stagiaires') then now() else fige_le end
    where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
revoke all on function cc_offre_postuler(bigint, text) from public;
grant execute on function cc_offre_postuler(bigint, text) to anon, authenticated;
