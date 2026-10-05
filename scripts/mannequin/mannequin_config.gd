@tool
class_name MannequinConfig
extends Resource
## Data-driven mannequin definition: an ordered list of primitive parts.
## Different body shapes are new MannequinConfig resources, not new code.

@export var parts: Array[MannequinPart] = []
