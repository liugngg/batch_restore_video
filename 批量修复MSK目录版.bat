
@echo off
REM 启用延迟环境变量扩展
setlocal enabledelayedexpansion

REM 设置窗口标题
title 视频MSK修改工具

REM ======================== 用户配置区 ========================
REM :: 【修复点 1】: 请在此处指定 lada-cli.exe 的完整路径
set "LADA_CLI_PATH=D:\Programs\lada-v0.8.2\lada-cli.exe"

REM 设置默认参数
set "CODEC=hevc_nvenc"
set "CRF=20"
set "DETECTION_MODEL=D:\Programs\lada-v0.8.2\_internal\model_weights\lada_mosaic_detection_model_v3.1_accurate.pt"
set "RESTORATION_MODEL=basicvsrpp-v1.2"
REM ==========================================================

@REM REM 检查 lada-cli.exe 是否存在
@REM if not exist "%LADA_CLI_PATH%" (
@REM     echo [错误] 未找到 lada-cli.exe!
@REM     echo       请编辑此脚本，在 "用户配置区" 中设置正确的 LADA_CLI_PATH 路径。
@REM     echo       当前配置的路径为: "%LADA_CLI_PATH%"
@REM     pause
@REM     exit /b
@REM )

REM 检查是否有输入路径
if "%~1"=="" (
    echo.
    echo 请将一个视频文件/文件夹拖放到此脚本上运行
    echo.
    echo 当前配置:
    echo   修复模型: %RESTORATION_MODEL%
    echo   检测模型: %DETECTION_MODEL%
    echo   编码器:   %CODEC%
    echo   CRF值:    %CRF%
    echo.
    echo 输出文件名为 [原文件名]-La.mp4
    echo.
    pause
    exit /b
)

REM 初始化计数器
set file_count=0
set processed_count=0
set failed_count=0
set total_processing_time=0

echo.
echo 开始处理任务...
set "input_path=%~f1"

REM 创建临时文件存储文件列表
set "temp_list=%temp%\video_files_list.txt"
if exist "%temp_list%" del "%temp_list%"

REM 判断是文件还是文件夹
if exist "%~1" ( SET ATTR=%~a1 ) else ( SET ATTR= )
if defined ATTR if "%ATTR:~0,1%" neq "d" (
    echo [信息] 发现文件: "%~nx1"
    echo "%input_path%" > "%temp_list%"
) else if exist "%input_path%\" (
    echo [信息] 发现文件夹: "%~nx1"
    echo 正在扫描文件夹中的媒体文件...
    for /r "%input_path%" %%f in (*.mp4 *.mkv *.avi *.mov *.wmv *.m4v *.mpeg *.mpg) do (
        if exist "%%f" echo "%%f" >> "%temp_list%"
    )
) else (
    echo [错误] 输入路径不存在: "%~nx1"
    pause
    exit /b
)

REM 统计文件数量
set total_files=0
if exist "%temp_list%" (
    for /f %%i in ('type "%temp_list%" ^| find /c /v ""') do set total_files=%%i
    REM 可选写法：
    REM for /f %%i in ('find /c /v "" "%temp_list%"') do set total_files=%%i
)

if %total_files% equ 0 (
    echo [警告] 未找到任何媒体文件
    pause
    exit /b
)

echo 当前配置:
echo   修复模型: %RESTORATION_MODEL%
echo   检测模型: %DETECTION_MODEL%
echo   编码器:   %CODEC%
echo   CRF值:    %CRF%
echo.
REM 显示待处理文件列表
echo.
echo ====== 待处理文件列表 (共 %total_files% 个) ======
set list_index=0
for /f "usebackq delims=" %%i in ("%temp_list%") do (
    set /a list_index+=1
    echo !list_index!. %%~nxi
)
echo ======================================

REM 询问是否开始处理
echo 请确认参数,输入任意键继续。
set /p "num=如需修改CRF值，直接输入数字(10~29): "
set "num=!num: =!"                 & REM 先删除空格
REM 验证输入是否为纯数字10-29
echo !num! | findstr /r "^[12][0-9]" >nul
if !errorlevel! equ 0 (
    set "CRF=!num!"
    echo [信息] 重新设置了CRF值: !CRF!
) else (
    echo [信息] 未修改CRF值
)

echo.
echo "使用CRF值：!CRF! ，开始处理..."

REM 逐个处理文件列表中的文件
for /f "usebackq delims=" %%i in ("%temp_list%") do (
    call :process_single_file "%%~i"
)

REM 清理临时文件
del "%temp_list%"

goto summary

REM 处理单个文件的子程序
:process_single_file
set "current_file=%~f1"

if not exist "%current_file%" (
    echo [警告] 文件不存在: "%~nx1"
    set /a failed_count+=1
    goto :eof
)

REM 验证是否有效视频文件
ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "%current_file%" >nul 2>&1
if errorlevel 1 (
    echo [警告] "%~nx1" 不是有效的视频文件，已跳过。
    set /a failed_count+=1
    goto :eof
)

set /a file_count+=1
echo.
echo ====== 处理文件 %file_count%/%total_files% ======
echo 正在处理: "%~nx1"
echo 文件路径: "%~f1"
echo 参数配置:
echo   修复模型: %RESTORATION_MODEL%
echo   检测模型: %DETECTION_MODEL%
echo   编码器:   %CODEC%
echo   CRF值:    %CRF%

REM 获取开始时间
for /f "tokens=1-4 delims=:.," %%a in ("%time%") do (
    set /a "start_h=%%a, start_m=1%%b-100, start_s=1%%c-100, start_cs=1%%d-100"
)

REM 输出目标文件路径
set "output_file=%~dpn1-La.mp4"

REM 执行 LADA 命令行工具
"%LADA_CLI_PATH%" ^
    --input "!current_file!" ^
    --output "!output_file!" ^
    --mosaic-restoration-model %RESTORATION_MODEL% ^
    --mosaic-detection-model-path "%DETECTION_MODEL%" ^
    --codec %CODEC% ^
    --device cuda:0 ^
    --max-clip-length 300 ^
    --custom-encoder-options "-rc vbr_hq -cq %CRF%"

if errorlevel 1 (
    echo [失败] 处理失败: "%~nx1"
    set /a failed_count+=1
    if exist "!output_file!" del "!output_file!"
    goto :eof
)

REM 记录结束时间
for /f "tokens=1-4 delims=:.," %%a in ("%time%") do (
    set /a "end_h=%%a, end_m=1%%b-100, end_s=1%%c-100, end_cs=1%%d-100"
)

REM 计算耗时（单位：厘秒）
set /a "duration=((end_h-start_h)*3600 + (end_m-start_m)*60 + (end_s-start_s)) * 100 + (end_cs-start_cs)"
if %duration% lss 0 set /a duration+=8640000

REM 累积总时间
set /a total_processing_time+=duration

REM 格式化显示时间
set /a "secs=%duration%/100, cs=%duration%%%100"
set /a "h=%secs%/3600, m=(%secs%%%3600)/60, s=%secs%%%60"

REM :: 【修复点 2】: 修正 if/else 语法错误并优化时间显示
if %h% gtr 0 (
    set "time_str=%h%小时 %m%分 %s%秒"
) else if %m% gtr 0 (
    set "time_str=%m%分 %s%秒"
) else (
    if !cs! lss 10 set "cs=0!cs!"
    set "time_str=%s%.!cs!秒"
)

echo [成功] 完成处理: "!output_file!"
echo 处理耗时: !time_str!
echo ========================
set /a processed_count+=1
goto :eof

:summary
REM 总时间格式化
set /a "tsec=%total_processing_time%/100, tcs=%total_processing_time%%%100"
set /a "th=%tsec%/3600, tm=(%tsec%%%3600)/60, ts=%tsec%%%60"

if %th% gtr 0 (
    set "total_time_str=%th%小时 %tm%分 %ts%秒"
) else if %tm% gtr 0 (
    set "total_time_str=%tm%分 %ts%秒"
) else (
    if !tcs! lss 10 set "tcs=0!tcs!"
    set "total_time_str=%ts%.!tcs!秒"
)

REM 显示汇总报告
echo.
echo ====== 最终统计 ======
echo 配置参数:
echo   修复模型: %RESTORATION_MODEL%
echo   检测模型: %DETECTION_MODEL%
echo   编码类型: %CODEC%
echo   CRF值:   %CRF%
echo.
echo 文件统计:
echo   总发现数量: %total_files% 个
echo   实际处理数量: %file_count% 个
echo   成功处理:   %processed_count% 个
echo   失败/跳过:   %failed_count% 个
echo.
echo 时间统计:
echo   总处理时间: !total_time_str!
if %file_count% gtr 0 (
    set /a avg_time=total_processing_time / file_count
    set /a "avg_sec=%avg_time%/100, avg_cs=%avg_time%%%100"
    if !avg_cs! lss 10 set avg_cs=0!avg_cs!
    echo   平均每项耗时: %avg_sec%.!avg_cs! 秒
)
echo ========================
echo.

REM 等待按键退出
pause
