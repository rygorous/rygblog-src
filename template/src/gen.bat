@echo off
setlocal
pushd %~dp0
lessc -x style.less ..\static\style.css