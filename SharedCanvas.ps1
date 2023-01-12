$Server = ""

$lol = $false

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$HashTable = [HashTable]::Synchronized(@{})
$HashTable.Lines = @()
$HashTable.FlattenedLines = [String[]]@()
$HashTable.Disposed = $false
$HashTable.DeltaIn = $false
$HashTable.DeltaOut = $false
$HashTable.OffsetX = 4
$HashTable.OffsetY = 26

$CPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
If($CPUs -lt 4){$CPUs = 4} #Lol, trash computers
$Runspace = [RunspaceFactory]::CreateRunspacePool(1,$CPUs)
$Runspace.Open()

$Form = [System.Windows.Forms.Form]::new()
$Form.Text = "Shared Canvas"
$Form.MaximizeBox = $false
$Form.FormBorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$Form.Height = $Form.Width = 750
$Form.Left = $Form.Top = 0

If($lol){
    $Form.FormBorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Form.TransparencyKey = $Form.BackColor
    $Form.AllowTransparency = $true
    $Form.Height = $Form.Width = 5000

    $Form.Show()
    $Form.TopMost = $true
    $Form.TopMost = $false # ~~~~
    $Form.TopMost = $true
    $Form.Hide()

    $HashTable.OffsetX = 0
    $HashTable.OffsetY = 0
}

$Jraphics = $Form.CreateGraphics()

$Quit = [System.windows.Forms.Button]::new()
$Quit.Text = "Quit"
$Quit.Width = 75
$Quit.Add_Click({$This.Parent.Close()})
$Quit.Parent = $Form

$Clear = [System.windows.Forms.Button]::new()
$Clear.Text = "Clear"
$Clear.Left = 75
$Clear.Width = 75
$Clear.Add_Click({
    $HashTable.Lines = @()
    $HashTable.FlattenedLines = [String[]]@()
    $HashTable.Clear = $true
    $HashTable.DeltaOut = $true

    $Form.Refresh()
})
$Clear.Parent = $Form

$Color = [System.windows.Forms.Button]::new()
$Color.Text = "Color"
$Color.Left = 600
$Color.Width = 75
$Color.BackColor = [System.Drawing.Color]::Black
$Color.ForeColor = [System.Drawing.Color]::White
$Color.Add_Click({
    $ColorDialog = [System.Windows.Forms.ColorDialog]::new()
    $ColorDialog.ShowDialog()
    $C = $ColorDialog.Color
    
    $This.BackColor = $C
    
    $Lum = [Math]::Sqrt(
        $C.R * $C.R * 0.299 +
        $C.G * $C.G * 0.587 +
        $C.B * $C.B * 0.114
    )
    If($Lum -gt 130){
        $This.ForeColor = [System.Drawing.Color]::Black
    }Else{
        $This.ForeColor = [System.Drawing.Color]::White
    }
})
$Color.Parent = $Form

$Size = [System.Windows.Forms.NumericUpDown]::new()
$Size.Width = 58
$Size.Top = 2
$Size.Left = 675
$Size.Maximum = 100
$Size.Minimum = 1
$Size.Parent = $Form

$SorterPosh = [Powershell]::Create()
$SorterPosh.RunspacePool = $Runspace
[Void]$SorterPosh.AddScript({
    param($T)
    While(!$T.Disposed){
        Try{
            $Sort = [String[]]($T.FlattenedLines | Sort {[int64]$_.Split(",")[0]})
            If($Sort.Count -eq $T.Lines.Count -and ![System.Linq.Enumerable]::SequenceEqual($T.FlattenedLines, $Sort)){
                $T.FlattenedLines = $Sort
                $T.Lines = ($T.Lines | Sort {$_.TS})
            }
        }Catch{}
        Sleep -Milliseconds 25
    }
})
[Void]$SorterPosh.AddParameter('T',$HashTable)
$SorterJob=$SorterPosh.BeginInvoke()

$GraphicsHandlerPosh = [Powershell]::Create()
$GraphicsHandlerPosh.RunspacePool = $GraphicsHandlerRunspace
[Void]$GraphicsHandlerPosh.AddScript({
    param($F,$J,$T)

    While(!$T.Disposed){
        If($T.DeltaIn){
            $F.Value.Refresh()
            ForEach($Line in $T.Lines){
                $J.Value.DrawLines($Line.Pen, $Line.Pts)
            }
            $T.DeltaIn = $false
        }
        Sleep -Milliseconds 10
    }
})
[Void]$GraphicsHandlerPosh.AddParameter('F',[ref]$Form)
[Void]$GraphicsHandlerPosh.AddParameter('J',[ref]$Jraphics)
[Void]$GraphicsHandlerPosh.AddParameter('T',$HashTable)
$GraphicsHandlerJob=$GraphicsHandlerPosh.BeginInvoke()

$FreeDrawPosh = [Powershell]::Create()
$FreeDrawPosh.RunspacePool = $Runspace
[Void]$FreeDrawPosh.AddScript({
    param($F,$J,$T)

    $F = $F.Value
    $J = $J.Value

    Try{
        Add-Type -Namespace "User" -Name "Keys" -MemberDefinition '
            [DllImport("user32.dll")]
            public static extern short GetKeyState(UInt16 virtualKeyCode);
        '
    }Catch{}

    $Pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black)

    $LastHash = $T
    While(!$T.Disposed){
        $LastPos = [System.Windows.Forms.Cursor]::Position
        $LastPos.X-=$F.Left+$T.OffsetX
        $LastPos.Y-=$F.Top+$T.OffsetY

        $Pen.Color = $F.Controls[2].BackColor
        $Pen.Width = $F.Controls[3].Value

        $Points = [System.Drawing.Point[]]@()
        While([User.Keys]::GetKeyState(0x01) -lt 0){
            Sleep -Milliseconds 10
            $CurrPos = [System.Windows.Forms.Cursor]::Position
            $CurrPos.X-=$F.Left+$T.OffsetX
            $CurrPos.Y-=$F.Top+$T.OffsetY
            If(($CurrPos.X -ne $LastPos.X -or $CurrPos.Y -ne $LastPos.Y) -and [User.Keys]::GetKeyState(0x01) -lt 0){
                $J.DrawLine($Pen, $LastPos.X, $LastPos.Y, $CurrPos.X, $CurrPos.Y)
                $Points+=($LastPos)
                $Points+=($CurrPos)
            }
            
            Sleep -Milliseconds 10
            $LastPos = [System.Windows.Forms.Cursor]::Position
            $LastPos.X-=$F.Left+$T.OffsetX
            $LastPos.Y-=$F.Top+$T.OffsetY
            If(($CurrPos.X -ne $LastPos.X -or $CurrPos.Y -ne $LastPos.Y) -and [User.Keys]::GetKeyState(0x01) -lt 0){
                $J.DrawLine($Pen, $CurrPos.X, $CurrPos.Y, $LastPos.X, $LastPos.Y)
                $Points+=($CurrPos)
                $Points+=($LastPos)
            }
        }

        If($Points.Count -gt 2){
            $TS = [datetime]::Now.ToFileTimeUtc()
            $T.Lines+=@{TS=$TS;Pen=$Pen.Clone();Pts=$Points}
            $T.FlattenedLines+=($TS.ToString()+"T"+$Pen.Color.ToArgb().ToString()+"C"+$Pen.Width.ToString()+"W"+[String]::Join("Y",$(ForEach($Pt in $Points){$Pt.X.ToString()+"X"+$Pt.Y.ToString()})))
            $T.DeltaOut = $true
        }
    }
})
[Void]$FreeDrawPosh.AddParameter('F',[ref]$Form)
[Void]$FreeDrawPosh.AddParameter('J',[ref]$Jraphics)
[Void]$FreeDrawPosh.AddParameter('T',$HashTable)
$FreeDrawJob=$FreeDrawPosh.BeginInvoke()

# Still need a clear button for the host

$CommsPosh = [Powershell]::Create()
$CommsPosh.RunspacePool = $Runspace
[Void]$CommsPosh.AddScript({
    param($T,$S)

    If(!$S){
        $Srv = [System.Net.Sockets.TcpListener]::new("0.0.0.0", 42069)
        $Srv.Start()

        $Buff = [Byte[]]::new(1024)
        $Streams = @()
        While(!$T.Disposed){
            If($Srv.Pending()){$Streams+=$Srv.AcceptTcpClientAsync().Result.GetStream()}

            $OutObj = "A"+[String]::Join("L", $T.FlattenedLines)+"Z"
            If($T.Clear){$OutObj = "AEMPTYZ";$T.Clear = $false}
            $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)

            $Clear = $false
            ForEach($Stream in $Streams){
                If($T.DeltaOut){$Stream.Write($OutObj, 0, $OutObj.Length)}
                
                If($Stream.DataAvailable){
                    $InObj = ""
                    While($Stream.DataAvailable){
                        $InCount = $Stream.Read($Buff, 0, 1024)
                        $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                    }
                    Try{
                        If($InObj -match "A" -and $InObj -match "Z"){
                            ForEach($Line in ($InObj -replace "^.*?A" -replace "Z.*").Split("L")){
                                If(!$T.FlattenedLines.Contains($Line) -and $Line -ne "EMPTY"){
                                    $T.FlattenedLines+=$Line

                                    $T.Lines+=@{
                                        TS=[int64]($Line -replace "T.*");
                                        Pen=[System.Drawing.Pen]::new(
                                            [System.Drawing.Color]::FromArgb([int]($Line -replace "^.*?T" -replace "C.*")),
                                            [Int]($Line -replace "^.*?C" -replace "W.*")
                                        );
                                        Pts=[System.Drawing.Point[]]$(
                                            ForEach($Coords in ($Line -replace "^.*?W").Split("Y")){
                                                [System.Drawing.Point]::new(
                                                    [int]($Coords -replace "X.*"),
                                                    [int]($Coords -replace "^.*?X")
                                                )
                                            }
                                        )
                                    }
                                    $T.DeltaIn = $true
                                }ElseIf($Line -eq "EMPTY"){
                                    $Clear = $true
                                }
                            }
                        }
                    }Catch{
                        $InObj | Out-File C:\Temp\Badsrv.txt
                        $Error[0] | Out-String | Out-file -Append C:\Temp\asyncErr.txt
                    }
                }
            }
            If($Clear){
                $T.Lines = @()
                $T.FlattenedLines = [String[]]@()
                $T.DeltaIn = $true
                $T.Clear = $true
            }Else{
                $T.DeltaOut = $false
            }

            Sleep -Milliseconds 250
        }

        ForEach($Stream in $Streams){$Stream.Close;$Stream.Dispose()}
        $Srv.Stop()

    }Else{
        $Client = [System.Net.Sockets.TcpClient]::New($S, 42069)
        $Stream = $Client.GetStream()

        $Buff = [Byte[]]::new(1024)
        While(!$T.Disposed -and $Client.Connected){
            $OutObj = "A"+[String]::Join("L", $T.FlattenedLines)+"Z"
            If($T.Clear){$OutObj = "AEMPTYZ";$T.Clear = $false}
            $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
            If($T.DeltaOut){$Stream.Write($OutObj, 0, $OutObj.Length);$T.DeltaOut = $false}

            If($Stream.DataAvailable){
                $InObj = ""
                While($Stream.DataAvailable){
                    $InCount = $Stream.Read($Buff, 0, 1024)
                    $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                }
                Try{
                    If($InObj -match "A" -and $InObj -match "Z"){
                        ForEach($Line in ($InObj -replace "^.*?A" -replace "Z.*").Split("L")){
                            If(!$T.FlattenedLines.Contains($Line) -and $Line -ne "EMPTY"){
                                $T.FlattenedLines+=$Line

                                $T.Lines+=@{
                                    TS=[int64]($Line -replace "T.*");
                                    Pen=[System.Drawing.Pen]::new(
                                        [System.Drawing.Color]::FromArgb([int]($Line -replace "^.*?T" -replace "C.*")),
                                        [Int]($Line -replace "^.*?C" -replace "W.*")
                                    );
                                    Pts=[System.Drawing.Point[]]$(
                                        ForEach($Coords in ($Line -replace "^.*?W").Split("Y")){
                                            [System.Drawing.Point]::new(
                                                [int]($Coords -replace "X.*"),
                                                [int]($Coords -replace "^.*?X")
                                            )
                                        }
                                    )
                                }
                                $T.DeltaIn = $true
                            }ElseIf($Line -eq "EMPTY"){
                                $T.Lines = @()
                                $T.FlattenedLines = [String[]]@()
                                $T.DeltaIn = $true
                                $T.Clear = $true
                            }
                        }
                    }
                }Catch{
                    $InObj | Out-File C:\Temp\Badsrv.txt
                    $Error[0] | Out-String | Out-file -Append C:\Temp\asyncErr.txt
                }
            }

            Sleep -Milliseconds 250
        }

        $Client.Close()
        $Client.Dispose()
    }
})
[Void]$CommsPosh.AddParameter('T',$HashTable)
[Void]$CommsPosh.AddParameter('S',$Server)
$CommsJob=$CommsPosh.BeginInvoke()

$Form.ShowDialog()
$Form.Dispose()

$HashTable.Disposed = $true

[Void]$SorterPosh.EndInvoke($SorterJob)
[Void]$GraphicsHandlerPosh.EndInvoke($GraphicsHandlerJob)
[Void]$FreeDrawPosh.EndInvoke($FreeDrawJob)
[Void]$CommsPosh.EndInvoke($CommsJob)
$Runspace.Close()
