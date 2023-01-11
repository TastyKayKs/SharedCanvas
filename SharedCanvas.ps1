$Server = ""

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$HashTable = [HashTable]::Synchronized(@{})
$HashTable.Lines = @()
$HashTable.FlattenedLines = [String[]]@()
$HashTable.Disposed = $false
$HashTable.DeltaIn = $false
$HashTable.DeltaOut = $false

$CPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$Runspace = [RunspaceFactory]::CreateRunspacePool(1,$CPUs)
$Runspace.Open()

$Form = [System.Windows.Forms.Form]::new()
$Form.Text = "Shared Canvas"
$Form.MaximizeBox = $false
$Form.FormBorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$Form.Height = $Form.Width = 500
$Form.Left = $Form.Top = 0

$Jraphics = $Form.CreateGraphics()

$Color = [System.windows.Forms.Button]::new()
$Color.Text = "Color"
$Color.Width = 250
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
$Size.Width = 240
$Size.Top = 2
$Size.Left = 250
$Size.Maximum = 100
$Size.Minimum = 1
$Size.Parent = $Form

$SorterPosh = [Powershell]::Create()
$SorterPosh.RunspacePool = $Runspace
[Void]$SorterPosh.AddScript({
    param($T)
    While(!$T.Disposed){
        $Sort = [String[]]($T.FlattenedLines | Sort {[int64]$_.Split(",")[0]})
        If($Sort.Count -eq $T.Lines.Count -and ![System.Linq.Enumerable]::SequenceEqual($T.FlattenedLines, $Sort)){
            $T.FlattenedLines = $Sort
            $T.Lines = ($T.Lines | Sort {$_.TS})
        }
        Sleep -Milliseconds 25
    }
})
[Void]$SorterPosh.AddParameter('T',$HashTable)
$SorterJob=$SorterPosh.BeginInvoke()

$GraphicsHandlerPosh = [Powershell]::Create()
$GraphicsHandlerPosh.RunspacePool = $GraphicsHandlerRunspace
[Void]$GraphicsHandlerPosh.AddScript({
    param($J,$T)

    $J = $J.Value
    While(!$T.Disposed){
        If($T.DeltaIn){
            $J.Clear()
            ForEach($Line in $T.Lines){
                $J.DrawLines($Line.Pen, $Line.Pts)
            }
            $T.DeltaIn = $false
        }
        Sleep -Milliseconds 10
    }
})
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
        $LastPos.X-=$F.Left+4
        $LastPos.Y-=$F.Top+26

        $Points = [System.Drawing.Point[]]@()
        While([User.Keys]::GetKeyState(0x01) -lt 0){
            Sleep -Milliseconds 10
            
            $CurrPos = [System.Windows.Forms.Cursor]::Position
            $CurrPos.X-=$F.Left+4
            $CurrPos.Y-=$F.Top+26

            $Pen.Color = $F.Controls[0].BackColor
            $Pen.Width = $F.Controls[1].Value
            If(($CurrPos.X -ne $LastPos.X -or $CurrPos.Y -ne $LastPos.Y) -and [User.Keys]::GetKeyState(0x01) -lt 0){
                $J.DrawLine($Pen, $LastPos.X, $LastPos.Y, $CurrPos.X, $CurrPos.Y)
                $Points+=($LastPos)
                $Points+=($CurrPos)
            }
            Sleep -Milliseconds 10
            $LastPos = [System.Windows.Forms.Cursor]::Position
            $LastPos.X-=$F.Left+4
            $LastPos.Y-=$F.Top+26
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

#Start Job to accept tcp connections and append the lines received to drawing table (clear incoming?)
#Send out copy of lines (append to outgoing?)

$CommsPosh = [Powershell]::Create()
$CommsPosh.RunspacePool = $Runspace
[Void]$CommsPosh.AddScript({
    param($T,$S)

    If(!$S){
        $AsyncCallback = [System.AsyncCallback]{
            param($Result)
            
            $Client = $Srv.EndAcceptTcpClient($Result)
            $Stream = $Client.GetStream()

            $Buff = [Byte[]]::new(1024)
            While(!$T.Disposed -and $Client.Connected){
                If($T.DeltaOut){
                    $OutObj = "A"+[String]::Join("L", $T.FlattenedLines)+"Z"
                    $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
                    $Stream.Write($OutObj, 0, $OutObj.Length)
                    $T.DeltaOut = $false
                }
                
                If($Stream.DataAvailable){
                    $InObj = ""
                    While($Stream.DataAvailable){
                        $InCount = $Stream.Read($Buff, 0, 1024)
                        $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                    }
                    Try{
                        If($InObj -match "A" -and $InObj -match "Z"){
                            ForEach($Line in ($InObj -replace "^.*?A" -replace "Z.*").Split("L")){
                                If(!$T.FlattenedLines.Contains($Line)){
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
        $Srv = [System.Net.Sockets.TcpListener]::new("0.0.0.0", 42069)
        $Srv.Start()
        $TESTCOUNT = 0
        While(!$T.Disposed){
            If($Srv.Pending()){
                $Result = $Srv.BeginAcceptTcpClient($AsyncCallBack,$Srv)
            }
        }
        $Srv.Stop()
    }Else{
        $Client = [System.Net.Sockets.TcpClient]::New($S, 42069)
        $Stream = $Client.GetStream()

        $Buff = [Byte[]]::new(1024)
        While(!$T.Disposed -and $Client.Connected){
            If($T.DeltaOut){
                $OutObj = "A"+[String]::Join("L", $T.FlattenedLines)+"Z"
                $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
                $Stream.Write($OutObj, 0, $OutObj.Length)
                $T.DeltaOut = $false
            }

            If($Stream.DataAvailable){
                $InObj = ""
                While($Stream.DataAvailable){
                    $InCount = $Stream.Read($Buff, 0, 1024)
                    $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                }
                Try{
                    If($InObj -match "A" -and $InObj -match "Z"){
                        ForEach($Line in ($InObj -replace "^.*?A" -replace "Z.*").Split("L")){
                            If(!$T.FlattenedLines.Contains($Line)){
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
                            }
                        }
                    }
                }Catch{
                    $InObj | Out-File C:\Temp\Badcli.txt
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
