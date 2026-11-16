#!/bin/bash
# Sauvegarde quotidienne de la base ComptaConnect (+ photos) : /var/backups/comptaconnect, 30 jours conservés.
set -e
D=/var/backups/comptaconnect; mkdir -p "$D"; J=$(date +%F)
sudo -u postgres pg_dump -Fc comptaconnect > "$D/comptaconnect_$J.dump"
tar -czf "$D/photos_$J.tgz" -C /var/lib/comptaconnect photos
find "$D" -type f -mtime +30 -delete
echo "$(date -Is) sauvegarde ok $(du -sh $D/comptaconnect_$J.dump | cut -f1)" >> /var/log/comptaconnect-sauvegarde.log
