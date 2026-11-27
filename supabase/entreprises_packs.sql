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
