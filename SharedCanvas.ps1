$Remote = ""

$lol = $false

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::VisualStyleState = [System.Windows.Forms.VisualStyles.VisualStyleState]::NoneEnabled

$Script:LastPos = [System.Drawing.Point]::new(0,0)
$Script:CurrPos = [System.Drawing.Point]::new(0,0)
$Script:Points = [System.Drawing.Point[]]@()
$Script:Pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black)

$Script:HashTable = [HashTable]::Synchronized(@{})
$Script:HashTable.Lines = [System.Collections.ArrayList]::new()
$Script:HashTable.FlattenedLines = [System.Collections.ArrayList]::new()
$Script:HashTable.Disposed = $false
$Script:HashTable.DeltaIn = $false
$Script:HashTable.DeltaOut = $false
$Script:HashTable.Drawing = $false
$Script:HashTable.Clear = $false
$Script:HashTable.Remote = $Remote
$Script:HashTable.BlankLine = @{TS=0;Pen=$Script:Pen.Clone();Pts=[System.Drawing.Point[]]@([System.Drawing.Point]::new(0,0),[System.Drawing.Point]::new(0,0))}
$Script:HashTable.FlatBlankLine = [String]("0T-16777216C1W0X0Y0X0")
[Void]$Script:HashTable.Lines.Add($Script:HashTable.BlankLine)
[Void]$Script:HashTable.FlattenedLines.Add($Script:HashTable.FlatBlankLine)

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

        $Script:Points.Clear()
    }
})
$Form.Add_MouseMove({
    If($Script:Hashtable.Drawing){
        #Sleep -Milliseconds 10
        
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
            $Script:HashTable.Lines.Add(@{TS=$TS;Pen=$Script:Pen.Clone();Pts=$Script:Points})
            $Script:HashTable.FlattenedLines.Add([String]($TS.ToString()+"T"+$Script:Pen.Color.ToArgb().ToString()+"C"+$Script:Pen.Width.ToString()+"W"+[String]::Join("Y",$(ForEach($Pt in $Script:Points){$Pt.X.ToString()+"X"+$Pt.Y.ToString()}))))
            $Script:HashTable.DeltaOut = $true
        }
    }
})
$Jraphics = $Form.CreateGraphics()

$Quit = [System.windows.Forms.Button]::new()
$Quit.Text = "Quit"
$Quit.Width = 75
$Quit.Add_Click({$This.Parent.Close()})
$Quit.BackColor = $Form.BackColor
$Quit.Parent = $Form

$Clear = [System.windows.Forms.Button]::new()
$Clear.Text = "Clear"
$Clear.Left = 75
$Clear.Width = 75
$Clear.Add_Click({
    For($i = 0; $i -lt 4; $i++){
        $Script:HashTable.Lines.Clear()
        $Script:HashTable.FlattenedLines.Clear()
        $Script:HashTable.Lines.Add($Script:HashTable.BlankLine)
        $Script:HashTable.FlattenedLines.Add($Script:HashTable.FlatBlankLine)
        $Script:HashTable.Clear = $true
        $Script:HashTable.DeltaIn = $true
        $Script:HashTable.DeltaOut = $true

        While($Script:HashTable.DeltaOut){Sleep -Milliseconds 10}
    }
})
$Clear.BackColor = $Form.BackColor
$Clear.Parent = $Form

$BGColor = [System.windows.Forms.Button]::new()
$BGColor.Text = "BGColor"
$BGColor.Left = 150
$BGColor.Width = 75
$BGColor.Add_Click({
    $ColorDialog = [System.Windows.Forms.ColorDialog]::new()
    $ColorDialog.ShowDialog()
    Try{$C = $ColorDialog.Color}Catch{}

    $This.Parent.BackColor = $C
    $Script:HashTable.BG = $C
    $Script:HashTable.Back = $true
    $Script:HashTable.DeltaIn = $true
    $Script:HashTable.DeltaOut = $true
})
$BGColor.BackColor = $Form.BackColor
$BGColor.Parent = $Form

$Refresh = [System.windows.Forms.Button]::new()
$Refresh.Text = "Refresh"
$Refresh.Left = 225
$Refresh.Width = 75
$Refresh.Add_Click({
    $Script:HashTable.DeltaIn = $true
})
$Refresh.BackColor = $Form.BackColor
$Refresh.Parent = $Form

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

$Size = [System.Windows.Forms.TrackBar]::new()
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
    $TimedOut = $false

    While(!$T.Disposed){
        If(!$T.Clear){
            $Entered = $false
            Try{
                [System.Threading.Monitor]::Enter($T)
                $Entered = $true
                $SortFlat = @($T.FlattenedLines | Sort {[int64]$_.Split("T")[0]})
                If($T.DeltaIn -or (![System.Linq.Enumerable]::SequenceEqual($T.FlattenedLines, $SortFlat) -and $SortFlat.Count -eq $T.FlattenedLines.Count)){
                    Try{
                        $SortLines = @($T.Lines | Sort {$_.TS})
                        $T.FlattenedLines.Clear()
                        $T.FlattenedLines.AddRange($SortFlat)
                        $T.Lines.Clear()
                        $T.Lines.AddRange($SortLines)
                    }Catch{
                        [Console]::WriteLine($Error[0])
                    }

                    $T.DeltaIn = $true
                }
            }Catch{}Finally{
                [System.Threading.Monitor]::Exit($T)
            }
        
            If($T.DeltaIn -or $T.Drawing){$TimedOut = $false}
            If($Entered -and ($T.DeltaIn -or $Timeout -ge 300 -and !$T.Drawing -and !$TimedOut)){
                $Timeout = 0
                $TimedOut = $true
            
                Try{If($F.Value.BackColor -ne $T.BG){$F.Value.BackColor = $T.BG}}Catch{}

                $F.Value.Refresh()
                ForEach($Line in $T.Lines){
                    $J.Value.DrawLines($Line.Pen, $Line.Pts)
                }
                $T.DeltaIn = $false
            }

            $Timeout++
        }

        Sleep -Milliseconds 10
    }
})
[Void]$SortAndDrawInPosh.AddParameter('F',[ref]$Form)
[Void]$SortAndDrawInPosh.AddParameter('J',[ref]$Jraphics)
[Void]$SortAndDrawInPosh.AddParameter('T',$Script:HashTable)
$SortAndDrawInJob=$SortAndDrawInPosh.BeginInvoke()

$CommsPosh = [Powershell]::Create()
$CommsPosh.RunspacePool = $Runspace
[Void]$CommsPosh.AddScript({
    param($T)

    $Streams = @()
    If(!$T.Remote){
        $Srv = [System.Net.Sockets.TcpListener]::new("0.0.0.0", 42069)
        Try{$Srv.Start()}Catch{[Console]::WriteLine($Error[0])}
    }Else{
        Try{
            $Client = [System.Net.Sockets.TcpClient]::New($T.Remote, 42069)
            $Stream = $Client.GetStream()
            $Streams+=$Stream
        }Catch{}
    }

    $Buff = [Byte[]]::new(1024)
    While(!$T.Disposed){
        If(!$T.Remote -and $Srv.Pending()){$Streams+=$Srv.AcceptTcpClientAsync().Result.GetStream()}

        $Back = $false
        $Clear = $false
        ForEach($Stream in $Streams){
            If($Stream.DataAvailable){
                $InObj = ""
                While($Stream.DataAvailable){
                    $InCount = $Stream.Read($Buff, 0, 1024)
                    $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                }

                If($Clear -or $T.Clear){
                    $InObj=""
                    $Clear = $true

                    ForEach($X in $Streams){While($X.DataAvailable){[Void]$X.Read($Buff, 0, 1024)}}

                    $T.Clear = $true
                    $T.Lines.Clear()
                    $T.FlattenedLines.Clear()
                    $T.Lines.Add($T.BlankLine)
                    $T.FlattenedLines.Add($T.FlatBlankLine)
                    
                    $T.DeltaIn = $true
                    If(!$T.Remote){$T.DeltaOut = $true}
                }

                Try{
                    If($InObj -match "A" -and $InObj -match "Z" -and !$Clear -and !$T.Clear){
                        ForEach($Line in ($InObj -replace "^.*?A" -replace "Z.*").Split("L")){
                            If(!$T.FlattenedLines.Contains($Line) -and $Line -ne "EMPTY" -and $Line -notmatch "^BACK"){
                                $T.FlattenedLines.Add($Line)
                                
                                $T.Lines.Add(@{
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
                                })

                                $T.DeltaIn = $true
                            }ElseIf($Line -eq "EMPTY"){
                                $Clear = $true
                            }ElseIf($Line -match "^BACK"){
                                $Back = $true
                                $BG = [System.Drawing.Color]::FromArgb([int]$Line.Replace("BACK",""))
                            }
                        }
                    }
                }Catch{
                    $InObj | Out-File C:\Temp\BadLineIn.txt
                    $Error[0] | Out-String | Out-file -Append C:\Temp\asyncErr.txt
                }
            }
        }

        If($Clear){
            ForEach($X in $Streams){While($X.DataAvailable){[Void]$X.Read($Buff, 0, 1024)}}

            $T.Clear = $true
            $T.Lines.Clear()
            $T.FlattenedLines.Clear()
            $T.Lines.Add($T.BlankLine)
            $T.FlattenedLines.Add($T.FlatBlankLine)

            $T.DeltaIn = $true
            If(!$T.Remote){$T.DeltaOut = $true}
        }ElseIf($Back){
            $T.BG = $BG
            $T.Back = $true

            $T.DeltaIn = $true
            If(!$T.Remote){$T.DeltaOut = $true}
        }ElseIf(!$T.Remote -and !$T.DeltaOut){
            $T.DeltaOut = $T.DeltaIn
        }

        $OutObj = "A"+[String]::Join("L", $T.FlattenedLines.ToArray())+"Z"
        If($T.Clear){$OutObj = "AEMPTYZ"}
        If($T.Back){$OutObj = "ABACK$($T.BG.ToArgb().ToString())Z"}
        $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
        If($T.DeltaOut){
            ForEach($Stream in $Streams){
                $Stream.Write($OutObj, 0, $OutObj.Length)
            }
        }

        $T.Back = $false
        $T.Clear = $false
        $T.DeltaOut = $false

        Sleep -Milliseconds 50
    }

    ForEach($Stream in $Streams){$Stream.Close;$Stream.Dispose()}
    $Srv.Stop()
})
[Void]$CommsPosh.AddParameter('T',$Script:HashTable)
$CommsJob=$CommsPosh.BeginInvoke()

$Form.ShowDialog()
$Form.Dispose()

$Script:HashTable.Disposed = $true

[Void]$SortAndDrawInPosh.EndInvoke($SortAndDrawInJob)
[Void]$CommsPosh.EndInvoke($CommsJob)
$Runspace.Close()
