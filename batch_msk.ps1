# 多媒体文件处理脚本

# 设置窗口标题
$host.UI.RawUI.WindowTitle = "视频批量修复工具"
# 设置全局前景色
$Host.UI.RawUI.ForegroundColor = "Green"

# 支持的多媒体文件扩展名
$mediaExtensions = @(
    ".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v"
)

# 设置并确认参数：
$Recurse = $false
$modelPath = "D:\Program Files\lada\_internal\model_weights\"
$modelName = "lada_mosaic_detection_model_v3.1_fast.pt"
$restorationModel = "basicvsrpp-v1.2"
$detectionModel = $modelPath + $modelName
$codec = "hevc_nvenc"
$cf = 16

# 处理输入参数
$fileList = @()
$inputPath = if ($args.Count -gt 0) { $args[0] } else {"D:\Videos\" }
$isDir = $false 
if (Test-Path $inputPath){  
    $inputPath = Get-Item $inputPath
    if ($inputPath.PSIsContainer) {$isDir = $true} 
} else {
    Write-Host "路径不存在: $inputPath" -ForegroundColor Red
    # 暂停以便查看结果
    Pause
    exit
}

$confirmed = $false
while ( -not $confirmed ) { 

    $fileList = @()
    # 获取所有文件
    if ($isDir) {
        if ($Recurse) {
            # 递归查找所有子文件夹中的多媒体文件
            $mediaFiles = Get-ChildItem -Path $inputPath -File -Recurse | Where-Object {
                $mediaExtensions -contains $_.Extension.ToLower()
            }
        } else {
            # 只查找当前文件夹中的多媒体文件
            $mediaFiles = Get-ChildItem -Path $inputPath -File | Where-Object {
                $mediaExtensions -contains $_.Extension.ToLower()
            }
        }
        
        $fileList += $mediaFiles
    } else {
        # 如果是文件，直接添加到列表
        if ($mediaExtensions -contains $inputPath.Extension.ToLower()) {
            # Write-Host "输入参数为媒体文件: $($inputPath.FullName)" -ForegroundColor Yellow
            $fileList += $inputPath
        }
    }

    # 显示默认参数：
    Write-Host ""
    Write-Host "当前使用的参数如下："
    if ($isDir) {
        Write-Host "  输入文件夹: $inputPath" -ForegroundColor Yellow
        Write-Host "  是否包含子文件夹：$Recurse" -ForegroundColor Yellow
        Write-Host "  文件数量：共找到 $($fileList.Count) 个文件需要处理" -ForegroundColor Yellow
    } else {
        Write-Host "  输入文件: $inputPath" -ForegroundColor Yellow
    }  
    Write-Host "" 
    Write-Host "  修复模型：$restorationModel" -ForegroundColor Yellow
    Write-Host "  检测模型：$modelName" -ForegroundColor Yellow
    Write-Host "  编码格式：$codec" -ForegroundColor Yellow
    Write-Host "  cf值: $cf" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "参数确认？(y/n): " -ForegroundColor Yellow -NoNewline
    $isConfirm = Read-Host
    if ($isConfirm -eq 'y' -or $isConfirm -eq 'Y') {
        Write-Host "参数已确认！" -ForegroundColor Yellow
        $confirmed = $true
        break
    } else {
        Write-Host "参数未确认，开始重新设置参数" -ForegroundColor Red
        Write-Host ""
    }

    # 确认是否递归处理子文件夹
    if ($isDir) {
        Write-Host "包含子文件夹？(y/n): " -ForegroundColor Yellow -NoNewline
        $isRecurse = Read-Host
        if ($isRecurse -eq 'y' -or $isRecurse -eq 'Y') {
            $Recurse = $true
        } else {
            $Recurse = $false
        }
    }    


    # 设置模型路径
    Write-Host ""
    Write-Host "请选择检测模型：(1, 2, 或 3)" -ForegroundColor Yellow
    Write-Host "  1. v3.1_fast(默认)" -ForegroundColor Yellow
    Write-Host "  2. v3.1_accurate" -ForegroundColor Yellow
    Write-Host "  3. v2" -ForegroundColor Yellow
    Write-Host "请选择(直接回车为默认): " -ForegroundColor Yellow -NoNewline
    $selectModel = Read-Host
    switch ($selectModel) {
        1 { $modelName = "lada_mosaic_detection_model_v3.1_fast.pt" }
        2 { $modelName = "lada_mosaic_detection_model_v3.1_accurate.pt" }
        3 { $modelName = "lada_mosaic_detection_model_v2.pt" }
        default {
            Write-Host "使用了默认的检测模型：$modelName"
        }
    }
    $detectionModel = $modelPath + $modelName

    # 设置输出的编码格式以及质量参数cf值
    Write-Host ""
    Write-Host "请选择编码格式：(1 或 2)" -ForegroundColor Yellow
    Write-Host "  1. hevc_nvenc(默认)" -ForegroundColor Yellow
    Write-Host "  2. h264_nvenc" -ForegroundColor Yellow
    Write-Host "请选择(直接回车为默认)： " -ForegroundColor Yellow -NoNewline
    $selectCodec = Read-Host
    if ($selectCodec -eq 2) {
        $codec = "h264_nvenc"
    } else {
        $codec = "hevc_nvenc"
    }
    Write-Host ""
    Write-Host "请选择视频质量cf值 (默认16): " -ForegroundColor Yellow -NoNewline
    $inputCf = Read-Host
    $cf = if ($inputCf -gt 0 -and $inputCf -lt 50) { $inputCf } else { 16 }
}


# 初始化统计变量
$fileCount = 0
$processedCount = 0
$failedCount = 0
$totalProcessingTime = [System.TimeSpan]::Zero

Write-Host ""
# 防止长时间执行任务时，电脑进入睡眠模式：
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

Write-Host ""
Write-Host "------开始批量处理媒体文件------"
# 遍历所有输入文件
foreach ($currentFile in $fileList) {
    $fileCount++

    # 检查文件是否存在
    if (-not (Test-Path $currentFile)) {
        Write-Host "[错误] 文件不存在: $(Split-Path $currentFile -Leaf)" -ForegroundColor Red
        $failedCount++
        continue
    }

    # 使用 ffprobe 检查是否为有效的音视频文件
    $ffprobeResult = & ffprobe -v error -select_streams v:0 -show_entries format=format_name -of default=nw=1 $currentFile 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 无效的音视频文件: $(Split-Path $currentFile -Leaf)" -ForegroundColor Red
        $failedCount++
        continue
    }

    # 构造输出文件路径
    $outputFile = [System.IO.Path]::GetDirectoryName($currentFile) + "\" + 
                  [System.IO.Path]::GetFileNameWithoutExtension($currentFile) + "_[修复].mp4"

    # 显示当前处理的文件信息
    Write-Host ""
    Write-Host "====== 文件 $fileCount/$($fileList.Count) ======"
    Write-Host "正在处理: $(Split-Path $currentFile -Leaf)"
    Write-Host "使用模型："
    Write-Host "  检测: $modelName"
    Write-Host "  修复: $restorationModel"
    Write-Host "编码信息："
    Write-Host "  编码: $codec"
    Write-Host "  cf值: $cf"

   
    # 记录开始时间
    $startTime = Get-Date

    # 执行 LADA CLI 工具进行视频处理
    try{
        & lada-cli.exe `
        --input "$currentFile" `
        --output "$outputFile" `
        --mosaic-restoration-model "$restorationModel" `
        --mosaic-detection-model-path "$detectionModel" `
        --codec "$codec" `
        --crf $cf `
        --device cuda:0 `
        --moov-front
        # 检查执行是否成功
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[失败] 处理失败: $(Split-Path $currentFile -Leaf)" -ForegroundColor Red
            $failedCount++
            if (Test-Path $outputFile) { Remove-Item $outputFile }
            continue
        }
    } catch {
        Write-Host "[失败] 处理失败: $(Split-Path $currentFile -Leaf)" -ForegroundColor Red
        Write-Host "错误信息: $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
        if (Test-Path $outputFile) { Remove-Item $outputFile }
        continue
    }
    

    # 记录结束时间并计算耗时
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $totalProcessingTime += $duration

    # 格式化时间显示
    $timeStr = if ($duration.Hours -gt 0) {
        "$($duration.Hours)小时 $($duration.Minutes)分 $($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    } elseif ($duration.Minutes -gt 0) {
        "$($duration.Minutes)分 $($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    } else {
        "$($duration.Seconds)秒 $($duration.Milliseconds)毫秒"
    }

    Write-Host "[成功] 已生成: $([System.IO.Path]::GetFileName($outputFile))" -ForegroundColor Yellow
    Write-Host "处理耗时: $timeStr" -ForegroundColor Yellow
    Write-Host "========================"

    $processedCount++
}

# 计算总耗时和平均耗时
$totalTimeStr = if ($totalProcessingTime.Hours -gt 0) {
    "$($totalProcessingTime.Hours)小时 $($totalProcessingTime.Minutes)分 $($totalProcessingTime.Seconds)秒 $($totalProcessingTime.Milliseconds)毫秒"
} elseif ($totalProcessingTime.Minutes -gt 0) {
    "$($totalProcessingTime.Minutes)分 $($totalProcessingTime.Seconds)秒 $($totalProcessingTime.Milliseconds)毫秒"
} else {
    "$($totalProcessingTime.Seconds)秒 $($totalProcessingTime.Milliseconds)毫秒"
}

$avgTime = if ($fileCount -gt 0) {
    $totalProcessingTime.TotalSeconds / $fileCount
} else {
    0
}

# 显示处理总结
$color_out = if ($failedCount -eq 0) {
    "Green"
} else {
    "Red"
}
Write-Host ""
Write-Host "====== 处理完成 ======" -ForegroundColor Yellow
Write-Host "使用的模型如下：" 
Write-Host "  修复模型：$restorationModel" 
Write-Host "  检测模型：$modelName" 
Write-Host "编码信息：" 
Write-Host "  编码: $codec" 
Write-Host "  cf值: $cf" 
Write-Host ""
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

# 暂停以便查看结果
Pause
exit