-- Paliers de 72 h ; à la fin d'un palier, s'il y a eu des candidats, le recruteur doit les examiner avant l'élargissement
update cc_settings set valeur = '72' where cle in ('offres_delai_membres_h','offres_delai_stagiaires_h');
alter table cc_offres add column if not exists palier_examine int not null default 0;   -- nb de paliers dont les candidats ont été examinés (0, 1, 2)

drop view if exists cc_offres_public;
drop function if exists cc_offre_postuler(bigint, text, text, text);
drop function if exists cc_offres_liste(text);
drop view if exists cc_offres_tout;
create view cc_offres_tout as
  with b as (
    select o.*, d.membres_h, d.stagiaires_h,
           o.valide_le + (d.membres_h || ' hours')::interval as fin1,
           o.valide_le + ((d.membres_h + d.stagiaires_h) || ' hours')::interval as fin2
    from cc_offres o cross join cc_offres_delais() d),
  p as (
    select b.*,
           case when now() < b.fin1 then 'membres' when now() < b.fin2 then 'stagiaires' else 'web' end as phase_temps,
           (b.palier_examine < 1 and exists (select 1 from cc_candidatures c where c.offre_id = b.id and c.quand < b.fin1)) as bloque1,
           (b.palier_examine < 2 and exists (select 1 from cc_candidatures c where c.offre_id = b.id and c.quand >= b.fin1 and c.quand < b.fin2)) as bloque2   -- candidats arrivés pendant le palier 2
    from b)
  select p.id, p.entreprise_id, p.membre_id,
         coalesce(e.nom, nullif(p.organisme, ''), '') as entreprise, coalesce(e.secteur, '') as secteur,
         (e.id is not null and e.abonne_jusqu is not null and e.abonne_jusqu >= current_date) as partenaire,
         case when p.membre_id is not null then m.nom else '' end as membre_nom,
         p.type, p.titre, p.description, p.ville, p.contrat, p.remuneration, p.date_limite, p.comment_postuler,
         p.candidatures, p.cree_le, p.valide_le,
         case when p.phase_temps = 'membres' or p.bloque1 then 'membres' when p.phase_temps = 'stagiaires' or p.bloque2 then 'stagiaires' else 'web' end as phase,
         p.phase_temps,
         (p.type <> 'stage' and not (p.phase_temps = 'membres' or p.bloque1)) as apercu,
         ((p.phase_temps <> 'membres' and p.bloque1) or (p.phase_temps = 'web' and p.bloque2)) as examen_requis,
         case when p.phase_temps <> 'membres' and p.bloque1 then 1 when p.phase_temps = 'web' and p.bloque2 then 2 else 0 end as palier_a_examiner,
         p.fin1 as stagiaires_le, p.fin2 as web_le
  from p left join cc_entreprises e on e.id = p.entreprise_id left join cc_membres m on m.id = p.membre_id
  where p.publie and p.valide and (e.id is null or e.publie) and (p.membre_id is null or m.actif) and (p.date_limite is null or p.date_limite >= current_date);
grant select on cc_offres_tout to authenticated;
create view cc_offres_public as
  select id, entreprise_id, membre_id, entreprise, secteur, partenaire, membre_nom, type, titre, description, ville, contrat, remuneration, date_limite,
         case when apercu then '' else comment_postuler end as comment_postuler, candidatures, cree_le, valide_le, phase, phase_temps, apercu, examen_requis, palier_a_examiner, stagiaires_le, web_le
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
      case when v_membre or not t.apercu then t.comment_postuler else '' end, t.candidatures, t.cree_le, t.valide_le, t.phase, t.phase_temps,
      (t.apercu and not v_membre), t.examen_requis, t.palier_a_examiner, t.stagiaires_le, t.web_le
    from cc_offres_tout t where v_membre or (v_stag and t.phase <> 'membres') or t.phase = 'web' order by t.id desc limit 200;
end $$;
revoke all on function cc_offres_liste(text) from public;
grant execute on function cc_offres_liste(text) to anon, authenticated;

create or replace function cc_offre_postuler(p_id bigint, p_tel text default '', p_nom text default '', p_email text default '')
returns json language plpgsql security definer set search_path = public as $$
declare v_t record; v_c text; v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_mid bigint; v_mnom text; v_memail text; v_sid bigint; v_snom text; v_semail text; v_orig text := 'public'; v_nom text := trim(coalesce(p_nom,''));
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_t from cc_offres_liste(p_tel) where id = p_id;
  if v_t.id is null then return json_build_object('ok', false, 'motif', 'phase'); end if;
  if v_t.apercu then return json_build_object('ok', false, 'motif', 'membres'); end if;
  if length(v_tel) < 8 then return json_build_object('ok', false, 'motif', 'tel'); end if;
  select id, nom, email into v_mid, v_mnom, v_memail from cc_membres where actif and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if v_mid is not null then v_orig := 'membre'; v_nom := v_mnom;
  else select id, nom, email into v_sid, v_snom, v_semail from cc_stagiaires where publie and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
       if v_sid is not null then v_orig := 'stagiaire'; v_nom := v_snom; end if; end if;
  if length(v_nom) < 2 then return json_build_object('ok', false, 'motif', 'nom'); end if;
  if exists (select 1 from cc_candidatures where offre_id = p_id and telephone = v_tel) then
    select comment_postuler into v_c from cc_offres where id = p_id; return json_build_object('ok', true, 'deja', true, 'comment_postuler', coalesce(v_c, ''));
  end if;
  insert into cc_candidatures (offre_id, nom, telephone, email, origine, membre_id, stagiaire_id)
  values (p_id, v_nom, v_tel, coalesce(nullif(trim(p_email),''), v_memail, v_semail, ''), v_orig, v_mid, v_sid);
  update cc_offres set candidatures = candidatures + 1, maj_le = now() where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
revoke all on function cc_offre_postuler(bigint, text, text, text) from public;
grant execute on function cc_offre_postuler(bigint, text, text, text) to anon, authenticated;

-- État des offres d'un recruteur (phase, examen requis) — informations non sensibles
create or replace function cc_offres_etats(p_ids bigint[])
returns table (id bigint, phase text, phase_temps text, examen_requis boolean, palier_a_examiner int, stagiaires_le timestamptz, web_le timestamptz)
language sql stable security definer set search_path = public as $$
  select t.id, t.phase, t.phase_temps, t.examen_requis, t.palier_a_examiner, t.stagiaires_le, t.web_le from cc_offres_tout t where t.id = any(p_ids);
$$;
revoke all on function cc_offres_etats(bigint[]) from public;
grant execute on function cc_offres_etats(bigint[]) to anon, authenticated;

-- Décision du recruteur : 'pourvue' | 'examine' (candidats du palier examinés → palier suivant)
create or replace function cc_offre_decider(p_tel text, p_code text, p_id bigint, p_action text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_o record; v_ok boolean := false; v_t record;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_o from cc_offres where id = p_id; if v_o.id is null then return json_build_object('ok', false); end if;
  if v_o.entreprise_id is not null then v_ok := exists (select 1 from cc_entreprises where id = v_o.entreprise_id and telephone = v_tel and code = upper(trim(coalesce(p_code,''))));
  elsif v_o.membre_id is not null then v_ok := exists (select 1 from cc_membres where id = v_o.membre_id and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel)); end if;
  if not v_ok then return json_build_object('ok', false, 'motif', 'acces'); end if;
  if p_action = 'pourvue' then update cc_offres set pourvue = true, publie = false, maj_le = now() where id = p_id;
  elsif p_action = 'examine' then
    select * into v_t from cc_offres_tout where id = p_id;
    update cc_offres set palier_examine = greatest(palier_examine, case v_t.phase_temps when 'stagiaires' then 1 when 'web' then 2 else 0 end), maj_le = now() where id = p_id;
  else return json_build_object('ok', false, 'motif', 'action'); end if;
  return json_build_object('ok', true);
end $$;
drop function if exists cc_offre_poursuivre(bigint);
