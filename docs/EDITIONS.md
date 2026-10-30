# Éditions de SPIN ARENA : gratuite (GitHub) et Pro (Tebex)

Une seule source, deux paquets construits par `python -I tools/package.py` (dans `dist/`, ignoré par git).

| | Gratuite (GitHub) | Pro (Tebex) |
|---|---|---|
| Duels 1 contre 1, entraînement contre le bot | oui | oui |
| Boutique, atelier, usure, réparation | oui | oui |
| Classement du serveur | oui (tous les matchs avec résultat) | oui, **matchs homologués seulement** |
| Homologation : certificat signé, matchs amicaux, anti-complaisance | non | oui |
| Tournois (inscriptions, tableau) | non | oui |
| Tables | Standard, Compacte, Éjection, Large | + Turbo (rail), Poche (portable), Colisée (tournoi) |
| Arène transportable (objet) | non | oui |
| Lanceurs | Cordon | + Manivelle, Ressort, Précision, Rail |
| Pièces | 18 de base | + Lame Scie, Verrou 9 crans, Embout Engrenage |
| Arènes fixes par la config (`arena.fixedList`) | oui | oui |
| Licence | `LICENSE` (AEOM : modification autorisée, revente interdite) | `LICENSE_PRO` (commerciale, un serveur) — **brouillon à faire relire** |
| Protection | aucune | Cfx.re Asset Escrow (à activer sur Tebex) |

## Comment le paquet gratuit est fabriqué
- Lignes finissant par `-- @pro` et blocs `-- @pro-begin` … `-- @pro-end` : retirés de l'édition gratuite (config des pièces, lanceurs,
  variantes de tables, icônes, objet d'inventaire). Dans l'édition Pro, seuls les marqueurs sont retirés.
- Fichiers retirés (liste `FREE_EXCLUDE` de `tools/package.py`) : `server/tournaments.lua`, `server/homologation.lua`, modèles des
  tables Turbo / Poche / Colisée et de trois pièces, icônes de ces pièces.
- `tools/edition/pro_stub.lua` remplace tournois et homologation : les actions de tournoi répondent « édition Pro ».
- Jamais livrés : `tests/`, `tools/`, `dist/`, `data/` (sauf `arenas.json` filtré : sans `test_*`, sans tables Pro), `docs/evidence`.

## Avant de publier — à faire par toi
1. **Faire relire `LICENSE_PRO`** par quelqu'un qui connaît le droit (brouillon, pas un avis juridique).
2. **Icônes « Money »** (`install/icons_money`) : vérifier que la planche fournie peut être distribuée gratuitement ET vendue
   (`docs/ASSET_REGISTER.md` §4) ; sinon les remplacer avant publication.
3. **Nom « SPIN ARENA »** : le registre le dit provisoire ; vérifier la disponibilité (marque) avant d'ouvrir une boutique.
4. **Contrôle en jeu** : les paquets sont testés hors jeu seulement. Les trois modèles de pièces retirés de l'édition gratuite
   restent déclarés dans `spin_arena_parts.ytyp` : vérifier qu'un `ensure` de l'édition gratuite ne journalise pas d'erreur bloquante.
5. **Tebex** : créer deux produits (ou un produit + une variante), activer l'escrow sur l'édition Pro, ne jamais y mettre `dist/…-free.zip`
   à la place.
6. **Publication GitHub** : un dépôt public avec le contenu de `dist/…-free.zip` ; rien n'est publié sans ton feu vert (aucun `git push` fait).
