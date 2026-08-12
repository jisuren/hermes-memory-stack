# Hermes Memory Stack — Modules mémoire pour agents Hermes

> Documentation autonome pour **Honcho** et **OpenViking**.
> Deux services indépendants, chacun peut être installé seul.
> Sans secrets, sans identifiants réels — prêt à cloner.

---

## Sommaire

- [À propos](#à-propos)
- [Module A — Honcho (mémoire conversationnelle)](#module-a--honcho)
- [Module B — OpenViking (base de connaissances)](#module-b--openviking)
- [Usage combiné](#usage-combiné)
- [Dépannage](#dépannage)

---

## À propos

```
┌────────────────────────────────────────────────────┐
│                  Hermes Agent                       │
├──────────────────────┬─────────────────────────────┤
│   Honcho             │   OpenViking                │
│   (conversations)    │   (documents techniques)    │
│   :8001              │   :1933                      │
│   Docker (4 ctnrs)   │   Service systemd            │
│   PostgreSQL+pgvector│   LevelDB+HNSW vectoriel     │
└──────────────────────┴─────────────────────────────┘
```

**Honcho** et **OpenViking sont deux services totalement indépendants.** Vous pouvez :
- Installer Honcho seul → mémoire conversationnelle
- Installer OpenViking seul → RAG documentaire
- Installer les deux → stack mémoire complète

Chaque module ci-dessous **part de zéro** et ne suppose rien de l'autre.

---

# Module A — Honcho

> Mémoire conversationnelle cross-session. Stocke les échanges, construit un profil utilisateur (peer card), et répond aux questions sur ce qui a été dit avant.

## Architecture

```
┌────────────────────────────────┐
│         Docker Compose          │
│  ┌─────────┐  ┌──────────────┐ │
│  │ honcho- │  │ honcho-      │ │
│  │ api     │  │ database     │ │
│  │ :8001   │  │ pgvector:5433│ │
│  └────┬────┘  └──────────────┘ │
│       │       ┌──────────────┐ │
│       │       │ honcho-      │ │
│       ├──────►│ deriver      │ │
│       │       │ (worker LLM) │ │
│       │       └──────────────┘ │
│       │       ┌──────────────┐ │
│       │       │ honcho-redis │ │
│       │       │ cache:6380   │ │
│       │       └──────────────┘ │
└───────┼────────────────────────┘
        │
┌───────▼────────────────────────┐
│        Hermes Agent             │
│  memory.provider = honcho      │
│  ~/.hermes/honcho.json         │
└────────────────────────────────┘
```

## Prérequis

- **Docker + Docker Compose** (ou Docker Compose plugin)
- **Python 3.10+** avec `pip`
- **~2 Go RAM** pour la stack
- **Une clé API LLM** (DeepSeek, OpenRouter, OpenAI, OpenCode Go, etc.)
- *(Optionnel)* **Une clé API OpenAI** pour les embeddings

## Installation

### 1. Cloner Honcho

```bash
cd /opt
git clone https://github.com/plastic-labs/honcho.git
cd honcho

# Copier le fichier Compose
cp docker-compose.yml{.example,}
```

### 2. Port-shifter (fortement recommandé)

Les ports par défaut (8000, 5432, 6379) sont souvent déjà utilisés. La convention est de décaler vers 8001/5433/6380 :

```bash
sed -i 's/"127.0.0.1:8000:8000"/"127.0.0.1:8001:8000"/' docker-compose.yml
sed -i 's/"127.0.0.1:5432:5432"/"127.0.0.1:5433:5432"/' docker-compose.yml
sed -i 's/"127.0.0.1:6379:6379"/"127.0.0.1:6380:6379"/' docker-compose.yml
```

### 3. Créer le fichier `.env`

Fichier : `/opt/honcho/.env`

```ini
# === LLM Provider : DeepSeek (transport OpenAI-compatible) ===
# Honcho supporte DeepSeek via son transport "openai" : la clé DeepSeek se met
# dans LLM_OPENAI_API_KEY et chaque module pointe vers l'API officielle avec
# MODEL_CONFIG__OVERRIDES__BASE_URL.
LLM_OPENAI_API_KEY=<VOTRE_CLE_API_DEEPSEEK>

# === Embeddings (OpenAI uniquement pour l'instant) ===
OPENAI_API_KEY=<VOTRE_CLE_API_OPENAI>

# === Modèles : DeepSeek V4 — API officielle https://api.deepseek.com ===
# Deriver — transforme les messages en observations
DERIVER_MODEL_CONFIG__MODEL=deepseek-v4-pro
DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
DERIVER_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE=json_object
DERIVER_FLUSH_ENABLED=true

# Dialectic — synthèse mémoire interrogée par l'agent (1 bloc par niveau)
DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL=deepseek-v4-pro
DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL=deepseek-v4-pro
DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL=deepseek-v4-pro
DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL=deepseek-v4-pro
DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1

# Dreamer — consolidation périodique en peer cards
DREAM_DEDUCTION_MODEL_CONFIG__MODEL=deepseek-v4-pro
DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
DREAM_DEDUCTION_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE=json_object
DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT=openai

# Summary — résumés de session
SUMMARY_MODEL_CONFIG__MODEL=deepseek-v4-pro
SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1

# Cache
CACHE_ENABLED=true
```

> ✅ **DeepSeek est supporté nativement par Honcho** (transport OpenAI-compatible). Il suffit de mettre la clé DeepSeek dans `LLM_OPENAI_API_KEY` et de pointer `OVERRIDES__BASE_URL` vers `https://api.deepseek.com/v1` — mécanisme documenté dans le `.env.template` officiel pour tous les providers OpenAI-compatibles (OpenRouter, etc.).
>
> ⚠️ **DeepSeek ne supporte pas `json_schema`.** La variable `STRUCTURED_OUTPUT_MODE=json_object` est OBLIGATOIRE pour que le deriver fonctionne. Sans ça, le deriver tourne mais génère 0 observations avec le warning : `Structured output via json_schema rejected by model`.

### 4. Lancer la stack Docker

```bash
cd /opt/honcho
docker compose up -d --build

# Vérifier — 4 containers "Up" (api, database, redis, deriver)
docker ps --format "table {{.Names}}\t{{.Status}}" | grep honcho

# Vérifier l'API
curl -s http://localhost:8001/health
# → {"status":"ok"}
```

### 5. Installer le SDK Python

```bash
pip install honcho-ai

# Vérifier qu'il n'y a PAS de conflit avec le package "honcho"
pip list | grep honcho
# → Doit montrer "honcho-ai", PAS "honcho" (le process manager Foreman)
# Si conflit : pip uninstall honcho -y && pip install honcho-ai --force-reinstall
```

### 6. Configurer `honcho.json`

Fichier : `~/.hermes/honcho.json`

```json
{
  "baseUrl": "http://localhost:8001",
  "hosts": {
    "hermes": {
      "enabled": true,
      "aiPeer": "<NOM_AGENT>",
      "peerName": "<NOM_UTILISATEUR>",
      "workspace": "hermes",
      "sessionStrategy": "global"
    }
  },
  "contextTokens": 2000,
  "recallMode": "hybrid",
  "writeFrequency": "turn",
  "messageMaxChars": 25000,
  "dialecticReasoningLevel": "low"
}
```

**Clés importantes :**

| Clé | Rôle | Valeur typique |
|-----|------|----------------|
| `aiPeer` | Comment Honcho appelle l'agent | `nom-agent` |
| `peerName` | Comment Honcho appelle l'utilisateur | `prenom` |
| `workspace` | Base de données isolée | `hermes` |
| `recallMode` | `hybrid` = auto-injection + outils, `context` = auto-injection seule, `tools` = outils seuls |
| `writeFrequency` | `turn` = écrit à chaque échange, `async` = batch |
| `dialecticReasoningLevel` | `low`/`medium`/`high`/`max` — profondeur de raisonnement |

### 7. Activer Honcho comme provider mémoire

```bash
hermes config set memory.provider honcho

# Vérifier
grep -A 3 '^memory:' ~/.hermes/config.yaml | grep 'provider:'
# → provider: honcho

# Redémarrer le gateway Hermes
systemctl restart hermes-gateway
```

### 8. Multi-profile Hermes

Chaque profil Hermes (`-p monprofil`) nécessite **deux choses** :

**a)** Un host block dans `honcho.json` :
```json
"hermes.monprofil": {
  "enabled": true,
  "aiPeer": "<NOM_AGENT>",
  "peerName": "<NOM_UTILISATEUR>",
  "workspace": "hermes",
  "sessionStrategy": "global"
}
```

**b)** `memory.provider: honcho` dans `~/.hermes/profiles/monprofil/config.yaml`

> ⚠️ **Sans host block, les valeurs racines sont utilisées mais `aiPeer`/`peerName`/`workspace` sont absents** → le dialectic reasoning et les peer cards sont désactivés silencieusement.

### Vérification

```bash
# Docker
docker ps --format "table {{.Names}}\t{{.Status}}" | grep honcho
# → 4 containers Up (healthy)

# API
curl -s http://localhost:8001/health
# → {"status":"ok"}

# Provider Hermes
grep 'provider: honcho' ~/.hermes/config.yaml

# SDK (optionnel — test complet)
python3 -c "
from plugins.memory.honcho.client import HonchoClientConfig, get_honcho_client
cfg = HonchoClientConfig.from_global_config()
print(f'baseUrl: {cfg.base_url}')
print(f'enabled: {cfg.enabled}')
print(f'peerName: {cfg.peer_name}')
"
# → Tout s'affiche sans erreur
```

### Pièges Honcho (checklist)

| Piège | Symptôme | Solution |
|-------|----------|----------|
| `docker compose restart` ne recharge PAS `.env` | Modifications ignorées après restart | Utiliser `docker compose down <svc> && docker compose up -d <svc>` |
| `provider: ''` (vide) dans config.yaml | Stack OK mais 0 données dans Honcho | `sed -i "/^  provider: ''$/d" ~/.hermes/config.yaml` |
| DeepSeek + `json_schema` | Deriver tourne mais 0 observations | Ajouter `STRUCTURED_OUTPUT_MODE=json_object` |
| DeepSeek via API officielle | Modèles pointent vers OpenAI/OpenRouter | Mettre la clé dans `LLM_OPENAI_API_KEY` + `OVERRIDES__BASE_URL=https://api.deepseek.com/v1` sur chaque module |
| Dreamer utilise son propre modèle (`gpt-5.4-mini`) | Peer card null malgré deriver OK | Configurer `DREAM_DEDUCTION_MODEL_CONFIG__*` dans `.env` |
| `memory_enabled: false` | Honcho reçoit les données mais Hermes ne les lit pas | `hermes config set memory.memory_enabled true` |

---

# Module B — OpenViking

> Base de connaissances vectorielle. Stocke des documents techniques, les indexe sémantiquement, et permet la recherche par similarité (RAG).

## Architecture

```
┌──────────────────────────────────────┐
│          Service systemd              │
│          openviking.service           │
│  ┌────────────────────────────────┐  │
│  │         openviking-server       │  │
│  │  HTTP API :1933                │  │
│  │  RAGFS + LevelDB + HNSW index  │  │
│  └──────────┬─────────────────────┘  │
│             │                         │
│  ┌──────────▼─────────────────────┐  │
│  │  Workspace (filesystem)         │  │
│  │  ~/.openviking/workspace/      │  │
│  │  ├── viking/default/resources/ │  │
│  │  ├── vectordb/ (HNSW index)    │  │
│  │  └── _system/ (queue, config)  │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
         │
         ▼
┌──────────────────────────┐
│     Hermes Agent          │
│  Plugin OpenViking        │
│  Tools: viking_read,      │
│  viking_search,           │
│  viking_browse,           │
│  viking_remember          │
└──────────────────────────┘
```

## Prérequis

- **Python 3.10+** avec `pip`
- **~4 Go RAM** recommandés (selon taille de l'index)
- **Une clé API OpenAI** pour les embeddings (obligatoire — voir piège ci-dessous)
- Systemd (pour le service)
- *(Optionnel)* **clé API VLM** pour le résumé automatique

> ⚠️ **OpenCode Zen, DeepSeek et Xiaomi MiMo ne supportent PAS les embeddings.** Le seul provider compatible est OpenAI (Ollama local en alternative). L'endpoint `/v1/embeddings` d'OpenCode retourne 404.

## Installation

### 1. Installer le package

```bash
pip install openviking

# Si Ubuntu 24.04+ (PEP 668) :
pip3 install --break-system-packages --ignore-installed openviking
```

### 2. Définir la langue (OBLIGATOIRE)

```bash
ov language en
```

> Toutes les commandes `ov` refusent de fonctionner avant d'avoir défini la langue. À faire **immédiatement après l'install**.

### 3. Créer les fichiers de config

#### Config serveur : `~/.openviking/ov.conf`

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 1933,
    "workers": 2
  },
  "storage": {
    "workspace": "/root/.openviking/workspace"
  },
  "embedding": {
    "dense": {
      "api_base": "https://api.openai.com/v1",
      "api_key": "<VOTRE_CLE_API_EMBEDDINGS>",
      "provider": "openai",
      "model": "text-embedding-3-small",
      "dimension": 1536
    },
    "max_concurrent": 10
  }
}
```

> ⚠️ **`storage.workspace` est OBLIGATOIRE.** Sans cette clé, le serveur répond OK au healthcheck mais ignore tous les fichiers ajoutés.

**Choix du modèle d'embedding :**

| Modèle | Dimension | RAM (pour 6 500 fichiers) | Coût API |
|--------|-----------|--------------------------|----------|
| `text-embedding-3-large` | 3072 | ~6 Go | Élevé |
| `text-embedding-3-small` | 1536 | ~350 Mo | Faible |

→ Commencer par `text-embedding-3-small` (1536d). Ne pas changer la dimension après avoir indexé — le vectordb devient incompatible.

**Section VLM (optionnelle) :** retirez-la complètement si vous n'avez pas besoin de résumé sémantique automatique. OpenViking fonctionne sans VLM (pure recherche vectorielle).

#### Config CLI : `~/.openviking/ovcli.conf`

```json
{
  "server": "http://127.0.0.1:1933",
  "account": "default",
  "user": "<NOM_UTILISATEUR>",
  "agent": "hermes"
}
```

### 4. Créer le service systemd

Fichier : `/etc/systemd/system/openviking.service`

```ini
[Unit]
Description=OpenViking Memory Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/openviking-server --host 127.0.0.1 --port 1933
Restart=on-failure
RestartSec=10
MemoryMax=4G
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now openviking.service
```

> ⚠️ **`Restart=on-failure` (pas `Restart=always`).** Avec `Restart=always` + MemoryMax trop bas, le process OOM-kill et redémarre en boucle infinie. `Restart=on-failure` évite ça (OOM ≠ on-failure).
>
> ⚠️ **Ne PAS mettre `MemoryHigh`** — provoque un D-state (wchan `__mem_cgroup_handle_over_high`). Utiliser `MemoryMax` uniquement.

### 5. Ajouter la variable d'environnement pour Hermes

Le plugin OpenViking Hermes utilise `OPENVIKING_ENDPOINT` pour détecter le serveur :

```bash
# Dans le service systemd Hermes, ajouter :
Environment="OPENVIKING_ENDPOINT=http://127.0.0.1:1933"

# OU globalement :
echo 'OPENVIKING_ENDPOINT=http://127.0.0.1:1933' >> /etc/environment
```

### 6. Symlinks (si installé dans un venv)

```bash
ln -sf /usr/local/lib/hermes-agent/venv/bin/ov /usr/local/bin/ov
ln -sf /usr/local/lib/hermes-agent/venv/bin/openviking-server /usr/local/bin/openviking-server
```

### Utilisation de base

```bash
# Ajouter un document
ov add-resource /tmp/ma-doc.md --to viking://resources/categories/sujet.md

# Lire
ov read viking://resources/categories/sujet.md

# Recherche sémantique
ov find "ma question ici"

# Recherche texte exact
ov grep "mot précis"

# Naviguer l'arborescence
ov tree viking://resources

# Voir la queue de traitement
ov observer queue
```

### Vérification

```bash
# Service
systemctl is-active openviking
# → active

# API
curl -s http://127.0.0.1:1933/health
# → {"healthy":true}

# Plugin Hermes
python3 -c "
from plugins.memory.openviking import OpenVikingMemoryProvider
p = OpenVikingMemoryProvider()
print(f'OpenViking disponible: {p.is_available()}')
"
# → True
```

### Pièges OpenViking (checklist)

| Piège | Symptôme | Solution |
|-------|----------|----------|
| `storage.workspace` manquant dans ov.conf | Health OK mais toutes les données ignorées | Ajouter `"storage": { "workspace": "... }"` |
| `MemoryHigh` défini | Process en D-state, ne répond plus | Enlever `MemoryHigh`, garder `MemoryMax` |
| `Restart=always` + MemoryMax trop bas | OOM loop infini | Passer à `Restart=on-failure` |
| LevelDB LOCK après `kill -9` | Le serveur refuse de démarrer | `rm -f .../store/LOCK` + nettoyer queue |
| `ov` refuse toutes les commandes | Langue pas définie | `ov language en` |
| OpenCode Zen en provider embedding | 404 sur `/v1/embeddings` | Utiliser OpenAI direct |
| `ov mv` sur ressource chunkée | `[INTERNAL] Internal server error` | `ov rm` puis ajouter au bon endroit |
| VLM model `gpt-4-vision-preview` | 404 (déprécié par OpenAI) | Remplacer par `gpt-4o-mini` |

---

# Usage combiné

## Honcho + OpenViking

Les deux services sont indépendants, mais ils se complètent :

| Fonctionnalité | Honcho | OpenViking |
|---------------|--------|------------|
| « Qu'est-ce qu'on a dit la semaine dernière ? » | ✅ | ❌ |
| « Trouve-moi le guide sur Rust unsafe » | ❌ | ✅ |
| « Quels sont les hobbies de l'utilisateur ? » | ✅ (peer card) | ❌ |
| « Cherche dans la doc technique » | ❌ | ✅ |
| « Sauvegarde une info pour plus tard » | ✅ | ✅ |

**Ordre d'installation recommandé :** Honcho d'abord (mémoire conversationnelle critique), OpenViking ensuite (RAG documentaire).

## Outils Hermes quand Honcho est actif

| Outil | Rôle |
|-------|------|
| `honcho_profile` | Voir la peer card de l'utilisateur |
| `honcho_search` | Recherche sémantique mémoire |
| `honcho_reasoning` | Synthèse LLM (dialectic Q&A) |
| `honcho_context` | Contexte session actuelle |
| `honcho_conclude` | Sauvegarder un fait persistant |

## Outils Hermes quand OpenViking est actif

| Outil | Rôle |
|-------|------|
| `viking_read` | Lire un document |
| `viking_browse` | Naviguer l'arborescence |
| `viking_search` | Recherche sémantique |
| `viking_remember` | Sauvegarder un souvenir |

---

# Dépannage

## Problèmes Honcho

### Le deriver tourne mais ne produit aucune observation

```bash
# 1. Vérifier les logs
docker logs honcho-deriver-1 --tail 20 2>&1 | grep -iE "warn|error|structured_output"

# 2. Si warning "json_schema rejected" :
#    Ajouter dans .env puis recréer le container
DERIVER_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE=json_object

# 3. Recréer (restart ne suffit PAS)
docker compose down deriver && docker compose up -d deriver
```

### Honcho stack OK mais Hermes n'écrit pas dedans

```bash
# 1. Vérifier le provider
grep -A 3 '^memory:' ~/.hermes/config.yaml
# → Doit montrer "provider: honcho" (pas '')

# 2. Vérifier qu'il n'y a pas DEUX lignes provider:
grep -n 'provider:' ~/.hermes/config.yaml | grep -v 'open\|auto\|edge\|local\|fal'
# → Si deux lignes "provider: honcho" + "provider: ''", supprimer la vide

# 3. Vérifier memory_enabled
grep memory_enabled ~/.hermes/config.yaml
# → Doit être true
```

### Le peer card reste null

```bash
# 1. Vérifier que le dreamer tourne sur le bon modèle
docker exec honcho-deriver-1 env | grep DREAM_
# → Si vide, ajouter dans .env :
#    DREAM_DEDUCTION_MODEL_CONFIG__MODEL=deepseek-v4-pro
#    DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=https://api.deepseek.com/v1
#    DREAM_DEDUCTION_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE=json_object

# 2. Injection manuelle si urgent
python3 -c "
from honcho import Honcho
h = Honcho(base_url='http://localhost:8000', workspace_id='hermes')
h.peer('<aiPeer>').set_card(['Fait 1', 'Fait 2'])
"
```

## Problèmes OpenViking

### Le serveur est en état D (uninterruptible sleep)

```bash
# 1. Identifier
ps -p $(pgrep -f openviking-server) -o pid,state,wchan --no-headers
# → state=D, wchan=__mem_cgroup_handle_over_high

# 2. Corriger : enlever MemoryHigh du service systemd
#    (ne garder que MemoryMax)
sed -i '/MemoryHigh/d' /etc/systemd/system/openviking.service
systemctl daemon-reload

# 3. Tuer le process bloqué
pkill -9 -f openviking-server

# 4. Nettoyer les locks
rm -f /root/.openviking/workspace/vectordb/context/store/LOCK
rm -f /root/.openviking/workspace/_system/queue/queue.db-shm
rm -f /root/.openviking/workspace/_system/queue/queue.db-wal

# 5. Redémarrer
systemctl start openviking
```

### Le serveur OOM-kill en boucle

```bash
# 1. Augmenter MemoryMax dans le service
#    (compter ~3× la taille du répertoire vectordb)
du -sh /root/.openviking/workspace/vectordb/
# → Si 2 Go, MemoryMax=6G minimum

# 2. Passer en Restart=on-failure
sed -i 's/Restart=always/Restart=on-failure/' /etc/systemd/system/openviking.service
systemctl daemon-reload

# 3. Nettoyer la queue (qui a pu gonfler pendant les crashs)
sqlite3 /root/.openviking/workspace/_system/queue/queue.db \
  "DELETE FROM queue_messages WHERE status='pending';"
sqlite3 /root/.openviking/workspace/_system/queue/queue.db "VACUUM;"

# 4. Starter
systemctl start openviking
```

---

## Fichiers livrés avec ce guide

```
📁 configs/
   ├── honcho.json              → Config Hermes pour Honcho
   ├── honcho.env               → Variables d'env Docker
   ├── ov.conf                  → Config serveur OpenViking
   ├── ovcli.conf               → Config CLI OpenViking
   └── openviking.service       → Service systemd
📁 scripts/
   └── health-check.sh          → Script vérification autonome
📄 AI_SUMMARY.md                → Résumé pour IA (10 secondes)
```

> Tous les fichiers de config utilisent des `<PLACEHOLDERS>` — copier, remplacer, exécuter.
