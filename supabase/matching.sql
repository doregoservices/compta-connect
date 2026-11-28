-- Tri léger des candidats : critères du recruteur (ville, niveaux, logiciels, disponibilité) croisés avec la fiche du candidat
alter table cc_offres add column if not exists criteres jsonb not null default '{}'::jsonb;
alter table cc_candidatures add column if not exists profil jsonb not null default '{}'::jsonb;   -- renseigné par les candidats du public

-- Dépôt entreprise : + critères
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
  insert into cc_offres (entreprise_id, type, titre, description, ville, contrat, remuneration, date_limite, comment_postuler, valide, criteres)
  values (v_e.id, v_type, trim(p_offre->>'titre'), left(coalesce(p_offre->>'description',''), 2000), coalesce(p_offre->>'ville',''), coalesce(p_offre->>'contrat',''),
          coalesce(p_offre->>'remuneration',''), nullif(p_offre->>'date_limite','')::date, coalesce(p_offre->>'comment_postuler',''), v_ab, coalesce((p_offre->'criteres')::jsonb, '{}'::jsonb))
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id, 'valide', v_ab);
end $$;

-- Partage membre : + critères
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
  insert into cc_offres (membre_id, organisme, type, titre, description, ville, contrat, remuneration, date_limite, comment_postuler, valide, criteres)
  values (v_mid, left(coalesce(p_offre->>'organisme',''), 80), v_type, trim(p_offre->>'titre'), left(coalesce(p_offre->>'description',''), 2000), coalesce(p_offre->>'ville',''), coalesce(p_offre->>'contrat',''),
          coalesce(p_offre->>'remuneration',''), nullif(p_offre->>'date_limite','')::date, coalesce(p_offre->>'comment_postuler',''), false, coalesce((p_offre->'criteres')::jsonb, '{}'::jsonb))
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id, 'valide', false);
end $$;

-- Postuler : + profil (public)
create or replace function cc_offre_postuler(p_id bigint, p_tel text default '', p_nom text default '', p_email text default '', p_profil json default '{}')
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
  insert into cc_candidatures (offre_id, nom, telephone, email, origine, membre_id, stagiaire_id, profil)
  values (p_id, v_nom, v_tel, coalesce(nullif(trim(p_email),''), v_memail, v_semail, ''), v_orig, v_mid, v_sid, coalesce(p_profil::jsonb, '{}'::jsonb));
  update cc_offres set candidatures = candidatures + 1, maj_le = now() where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
drop function if exists cc_offre_postuler(bigint, text, text, text);
revoke all on function cc_offre_postuler(bigint, text, text, text, json) from public;
grant execute on function cc_offre_postuler(bigint, text, text, text, json) to anon, authenticated;

-- Correspondance d'un profil avec les critères : renvoie {score, max, details:[{c, ok, info}]}
create or replace function cc_correspondance(p_crit jsonb, p_prof jsonb) returns json language plpgsql immutable as $$
declare d json[] := '{}'; n int := 0; mx int := 0; ok boolean; v text; lg text; trouves int; total int;
begin
  if coalesce(p_crit->>'ville','') <> '' then mx := mx + 1; ok := lower(coalesce(p_prof->>'ville','')) like '%' || lower(p_crit->>'ville') || '%'; if ok then n := n + 1; end if;
    d := d || json_build_object('c', 'Ville ' || (p_crit->>'ville'), 'ok', ok, 'info', coalesce(p_prof->>'ville','?')); end if;
  if jsonb_typeof(p_crit->'niveaux') = 'array' and jsonb_array_length(p_crit->'niveaux') > 0 then mx := mx + 1;
    ok := exists (select 1 from jsonb_array_elements_text(p_crit->'niveaux') x where lower(x) = lower(coalesce(p_prof->>'niveau',''))); if ok then n := n + 1; end if;
    d := d || json_build_object('c', 'Niveau', 'ok', ok, 'info', coalesce(nullif(p_prof->>'niveau',''),'?')); end if;
  if coalesce(p_crit->>'logiciels','') <> '' then
    lg := lower(coalesce(p_prof->>'logiciels','')); trouves := 0; total := 0;
    for v in select trim(x) from regexp_split_to_table(p_crit->>'logiciels', '[,;/]') x where trim(x) <> '' loop
      total := total + 1; if position(lower(v) in lg) > 0 then trouves := trouves + 1; end if;
      mx := mx + 1; if position(lower(v) in lg) > 0 then n := n + 1; end if;
      d := d || json_build_object('c', v, 'ok', position(lower(v) in lg) > 0, 'info', '');
    end loop;
  end if;
  if coalesce(p_crit->>'disponible_avant','') <> '' then mx := mx + 1;
    ok := coalesce(nullif(p_prof->>'disponible_le','')::date, current_date) <= (p_crit->>'disponible_avant')::date; if ok then n := n + 1; end if;
    d := d || json_build_object('c', 'Disponible avant le ' || to_char((p_crit->>'disponible_avant')::date, 'DD/MM/YYYY'), 'ok', ok, 'info', coalesce(p_prof->>'disponible_le','immédiate')); end if;
  return json_build_object('score', n, 'max', mx, 'details', to_json(d));
end $$;

-- Candidats pour le recruteur : priorité réseau, puis correspondance, puis ancienneté
create or replace function cc_offre_candidats(p_tel text, p_code text, p_id bigint)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_o record; v_ok boolean := false;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_o from cc_offres where id = p_id; if v_o.id is null then return '[]'::json; end if;
  if v_o.entreprise_id is not null then v_ok := exists (select 1 from cc_entreprises where id = v_o.entreprise_id and telephone = v_tel and code = upper(trim(coalesce(p_code,''))));
  elsif v_o.membre_id is not null then v_ok := exists (select 1 from cc_membres where id = v_o.membre_id and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel)); end if;
  if not v_ok then return '[]'::json; end if;
  return (
    with c as (
      select c.*, s.cv_url as s_cv,
        -- profil : fiche stagiaire (du stagiaire ou du membre), sinon fiche membre, complété par le profil saisi
        (coalesce(c.profil, '{}'::jsonb) || coalesce(
           case when s.id is not null then jsonb_build_object('ville', s.ville, 'niveau', s.niveau, 'logiciels', s.logiciels, 'disponible_le', s.disponible_le) end,
           case when m.id is not null then jsonb_build_object('ville', m.ville, 'niveau', coalesce(nullif(c.profil->>'niveau',''), ''), 'logiciels', coalesce(c.profil->>'logiciels', m.specialite, '')) end,
           '{}'::jsonb) || coalesce(c.profil, '{}'::jsonb)) as prof
      from cc_candidatures c
      left join cc_membres m on m.id = c.membre_id
      left join lateral (select * from cc_stagiaires s where (s.id = c.stagiaire_id) or (c.membre_id is not null and s.membre_id = c.membre_id and s.publie) order by s.maj_le desc limit 1) s on true
      where c.offre_id = p_id),
    cc as (select c.*, cc_correspondance(v_o.criteres, c.prof) as corr from c)
    select coalesce(json_agg(json_build_object('nom', nom, 'telephone', telephone, 'email', email, 'origine', origine, 'quand', quand,
             'a_jour', (membre_id is not null and cc_membre_a_jour(membre_id)), 'cv_url', coalesce(s_cv, ''), 'profil', prof, 'corr', corr)
           order by case origine when 'membre' then 1 when 'stagiaire' then 2 else 3 end, (corr->>'score')::int desc, quand asc), '[]'::json) from cc);
end $$;
