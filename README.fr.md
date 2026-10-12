# Enchron

[简体中文](README.md) | [繁體中文](README.zh-TW.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | Français | [Deutsch](README.de.md)

[![Verification](https://github.com/1873663116/Enchron/actions/workflows/verification.yml/badge.svg?branch=main)](https://github.com/1873663116/Enchron/actions/workflows/verification.yml) [![License: GPL-3.0](https://img.shields.io/github/license/1873663116/Enchron)](LICENSE)

Enchron est un lecteur multimédia pour Apple Vision Pro. Il lit des vidéos dans des fenêtres et des espaces immersifs, et prend en charge les fichiers locaux ainsi que les bibliothèques SMB, WebDAV et Emby.

## État

Enchron est disponible en bêta publique sur TestFlight. Rejoignez le test depuis un Apple Vision Pro à l’aide du lien ci-dessous. Les fonctionnalités et la compatibilité peuvent évoluer.

<a href="https://testflight.apple.com/join/F1xpZq6b">
  <img src="docs/assets/testflight/testflight.svg" alt="Rejoindre la bêta publique d’Enchron sur TestFlight" width="240" />
</a>

## Fonctionnalités

- Lire des vidéos dans une fenêtre, sur un écran ancré ou dans un environnement immersif.
- Parcourir les médias locaux ou se connecter à des serveurs SMB, WebDAV et Emby.
- Contrôler la lecture et choisir les sous-titres et les pistes audio.
- Utiliser AVFoundation pour le décodage et le rendu accélérés par le matériel. La lecture HDR10, HLG et Dolby Vision dépend de l’appareil et du format du média.
- Utiliser FFmpeg pour lire les conteneurs multimédias courants. La prise en charge de codecs tels que H.264, HEVC et AV1 dépend de l’appareil ; Apple Vision Pro (M5) prend en charge AV1.

## Compilation

Le projet nécessite Xcode 27.0 et le SDK visionOS. Après le clonage, exécutez ces commandes depuis la racine du dépôt pour préparer les dépendances binaires requises par `Packages/PlaybackCore`. Elles ne sont pas stockées dans Git.

```sh
Scripts/provision_vendored_ffmpeg.sh
Scripts/provision_vendored_bluray.sh
```

La structure des échantillons Blu-ray est vérifiée par rapport à un analyseur MPLS indépendant avec `Scripts/build/verify_bluray_corpus.py`. Les données de validation Blu-ray et les outils de vérification sur simulateur se trouvent dans `Scripts/verification/`. Les points d’entrée de compilation et de vérification sont dans `Scripts/` et `Regression/`. Consultez [`ARCHITECTURE.md`](ARCHITECTURE.md) pour la propriété des modules, [`AGENTS.md`](AGENTS.md) pour les contraintes du projet et [`Regression/README.md`](Regression/README.md) pour le protocole de test.

## Confidentialité et réseau

Enchron n’exploite pas de service multimédia et n’envoie au développeur ni médias, ni historique de lecture, ni identifiants de serveurs distants. L’application se connecte directement aux serveurs configurés par les utilisateurs et stocke les identifiants distants dans le trousseau de l’appareil. Consultez [`PRIVACY.md`](PRIVACY.md) pour en savoir plus.

L’application autorise les connexions HTTP non chiffrées aux serveurs auto-hébergés sans TLS. Avant une connexion à une adresse publique, elle avertit que les identifiants peuvent être transmis sans chiffrement et demande confirmation. Vous pouvez utiliser HTTPS ou un réseau privé chiffré.

## Licence et logiciels tiers

Enchron est distribué sous la GNU General Public License v3.0. Le texte de la licence se trouve dans [`LICENSE`](LICENSE) ; les logiciels tiers et leurs licences sont répertoriés dans [`NOTICE`](NOTICE). L’application fournit également les informations de licence correspondantes dans ses réglages.

## Contributions externes

Les contributions externes ne sont pas acceptées pour le moment. Ce dépôt est destiné à la consultation du code source, aux compilations reproductibles et au respect des licences. L’intégration continue, la signature et l’infrastructure de publication ne sont pas accessibles aux contributeurs externes.
