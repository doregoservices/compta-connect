-- ============================================================
-- ComptaConnect — Parcours « nouveau membre » (adhésion en ligne)
-- À coller dans Supabase → SQL Editor → Run (rejouable sans danger)
-- ============================================================

-- 1) Réglages supplémentaires
insert into cc_settings (cle, valeur) values
  ('adhesion', '5000'),
  ('whatsapp_lien', ''),
  ('bienvenue', 'Bienvenue dans le réseau ComptaConnect ! Rejoignez le groupe WhatsApp ci-dessous et enregistrez le numéro du trésorier.')
on conflict (cle) do nothing;

-- 2) Un nouveau membre s'inscrit lui-même (anonyme) : créé INACTIF jusqu'au paiement.
--    Si le téléphone existe déjà, on renvoie le code existant (pas de doublon).
create or replace function cc_adherer(p_nom text, p_tel text, p_ville text default '', p_email text default '', p_specialite text default '')
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  v_code text;
  v_id bigint;
  v_existant record;
begin
  if length(trim(coalesce(p_nom,''))) < 3 then
    raise exception 'Nom trop court';
  end if;
  if length(v_tel) < 8 then
    raise exception 'Numéro de téléphone invalide';
  end if;
  -- forme locale 10 chiffres (07xxxxxxxx) ou internationale 225xxxxxxxxxx
  if length(v_tel) = 13 and v_tel like '225%' then v_tel := substr(v_tel, 4); end if;

  select id, code, actif into v_existant from cc_membres
    where regexp_replace(telephone, '\D', '', 'g') in (v_tel, '225' || v_tel) limit 1;
  if found then
    return json_build_object('code', v_existant.code, 'id', v_existant.id, 'actif', v_existant.actif, 'existant', true);
  end if;

  select lpad((coalesce(max(code::int), 0) + 1)::text, 3, '0') into v_code
    from cc_membres where code ~ '^\d+$';

  insert into cc_membres (code, nom, telephone, ville, specialite, email, cotisation, date_adhesion, actif, exonere)
  values (v_code, trim(p_nom), v_tel, coalesce(p_ville,''), coalesce(p_specialite,''), coalesce(p_email,''),
          coalesce((select valeur::int from cc_settings where cle='cotisation'), 5000),
          to_char(current_date, 'YYYY-MM-DD'), false, false)
  returning id into v_id;

  return json_build_object('code', v_code, 'id', v_id, 'actif', false, 'existant', false);
end $$;

revoke all on function cc_adherer(text,text,text,text,text) from public;
grant execute on function cc_adherer(text,text,text,text,text) to anon, authenticated;

-- 3) Dès qu'un paiement est rapproché à un membre, le membre devient actif
--    (valable pour le rapprochement manuel, l'import de relevé ET le futur webhook CinetPay).
create or replace function cc_activer_apres_paiement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'RAPPROCHE' and new.membre_id is not null then
    update cc_membres set actif = true where id = new.membre_id and actif = false;
  end if;
  return new;
end $$;

drop trigger if exists trg_cc_activer on cc_paiements;
create trigger trg_cc_activer after insert or update of statut, membre_id on cc_paiements
  for each row execute function cc_activer_apres_paiement();

-- 4) Le lien WhatsApp n'est remis QU'À un membre actif ayant au moins un paiement rapproché.
create or replace function cc_bienvenue(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_m record;
  v_nb int;
begin
  select * into v_m from cc_membres where code = lpad(p_code, 3, '0');
  if not found then return json_build_object('ok', false, 'motif', 'inconnu'); end if;
  select count(*) into v_nb from cc_paiements where membre_id = v_m.id and statut = 'RAPPROCHE';
  if not v_m.actif or v_nb = 0 then
    return json_build_object('ok', false, 'motif', 'attente');
  end if;
  return json_build_object('ok', true,
    'nom', v_m.nom,
    'whatsapp', (select valeur from cc_settings where cle='whatsapp_lien'),
    'message',  (select valeur from cc_settings where cle='bienvenue'),
    'tresorier', (select valeur from cc_settings where cle='tresorier'),
    'tresorier_tel', (select valeur from cc_settings where cle='tresorier_tel'));
end $$;

revoke all on function cc_bienvenue(text) from public;
grant execute on function cc_bienvenue(text) to anon, authenticated;
