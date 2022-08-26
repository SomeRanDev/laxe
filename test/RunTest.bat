@echo off

cls

IF "%~1"=="clean" GOTO clean
IF "%~1"=="hl" GOTO hl
IF "%~1"=="js" GOTO js
IF "%~1"=="cs" GOTO cs

@echo Must specify "hl", "js", or "cs" to run test.
@echo Use "clean" to clean.
GOTO end

:clean
@echo -- Cleaning
if exist "./Test.js" del Test.js
if exist "./Test.hl" del Test.hl
if exist "./bin_cs" rmdir -f bin_cs
@echo.
GOTO end

:js
@echo -- haxe Test.hxml -js Test.js
haxe Test.hxml -js Test.js
node Test.js
@echo.
GOTO end

:hl
@echo -- haxe Test.hxml -hl Test.hl
haxe Test.hxml -hl Test.hl
hl Test.hl
@echo.
GOTO end

:cs
@echo -- haxe Test.hxml -cs bin_cs
haxe Test.hxml -cs bin_cs
@echo.
GOTO end

:end