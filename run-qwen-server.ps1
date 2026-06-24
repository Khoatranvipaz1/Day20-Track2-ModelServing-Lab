$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = 'utf-8'

$model = (Get-Content .\models\active.json | ConvertFrom-Json).primary_model
& .\.venv\Scripts\python.exe -m llama_cpp.server `
    --model "$model" `
    --host 0.0.0.0 `
    --port 8080 `
    --n_threads 12 `
    --n_gpu_layers 99 `
    --n_ctx 2048
