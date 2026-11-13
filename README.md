# Excavator Simulator

A first-person simulator of a hydraulic crawler excavator, built to practise the coordination of the real controls (boom, stick, bucket, swing, travel). It is a training tool, not a game: there is no score chasing and no guided progression.

## Features

- First-person view from the cab, with a 20 t class machine (parameters based on the Cat 320 manufacturer data)
- Hydraulic system where each cylinder length is the state, with shared pump flow, stalls and load handling
- Diggable terrain with several soil materials (common earth, clay, sand), loose soil and a bucket load model
- A dump truck that can be loaded
- A trench exercise scored like the CACES R482 category B1 practical test
- Automated tests that check the machine envelope and function times against manufacturer data

In-game text is in French.

## Tech stack

- Godot 4.7, GDScript, Jolt Physics
- Models prepared in Blender and exported as glTF

## Run locally

1. Install Godot 4.7 (standard build).
2. Open `project.godot` in the editor and run the project (main scene: `scenes/main.tscn`).

To run the tests from the command line:

```
godot --headless --path . --script res://tests/run_tests.gd
```

Sound effects are not included in this repository, so the project runs silently until you add your own files at the paths referenced in `scenes/excavator.tscn`.

## Credits and licenses

The source code is released under the MIT License (see `LICENSE`).

The excavator 3D model is "Excavator (CAT)" by sarvesh777, https://sketchfab.com/3d-models/excavator-cat-5f195244108c46e495a1e78040f02f7e, licensed under Creative Commons Attribution 4.0 International (CC BY 4.0), https://creativecommons.org/licenses/by/4.0/. The model was modified for this project (changes listed in `assets/models/excavator/CREDITS.md`). Caterpillar, CAT and their logos are trademarks of Caterpillar Inc.; the CC BY license covers the modeller's work, not the trademark, and the logos present in the original textures were removed. This project is not affiliated with Caterpillar Inc.

`addons/godot_ai` is a third-party editor plugin under its own MIT license (see `addons/godot_ai/LICENSE`).

Third-party assets keep their own licenses.
