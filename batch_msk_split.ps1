# 多媒体文件处理脚本


#region Script Parameters
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="请输入要处理的视频文件的路径")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "错误：文件路径未找到，请提供一个有效的文件路径。"
        }
        return $true
    })]
    [string]$inputPathStr
)

# 设置窗口标题
$host.UI.RawUI.WindowTitle = "视频批量修复工具"
# 设置全局前景色
$Host.UI.RawUI.ForegroundColor = "Green"

# # 设置环境编码：
# chcp 65001  # 设置命令本身编码为 UTF8
# # 设置控制台输出编码为 UTF-8
# [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# # 设置控制台输入编码为 UTF-8
# [Console]::InputEncoding = [System.Text.Encoding]::UTF8


# 文件相关参数：
# 支持的多媒体文件扩展名
$script:mediaExtensions = @(
    ".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v"
)
$script:Recurse = $false
$script:fileList = @()
$script:inputPath =  Get-Item -LiteralPath $inputPathStr
$script:isDir = if ($script:inputPath.PSIsContainer) {$true} else {$false}
$script:isSplit = $false
$script:splitDuration = 1800 # 30分钟

# lada-cli参数
$script:MAX_CLIP_LENGTH = 300
$script:modelPath = "D:\Programs\lada-v0.8.2\_internal\model_weights\"
$script:modelName = "lada_mosaic_detection_model_v3.1_accurate.pt"
$script:restorationModel = "basicvsrpp-v1.2"
$script:detectionModel = $modelPath + $modelName
$script:codec = "hevc_nvenc"
$script:crfDefault = 17
$script:qmax = 28
$script:crf = $script:crfDefault

# 任务完成后是否关机：
$script:autoShutdown = $false

#region Script Parameters end

# 测试 ffmpeg/ffprobe/lada-cli等命令是否可用
function Test-ToolsAvailability {
    <#
    .SYNOPSIS
        检查 ffmpeg/ffprobe/lada-cli 是否已安装并在系统 PATH 中。
    #>
    $cmd_list = @("ffmpeg", "ffprobe", "lada-cli")
    foreach ($cmd in $cmd_list) {
        $cmdPath = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $cmdPath) {
            Write-Error "错误：未在系统 PATH 中找到 $cmd.exe。请确保已安装 $cmd 并将其添加到环境变量中。"
            Pause
            exit
        }
    }
}

# 检测是否是有效的视频文件：
function Check-VideoFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$videoFile
    )

    # 检查文件是否存在
    if (-not (Test-Path -LiteralPath $videoFile)) {
        Write-Host "[错误] 文件不存在:  $videoFile" -ForegroundColor Red
        return $false
    }

    # 使用 ffprobe 检查是否为有效的音视频文件
    $ffprobeResult = & ffprobe -v error -select_streams v:0 -show_entries format=format_name -of default=nw=1 $videoFile 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 无效的音视频文件: $videoFile" -ForegroundColor Red
        return $false
    }
    # 是有效的视频文件
    return $true
}
# 显示当前参数：
function Dispay-Parameters {
    Write-Host ('*'*80)
    Write-Host "当前使用的参数如下："
    if ($script:isDir) {
        Write-Host "  输入文件夹: $inputPathStr" -ForegroundColor Yellow
        Write-Host "  是否包含子文件夹：$script:Recurse" -ForegroundColor Yellow
        Write-Host "  文件数量：共找到 $($script:fileList.Count) 个文件需要处理" -ForegroundColor Yellow
    } else {
        Write-Host "  输入文件: $inputPathStr" -ForegroundColor Yellow
    }  
    Write-Host "  任务完成后是否关机：$script:autoShutdown" -ForegroundColor Yellow
    if($script:isSplit) {
        Write-Host "  视频分段处理：是" -ForegroundColor Yellow
        Write-Host "  视频分段长度：$($script:splitDuration/60) 分钟" -ForegroundColor Yellow
    }else {
        Write-Host "  视频分段处理：否" -ForegroundColor Yellow
    }
    Write-Host '  ---------------------------'
    Write-Host "  修复模型：$script:restorationModel" -ForegroundColor Yellow
    Write-Host "  检测模型：$script:modelName" -ForegroundColor Yellow
    Write-Host "  编码格式：$script:codec" -ForegroundColor Yellow
    Write-Host "  crf值: $script:crf" -ForegroundColor Yellow
    Write-Host ('*'*80)
}

# 格式化时间显示
function Format-TimeSpan($duration) {
    $timeStr = if ($duration.Hours -gt 0) {
        "$($duration.Hours)小时 $($duration.Minutes)分 $($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    } elseif ($duration.Minutes -gt 0) {
        "$($duration.Minutes)分 $($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    } else {
        "$($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    }
    return $timeStr
}
# 设置并确认参数：
function Confirm-Parameters {
    Write-Host "正在确认参数..." -ForegroundColor Yellow
    $confirmed = $false
    while ( -not $confirmed ) { 
        $script:fileList = @()
        # 获取所有文件
        if ($script:isDir) {
            if ($script:Recurse) {
                # 递归查找所有子文件夹中的多媒体文件
                $mediaFiles = Get-ChildItem -LiteralPath $script:inputPath -File -Recurse | Where-Object {
                    $script:mediaExtensions -contains $_.Extension.ToLower()
                }
            } else {
                # 只查找当前文件夹中的多媒体文件
                $mediaFiles = Get-ChildItem -LiteralPath $script:inputPath -File | Where-Object {
                    $script:mediaExtensions -contains $_.Extension.ToLower()
                }
            }
            foreach ($mediaFile in $mediaFiles) { 
                if (Check-VideoFile $mediaFile.FullName){
                    $script:fileList += $mediaFile.FullName
                }
            }

                        
        } else {
            # 如果是文件，直接添加到列表
            if ($script:mediaExtensions -contains $script:inputPath.Extension.ToLower()) {
                if (Check-VideoFile($script:inputPath)){
                    $script:fileList += $script:inputPath.FullName
                }
            }
            else {
                Write-Host "输入参数不是媒体文件，请重新输入！" -ForegroundColor Red
                Exit-PSHostProcess
            }
        }

        # 显示参数
        Dispay-Parameters

        # 确认参数
        Write-Host "参数确认？(y确认，e退出程序): " -ForegroundColor Yellow -NoNewline
        $isConfirm = Read-Host
        if ($isConfirm -eq 'y' -or $isConfirm -eq 'Y') {
            Write-Host "参数已确认！" -ForegroundColor Yellow
            $confirmed = $true
            break
        } elseif ($isConfirm -eq 'e' -or $isConfirm -eq 'E') {
            Write-Host "程序已退出！" -ForegroundColor Red
            exit
        } else {
            Write-Host "参数未确认，开始重新设置参数" -ForegroundColor Red
            Write-Host ""
        }

        # 确认是否递归处理子文件夹
        if ($script:isDir) {
            Write-Host "包含子文件夹？(y/n): " -ForegroundColor Yellow -NoNewline
            $isRecurse = Read-Host
            if ($isRecurse -eq 'y' -or $isRecurse -eq 'Y') {
                $script:Recurse = $true
            } else {
                $script:Recurse = $false
            }
        } 
        
        # 确认是否分段处理视频
        Write-Host "是否分段处理视频？(y/n): " -ForegroundColor Yellow -NoNewline
        $selectSplit = Read-Host
        if ($selectSplit -eq 'y' -or $selectSplit -eq 'Y') {
            Write-Host "请输入分段长度（分钟）: " -ForegroundColor Yellow -NoNewline
            $seg_time = Read-Host
            # 验证输入是否为数字
            if ($seg_time -match '^\d+$') {
                $script:splitDuration = [int]$seg_time * 60
            } else {
                Write-Host "输入不是有效数字！已使用默认值：30分钟" -ForegroundColor Red
                $script:splitDuration = 180
            }
            $script:isSplit = $true
        } else {
            $script:isSplit = $false
        }


        # 确认是否需要关机
        Write-Host "设置任务完成后关机？(y/n): " -ForegroundColor Yellow -NoNewline
        $isShutdown = Read-Host
        if ($isShutdown -eq 'y' -or $isShutdown -eq 'Y') {
            $script:autoShutdown = $true
        } else {
            $script:autoShutdown = $false
        }


        # 设置模型路径
        Write-Host ""
        Write-Host "请选择检测模型：(1, 2, 或 3)" -ForegroundColor Yellow
        Write-Host "  1. v3.1_accurate(默认)" -ForegroundColor Yellow
        Write-Host "  2. v3.1_fast" -ForegroundColor Yellow
        Write-Host "  3. v2" -ForegroundColor Yellow
        Write-Host "请选择(直接回车为默认): " -ForegroundColor Yellow -NoNewline
        $selectModel = Read-Host
        switch ($selectModel) {
            1 { $modelName = "lada_mosaic_detection_model_v3.1_accurate.pt" }
            2 { $modelName = "lada_mosaic_detection_model_v3.1_fast.pt" }
            3 { $modelName = "lada_mosaic_detection_model_v2.pt" }
            default {
                $modelName = "lada_mosaic_detection_model_v3.1_accurate.pt"
                Write-Host "使用了默认的检测模型：$modelName"
            }
        }
        $script:detectionModel = $script:modelPath + $modelName

        # 设置输出的编码格式以及质量参数crf值
        Write-Host ""
        Write-Host "请选择编码格式：(1 或 2)" -ForegroundColor Yellow
        Write-Host "  1. hevc_nvenc(默认)" -ForegroundColor Yellow
        Write-Host "  2. h264_nvenc" -ForegroundColor Yellow
        Write-Host "请选择(直接回车为默认)： " -ForegroundColor Yellow -NoNewline
        $selectCodec = Read-Host
        if ($selectCodec -eq 2) {
            $script:codec = "h264_nvenc"
        } else {
            $script:codec = "hevc_nvenc"
        }
        Write-Host ""
        Write-Host "请选择视频质量crf值 (默认$script:crfDefault): " -ForegroundColor Yellow -NoNewline
        $inputCf = Read-Host
        $script:crf = if ($inputCf -gt 10 -and $inputCf -lt 30) { $inputCf } else { $script:crfDefault }
    }
}


# 切割视频
function Split-Video {
    <#
    .SYNOPSIS
        创建临时目录并将源视频分割成片段。
    #>
    param(
        [string]$SourceFile,
        [int]$SegmentDuration,
        [string]$TempDirectory
    )
    
    Write-Host "`n--- 创建临时目录并分割视频 ---" -ForegroundColor Yellow
    New-Item -Path $TempDirectory -ItemType Directory -Force | Out-Null
    Write-Host "已创建临时目录: $TempDirectory"

    $fileExtension = [System.IO.Path]::GetExtension($SourceFile)
    $splitArgs = "-i `"$SourceFile`" -c copy -map 0 -segment_time $SegmentDuration -f segment -reset_timestamps 1 `"$TempDirectory\segment_%04d$fileExtension`""
    
    Write-Host "执行分割命令: ffmpeg $splitArgs"
    $process = Start-Process ffmpeg -ArgumentList $splitArgs -Wait -NoNewWindow -PassThru
    
    if ($process.ExitCode -ne 0) {
        Write-Error "视频分割失败。请检查 FFmpeg 输出以获取详细信息。"
        return 1
    }
    Write-Host "视频分割完成。" -ForegroundColor Green
}


function Merge-VideoSegments {
    <#
    .SYNOPSIS
        将处理过的片段合并成最终的视频文件。
    #>
    param(
        [string[]]$SegmentPaths,
        [string]$TempDirectory,
        [string]$OutputFile
    )
    
    Write-Host "`n--- 开始合并所有处理过的片段 ---" -ForegroundColor Yellow

    # 创建 ffmpeg concat demuxer 需要的列表文件
    $listFilePath = Join-Path -Path $TempDirectory -ChildPath "filelist.txt"
    $fileListContent = $SegmentPaths | ForEach-Object { "file '$($_ -replace '\\', '/')'" }
    Set-Content -Path $listFilePath -Value $fileListContent -Encoding UTF8
    Write-Host "生成的合并列表文件: $listFilePath"

    # 使用 concat demuxer 进行无损合并
    $mergeArgs = "-f concat -safe 0 -i `"$listFilePath`" -c copy `"$OutputFile`""
    Write-Host "执行合并命令: ffmpeg $mergeArgs"
    
    $process = Start-Process ffmpeg -ArgumentList $mergeArgs -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Error "合并视频失败: $TempDirectory"
        return 1
    }
    
    Write-Host "视频合并完成: $TempDirectory" -ForegroundColor Green
}

function Remove-TemporaryFiles {
    <#
    .SYNOPSIS
        删除包含所有中间文件的临时目录。
    #>
    param(
        [string]$TempDirectory
    )

    if (Test-Path $TempDirectory) {
        Write-Host "`n--- 清理临时文件 ---" -ForegroundColor Yellow
        Write-Host "正在删除临时目录: $TempDirectory"
        Remove-Item -Path $TempDirectory -Recurse -Force
        Write-Host "清理完成。" -ForegroundColor Green
    }
}


function Restore-Video {
    param (
        [string]$inputFile,
        [string]$outputFile=$null
    )
    # 显示当前处理的文件信息
    Write-Host ""
    Write-Host "正在处理:  $inputFile" -ForegroundColor Yellow

    # if (-not $outputFile) {
    #     # 获取输出文件名: 当前文件名 + "_修复后.mp4"
    #     $outname =  (Split-Path $inputFile  -LeafBase) + "_修复后.mp4"
    #     $outputFile = Join-Path (Split-Path $inputFile) $outname
    # }

    # 填写 lada-cli 的参数：
    $cli_params = @(
        "--input", "$inputFile",
        # "--output", "$outputFile",
        "--device", "cuda:0",
        "--mosaic-restoration-model", "$script:restorationModel",
        "--mosaic-detection-model-path", "$script:detectionModel",
        "--codec", $script:codec,
        # "--crf", $script:crf,
        "--max-clip-length", $script:MAX_CLIP_LENGTH
        "--custom-encoder-options", "-cq $script:crf"
    )
    # 记录开始时间
    $startTime = Get-Date
    # 执行 LADA CLI 工具进行视频处理
    # `-c:a copy` 表示 “复制原始音频编码数据”
    # --max-clip-length MAX_CLIP_LENGTH
    # 修复时模型每次最多处理的帧数。较高的值可增强时间稳定性，较低的值可减少显存占用
    # 若设置过低，可能会出现画面闪烁。 (默认: 180)
    try{
        
        # PS2exe编译后，外部命令运行时产生的输出会被当做错误输出（2），后面加入2>&1，将错误输出重定向到标准输出
        $cmd_para = "lada-cli.exe "+ $cli_params -join " "
        Write-Host "$cmd_para"
        & lada-cli.exe @cli_params 2>&1
        # $r = & lada-cli.exe @cli_params
        # $cmd_para

        # # 按原始格式处理输出（不触发错误标记）
        # Write-Host $output -ForegroundColor ($LASTEXITCODE -eq 0 ? "Green" : "Red")
        # $cli_params = "-i `"$inputFile`" -c:v libx264 -preset medium -crf 28 -c:a copy `"$outputFile`""
        
        # 检查执行是否成功
        if ($LASTEXITCODE -eq 0) {
            # 记录结束时间并计算耗时
            $endTime = Get-Date
            $duration = $endTime - $startTime
            $timeStr = Format-TimeSpan $duration
            Write-Host "[成功] 已生成: $outname" -ForegroundColor Yellow
            Write-Host "处理耗时: $timeStr" -ForegroundColor Yellow
            Write-Host "========================"
            return 0
            
        } else {
            Write-Host "[失败] 处理失败: $inputFile" -ForegroundColor Red
            if (Test-Path $outputFile) { Remove-Item $outputFile }
            return 1
        }
    } catch {
        Write-Host "[失败] 处理失败: $inputFile" -ForegroundColor Red
        Write-Host "错误信息: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $outputFile) { Remove-Item $outputFile }
        return 1
    }
}

function Split_Restore {
    param (
        [string]$VideoFile,
        # 每个分割片段的时长（秒）
        [int]$Duration
    )
    # 显示当前处理的文件信息
    Write-Host ""
    Write-Host "正在拆分处理: $VideoFile" -ForegroundColor Yellow

    # --- 变量初始化 ---
    $fileInfo = Get-Item $VideoFile
    $fileDirectory = $fileInfo.DirectoryName
    $fileBaseName = $fileInfo.BaseName
    $fileExtension = $fileInfo.Extension
    $outputFile = Join-Path -Path $fileDirectory -ChildPath "$($fileBaseName)_修复后.mp4"
    $tempDir = Join-Path -Path $fileDirectory -ChildPath "temp_video_processing_$(Get-Random)"

    # --- 流程 ---
    try {
        # 1. 分割视频
        Split-Video -SourceFile $VideoFile -SegmentDuration $Duration -TempDirectory $tempDir

        # 2. 处理片段
        Write-Host "`n--- 开始处理分割后的片段 ---" -ForegroundColor Yellow
        $segments = Get-ChildItem -Path $tempDir -Filter "segment_*$($FileExtension)" | Sort-Object Name
        if ($segments.Count -eq 0) {
            Write-Warning "警告：在临时目录中未找到任何分割后的视频片段。"
            return @() # 返回空数组
        }

        $processedSegmentPaths = @()
        $totalSegments = $segments.Count
        $currentSegment = 1

        foreach ($segment in $segments) {
            Write-Host "正在处理片段 $currentSegment / $totalSegments : $($segment.Name)"
            $fileBaseName = $segment.BaseName
            $directory = $segment.DirectoryName
            $inputSegmentPath = $segment.FullName
            $outputSegmentPath =Join-Path  -Path $directory  "$($fileBaseName)_修复后.mp4"  
            Write-Host "输出片段路径: $outputSegmentPath"
            
            # ===================================================================
            # !!! 在这里定义你的处理逻辑 !!!            
            # $result_code = Copy-Item "$inputSegmentPath" -Destination "$outputSegmentPath"
            # Write-Host "  处理片段结束: $inputSegmentPath "
            # ===================================================================

            Write-Host "  开始执行片段的修复命令: lada-cli"
            $result_code = Restore-Video -inputFile "$inputSegmentPath" -outputFile "$outputSegmentPath"
            
            if ($result_code -and $result_code[-1] -eq 0) {
                # 为节省空间，将已处理的视频片段删除
                Remove-Item $inputSegmentPath -Force
            } else {
                throw "处理片段 $($segment.Name) 失败。"
            }
            
            Write-Host "  已生成: $outputSegmentPath" -ForegroundColor Green
            $processedSegmentPaths += $outputSegmentPath
            $currentSegment++
        }
        Write-Host "所有片段修复完成。" -ForegroundColor Green

        # 3. 如果有处理好的文件，则合并
        if ($processedSegmentPaths -and $processedSegmentPaths.Count -gt 0) {
            Merge-VideoSegments -SegmentPaths $processedSegmentPaths -TempDirectory $tempDir -OutputFile $outputFile
            Write-Host "`n--- 所有任务已成功完成！ ---" -ForegroundColor Cyan
            Write-Host "最终生成的视频文件位于:"
            Write-Host $outputFile -ForegroundColor White
        } else {
            Write-Warning "没有生成任何处理过的文件，跳过合并步骤。"
        }
        # 如果处理成功，则清理临时文件
        Remove-TemporaryFiles -TempDirectory $tempDir
        return 0
    }
    catch {
        # 捕获任何函数中抛出的错误，保留已处理的视频片段：
        Write-Error "脚本执行过程中发生严重错误: $($_.Exception.Message)"
        Write-Error "请手动清理临时文件夹： $tempDir"
        return 1
    }
    # finally {
    #     # 5. 无论成功或失败，都清理临时文件
    #     Remove-TemporaryFiles -TempDirectory $tempDir
    # }

}

# 防止长时间执行任务时，电脑进入睡眠模式：
function Clear-Sleep {
    try {
        # 防止系统睡眠
        Write-Host "正在禁用睡眠模式..." -ForegroundColor Yellow
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        Write-Host "已完成" -ForegroundColor Yellow
    } 
    catch {
            Write-Host "无法禁用睡眠模式，请手动禁用:: $($_.Exception.Message)" -ForegroundColor Red
    }
}
# 任务完成后关闭电脑：
function Close-Computer {
    try {
        Write-Host "系统将在20秒后关机...(按 Ctrl+C 可取消)" -ForegroundColor Red
        Start-Sleep -Seconds 20
        Stop-Computer -Force
    } 
    catch {
        Write-Host "无法关闭计算机，请手动关闭:: $($_.Exception.Message)" -ForegroundColor Red
    }
}




#########################################################################
# 主程序从这里开始。。。。。。。。。

# 检测工具依赖项是否可用
# Test-ToolsAvailability

# 获取并确认输入参数:
Confirm-Parameters
# 如果文件列表为空，则退出程序
if($script:fileList.Count -eq 0) {
    Write-Error "输入文件列表为空"
    Pause
    exit
}

# 初始化统计变量
$fileCount = 0
$processedCount = 0
$failedCount = 0
$totalProcessingTime = [System.TimeSpan]::Zero

# 防止长时间执行任务时，电脑进入睡眠模式：
Clear-Sleep

Write-Host ""
Write-Host "------开始批量处理媒体文件------"

# 记录开始时间
$startTotalTime = Get-Date

# 遍历所有输入文件
foreach ($currentFile in $script:fileList) {
    $fileCount++

    # 显示当前处理的文件信息
    Write-Host ""
    Write-Host "====== 文件 $fileCount/$($script:fileList.Count) ======"
    # $result = Restore-Video $currentFile
    if($script:isSplit) {
        Split_Restore $currentFile $script:splitDuration
    } else {
        Restore-Video $currentFile
    }
    
    if ($LASTEXITCODE -eq 0) {
        $processedCount++
    } else {
        $failedCount++
    }
}

# 计算总耗时和平均耗时
$endTotalTime = Get-Date
$totalProcessingTime = $endTotalTime - $startTotalTime
$totalTimeStr = Format-TimeSpan $totalProcessingTime
$avgTime = if ($fileCount -gt 0) {
    $totalProcessingTime.TotalSeconds / $fileCount
} else {
    0
}

# 显示处理总结
$color_out = if ($failedCount -eq 0) {"Green"} else {"Red"}
Write-Host ""
Write-Host "====== 处理完成 ======" -ForegroundColor Yellow
Write-Host "文件统计：" 
Write-Host "  总文件数: $fileCount 个"
Write-Host "  成功处理: $processedCount 个" 
Write-Host "  失败文件: $failedCount 个" -ForegroundColor $color_out
Write-Host ""
Write-Host "时间统计：" 
Write-Host "  总处理时间: $totalTimeStr" 
if ($fileCount -gt 0) {
    Write-Host "  平均每个文件: $([math]::Round($avgTime, 2)) 秒" 
}
Write-Host "========================" -ForegroundColor Yellow
Write-Host ""

# 如果指定了自动关机，则执行
if ($script:autoShutdown) { Close-Computer }

# 暂停以便查看结果
Pause

# 退出程序
exit

#############主程序结束############################################
