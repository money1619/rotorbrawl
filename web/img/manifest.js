/* Rendus de nos modèles disponibles pour la boutique (Fermi). Clé = dossier/identifiant technique, sans extension :
   tops/<kit>, parts/<partId>, launchers/spin_launcher, repair/spin_repair_kit. Une image absente de cette liste
   n'est jamais demandée : la boutique garde son SVG provisoire.
   ÉCHANTILLON (Fermi, arena-recherche-visuelle 8b541cf, rendus Cycles de nos modèles) : 5 toupies et le lanceur.
   À valider par Money avant toute généralisation ; les pièces n'ont pas encore de modèle 3D. */
window.SPIN_IMAGES = {
    'tops/attack': true, 'tops/defense': true, 'tops/endurance': true, 'tops/balance': true, 'tops/mobility': true,
    'launchers/spin_launcher': true,
    // Pièces : icônes de la planche de Money (install/icons_money), converties en WebP ; 3 pièces sans icône gardent le dessin
    'parts/ring_smash': true,
    'parts/ring_guard': true,
    'parts/ring_round': true,
    'parts/ring_std': true,
    'parts/ring_reverse': true,   // dérivée de ring_std : miroir + teinte violette (28/10)
    'parts/frame_std': true,
    'parts/frame_wide': true,
    'parts/frame_low': true,
    'parts/frame_spike': true,
    'parts/core_std': true,
    'parts/core_rim': true,
    'parts/core_heavy': true,
    'parts/tip_flat': true,
    'parts/tip_sharp': true,
    'parts/tip_rubber': true,
};
