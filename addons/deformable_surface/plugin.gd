@tool
extends EditorPlugin
## Deformable Surface needs no editor integration: its node types (DeformableSurface,
## Deformer, DeformerFootsteps) register themselves through class_name,
## so they appear in "Add Node" as soon as the folder is in your project.
## This script exists so the addon shows up in Project Settings > Plugins and
## can host editor tooling later.
