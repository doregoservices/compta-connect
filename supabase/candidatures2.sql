-- Plus de gel après candidature : la priorité du réseau se joue dans les phases (membres 7 j, stagiaires 4 j) et dans l'ordre des candidats
update cc_settings set valeur = '168' where cle = 'offres_delai_membres_h' and valeur = '48';
update cc_settings set valeur = '96' where cle = 'offres_delai_stagiaires_h' and valeur = '48';
update cc_offres set fige_phase = null, fige_le = null where fige_phase is not null;

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

-- Candidats triés pour le recruteur : membres (priorité réseau), puis stagiaires inscrits, puis public ; à date égale, le plus ancien d'abord
create or replace function cc_offre_candidats(p_tel text, p_code text, p_id bigint)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_o record; v_ok boolean := false;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_o from cc_offres where id = p_id; if v_o.id is null then return '[]'::json; end if;
  if v_o.entreprise_id is not null then v_ok := exists (select 1 from cc_entreprises where id = v_o.entreprise_id and telephone = v_tel and code = upper(trim(coalesce(p_code,''))));
  elsif v_o.membre_id is not null then v_ok := exists (select 1 from cc_membres where id = v_o.membre_id and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel)); end if;
  if not v_ok then return '[]'::json; end if;
  return (select coalesce(json_agg(json_build_object('nom', c.nom, 'telephone', c.telephone, 'email', c.email, 'origine', c.origine, 'quand', c.quand,
            'a_jour', (c.membre_id is not null and cc_membre_a_jour(c.membre_id)),
            'cv_url', coalesce((select s.cv_url from cc_stagiaires s where s.id = c.stagiaire_id), (select s.cv_url from cc_stagiaires s where s.membre_id = c.membre_id and s.publie limit 1), ''))
            order by case c.origine when 'membre' then 1 when 'stagiaire' then 2 else 3 end, c.quand asc), '[]'::json) from cc_candidatures c where c.offre_id = p_id);
end $$;
drop function if exists cc_offres_lever_gels();
