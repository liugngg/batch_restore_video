# 1. 批量修复视频工具

## 1.1. 主要功能：
1. 采用 powershell 实现；
2. 查找输入文件或目录中的所有视频文件，使用`lada-cli`进行修复；
3. 修复视频前，主要参数可确认和修改；
4. 在任务执行前，支持取消电脑睡眠或休眠功能；
5. 支持任务完成后自动关机。

## 1.2. 使用方法：
- 使用方法比较简单，略

## 1.3. 编译成可执行文件
  1. 首先需要安装PS2EXE：
     `Install-Module -Name PS2EXE -Scope CurrentUser -Force`  
  2. 将PS1脚本编译成EXE可执行文件：
     `Invoke-PS2EXE -InputFile .\batch_msk.ps1  -OutputFile "batch_msk.exe"`
