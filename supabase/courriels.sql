-- File d'attente des publications à envoyer par e-mail (annonces, événements, offres…) et journal des envois
create table if not exists cc_courriels_file (
  cle text primary key,                 -- même clé que cc_notifies (annonce:12, evenement:4, offre:7…)
  titre text not null, corps text not null default '', url text not null default '/',
  cree_le timestamptz not null default now()
);
create table if not exists cc_courriels_envois (
  id bigserial primary key,
  dest text not null,                   -- adresse e-mail
  cles text[] not null,                 -- publications incluses
  quand timestamptz not null default now()
);
create index if not exists cc_courriels_envois_dest_idx on cc_courriels_envois(dest, quand desc);
alter table cc_courriels_file enable row level security; alter table cc_courriels_envois enable row level security;
revoke all on cc_courriels_file, cc_courriels_envois from anon, authenticated;
insert into cc_settings (cle, valeur) values ('courriel_publications', 'oui'), ('courriel_plafond_jour', '250') on conflict (cle) do nothing;
