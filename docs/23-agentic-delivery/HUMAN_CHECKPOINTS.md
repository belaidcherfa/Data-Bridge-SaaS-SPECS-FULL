# Points de contrôle humains (propriétaire)

Statut : ACCEPTED 2026-09-28 · Référence : [ADR-018](../architecture/adr/ADR-018-agentic-delivery.md), [ORCHESTRATION](ORCHESTRATION.md) §8.

Ce document liste **tout ce que seul un humain peut faire**. Les agents préparent chaque action (commandes, plans, listes de contrôle) pour qu'elle prenne quelques minutes. Tant que les points H0 à H5 ne sont pas faits, `control.paused` reste à `true` et l'orchestrateur ne fait que réconcilier et produire des rapports.

## A. Avant de lancer les agents (une fois)

| # | Action | Pourquoi | Temps |
|---|---|---|---|
| **H0** | Passer le dépôt GitHub en **privé** (Settings → General → Danger Zone → Change visibility). | ADR-017 : aucun code produit ni identifiant réel dans un dépôt public. | 2 min |
| **H1** | Appliquer la protection de `main` : PR obligatoire, checks requis, merge queue (squash), pas de force push ; créer la règle de `delivery-ledger` (seule l'identité de l'orchestrateur pousse) ; créer les labels. Le script `tools/github/apply_rulesets.py` (AGT-004) le fait en une commande ; en attendant, suivre [ci-checks.md](../development/ci-checks.md). Committer toi-même `.github/CODEOWNERS` (les agents ne peuvent pas l'éditer). | Empêche tout merge non revu et protège l'état. | 15 min |
| **H2** | Créer une **GitHub App** (ou un compte machine) pour l'orchestrateur : droits contents/pull-requests/issues/actions en écriture sur ce seul dépôt. Installer la clé sur le serveur (jamais dans le dépôt). | Identité distincte, révocable, traçable. | 15 min |
| **H3** | Fournir le **serveur de livraison** (Ubuntu 24.04, 8–16 vCPU, 32–64 Go RAM, 250 Go SSD) et le **crédit Anthropic** (clé API d'un workspace dédié avec plafond de dépense mensuel, ou abonnement Claude). Lancer `tools/server/bootstrap.sh` puis `tools/server/doctor.sh` (AGT-001). | Exécution des modes A/B. | 1 h |
| **H4** | Fixer le **budget** : `control.daily_budget_usd` (défaut 400 USD/jour) et `usd_per_estimated_hour` (défaut 6) dans l'état ; plafond mensuel côté console Anthropic. | Borne la dépense ; l'orchestrateur s'arrête au plafond. | 5 min |
| **H5** | Choisir le **mode** : A (session interactive supervisée) pour la vague 0, puis B (boucle autonome sur le serveur) après le pilote de 48 h (AGT-003). Mettre `control.paused=false` avec une raison. | Démarrage. | 2 min |

## B. Dès que possible (débloque les couloirs infra et données)

| # | Action | Débloque | Temps |
|---|---|---|---|
| H6 | Créer/autoriser l'**AWS Organization** et les comptes (management, shared, dev, staging, prod), IAM Identity Center ; remplir `config/environments/{dev,staging,prod}.yaml` à partir des `*.example.yaml` (voir [config/README.md](../../config/README.md)) ; `make config-validate`. | INF-001 puis tout le couloir A1 infra | 2–4 h |
| H7 | Créer le compte **Snowflake DEV** (bac à sable) et les comptes centraux STAGING/PROD (ORGADMIN), puis le **test estate** (organisations T_A/T_B) dans les budgets D-32 (≤ 150 crédits/mois pour le test estate, ≤ 500 crédits/mois hors prod, ≤ 600 crédits ponctuels). | INF-008, INF-101, toutes les « live gates » Snowflake | 2 h |
| H8 | Domaine et DNS (zone Route 53), domaine d'envoi `notify.<domaine>` pour SES, demande de sortie du sandbox SES. | INF-006, GOV-006 | 1 h + délai AWS |
| H9 | Tenants IdP de test (Entra ID, Okta, Google) pour SAML/OIDC. | SEC-003 | 1 h |
| H10 | Choisir les **sous-traitants optionnels** (Sentry UE, PostHog UE) ou les refuser. | OPS, UX analytics | 10 min |

## C. En continu (pendant que les agents tournent)

| Fréquence | Action | Où |
|---|---|---|
| Quotidien (5–10 min) | Lire la section « Décisions / actions attendues de toi » du rapport du jour ; répondre aux escalades (une ligne suffit : « Option 2 »). | Issue « Delivery report », `delivery/escalations/` sur `delivery-ledger` |
| Quotidien | Traiter les PR étiquetées `needs-human` (checklist dans `delivery/human-gates/<TASK>.md`). | GitHub |
| Hebdomadaire (30 min) | Lire le rapport hebdomadaire : vélocité, coût par heure estimée livrée, qualité, re-prévision du chemin critique ; ajuster budget/`max_workers`. | Rapport hebdomadaire |
| À la demande | **Arrêt d'urgence** : mettre le label `delivery-pause` sur l'issue de contrôle, ou `control.paused=true` sur `delivery-ledger`. L'orchestrateur termine la revue/le rapport et ne lance plus rien. | GitHub |

## D. Portes humaines par tâche (extraits)

Les portes exactes sont dans chaque paquet (`human_gates`) et dans [packet-overrides.yaml](../../delivery/packet-overrides.yaml). Les principales :

- **Juridique et commercial** : catalogue d'offres et prix (LCH-001, D-17), DPA / sous-traitants / CGU (LCH-102, entité française D-36), politique de support (LCH-104, D-37), grille de tranches de dépense (LCH-105), preuves de paiement (LCH-002/103, D-30).
- **Production** : tout `terraform apply` STAGING/PROD, frontières IAM et SCP en prod, DNS de production, go/no-go de release (REL-004), mise en production (LCH-003).
- **Sécurité** : périmètre du pentest externe (OPS-107), propriétaires des contrôles SOC 2 (OPS-108), premières exécutions témoin des tests WIF et des exercices de restauration (CON-002, OPS-006, OPS-007).
- **Clients** : scripts d'installation exécutés par l'administrateur du client, validation de la réconciliation, atelier d'onboarding (ONB-003/004/005, D-38).
- **Livraison** : ratification des contrats (AGT-007), passage en mode B (AGT-003), scores qualité des agents (AGT-006).

## E. Ce que les agents ne feront jamais

Pousser sur `main`, forcer un push, appliquer Terraform hors DEV, lire des secrets, utiliser des identifiants de production, modifier le PRD, désactiver RLS/politiques d'accès/contrôles CI, envoyer des e-mails ou notifications à de vrais destinataires, merger une PR rouge ou non revue. Les hooks (`.claude/hooks/`), la CI et la protection de branche l'imposent de façon déterministe.
