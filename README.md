# L'Atelier — blog statique avec admin intégrée

Site 100% statique (compatible GitHub Pages), sans base de données ni serveur.
La publication d'articles (texte, images, vidéos) se fait depuis `admin.html`,
qui écrit directement dans le dépôt GitHub via l'API.

## Pourquoi pas un vrai login serveur ?

GitHub Pages ne sait servir que des fichiers statiques : il n'y a pas de backend
capable de vérifier un mot de passe. La solution retenue ici :

- **Nom d'utilisateur** = ton nom d'utilisateur GitHub
- **Mot de passe** = un **token d'accès personnel GitHub** (PAT), qui autorise
  l'écriture sur ce dépôt précis.

Le token n'est stocké que dans `sessionStorage` de ton navigateur (effacé à la
fermeture de l'onglet) et n'est jamais commité dans le dépôt. Il ne remplace pas
une vraie authentification serveur, mais c'est la seule façon d'avoir une
admin qui écrit réellement dans le repo depuis un site 100% statique — c'est le
principe utilisé par les CMS "headless" comme Decap CMS.

**Sécurité** : le dépôt doit rester privé si tu ne veux pas que le contenu soit
public avant publication (GitHub Pages sur un dépôt privé nécessite un compte
GitHub Pro, sinon héberge le repo en public — dans ce cas, n'importe qui peut
lire `data/articles.json`, ce qui est normal pour un blog public). Ne partage
jamais ton token, et donne-lui uniquement les droits nécessaires (voir plus bas).

## 1. Mise en place du dépôt

1. Crée un dépôt GitHub (ex. `mon-atelier`).
2. Mets-y les fichiers de ce dossier (`index.html`, `admin.html`, `css/`, `js/`, `data/`, `images/`).
3. Dans **Settings → Pages**, choisis la branche `main` (dossier `/root`) comme source.
4. Ton site sera accessible à `https://<ton-nom-utilisateur>.github.io/<nom-du-repo>/`.

## 2. Créer le token d'accès (le "mot de passe" admin)

1. Sur GitHub : **Settings** (de ton compte) → **Developer settings** →
   **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
2. **Repository access** : sélectionne uniquement ce dépôt (pas "All repositories").
3. **Permissions** → **Contents** : mets sur **Read and write**.
4. Génère le token et copie-le tout de suite (il ne sera plus jamais affiché).
5. Ne le partage avec personne : c'est lui qui permet de modifier ton site.

## 3. Se connecter à l'admin

Va sur `https://<ton-nom-utilisateur>.github.io/<nom-du-repo>/admin.html` et entre :

- Nom d'utilisateur GitHub
- Nom du dépôt
- Branche (`main` par défaut)
- Le token créé à l'étape 2

## 4. Publier un article

Depuis le tableau de bord de l'admin : **+ Nouvel article**, remplis le titre,
la date, le résumé, puis ajoute des blocs :

- **Titre de section** — un sous-titre dans l'article
- **Texte** — supporte `**gras**` et `*italique*`
- **Image** — upload direct (envoyée dans `images/` du dépôt) ou URL externe
- **Vidéo** — colle un lien YouTube, Vimeo, ou un lien direct vers un `.mp4`
- **Code** — pour coller un extrait de code

Clique sur **Enregistrer et publier** : l'admin met à jour `data/articles.json`
(et envoie les images) directement dans le dépôt via un commit. Le site public
(`index.html`) se met à jour automatiquement, sans rebuild — GitHub Pages sert
le fichier JSON à jour.

## Remarque sur les vidéos

Pour rester léger sur GitHub Pages (limite de 100 Mo par fichier, dépôt pas fait
pour stocker de gros binaires), les vidéos ne sont **pas** uploadées dans le
dépôt : héberge-les sur YouTube (en non répertorié si tu veux qu'elles restent
privées) ou Vimeo, et colle simplement le lien dans le bloc "Vidéo".

## Structure des fichiers

```
index.html          → page publique (liste + lecture des articles)
admin.html           → interface d'administration
css/style.css        → style partagé
js/matrix.js         → animation de la matrice LED (en-tête)
js/render.js         → transforme un article JSON en HTML
js/admin.js          → logique de connexion + écriture via l'API GitHub
data/articles.json   → base de données des articles (modifiée par l'admin)
images/               → images uploadées depuis l'admin
```
