class_name RefreshHotsEffect
extends Resource
## Effect sub-resource: refresh the remaining duration of all active HoT statuses
## on the target. "HoT" = positive status with "Heal" tag and tick_interval > 0.
## Uses the status's recorded _applied_duration (already includes any source
## duration bonus from when it was applied, e.g. Faithful).
## First consumer: Cleric Deepening Faith (2+ HoT targets refresh on direct heal).
