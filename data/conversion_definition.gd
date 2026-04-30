class_name ConversionDefinition
extends Resource
## Converts one damage type to another. Separate from ModifierDefinition because
## conversions need a target type string, not a numeric value.
## Only one conversion per damage instance (first in processing order wins).
## True damage cannot be converted to or from.

@export var source_type: String = ""       ## Original damage type ("Physical", "Fire", etc.)
@export var target_type: String = ""       ## Converted damage type ("Lightning", "Ice", etc.)
@export var source_name: String = ""       ## For "Show your work" stat display
