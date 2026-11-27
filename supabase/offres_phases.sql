-- Diffusion des offres en trois temps : membres d'abord, puis stagiaires inscrits (liste externe), puis le web (public)
alter table cc_offres add column if not exists valide_le timestamptz;
update cc_offres set valide_le = coalesce(valide_le, maj_le, cree_le) where valide and valide_le is null;
create or replace function cc_offres_valide_le() returns trigger language plpgsql as $$
begin
  if new.valide and (old is null or not old.valide or new.valide_le is null) then new.valide_le := coalesce(new.valide_le, now()); end if;
  return new;
end $$;
drop trigger if exists cc_offres_valide_le on cc_offres;
create trigger cc_offres_valide_le before insert or update on cc_offres for each row execute function cc_offres_valide_le();
insert into cc_settings (cle, valeur) values ('offres_delai_membres_h', '48'), ('offres_delai_stagiaires_h', '48') on conflict (cle) do nothing;

create or replace function cc_offres_delais() returns table (membres_h int, stagiaires_h int) language sql stable as $$
  select coalesce(nullif((select valeur from cc_settings where cle='offres_delai_membres_h'), '')::int, 48),
         coalesce(nullif((select valeur from cc_settings where cle='offres_delai_stagiaires_h'), '')::int, 48);
$$;

drop view if exists cc_offres_public;
drop view if exists cc_offres_tout;
create view cc_offres_tout as
  select o.id, o.entreprise_id, o.membre_id,
         coalesce(e.nom, nullif(o.organisme, ''), '') as entreprise, coalesce(e.secteur, '') as secteur,
         (e.id is not null and e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire,
         case when o.membre_id is not null then m.nom else '' end as membre_nom,
         o.type, o.titre, o.description, o.ville, o.contrat, o.remuneration, o.date_limite, o.comment_postuler, o.candidatures, o.cree_le, o.valide_le,
         case when o.valide_le > now() - (d.membres_h || ' hours')::interval then 'membres'
              when o.valide_le > now() - ((d.membres_h + d.stagiaires_h) || ' hours')::interval then 'stagiaires' else 'web' end as phase,
         o.valide_le + (d.membres_h || ' hours')::interval as stagiaires_le,
         o.valide_le + ((d.membres_h + d.stagiaires_h) || ' hours')::interval as web_le
  from cc_offres o cross join cc_offres_delais() d left join cc_entreprises e on e.id = o.entreprise_id left join cc_membres m on m.id = o.membre_id
  where o.publie and o.valide and (e.id is null or e.publie) and (o.membre_id is null or m.actif) and (o.date_limite is null or o.date_limite >= current_date);
grant select on cc_offres_tout to authenticated;   -- trésorier ; le service utilise la clé de service

create view cc_offres_public as select * from cc_offres_tout where phase = 'web';
grant select on cc_offres_public to anon, authenticated;

-- Liste selon qui demande : membre actif → tout ; stagiaire inscrit → après la phase membres ; sinon → web
create or replace function cc_offres_liste(p_tel text)
returns setof cc_offres_tout language plpgsql stable security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_membre boolean; v_stag boolean;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  v_membre := length(v_tel) >= 8 and exists (select 1 from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  v_stag := not v_membre and length(v_tel) >= 8 and exists (select 1 from cc_stagiaires where publie and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel));
  return query select * from cc_offres_tout t where v_membre or (v_stag and t.phase <> 'membres') or t.phase = 'web' order by t.id desc limit 200;
end $$;
revoke all on function cc_offres_liste(text) from public;
grant execute on function cc_offres_liste(text) to anon, authenticated;

-- Postuler : respecter la phase (un lien public ne doit pas contourner la priorité)
create or replace function cc_offre_postuler(p_id bigint, p_tel text default '')
returns json language plpgsql security definer set search_path = public as $$
declare v_c text; v_ok boolean;
begin
  v_ok := exists (select 1 from cc_offres_liste(p_tel) where id = p_id);
  if not v_ok then return json_build_object('ok', false, 'motif', 'phase'); end if;
  update cc_offres set candidatures = candidatures + 1 where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
revoke all on function cc_offre_postuler(bigint, text) from public;
grant execute on function cc_offre_postuler(bigint, text) to anon, authenticated;
drop function if exists cc_offre_postuler(bigint);

alter table cc_courriels_file add column if not exists cible text not null default 'tous';   -- tous | membres | stagiaires
