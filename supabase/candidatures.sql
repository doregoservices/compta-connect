-- Candidatures nominatives : le recruteur voit qui a postulé et décide (poste pourvu / poursuivre) ; reprise automatique après un délai de gel
create table if not exists cc_candidatures (
  id bigserial primary key,
  offre_id bigint not null references cc_offres(id) on delete cascade,
  nom text not null default '', telephone text not null default '', email text not null default '',
  origine text not null default 'public',        -- membre | stagiaire | public
  membre_id bigint references cc_membres(id) on delete set null,
  stagiaire_id bigint references cc_stagiaires(id) on delete set null,
  notifie boolean not null default false,        -- recruteur prévenu (nouveautes.js)
  quand timestamptz not null default now()
);
create index if not exists cc_candidatures_offre_idx on cc_candidatures(offre_id, quand desc);
alter table cc_candidatures enable row level security;
drop policy if exists "tresorier cc_candidatures" on cc_candidatures;
create policy "tresorier cc_candidatures" on cc_candidatures for select to authenticated using (true);
grant select on cc_candidatures to authenticated; revoke all on cc_candidatures from anon;
alter table cc_offres add column if not exists pourvue boolean not null default false;
insert into cc_settings (cle, valeur) values ('offres_gel_h', '72') on conflict (cle) do nothing;

-- Postuler = candidature nominative (téléphone obligatoire) ; gèle la phase ; le gel expire après offres_gel_h
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
  update cc_offres set candidatures = candidatures + 1, maj_le = now(),
         fige_phase = case when fige_phase is null and v_t.phase in ('membres','stagiaires') then v_t.phase else fige_phase end,
         fige_le = case when fige_phase is null and v_t.phase in ('membres','stagiaires') then now() else fige_le end
    where id = p_id and publie and valide returning comment_postuler into v_c;
  return json_build_object('ok', v_c is not null, 'comment_postuler', coalesce(v_c, ''));
end $$;
drop function if exists cc_offre_postuler(bigint, text);
revoke all on function cc_offre_postuler(bigint, text, text, text) from public;
grant execute on function cc_offre_postuler(bigint, text, text, text) to anon, authenticated;

-- Reprise automatique : un gel plus vieux que offres_gel_h est levé (la phase suivante démarre), sauf si le recruteur a marqué « pourvue »
create or replace function cc_offres_lever_gels() returns int language plpgsql security definer set search_path = public as $$
declare d record; v_h int := coalesce(nullif((select valeur from cc_settings where cle='offres_gel_h'), '')::int, 72); n int;
begin
  select * into d from cc_offres_delais();
  update cc_offres set fige_phase = null, fige_le = null, maj_le = now(),
    valide_le = case when fige_phase = 'membres' then now() - (d.membres_h || ' hours')::interval else now() - ((d.membres_h + d.stagiaires_h) || ' hours')::interval end
    where fige_phase is not null and not pourvue and publie and v_h > 0 and fige_le < now() - (v_h || ' hours')::interval;
  get diagnostics n = row_count; return n;
end $$;
revoke all on function cc_offres_lever_gels() from public;

-- Décision du recruteur (entreprise : tel + code ; membre : tel) : 'pourvue' ferme l'offre, 'poursuivre' lève le gel
create or replace function cc_offre_decider(p_tel text, p_code text, p_id bigint, p_action text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g'); v_o record; v_ok boolean := false; d record;
begin
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;
  select * into v_o from cc_offres where id = p_id; if v_o.id is null then return json_build_object('ok', false); end if;
  if v_o.entreprise_id is not null then v_ok := exists (select 1 from cc_entreprises where id = v_o.entreprise_id and telephone = v_tel and code = upper(trim(coalesce(p_code,''))));
  elsif v_o.membre_id is not null then v_ok := exists (select 1 from cc_membres where id = v_o.membre_id and regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel)); end if;
  if not v_ok then return json_build_object('ok', false, 'motif', 'acces'); end if;
  if p_action = 'pourvue' then update cc_offres set pourvue = true, publie = false, maj_le = now() where id = p_id;
  elsif p_action = 'poursuivre' then select * into d from cc_offres_delais();
    update cc_offres set fige_phase = null, fige_le = null, maj_le = now(),
      valide_le = case when fige_phase = 'membres' then now() - (d.membres_h || ' hours')::interval when fige_phase = 'stagiaires' then now() - ((d.membres_h + d.stagiaires_h) || ' hours')::interval else valide_le end
      where id = p_id;
  else return json_build_object('ok', false, 'motif', 'action'); end if;
  return json_build_object('ok', true);
end $$;
revoke all on function cc_offre_decider(text, text, bigint, text) from public;
grant execute on function cc_offre_decider(text, text, bigint, text) to anon, authenticated;

-- Candidatures d'une offre pour son recruteur
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
            'cv_url', coalesce((select s.cv_url from cc_stagiaires s where s.id = c.stagiaire_id), '')) order by c.quand desc), '[]'::json) from cc_candidatures c where c.offre_id = p_id);
end $$;
revoke all on function cc_offre_candidats(text, text, bigint) from public;
grant execute on function cc_offre_candidats(text, text, bigint) to anon, authenticated;
