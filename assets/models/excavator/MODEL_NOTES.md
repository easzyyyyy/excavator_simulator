# Notes du modèle de pelle

Modèle préparé dans Blender 5.2 à partir de "Excavator (CAT)" (voir CREDITS.md), pour remplacer les primitives du simulateur sans changer les scripts.

## Fichiers

- `excavator.gltf`, `excavator.bin` et `textures/` (27 fichiers, 31,4 Mo), plus les fichiers `.import` générés par Godot.
- Export glTF séparé, +Y en haut, modificateurs appliqués, hiérarchie conservée, sans animation, caméra ni lumière. Les textures sont les fichiers préparés, copiés sans recompression.
- Hors dépôt, dans `../excavator_simulator-data/blender/` : fichier de travail `excavator.blend` et sauvegardes par étape, scripts `tools/exc.py`, `tools/tex.py`, `tools/mats.py`, captures de contrôle `checks/`.

## Repères et conventions

- Blender : X à droite, Y vers l'avant, Z vers le haut. Après export, un point Blender (x, y, z) devient (x, z, -y) dans Godot. `Boom` en (0,30 ; 0,15 ; 2,10) correspond donc à `boom_foot` (0,30 ; 2,10 ; -0,15).
- Pose zéro : ligne d'axes de la flèche, balancier et direction axe du godet vers dent horizontaux vers l'avant.
- Les pivots principaux ont une rotation nulle. Une rotation X positive lève ou ouvre ; l'axe X étant inchangé à l'export, le signe est le même dans Godot.
- Empties de vérins et de biellettes : leur +Y local Blender vise l'autre axe, ce qui donne -Z local dans Godot. Leur angle en pose zéro figure dans le tableau des coordonnées.
- Les maillages enfants ont une transformation identité : leurs sommets sont exprimés dans l'espace de leur Empty. Deux exceptions volontaires :
  - Les 98 patins `Undercarriage_LeftTrackShoe_NN` et `Undercarriage_RightTrackShoe_NN` partagent le maillage `TrackShoe`. Chaque noeud porte sa position sur la boucle pour une distance parcourue nulle, calculée comme `_track_shoe_transform` des primitives : patin i à i x L / 49, L = 9,499 m, rayon de boucle 0,35 m, axe des roues à 0,40 m, roue folle à l'avant. Repère local du patin dans Blender : X latéral, +Y le long de la boucle dans le sens des distances croissantes, +Z vers l'extérieur ; dans Godot, -Z le long de la boucle et +Y vers l'extérieur, comme `MeshKit.side_basis_z`.
  - Roues folles et barbotins (`Undercarriage_LeftIdler`, `..._LeftSprocket`, `..._RightIdler`, `..._RightSprocket`) : origine sur leur axe, simple translation, pour tourner autour de leur X local.
- Empties ajoutés à la liste du brief : `LeftTravelLever` et `RightTravelLever`, pivots des leviers de translation, rotation nulle. Les leviers et les manipulateurs sont verticaux en pose zéro ; l'inclinaison de repos de 12° des leviers reste à appliquer par le simulateur.

## Hiérarchie finale

```
Excavator
  Undercarriage  (Undercarriage_Carbody, Undercarriage_LeftIdler, Undercarriage_LeftSprocket,
                  Undercarriage_LeftTrackFrame, Undercarriage_LeftTrackInnerPlate, Undercarriage_RightIdler,
                  Undercarriage_RightSprocket, Undercarriage_RightTrackFrame, Undercarriage_RightTrackInnerPlate,
                  Undercarriage_SwingRing, 98 patins TrackShoe)
    Turret  (Turret_AirFilter, Turret_Body, Turret_BoomCylinderBaseLugs, Turret_BoomCylinderBasePin,
             Turret_BoomFootBlock, Turret_BoomFootBlockFront, Turret_BoomFootCheeks, Turret_BoomFootPin,
             Turret_CounterweightDeck, Turret_Exhaust, Turret_ExhaustPipe, Turret_Radiator, Turret_RightSideFitting)
      Cab  (Cab_ArmrestLeft, Cab_ArmrestRight, Cab_ConsoleLeft, Cab_ConsoleRight, Cab_Floor, Cab_Frame, Cab_Glass,
            Cab_HingeLeftLower, Cab_HingeLeftUpper, Cab_HingeRightLower, Cab_HingeRightUpper, Cab_LowerGlass,
            Cab_Monitor, Cab_MonitorScreen, Cab_RoofRearWall, Cab_Seat, Cab_SeatBase, Cab_TravelLeverHousing,
            Cab_TravelPedalLeft, Cab_TravelPedalRight)
        LeftJoystick  (LeftJoystick_Grip, LeftJoystick_Shaft)
        RightJoystick  (RightJoystick_Grip, RightJoystick_Shaft)
        LeftTravelLever  (LeftTravelLever_Rod)
        RightTravelLever  (RightTravelLever_Rod)
      EyePoint
      BoomCylinderLeftBarrel  (BoomCylinderLeftBarrel_Eye, BoomCylinderLeftBarrel_Tube)
      BoomCylinderRightBarrel  (BoomCylinderRightBarrel_Eye, BoomCylinderRightBarrel_Tube)
      Boom  (Boom_Body, Boom_CylinderRodBossLeft, Boom_CylinderRodBossRight, Boom_CylinderRodEars,
             Boom_CylinderRodPin, Boom_HoseLeft, Boom_HoseRight, Boom_NosePin, Boom_StickCylinderBasePin,
             Boom_StickCylinderEars)
        BoomCylinderLeftRod  (BoomCylinderLeftRod_Eye, BoomCylinderLeftRod_Rod)
        BoomCylinderRightRod  (BoomCylinderRightRod_Eye, BoomCylinderRightRod_Rod)
        StickCylinderBarrel  (StickCylinderBarrel_Eye, StickCylinderBarrel_Tube)
        Stick  (Stick_Body, Stick_BucketCylinderBasePin, Stick_BucketCylinderEars, Stick_BucketPin,
                Stick_CylinderRodPin, Stick_HoseLeft, Stick_HoseLoop, Stick_HoseRight, Stick_RockerPivotPin)
          StickCylinderRod  (StickCylinderRod_Eye, StickCylinderRod_Rod)
          BucketCylinderBarrel  (BucketCylinderBarrel_Eye, BucketCylinderBarrel_Tube)
          BucketCylinderRod  (BucketCylinderRod_Eye, BucketCylinderRod_Rod)
          RockerLink  (RockerLink_Plates)
          PowerLink  (PowerLink_H, PowerLink_JointPin)
          Bucket  (Bucket_Body, Bucket_Ears, Bucket_LinkPin, Bucket_LinkTube)
```

## Coordonnées mesurées en pose zéro

Positions monde Blender en mètres, cibles calculées depuis `scripts/machine_params.gd`. Angle X : direction du +Y local dans le plan latéral, 0 pour les pivots principaux.

| Empty | Parent | Position mesurée | Cible | Écart (mm) | Angle X (°) |
|---|---|---|---|---|---|
| Excavator | - | 0,000 ; 0,000 ; 0,000 | - | - | 0,00 |
| Undercarriage | Excavator | 0,000 ; 0,000 ; 0,000 | - | - | 0,00 |
| Turret | Undercarriage | 0,000 ; 0,000 ; 0,000 | - | - | 0,00 |
| Cab | Turret | -0,975 ; 0,375 ; 1,300 | - | - | 0,00 |
| LeftJoystick | Cab | -1,310 ; 0,500 ; 1,890 | - | - | 0,00 |
| RightJoystick | Cab | -0,590 ; 0,500 ; 1,890 | - | - | 0,00 |
| LeftTravelLever | Cab | -1,050 ; 0,850 ; 1,580 | - | - | 0,00 |
| RightTravelLever | Cab | -0,850 ; 0,850 ; 1,580 | - | - | 0,00 |
| EyePoint | Turret | -0,950 ; 0,450 ; 2,420 | -0,950 ; 0,450 ; 2,420 | 0,0 | 0,00 |
| BoomCylinderLeftBarrel | Turret | -0,120 ; 0,295 ; 1,316 | -0,120 ; 0,295 ; 1,316 | 0,0 | 10,44 |
| BoomCylinderRightBarrel | Turret | 0,720 ; 0,295 ; 1,316 | 0,720 ; 0,295 ; 1,316 | 0,0 | 10,44 |
| Boom | Turret | 0,300 ; 0,150 ; 2,100 | 0,300 ; 0,150 ; 2,100 | 0,0 | 0,00 |
| BoomCylinderLeftRod | Boom | -0,120 ; 2,646 ; 1,749 | -0,120 ; 2,646 ; 1,749 | 0,0 | -169,56 |
| BoomCylinderRightRod | Boom | 0,720 ; 2,646 ; 1,749 | 0,720 ; 2,646 ; 1,749 | 0,0 | -169,56 |
| StickCylinderBarrel | Boom | 0,300 ; 3,200 ; 3,428 | 0,300 ; 3,200 ; 3,428 | 0,0 | -30,27 |
| Stick | Boom | 0,300 ; 5,850 ; 2,100 | 0,300 ; 5,850 ; 2,100 | 0,0 | 0,00 |
| StickCylinderRod | Stick | 0,300 ; 5,057 ; 2,344 | 0,300 ; 5,057 ; 2,344 | 0,0 | 149,73 |
| BucketCylinderBarrel | Stick | 0,300 ; 6,128 ; 2,469 | 0,300 ; 6,128 ; 2,469 | 0,0 | 5,69 |
| BucketCylinderRod | Stick | 0,300 ; 8,029 ; 2,658 | 0,300 ; 8,029 ; 2,658 | 0,0 | -174,31 |
| RockerLink | Stick | 0,300 ; 8,274 ; 2,051 | 0,300 ; 8,274 ; 2,051 | 0,0 | 111,97 |
| PowerLink | Stick | 0,300 ; 8,029 ; 2,658 | 0,300 ; 8,029 ; 2,658 | 0,0 | -6,15 |
| Bucket | Stick | 0,300 ; 8,750 ; 2,100 | 0,300 ; 8,750 ; 2,100 | 0,0 | 0,00 |

Autres mesures :

| Cote | Mesure | Cible |
|---|---|---|
| Pointe des dents | 0,721 ; 10,343 ; 2,100, rayon 1,593 m, direction +Y | rayon 1,560 m |
| Largeur du godet | 1,203 m avec bossages | 1,20 m |
| Vérins de flèche, fût et tige | 1,683 m et 1,480 m, rayons 0,090 et 0,042 m | 1,803 - 0,12 et 1,26 + 0,22 |
| Vérin de balancier, fût et tige | 2,073 m et 1,724 m, rayons 0,100 et 0,049 m | 2,193 - 0,12 et 1,504 + 0,22 |
| Vérin de godet, fût et tige | 1,514 m et 1,324 m, rayons 0,090 et 0,042 m | 1,634 - 0,12 et 1,104 + 0,22 |
| Longueur de chenille | 4,464 m | 4,45 m |
| Entraxe roue folle et barbotin | 3,650 m | 3,65 m |
| Voie et largeur de patin | 2,380 m et 0,600 m | 2,38 m et 0,60 m |
| Largeur de tourelle | 3,005 m | 2,95 m |
| Rayon arrière de tourelle | 2,90 m aux coins du contrepoids, 2,83 m au centre | 2,83 m |
| Garde au sol du contrepoids | 1,046 m | 1,05 m |
| Hauteur au toit de cabine | 2,948 m | 2,95 m |
| Cabine | 1,000 m sur 1,850 m, avant à Y = 1,300 | 1,00 sur 1,85, avant à 1,30 |
| Siège | dessus du coussin 0,72 m sous EyePoint, plancher à 1,385 m | - |

## Triangles par pièce

Total : 85 498 triangles. Un patin compte 388 triangles, les 98 patins 38 024.

| Empty parent | Triangles |
|---|---|
| Undercarriage | 52 152 |
| Boom | 11 000 |
| Cab | 6 256 |
| Stick | 6 056 |
| Turret | 4 006 |
| Bucket | 1 864 |
| PowerLink | 620 |
| BoomCylinderLeftBarrel, BoomCylinderRightBarrel | 572 chacun |
| StickCylinderBarrel, BucketCylinderBarrel | 492 chacun |
| Tiges des quatre vérins | 184 chacune |
| LeftJoystick, RightJoystick | 176 chacun |
| RockerLink | 168 |
| LeftTravelLever, RightTravelLever | 80 chacun |

## Matériaux et textures

Couleur de base en JPEG qualité 90, normal maps en PNG, cartes metal et roughness empaquetées en PNG 1024 px selon la convention glTF (G = roughness, B = metal).

| Matériau | Jeu de textures | Cartes |
|---|---|---|
| Boom | boom | couleur, metal et roughness |
| Stick | stick | couleur, metal et roughness, normal |
| Body_Yellow, Body_Yellow_Boss | body_yellow | couleur, metal (roughness 0,55 constante), normal |
| Body_Black | body_black | couleur, metal et roughness |
| Counterweight | counterweight | couleur, roughness (metal 0,2), normal |
| Radiator | radiator | couleur (roughness 0,6, metal 0,1) |
| Bucket | bucket | couleur, metal et roughness, normal |
| Cylinder_Barrel | cylinder | couleur, metal et roughness, normal |
| Track_Left, Track_Right | track | couleur, roughness (metal 0,2), normal |
| Cab_Frame | cab_frame | couleur, roughness (metal 0) |
| Seat | seat | couleur (roughness 0,7) |
| Swing_Ring | swing_ring | couleur (roughness 0,6, metal 0,3) |
| Cylinder_Rod, Pin_Steel, Pin_Cap, Hinge_Black, Hose, Rubber_Dark, Interior_Dark, Cab_Floor | aucun | valeurs constantes |
| Cab_Glass | aucun | transparent, alpha 0,18 |
| Cab_Screen | aucun | sombre, légère émission |

| Fichier | Résolution | Taille (Mo) |
|---|---|---|
| excavator_body_black_basecolor.jpg | 2048 | 0,54 |
| excavator_body_black_metalrough.png | 1024 | 1,09 |
| excavator_body_yellow_basecolor.jpg | 2048 | 0,36 |
| excavator_body_yellow_metalrough.png | 1024 | 0,74 |
| excavator_body_yellow_normal.png | 2048 | 0,17 |
| excavator_boom_basecolor.jpg | 2048 | 0,29 |
| excavator_boom_metalrough.png | 1024 | 0,56 |
| excavator_bucket_basecolor.jpg | 2048 | 1,06 |
| excavator_bucket_metalrough.png | 1024 | 1,24 |
| excavator_bucket_normal.png | 2048 | 5,42 |
| excavator_cab_frame_basecolor.jpg | 2048 | 0,43 |
| excavator_cab_frame_metalrough.png | 1024 | 0,61 |
| excavator_counterweight_basecolor.jpg | 2048 | 0,27 |
| excavator_counterweight_metalrough.png | 1024 | 0,51 |
| excavator_counterweight_normal.png | 2048 | 0,06 |
| excavator_cylinder_basecolor.jpg | 2048 | 0,79 |
| excavator_cylinder_metalrough.png | 1024 | 0,82 |
| excavator_cylinder_normal.png | 2048 | 2,04 |
| excavator_radiator_basecolor.jpg | 2048 | 0,63 |
| excavator_seat_basecolor.jpg | 2048 | 0,89 |
| excavator_stick_basecolor.jpg | 2048 | 0,43 |
| excavator_stick_metalrough.png | 1024 | 0,80 |
| excavator_stick_normal.png | 2048 | 0,06 |
| excavator_swing_ring_basecolor.jpg | 2048 | 0,38 |
| excavator_track_basecolor.jpg | 2048 | 1,59 |
| excavator_track_metalrough.png | 1024 | 1,10 |
| excavator_track_normal.png | 2048 | 8,49 |

Les cartes absentes de l'archive d'origine sont remplacées par les constantes indiquées : metal des chenilles et du contrepoids, roughness et metal du radiateur, roughness de la caisse jaune, toutes les cartes des tiges de vérins et des axes.

## Écarts volontaires par rapport au modèle d'origine

- Flèche pliée au coude de 0,35 m vers le bas pour que la chape de tige des vérins de flèche soit 0,50 m sous le ventre et la chape du vérin de balancier 0,41 m au-dessus, au lieu de 0,81 m et 0,09 m.
- Balancier : partie centrale étirée de 55 %, dessus abaissé de 45 % près du pivot pour laisser le vérin de godet au-dessus, queue reculée de 0,15 m et abaissée de 0,11 m pour porter l'axe de tige du vérin de balancier.
- Le godet est articulé sur l'axe de bout de balancier ; ses oreilles portent l'axe du godet et l'axe de bielle.
- Tourelle : contrepoids cintré en plan, capot compressé de 0,71 m, flanc intérieur gauche reculé à X = -0,26 devant la cabine, plancher entaillé sous la flèche, bloc avant de pied de flèche abaissé et reculé.
- Cabine rétrécie de 25 % et allongée de 8 %, plancher remplacé par un plan à 1,385 m.
- Chenilles reconstruites aux cotes et nombres de `machine_params.gd` : patins, galets et hauteur de train réduits (roues de 0,30 m de rayon).

## Défauts restants

- Les flexibles de la flèche et du balancier sont fixes et ne suivent pas les articulations ; la boucle de flexible du balancier flotte.
- En pose zéro, hors butées, le vérin de balancier est plus court que sa longueur fermée (2,150 m pour 2,193 m) : fût et tige se recouvrent plus que dans la réalité.
- Les axes de base des vérins de flèche sont 4 cm sous le dessus du plancher de tourelle, comme le veulent les cotes du simulateur.
- Rayon de pointe du godet de 1,593 m au lieu de 1,56 m, profil d'origine conservé comme demandé.
- Flèche en butée basse, tourelle tournée au-dessus d'une chenille : la flèche peut traverser le haut de la chenille.
- Pièces ajoutées texturées par projection boîte dans une zone de l'atlas : usure moins détaillée que sur les pièces d'origine. Trace rectangulaire discrète à l'emplacement du grand logo du capot.
- Les normales personnalisées du FBX sont conservées sur les pièces déformées : légers écarts d'ombrage possibles sur la flèche, le balancier et la tourelle.
- Vitrage en boîte fermée doublé par deux panneaux bas : le tri des surfaces transparentes est à vérifier dans Godot.
- Roue folle et barbotin sont tous deux dentés, comme dans le modèle source.
- `Turret_RightSideFitting` est une pièce d'origine non identifiée, conservée telle quelle.
- Châssis de chenilles et plaques intérieures mis à l'échelle de façon non uniforme.
- Normal maps presque plates pour `stick` et `counterweight` (fichiers d'origine quasi uniformes).
