@echo off
REM Local-only example. For another computer, use an authenticated HTTPS proxy
REM or an encrypted tunnel bound to loopback on the Mac. Do not expose this port.
REM Configure Qiusuo's endpoint manually; model names depend on your server.
set MODEL=your-model.gguf
llama-server.exe -m %MODEL% --host 127.0.0.1 --port 8080 -c 4096 -ngl 99
