@echo off

cls

IF "%~1"=="clean" GOTO clean
IF "%~1"=="hl" GOTO hl
IF "%~1"=="js" GOTO js
IF "%~1"=="py" GOTO py
IF "%~1"=="lua" GOTO lua
IF "%~1"=="cs" GOTO cs
IF "%~1"=="cpp" GOTO cpp

@echo Must specify "hl", "js", "py", "lua", "cs", or "cpp" to run test.
@echo Use "clean" to clean.
GOTO end

:clean
@echo -- Cleaning
if exist "./Test.js" del Test.js
if exist "./Test.py" del Test.py
if exist "./Test.lua" del Test.lua
if exist "./Test.hl" del Test.hl
if exist "./bin_cs" rmdir /s /q bin_cs
if exist "./bin_cpp" rmdir /s /q bin_cpp
@echo.
GOTO end


:: ----------------
:: js
:: ----------------

:js
@echo on

haxe Test.hxml -js Test.js

@echo.

node Test.js

@echo off
@echo.
GOTO end

:: ----------------
:: py
:: ----------------

:py
@echo on

haxe Test.hxml -python Test.py

@echo.

python Test.py

@echo off
@echo.
GOTO end

:: ----------------
:: lua
:: ----------------

:lua
@echo on

haxe Test.hxml -lua Test.lua

@echo.

lua Test.lua

@echo off
@echo.
GOTO end

:: ----------------
:: hl
:: ----------------

:hl
@echo on

haxe Test.hxml -hl Test.hl

@echo.

hl Test.hl

@echo off
@echo.
GOTO end

:: ----------------
:: cs
:: ----------------

:cs
@echo on

haxe Test.hxml -cs bin_cs

@echo.

"./bin_cs/bin/Test.exe"

@echo off
@echo.
GOTO end

:: ----------------
:: cpp
:: ----------------

:cpp
@echo on

haxe Test.hxml -cpp bin_cpp

@echo.

"./bin_cpp/Test.exe"

@echo off
@echo.
GOTO end

:: ----------------
:: end
:: ----------------

:end