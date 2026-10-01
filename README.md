# Voyageur Temporal

Un vaisseau qui voyage à travers l'espace pendant ta journée de travail. Tu fixes l'heure d'arrivée et les étapes, puis tu gardes la fenêtre dans un coin de l'écran pour penser à faire des pauses.

## Télécharger

1. Va dans [**Releases**](../../releases/latest).
2. Télécharge `VoyageurTemporal.exe`.
3. Double-clique dessus. Il n'y a rien à installer.

> **Windows peut afficher « Windows a protégé votre ordinateur »**, parce que l'application n'est pas signée numériquement.
> Clique sur **Informations complémentaires**, puis sur **Exécuter quand même**.

**Configuration requise :** Windows 10 ou 11 (64 bits) avec une carte graphique compatible OpenGL 3.3.

Les réglages sont enregistrés dans `%APPDATA%\VoyageurTemporal\`.

## Développement

Le projet utilise Godot 4.7. Pour produire l'exécutable :

1. Ouvre le projet dans Godot 4.7.
2. Installe les modèles d'export : *Éditeur → Gérer les modèles d'export*.
3. Va dans *Projet → Exporter → Windows Desktop → Exporter le projet*, en décochant *Exporter avec débogage*.

L'exécutable est créé dans `../builds/VoyageurTemporal.exe`. C'est un fichier unique qui contient tout le jeu.
