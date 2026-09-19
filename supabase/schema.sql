-- ============================================================
-- ComptaConnect — à coller dans UN PROJET SUPABASE EXISTANT
-- (Supabase → SQL Editor → coller → Run)
--
-- Toutes les tables sont préfixées « cc_ » : elles cohabitent avec
-- les autres applications du projet SANS rien modifier ni écraser.
-- Aucune création de troisième projet n'est nécessaire.
-- ============================================================


create table if not exists cc_membres (
  id bigserial primary key,
  code text unique not null,
  nom text not null,
  telephone text default '',
  ville text default '',
  specialite text default '',
  email text default '',
  cotisation integer default 5000,
  date_adhesion text default '',
  actif boolean default true,
  exonere boolean default false
);

create table if not exists cc_paiements (
  id bigserial primary key,
  date date not null default current_date,
  montant integer not null,
  canal text default '',
  expediteur text default '',
  telephone text default '',
  libelle text default '',
  mois text default '',
  membre_id bigint references cc_membres(id) on delete set null,
  statut text default 'NON_RAPPROCHE',
  methode text default 'aucun'
);

create table if not exists cc_settings (
  cle text primary key,
  valeur text default ''
);

-- Sécurité : lecture publique (page membre), écriture réservée au trésorier connecté
alter table cc_membres  enable row level security;
alter table cc_paiements enable row level security;
alter table cc_settings enable row level security;

drop policy if exists "lecture publique cc_membres" on cc_membres;
create policy "lecture publique cc_membres" on cc_membres for select using (true);
drop policy if exists "ecriture tresorier cc_membres" on cc_membres;
create policy "ecriture tresorier cc_membres" on cc_membres for all to authenticated using (true) with check (true);

drop policy if exists "lecture publique cc_paiements" on cc_paiements;
create policy "lecture publique cc_paiements" on cc_paiements for select using (true);
drop policy if exists "ecriture tresorier cc_paiements" on cc_paiements;
create policy "ecriture tresorier cc_paiements" on cc_paiements for all to authenticated using (true) with check (true);

drop policy if exists "lecture publique cc_settings" on cc_settings;
create policy "lecture publique cc_settings" on cc_settings for select using (true);
drop policy if exists "ecriture tresorier cc_settings" on cc_settings;
create policy "ecriture tresorier cc_settings" on cc_settings for all to authenticated using (true) with check (true);

-- Réglages du réseau (extraits du relevé officiel de juin 2026)
insert into cc_settings (cle, valeur) values
  ('reseau', 'ComptaConnect'),
  ('slogan', 'Le réseau des professionnels de la comptabilité'),
  ('cotisation', '5000'),
  ('jour_echeance', '10'),
  ('tresorier', 'Cabinet GSC — Basile EKLOU'),
  ('tresorier_tel', '+225 05 55 99 20 04'),
  ('contact_email', 'supportcomptaconnect@gmail.com'),
  ('site_web', 'www.comptaconnect.com'),
  ('wave_numero', ''), ('om_numero', ''), ('mtn_numero', ''),
  ('instructions', '')
on conflict (cle) do nothing;

-- ============================================================
-- Les 80 cc_membres réels du relevé Chariow de juin 2026
-- ============================================================
insert into cc_membres (code, nom, telephone, ville, cotisation, date_adhesion) values
  ('001', 'Gbahonnon Josée-therese Oraga', '', 'Côte d''Ivoire', 5000, '2026-06-10'),
  ('002', 'Aminata Fadiga', '', 'Côte d''Ivoire', 5000, '2026-06-10'),
  ('003', 'Ahoua Koné', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('004', 'Estelle Kabie', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('005', 'RACHELLE KOFFI', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('006', 'Nabil DOREGO', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('007', 'hermann montime', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('008', 'Kouadio N''guettia Guy Roger KRA', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('009', 'Frédéric Male', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('010', 'Koffi sylvain Assemian', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('011', 'KAFOUGOUNAN KONATE', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('012', 'Amenan Marceline Kouadio épouse Madou', '', 'Côte d''Ivoire', 5000, '2026-06-11'),
  ('013', 'EKEPE ANGE DESIRE N’GUESSAN', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('014', 'Barrahaicha Coulibaly', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('015', 'WILFRIED EVRARD ZAGLOLE', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('016', 'Ange Richard YAPO', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('017', 'Nacissé DIABY', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('018', 'JOSEE JUDITH BLE EPSE DANHO', '', 'Côte d''Ivoire', 5000, '2026-06-12'),
  ('019', 'YAO CLOVIS BOKA', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('020', 'RUPHIN GBAHO', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('021', 'TIEGBE KONE', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('022', 'Koffi Yao', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('023', 'Diby Consulting', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('024', 'Eugène Kouadja', '', 'Côte d''Ivoire', 5000, '2026-06-13'),
  ('025', 'Wende Thierry', '', 'Côte d''Ivoire', 5000, '2026-06-14'),
  ('026', 'Kouabenan Stéphane Djaban', '', 'Côte d''Ivoire', 5000, '2026-06-14'),
  ('027', 'Kan Enos Kouakou', '', 'Côte d''Ivoire', 5000, '2026-06-14'),
  ('028', 'YAO STÉPHANE KOUAKOU', '', 'Côte d''Ivoire', 5000, '2026-06-14'),
  ('029', 'Fabrice Sanou', '', 'Burkina Faso', 5000, '2026-06-14'),
  ('030', 'Elsa Yao', '', 'Côte d''Ivoire', 5000, '2026-06-14'),
  ('031', 'Valerie Konan', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('032', 'Roselyne ABEU', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('033', 'Djifa AGBODZA', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('034', 'Gnoudjibi Josiane Guireoulou épouse Diomande', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('035', 'TCHANGUE BANAME SARTCHI', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('036', 'Lacine Konate', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('037', 'Noba Jean Eudes Able', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('038', 'SORO KASSOUM', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('039', 'Sebastien Diomande', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('040', 'Vincent KOUASSI', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('041', 'Mariame Diomandé', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('042', 'KOUADIO JEAN BAPTISTE KOFFI', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('043', 'Sarah Soumahoro', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('044', 'Fatime Traore', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('045', 'Armand Kouakou KOUAKOU', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('046', 'Kouassi Gabin ASSRI', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('047', 'Kouakou kisito Yao', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('048', 'Diakaridia Lassine Doumbia', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('049', 'Remi KOFFI', '', 'Côte d''Ivoire', 5000, '2026-06-15'),
  ('050', 'Sonia Zagro', '', 'Côte d''Ivoire', 5000, '2026-06-16'),
  ('051', 'Sylvestre Kouadio Kouassi', '', 'Côte d''Ivoire', 5000, '2026-06-17'),
  ('052', 'Hadja Khady Diaby', '', 'Côte d''Ivoire', 5000, '2026-06-17'),
  ('053', 'TANO KOUADIO ARISTIDE', '', 'Côte d''Ivoire', 5000, '2026-06-18'),
  ('054', 'N''DA KOUAME CHRISTIAN DE SAINT ANGE KOFFI', '', 'Côte d''Ivoire', 5000, '2026-06-18'),
  ('055', 'Konan Delphin Koffi', '', 'Côte d''Ivoire', 5000, '2026-06-18'),
  ('056', 'Roger Pacome Meledje', '', 'Côte d''Ivoire', 5000, '2026-06-19'),
  ('057', 'Gnepa Guy', '', 'Côte d''Ivoire', 5000, '2026-06-19'),
  ('058', 'Aboubakar Coulibaly', '', 'Côte d''Ivoire', 5000, '2026-06-20'),
  ('059', 'Mamadi OUEDRAOGO', '', 'Côte d''Ivoire', 5000, '2026-06-21'),
  ('060', 'N''cho Severin N''cho', '', 'Côte d''Ivoire', 5000, '2026-06-22'),
  ('061', 'YAPO BRICE', '', 'Côte d''Ivoire', 5000, '2026-06-23'),
  ('062', 'Henri-Michel Meaka', '', 'Côte d''Ivoire', 5000, '2026-06-23'),
  ('063', 'SARAH -ANGE PARIENTE BOSSOMAH EBOUKO EPSE ABOA', '', 'Côte d''Ivoire', 5000, '2026-06-24'),
  ('064', 'BI TAH JOSEPH KOHOU', '', 'Côte d''Ivoire', 5000, '2026-06-26'),
  ('065', 'BINTOU KONATE', '', 'Côte d''Ivoire', 5000, '2026-06-28'),
  ('066', 'Francia Mouk', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('067', 'N''DA RAPHAËL-PARFAIT ALLiCO', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('068', 'N''koumo Clotilde sabina Ouali', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('069', 'ALI KAMAGATE', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('070', 'Olivier Kodjo', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('071', 'Ismail Sanogo', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('072', 'WANG NI ISAAC ADJAI', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('073', 'Laura Pohe', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('074', 'Grace Tatiana BOUIN', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('075', 'Daniel YAPI', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('076', 'Flaure KOUASSI', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('077', 'Marie Pascaline Dignayo TOURE', '', 'Côte d''Ivoire', 5000, '2026-06-30'),
  ('078', 'ATIOTA ANGE-PATRICK KAWEA', '', 'Côte d''Ivoire', 5000, '2026-07-01'),
  ('079', 'Kouadio Sébastien Kouame', '', 'Côte d''Ivoire', 5000, '2026-07-08'),
  ('080', 'Kouadio Stephane', '', 'Côte d''Ivoire', 5000, '2026-07-11')
on conflict (code) do nothing;

-- Les 80 cotisations de juin 2026 déjà encaissées via Chariow (historique)
insert into cc_paiements (date, montant, canal, expediteur, telephone, libelle, mois, membre_id, statut, methode)
select p.date, p.montant, 'Chariow (relevé importé)', p.expediteur, p.telephone, p.libelle, p.mois,
       (select id from cc_membres m where m.code = mm.code), 'RAPPROCHE', 'manuel'
from (values
  ('2026-06-10', 5000, 'Gbahonnon Josée-therese Oraga', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '001'),
  ('2026-06-10', 5000, 'Aminata Fadiga', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '002'),
  ('2026-06-11', 5000, 'Ahoua Koné', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '003'),
  ('2026-06-11', 5000, 'Estelle Kabie', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '004'),
  ('2026-06-11', 5000, 'RACHELLE KOFFI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '005'),
  ('2026-06-11', 5000, 'Nabil DOREGO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '006'),
  ('2026-06-11', 5000, 'hermann montime', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '007'),
  ('2026-06-11', 5000, 'Kouadio N''guettia Guy Roger KRA', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '008'),
  ('2026-06-11', 5000, 'Frédéric Male', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '009'),
  ('2026-06-11', 5000, 'Koffi sylvain Assemian', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '010'),
  ('2026-06-11', 5000, 'KAFOUGOUNAN KONATE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '011'),
  ('2026-06-11', 5000, 'Amenan Marceline Kouadio épouse Madou', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '012'),
  ('2026-06-12', 5000, 'EKEPE ANGE DESIRE N’GUESSAN', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '013'),
  ('2026-06-12', 5000, 'Barrahaicha Coulibaly', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '014'),
  ('2026-06-12', 5000, 'WILFRIED EVRARD ZAGLOLE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '015'),
  ('2026-06-12', 5000, 'Ange Richard YAPO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '016'),
  ('2026-06-12', 5000, 'Nacissé DIABY', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '017'),
  ('2026-06-12', 5000, 'JOSEE JUDITH BLE EPSE DANHO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '018'),
  ('2026-06-13', 5000, 'YAO CLOVIS BOKA', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '019'),
  ('2026-06-13', 5000, 'RUPHIN GBAHO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '020'),
  ('2026-06-13', 5000, 'TIEGBE KONE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '021'),
  ('2026-06-13', 5000, 'Koffi Yao', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '022'),
  ('2026-06-13', 5000, 'Diby Consulting', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '023'),
  ('2026-06-13', 5000, 'Eugène Kouadja', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '024'),
  ('2026-06-14', 5000, 'Wende Thierry', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '025'),
  ('2026-06-14', 5000, 'Kouabenan Stéphane Djaban', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '026'),
  ('2026-06-14', 5000, 'Kan Enos Kouakou', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '027'),
  ('2026-06-14', 5000, 'YAO STÉPHANE KOUAKOU', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '028'),
  ('2026-06-14', 5000, 'Fabrice Sanou', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '029'),
  ('2026-06-14', 5000, 'Elsa Yao', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '030'),
  ('2026-06-15', 5000, 'Valerie Konan', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '031'),
  ('2026-06-15', 5000, 'Roselyne ABEU', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '032'),
  ('2026-06-15', 5000, 'Djifa AGBODZA', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '033'),
  ('2026-06-15', 5000, 'Gnoudjibi Josiane Guireoulou épouse Diomande', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '034'),
  ('2026-06-15', 5000, 'TCHANGUE BANAME SARTCHI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '035'),
  ('2026-06-15', 5000, 'Lacine Konate', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '036'),
  ('2026-06-15', 5000, 'Noba Jean Eudes Able', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '037'),
  ('2026-06-15', 5000, 'SORO KASSOUM', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '038'),
  ('2026-06-15', 5000, 'Sebastien Diomande', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '039'),
  ('2026-06-15', 5000, 'Vincent KOUASSI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '040'),
  ('2026-06-15', 5000, 'Mariame Diomandé', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '041'),
  ('2026-06-15', 5000, 'KOUADIO JEAN BAPTISTE KOFFI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '042'),
  ('2026-06-15', 5000, 'Sarah Soumahoro', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '043'),
  ('2026-06-15', 5000, 'Fatime Traore', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '044'),
  ('2026-06-15', 5000, 'Armand Kouakou KOUAKOU', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '045'),
  ('2026-06-15', 5000, 'Kouassi Gabin ASSRI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '046'),
  ('2026-06-15', 5000, 'Kouakou kisito Yao', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '047'),
  ('2026-06-15', 5000, 'Diakaridia Lassine Doumbia', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '048'),
  ('2026-06-15', 5000, 'Remi KOFFI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '049'),
  ('2026-06-16', 5000, 'Sonia Zagro', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '050'),
  ('2026-06-17', 5000, 'Sylvestre Kouadio Kouassi', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '051'),
  ('2026-06-17', 5000, 'Hadja Khady Diaby', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '052'),
  ('2026-06-18', 5000, 'TANO KOUADIO ARISTIDE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '053'),
  ('2026-06-18', 5000, 'N''DA KOUAME CHRISTIAN DE SAINT ANGE KOFFI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '054'),
  ('2026-06-18', 5000, 'Konan Delphin Koffi', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '055'),
  ('2026-06-19', 5000, 'Roger Pacome Meledje', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '056'),
  ('2026-06-19', 5000, 'Gnepa Guy', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '057'),
  ('2026-06-20', 5000, 'Aboubakar Coulibaly', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '058'),
  ('2026-06-21', 5000, 'Mamadi OUEDRAOGO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '059'),
  ('2026-06-22', 5000, 'N''cho Severin N''cho', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '060'),
  ('2026-06-23', 5000, 'YAPO BRICE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '061'),
  ('2026-06-23', 5000, 'Henri-Michel Meaka', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '062'),
  ('2026-06-24', 5000, 'SARAH -ANGE PARIENTE BOSSOMAH EBOUKO EPSE ABOA', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '063'),
  ('2026-06-26', 5000, 'BI TAH JOSEPH KOHOU', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '064'),
  ('2026-06-28', 5000, 'BINTOU KONATE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '065'),
  ('2026-06-30', 5000, 'Francia Mouk', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '066'),
  ('2026-06-30', 5000, 'N''DA RAPHAËL-PARFAIT ALLiCO', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '067'),
  ('2026-06-30', 5000, 'N''koumo Clotilde sabina Ouali', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '068'),
  ('2026-06-30', 5000, 'ALI KAMAGATE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '069'),
  ('2026-06-30', 5000, 'Olivier Kodjo', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '070'),
  ('2026-06-30', 5000, 'Ismail Sanogo', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '071'),
  ('2026-06-30', 5000, 'WANG NI ISAAC ADJAI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '072'),
  ('2026-06-30', 5000, 'Laura Pohe', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '073'),
  ('2026-06-30', 5000, 'Grace Tatiana BOUIN', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '074'),
  ('2026-06-30', 5000, 'Daniel YAPI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '075'),
  ('2026-06-30', 5000, 'Flaure KOUASSI', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '076'),
  ('2026-06-30', 5000, 'Marie Pascaline Dignayo TOURE', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '077'),
  ('2026-07-01', 5000, 'ATIOTA ANGE-PATRICK KAWEA', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '078'),
  ('2026-07-08', 5000, 'Kouadio Sébastien Kouame', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '079'),
  ('2026-07-11', 5000, 'Kouadio Stephane', '', 'Import relevé Chariow — prélevé 750 FCFA, net 4250 FCFA', '2026-06', '080')
) as p(date, montant, expediteur, telephone, libelle, mois, code)
join cc_membres mm on mm.code = p.code
where not exists (select 1 from cc_paiements x where x.libelle = p.libelle);
