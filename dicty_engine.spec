# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = [('bin/whisper.cpp/build/bin/whisper-cli', 'bin'), ('bin/whisper.cpp/build/bin/whisper-server', 'bin'), ('models_config.json', '.'), ('telemetry_config.json', '.'), ('.env.example', '.env')]
binaries = []
hiddenimports = ['passlib.handlers.bcrypt', 'uvicorn.logging', 'uvicorn.loops', 'uvicorn.loops.auto', 'uvicorn.protocols', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto', 'uvicorn.protocols.websockets', 'uvicorn.protocols.websockets.auto', 'websockets', 'websockets.legacy.client', 'cloud_streaming', 'transcript_join', 'dicty_paths', 'engine_auth', 'uvicorn.lifespan', 'uvicorn.lifespan.on', 'uvicorn.lifespan.off', 'fastapi', 'starlette', 'anyio', 'pydantic', 'pydantic.fields', 'pydantic.main', 'multipart', 'email_validator', 'passlib.handlers.bcrypt', 'scipy', 'scipy.signal', 'prompts', 'llm_service', 'transcribe_service', 'model_manager', 'audio_recorder', 'agent_service', 'notion_service', 'queue_manager', 'pending_manager', 'auth', 'update_manager', 'telemetry_service', 'db', 'git_service', 'github_service', 'gitlab_service', 'bitbucket_service', 'linear_service', 'confluence_service', 'obsidian_service', 'hub_service', 'tts_service', 'silero_service', 'piper_service', 'dictation_metrics', 'local_whisper', 'local_llm', 'snippet_service', 'meeting_dialogue', 'modes_service', 'style_rules', 'local_corrections', 'typing_extensions', 'pickletools', '_compat_pickle', 'app_rules', 'app_rules_defaults']
tmp_ret = collect_all('onnxruntime')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('kokoro_onnx')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('espeakng_loader')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('phonemizer')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('certifi')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('numpy')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    ['dicty_engine.py'],
    pathex=['.', 'services', 'integrations'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['torch', 'torchvision', 'torchaudio'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='dicty_engine',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='dicty_engine',
)
