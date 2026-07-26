# Hermes Memory Stack — AI Summary (10s read)
> Pour une IA : architecture, dépendances, pièges.

## Architecture — 2 services indépendants

```
Honcho              ou              OpenViking
(mémoire conversationnelle)        (base de connaissances RAG)
:8001 / Docker 4 containers         :1933 / systemd
PostgreSQL + pgvector               LevelDB + HNSW vectoriel
```

- **Chacun peut être installé seul.**
- **Aucune dépendance entre les deux.**
- Hermes s'interface via `memory.provider` pour Honcho, plugin natif pour OpenViking.

## Honcho

4 containers Docker : `api` (:8001), `database` (pgvector, :5433), `redis` (:6380), `deriver` (worker LLM).

**Prérequis :**
- Docker + Compose, Python, ~2 Go RAM
- 1 clé API LLM (OpenRouter, OpenAI, OpenCode Go...)

**Install (résumé) :**
```bash
git clone https://github.com/plastic-labs/honcho.git → port-shift → .env → docker compose up -d --build
pip install honcho-ai → honcho.json → hermes config set memory.provider honcho
```

**Pièges critiques :**
- `docker compose restart` ne recharge PAS `.env` → utiliser `down && up -d`
- DeepSeek V4 nécessite `STRUCTURED_OUTPUT_MODE=json_object` (pas `json_schema`)
- `provider: ''` dans config.yaml → Honcho ignoré silencieusement
- `memory_enabled: false` bloque tout
- Le dreamer (peer cards) a son propre modèle → configurer `DREAM_DEDUCTION_MODEL_CONFIG__*`
- Double provider dans `config.yaml` : supprimer la ligne vide

## OpenViking

Service système unique : `openviking-server` HTTP sur :1933.

**Prérequis :**
- Python 3.10+, systemd, ~4 Go RAM
- 1 clé API **OpenAI** pour les embeddings (⚠️ seul provider compatible — pas OpenCode, pas DeepSeek)
- *(Optionnel)* clé VLM pour résumé automatique

**Install (résumé) :**
```bash
pip install openviking → ov language en → ov.conf + ovcli.conf → systemd → OPENVIKING_ENDPOINT dans env
```

**Pièges critiques :**
- `storage.workspace` manquant dans ov.conf → data ignorées silencieusement
- `MemoryHigh` = D-state. Utiliser `MemoryMax` uniquement.
- `Restart=always` + OOM = boucle infinie. Utiliser `Restart=on-failure`.
- Stale LOCK file après `kill -9` → le supprimer manuellement
- `ov` refuse toute commande si `ov language` pas fait en premier
- `text-embedding-3-large` (3072d) prend ~6 Go RAM vs `text-embedding-3-small` (1536d) ~350 Mo

## Fichiers de config

| Fichier | Service | Rôle |
|---------|---------|------|
| `~/.hermes/honcho.json` | Honcho | Configuration plugin Hermes |
| `~/.hermes/config.yaml` (memory.provider) | Honcho | Active Honcho comme provider |
| `/opt/honcho/.env` | Honcho | Clés LLM, modèles, paramètres Docker |
| `/opt/honcho/docker-compose.yml` | Honcho | Définition des 4 containers |
| `~/.openviking/ov.conf` | OpenViking | Config serveur (embedding, storage) |
| `~/.openviking/ovcli.conf` | OpenViking | Config CLI |
| `/etc/systemd/system/openviking.service` | OpenViking | Service systemd |

## Vérification

```bash
# Honcho
docker ps | grep honcho           # 4 Up
curl -s :8001/health              # {"status":"ok"}
grep 'provider: honcho' ~/.hermes/config.yaml

# OpenViking
systemctl is-active openviking     # active
curl -s :1933/health               # {"healthy":true}
python3 -c "from plugins.memory.openviking import OpenVikingMemoryProvider; p=OpenVikingMemoryProvider(); print(p.is_available())"
# → True
```
