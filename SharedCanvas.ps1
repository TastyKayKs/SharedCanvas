$Server = ""

$lol = $false

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::VisualStyleState = [System.Windows.Forms.VisualStyles.VisualStyleState]::NoneEnabled

$Script:HashTable = [HashTable]::Synchronized(@{})
$Script:HashTable.Lines = @()
$Script:HashTable.FlattenedLines = [String[]]@()
$Script:HashTable.Disposed = $false
$Script:HashTable.DeltaIn = $false
$Script:HashTable.DeltaOut = $false
$Script:HashTable.Drawing = $false
$Script:HashTable.Clear = $false

$Script:LastPos = [System.Drawing.Point]::new(0,0)
$Script:CurrPos = [System.Drawing.Point]::new(0,0)
$Script:Points = [System.Drawing.Point[]]@()
$Script:Pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black)

$CPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
If($CPUs -lt 2){$CPUs = 2} #Lol, trash computers
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
    $Form.TopMost = $false
    $Form.TopMost = $true
    $Form.Hide()
}
$Form.Add_MouseDown({
    If($_.Button -eq [System.Windows.Forms.MouseButtons]::Left){
        $Script:HashTable.Drawing = $true
        $Script:LastPos = $Form.PointToClient([System.Windows.Forms.Cursor]::Position)

        $Script:Pen.Color = $Color.BackColor
        $Script:Pen.Width = $Size.Value

        $Script:Points = [System.Drawing.Point[]]@()
    }
})
$Form.Add_MouseMove({
    If($Script:Hashtable.Drawing){
        Sleep -Milliseconds 10
        
        $Script:CurrPos = $Form.PointToClient([System.Windows.Forms.Cursor]::Position)
        If($Script:CurrPos.X -ne $Script:LastPos.X -or $Script:CurrPos.Y -ne $Script:LastPos.Y){
            $Jraphics.DrawLine($Script:Pen, $Script:LastPos.X, $Script:LastPos.Y, $Script:CurrPos.X, $Script:CurrPos.Y)
            $Script:Points+=($Script:LastPos)
            $Script:Points+=($Script:CurrPos)
        }
        
        $Script:LastPos = $Form.PointToClient([System.Windows.Forms.Cursor]::Position)
    }
})
$Form.Add_MouseUp({
    If($_.Button -eq [System.Windows.Forms.MouseButtons]::Left){
        $Script:HashTable.Drawing = $false
        If($Script:Points.Count -gt 2){
            $TS = [datetime]::Now.ToFileTimeUtc()
            $Script:HashTable.Lines+=@{TS=$TS;Pen=$Script:Pen.Clone();Pts=$Script:Points}
            $Script:HashTable.FlattenedLines+=[String]($TS.ToString()+"T"+$Script:Pen.Color.ToArgb().ToString()+"C"+$Script:Pen.Width.ToString()+"W"+[String]::Join("Y",$(ForEach($Pt in $Script:Points){$Pt.X.ToString()+"X"+$Pt.Y.ToString()})))
            $Script:HashTable.FlattenedLines = [String[]]$Script:HashTable.FlattenedLines
            $Script:HashTable.DeltaOut = $true
        }
    }
})
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
    $Script:HashTable.Lines = @()
    $Script:HashTable.FlattenedLines = [String[]]@()
    $Script:HashTable.Clear = $true
    $Script:HashTable.DeltaOut = $true

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
    Try{$C = $ColorDialog.Color}Catch{}
    
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
$Size.Width = 60
$Size.Top = 2
$Size.Left = 675
$Size.Maximum = 100
$Size.Minimum = 1
$Size.Parent = $Form

$SortAndDrawInPosh = [Powershell]::Create()
$SortAndDrawInPosh.RunspacePool = $Runspace
[Void]$SortAndDrawInPosh.AddScript({
    param($F,$J,$T)

    $Timeout = 0

    While(!$T.Disposed){
        Try{
            $Sort = [String[]]@($T.FlattenedLines | Sort {[int64]$_.Split(",")[0]})
            If($Sort.Count -eq $T.Lines.Count -and ![System.Linq.Enumerable]::SequenceEqual($T.FlattenedLines, $Sort)){
                $T.FlattenedLines = $Sort
                $T.Lines = ($T.Lines | Sort {$_.TS})
            }
        }Catch{}
        
        If($T.DeltaIn -or $Timeout -ge 300 -and !$T.Drawing){
            $Timeout = 0
            
            $F.Value.Refresh()
            ForEach($Line in $T.Lines){
                $J.Value.DrawLines($Line.Pen, $Line.Pts)
            }
            $T.DeltaIn = $false
        }
        Sleep -Milliseconds 10

        $Timeout++
    }
})
[Void]$SortAndDrawInPosh.AddParameter('F',[ref]$Form)
[Void]$SortAndDrawInPosh.AddParameter('J',[ref]$Jraphics)
[Void]$SortAndDrawInPosh.AddParameter('T',$Script:HashTable)
$SortAndDrawInJob=$SortAndDrawInPosh.BeginInvoke()

$CommsPosh = [Powershell]::Create()
$CommsPosh.RunspacePool = $Runspace
[Void]$CommsPosh.AddScript({
    param($T,$S)

    If(!$S){
        $Srv = [System.Net.Sockets.TcpListener]::new("0.0.0.0", 42069)
        Try{$Srv.Start()}Catch{[Console]::WriteLine($Error[0])}

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
                $T.DeltaOut = $true
                $T.Clear = $true
            }Else{
                If(!$T.DeltaIn){
                    $T.DeltaOut = $false
                }Else{
                    $T.DeltaOut = $true
                }
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
[Void]$CommsPosh.AddParameter('T',$Script:HashTable)
[Void]$CommsPosh.AddParameter('S',$Server)
$CommsJob=$CommsPosh.BeginInvoke()

$Form.ShowDialog()
$Form.Dispose()

$Script:HashTable.Disposed = $true

[Void]$SortAndDrawInPosh.EndInvoke($SortAndDrawInJob)
[Void]$CommsPosh.EndInvoke($CommsJob)
$Runspace.Close()
