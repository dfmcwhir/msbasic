@echo off

REM Create tmp directory if it doesn't exist
if not exist tmp (
    mkdir tmp
)

REM Loop through each target
for %%i in (isa6502) do (
    echo %%i
    ca65 -D %%i msbasic.s -o tmp\%%i.o
    if errorlevel 1 goto :error

    ld65 -C %%i.cfg tmp\%%i.o -o tmp\%%i.bin -Ln tmp\%%i.lbl
    if errorlevel 1 goto :error
)

echo Build complete
goto :eof

:error
echo Build failed
exit /b 1
