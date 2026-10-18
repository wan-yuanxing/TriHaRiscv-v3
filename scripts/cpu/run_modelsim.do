# ModelSim owns tool execution; run.ps1 validates the actual program result.
onerror {quit -f -code 2}
onbreak {quit -f -code 3}
run -all
quit -f -code 0
